extends SceneTree
## InputManager 手柄相关 headless 断言测试:品牌识别、按键图标键名、当前手柄跟踪、震动。
## 震动经可注入的 Input 后端替身记录调用,不需要真实硬件。
## 运行:godot --headless --path . -s res://test/test_input_joypad.gd
##
## 加载注:input_manager.gd 运行期引用全局 CoreKit,故延迟到 _initialize() 内 load()。

var InputManagerScript
var failures := 0

const SETTINGS_PATH := "user://__test_input_joypad_settings__.json"


## Input 单例替身:joys = {device: [vendor_id, name]};记录震动调用。
class FakeInput extends RefCounted:
	var joys := {}
	var vibratable := {}
	var calls := []

	func get_connected_joypads() -> Array:
		return joys.keys()

	func get_joy_info(device: int) -> Dictionary:
		return {"vendor_id": joys[device][0]} if joys.has(device) and joys[device][0] != "" else {}

	func get_joy_name(device: int) -> String:
		return joys[device][1] if joys.has(device) else ""

	func has_joy_vibration(device: int) -> bool:
		return vibratable.get(device, false)

	func start_joy_vibration(device: int, weak: float, strong: float, duration: float) -> void:
		calls.append(["joy", device, weak, strong, duration])

	func stop_joy_vibration(device: int) -> void:
		calls.append(["stop", device])

	func vibrate_handheld(ms: int, amplitude: float) -> void:
		calls.append(["handheld", ms, amplitude])


func _pad_button(device: int) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = JOY_BUTTON_A
	ev.pressed = true
	return ev


