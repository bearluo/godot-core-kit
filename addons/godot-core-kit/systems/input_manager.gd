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
## 绑定槽在存档里的 key(固定字符串,调整枚举不影响存档)。
const SLOT_KEYS := {DeviceType.KEYBOARD_MOUSE: "kbm", DeviceType.GAMEPAD: "gamepad"}
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
		var overrides := _decode_overrides(stored)
		for slot in overrides:
			var dict = overrides[slot]
			if dict == null:
				_clear_slot(action_name, slot)
				continue
			var event := _dict_to_event(dict)
			if event == null or slot_of(event) != slot:
				push_warning("InputManager: 动作 '%s' 的 %s 槽覆盖损坏,已跳过" % [action_name, SLOT_KEYS[slot]])
				continue
			_apply_binding(action_name, event)


## 把 event 所在槽的绑定替换为这一个事件并持久化,另一个槽不受影响。
## action 不存在 / 事件类型不支持 → CoreKit.log.warn + false。
func rebind_action(action: String, event: InputEvent) -> bool:
	if not InputMap.has_action(action):
		CoreKit.log.warn("InputManager: 动作 '%s' 不存在于 InputMap,忽略重绑定" % action)
		return false
	var encoded := _event_to_dict(event)
	if encoded.is_empty():
		CoreKit.log.warn("InputManager: 不支持的事件类型 %s,忽略重绑定" % event.get_class())
		return false
	# 经序列化格式走一遍:本局生效的事件与重启后恢复的完全一致(device=-1、无修饰键)。
	var normalized := _dict_to_event(encoded)
	_apply_binding(action, normalized)
	_write_override(action, slot_of(normalized), encoded)
	action_rebound.emit(action)
	return true


## 清空 action 的一个槽并持久化「清空」(存 null,重启后仍为空)。
## 未知动作 / 非绑定槽 → false。
func unbind_action(action: String, device: int) -> bool:
	if not InputMap.has_action(action) or not SLOT_KEYS.has(device):
		return false
	_clear_slot(action, device)
	_write_override(action, device, null)
	action_rebound.emit(action)
	return true


## 恢复 action 到工程默认(启动时快照)并清除持久化覆盖。
## device = -1 整个动作复位;传槽(DeviceType)则只复位该槽。
func reset_action(action: String, device := -1) -> void:
	if not _defaults.has(action):
		return
	if device == -1:
		InputMap.action_erase_events(action)
	else:
		_clear_slot(action, device)
	for ev in _defaults[action]:
		if device == -1 or slot_of(ev) == device:
			InputMap.action_add_event(action, ev.duplicate())
	if device == -1:
		if _settings != null:
			_settings.erase_value(SETTINGS_SECTION, action)
	else:
		_write_override(action, device, null, true)
	action_rebound.emit(action)


func reset_all() -> void:
	for action in _defaults.keys():
		reset_action(action)


## 取 action 当前第一个绑定事件(UI 显示用);无绑定/未知 action 返回 null。
## device = -1 不分槽;传槽(DeviceType)则只在该槽里找,空槽返回 null。
func get_action_event(action: String, device := -1) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for ev in InputMap.action_get_events(action):
		if device == -1 or slot_of(ev) == device:
			return ev
	return null


## 返回当前占用该事件的动作名;among 空=扫全部动作,否则只扫子集;无占用返回 ""。
## 复用 _event_to_dict 做结构相等比较(键盘按 physical_keycode 等)。供重绑 UI 判冲突。
func action_for_event(event: InputEvent, among := PackedStringArray()) -> String:
	var target := _event_to_dict(event)
	if target.is_empty():
		return ""
	var scan: Array = Array(among) if among.size() > 0 else InputMap.get_actions()
	for action in scan:
		if not InputMap.has_action(action):
			continue
		for ev in InputMap.action_get_events(action):
			if _event_to_dict(ev) == target:
				return String(action)
	return ""


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


