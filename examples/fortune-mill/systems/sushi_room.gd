class_name SushiRoom
extends RefCounted
## 寿司房 model(纯数据,不挂节点树)。选配方 → 等制作时长 → 出寿司得 ribbons;升级经 KitModifiers;
## 攒够 BRIBE_COST 贿赂守卫 Hivemind 过关。
##
## 三处机制:
## ① 制作时长(手动):select_recipe → start_craft(消耗食材)→ update(dt) 计时 → 完成 award。
##    食材柜是真 KitInventory dogfood(add/remove/count/has);制作时长受 craft_speed 缩短。
## ② 自动厨师(自动化/离线):auto_ribbon_rate() 连续期望率(不走离散食材/制作),保在线=离线。
## ③ 解锁式开关协同(SUSHI 型,三类协同唯一「规则开关」):解锁带 switch 的高级配方 → 往**别房**
##    target 注册一条永久 modifier(源 sushi_<id>),如 throws_per_sec ×2「飞镖自动投速翻倍」。
##    经共享 KitModifiers 唯一求值点即时生效于别房;_unlocked 是权威态(存档),from_dict 重放开关。

const GLOBAL_MUL := &"global_mul"    ## 跨房协同求值 target(全房间共读)
const BRIBE_COST := 1_000_000.0      ## 贿赂 Hivemind 门槛
const PANTRY_SLOTS := 12             ## 食材柜格数

var _ribbons: Currency
var _modifiers: KitModifiers
var _registry: KitDataRegistry
var _pantry: KitInventory            ## 食材容器(dogfood)
var _levels: Dictionary = {}         # StringName(升级 id) -> int(level)
var _unlocked: Dictionary = {}       # StringName(配方 id) -> true(权威;驱动开关协同)
var _active_recipe: StringName = &""
var _crafting: bool = false          ## 是否有一份手动制作在进行(live 态,不持久化)
var _crafting_recipe: StringName = &""
var _craft_progress: float = 0.0     ## 当前制作已累积秒(有效时长口径,受 craft_speed)
var _cleared: bool = false


func _init(ribbons: Currency, modifiers: KitModifiers, registry: KitDataRegistry) -> void:
	_ribbons = ribbons
	_modifiers = modifiers
	_registry = registry
	_pantry = KitInventory.new(PANTRY_SLOTS)
	_apply_default_unlocks()


# --- 通用查询 ---

func level_of(id: StringName) -> int:
	return int(_levels.get(id, 0))


func cost_of(id: StringName) -> float:
	var def = _registry.get_def(&"sushi_upgrade", id)
	if def == null:
		return INF
	return float(def.base_cost) * pow(float(def.growth), level_of(id))


func pantry() -> KitInventory:
	return _pantry


func ingredient_count(id: StringName) -> int:
	return _pantry.count(id)


# --- 配方 / 解锁式开关协同 ---

func recipe_ids() -> Array:
	return _registry.ids(&"sushi_recipe", true)


func is_unlocked(id: StringName) -> bool:
	return _unlocked.has(id)


func active_recipe() -> StringName:
	return _active_recipe


func unlock_cost(id: StringName) -> float:
	var def = _registry.get_def(&"sushi_recipe", id)
	return INF if def == null else float(def.unlock_cost)


func can_unlock(id: StringName) -> bool:
	var def = _registry.get_def(&"sushi_recipe", id)
	return def != null and not _unlocked.has(id) and _ribbons.get_amount() >= float(def.unlock_cost)


## 解锁配方(花 ribbons)。带 switch 的高级配方解锁 → 注册跨房永久开关。返回是否成功。
func unlock_recipe(id: StringName) -> bool:
	var def = _registry.get_def(&"sushi_recipe", id)
	if def == null or _unlocked.has(id):
		return false
	if not _ribbons.spend(float(def.unlock_cost)):
		return false
	_unlocked[id] = true
	_apply_switch(def)
	return true


## 选中要制作的配方(须已解锁)。切换会取消进行中的制作(简化;食材已扣不退)。
func select_recipe(id: StringName) -> bool:
	if not _unlocked.has(id):
		return false
	if _crafting and id != _crafting_recipe:
		_crafting = false
		_craft_progress = 0.0
	_active_recipe = id
	return true


