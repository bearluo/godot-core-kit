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
const SETTINGS_PATH := "user://__test_input_settings__.json"


func _make_key_event(keycode: int, pressed: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = pressed
	return ev


## 把 ACTION 的 InputMap 绑定恢复为默认(KEY_SPACE),模拟"新引擎会话启动时"。
func _restore_action_default() -> void:
	InputMap.action_erase_events(ACTION)
	InputMap.action_add_event(ACTION, _make_key_event(KEY_SPACE))


func _initialize() -> void:
	InputManagerScript = load("res://addons/godot-core-kit/input_manager.gd")
	SettingsScript = load("res://addons/godot-core-kit/settings.gd")
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
	if typeof(stored) != TYPE_DICTIONARY or stored.get("type") != "key":
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

	# 清理
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
