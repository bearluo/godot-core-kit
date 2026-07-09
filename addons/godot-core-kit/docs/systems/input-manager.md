# InputManager —— 重绑定持久化 + 设备检测 + 输入前缓冲

> `CoreKit.input` · `systems/input_manager.gd`

## 职责

动作(action)仍在工程 Input Map 里定义,本子系统不发明第二套动作系统,只补三件事:① `rebind_action` 运行时改 `InputMap` 并经注入的 Settings 持久化(section `"input"`,key 为动作名),`bind_settings` 时恢复;② `device_changed` 在输入来源设备(键鼠/手柄/触屏)变化时广播,供 UI 切换按键图标;③ `is_action_buffered` 前缓冲,`_input` 里记录动作按下时间戳,窗口期内查询是否按下过。coyote time、组合键、多绑定槽、多玩家路由均不在 v1 范围。

## 公开 API

```gdscript
enum DeviceType { KEYBOARD_MOUSE, GAMEPAD, TOUCH }

signal device_changed(device_type: DeviceType)   # 输入设备变化时广播(仅变化时,不逐事件)
signal action_rebound(action: String)            # 某动作被重绑定/重置后广播

func bind_settings(settings) -> void             # 注入 Settings:恢复已保存的键位覆盖并持有引用供后续 rebind 写回
func rebind_action(action: String, event: InputEvent) -> bool  # 整体替换 action 绑定为单个 event 并持久化;action 不存在/事件类型不支持则 warn + false
func reset_action(action: String) -> void        # 恢复 action 到工程默认(启动时快照)并清除持久化覆盖
func reset_all() -> void                         # 对全部动作执行 reset_action
func get_action_event(action: String) -> InputEvent  # 取 action 当前第一个绑定事件(UI 显示用);无绑定/未知 action 返回 null
func is_action_buffered(action: String, window_sec: float) -> bool  # action 在最近 window_sec 秒内是否被按下过
func consume_buffer(action: String) -> void      # 清除 action 的缓冲时间戳(命中后调用,防一次按键触发两次)

var current_device: int = DeviceType.KEYBOARD_MOUSE   # 当前检测到的输入设备
var _ticks_msec_func: Callable = Time.get_ticks_msec  # 测试接缝:缓冲计时经此取时,测试可注入假时钟
```

## 依赖

被门面经 `input.bind_settings(settings)` 注入 `Settings` 引用,用于把键位覆盖落盘到 `section "input"`。未注入时 `_settings` 为 `null`——`rebind_action`/`reset_action` 仍会即时生效于 `InputMap`,只是不会持久化,适用于脱离门面的单测或不需要持久化的消费方。

## 用法示例

```gdscript
# 重绑定"跳跃"动作为空格键
var ev := InputEventKey.new()
ev.physical_keycode = KEY_SPACE
CoreKit.input.rebind_action("jump", ev)

# 恢复工程默认键位
CoreKit.input.reset_action("jump")

# 监听设备切换(如换手柄按键图标)
CoreKit.input.device_changed.connect(func(device_type):
    update_prompt_icons(device_type))

# 输入前缓冲:落地前提前按跳跃也算数
func _on_landed() -> void:
    if CoreKit.input.is_action_buffered("jump", 0.15):
        CoreKit.input.consume_buffer("jump")
        do_jump()
```

## 注意事项

- 动作仍在工程 Input Map 定义,本子系统不发明第二套动作系统;v1 不支持 coyote time、组合键、多绑定槽、多玩家路由。
- 摇杆漂移噪声门限 `MOTION_DEADZONE = 0.2`:`InputEventJoypadMotion` 幅值低于此值不算"玩家在用手柄",避免摇杆静止漂移误判成设备切换。
- 键盘重绑定与序列化用 `physical_keycode`(布局无关),换键盘布局后绑定仍落在物理同一位置。
- `_snapshot_defaults()` 必须在应用任何覆盖之前调用才能拿到正确的工程默认键位;`_ready` 会自动调用,脱离场景树的测试需手动调用一次。
- 持久化覆盖条目损坏(非 dict / 无法解码)时,`bind_settings` 逐条跳过并 `push_warning`,不影响其余动作恢复。
- 前缓冲是全动作线性扫描(`_actions` 在快照默认键位时固定),动作数量级约几十,代价可忽略;**启动后新增的动作不在扫描列表内**。
- `rebind_action` 对不存在的 action 或不支持的事件类型返回 `false` 并 `CoreKit.log.warn`,不抛异常。
