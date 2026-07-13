class_name KitUiStack
extends Control
## 通用 UI 栈导航宿主(off-facade 类库)。挂到任意父节点(某 CanvasLayer/Control)下,
## push/pop/replace/clear 管一叠 UI 屏(LIFO)。push 进来的屏是本节点子节点 →
## 只管加进来的、不碰你手动摆的。被盖屏 process_mode=DISABLED 一刀切停用(键鼠/动作/
## tick 全惰性);栈顶保持活动、用自己的输入回调;返回键经本节点 _unhandled_input 兜底。
## 屏若挂 KitUiScreen 组件则收生命周期信号 + 得公共方法。零框架依赖。

signal screen_pushed(screen: Control)
signal screen_popped(screen: Control)
signal emptied()

## 返回键动作名;为空 StringName 则关闭"返回键弹栈"。
@export var cancel_action: StringName = &"ui_cancel"

## 栈条目:{screen, backdrop, own, cancellable, prev_mode, prev_visible}。栈底->栈顶。
var _stack: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 压一屏。scene_or_node: PackedScene(实例化)或现成 Control。返回屏实例;非法 → null。
func push(scene_or_node, opts := {}) -> Control:
	var screen := _instantiate(scene_or_node)
	if screen == null:
		return null
	var prev_name := ""
	if not _stack.is_empty():
		var top_entry: Dictionary = _stack[-1]
		prev_name = String((top_entry["screen"] as Control).name)
		_cover(top_entry, opts.get("hide_below", true))
	_mount_new(screen, opts, prev_name)
	return screen


## 弹栈顶。空栈 → push_warning + no-op。
func pop() -> void:
	if _stack.is_empty():
		push_warning("KitUiStack: 栈空,pop 忽略")
		return
	var next_name := ""
	if _stack.size() >= 2:
		next_name = String((_stack[-2]["screen"] as Control).name)
	var top_screen: Control = _stack[-1]["screen"]
	_teardown_top(next_name)
	if not _stack.is_empty():
		_reveal(_stack[-1])
	screen_popped.emit(top_screen)
	if _stack.is_empty():
		emptied.emit()


## 换顶(栈深不变):拆旧顶但不 reveal 下层,再把新屏盖到同一下层。空栈时等价纯 push。
func replace(scene_or_node, opts := {}) -> Control:
	if _stack.is_empty():
		return push(scene_or_node, opts)
	var screen := _instantiate(scene_or_node)
	if screen == null:
		return null
	_teardown_top(String(screen.name))
	var prev_name := ""
	if not _stack.is_empty():
		prev_name = String((_stack[-1]["screen"] as Control).name)
	_mount_new(screen, opts, prev_name)
	return screen


## 从顶到底逐个弹空,末发 emptied。
func clear() -> void:
	if _stack.is_empty():
		return
	while not _stack.is_empty():
		var top_screen: Control = _stack[-1]["screen"]
		_teardown_top("")
		screen_popped.emit(top_screen)
	emptied.emit()


func top() -> Control:
	return _stack[-1]["screen"] if not _stack.is_empty() else null


func depth() -> int:
	return _stack.size()


func is_empty() -> bool:
	return _stack.is_empty()


## 返回键兜底:仅当没人消费该 unhandled 输入时才触发(栈顶自定义返回则不弹)。
func _unhandled_input(event: InputEvent) -> void:
	if _stack.is_empty() or cancel_action == &"":
		return
	if event.is_action_pressed(cancel_action) and _stack[-1]["cancellable"]:
		pop()
		get_viewport().set_input_as_handled()


## --- 内部 ---

## 归一 push 参数为 Control 实例;PackedScene 则 instantiate。非法 → push_error + null。
func _instantiate(scene_or_node) -> Control:
	if scene_or_node is PackedScene:
		var inst: Node = (scene_or_node as PackedScene).instantiate()
		if inst is Control:
			return inst
		push_error("KitUiStack.push: PackedScene 实例化结果非 Control,拒绝")
		if inst != null:
			inst.free()
		return null
	if scene_or_node is Control:
		return scene_or_node
	push_error("KitUiStack.push: 参数须为 PackedScene 或 Control,拒绝")
	return null


## 盖住一屏:记录原 process_mode/visible → DISABLED 停用 →(hide)隐藏 → covered()。
func _cover(entry: Dictionary, hide: bool) -> void:
	var screen: Control = entry["screen"]
	entry["prev_mode"] = screen.process_mode
	entry["prev_visible"] = screen.visible
	screen.process_mode = Node.PROCESS_MODE_DISABLED
	if hide:
		screen.visible = false
	var comp := KitUiScreen.of(screen)
	if comp != null:
		comp.covered.emit()


## 揭开一屏:还原 process_mode/visible → revealed()。
func _reveal(entry: Dictionary) -> void:
	var screen: Control = entry["screen"]
	screen.process_mode = entry.get("prev_mode", Node.PROCESS_MODE_INHERIT)
	screen.visible = entry.get("prev_visible", true)
	var comp := KitUiScreen.of(screen)
	if comp != null:
		comp.revealed.emit()


## 拆栈顶(不 reveal 下层):exited(next_name) → 移挡层 → 按 own free/detach 屏。
func _teardown_top(next_name: String) -> void:
	var entry: Dictionary = _stack.pop_back()
	var screen: Control = entry["screen"]
	var comp := KitUiScreen.of(screen)
	if comp != null:
		comp.exited.emit(next_name)
	if entry["backdrop"] != null:
		(entry["backdrop"] as Node).queue_free()
	remove_child(screen)
	if entry["own"]:
		screen.queue_free()


## 挂新屏为栈顶:(模态)插挡层 → add_child → 记条目 → 注入 stack + entered() → screen_pushed。
func _mount_new(screen: Control, opts: Dictionary, prev_name: String) -> void:
	var backdrop: ColorRect = null
	if not opts.get("hide_below", true):
		backdrop = ColorRect.new()
		backdrop.color = opts.get("dim", Color(0, 0, 0, 0))
		backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(backdrop)
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	_stack.append({
		"screen": screen,
		"backdrop": backdrop,
		"own": opts.get("own", true),
		"cancellable": opts.get("cancellable", true),
		"prev_mode": Node.PROCESS_MODE_INHERIT,
		"prev_visible": true,
	})
	var comp := KitUiScreen.of(screen)
	if comp != null:
		comp.stack = self
		comp.entered.emit(prev_name)
	screen_pushed.emit(screen)
