# InputManager 子系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现输入子系统 InputManager(重绑定 + Settings 持久化、设备检测信号、输入前缓冲)。

**Architecture:** 见 spec `docs/superpowers/specs/2026-07-02-input-manager-design.md`。单文件 Node;依赖 Settings(波 1 已交付,经 `bind_settings()` 注入);门面接线留给集成任务。

**Tech Stack:** Godot 4.7 / 纯 GDScript / headless `-s` 断言测试(手工构造 InputEvent、假时钟、临时 InputMap 动作)

## Global Constraints

- 分支:全部工作在 `feat/framework-v0.4` 上(从 main 切出);线性历史,不得产生 merge commit。
- 纯 GDScript、Tab 缩进;无 C#、无 GDExtension、无第三方依赖;命令行 `godot` 已在 PATH。
- Web 导出兼容:禁用线程/平台专属 API。
- 依赖纪律:仅 `CoreKit.log.warn`(运行期)与注入的 Settings(未注入时降级不持久化,`if _settings != null` 守卫);初始化期诊断用 `push_warning`。
- 测试纪律(`-s` 避坑手册):`-s` 主脚本不得在类作用域 preload 任何引用 `CoreKit` 全局的脚本(`_initialize()` 内运行时 `load()`);untyped 值的下游变量显式标注类型(不用 `:=`);测试无论成败必须到达 `quit()`。
- 运行测试用硬超时模板(PowerShell,单测 60s 上限):

```powershell
$p = Start-Process godot -ArgumentList '--headless','--path','.','-s','res://test/test_input_manager.gd' -RedirectStandardOutput "$env:TEMP\gck-out.txt" -RedirectStandardError "$env:TEMP\gck-err.txt" -PassThru -NoNewWindow; if (-not $p.WaitForExit(60000)) { $p.Kill(); 'TIMEOUT(疑似测试报错未达 quit)' }; Get-Content "$env:TEMP\gck-out.txt"
```

- git 提交消息不得含英文双引号(PowerShell here-string 坑)。

---

### Task 1: InputManager 核心

**Files:**
- Create: `addons/godot-core-kit/input_manager.gd`
- Test: `test/test_input_manager.gd`

**Interfaces:**
- Consumes: Settings 实例(波 1):`get_value(section, key, default=null) -> Variant`、`set_value(section, key, value) -> void`、`erase_value(section, key) -> void`;`CoreKit.log.warn(msg: String)`。
- Produces: `enum DeviceType { KEYBOARD_MOUSE, GAMEPAD, TOUCH }`;`signal device_changed(device_type)`、`signal action_rebound(action: String)`;`var current_device: int`;`bind_settings(settings) -> void`;`rebind_action(action: String, event: InputEvent) -> bool`;`reset_action(action) -> void`;`reset_all() -> void`;`get_action_event(action) -> InputEvent`;`is_action_buffered(action: String, window_sec: float) -> bool`;`consume_buffer(action) -> void`;接缝 `_event_to_dict(event) -> Dictionary`、`_dict_to_event(dict) -> InputEvent`、`_snapshot_defaults() -> void`、`var _ticks_msec_func: Callable`、`var _settings`。集成任务将调用 `CoreKit.input.bind_settings(CoreKit.settings)`。

- [ ] **Step 1: 写失败测试 test/test_input_manager.gd**

```gdscript
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
```

- [ ] **Step 2: 跑测试确认失败**

用 Global Constraints 的硬超时模板运行。Expected: 报错退出,退出码非 0。

- [ ] **Step 3: 实现 addons/godot-core-kit/input_manager.gd**

