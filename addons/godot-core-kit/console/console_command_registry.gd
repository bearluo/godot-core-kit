extends RefCounted
## 控制台命令表(纯逻辑,无 UI)。命令 callable 契约:func(args: PackedStringArray) -> Variant。
## 零依赖(诊断用 push_warning),可脱离框架单测。

var _commands: Dictionary = {}   # name(String) -> {callable: Callable, description: String}


## 登记命令。空名 → 忽略;无效 callable → 忽略;同名 → 覆盖 + 告警。
func register(name: String, callable: Callable, description: String = "") -> void:
	if name.is_empty():
		push_warning("ConsoleCommandRegistry.register: 空命令名,忽略")
		return
	if not callable.is_valid():
		push_warning("ConsoleCommandRegistry.register('%s'): 无效 callable,忽略" % name)
		return
	if _commands.has(name):
		push_warning("ConsoleCommandRegistry.register('%s'): 重复命令,覆盖" % name)
	_commands[name] = {"callable": callable, "description": description}


func unregister(name: String) -> void:
	_commands.erase(name)


func has(name: String) -> bool:
	return _commands.has(name)


## 已注册命令名,升序。
func names() -> PackedStringArray:
	var out := PackedStringArray(_commands.keys())
	out.sort()
	return out


func description_of(name: String) -> String:
	if _commands.has(name):
		return _commands[name]["description"]
	return ""


## 派发:以单参形式调用命令 callable(args 作为唯一实参)并返回其返回值;
## 未注册 → push_warning + 返回 null。
func dispatch(name: String, args: PackedStringArray) -> Variant:
	if not _commands.has(name):
		push_warning("ConsoleCommandRegistry.dispatch('%s'): 未注册" % name)
		return null
	var callable: Callable = _commands[name]["callable"]
	return callable.call(args)
