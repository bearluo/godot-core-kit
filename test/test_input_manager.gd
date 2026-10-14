extends SceneTree
## InputManager headless 断言测试(直接实例化,不入树 → _ready 不自动跑,
## 手动调 _snapshot_defaults();设备/缓冲用手工构造的 InputEvent 直接喂
## _input(),不需要真实硬件;InputMap 在 headless 下完全可编程)。
## 运行:godot --headless --path . -s res://test/test_input_manager.gd
##
## 加载注:input_manager.gd 运行期引用全局 autoload 标识符 CoreKit,故不在
## 类作用域 preload,延迟到 _initialize() 内 load()。持久化用真 Settings 实例
## + 一次性测试文件(不碰真实 user://settings.json)。

var InputManagerScript
var SettingsScript

const ACTION := "__test_jump__"
const SLOT_ACTION := "__test_move_up__"
const SETTINGS_PATH := "user://__test_input_settings__.json"


func _make_key_event(keycode: int, pressed: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = pressed
	return ev


func _joy(button: int) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	return ev


## SLOT_ACTION 的工程默认:键盘槽两个键(W/↑),手柄槽一个(十字键上)。
func _slot_defaults() -> Array:
	return [_make_key_event(KEY_W), _make_key_event(KEY_UP), _joy(JOY_BUTTON_DPAD_UP)]


## 把动作当前绑定描述成排序后的字符串数组,便于整体比较。
func _describe(action: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append("key:%d" % ev.physical_keycode)
		elif ev is InputEventJoypadButton:
			out.append("joy:%d" % ev.button_index)
		elif ev is InputEventJoypadMotion:
			out.append("axis:%d:%s" % [ev.axis, ev.axis_value])
		else:
			out.append(ev.get_class())
	out.sort()
	return out


func _sorted_default_desc() -> Array:
	var out := ["joy:%d" % JOY_BUTTON_DPAD_UP, "key:%d" % KEY_UP, "key:%d" % KEY_W]
	out.sort()
	return out


## 模拟新会话:InputMap 回工程默认,新实例快照后绑定 settings。
func _fresh_slot_manager(settings):
	_restore_slot_default()
	var m = InputManagerScript.new()
	m._snapshot_defaults()
	m.bind_settings(settings)
	return m


## 把 SLOT_ACTION 的 InputMap 恢复为工程默认,模拟新会话。
func _restore_slot_default() -> void:
	InputMap.action_erase_events(SLOT_ACTION)
	for ev in _slot_defaults():
		InputMap.action_add_event(SLOT_ACTION, ev)


## 把 ACTION 的 InputMap 绑定恢复为默认(KEY_SPACE),模拟"新引擎会话启动时"。
func _restore_action_default() -> void:
	InputMap.action_erase_events(ACTION)
	InputMap.action_add_event(ACTION, _make_key_event(KEY_SPACE))


func _initialize() -> void:
	InputManagerScript = load("res://addons/godot-core-kit/systems/input_manager.gd")
	SettingsScript = load("res://addons/godot-core-kit/core/settings.gd")
	var failures := 0

	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	InputMap.add_action(ACTION)
	InputMap.action_add_event(ACTION, _make_key_event(KEY_SPACE))

	var im = InputManagerScript.new()
	im._snapshot_defaults()

	# 1. _event_to_dict / _dict_to_event 四种类型往返;不支持类型;畸形 dict
	var key_ev := _make_key_event(KEY_J)
	var key_dict: Dictionary = im._event_to_dict(key_ev)
	var key_back = im._dict_to_event(key_dict)
	if not (key_back is InputEventKey) or key_back.physical_keycode != KEY_J:
		print("FAIL 1: key 往返失败,得到 %s / %s" % [key_dict, key_back])
		failures += 1
	var mouse_ev := InputEventMouseButton.new()
	mouse_ev.button_index = MOUSE_BUTTON_RIGHT
	var mouse_back = im._dict_to_event(im._event_to_dict(mouse_ev))
	if not (mouse_back is InputEventMouseButton) or mouse_back.button_index != MOUSE_BUTTON_RIGHT:
		print("FAIL 1: mouse_button 往返失败")
		failures += 1
	var joy_btn_ev := InputEventJoypadButton.new()
	joy_btn_ev.button_index = JOY_BUTTON_A
	var joy_btn_back = im._dict_to_event(im._event_to_dict(joy_btn_ev))
	if not (joy_btn_back is InputEventJoypadButton) or joy_btn_back.button_index != JOY_BUTTON_A:
		print("FAIL 1: joypad_button 往返失败")
		failures += 1
	var joy_motion_ev := InputEventJoypadMotion.new()
	joy_motion_ev.axis = JOY_AXIS_LEFT_X
	joy_motion_ev.axis_value = -1.0
	var joy_motion_back = im._dict_to_event(im._event_to_dict(joy_motion_ev))
	if not (joy_motion_back is InputEventJoypadMotion) or joy_motion_back.axis != JOY_AXIS_LEFT_X or joy_motion_back.axis_value != -1.0:
		print("FAIL 1: joypad_motion 往返失败")
		failures += 1
	if im._event_to_dict(InputEventScreenTouch.new()) != {}:
		print("FAIL 1: 不支持的事件类型应编码为 {}")
		failures += 1
	if im._dict_to_event({}) != null or im._dict_to_event({"type": "alien"}) != null or im._dict_to_event({"type": "key"}) != null:
		print("FAIL 1: 畸形 dict 应解码为 null")
		failures += 1

	# 2. rebind_action:替换绑定、广播、未知 action 拒绝
	var rebound := []
	im.action_rebound.connect(func(action: String) -> void: rebound.append(action))
	if not im.rebind_action(ACTION, _make_key_event(KEY_J)):
		print("FAIL 2: 合法重绑定应返回 true")
		failures += 1
	var events := InputMap.action_get_events(ACTION)
	if events.size() != 1 or not (events[0] is InputEventKey) or events[0].physical_keycode != KEY_J:
		print("FAIL 2: 重绑定应整体替换为单事件 KEY_J")
		failures += 1
	if rebound != [ACTION]:
		print("FAIL 2: action_rebound 应广播一次")
		failures += 1
	if im.rebind_action("__no_such_action__", _make_key_event(KEY_K)):
		print("FAIL 2: 未知 action 应返回 false")
		failures += 1
	if im.rebind_action(ACTION, InputEventScreenTouch.new()):
		print("FAIL 2: 不支持的事件类型应返回 false")
		failures += 1

	# 3. reset_action 恢复快照默认
	im.reset_action(ACTION)
	var reset_events := InputMap.action_get_events(ACTION)
	if reset_events.size() != 1 or reset_events[0].physical_keycode != KEY_SPACE:
		print("FAIL 3: reset_action 应恢复 KEY_SPACE 默认")
		failures += 1

	# 3b. get_action_event
	var first_event = im.get_action_event(ACTION)
	if not (first_event is InputEventKey) or first_event.physical_keycode != KEY_SPACE:
		print("FAIL 3b: get_action_event 应返回第一个绑定")
		failures += 1
	if im.get_action_event("__no_such_action__") != null:
		print("FAIL 3b: 未知 action 应返回 null")
		failures += 1

	# 4. 持久化:rebind 写入 settings;新实例 bind 后覆盖恢复;reset 清除覆盖
	var settings = SettingsScript.new()
	settings.settings_path = SETTINGS_PATH
	im.bind_settings(settings)
	im.rebind_action(ACTION, _make_key_event(KEY_J))
	var stored = settings.get_value("input", ACTION)
	if typeof(stored) != TYPE_DICTIONARY or typeof(stored.get("kbm")) != TYPE_DICTIONARY or stored["kbm"].get("type") != "key":
		print("FAIL 4: rebind 应把覆盖写进 settings,得到 %s" % [stored])
		failures += 1
	_restore_action_default()  # 模拟新会话:InputMap 回到工程默认
	var im2 = InputManagerScript.new()
	im2._snapshot_defaults()
	im2.bind_settings(settings)
	var restored := InputMap.action_get_events(ACTION)
	if restored.size() != 1 or restored[0].physical_keycode != KEY_J:
		print("FAIL 4: bind_settings 应把覆盖恢复到 InputMap")
		failures += 1
	im2.reset_action(ACTION)
	if settings.get_value("input", ACTION) != null:
		print("FAIL 4: reset 应清除 settings 覆盖")
		failures += 1
	var after_reset := InputMap.action_get_events(ACTION)
	if after_reset.size() != 1 or after_reset[0].physical_keycode != KEY_SPACE:
		print("FAIL 4: reset 后 InputMap 应回默认")
		failures += 1
	im2.free()

	# 5. 损坏覆盖:跳过不崩,其余正常
	settings.set_value("input", ACTION, {"type": "alien"})
	settings.set_value("input", "__ghost_action__", 42)  # 非 dict + 动作不存在,均只跳过
	var im3 = InputManagerScript.new()
	im3._snapshot_defaults()
	im3.bind_settings(settings)  # 不崩即通过
	var still_default := InputMap.action_get_events(ACTION)
	if still_default.size() != 1 or still_default[0].physical_keycode != KEY_SPACE:
		print("FAIL 5: 损坏覆盖应被跳过,InputMap 保持默认")
		failures += 1
	im3.free()

	# 6. 设备检测:仅变化时广播;摇杆噪声门限
	var devices := []
	im.device_changed.connect(func(device_type) -> void: devices.append(device_type))
	var joy_press := InputEventJoypadButton.new()
	joy_press.button_index = JOY_BUTTON_A
	im._input(joy_press)
	if devices != [im.DeviceType.GAMEPAD] or im.current_device != im.DeviceType.GAMEPAD:
		print("FAIL 6: 手柄按键应切到 GAMEPAD")
		failures += 1
	var drift := InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = 0.1
	im._input(drift)  # 噪声,不切换、不广播(本来就是 GAMEPAD 也不重发)
	im._input(_make_key_event(KEY_A, true))
	if devices.size() != 2 or devices[1] != im.DeviceType.KEYBOARD_MOUSE:
		print("FAIL 6: 键盘事件应切回 KEYBOARD_MOUSE,实际 %s" % [devices])
		failures += 1
	var strong := InputEventJoypadMotion.new()
	strong.axis = JOY_AXIS_LEFT_X
	strong.axis_value = 0.5
	im._input(strong)
	if devices.size() != 3 or devices[2] != im.DeviceType.GAMEPAD:
		print("FAIL 6: 过门限摇杆应切到 GAMEPAD")
		failures += 1
	var touch := InputEventScreenTouch.new()
	im._input(touch)
	if devices.size() != 4 or devices[3] != im.DeviceType.TOUCH:
		print("FAIL 6: 触屏事件应切到 TOUCH")
		failures += 1

	# 7. 输入缓冲:窗口内 true、超窗 false、consume 立即失效
	var clock := {"now": 100000}
	im._ticks_msec_func = func() -> int: return clock["now"]
	_restore_action_default()
	im._input(_make_key_event(KEY_SPACE, true))  # 命中 ACTION,记录时间戳
	if not im.is_action_buffered(ACTION, 0.15):
		print("FAIL 7: 刚按下应在缓冲窗口内")
		failures += 1
	clock["now"] += 100
	if not im.is_action_buffered(ACTION, 0.15):
		print("FAIL 7: 100ms 后仍应在 150ms 窗口内")
		failures += 1
	clock["now"] += 100
	if im.is_action_buffered(ACTION, 0.15):
		print("FAIL 7: 200ms 后应超出 150ms 窗口")
		failures += 1
	im._input(_make_key_event(KEY_SPACE, true))
	im.consume_buffer(ACTION)
	if im.is_action_buffered(ACTION, 0.15):
		print("FAIL 7: consume 后应立即失效")
		failures += 1
	if im.is_action_buffered("__never_pressed__", 9.9):
		print("FAIL 7: 未按过的 action 应为 false")
		failures += 1

	# 8. action_for_event:among 作用域内命中/不命中/不支持事件
	_restore_action_default()  # ACTION 回 SPACE
	if im.action_for_event(_make_key_event(KEY_SPACE), PackedStringArray([ACTION])) != ACTION:
		print("FAIL 8: action_for_event(SPACE, [ACTION]) 应命中 ACTION")
		failures += 1
	if im.action_for_event(_make_key_event(KEY_Z), PackedStringArray([ACTION])) != "":
		print("FAIL 8: 未占用的键应返回空")
		failures += 1
	if im.action_for_event(InputEventScreenTouch.new(), PackedStringArray([ACTION])) != "":
		print("FAIL 8: 不支持事件应返回空")
		failures += 1

	# 9. 按设备分槽:slot_of;重绑只替换同槽,另一槽保留
	InputMap.add_action(SLOT_ACTION)
	for ev in _slot_defaults():
		InputMap.action_add_event(SLOT_ACTION, ev)
	var ims = InputManagerScript.new()
	ims._snapshot_defaults()
	var KBM: int = ims.DeviceType.KEYBOARD_MOUSE
	var PAD: int = ims.DeviceType.GAMEPAD
	if ims.slot_of(_make_key_event(KEY_J)) != KBM or ims.slot_of(mouse_ev) != KBM:
		print("FAIL 9: 键盘/鼠标事件应归 KEYBOARD_MOUSE 槽")
		failures += 1
	if ims.slot_of(joy_btn_ev) != PAD or ims.slot_of(joy_motion_ev) != PAD:
		print("FAIL 9: 手柄按键/轴应归 GAMEPAD 槽")
		failures += 1
	if ims.slot_of(InputEventScreenTouch.new()) != -1:
		print("FAIL 9: 不可绑定事件应返回 -1")
		failures += 1
	ims.rebind_action(SLOT_ACTION, _make_key_event(KEY_J))
	if _describe(SLOT_ACTION) != ["joy:%d" % JOY_BUTTON_DPAD_UP, "key:%d" % KEY_J]:
		print("FAIL 9: 改键盘键后应只剩 J + 手柄原键,实际 %s" % [_describe(SLOT_ACTION)])
		failures += 1
	ims.rebind_action(SLOT_ACTION, _joy(JOY_BUTTON_B))
	if _describe(SLOT_ACTION) != ["joy:%d" % JOY_BUTTON_B, "key:%d" % KEY_J]:
		print("FAIL 9: 改手柄键后键盘 J 应保留,实际 %s" % [_describe(SLOT_ACTION)])
		failures += 1

	# 10. 按槽查询与复位
	var kbm_ev = ims.get_action_event(SLOT_ACTION, KBM)
	var pad_ev = ims.get_action_event(SLOT_ACTION, PAD)
	if not (kbm_ev is InputEventKey) or kbm_ev.physical_keycode != KEY_J:
		print("FAIL 10: get_action_event(KBM) 应返回 J")
		failures += 1
	if not (pad_ev is InputEventJoypadButton) or pad_ev.button_index != JOY_BUTTON_B:
		print("FAIL 10: get_action_event(GAMEPAD) 应返回 B")
		failures += 1
	ims.reset_action(SLOT_ACTION, KBM)
	if _describe(SLOT_ACTION) != ["joy:%d" % JOY_BUTTON_B, "key:%d" % KEY_UP, "key:%d" % KEY_W]:
		print("FAIL 10: 按槽复位键盘应恢复 W/↑ 且保留手柄 B,实际 %s" % [_describe(SLOT_ACTION)])
		failures += 1
	ims.reset_action(SLOT_ACTION)
	if _describe(SLOT_ACTION) != _sorted_default_desc():
		print("FAIL 10: 不带 device 的 reset 应整体恢复默认")
		failures += 1
	ims.free()

	# 11. 新持久化格式:按槽存,只存改过的槽;重启恢复;事件规范化为 device=-1
	var sset = SettingsScript.new()
	sset.settings_path = SETTINGS_PATH
	var im_a = _fresh_slot_manager(sset)
	var raw := _make_key_event(KEY_J, true)
	raw.device = 3
	raw.ctrl_pressed = true
	im_a.rebind_action(SLOT_ACTION, raw)
	if sset.get_value("input", SLOT_ACTION) != {"kbm": {"type": "key", "physical_keycode": KEY_J}}:
		print("FAIL 11: 只应存改过的 kbm 槽,实际 %s" % [sset.get_value("input", SLOT_ACTION)])
		failures += 1
	var live = im_a.get_action_event(SLOT_ACTION, KBM)
	if live.device != -1 or live.ctrl_pressed or live.pressed:
		print("FAIL 11: 本局生效的事件应规范化(device=-1、无修饰、未按下)")
		failures += 1
	var pad_raw := _joy(JOY_BUTTON_B)
	pad_raw.device = 2
	im_a.rebind_action(SLOT_ACTION, pad_raw)
	im_a.free()
	var im_b = _fresh_slot_manager(sset)
	if _describe(SLOT_ACTION) != ["joy:%d" % JOY_BUTTON_B, "key:%d" % KEY_J]:
		print("FAIL 11: 重启后应恢复两个槽的覆盖,实际 %s" % [_describe(SLOT_ACTION)])
		failures += 1
	for ev in InputMap.action_get_events(SLOT_ACTION):
		if ev.device != -1:
			print("FAIL 11: 恢复出的事件 device 应为 -1,%s 为 %d" % [ev.get_class(), ev.device])
			failures += 1
	# 12. 按槽复位只删该槽记录;unbind 存 null,重启仍为空槽
	im_b.reset_action(SLOT_ACTION, KBM)
	if sset.get_value("input", SLOT_ACTION) != {"gamepad": {"type": "joypad_button", "button_index": JOY_BUTTON_B}}:
		print("FAIL 12: 按槽复位应只删 kbm 记录,实际 %s" % [sset.get_value("input", SLOT_ACTION)])
		failures += 1
	if not im_b.unbind_action(SLOT_ACTION, PAD):
		print("FAIL 12: unbind_action 应返回 true")
		failures += 1
	if im_b.get_action_event(SLOT_ACTION, PAD) != null:
		print("FAIL 12: unbind 后手柄槽应为空")
		failures += 1
	if sset.get_value("input", SLOT_ACTION) != {"gamepad": null}:
		print("FAIL 12: unbind 应存 null,实际 %s" % [sset.get_value("input", SLOT_ACTION)])
		failures += 1
	if im_b.unbind_action("__no_such_action__", PAD) or im_b.unbind_action(SLOT_ACTION, im_b.DeviceType.TOUCH):
		print("FAIL 12: 未知动作或非法槽 unbind 应返回 false")
		failures += 1
	im_b.free()
	var im_c = _fresh_slot_manager(sset)
	if _describe(SLOT_ACTION) != ["key:%d" % KEY_UP, "key:%d" % KEY_W]:
		print("FAIL 12: 重启后手柄槽应保持清空,实际 %s" % [_describe(SLOT_ACTION)])
		failures += 1
	im_c.free()

	# 13. 旧格式:只覆盖对应槽,另一槽用默认;下次写入才转新格式
	sset.set_value("input", SLOT_ACTION, {"type": "key", "physical_keycode": KEY_J})
	var im_d = _fresh_slot_manager(sset)
	if _describe(SLOT_ACTION) != ["joy:%d" % JOY_BUTTON_DPAD_UP, "key:%d" % KEY_J]:
		print("FAIL 13: 旧格式应只覆盖键盘槽,实际 %s" % [_describe(SLOT_ACTION)])
		failures += 1
	if sset.get_value("input", SLOT_ACTION) != {"type": "key", "physical_keycode": KEY_J}:
		print("FAIL 13: 读取时不应改写旧格式")
		failures += 1
	im_d.rebind_action(SLOT_ACTION, _joy(JOY_BUTTON_X))
	if sset.get_value("input", SLOT_ACTION) != {"kbm": {"type": "key", "physical_keycode": KEY_J}, "gamepad": {"type": "joypad_button", "button_index": JOY_BUTTON_X}}:
		print("FAIL 13: 下次写入应转成新格式,实际 %s" % [sset.get_value("input", SLOT_ACTION)])
		failures += 1
	im_d.free()

	# 14. 单槽损坏只跳过该槽
	sset.set_value("input", SLOT_ACTION, {"kbm": {"type": "alien"}, "gamepad": {"type": "joypad_button", "button_index": JOY_BUTTON_B}})
	var im_e = _fresh_slot_manager(sset)
	if _describe(SLOT_ACTION) != ["joy:%d" % JOY_BUTTON_B, "key:%d" % KEY_UP, "key:%d" % KEY_W]:
		print("FAIL 14: 损坏的 kbm 槽应跳过、gamepad 槽照常,实际 %s" % [_describe(SLOT_ACTION)])
		failures += 1
	im_e.free()
	sset.free()

	# 清理
	InputMap.erase_action(SLOT_ACTION)
	im.free()
	settings.free()
	InputMap.erase_action(ACTION)
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)

	if failures == 0:
		print("test_input_manager: ALL PASS")
		quit(0)
	else:
		print("test_input_manager: %d FAILURE(S)" % failures)
		quit(1)
