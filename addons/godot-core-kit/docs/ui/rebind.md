# 键位重绑定 UI(KitRebindButton / KitRebindList)

> `class_name KitRebindButton` / `KitRebindList` · `ui/rebind_button.gd` / `ui/rebind_list.gd` · off-facade 可复用 UI 组件(不挂门面)

## 职责

可复用的游戏内键位重绑定 UI。`KitRebindButton` 一个动作一个按钮:点击 → 按新键捕获 → 冲突检测(检测+拦截)→ 落到 `CoreKit.input.rebind_action`(替换 InputMap + 持久化 Settings)。`KitRebindList` 吃动作清单一次性建列表 + 全部复位。组件只管 UI + 捕获 + 冲突判定,重绑/复位/持久化复用 InputManager。audio 音量、locale 切换是一行绑定的琐碎活,自己拼即可(见 demo)。

## 公开 API

### KitRebindButton(extends Button)

| 成员 | 说明 |
|---|---|
| `setup(action, conflict_scope := PackedStringArray(), input_manager = null)` | 绑定动作;`input_manager` 省略用 `CoreKit.input`;`conflict_scope` 空=冲突扫全部动作,否则只在子集内判。 |
| `begin_capture()` | 进捕获态(点击自动触发):提示「按任意键…」+ 抢焦点。 |
| `capture_event(event) -> bool` | 处理候选事件(真实输入与测试共用的种子)。Esc→取消;不支持类型→`unsupported`;冲突→`conflict:<other>` 且不改绑定;否则重绑成功。 |
| `cancel_capture()` | 取消捕获(编程/UI)。 |
| `refresh()` | 文字=当前绑定 `as_text()`,无绑定显「未绑定」。 |
| `reset()` | 复位到工程默认 + 刷新。 |
| `signal rebound(action, event)` / `signal rebind_failed(action, reason)` | reason ∈ `conflict:<other>` / `unsupported` / `cancelled`。 |

捕获类型:Key / MouseButton / JoypadButton(忽略摇杆轴);Esc 取消。

### KitRebindList(extends VBoxContainer)

| 成员 | 说明 |
|---|---|
| `setup(rows, input_manager = null)` | `rows=[{action, label}, ...]`;每行 `[Label \| KitRebindButton \| 复位]` + 底部「全部复位」;各按钮 `conflict_scope`=全部行动作。 |
| `refresh_all()` | 刷新所有子按钮。 |
| `signal rebound / rebind_failed` | 转发各子按钮信号。 |

## 依赖

- 消费 `CoreKit.input`(`InputManager`)的 `action_for_event`/`rebind_action`/`reset_action`/`get_action_event`。**零门面耦合**:告警走 `push_warning`,对 `CoreKit.input` 的默认解析可注入 standalone InputManager 绕开(headless 单测)。off-facade:不挂门面,`.new()`+`add_child` 即用。

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
- **v1 范围外**:冲突交换(只做拦截)、摇杆轴当按键、多绑定槽、组合键。
