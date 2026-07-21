class_name GachaRoom
extends RefCounted
## 扭蛋房 model(纯数据,不挂节点树)。投币抽扭蛋 → 按稀有度加权得道具(进 KitInventory 收藏柜)+ stuffing;
## 升级经 KitModifiers 聚合;攒够 BRIBE_COST 贿赂守卫 Executor 过关。
##
## 三处机制:
## ① 手动抽卡(pull):加权 RNG 抽一个道具 → grant_item 收藏 + 挂被动协同 + 产 stuffing。
## ② 自动抽卡(automation/离线):auto_stuffing_rate() 连续期望率(不收集离散道具,保在线=离线)。
## ③ 被动收集协同(GACHA 型,第 4 类协同——唯一「收集向」):持有道具 → 往各房 target 挂**永久** add/mul
##    (源 gacha_<id>),持有越多越强。经共享 KitModifiers 唯一求值点即时生效于别房(含 global_mul);
##    收藏柜 _vault(KitInventory)是权威态(存档),from_dict 按持有数重放被动层。

const GLOBAL_MUL := &"global_mul"    ## 跨房协同求值 target(全房间共读)
const BRIBE_COST := 1_000_000.0      ## 贿赂 Executor 门槛
const VAULT_SLOTS := 16              ## 收藏柜格数
const VAULT_STACK := 1_000_000       ## 单格堆叠上限(设大 → 每种道具占 1 格,count 仍跨格求和)
const PULL_BASE_RATE := 1.0          ## 每台自动抽卡机基准 抽/秒(× pull_speed)

var _stuffing: Currency
var _modifiers: KitModifiers
var _registry: KitDataRegistry
var _vault: KitInventory              ## 道具收藏柜(dogfood)
var _levels: Dictionary = {}          # StringName(升级 id) -> int(level)
var _rarity_level: int = 0            # 稀有度权重 unlock 档(抬高 rare/epic 权重)
var _cleared: bool = false
var _rng := RandomNumberGenerator.new()


func _init(stuffing: Currency, modifiers: KitModifiers, registry: KitDataRegistry) -> void:
	_stuffing = stuffing
	_modifiers = modifiers
	_registry = registry
	_vault = KitInventory.new(VAULT_SLOTS, VAULT_STACK)
	_rng.randomize()


func seed_rng(s: int) -> void:
	_rng.seed = s


# --- 通用查询 ---

func item_ids() -> Array:
	return _registry.ids(&"gacha_item", true)


func upgrade_ids() -> Array:
	return _registry.ids(&"gacha_upgrade", true)


func vault() -> KitInventory:
	return _vault


func owned(id: StringName) -> int:
	return _vault.count(id)


func level_of(id: StringName) -> int:
	return int(_levels.get(id, 0))


func cost_of(id: StringName) -> float:
	var def = _registry.get_def(&"gacha_upgrade", id)
	if def == null:
		return INF
	return float(def.base_cost) * pow(float(def.growth), level_of(id))


func rarity_level() -> int:
	return _rarity_level


# --- 加权抽取 ---

## 单个道具当前权重:rare/epic 随稀有度权重升级抬高(镜像 lotto 的 jackpot 权重)。
func _item_weight(def) -> float:
	var w := float(def.weight)
	if def.rarity != &"common":
		w *= (1.0 + 0.5 * float(_rarity_level))
	return w


## 返回 [{def, w}](按当前稀有度档的权重)。
func _weighted_defs() -> Array:
	var out: Array = []
	for id in item_ids():
		var def = _registry.get_def(&"gacha_item", id)
		if def != null:
			out.append({"def": def, "w": _item_weight(def)})
	return out


func _roll_item() -> StringName:
	var wd := _weighted_defs()
	if wd.is_empty():
		return &""
	var sum := 0.0
	for e in wd:
		sum += float(e["w"])
	var pick := _rng.randf() * sum
	var acc := 0.0
	for e in wd:
		acc += float(e["w"])
		if pick <= acc:
			return e["def"].id
	return wd[wd.size() - 1]["def"].id


# --- 手动抽卡(RNG;收集离散道具 → 被动协同) ---

## 抽一次:加权抽道具 → grant_item 收藏 + 挂被动 + 产 stuffing。
## 返回 {stuffing, item, rarity, owned}。
func pull() -> Dictionary:
	var id := _roll_item()
	if String(id).is_empty():
		return {"stuffing": 0.0, "item": &"", "rarity": &"", "owned": 0}
	var def = _registry.get_def(&"gacha_item", id)
	grant_item(id, 1)
	var st := _modifiers.value_for(&"stuffing_per_pull", 1.0) * float(def.stuffing_value) * _modifiers.value_for(GLOBAL_MUL, 1.0)
	_stuffing.add(st)
	return {"stuffing": st, "item": id, "rarity": def.rarity, "owned": owned(id)}


## 收集 n 份道具进收藏柜 + 按新持有数重挂被动协同层(不产 stuffing)。
## pull 与测试共用的确定性入口(道具是收集向,收集 = 加被动 modifier)。
func grant_item(id: StringName, n: int) -> void:
	var def = _registry.get_def(&"gacha_item", id)
	if def == null or n <= 0:
		return
	_vault.add(id, n)
	_apply_item(def)


