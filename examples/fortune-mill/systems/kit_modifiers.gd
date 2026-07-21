class_name KitModifiers
extends RefCounted
## 数值修正器栈雏形。target -> { source_id -> {op, value} }。
## value_for(target, base) = (base + Σ add.value) × Π mul.value。
## 脏标缓存聚合结果(add_sum, mul_product),set/remove 置脏,value_for 惰性重算。
## bus 只广播脏标记;真正的求值只在这里发生(spec §5.6 的唯一求值点)。

var _mods: Dictionary = {}    # StringName(target) -> { StringName(source_id) -> {"op":StringName,"value":float} }
var _cache: Dictionary = {}   # StringName(target) -> {"add":float,"mul":float}
var _dirty: Dictionary = {}   # StringName(target) -> bool


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
