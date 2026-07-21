class_name Prestige
extends RefCounted
## NG+ 元进度(纯数据,不挂节点树)。通关 5 房 → ascend 进下一周目:门槛 ×10、发 prestige 点。
## 保留/重置的边界(spec §5.8):
##   · 重置(调用方 FortuneMill._reset_rooms 负责):5 房货币、房间升级、守卫拦路。
##   · 保留(本类负责):ng_level、prestige 点、NG+ 专属升级(其 modifier 跨周目存活)、Lethal 最佳时间。
##     (部分稀有扭蛋道具的保留在 FortuneMill._reset_rooms 里做。)
##
## 两条 modifier 通道,都经**共享 KitModifiers**(与 5 房同一求值点):
##   ① 门槛缩放:target `bribe_cost_mul`,唯一源 `ng_threshold`(mul)= 10^ng_level;
##      各房 can_bribe() 读 BRIBE_COST × value_for(bribe_cost_mul,1.0)。ng0 → ×1.0(完全向后兼容)。
##   ② prestige 加成:每条 NG+ 升级往 def.target 挂永久源 `prestige_<id>`(跨周目不清)。
##
## Lethal Mode(可选速通):限时 + **无 NG+ 加成**——期间撤除 prestige 加成、门槛回 1M(factor 1.0),
##   计时;5 房全通关时 finish_lethal 记录最佳秒数;abort/finish 退出即恢复 prestige 加成与门槛。

const BRIBE_COST_MUL := &"bribe_cost_mul"   ## 各房 can_bribe 读此 target 缩放门槛(base 1.0)
const THRESHOLD_SOURCE := &"ng_threshold"   ## prestige 在 bribe_cost_mul 上的唯一门槛源
const THRESHOLD_STEP := 10.0                ## 每周目门槛 ×10(spec §5.8:1M → 10M → ...)
const PRESTIGE_TYPE := &"prestige_upgrade"

var _modifiers: KitModifiers
var _registry: KitDataRegistry
var _ng_level: int = 0                       # 当前周目(0 = 首周目)
var _points: float = 0.0                     # prestige 点(ascend 累积,买 NG+ 升级)
var _levels: Dictionary = {}                 # StringName(升级 id) -> int(level)
var _lethal: bool = false                    # Lethal Mode 进行中
var _lethal_elapsed: float = 0.0             # 本局 Lethal 已用秒数
var _lethal_best: float = -1.0               # 历史最佳速通秒数(-1 = 未完成过)


func _init(modifiers: KitModifiers, registry: KitDataRegistry) -> void:
	_modifiers = modifiers
	_registry = registry
	_rebuild_modifiers()   # ng0 → 门槛 factor 1.0;无 prestige 升级


# --- 查询 ---

func ng_level() -> int: return _ng_level
func points() -> float: return _points
func level_of(id: StringName) -> int: return int(_levels.get(id, 0))
func lethal_active() -> bool: return _lethal
func lethal_elapsed() -> float: return _lethal_elapsed
func lethal_best() -> float: return _lethal_best
func upgrade_ids() -> Array: return _registry.ids(PRESTIGE_TYPE, true)

## 当前门槛缩放因子(informational;Lethal 时强制 1.0)。
func threshold_factor() -> float:
	return 1.0 if _lethal else pow(THRESHOLD_STEP, _ng_level)

## 下一级成本(prestige 点)= base_cost × growth^level。
func cost_of(id: StringName) -> float:
	var def = _registry.get_def(PRESTIGE_TYPE, id)
	if def == null:
		return INF
	return float(def.base_cost) * pow(float(def.growth), level_of(id))

## ascend 奖励公式(【自定】,确定性):升 ng_level 前发 (ng_level+1) 点。
## 首次 ascend(ng0→1)发 1 点;再 ascend(ng1→2)发 2 点……越深一轮回报越高。
func ascend_reward() -> float:
	return float(_ng_level + 1)

## NG+ 专属升级是否可买:须 ng_level≥1、非 Lethal、未满级、点数够。
func can_buy(id: StringName) -> bool:
	if _ng_level < 1 or _lethal:
		return false
	var def = _registry.get_def(PRESTIGE_TYPE, id)
	if def == null:
		return false
	if def.max_level >= 0 and level_of(id) >= def.max_level:
		return false
	return _points >= cost_of(id)


# --- 进周目 / 买升级 ---

