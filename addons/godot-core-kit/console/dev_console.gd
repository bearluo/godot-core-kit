extends CanvasLayer
## DevConsole —— 运行时调试控制台(CoreKit 第 11 子系统,面向前端 UI)。
## 完整四件套:日志 overlay + 命令/作弊注册 + GDScript 表达式执行 + 变量 watch。
## 门控:默认仅 OS.is_debug_build() 启用;发行版整体 no-op、零开销(可 force_enable 强开)。
## 全代码建 UI(无 .tscn),纯 GDScript、可 Web 导出。
##
## 用法:CoreKit.console.register_command("god", func(a): return "on")
##       CoreKit.console.bind_context("player", $Player)   # 后 player.hp=100 可求值
##       CoreKit.console.watch("player.hp")
##       控制台输入行:命中命令则派发,否则整行走 GDScript 表达式求值。
## 默认切换键 `(KEY_QUOTELEFT / ~),set_toggle_key 可改。

const RegistryScript := preload("res://addons/godot-core-kit/console/console_command_registry.gd")
const EvaluatorScript := preload("res://addons/godot-core-kit/console/console_evaluator.gd")
const WatchScript := preload("res://addons/godot-core-kit/console/console_watch_list.gd")

const TOGGLE_KEY_DEFAULT := KEY_QUOTELEFT
const WATCH_INTERVAL := 0.1
const INPUT_HISTORY_MAX := 64
## 日志 level → bbcode 颜色(镜像 Log._LEVEL_COLORS;INFO 用 "" 表默认色)。
const _LEVEL_COLOR := ["gray", "", "yellow", "red"]

var _registry
var _evaluator
var _watch
var _core: Object = null
var _enabled: bool = false
var _toggle_key: int = TOGGLE_KEY_DEFAULT
var _pause_on_open: bool = false
var _was_paused: bool = false
var _ui_built: bool = false
var _log_connected: bool = false
var _watch_accum: float = 0.0
var _input_history: Array[String] = []
var _history_index: int = 0

# UI 节点(建后持有)
var _root: Control
var _output: RichTextLabel
var _input_field: LineEdit
var _watch_label: RichTextLabel


func _init() -> void:
	_registry = RegistryScript.new()
	_evaluator = EvaluatorScript.new()
	_watch = WatchScript.new()
	layer = 128  # = CoreKit.layers.CONSOLE(权威保留带常量,见 systems/layer_manager.gd)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_enabled = OS.is_debug_build()
	if _enabled:
		_activate()
	else:
		set_process(false)
		set_process_input(false)


# --- 门面接线(由 CoreKit._ready 调用)------------------------------------
func bind_core(core: Object) -> void:
	_core = core
	_evaluator.set_base(core)
	if _enabled:
		_connect_log_feed()


# --- 启停 -----------------------------------------------------------------
func _activate() -> void:
	if not _ui_built:
		_build_ui()
	set_process(true)
	set_process_input(true)
	if _core != null:
		_connect_log_feed()


func _deactivate() -> void:
	close()
	set_process(false)
	set_process_input(false)
	_disconnect_log_feed()


func set_enabled(v: bool) -> void:
	if v:
		force_enable()
	else:
		_enabled = false
		_deactivate()


func is_enabled() -> bool:
	return _enabled


func force_enable() -> void:
	if _enabled and _ui_built:
		return
	_enabled = true
	_activate()


func _connect_log_feed() -> void:
	if _log_connected or _core == null:
		return
	var logger = _core.get("log")
	if logger == null:
		return
	logger.line_logged.connect(_on_log_line)
	_log_connected = true
	for line in logger.history():
		_append_output(String(line))


func _disconnect_log_feed() -> void:
	if not _log_connected or _core == null:
		return
	var logger = _core.get("log")
	if logger != null and logger.line_logged.is_connected(_on_log_line):
		logger.line_logged.disconnect(_on_log_line)
	_log_connected = false


# --- 公共 API:命令 / 上下文 / watch(委托逻辑单元)------------------------
func register_command(name: String, callable: Callable, description: String = "") -> void:
	_registry.register(name, callable, description)


func unregister_command(name: String) -> void:
	_registry.unregister(name)


func bind_context(name: String, object) -> void:
	_evaluator.bind_context(name, object)


func unbind_context(name: String) -> void:
	_evaluator.unbind_context(name)


func watch(expr: String) -> void:
	_watch.add(expr)


func unwatch(expr: String) -> void:
	_watch.remove(expr)


func set_toggle_key(keycode: int) -> void:
	_toggle_key = keycode


func set_pause_on_open(v: bool) -> void:
	_pause_on_open = v