## 把配方的 switch 效果注册到别房 target(源 sushi_<id>)。空 target = 无协同。覆盖式。
func _apply_switch(def) -> void:
	if String(def.switch_target).is_empty():
		return
	_modifiers.set_modifier(def.switch_target, _switch_source(def.id), def.switch_op, float(def.switch_value))


func _switch_source(recipe_id: StringName) -> StringName:
	return StringName("sushi_" + String(recipe_id))


# --- 制作(手动;dogfood KitInventory) ---

## 有效制作时长(秒)= craft_time / craft_speed 聚合。
func craft_time_of(id: StringName) -> float:
	var def = _registry.get_def(&"sushi_recipe", id)
	if def == null:
		return INF
	return float(def.craft_time) / craft_speed()


func craft_speed() -> float:
	return _modifiers.value_for(&"craft_speed", 1.0)


func is_crafting() -> bool:
	return _crafting


func craft_progress() -> float:
	return _craft_progress


## 当前制作目标时长(有效口径;非制作中返回 0)。
func craft_target() -> float:
	if not _crafting:
		return 0.0
	return craft_time_of(_crafting_recipe)


## 补货:往食材柜加 amount 个 id 食材(KitInventory.add)。返回没塞下的余量。
func restock(id: StringName, amount: int) -> int:
	return _pantry.add(id, amount)


## 为所有已解锁配方各备 amount 份食材(便捷备料)。
func restock_all(amount: int) -> void:
	for rid in _unlocked:
		var def = _registry.get_def(&"sushi_recipe", rid)
		if def != null and not String(def.ingredient).is_empty():
			_pantry.add(def.ingredient, amount)


## 开始制作选中配方:需已选、未在制作、食材够 → 扣食材、起计时。返回是否开工。
func start_craft() -> bool:
	if _crafting or String(_active_recipe).is_empty():
		return false
	var def = _registry.get_def(&"sushi_recipe", _active_recipe)
	if def == null:
		return false
	if not String(def.ingredient).is_empty():
		if not _pantry.has(def.ingredient, int(def.ingredient_count)):
			return false
		_pantry.remove(def.ingredient, int(def.ingredient_count))
	_crafting = true
	_crafting_recipe = _active_recipe
	_craft_progress = 0.0
	return true


## 时间推进:手动制作计时(× craft_speed),完成 → 出寿司入账。返回本次完成产出的 ribbons(0=未完成)。
func update(dt: float) -> float:
	if not _crafting or dt <= 0.0:
		return 0.0
	var def = _registry.get_def(&"sushi_recipe", _crafting_recipe)
	if def == null:
		_crafting = false
		_craft_progress = 0.0
		return 0.0
	_craft_progress += dt * craft_speed()
	if _craft_progress >= float(def.craft_time):
		_crafting = false
		_craft_progress = 0.0
		return _award_sushi(def)
	return 0.0


## 出一份寿司:ribbons_per_sushi 聚合 × 配方 ribbon_value × global_mul。返回入账 ribbons。
func _award_sushi(def) -> float:
	var per := _modifiers.value_for(&"ribbons_per_sushi", 1.0) * float(def.ribbon_value)
	var gmul := _modifiers.value_for(GLOBAL_MUL, 1.0)
	var r := per * gmul
	_ribbons.add(r)
	return r


# --- 自动厨师(连续期望产率;不走离散食材/制作,保在线=离线) ---

## 自动率基准配方:当前选中(已解锁)优先,否则取第一个已解锁配方。
func _rate_recipe():
	if not String(_active_recipe).is_empty() and _unlocked.has(_active_recipe):
		return _registry.get_def(&"sushi_recipe", _active_recipe)
	for rid in recipe_ids():
		if _unlocked.has(rid):
			return _registry.get_def(&"sushi_recipe", rid)
	return null


## 自动厨师期望 ribbons/秒(chefs × 单份价值 / 有效制作时长 × global_mul)。
## auto_chef 基 0,买 Auto Chef 才 >0。用期望率,不模拟离散制作/食材(保在线=离线)。
func auto_ribbon_rate() -> float:
	var chefs := _modifiers.value_for(&"auto_chef", 0.0)
	if chefs <= 0.0:
		return 0.0
	var def = _rate_recipe()
	if def == null:
		return 0.0
	var ct := float(def.craft_time) / craft_speed()
	if ct <= 0.0:
		return 0.0
	var per := _modifiers.value_for(&"ribbons_per_sushi", 1.0) * float(def.ribbon_value)
	var gmul := _modifiers.value_for(GLOBAL_MUL, 1.0)
	return chefs * (per / ct) * gmul


