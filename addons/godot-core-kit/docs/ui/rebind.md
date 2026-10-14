# 键位重绑定 UI(KitRebindButton / KitRebindList)

> `class_name KitRebindButton` / `KitRebindList` · `ui/rebind_button.gd` / `ui/rebind_list.gd` · off-facade 可复用 UI 组件(不挂门面)

## 职责

可复用的游戏内键位重绑定 UI。`KitRebindButton` 一个动作一个按钮:点击 → 按新键捕获 → 冲突检测(默认拦截,可选互换)→ 落到 `CoreKit.input.rebind_action`(只替换该槽 + 持久化 Settings)。按钮可以只负责键盘或只负责手柄一个槽。`KitRebindList` 吃动作清单一次性建「键盘 | 手柄」两列的列表 + 全部复位。组件只管 UI + 捕获 + 冲突判定,重绑/复位/持久化复用 InputManager。audio 音量、locale 切换是一行绑定的琐碎活,自己拼即可(见 demo)。

## 公开 API

### KitRebindButton(extends Button)

| 成员 | 说明 |
|---|---|
| `setup(action, conflict_scope := PackedStringArray(), input_manager = null, device := -1)` | 绑定动作;`input_manager` 省略用 `CoreKit.input`;`conflict_scope` 空=冲突扫全部动作,否则只在子集内判。`device` 传 `InputManager.DeviceType.KEYBOARD_MOUSE` / `GAMEPAD` 时只负责该槽:捕获只收该槽的事件(异槽事件忽略,不报错也不退出捕获),显示和复位也只针对该槽;`-1` 不分槽(0.24 行为)。 |
| `conflict_mode` | `ConflictMode.BLOCK`(默认)冲突时拒绝;`SWAP` 把冲突动作的该槽换成本动作原来的键,本动作该槽原来为空则清空对方该槽。 |
| `begin_capture()` | 进捕获态(点击自动触发):提示「按任意键…」+ 抢焦点。 |
| `capture_event(event) -> bool` | 处理候选事件(真实输入与测试共用的种子)。Esc→取消;不支持类型→`unsupported`;冲突且 BLOCK→`conflict:<other>` 且不改绑定;否则重绑(SWAP 时先处理对方)。 |
| `cancel_capture()` | 取消捕获(编程/UI)。 |
| `refresh()` | 文字=当前绑定的 `InputManager.glyph_text`(按当前手柄品牌,如 "A" / "✕" / "Space"),无绑定显「未绑定」。 |
| `reset()` | 复位到工程默认(分槽时只复位该槽)+ 刷新。 |
| `signal rebound(action, event)` / `signal rebind_failed(action, reason)` | reason ∈ `conflict:<other>` / `unsupported` / `cancelled`。 |

捕获类型:Key / MouseButton / JoypadButton(忽略摇杆轴);Esc 取消。

### KitRebindList(extends VBoxContainer)

| 成员 | 说明 |
|---|---|
| `setup(rows, input_manager = null, devices := [0, 1])` | `rows=[{action, label}, ...]`;每行 `[Label \| 键盘列 \| 手柄列 \| 复位]` + 底部「全部复位」;行复位复位整行两个槽;各按钮 `conflict_scope`=全部行动作。`devices` 选显示哪些列(值为 `InputManager.DeviceType`,如纯键盘游戏传 `[0]`)。 || KitRebindButton \| 复位]` + 底部「全部复位」;各按钮 `conflict_scope`=全部行动作。 |
| `refresh_all()` | 刷新所有子按钮。 |
| `signal rebound / rebind_failed` | 转发各子按钮信号。 |

## 依赖

- 消费 `CoreKit.input`(`InputManager`)的 `action_for_event`/`rebind_action`/`reset_action`/`get_action_event`。**零门面耦合**:失败经 `rebind_failed` 信号上报(不引 `CoreKit.log`),对 `CoreKit.input` 的默认解析可注入 standalone InputManager 绕开(headless 单测)。off-facade:不挂门面,`.new()`+`add_child` 即用。

## 用法示例

```gdscript
# 一次性列表(推荐)
var list := KitRebindList.new()
add_child(list)
list.setup([
    {"action": "move_left",  "label": "左移"},
    {"action": "move_right", "label": "右移"},
    {"action": "jump",       "label": "跳跃"},
])
list.rebind_failed.connect(func(a, r): if r.begins_with("conflict:"): $Toast.show("已被占用"))

# 单个按钮
var btn := KitRebindButton.new()
add_child(btn)
btn.setup("jump", PackedStringArray(["jump", "attack"]))

# audio / locale 是一行绑定,自己拼(无需组件):
$VolumeSlider.value_changed.connect(func(v): CoreKit.audio.set_volume("master", v))
$LocaleOption.item_selected.connect(func(i): CoreKit.i18n.set_locale(locales[i]))
```

## 注意事项

- **冲突范围**:`conflict_scope` 决定冲突只在哪些动作间判——`KitRebindList` 自动传全部行(避免「Space 撞 ui_accept」误报)。单用 `KitRebindButton` 时自己传可重绑集合。
- **同键重绑自身**:把动作重绑到它当前已有的键 → 放行(成功、等价 no-op)。
- **持久化**:重绑经 `InputManager.rebind_action` 写 Settings section `input`;下次启动 `bind_settings` 恢复。复位清除覆盖。
- **冲突只在同槽里发生**:键盘键只会和键盘键撞,手柄键只会和手柄键撞。
- **SWAP 的回滚**:如果本动作的重绑失败(比如动作不在 InputMap 里),对方会拿回原来的键,然后发 `rebind_failed`。
- **范围外**:摇杆轴当按键、多个副槽、组合键、多玩家分手柄。
