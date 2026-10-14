class_name KitRebindList
extends VBoxContainer
## KitRebindList —— 多动作重绑定列表(off-facade 可复用 UI 组件)。
## 吃 [{action, label}, ...],每行建 [Label | 键盘列 | 手柄列 | 复位],底部「全部复位」。
## 每列一个 KitRebindButton,只管该绑定槽;行复位复位整行(两个槽)。
## 各按钮的 conflict_scope = 全部行动作(冲突只在可重绑集合内判)。转发子按钮信号。

signal rebound(action: String, event: InputEvent)
signal rebind_failed(action: String, reason: String)

## InputManager.DeviceType 的 KEYBOARD_MOUSE / GAMEPAD(子系统无 class_name,这里写值)。
const DEFAULT_DEVICES := [0, 1]

var _input = null
var _buttons: Array = []                       # KitRebindButton 列表(按行、行内按列)
var _row_actions: PackedStringArray = PackedStringArray()


## rows = [{action, label}, ...]。input_manager 省略则各按钮用 CoreKit.input。
## devices 选显示哪些列(纯键盘或纯手柄的游戏只给一列)。
func setup(rows: Array, input_manager = null, devices: Array = DEFAULT_DEVICES) -> void:
	_input = input_manager
	_clear()
	_row_actions = PackedStringArray()
	for row in rows:
		_row_actions.append(String(row.get("action", "")))
	for row in rows:
		_add_row(String(row.get("action", "")), String(row.get("label", row.get("action", ""))), devices)
	var reset_all_btn := Button.new()
	reset_all_btn.text = "全部复位"
	reset_all_btn.pressed.connect(_on_reset_all)
	add_child(reset_all_btn)


## 刷新所有子按钮(复位后 / 外部变更后)。
func refresh_all() -> void:
	for btn in _buttons:
		btn.refresh()


func _add_row(action: String, label_text: String, devices: Array) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	for device in devices:
		var btn := KitRebindButton.new()
		row.add_child(btn)
		btn.setup(action, _row_actions, _input, device)
		btn.rebound.connect(func(a, e): rebound.emit(a, e))
		btn.rebind_failed.connect(func(a, r): rebind_failed.emit(a, r))
		_buttons.append(btn)
	var reset_btn := Button.new()
	reset_btn.text = "复位"
	reset_btn.pressed.connect(_reset_row.bind(action))
	row.add_child(reset_btn)
	add_child(row)


func _reset_row(action: String) -> void:
	_mgr().reset_action(action)
	refresh_all()


## 只复位本列表的行(不用 reset_all,避免复位列表外动作)。
func _on_reset_all() -> void:
	for action in _row_actions:
		_mgr().reset_action(action)
	refresh_all()


func _mgr():
	return _input if _input != null else CoreKit.input


func _clear() -> void:
	for child in get_children():
		child.queue_free()
	_buttons.clear()