func produce(dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	var r := auto_ribbon_rate() * dt
	if r <= 0.0:
		return 0.0
	_ribbons.add(r)
	return r


# --- 升级 ---

func buy_upgrade(id: StringName) -> bool:
	var def = _registry.get_def(&"sushi_upgrade", id)
	if def == null:
		return false
	var lvl := level_of(id)
	if def.max_level >= 0 and lvl >= def.max_level:
		return false
	if not _ribbons.spend(cost_of(id)):
		return false
	_levels[id] = lvl + 1
	_apply_upgrade(def, lvl + 1)
	return true


## 升级效果落 modifier(value/speed/automation 都写 target)。覆盖式(同 source_id)。
func _apply_upgrade(def, level: int) -> void:
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
	return _ribbons.get_amount() >= bribe_threshold()


func bribe() -> bool:
	if not can_bribe():
		return false
	_cleared = true
	return true


func is_cleared() -> bool:
	return _cleared


# --- 默认解锁 ---

func _apply_default_unlocks() -> void:
	for rid in recipe_ids():
		var def = _registry.get_def(&"sushi_recipe", rid)
		if def != null and bool(def.unlocked_by_default) and not _unlocked.has(rid):
			_unlocked[rid] = true
			_apply_switch(def)   # 默认配方一般无 switch,一致处理无副作用
	if String(_active_recipe).is_empty():
		_active_recipe = _default_active()


func _default_active() -> StringName:
	for rid in recipe_ids():
		if _unlocked.has(rid):
			return rid
	return &""


## 摘除所有已解锁配方注册的跨房开关(from_dict 重算前清残留)。
func _remove_all_switches() -> void:
	for rid in _unlocked:
		var def = _registry.get_def(&"sushi_recipe", rid)
		if def != null and not String(def.switch_target).is_empty():
			_modifiers.remove_source(def.switch_target, _switch_source(rid))


# --- 存档(只存权威态;派生 modifier/开关 from_dict 重算;进行中制作是 live 态不持久化) ---

func to_dict() -> Dictionary:
	var lv := {}
	for id in _levels:
		lv[String(id)] = int(_levels[id])
	var unlocked := []
	for rid in _unlocked:
		unlocked.append(String(rid))
	return {
		"levels": lv,
		"cleared": _cleared,
		"unlocked": unlocked,
		"active": String(_active_recipe),
		"pantry": _pantry.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	# 摘除本 room 此前施加的升级 modifier + 所有配方跨房开关,派生态从零重算不叠残留。
	for old_id in _levels:
		var od = _registry.get_def(&"sushi_upgrade", old_id)
		if od != null:
			_modifiers.remove_source(od.target, old_id)
	_remove_all_switches()
	_levels.clear()
	_unlocked.clear()
	_crafting = false
	_craft_progress = 0.0
	_active_recipe = &""
	_cleared = bool(d.get("cleared", false))
	# 升级
	var lv: Dictionary = d.get("levels", {})
	for k in lv:
		var id := StringName(k)
		var level := int(lv[k])
		_levels[id] = level
		var def = _registry.get_def(&"sushi_upgrade", id)
		if def != null:
			_apply_upgrade(def, level)
	# 默认解锁 + 存档解锁(重放开关)
	_apply_default_unlocks()
	var unlocked: Array = d.get("unlocked", [])
	for rid in unlocked:
		var rname := StringName(rid)
		if not _unlocked.has(rname):
			var rdef = _registry.get_def(&"sushi_recipe", rname)
			if rdef != null:
				_unlocked[rname] = true
				_apply_switch(rdef)
	# 选中配方
	var act := StringName(d.get("active", ""))
	if not String(act).is_empty() and _unlocked.has(act):
		_active_recipe = act
	else:
		_active_recipe = _default_active()
	# 食材柜
	if d.has("pantry"):
		_pantry.from_dict(d["pantry"])