## 持有道具 → 被动 modifier(源 gacha_<id>):add=value×count / mul=(1+value)^count。覆盖式(随持有数重算)。
func _apply_item(def) -> void:
	var n := _vault.count(def.id)
	if n <= 0:
		return
	var v := 0.0
	if def.op == &"add":
		v = float(def.value_per_copy) * n
	else:  # mul:每份 ×(1+value)
		v = pow(1.0 + float(def.value_per_copy), n)
	_modifiers.set_modifier(def.target, _item_source(def.id), def.op, v)


func _item_source(item_id: StringName) -> StringName:
	return StringName("gacha_" + String(item_id))


# --- 自动抽卡(连续期望率;不收集离散道具,保在线=离线) ---

## 单抽期望 stuffing = Σ(w_i × stuffing_value_i)/Σw × stuffing_per_pull 聚合。
func _expected_stuffing() -> float:
	var wd := _weighted_defs()
	if wd.is_empty():
		return 0.0
	var sum := 0.0
	var wsum := 0.0
	for e in wd:
		var w := float(e["w"])
		wsum += w
		sum += w * float(e["def"].stuffing_value)
	if wsum <= 0.0:
		return 0.0
	return (sum / wsum) * _modifiers.value_for(&"stuffing_per_pull", 1.0)


## 自动抽卡期望 stuffing/秒 = pullers × PULL_BASE_RATE × pull_speed × 期望单抽 × global_mul。
## auto_puller 基 0,买自动抽卡机才 >0。用期望率,不收集离散道具(保在线=离线,同其余房 auto 先例)。
func auto_stuffing_rate() -> float:
	var pullers := _modifiers.value_for(&"auto_puller", 0.0)
	if pullers <= 0.0:
		return 0.0
	var speed := _modifiers.value_for(&"pull_speed", 1.0)
	var gmul := _modifiers.value_for(GLOBAL_MUL, 1.0)
	return pullers * PULL_BASE_RATE * speed * _expected_stuffing() * gmul


func produce(dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	var s := auto_stuffing_rate() * dt
	if s <= 0.0:
		return 0.0
	_stuffing.add(s)
	return s


# --- 升级 ---

func buy_upgrade(id: StringName) -> bool:
	var def = _registry.get_def(&"gacha_upgrade", id)
	if def == null:
		return false
	var lvl := level_of(id)
	if def.max_level >= 0 and lvl >= def.max_level:
		return false
	if not _stuffing.spend(cost_of(id)):
		return false
	_levels[id] = lvl + 1
	_apply_upgrade(def, lvl + 1)
	return true


## 升级效果落 modifier(unlock 类改稀有度权重档,不落 modifier)。覆盖式(同 source_id)。
func _apply_upgrade(def, level: int) -> void:
	if def.kind == &"unlock":
		_rarity_level = level
		return
	var v := 0.0
	if def.op == &"add":
		v = float(def.effect_per_level) * level
	else:  # mul:每级 ×(1+effect)
		v = pow(1.0 + float(def.effect_per_level), level)
	_modifiers.set_modifier(def.target, def.id, def.op, v)


## 当前贿赂门槛 = 基础 1M × NG+ 门槛缩放(共享 bribe_cost_mul,prestige 挂 ng_threshold 源)。ng0 → ×1.0(向后兼容)。
func bribe_threshold() -> float:
	return BRIBE_COST * _modifiers.value_for(&"bribe_cost_mul", 1.0)


func can_bribe() -> bool:
	return _stuffing.get_amount() >= bribe_threshold()


func bribe() -> bool:
	if not can_bribe():
		return false
	_cleared = true
	return true


func is_cleared() -> bool:
	return _cleared


# --- 存档(只存权威态:levels/cleared/vault;派生态 rarity_level/升级 modifier/道具被动层 from_dict 重算) ---

func to_dict() -> Dictionary:
	var lv := {}
	for id in _levels:
		lv[String(id)] = int(_levels[id])
	return {
		"levels": lv,
		"cleared": _cleared,
		"vault": _vault.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	# 摘除本 room 此前施加的升级 modifier + 所有道具被动层,派生态从零重算不叠残留。
	for old_id in _levels:
		var od = _registry.get_def(&"gacha_upgrade", old_id)
		if od != null and od.kind != &"unlock":
			_modifiers.remove_source(od.target, old_id)
	for iid in item_ids():
		var idef = _registry.get_def(&"gacha_item", iid)
		if idef != null:
			_modifiers.remove_source(idef.target, _item_source(iid))
	_levels.clear()
	_rarity_level = 0
	_cleared = bool(d.get("cleared", false))
	# 升级(unlock 类重建 rarity_level)
	var lv: Dictionary = d.get("levels", {})
	for k in lv:
		var id := StringName(k)
		var level := int(lv[k])
		_levels[id] = level
		var def = _registry.get_def(&"gacha_upgrade", id)
		if def != null:
			_apply_upgrade(def, level)
	# 收藏柜:先重建空柜(from_dict({}) = 完全重置,清掉旧库存,避免 NG+/Lethal 重置时叠加),有存档再载入
	_vault = KitInventory.new(VAULT_SLOTS, VAULT_STACK)
	if d.has("vault"):
		_vault.from_dict(d["vault"])
	for iid in item_ids():
		var idef = _registry.get_def(&"gacha_item", iid)
		if idef != null and _vault.count(iid) > 0:
			_apply_item(idef)
