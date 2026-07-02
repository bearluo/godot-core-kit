# godot-core-kit InputManager 子系统设计

- 日期:2026-07-02
- 状态:已确认,待实现
- 版本目标:0.4.0
- 前置:`2026-07-02-corekit-facade-design.md`(总纲;门面属性 `CoreKit.input`)、`2026-07-02-settings-design.md`(持久化依赖)

---

## 目标与定位

`InputManager` 在 Godot 原生 `InputMap`/`Input` 之上补三块 2D 游戏刚需:**键位重绑定 + 持久化**、**输入设备检测**(键鼠/手柄/触屏切换,UI 换提示图标)、**输入缓冲**(平台跳跃/连招的前缓冲)。

定位边界:动作(action)本身仍在工程的 Input Map 里定义,本子系统不发明第二套动作系统;不做 coyote time(那是游戏层跳跃逻辑)、不做组合键/长按短按语义、不做多玩家分设备路由。

## Public API(GDScript 精确签名)

```gdscript
extends Node
## InputManager —— 重绑定持久化 + 设备检测 + 输入缓冲。

enum DeviceType { KEYBOARD_MOUSE, GAMEPAD, TOUCH }

## 输入来源设备变化时广播(仅在变化时,不逐事件)。
signal device_changed(device_type: DeviceType)

## 某动作被重绑定/重置后广播。
signal action_rebound(action: String)

var current_device: DeviceType = DeviceType.KEYBOARD_MOUSE

## 由 CoreKit._ready 注入 Settings:恢复已保存的键位覆盖并持有引用。
## 未注入时重绑定仍生效,只是不持久化。
func bind_settings(settings) -> void

## 把 action 的绑定替换为单个 event(清掉原有全部 events)。
## action 不存在于 InputMap → CoreKit.log.warn + 返回 false。
func rebind_action(action: String, event: InputEvent) -> bool

## 恢复 action / 全部动作到工程默认(启动时快照),并清除持久化覆盖。
func reset_action(action: String) -> void
func reset_all() -> void

## 取 action 当前第一个绑定事件(UI 显示用);无绑定/未知 action 返回 null。
func get_action_event(action: String) -> InputEvent

## action 在最近 window_sec 秒内是否被按下过(前缓冲)。
func is_action_buffered(action: String, window_sec: float) -> bool

## 清除 action 的缓冲时间戳(命中后调用,防一次按键触发两次)。
func consume_buffer(action: String) -> void
```

## Behavior & data flow

- **默认快照**:`_ready` 时对 `InputMap.get_actions()` 逐动作深拷贝 events 存 `_defaults`(含 `ui_*`,反正只是快照);同时缓存动作名列表 `_actions` 供缓冲扫描。
- **重绑定**:`rebind_action` = `action_erase_events` + `action_add_event`;成功后若已 bind settings,写 `settings.set_value("input", action, _event_to_dict(event))`,并 `emit action_rebound`。`reset_*` 恢复快照 + `settings.erase_value("input", action)`。
- **持久化格式**(`_event_to_dict` / `_dict_to_event` 纯函数接缝):

```gdscript
# InputEventKey          → {"type": "key", "physical_keycode": int}
# InputEventMouseButton  → {"type": "mouse_button", "button_index": int}
# InputEventJoypadButton → {"type": "joypad_button", "button_index": int}
# InputEventJoypadMotion → {"type": "joypad_motion", "axis": int, "axis_value": float}
# 不支持的事件类型 → {}(rebind 返回 false);_dict_to_event 对畸形输入返回 null
```

  键盘用 `physical_keycode`(布局无关,换键盘布局绑定仍在物理同位)。`bind_settings` 恢复时逐条 `_dict_to_event`,null(损坏)则跳过该条并 `push_warning`,不影响其余。
- **设备检测**:`_input(event)` 按事件类型归类——Key/MouseButton/MouseMotion → KEYBOARD_MOUSE;JoypadButton → GAMEPAD;JoypadMotion 需 `abs(axis_value) > 0.2`(摇杆漂移噪声门限)才算;ScreenTouch/ScreenDrag → TOUCH。归类结果 ≠ `current_device` 时更新并广播。
- **输入缓冲**:`_input(event)` 里对 `_actions` 逐个 `event.is_action_pressed(action)` 判命中,命中记 `_last_pressed_msec[action] = Time.get_ticks_msec()`。`is_action_buffered` = `(now - last) <= window_sec * 1000.0`。时钟经 `_ticks_msec_func: Callable` 接缝注入(测试假时钟)。动作数量级 ~几十,逐事件线性扫可接受。

## Key decisions

| # | 维度 | 结论 | 理由 |
|---|---|---|---|
| 1 | 重绑定语义 | 整体替换为单事件 | 多绑定槽(主/副键位)是 YAGNI;替换语义最不易出"幽灵旧绑定" |
| 2 | 键盘序列化 | physical_keycode | 布局无关;国际键盘用户换布局不丢绑定 |
| 3 | 缓冲采集 | `_input` 全动作扫描 + 时间戳 | 无需注册 watch;动作数小,代价可忽略 |
| 4 | 缓冲消费 | 显式 `consume_buffer` | "跳跃命中即清"必须由游戏逻辑决定时机,自动清会踩连招场景 |
| 5 | 摇杆噪声 | JoypadMotion 0.2 门限 | 漂移手柄会把设备检测锁死在 GAMEPAD |
| 6 | Settings 依赖 | `bind_settings` 注入,未注入降级不持久化 | 可脱离门面单测;依赖表纪律 |

## Web-export considerations

全同步、零线程、零文件 IO(落盘经 Settings);键鼠/触屏事件 Web 原生支持,手柄走浏览器 Gamepad API(Godot 封装,行为一致)。`Time.get_ticks_msec` 全平台可用。

## Testable seams + test plan

接缝:`_event_to_dict`/`_dict_to_event` 纯函数;`_ticks_msec_func` 假时钟;`_input(event)` 可直接手工构造 InputEvent 调用(不需要真实硬件);InputMap 在 headless 下完全可编程(`add_action`/`action_add_event`)。测试自建临时 action,结束清理。

`test/test_input_manager.gd`(headless,直接实例化):

1. `_event_to_dict`/`_dict_to_event` 四种事件类型往返;不支持类型 → `{}`;畸形 dict → null。
2. `rebind_action`:InputMap 里旧 events 被清、新 event 生效;`action_rebound` 广播;未知 action 返回 false。
3. `reset_action`/`reset_all`:恢复到快照默认。
4. 持久化:bind 一个真 Settings 实例,rebind → settings 里出现覆盖;重建 InputManager + bind 同一 Settings → 覆盖被恢复到 InputMap;reset 后覆盖消失。
5. 损坏覆盖:settings 里手塞畸形 dict,bind 时跳过不崩,其余覆盖正常恢复。
6. 设备检测:依次喂 Key/JoypadButton/ScreenTouch 事件,`device_changed` 按变化广播且 `current_device` 正确;JoypadMotion axis_value 0.1 不切换、0.5 切换。
7. 缓冲:假时钟下按下后 window 内 `is_action_buffered` 为 true、超窗为 false;`consume_buffer` 后立即 false;未按过的 action 为 false。

## 版本

InputManager v0.4.0 起:重绑定 + Settings 持久化(physical_keycode)、设备检测信号、输入前缓冲。依赖:log(运行期)、settings(注入)。