func _pad_motion(device: int, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.device = device
	ev.axis = JOY_AXIS_LEFT_X
	ev.axis_value = value
	return ev


func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: " + msg)
		failures += 1


func _initialize() -> void:
	InputManagerScript = load("res://addons/godot-core-kit/systems/input_manager.gd")
	var im = InputManagerScript.new()
	var B = im.JoypadBrand

	# 1. brand_from:VID 优先 → 名字关键字 → GENERIC
	var cases := [
		[str(0x045e), "", B.XBOX],
		[str(0x054c), "", B.PLAYSTATION],
		[str(0x057e), "", B.SWITCH],
		["", "Nintendo Switch Joy-Con (L)", B.SWITCH],
		["", "Pro Controller", B.SWITCH],
		["", "DualSense Wireless Controller", B.PLAYSTATION],
		["", "PS4 Controller", B.PLAYSTATION],
		["", "Xbox Series X Controller", B.XBOX],
		["", "XInput Gamepad", B.XBOX],
		["", "Standard Gamepad Mapping", B.GENERIC],
		["", "", B.GENERIC],
		[str(0x054c), "Xbox Wireless Controller", B.PLAYSTATION],  # VID 与名字冲突,以 VID 为准
	]
	for c in cases:
		var got: int = im.brand_from(c[0], c[1])
		_check(got == c[2], "brand_from(%s, %s) 应为 %d,得到 %d" % [c[0], c[1], c[2], got])

	# 2. glyph_key / glyph_text:4 品牌 × 南东西北,外加键盘、鼠标、轴、不支持事件
	var faces := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]
	var expect_keys := {
		B.XBOX: ["xbox/a", "xbox/b", "xbox/x", "xbox/y"],
		B.PLAYSTATION: ["playstation/cross", "playstation/circle", "playstation/square", "playstation/triangle"],
		B.SWITCH: ["switch/b", "switch/a", "switch/y", "switch/x"],
		B.GENERIC: ["generic/south", "generic/east", "generic/west", "generic/north"],
	}
	var expect_text := {
		B.XBOX: ["A", "B", "X", "Y"],
		B.PLAYSTATION: ["✕", "○", "□", "△"],
		B.SWITCH: ["B", "A", "Y", "X"],
		B.GENERIC: ["A", "B", "X", "Y"],
	}
	for brand in expect_keys:
		for i in faces.size():
			var ev := InputEventJoypadButton.new()
			ev.button_index = faces[i]
			_check(im.glyph_key(ev, brand) == expect_keys[brand][i], "glyph_key 品牌 %d 键 %d 应为 %s,得到 %s" % [brand, faces[i], expect_keys[brand][i], im.glyph_key(ev, brand)])
			_check(im.glyph_text(ev, brand) == expect_text[brand][i], "glyph_text 品牌 %d 键 %d 应为 %s,得到 %s" % [brand, faces[i], expect_text[brand][i], im.glyph_text(ev, brand)])
	var a_btn := InputEventJoypadButton.new()
	_check(im.glyph_key(a_btn) == "generic/south", "glyph_key 不传品牌应按 GENERIC")
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	_check(im.glyph_key(space) == "kbm/key_space", "空格键名应为 kbm/key_space,得到 %s" % im.glyph_key(space))
	_check(im.glyph_text(space) == "Space", "空格文字应为 Space,得到 %s" % im.glyph_text(space))
	var jkey := InputEventKey.new()
	jkey.physical_keycode = KEY_J
	_check(im.glyph_key(jkey, B.XBOX) == "kbm/key_j", "键盘键名与品牌无关,应为 kbm/key_j")
	var lmb := InputEventMouseButton.new()
	lmb.button_index = MOUSE_BUTTON_LEFT
	_check(im.glyph_key(lmb) == "kbm/mouse_left", "鼠标左键名应为 kbm/mouse_left,得到 %s" % im.glyph_key(lmb))
	_check(im.glyph_text(lmb) != "", "鼠标左键应有文字兜底")
	var stick_up := InputEventJoypadMotion.new()
	stick_up.axis = JOY_AXIS_LEFT_Y
	stick_up.axis_value = -1.0
	_check(im.glyph_key(stick_up) == "generic/left_stick_up", "左摇杆上应为 generic/left_stick_up,得到 %s" % im.glyph_key(stick_up))
	var lt := InputEventJoypadMotion.new()
	lt.axis = JOY_AXIS_TRIGGER_LEFT
	lt.axis_value = 1.0
	_check(im.glyph_key(lt, B.XBOX) == "xbox/lt", "Xbox 左扳机应为 xbox/lt,得到 %s" % im.glyph_key(lt, B.XBOX))
	_check(im.glyph_text(lt, B.PLAYSTATION) == "L2", "PS 左扳机文字应为 L2,得到 %s" % im.glyph_text(lt, B.PLAYSTATION))
	_check(im.glyph_key(InputEventScreenTouch.new()) == "" and im.glyph_text(InputEventScreenTouch.new()) == "", "不支持事件应返回空串")
	_check(im.glyph_key(null) == "" and im.glyph_text(null) == "", "null 应返回空串")

	im.free()

	# 3. 品牌缓存 + 当前手柄跟踪:joypad_changed 只在当前手柄或其品牌变化时发
	var fake := FakeInput.new()
	fake.joys = {1: [str(0x045e), "Xbox Controller"], 2: ["", "DualSense Wireless Controller"]}
	var jm = InputManagerScript.new()
	jm._input_backend = fake
	jm._refresh_joypads()
	var JB = jm.JoypadBrand
	_check(jm.get_joypad_brand(1) == JB.XBOX, "设备 1 应识别为 XBOX")
	_check(jm.get_joypad_brand(2) == JB.PLAYSTATION, "设备 2 应识别为 PLAYSTATION")
	_check(jm.get_joypad_brand(9) == JB.GENERIC, "未连接设备应为 GENERIC")
	var changes := []
	jm.joypad_changed.connect(func(device: int, brand: int) -> void: changes.append([device, brand]))
	jm._input(_pad_button(1))
	_check(jm.current_joypad == 1 and changes == [[1, JB.XBOX]], "设备 1 按键应发一次 (1, XBOX),实际 %s" % [changes])
	jm._input(_pad_button(1))
	_check(changes.size() == 1, "同一手柄再按不应重发")
	jm._input(_pad_motion(2, 0.1))
	_check(changes.size() == 1 and jm.current_joypad == 1, "门限内的摇杆噪声不应切换当前手柄")
	jm._input(_pad_motion(2, 0.8))
	_check(changes.size() == 2 and changes[1] == [2, JB.PLAYSTATION], "设备 2 推摇杆应发 (2, PLAYSTATION)")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_A
	k.pressed = true
	jm._input(k)
	_check(changes.size() == 2 and jm.current_joypad == 2, "键盘输入不改变当前手柄")
	fake.joys[2] = ["", "Pro Controller"]  # 同一设备号换了手柄
	jm._on_joy_connection_changed(2, true)
	_check(changes.size() == 3 and changes[2] == [2, JB.SWITCH], "当前手柄品牌变化应重发,实际 %s" % [changes])
	fake.joys.erase(1)
	jm._on_joy_connection_changed(1, false)
	_check(jm.get_joypad_brand(1) == JB.GENERIC and changes.size() == 3, "非当前手柄断开只清缓存不发信号")
	jm.free()

	# 4. rumble:clamp、≤0 不做、走手柄还是机身、开关(持久化)
	var rf := FakeInput.new()
	rf.joys = {2: ["", "Xbox Controller"], 3: ["", "Generic"]}
	rf.vibratable = {2: true}
	var rm = InputManagerScript.new()
	rm._input_backend = rf
	rm._refresh_joypads()
	_check(rm.rumble_enabled, "震动开关默认应为开")
	rm._input(_pad_button(2))  # 当前设备 = GAMEPAD,当前手柄 = 2
	rm.rumble(1.5, 0.3)
	_check(rf.calls == [["joy", 2, 1.0, 1.0, 0.3]], "可震手柄应 start_joy_vibration 且 strength 被 clamp 到 1,实际 %s" % [rf.calls])
	rf.calls.clear()
	rm.rumble(0.5, 0.0)
	rm.rumble(0.5, -1.0)
	_check(rf.calls.is_empty(), "duration ≤ 0 应什么都不做(SDL 上 0 等于震 65 秒)")
	rm.rumble(0.5, 0.2, 3)  # 设备 3 不能震 → 回退机身
	_check(rf.calls == [["handheld", 200, 0.5]], "不可震手柄应回退 vibrate_handheld,实际 %s" % [rf.calls])
	rf.calls.clear()
	rm.stop_rumble()
	_check(rf.calls == [["stop", 2]], "stop_rumble 默认停当前手柄,实际 %s" % [rf.calls])
	rf.calls.clear()
	var kk := InputEventKey.new()
	kk.physical_keycode = KEY_A
	kk.pressed = true
	rm._input(kk)  # 当前设备切回键鼠
	rm.rumble(-2.0, 0.1)
	_check(rf.calls == [["handheld", 100, 0.0]], "非手柄输入时应走机身且 strength clamp 到 0,实际 %s" % [rf.calls])
	rf.calls.clear()
	var SettingsScript = load("res://addons/godot-core-kit/core/settings.gd")
	var st = SettingsScript.new()
	st.settings_path = SETTINGS_PATH
	rm.bind_settings(st)
	rm.rumble_enabled = false
	rm.rumble(1.0, 0.5)
	_check(rf.calls.is_empty(), "关闭开关后 rumble 应什么都不做")
	_check(st.get_value("input", "_rumble_enabled") == false, "开关应持久化到 input._rumble_enabled")
	var rm2 = InputManagerScript.new()
	rm2._input_backend = rf
	rm2.bind_settings(st)
	_check(not rm2.rumble_enabled, "重启后应恢复关闭状态")
	rm2.free()
	rm.free()
	st.free()
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)

	# 5. 微信小游戏:机身震动改走 wx.vibrateShort(按强度分档)/ vibrateLong(≥0.2s);手柄不受影响
	var wf := FakeInput.new()
	wf.joys = {2: ["", "Xbox Controller"]}
	wf.vibratable = {2: true}
	var wm = InputManagerScript.new()
	wm._input_backend = wf
	wm._refresh_joypads()
	var wx_calls: Array = []
	wm._wx_vibrate = func(kind: String) -> void: wx_calls.append(kind)
	wm.rumble(0.2, 0.05)
	wm.rumble(0.5, 0.05)
	wm.rumble(1.0, 0.1)
	wm.rumble(0.3, 0.5)
	_check(wx_calls == ["light", "medium", "heavy", "long"], "微信应按强度/时长分档,实际 %s" % [wx_calls])
	_check(wf.calls.is_empty(), "有 wx 时不应再调 vibrate_handheld,实际 %s" % [wf.calls])
	wm._input(_pad_button(2))
	wm.rumble(0.5, 0.3)
	_check(wf.calls == [["joy", 2, 0.5, 0.5, 0.3]] and wx_calls.size() == 4, "可震手柄仍应走手柄")
	wm.free()

	if failures == 0:
		print("test_input_joypad: ALL PASS")
		quit(0)
	else:
		print("test_input_joypad: %d FAILURE(S)" % failures)
		quit(1)