## 进下一周目:发点 + ng_level++ + 抬门槛因子。只更新 prestige 元状态,
## 5 房重置由调用方(FortuneMill.ascend → _reset_rooms)负责。返回本次数据包(空 = 拒绝)。
func ascend() -> Dictionary:
	if _lethal:
		return {}
	var reward := ascend_reward()
	_points += reward
	_ng_level += 1
	_refresh_threshold()
	return {"ng_level": _ng_level, "reward": reward, "points": _points}

## 买一级 NG+ 专属升级(花 prestige 点)。不满足 can_buy → false。
func buy_upgrade(id: StringName) -> bool:
	if not can_buy(id):
		return false
	var def = _registry.get_def(PRESTIGE_TYPE, id)
	var lvl := level_of(id)
	_points -= cost_of(id)
	_levels[id] = lvl + 1
	_apply_upgrade(def, lvl + 1)
	return true

## 把某 NG+ 升级在 level 时的效果落 modifier(源 prestige_<id>,跨周目存活)。覆盖式。
func _apply_upgrade(def, level: int) -> void:
	var v := 0.0
	if def.op == &"add":
		v = float(def.effect_per_level) * level
	else:  # mul:每级 ×(1+effect)
		v = pow(1.0 + float(def.effect_per_level), level)
	_modifiers.set_modifier(def.target, _src(def.id), def.op, v)


# --- Lethal Mode(限时速通:无 NG+ 加成) ---

## 开一局 Lethal:撤 prestige 加成、门槛回 1M、清零计时。已在 Lethal 中 → false。
## (5 房重置由调用方 FortuneMill.start_lethal → _reset_rooms 负责。)
func start_lethal() -> bool:
	if _lethal:
		return false
	_lethal = true
	_lethal_elapsed = 0.0
	_rebuild_modifiers()   # factor→1.0 + 撤 prestige 源
	return true

## 累加 Lethal 计时(仅进行中)。
func tick_lethal(dt: float) -> void:
	if _lethal and dt > 0.0:
		_lethal_elapsed += dt

## 5 房全通关时调:记录最佳时间(取 min)、退出 Lethal、恢复 prestige 加成与门槛。返回本局用时。
func finish_lethal() -> float:
	if not _lethal:
		return -1.0
	var t := _lethal_elapsed
	if _lethal_best < 0.0 or t < _lethal_best:
		_lethal_best = t
	_lethal = false
	_rebuild_modifiers()
	return t

## 中途放弃 Lethal(不记时间),恢复 prestige 加成与门槛。
func abort_lethal() -> void:
	if not _lethal:
		return
	_lethal = false
	_rebuild_modifiers()


# --- modifier 重建(门槛因子 + prestige 加成;Lethal 时撤加成) ---

func _refresh_threshold() -> void:
	_modifiers.set_modifier(BRIBE_COST_MUL, THRESHOLD_SOURCE, &"mul", threshold_factor())

func _rebuild_modifiers() -> void:
	_refresh_threshold()
	# 先摘掉所有 prestige 源,再按当前状态重挂(Lethal 时不挂 → 无 NG+ 加成)
	for id in _levels:
		var def = _registry.get_def(PRESTIGE_TYPE, id)
		if def != null:
			_modifiers.remove_source(def.target, _src(id))
	if not _lethal:
		for id in _levels:
			var def2 = _registry.get_def(PRESTIGE_TYPE, id)
			if def2 != null:
				_apply_upgrade(def2, int(_levels[id]))

func _src(id: StringName) -> StringName:
	return StringName("prestige_" + String(id))


# --- 存档(只存权威态:ng_level/points/levels/lethal_best;门槛与 prestige 加成 from_dict 重算) ---
## Lethal 进行态不存(退出即结束;存档只留 best);_lethal_elapsed 是瞬时值不入档。

func to_dict() -> Dictionary:
	var lv := {}
	for id in _levels:
		lv[String(id)] = int(_levels[id])
	return {"ng_level": _ng_level, "points": _points, "levels": lv, "lethal_best": _lethal_best}

func from_dict(d: Dictionary) -> void:
	# 摘除旧 prestige 源(派生态从零重算不叠残留)
	for old_id in _levels:
		var od = _registry.get_def(PRESTIGE_TYPE, old_id)
		if od != null:
			_modifiers.remove_source(od.target, _src(old_id))
	_levels.clear()
	_lethal = false
	_lethal_elapsed = 0.0
	_ng_level = int(d.get("ng_level", 0))
	_points = float(d.get("points", 0.0))
	_lethal_best = float(d.get("lethal_best", -1.0))
	var lv: Dictionary = d.get("levels", {})
	for k in lv:
		_levels[StringName(k)] = int(lv[k])
	_rebuild_modifiers()