```gdscript
extends Node
## InputManager —— 重绑定持久化 + 设备检测 + 输入前缓冲。
##
## 动作(action)仍在工程 Input Map 里定义,本子系统不发明第二套动作系统:
## ① rebind_action 运行时改 InputMap 并经注入的 Settings 持久化(section
##    "input",key 为动作名,value 为事件序列化 dict),bind_settings 时恢复;
## ② device_changed 在输入来源设备(键鼠/手柄/触屏)变化时广播,UI 换图标用;
## ③ is_action_buffered 前缓冲:_input 里记录动作按下时间戳(全动作线性扫,
##    动作数量级 ~几十,代价可忽略;启动后新增的动作不在扫描列表内)。
## coyote time、组合键、多绑定槽、多玩家路由均不在 v1 范围。

enum DeviceType { KEYBOARD_MOUSE, GAMEPAD, TOUCH }

## 输入来源设备变化时广播(仅变化时,不逐事件)。
signal device_changed(device_type: DeviceType)

## 某动作被重绑定/重置后广播。
signal action_rebound(action: String)

const SETTINGS_SECTION := "input"
## 摇杆漂移噪声门限:JoypadMotion 低于此幅值不算"玩家在用手柄"。
const MOTION_DEADZONE := 0.2

var current_device: int = DeviceType.KEYBOARD_MOUSE

## bind_settings 注入;untyped:未注入(脱离门面单测/消费方不持久化)时为 null。
var _settings = null
var _defaults: Dictionary = {}          # action(String) -> Array[InputEvent] 深拷贝快照
var _actions: Array = []                # 缓冲扫描用的动作名列表(StringName)
var _last_pressed_msec: Dictionary = {} # action(String) -> 按下时刻(msec)
## 测试接缝:缓冲计时经此取时,测试注入假时钟。
var _ticks_msec_func: Callable = Time.get_ticks_msec


func _ready() -> void:
	_snapshot_defaults()


## 快照工程默认键位(须在应用任何覆盖之前调用;_ready 自动调,
## 脱离场景树的测试手动调)。
func _snapshot_defaults() -> void:
	_actions = InputMap.get_actions()
	_defaults.clear()
	for action in _actions:
		var events := []
		for ev in InputMap.action_get_events(action):
			events.append(ev.duplicate())
		_defaults[String(action)] = events


## 注入 Settings:恢复已保存的键位覆盖并持有引用(后续 rebind 写回)。
## 损坏的覆盖条目逐条跳过(push_warning),不影响其余。
func bind_settings(settings) -> void:
	_settings = settings
	if _settings == null:
		return
	for action_name in _defaults.keys():
		var stored = _settings.get_value(SETTINGS_SECTION, action_name)
		if stored == null:
			continue
		if typeof(stored) != TYPE_DICTIONARY:
			push_warning("InputManager: 动作 '%s' 的键位覆盖损坏(非 dict),已跳过" % action_name)
			continue
		var event := _dict_to_event(stored)
		if event == null:
			push_warning("InputManager: 动作 '%s' 的键位覆盖损坏(无法解码),已跳过" % action_name)
			continue
		_apply_binding(action_name, event)


## 把 action 的绑定整体替换为单个 event 并持久化。
## action 不存在 / 事件类型不支持 → CoreKit.log.warn + false。
func rebind_action(action: String, event: InputEvent) -> bool:
	if not InputMap.has_action(action):
		CoreKit.log.warn("InputManager: 动作 '%s' 不存在于 InputMap,忽略重绑定" % action)
		return false
	var encoded := _event_to_dict(event)
	if encoded.is_empty():
		CoreKit.log.warn("InputManager: 不支持的事件类型 %s,忽略重绑定" % event.get_class())
		return false
	_apply_binding(action, event)
	if _settings != null:
		_settings.set_value(SETTINGS_SECTION, action, encoded)
	action_rebound.emit(action)
	return true


## 恢复 action 到工程默认(启动时快照)并清除持久化覆盖。
func reset_action(action: String) -> void:
	if not _defaults.has(action):
		return
	InputMap.action_erase_events(action)
	for ev in _defaults[action]:
		InputMap.action_add_event(action, ev.duplicate())
	if _settings != null:
		_settings.erase_value(SETTINGS_SECTION, action)
	action_rebound.emit(action)


func reset_all() -> void:
	for action in _defaults.keys():
		reset_action(action)


## 取 action 当前第一个绑定事件(UI 显示用);无绑定/未知 action 返回 null。
func get_action_event(action: String) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return null
	return events[0]


## action 在最近 window_sec 秒内是否被按下过(前缓冲)。
func is_action_buffered(action: String, window_sec: float) -> bool:
	if not _last_pressed_msec.has(action):
		return false
	var now: int = _ticks_msec_func.call()
	return now - int(_last_pressed_msec[action]) <= int(window_sec * 1000.0)


## 清除 action 的缓冲时间戳(命中后调用,防一次按键触发两次跳跃)。
func consume_buffer(action: String) -> void:
	_last_pressed_msec.erase(action)


func _input(event: InputEvent) -> void:
	_update_device(event)
	_record_buffer(event)


func _apply_binding(action: String, event: InputEvent) -> void:
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)


func _update_device(event: InputEvent) -> void:
	var detected: int = -1
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		detected = DeviceType.KEYBOARD_MOUSE
	elif event is InputEventJoypadButton:
		detected = DeviceType.GAMEPAD
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > MOTION_DEADZONE:
			detected = DeviceType.GAMEPAD
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		detected = DeviceType.TOUCH
	if detected != -1 and detected != current_device:
		current_device = detected
		device_changed.emit(current_device)


func _record_buffer(event: InputEvent) -> void:
	for action in _actions:
		if event.is_action_pressed(action):
			_last_pressed_msec[String(action)] = _ticks_msec_func.call()


## --- 可测接缝(纯函数):InputEvent <-> JSON 可存 dict ---
## 键盘用 physical_keycode(布局无关,换键盘布局绑定仍在物理同位)。

func _event_to_dict(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {"type": "key", "physical_keycode": int(event.physical_keycode)}
	if event is InputEventMouseButton:
		return {"type": "mouse_button", "button_index": int(event.button_index)}
	if event is InputEventJoypadButton:
		return {"type": "joypad_button", "button_index": int(event.button_index)}
	if event is InputEventJoypadMotion:
		return {"type": "joypad_motion", "axis": int(event.axis), "axis_value": float(event.axis_value)}
	return {}


func _dict_to_event(dict: Dictionary) -> InputEvent:
	match dict.get("type"):
		"key":
			if typeof(dict.get("physical_keycode")) not in [TYPE_INT, TYPE_FLOAT]:
				return null
			var ev := InputEventKey.new()
			ev.physical_keycode = int(dict["physical_keycode"])
			return ev
		"mouse_button":
			if typeof(dict.get("button_index")) not in [TYPE_INT, TYPE_FLOAT]:
				return null
			var ev := InputEventMouseButton.new()
			ev.button_index = int(dict["button_index"])
			return ev
		"joypad_button":
			if typeof(dict.get("button_index")) not in [TYPE_INT, TYPE_FLOAT]:
				return null
			var ev := InputEventJoypadButton.new()
			ev.button_index = int(dict["button_index"])
			return ev
		"joypad_motion":
			if typeof(dict.get("axis")) not in [TYPE_INT, TYPE_FLOAT] or typeof(dict.get("axis_value")) not in [TYPE_INT, TYPE_FLOAT]:
				return null
			var ev := InputEventJoypadMotion.new()
			ev.axis = int(dict["axis"])
			ev.axis_value = float(dict["axis_value"])
			return ev
	return null
```

注意:`match` 各分支里的 `var ev` 同名——GDScript 的 match 分支各自成作用域,合法;若解析器报重复声明,改成 `ev_key`/`ev_mouse` 等不同名即可,行为不变。

- [ ] **Step 4: 跑测试确认全绿**

同 Step 2 命令。Expected: `test_input_manager: ALL PASS`,退出码 0。

- [ ] **Step 5: 提交**

```powershell
git add addons/godot-core-kit/input_manager.gd test/test_input_manager.gd
git commit -m 'feat: add InputManager core (rebind persistence, device detection, input buffer)'
```
