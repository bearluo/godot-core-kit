class_name KitRebindButton
extends Button
## KitRebindButton —— 单动作键位重绑定按钮(off-facade 可复用 UI 组件)。
## 点击进捕获态 → 玩家按新键 → 冲突检测(检测+拦截)→ 落到 InputManager.rebind_action
## (替换 InputMap + 持久化 Settings)。只管 UI + 捕获 + 冲突判定;重绑/复位/持久化
## 复用注入的 InputManager(默认 CoreKit.input,可注入 standalone 做 headless 单测)。
##
## 零门面耦合:不引 CoreKit.log(失败经 rebind_failed 信号上报);对 CoreKit.input 的默认解析是
## 消费侧便利,测试注入 standalone InputManager 绕开。捕获 Key/MouseButton/JoypadButton
## (对齐 InputManager 编码支持,忽略 joypad motion);Esc 取消。

## 重绑成功。
signal rebound(action: String, event: InputEvent)
## 重绑失败。reason ∈ "conflict:<other>" / "unsupported" / "cancelled"。
signal rebind_failed(action: String, reason: String)

const CAPTURE_PROMPT := "按任意键…(Esc 取消)"

var _action: String = ""
var _conflict_scope: PackedStringArray = PackedStringArray()
var _input_mgr = null                  # untyped:未注入时运行期解析 CoreKit.input
var _capturing: bool = false


func _ready() -> void:
	set_process_input(false)
	pressed.connect(begin_capture)


## 绑定动作。input_manager 省略则运行期用 CoreKit.input;conflict_scope 空=冲突扫全部。
func setup(action: String, conflict_scope := PackedStringArray(), input_manager = null) -> void:
	_action = action
	_conflict_scope = conflict_scope
	_input_mgr = input_manager
	refresh()


## 进捕获态:提示文字 + 抢焦点 + 开输入监听。
func begin_capture() -> void:
	if _capturing:
		return
	_capturing = true
	text = CAPTURE_PROMPT
	set_process_input(true)
	grab_focus()


## 编程/UI 取消:退捕获态、刷新、发 cancelled。
func cancel_capture() -> void:
	if not _capturing:
		return
	_finish_capture()
	refresh()
	rebind_failed.emit(_action, "cancelled")


## 可测种子:处理一个候选事件。Esc→取消;不支持→unsupported;冲突→conflict:<other>
## 且不改绑定;否则 rebind_action → rebound。返回是否成功重绑。
func capture_event(event: InputEvent) -> bool:
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
		return _fail("cancelled")
	if not _is_capturable(event):
		return _fail("unsupported")
	var mgr = _resolve_input()
	var other := String(mgr.action_for_event(event, _conflict_scope))
	if other != "" and other != _action:
		return _fail("conflict:%s" % other)
	if not mgr.rebind_action(_action, event):
		return _fail("unsupported")
	_finish_capture()
	refresh()
	rebound.emit(_action, event)
	return true


## 失败收尾:退捕获态、刷新回当前绑定显示(不卡在「按任意键…」提示)、发 rebind_failed。
func _fail(reason: String) -> bool:
	_finish_capture()
	refresh()
	rebind_failed.emit(_action, reason)
	return false


## 刷新文字为当前绑定的可读名;无绑定显「未绑定」。
func refresh() -> void:
	var mgr = _resolve_input()
	var ev: InputEvent = mgr.get_action_event(_action)
	text = ev.as_text() if ev != null else "未绑定"


## 复位到工程默认(InputManager 内部会发 action_rebound)并刷新。
func reset() -> void:
	_resolve_input().reset_action(_action)
	refresh()


func _input(event: InputEvent) -> void:
	if not _capturing:
		return
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE and event.pressed:
		capture_event(event)
		accept_event()
		return
	if _is_capturable(event):
		capture_event(event)
		accept_event()


func _finish_capture() -> void:
	_capturing = false
	set_process_input(false)


func _is_capturable(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton:
		return event.pressed
	if event is InputEventJoypadButton:
		return event.pressed
	return false


func _resolve_input():
	return _input_mgr if _input_mgr != null else CoreKit.input
