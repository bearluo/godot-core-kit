extends RefCounted
## 控制台表达式求值(纯逻辑,包 GDScript Expression)。
## parse/execute 错误全折成 {ok, value, error},永不抛到调用方。

var _base: Object = null          # 求值 base instance(裸标识符对它解析,通常 = CoreKit 门面)
var _contexts: Dictionary = {}    # name(String) -> object(作为 Expression input 变量注入)


func set_base(base: Object) -> void:
	_base = base


func bind_context(name: String, object) -> void:
	if name.is_empty():
		push_warning("ConsoleEvaluator.bind_context: 空名,忽略")
		return
	_contexts[name] = object


func unbind_context(name: String) -> void:
	_contexts.erase(name)


## 求值。返回 {ok: bool, value: Variant, error: String}。
func evaluate(text: String) -> Dictionary:
	var expr := Expression.new()
	var names := PackedStringArray(_contexts.keys())
	var err := expr.parse(text, names)
	if err != OK:
		return {"ok": false, "value": null, "error": expr.get_error_text()}
	var inputs: Array = []
	for n in names:                 # 与 names 同序(Dictionary 保插入序)
		inputs.append(_contexts[n])
	var result: Variant = expr.execute(inputs, _base, false)
	if expr.has_execute_failed():
		return {"ok": false, "value": null, "error": expr.get_error_text()}
	return {"ok": true, "value": result, "error": ""}
