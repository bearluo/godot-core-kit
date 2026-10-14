extends SceneTree
## KitRebindButton / KitRebindList headless 断言测试。经 capture_event 种子脱离真实
## 输入测核心逻辑;注入 standalone InputManager(临时动作 + _snapshot_defaults)。
## 运行:godot --headless --path . -s res://test/test_rebind.gd
##
## 加载注:input_manager.gd 运行期引用全局 autoload CoreKit,故 load() 于 _initialize;
## KitRebindButton/List(class_name)一并 load(),避免类作用域 preload 的解析期坑。
## 隔离:临时动作用完 InputMap.erase_action 清除。组件注入 im,从不触及 CoreKit.input。

var RebindButtonScript
var RebindListScript
var InputManagerScript

const A_JUMP := "__rb_jump__"
const A_FIRE := "__rb_fire__"


func _key(kc: int, pressed := true) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = kc
	ev.pressed = pressed
	return ev


func _pad(button: int, pressed := false) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = pressed
	return ev


func _initialize() -> void:
	RebindButtonScript = load("res://addons/godot-core-kit/ui/rebind_button.gd")
	RebindListScript = load("res://addons/godot-core-kit/ui/rebind_list.gd")
	InputManagerScript = load("res://addons/godot-core-kit/systems/input_manager.gd")
	var failures := 0

	# 临时动作:jump=SPACE,fire=G
	InputMap.add_action(A_JUMP)
	InputMap.action_add_event(A_JUMP, _key(KEY_SPACE, false))
	InputMap.add_action(A_FIRE)
	InputMap.action_add_event(A_FIRE, _key(KEY_G, false))
	var im = InputManagerScript.new()
	im._snapshot_defaults()

	var scope := PackedStringArray([A_JUMP, A_FIRE])
	var btn = RebindButtonScript.new()
	btn.setup(A_JUMP, scope, im)
	var rebounds := []
	var fails := []
	btn.rebound.connect(func(a, e): rebounds.append(a))
	btn.rebind_failed.connect(func(a, r): fails.append(r))

	# 1. 正常重绑 jump -> F
	var ok1: bool = btn.capture_event(_key(KEY_F))
	var jump_events := InputMap.action_get_events(A_JUMP)
	if not ok1 or jump_events.size() != 1 or jump_events[0].physical_keycode != KEY_F:
		print("FAIL 1: 正常重绑 jump 应变 F,ok=%s events=%s" % [ok1, jump_events])
		failures += 1
	if rebounds != [A_JUMP]:
		print("FAIL 1: 应发一次 rebound(jump),实际 %s" % [rebounds])
		failures += 1

	# 2. 冲突拦截:jump 重绑到 G(fire 占用)-> 拒绝、不改;失败后文字回退不卡提示
	btn.text = btn.CAPTURE_PROMPT  # 模拟捕获态
	var ok2: bool = btn.capture_event(_key(KEY_G))
	if ok2:
		print("FAIL 2: 冲突应返回 false")
		failures += 1
	if fails != ["conflict:%s" % A_FIRE]:
		print("FAIL 2: 应发 rebind_failed conflict:%s,实际 %s" % [A_FIRE, fails])
		failures += 1
	if InputMap.action_get_events(A_JUMP)[0].physical_keycode != KEY_F:
		print("FAIL 2: 冲突后 jump 绑定应保持 F 不变")
		failures += 1
	if btn.text == btn.CAPTURE_PROMPT:
		print("FAIL 2: 冲突失败后按钮文字应回退到绑定显示,不卡在捕获提示")
		failures += 1

	# 3. 不支持类型
	fails.clear()
	var ok3: bool = btn.capture_event(InputEventMouseMotion.new())
	if ok3 or fails != ["unsupported"]:
		print("FAIL 3: 不支持类型应 rebind_failed unsupported,实际 %s" % [fails])
		failures += 1

	# 4. Esc 取消
	fails.clear()
	var ok4: bool = btn.capture_event(_key(KEY_ESCAPE))
	if ok4 or fails != ["cancelled"]:
		print("FAIL 4: Esc 应 rebind_failed cancelled,实际 %s" % [fails])
		failures += 1
	if InputMap.action_get_events(A_JUMP)[0].physical_keycode != KEY_F:
		print("FAIL 4: 取消后 jump 绑定应不变(F)")
		failures += 1

	# 5. reset 回默认 SPACE
	btn.reset()
	if InputMap.action_get_events(A_JUMP)[0].physical_keycode != KEY_SPACE:
		print("FAIL 5: reset 应回默认 SPACE")
		failures += 1

	# 6. action_for_event(among 作用域,避开 ui_accept 默认占 Space)
	if im.action_for_event(_key(KEY_G), scope) != A_FIRE:
		print("FAIL 6: action_for_event(G) 应为 fire")
		failures += 1
	if im.action_for_event(_key(KEY_G), PackedStringArray([A_JUMP])) != "":
		print("FAIL 6: among 子集不含 fire 时应为空")
		failures += 1
	if im.action_for_event(InputEventScreenTouch.new(), scope) != "":
		print("FAIL 6: 不支持事件 action_for_event 应为空")
		failures += 1
	btn.free()

	# 7. KitRebindList:2 行 + 全部复位 + 转发信号
	im.reset_action(A_JUMP)  # 干净起步:jump 回 SPACE
	var list = RebindListScript.new()
	list.setup([{"action": A_JUMP, "label": "Jump"}, {"action": A_FIRE, "label": "Fire"}], im)
	if list._buttons.size() != 4:
		print("FAIL 7: 2 行 × 键盘/手柄两列应建 4 个重绑按钮,实际 %d" % list._buttons.size())
		failures += 1
	var list_rebounds := []
	list.rebound.connect(func(a, e): list_rebounds.append(a))
	list._buttons[0].capture_event(_key(KEY_F))  # 经首个按钮重绑 jump -> F(不冲突)
	if list_rebounds != [A_JUMP]:
		print("FAIL 7: 列表应转发 rebound(jump),实际 %s" % [list_rebounds])
		failures += 1
	list._on_reset_all()
	if InputMap.action_get_events(A_JUMP)[0].physical_keycode != KEY_SPACE:
		print("FAIL 7: 全部复位应把 jump 回 SPACE")
		failures += 1
	list.free()

	# 8. 按槽的按钮:只收本槽事件(异槽忽略且不退出捕获)、显示与复位只针对本槽
	im.free()
	InputMap.action_erase_events(A_JUMP)
	InputMap.action_add_event(A_JUMP, _key(KEY_SPACE, false))
	InputMap.action_add_event(A_JUMP, _pad(JOY_BUTTON_A))
	InputMap.action_erase_events(A_FIRE)
	InputMap.action_add_event(A_FIRE, _key(KEY_G, false))
	InputMap.action_add_event(A_FIRE, _pad(JOY_BUTTON_B))
	im = InputManagerScript.new()
	im._snapshot_defaults()
	var KBM: int = im.DeviceType.KEYBOARD_MOUSE
	var PAD: int = im.DeviceType.GAMEPAD
	var kb = RebindButtonScript.new()
	kb.setup(A_JUMP, scope, im, KBM)
	var pb = RebindButtonScript.new()
	pb.setup(A_JUMP, scope, im, PAD)
	if kb.text != "Space" or pb.text != "A":
		print("FAIL 8: 键盘列应显示 Space、手柄列应显示 A,实际 %s / %s" % [kb.text, pb.text])
		failures += 1
	var kb_events := []
	kb.rebound.connect(func(a, e): kb_events.append("ok"))
	kb.rebind_failed.connect(func(a, r): kb_events.append(r))
	kb.begin_capture()
	if kb.capture_event(_pad(JOY_BUTTON_X, true)) or not kb_events.is_empty() or not kb._capturing:
		print("FAIL 8: 键盘列收到手柄键应忽略:不重绑、不发信号、仍在捕获,实际 %s" % [kb_events])
		failures += 1
	if not kb.capture_event(_key(KEY_F)):
		print("FAIL 8: 键盘列应能绑 F")
		failures += 1
	var jump_pad = im.get_action_event(A_JUMP, PAD)
	if jump_pad == null or jump_pad.button_index != JOY_BUTTON_A:
		print("FAIL 8: 改键盘键后手柄 A 应保留")
		failures += 1
	pb.capture_event(_pad(JOY_BUTTON_Y, true))
	kb.reset()
	if im.get_action_event(A_JUMP, KBM).physical_keycode != KEY_SPACE or im.get_action_event(A_JUMP, PAD).button_index != JOY_BUTTON_Y:
		print("FAIL 8: 键盘列复位只应复位键盘槽(回 Space),手柄 Y 保留")
		failures += 1
	kb.free()
	pb.free()

	# 9. SWAP:有原键时两动作互换;本动作该槽为空时对方被清空;BLOCK 为默认
	im.reset_action(A_JUMP)
	im.reset_action(A_FIRE)
	var sw = RebindButtonScript.new()
	sw.setup(A_JUMP, scope, im, KBM)
	if sw.conflict_mode != sw.ConflictMode.BLOCK:
		print("FAIL 9: conflict_mode 默认应为 BLOCK")
		failures += 1
	sw.conflict_mode = sw.ConflictMode.SWAP
	var sw_ok := []
	sw.rebound.connect(func(a, e): sw_ok.append(a))
	if not sw.capture_event(_key(KEY_G)):
		print("FAIL 9: SWAP 冲突时应成功")
		failures += 1
	if im.get_action_event(A_JUMP, KBM).physical_keycode != KEY_G or im.get_action_event(A_FIRE, KBM).physical_keycode != KEY_SPACE:
		print("FAIL 9: SWAP 后 jump=G、fire=Space")
		failures += 1
	if im.get_action_event(A_FIRE, PAD).button_index != JOY_BUTTON_B:
		print("FAIL 9: SWAP 不应动对方的手柄槽")
		failures += 1
	if sw_ok != [A_JUMP]:
		print("FAIL 9: SWAP 成功应发一次 rebound,实际 %s" % [sw_ok])
		failures += 1
	im.unbind_action(A_JUMP, KBM)
	sw.capture_event(_key(KEY_SPACE))  # fire 占着 Space,jump 键盘槽为空
	if im.get_action_event(A_JUMP, KBM).physical_keycode != KEY_SPACE or im.get_action_event(A_FIRE, KBM) != null:
		print("FAIL 9: 本槽为空时 SWAP 应清空对方该槽")
		failures += 1
	sw.free()

	# 10. KitRebindList 两列:每行 [键盘, 手柄];devices 可只显示一列;行复位复位整行
	im.reset_action(A_JUMP)
	var rows := [{"action": A_JUMP, "label": "Jump"}, {"action": A_FIRE, "label": "Fire"}]
	var two = RebindListScript.new()
	two.setup(rows, im)
	if two._buttons.size() != 4 or two._buttons[0]._device != KBM or two._buttons[1]._device != PAD:
		print("FAIL 10: 默认每行应为 [键盘, 手柄] 两列")
		failures += 1
	two._buttons[0].capture_event(_key(KEY_F))
	two._buttons[1].capture_event(_pad(JOY_BUTTON_Y, true))
	two._reset_row(A_JUMP)
	if im.get_action_event(A_JUMP, KBM).physical_keycode != KEY_SPACE or im.get_action_event(A_JUMP, PAD).button_index != JOY_BUTTON_A:
		print("FAIL 10: 行复位应把整行(两个槽)恢复默认")
		failures += 1
	two.free()
	var kb_only = RebindListScript.new()
	kb_only.setup(rows, im, [KBM])
	if kb_only._buttons.size() != 2 or kb_only._buttons[0]._device != KBM:
		print("FAIL 10: devices=[KBM] 时每行只应有键盘列")
		failures += 1
	kb_only.free()

	# 清理
	im.free()
	InputMap.erase_action(A_JUMP)
	InputMap.erase_action(A_FIRE)

	if failures == 0:
		print("test_rebind: ALL PASS")
		quit(0)
	else:
		print("test_rebind: %d FAILURE(S)" % failures)
		quit(1)
