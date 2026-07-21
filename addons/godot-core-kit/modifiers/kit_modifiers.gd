class_name KitModifiers
extends RefCounted
## 数值修正器栈(off-facade 纯逻辑类,不挂节点树)。放置/增量(incremental/idle)游戏的
## 「产出聚合」心脏:每个可加成的量(伤害、产率、暴击率……)对应一个 target,其最终值 =
## (base + Σ加法层) × Π乘法层。每条修正带 source_id(哪个升级/道具/协同来源贡献的),
## 故可覆盖、可移除、可查询明细,顺序无关(聚合是可交换的),避免散落各处的 `total *= x`
## 顺序不可控、无法回滚、无法展示明细。
##
## value_for(target, base) = (base + Σ add.value) × Π mul.value。
## 脏标缓存聚合结果(add_sum, mul_product):set/remove 置脏,value_for/breakdown 惰性重算。
## 零依赖、不参与存档(调用方持权威态如升级等级,读档后重放 set_modifier 即可)。
##
## 跨来源协同:多个来源可写同一 target(如一条「全局乘数」target 被多处 mul),一次求值放大
## 所有读它的地方——这正是本类作为「唯一求值点」的价值。exp 指数层预留(未知 op 登记但不求值)。

var _mods: Dictionary = {}    # StringName(target) -> { StringName(source_id) -> {"op":StringName,"value":float} }
var _cache: Dictionary = {}   # StringName(target) -> {"add":float,"mul":float}
var _dirty: Dictionary = {}   # StringName(target) -> bool


## 注册/覆盖一条修正(同 source_id 覆盖式,累积效果请由调用方把 level 折进 value)。
## op:&"add"(进加法层)/ &"mul"(进乘法层)。其余(如保留的 &"exp")登记但暂不参与求值。
func set_modifier(target: StringName, source_id: StringName, op: StringName, value: float) -> void:
	if not _mods.has(target):
		_mods[target] = {}
	(_mods[target] as Dictionary)[source_id] = {"op": op, "value": value}
	_dirty[target] = true


func remove_source(target: StringName, source_id: StringName) -> void:
	if _mods.has(target) and (_mods[target] as Dictionary).has(source_id):
		(_mods[target] as Dictionary).erase(source_id)
		_dirty[target] = true


## (base + Σadd) × Πmul。惰性重算聚合并缓存。
func value_for(target: StringName, base: float) -> float:
	_ensure(target)
	var agg: Dictionary = _cache[target]
	return (base + float(agg["add"])) * float(agg["mul"])


## 明细查询:产出由哪些来源构成。返回
## {base, add, mul, result, sources:[{source_id, op, value}]}。UI 展示「产出来自...」。
## 未知 op(如保留的 exp)仍列进 sources,但不参与 add/mul 聚合。
func breakdown(target: StringName, base: float) -> Dictionary:
	_ensure(target)
	var agg: Dictionary = _cache[target]
	var list: Array = []
	if _mods.has(target):
		for sid in (_mods[target] as Dictionary):
			var mod: Dictionary = _mods[target][sid]
			list.append({"source_id": sid, "op": mod["op"], "value": float(mod["value"])})
	return {
		"base": base,
		"add": float(agg["add"]),
		"mul": float(agg["mul"]),
		"result": (base + float(agg["add"])) * float(agg["mul"]),
		"sources": list,
	}


## 某 target 上已注册的所有 source_id(顺序不保证)。
func sources(target: StringName) -> Array:
	if not _mods.has(target):
		return []
	return (_mods[target] as Dictionary).keys()


func clear(target: StringName = &"") -> void:
	if String(target).is_empty():
		_mods.clear()
		_cache.clear()
		_dirty.clear()
	else:
		_mods.erase(target)
		_cache.erase(target)
		_dirty[target] = true


## 若脏(或未缓存)则重算 target 的 (add_sum, mul_product)。
func _ensure(target: StringName) -> void:
	if _cache.has(target) and not bool(_dirty.get(target, true)):
		return
	var add_sum := 0.0
	var mul_prod := 1.0
	if _mods.has(target):
		for sid in (_mods[target] as Dictionary):
			var mod: Dictionary = _mods[target][sid]
			if mod["op"] == &"add":
				add_sum += float(mod["value"])
			elif mod["op"] == &"mul":
				mul_prod *= float(mod["value"])
	_cache[target] = {"add": add_sum, "mul": mul_prod}
	_dirty[target] = false