# --- 提交 -----------------------------------------------------------------
## 程序化提交:回显 "> text",执行,返回输出串(UI 未建也可用 —— headless 命门)。
func execute(text: String) -> String:
	var out := _run(text)
	if _ui_built:
		_append_output("> " + text)
		if out != "":
			_append_output(out)
	return out


func _run(text: String) -> String:
	var trimmed := text.strip_edges()
	if trimmed == "":
		return ""
	var parts := trimmed.split(" ", false)
	var head := String(parts[0])
	if _registry.has(head):
		var args: PackedStringArray = parts.slice(1)
		var r = _registry.dispatch(head, args)
		return "" if r == null else str(r)
	var res: Dictionary = _evaluator.evaluate(trimmed)
	return str(res["value"]) if res["ok"] else "ERROR: " + String(res["error"])


# --- 显隐 -----------------------------------------------------------------
func toggle() -> void:
	if not _enabled or not _ui_built:
		return
	if is_open():
		close()
	else:
		open()


func open() -> void:
	if not _enabled or not _ui_built:
		return
	_root.visible = true
	_input_field.grab_focus()
	if _pause_on_open:
		_was_paused = get_tree().paused
		get_tree().paused = true


func close() -> void:
	if not _ui_built:
		return
	_root.visible = false
	if _pause_on_open:
		get_tree().paused = _was_paused


func is_open() -> bool:
	return _ui_built and _root.visible


# --- 每帧 watch(仅启用且可见)---------------------------------------------
func _process(delta: float) -> void:
	if not _enabled or not is_open():
		return
	_watch_accum += delta
	if _watch_accum < WATCH_INTERVAL:
		return
	_watch_accum = 0.0
	_refresh_watch()


func _refresh_watch() -> void:
	if _watch_label == null:
		return
	var results: Array = _watch.evaluate_all(_evaluator)
	var sb := ""
	for entry in results:
		if entry["ok"]:
			sb += "%s = %s\n" % [entry["expr"], str(entry["value"])]
		else:
			sb += "[color=red]%s ! %s[/color]\n" % [entry["expr"], _escape_bbcode(String(entry["error"]))]
	_watch_label.text = sb


# --- 输入 -----------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == _toggle_key:
		toggle()
		get_viewport().set_input_as_handled()


func _on_submit(text: String) -> void:
	execute(text)
	if not text.strip_edges().is_empty():
		_input_history.append(text)
		if _input_history.size() > INPUT_HISTORY_MAX:
			_input_history.pop_front()
	_history_index = _input_history.size()
	_input_field.clear()


func _on_input_gui(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			_recall_history(-1)
			_input_field.accept_event()
		elif event.keycode == KEY_DOWN:
			_recall_history(1)
			_input_field.accept_event()


func _recall_history(dir: int) -> void:
	if _input_history.is_empty():
		return
	_history_index = clampi(_history_index + dir, 0, _input_history.size())
	if _history_index >= _input_history.size():
		_input_field.text = ""
	else:
		_input_field.text = _input_history[_history_index]
	_input_field.caret_column = _input_field.text.length()


# --- 输出 -----------------------------------------------------------------
func _append_output(text: String) -> void:
	if not _ui_built or _output == null:
		return
	_output.append_text(_escape_bbcode(text) + "\n")


func _on_log_line(level: int, text: String) -> void:
	if not _ui_built or _output == null:
		return
	var color: String = _LEVEL_COLOR[level] if level >= 0 and level < _LEVEL_COLOR.size() else ""
	if color.is_empty():
		_append_output(text)
	else:
		_output.append_text("[color=%s]%s[/color]\n" % [color, _escape_bbcode(text)])


## 转义 bbcode:日志/结果文本里的 '[' 不应被 RichTextLabel 当标签解析。
func _escape_bbcode(s: String) -> String:
	return s.replace("[", "[lb]")


# --- UI 建构(全代码,无 .tscn)-------------------------------------------
func _build_ui() -> void:
	_root = Control.new()
	_root.name = "ConsoleRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 320.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	_output = RichTextLabel.new()
	_output.bbcode_enabled = true
	_output.scroll_following = true
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.custom_minimum_size = Vector2(0, 260)
	vbox.add_child(_output)

	_input_field = LineEdit.new()
	_input_field.placeholder_text = "命令或 GDScript 表达式,回车执行"
	_input_field.text_submitted.connect(_on_submit)
	_input_field.gui_input.connect(_on_input_gui)
	vbox.add_child(_input_field)

	_watch_label = RichTextLabel.new()
	_watch_label.bbcode_enabled = true
	_watch_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_watch_label.offset_left = -240.0
	_watch_label.offset_bottom = 160.0
	_watch_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_watch_label)

	_ui_built = true
