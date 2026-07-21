class_name DartsRoom
extends RefCounted
## 飞镖房 model(纯数据,不挂节点树)。手动投镖 → 命中靶心档 → 按倍率产 gold;
## 升级经 KitModifiers 聚合;攒够 BRIBE_COST 贿赂守卫 Verminous 过关。

## 靶心 17 档倍率(spec §5.1,照抄,勿改):red..Supernova。
const BULLSEYE := [1.5, 2.0, 3.0, 5.0, 8.0, 12.0, 20.0, 30.0, 50.0, 80.0, 125.0, 200.0, 300.0, 500.0, 800.0, 1200.0, 2500.0]
const DART_BASE := 1.0            ## 单镖基础 gold(未加成)
const BRIBE_COST := 1_000_000.0   ## 贿赂 Verminous 门槛

var _currency: Currency
var _modifiers: KitModifiers
var _registry: KitDataRegistry
var _levels: Dictionary = {}      # StringName(id) -> int(level)
var _bullseye_unlock: int = 0     # 已解锁的额外靶心档数(0 = 只有 tier1 red)
var _cleared: bool = false
var _rng := RandomNumberGenerator.new()


func _init(currency: Currency, modifiers: KitModifiers, registry: KitDataRegistry) -> void:
	_currency = currency
	_modifiers = modifiers
	_registry = registry
	_rng.randomize()


func seed_rng(s: int) -> void:
	_rng.seed = s


## 当前可命中的最高靶心档(1-based,含)。初始 1(仅 red),每级 unlock +1,封顶 17。
func max_tier() -> int:
	return clampi(1 + _bullseye_unlock, 1, BULLSEYE.size())


func level_of(id: StringName) -> int:
	return int(_levels.get(id, 0))


## 下一级成本 = base_cost × growth^当前level。
func cost_of(id: StringName) -> float:
	var def = _registry.get_def(&"dart_upgrade", id)
	if def == null:
		return INF
	return float(def.base_cost) * pow(float(def.growth), level_of(id))


## 投一次(含多镖)。每镖:gold_per_dart 聚合值 × 命中靶心倍率。返回 {gold, darts}。
func throw() -> Dictionary:
	var darts := maxi(1, int(_modifiers.value_for(&"darts_per_throw", 1.0)))
	var per_dart := _modifiers.value_for(&"gold_per_dart", DART_BASE)
	var total := 0.0
	for _i in darts:
		total += per_dart * BULLSEYE[_roll_tier() - 1]
	_currency.add(total)
	return {"gold": total, "darts": darts}


## 加权随机命中档(1..max_tier);低档常见、高档稀有(权重 1/tier^2)。
func _roll_tier() -> int:
	var top := max_tier()
	if top <= 1:
		return 1
	var weights := []
	var sum := 0.0
	for tier in range(1, top + 1):
		var w := 1.0 / float(tier * tier)
		weights.append(w)
		sum += w
	var pick := _rng.randf() * sum
	var acc := 0.0
	for i in range(weights.size()):
		acc += weights[i]
		if pick <= acc:
			return i + 1
	return top


## 买一级升级。买不起 / 已满级 / 无此 def → false。
func buy_upgrade(id: StringName) -> bool:
	var def = _registry.get_def(&"dart_upgrade", id)
	if def == null:
		return false
	var lvl := level_of(id)
	if def.max_level >= 0 and lvl >= def.max_level:
		return false
	if not _currency.spend(cost_of(id)):
		return false
	_levels[id] = lvl + 1
	_apply_upgrade(def, lvl + 1)
	return true


## 把某升级在 level 时的效果落到 modifier(unlock 类改解锁档数)。覆盖式(同 source_id)。
func _apply_upgrade(def, level: int) -> void:
	if def.kind == &"unlock":
		_bullseye_unlock = level
		return
	var v := 0.0
	if def.op == &"add":
		v = float(def.effect_per_level) * level
	else:  # mul:每级 ×(1+effect)
		v = pow(1.0 + float(def.effect_per_level), level)
	_modifiers.set_modifier(def.target, def.id, def.op, v)


func can_bribe() -> bool:
	return _currency.get_amount() >= BRIBE_COST


## 达门槛则过关(P0 不扣货币,过关即本切片终点)。
func bribe() -> bool:
	if not can_bribe():
		return false
	_cleared = true
	return true


func is_cleared() -> bool:
	return _cleared


## 只存权威状态(levels/cleared);modifier 与 bullseye_unlock 是派生值,from_dict 重算。
func to_dict() -> Dictionary:
	var lv := {}
	for id in _levels:
		lv[String(id)] = int(_levels[id])   # JSON key 统一 String
	return {"levels": lv, "cleared": _cleared}


func from_dict(d: Dictionary) -> void:
	# 先摘除本 room 此前已施加的所有 modifier(派生态从零重算,不叠加残留)
	for old_id in _levels:
		var old_def = _registry.get_def(&"dart_upgrade", old_id)
		if old_def != null and old_def.kind != &"unlock":
			_modifiers.remove_source(old_def.target, old_id)
	_levels.clear()
	_bullseye_unlock = 0
	_cleared = bool(d.get("cleared", false))
	var lv: Dictionary = d.get("levels", {})
	for k in lv:
		var id := StringName(k)
		var level := int(lv[k])
		_levels[id] = level
		var def = _registry.get_def(&"dart_upgrade", id)
		if def != null:
			_apply_upgrade(def, level)
