extends RefCounted
## 控制台 watch 表(纯逻辑)。去重、保序;evaluate_all 复用传入 evaluator。

var _exprs: Array[String] = []


func add(expr: String) -> void:
	if expr.is_empty():
		return
	if not _exprs.has(expr):
		_exprs.append(expr)


func remove(expr: String) -> void:
	_exprs.erase(expr)


func entries() -> Array[String]:
	return _exprs.duplicate()


func clear() -> void:
	_exprs.clear()


## 逐条用 evaluator 求值。返回 [{expr, ok, value, error}, ...]。
func evaluate_all(evaluator) -> Array:
	var out: Array = []
	for e in _exprs:
		var r: Dictionary = evaluator.evaluate(e)
		out.append({"expr": e, "ok": r["ok"], "value": r["value"], "error": r["error"]})
	return out
