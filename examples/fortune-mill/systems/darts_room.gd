class_name DartsRoom
extends RefCounted
## 飞镖房 model(命运转盘,纯数据,不挂节点树)。手动 throw(aim,power) → 扇形多镖各自扎盘 →
## 按扇区倍率×径向加成产 gold;升级经共享 KitModifiers;自动投(AI)走期望值保在线=离线;
## 攒够 BRIBE_COST 贿赂守卫 Verminous 过关。转盘几何/结算数学在 FortuneWheelLayout(纯静态)。

const DART_BASE := 1.0             ## 单镖基础 gold(未加成)
const BRIBE_COST := 1_000_000.0    ## 贿赂 Verminous 门槛
const WHEEL_SPEED := 45.0          ## 转盘角速度(°/秒);model 自持相位,view 只读渲染

var wheel_angle: float = 0.0       ## 当前转盘相位(°);update(dt) 推进,throw 读它定命中扇区
var _currency: Currency
var _modifiers: KitModifiers
var _registry: KitDataRegistry
var _levels: Dictionary = {}       # StringName(id) -> int(level)
var _cleared: bool = false
var _rng := RandomNumberGenerator.new()


func _init(currency: Currency, modifiers: KitModifiers, registry: KitDataRegistry) -> void:
	_currency = currency
	_modifiers = modifiers
	_registry = registry
	_rng.randomize()


func seed_rng(s: int) -> void:
	_rng.seed = s


func level_of(id: StringName) -> int:
	return int(_levels.get(id, 0))


func cost_of(id: StringName) -> float:
	var def = _registry.get_def(&"dart_upgrade", id)
	if def == null:
		return INF
	return float(def.base_cost) * pow(float(def.growth), level_of(id))


## 墙面静态,无旋转:update 为 no-op(保留供 autoload ticker 调用,wheel_angle 恒 0)。
## 命中档只由发射角(aim)决定,throw 里 wheel_angle 项恒为 0 → 落点确定。
func update(_dt: float) -> void:
	pass


## 手动投:方向 aim(0..1) + 力度 power(0..1)。扇形多镖各以不同角偏移扎盘,各自结算。
## 返回 {gold, darts, hits:[{seg,mult,r,gold,vermin}]}。
func throw(aim: float, power: float) -> Dictionary:
	var darts := maxi(1, int(_modifiers.value_for(&"darts_per_throw", 1.0)))
	var per_dart := _modifiers.value_for(&"gold_per_dart", DART_BASE)
	var win_bonus := _modifiers.value_for(&"win_zone", 0.0)
	var gmul := _modifiers.value_for(&"global_mul", 1.0)
	var land := FortuneWheelLayout.landing(aim, power)
	var r := float(land["r"])
	var rb := FortuneWheelLayout.radial_bonus(r)
	var fans := FortuneWheelLayout.fan_offsets(darts)
	var total := 0.0
	var hits: Array = []
	for i in darts:
		var hit_angle: float = wheel_angle + float(land["a_off"]) + float(fans[i])
		var seg := FortuneWheelLayout.segment_at(hit_angle, win_bonus)
		var pay: float = per_dart * float(seg["mult"]) * rb * gmul
		total += pay
		hits.append({"seg": seg["name"], "mult": float(seg["mult"]), "r": r, "gold": pay, "vermin": bool(seg["vermin"])})
	_currency.add(total)
	return {"gold": total, "darts": darts, "hits": hits}


## 自动产出期望 gold/秒(确定性):throws/s × 多镖 × 单镖聚合值 × AI 期望倍率(含平均径向) × global_mul。
## throws_per_sec 基值 0,买 hire_ai 才 >0;在线 produce 与离线结算同用此率(在线=离线)。
func auto_gold_rate() -> float:
	var tps := _modifiers.value_for(&"throws_per_sec", 0.0)
	if tps <= 0.0:
		return 0.0
	var darts := maxi(1, int(_modifiers.value_for(&"darts_per_throw", 1.0)))
	var per_dart := _modifiers.value_for(&"gold_per_dart", DART_BASE)
	var ai_skill := _modifiers.value_for(&"ai_skill", 0.0)
	var gmul := _modifiers.value_for(&"global_mul", 1.0)
	return tps * float(darts) * per_dart * FortuneWheelLayout.expected_mult(ai_skill) * gmul


func produce(dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	var g := auto_gold_rate() * dt
	if g <= 0.0:
		return 0.0
	_currency.add(g)
	return g


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


## 把某升级在 level 的效果落到 modifier。automation(hire_ai)特判:一条驱动 throws_per_sec + ai_skill。
func _apply_upgrade(def, level: int) -> void:
	if def.kind == &"automation":
		# cadence:每级 +effect;ai_skill:L1=0(随机)逐级升到 ~1(稳准)
		_modifiers.set_modifier(&"throws_per_sec", def.id, &"add", float(def.effect_per_level) * level)
		_modifiers.set_modifier(&"ai_skill", def.id, &"add", clampf(float(level - 1) * 0.12, 0.0, 1.0))
		return
	var v := 0.0
	if def.op == &"add":
		v = float(def.effect_per_level) * level
	else:  # mul:每级 ×(1+effect)
		v = pow(1.0 + float(def.effect_per_level), level)
	_modifiers.set_modifier(def.target, def.id, def.op, v)


func bribe_threshold() -> float:
	return BRIBE_COST * _modifiers.value_for(&"bribe_cost_mul", 1.0)


func can_bribe() -> bool:
	return _currency.get_amount() >= bribe_threshold()


func bribe() -> bool:
	if not can_bribe():
		return false
	_cleared = true
	return true


func is_cleared() -> bool:
	return _cleared


## 只存权威状态(levels/cleared);modifier 是派生值,from_dict 重算。
func to_dict() -> Dictionary:
	var lv := {}
	for id in _levels:
		lv[String(id)] = int(_levels[id])
	return {"levels": lv, "cleared": _cleared}


func from_dict(d: Dictionary) -> void:
	# 先摘除本 room 此前已施加的所有 modifier(派生态从零重算,不叠加残留)
	for old_id in _levels:
		_clear_upgrade_modifiers(old_id)
	_levels.clear()
	_cleared = bool(d.get("cleared", false))
	var lv: Dictionary = d.get("levels", {})
	for k in lv:
		var id := StringName(k)
		var level := int(lv[k])
		_levels[id] = level
		var def = _registry.get_def(&"dart_upgrade", id)
		if def != null:
			_apply_upgrade(def, level)


## 摘除某升级施加的 modifier 源(automation 占两个 target)。
func _clear_upgrade_modifiers(id: StringName) -> void:
	var def = _registry.get_def(&"dart_upgrade", id)
	if def == null:
		return
	if def.kind == &"automation":
		_modifiers.remove_source(&"throws_per_sec", id)
		_modifiers.remove_source(&"ai_skill", id)
	else:
		_modifiers.remove_source(def.target, id)