## 事件所属绑定槽:键盘/鼠标按键 → KEYBOARD_MOUSE,手柄按键/轴 → GAMEPAD;
## 不可绑定的事件(触屏、鼠标移动等)返回 -1。
func slot_of(event: InputEvent) -> int:
	if event is InputEventKey or event is InputEventMouseButton:
		return DeviceType.KEYBOARD_MOUSE
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return DeviceType.GAMEPAD
	return -1


## 只替换 event 所在槽的绑定,另一个槽原样保留。
func _apply_binding(action: String, event: InputEvent) -> void:
	_clear_slot(action, slot_of(event))
	# duplicate() 防止 InputMap 持有调用方传入的同一个 InputEvent 引用(别名)。
	InputMap.action_add_event(action, event.duplicate())


func _clear_slot(action: String, slot: int) -> void:
	for ev in InputMap.action_get_events(action):
		if slot_of(ev) == slot:
			InputMap.action_erase_event(action, ev)


## 存档值 → {槽: 事件 dict | null}。新格式 {"kbm":…, "gamepad":…};
## 旧格式(带 "type" 的单事件 dict)归到它解码后所在的槽,解不出则为空表。
func _decode_overrides(stored: Dictionary) -> Dictionary:
	var out := {}
	if stored.has("type"):
		var legacy := _dict_to_event(stored)
		if legacy == null:
			push_warning("InputManager: 旧格式键位覆盖损坏(无法解码),已跳过")
		else:
			out[slot_of(legacy)] = stored
		return out
	for slot in SLOT_KEYS:
		if stored.has(SLOT_KEYS[slot]):
			out[slot] = stored[SLOT_KEYS[slot]]
	return out


## 写一个槽的覆盖(value 为事件 dict 或 null=显式清空);erase=true 则删掉该槽的覆盖记录。
## 旧格式在这里顺带转成新格式。
func _write_override(action: String, slot: int, value, erase := false) -> void:
	if _settings == null:
		return
	var stored = _settings.get_value(SETTINGS_SECTION, action)
	var overrides := _decode_overrides(stored) if typeof(stored) == TYPE_DICTIONARY else {}
	if erase:
		overrides.erase(slot)
	else:
		overrides[slot] = value
	if overrides.is_empty():
		_settings.erase_value(SETTINGS_SECTION, action)
		return
	var out := {}
	for s in overrides:
		out[SLOT_KEYS[s]] = overrides[s]
	_settings.set_value(SETTINGS_SECTION, action, out)


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


## 解出的事件 device 统一为 -1(任意设备):InputEvent.device 默认 0,
## 不规范化的话改过的手柄键只认 0 号手柄。
func _dict_to_event(dict: Dictionary) -> InputEvent:
	var ev := _decode_event(dict)
	if ev != null:
		ev.device = -1
	return ev


func _decode_event(dict: Dictionary) -> InputEvent:
	match dict.get("type"):
		"key":
			if typeof(dict.get("physical_keycode")) not in [TYPE_INT, TYPE_FLOAT]:
				return null
			var ev_key := InputEventKey.new()
			ev_key.physical_keycode = int(dict["physical_keycode"])
			return ev_key
		"mouse_button":
			if typeof(dict.get("button_index")) not in [TYPE_INT, TYPE_FLOAT]:
				return null
			var ev_mouse := InputEventMouseButton.new()
			ev_mouse.button_index = int(dict["button_index"])
			return ev_mouse
		"joypad_button":
			if typeof(dict.get("button_index")) not in [TYPE_INT, TYPE_FLOAT]:
				return null
			var ev_joy_btn := InputEventJoypadButton.new()
			ev_joy_btn.button_index = int(dict["button_index"])
			return ev_joy_btn
		"joypad_motion":
			if typeof(dict.get("axis")) not in [TYPE_INT, TYPE_FLOAT] or typeof(dict.get("axis_value")) not in [TYPE_INT, TYPE_FLOAT]:
				return null
			var ev_joy_motion := InputEventJoypadMotion.new()
			ev_joy_motion.axis = int(dict["axis"])
			ev_joy_motion.axis_value = float(dict["axis_value"])
			return ev_joy_motion
	return null
