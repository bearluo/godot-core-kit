extends SceneTree
## KitUiStack + KitUiScreen headless 断言。宿主入树(root.add_child + await frame)后
## 程序化 push/pop/replace/clear;屏用代码建的最小 Control(挂 KitUiScreen 子节点)。
## 运行:godot --headless --path . -s res://test/test_ui_stack.gd
## 前置:先跑过一次 --import(class_name 缓存),否则 is KitUiScreen 解析不到。

var StackScript
var ScreenScript
var journal: Array = []


## 建一屏:Control 根 + KitUiScreen 子组件,组件信号写进 journal。
func _mk(nm: String) -> Control:
	var s := Control.new()
	s.name = nm
	var comp = ScreenScript.new()
	comp.name = "KitUiScreen"
	s.add_child(comp)
	comp.entered.connect(func(prev: String) -> void: journal.append([nm, "entered", prev]))
	comp.exited.connect(func(nx: String) -> void: journal.append([nm, "exited", nx]))
	comp.covered.connect(func() -> void: journal.append([nm, "covered"]))
	comp.revealed.connect(func() -> void: journal.append([nm, "revealed"]))
	return s


func _initialize() -> void:
	StackScript = load("res://addons/godot-core-kit/ui/kit_ui_stack.gd")
	ScreenScript = load("res://addons/godot-core-kit/ui/kit_ui_screen.gd")
	var failures := 0

	var stack = StackScript.new()
	root.add_child(stack)
	await process_frame   # _initialize 期 root 未入树,补一帧触发 _ready

	# 1. push/depth/top
	var a1 = _mk("A"); stack.push(a1)
	var b1 = _mk("B"); stack.push(b1)
	var c1 = _mk("C"); var pushed = stack.push(c1)
	if stack.depth() != 3 or stack.top() != c1 or pushed != c1:
		print("FAIL 1: push 后 depth 应 3、top 应 C,depth=%d" % stack.depth()); failures += 1

	# 2. pop 顺序 + 空栈守卫
	stack.pop(); stack.pop()
	if stack.depth() != 1 or stack.top() != a1:
		print("FAIL 2: pop 两次后 depth 应 1、top 应 A,depth=%d" % stack.depth()); failures += 1
	stack.pop()
	stack.pop()   # 空栈再 pop → no-op 不崩
	if stack.depth() != 0:
		print("FAIL 2: 空栈 pop 应 no-op,depth=%d" % stack.depth()); failures += 1

	# 3. replace 换顶不改深 + 旧顶被 free
	var a3 = _mk("A3"); stack.push(a3)
	var b3 = _mk("B3"); stack.push(b3)
	var c3 = _mk("C3"); stack.replace(c3)
	if stack.depth() != 2 or stack.top() != c3:
		print("FAIL 3: replace 后 depth 应 2、top 应 C3,depth=%d" % stack.depth()); failures += 1
	await process_frame
	if is_instance_valid(b3):
		print("FAIL 3: replace 应 free 旧顶 B3"); failures += 1
	stack.clear()

	# 4. clear + emptied
	var emptied_count := [0]
	stack.emptied.connect(func() -> void: emptied_count[0] += 1)
	stack.push(_mk("X")); stack.push(_mk("Y"))
	stack.clear()
	if stack.depth() != 0 or emptied_count[0] != 1:
		print("FAIL 4: clear 后 depth 应 0、emptied 一次,depth=%d cnt=%d" % [stack.depth(), emptied_count[0]]); failures += 1

	# 5. hide_below=true 隐藏 + 停用下层
	var a5 = _mk("A5"); stack.push(a5)
	var b5 = _mk("B5"); stack.push(b5)   # 默认 hide_below=true
	if a5.visible != false or a5.can_process() != false:
		print("FAIL 5: 默认 push 应隐藏 + 停用下层,visible=%s can_process=%s" % [a5.visible, a5.can_process()]); failures += 1
	stack.pop()
	if a5.visible != true or a5.can_process() != true:
		print("FAIL 5: pop 后下层应还原,visible=%s can_process=%s" % [a5.visible, a5.can_process()]); failures += 1
	stack.clear()

	# 6. 模态 hide_below=false 保留可见 + 停用 + 插挡层
	var a6 = _mk("A6"); stack.push(a6)
	var b6 = _mk("B6"); stack.push(b6, {"hide_below": false, "dim": Color(0, 0, 0, 0.5)})
	var backdrop = stack._stack[-1]["backdrop"]
	if a6.visible != true or a6.can_process() != false:
		print("FAIL 6: 模态下层应可见但停用,visible=%s can_process=%s" % [a6.visible, a6.can_process()]); failures += 1
	if backdrop == null or backdrop.mouse_filter != Control.MOUSE_FILTER_STOP or backdrop.color != Color(0, 0, 0, 0.5):
		print("FAIL 6: 模态应插 STOP 挡层 + dim 色"); failures += 1
	stack.pop()
	await process_frame
	if a6.can_process() != true or is_instance_valid(backdrop):
		print("FAIL 6: pop 模态后下层应恢复、挡层应被 free"); failures += 1
	stack.clear()

	# 7. 生命周期信号 + 顺序
	journal.clear()
	var a7 = _mk("A"); stack.push(a7)   # A entered ""
	var b7 = _mk("B"); stack.push(b7)   # A covered, B entered "A"
	stack.pop()                          # B exited "A", A revealed
	var expect7 = [["A", "entered", ""], ["A", "covered"], ["B", "entered", "A"], ["B", "exited", "A"], ["A", "revealed"]]
	if journal != expect7:
		print("FAIL 7: 生命周期序列不符,实际 %s" % [journal]); failures += 1
	stack.clear()

	# 8. own 归属
	var keep := Control.new(); keep.name = "Keep"
	stack.push(keep, {"own": false})
	stack.pop()
	if not is_instance_valid(keep):
		print("FAIL 8: own=false 应仅 detach 不 free"); failures += 1
	if is_instance_valid(keep):
		keep.free()
	var drop = _mk("Drop"); stack.push(drop)   # own 默认 true
	stack.pop()
	await process_frame
	if is_instance_valid(drop):
		print("FAIL 8: own=true pop 后应被 free"); failures += 1

	# 9. KitUiScreen.of() 解析
	var s9 = _mk("S9")
	var deep := Button.new()
	s9.add_child(deep)
	stack.push(s9)
	if ScreenScript.of(deep) == null or ScreenScript.of(deep) != s9.get_node("KitUiScreen"):
		print("FAIL 9: of() 应从深层子节点找到本屏组件"); failures += 1
	var bare := Control.new()   # 无组件屏
	if ScreenScript.of(bare) != null:
		print("FAIL 9: 无组件屏 of() 应为 null"); failures += 1
	bare.free()
	stack.clear()

	# 10. 回指注入 + ui.pop() 等价
	var s10 = _mk("S10"); stack.push(s10)
	var comp10 = s10.get_node("KitUiScreen")
	if comp10.stack != stack:
		print("FAIL 10: push 应注入 stack 回指"); failures += 1
	stack.push(_mk("S10b"))
	var comp10b_depth_before: int = stack.depth()
	var comp10b = stack.top().get_node("KitUiScreen")
	comp10b.pop()   # 经组件转发弹自己
	if stack.depth() != comp10b_depth_before - 1:
		print("FAIL 10: ui.pop() 应等价宿主 pop(),depth 未 -1"); failures += 1
	stack.clear()

	# 11. cancel 弹栈 + cancellable=false 不弹
	var s11 = _mk("S11"); stack.push(s11)
	var ev := InputEventAction.new()
	ev.action = stack.cancel_action
	ev.pressed = true
	stack._unhandled_input(ev)
	if stack.depth() != 0:
		print("FAIL 11: cancel 应弹栈顶,depth=%d" % stack.depth()); failures += 1
	var s11b = _mk("S11b"); stack.push(s11b, {"cancellable": false})
	stack._unhandled_input(ev)
	if stack.depth() != 1:
		print("FAIL 11: cancellable=false 不应被 cancel 弹出,depth=%d" % stack.depth()); failures += 1
	stack.clear()

	# 12. 非法 push(拒绝调用方持有的节点,不替它 free → 测试自行释放)
	var before12: int = stack.depth()
	var bad_node := Node.new()
	var r1 = stack.push(Resource.new())
	var r2 = stack.push(bad_node)
	if r1 != null or r2 != null or stack.depth() != before12:
		print("FAIL 12: 非法 push 应返回 null 且不入栈,depth=%d" % stack.depth()); failures += 1
	bad_node.free()

	stack.free()

	if failures == 0:
		print("test_ui_stack: ALL PASS")
		quit(0)
	else:
		print("test_ui_stack: %d FAILURE(S)" % failures)
		quit(1)
