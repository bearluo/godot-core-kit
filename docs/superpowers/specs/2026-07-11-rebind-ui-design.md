# 设置/重绑定 UI 设计(KitRebindButton / KitRebindList）

> 阶段4 补缺库 3/4。对标 Maaack 的可复用重绑定 UI。核心交付「键位重绑定组件」——游戏真正难自造的那块;audio 音量、locale 切换是一行绑定的琐碎活,放 demo 示范游戏怎么自己拼(不做成品设置面板)。

**版本:** v0.11.0(承 i18n v0.10.0)

## 目标

给使用 core-kit 的游戏一个**可复用的键位重绑定 UI 组件**:玩家点击 → 按新键捕获 → 冲突检测(检测+拦截)→ 落到既有 `InputManager.rebind_action`(替换 InputMap + 持久化 Settings)。组件只管 UI + 捕获 + 冲突判定,重绑/复位/持久化全复用既有 InputManager。

## 非目标(YAGNI v1)

- **成品设置面板**:不做「audio 三滑条 + locale 下拉 + 重绑列表」一体化的 SettingsPanel(布局/风格偏游戏特定)。audio/locale 的接线是一行调用,放 demo 示范。
- **.tscn 场景 / Maaack 式菜单模板**:保持库的纯 GDScript、无 .tscn 资产、Web 友好定位;代码建 UI(同 DevConsole)。
- **冲突交换(swap)**:v1 只做检测+拦截(冲突则拒绝、保留原绑定、报占用者);交换语义复杂、边界多,暂缓。
- **joypad motion 作按键重绑**:捕获忽略摇杆轴(轴当按键语义怪);捕获 Key/MouseButton/JoypadButton。
- **多绑定槽 / 组合键 / 多玩家**:同 InputManager v1 范围外。

## 架构 / 定位

新增 **off-facade UI 组件层** `addons/godot-core-kit/ui/`(与 `state_machine/`、`di/` 同为不挂门面的 `class_name` 类库,`.new()` + `add_child` 即用)。**不接门面、不改 core_kit.gd、不动 12 子系统计数**——UI 组件是 off-facade 类库,如 `KitStateMachine`/`KitContext`。命名沿用 `Kit` 前缀。

依赖:组件消费 `CoreKit.input`(默认,可注入 standalone InputManager 做单测)。组件不引 `CoreKit.log`,告警走 `push_warning`(保 standalone 可 headless 测,同各子系统 `_settings=null` 意图)。

## 组件

### a. `KitRebindButton`(`ui/rebind_button.gd`,`class_name KitRebindButton extends Button`)—— 核心原子

一个动作一个按钮。

| 成员 | 说明 |
|---|---|
| `setup(action: String, conflict_scope := PackedStringArray(), input_manager = null) -> void` | 绑定动作;`input_manager` 省略则运行时解析为 `CoreKit.input`(测试注入 standalone)。`conflict_scope` 空=冲突扫全部动作,否则只在该子集内判。末尾 `refresh()`。 |
| `begin_capture() -> void` | 进捕获态:存原文字、文字变「按任意键…(Esc 取消)」、`grab_focus()`、开 `_input` 监听。 |
| `capture_event(event: InputEvent) -> bool` | **可测种子**。Esc→`cancel_capture` 返 false;不支持类型→发 `rebind_failed(action,"unsupported")` 返 false;冲突(`action_for_event` 命中他人)→发 `rebind_failed(action,"conflict:<other>")`、**不改绑定**、返 false;否则 `input.rebind_action(action,event)` 成功→`refresh()`+发 `rebound(action,event)` 返 true。处理后退出捕获态。 |
| `cancel_capture() -> void` | 退捕获态、`refresh()`、发 `rebind_failed(action,"cancelled")`。 |
| `refresh() -> void` | 文字 = 当前绑定 `input.get_action_event(action).as_text()`(引擎渲染「Space」「Left Mouse Button」);无绑定显「未绑定」。 |
| `reset() -> void` | `input.reset_action(action)` + `refresh()`(InputManager 内部会发 `action_rebound`,组件不重复发)。 |
| `signal rebound(action: String, event: InputEvent)` | 重绑成功。 |
| `signal rebind_failed(action: String, reason: String)` | reason ∈ `"conflict:<other>"` / `"unsupported"` / `"cancelled"`。 |

- **捕获谓词**:`InputEventKey`(pressed 且非 echo)/ `InputEventMouseButton`(pressed)/ `InputEventJoypadButton`(pressed);Esc(physical_keycode==KEY_ESCAPE)→取消;忽略 motion / 释放 / 触屏。
- **冲突判定**:`var other := input.action_for_event(event, conflict_scope)`;`other != "" and other != action` 即冲突。`other == action`(同键重绑自身)放行(成功、等价 no-op)。
- **输入管线**:`_input(event)` 仅在 `_capturing` 时把合格事件喂给 `capture_event` 并 `accept_event()`;非捕获态 `set_process_input(false)`。真实点击 `pressed` → `begin_capture`。

### b. `KitRebindList`(`ui/rebind_list.gd`,`class_name KitRebindList extends VBoxContainer`)—— 薄组合(用户确认保留)

| 成员 | 说明 |
|---|---|
| `setup(rows: Array, input_manager = null) -> void` | `rows = [{action, label}, ...]`;每行建 HBoxContainer`[Label(label) | KitRebindButton | 复位 Button]`;底部「全部复位」Button。各 KitRebindButton 的 `conflict_scope` = 全部行的 action 集(冲突只在可重绑集合内判,避免「Space 撞 ui_accept」误报)。 |
| `refresh_all() -> void` | 刷新每个子 KitRebindButton(复位全部/外部变更后)。 |
| `signal rebound(action, event)` / `signal rebind_failed(action, reason)` | 转发各子按钮信号,便于集中监听。 |
| 「全部复位」 | 对本列表每行 action 调 `input.reset_action`(**不用 `reset_all`**,避免复位列表外的动作)+ `refresh_all()`。 |
| 每行「复位」 | 该行 `KitRebindButton.reset()`。 |

### c. InputManager 增补 `action_for_event`(`systems/input_manager.gd`)

```gdscript
## 返回当前占用该事件的动作名;among 空=扫全部动作,否则只扫子集;无占用返回 ""。
## 复用 _event_to_dict 做结构相等比较(键盘按 physical_keycode 等)。
func action_for_event(event: InputEvent, among := PackedStringArray()) -> String:
	var target := _event_to_dict(event)
	if target.is_empty():
		return ""
	var scan: Array = among if among.size() > 0 else InputMap.get_actions()
	for action in scan:
		if not InputMap.has_action(action):
			continue
		for ev in InputMap.action_get_events(action):
			if _event_to_dict(ev) == target:
				return String(action)
	return ""
```

服务本目标的定向增强(绑定归 InputManager 所有);零新逻辑,复用现有编码器。

## 数据流

点击 → `begin_capture` → `_input` 捕获下一个合格事件 → `capture_event(ev)` → `input.action_for_event(ev, conflict_scope)`:命中他人→`rebind_failed`、绑定不变;否则 `input.rebind_action(action, ev)`(替换 InputMap + 持久化 Settings section `input`)→ `refresh` → `rebound`。复位走 `input.reset_action`/`reset_all`。

## 错误处理

- 不支持类型 / Esc / 冲突 → 各发 `rebind_failed(reason)`、不改绑定、不崩。
- `setup` 不存在的 action → `refresh` 时 `get_action_event` 返 null → 显「未绑定」;真重绑时 `rebind_action` 本就 guard 返 false(组件据其返回值发 `rebind_failed("unsupported")` 或不发 `rebound`)。
- 全程 `push_warning`(如需),无 `CoreKit.log`、无 crash 路径。

## 测试(headless,`test/test_rebind.gd`)

经 `capture_event` 种子脱离真实输入测核心逻辑。standalone InputManager:`InputMap.add_action` 建临时动作(`test_jump` 默认 Space、`test_fire` 默认 KEY_G)+ `im._snapshot_defaults()`;KitRebindButton 注入该 im。覆盖:

1. **正常重绑**:`capture_event(key F)` on test_jump → InputMap test_jump 变 F、`rebound("test_jump", ev)` 发、(可选)持久化到注入 Settings。
2. **冲突拦截**:`capture_event(key G)` on test_jump(conflict_scope 含 test_fire)→ `rebind_failed("test_jump","conflict:test_fire")`、test_jump 绑定不变。
3. **不支持类型**:`capture_event(InputEventMouseMotion)` → `rebind_failed(...,"unsupported")`、不变。
4. **Esc 取消**:`capture_event(key ESCAPE)` → `rebind_failed(...,"cancelled")`、不变。
5. **reset**:重绑后 `reset()` → test_jump 回默认 Space、文字刷新。
6. **`action_for_event`**:`im.action_for_event(key G)` → "test_fire";`among=["test_jump"]` → "";不支持事件 → ""。
7. **KitRebindList**:`setup([{action:"test_jump",label:"Jump"},{action:"test_fire",label:"Fire"}], im)` → 建 2 行、各含一个 KitRebindButton;转发信号;「全部复位」→ 对两行各 `reset_action` + 刷新(不复位列表外动作)。

隔离:收尾 `InputMap.erase_action("test_jump"/"test_fire")`、free 节点。`test/test_input_manager.gd` 补 `action_for_event` 断言(全/子集/无占用/不支持)。

## 收尾件

- 新 `ui/rebind_button.gd` + `ui/rebind_list.gd`(各 +.gd.uid);新 `test/test_rebind.gd`(+.uid)。
- `systems/input_manager.gd` 增 `action_for_event`;`test/test_input_manager.gd` 补断言。
- 新 `docs/ui/rebind.md`(五段式);`docs/README.md` 加「### ui/ —— 可复用 UI 组件」段 + 行;`architecture.md` 目录布局加 `ui/`、依赖纪律注(`KitRebindButton → CoreKit.input` 默认 / off-facade)、版本;根 `README.md` 表加行 + 版本 0.11.0 条目;`plugin.cfg` version 0.11.0 + description。
- `demo/demo.gd`:KitRebindButton 冒烟(建临时动作 + 程序化 `capture_event` 正常/冲突,ASCII marker),收尾清临时动作;`test/run_all.ps1` 加 `test_rebind` + demo marker + 计数。
- **不改** `core_kit.gd` / `test_core_kit.gd`(off-facade,不接门面,12 子系统计数不变)。

## 我替你拍的默认(实现时若无异议即照此)

`ui/` 新目录 + `Kit` 前缀 · 捕获忽略 joypad motion · Esc=取消 · 冲突只在 `conflict_scope` 内判(空=全部)· `other==action` 同键重绑自身放行 · off-facade 不接门面 · 版本 0.11.0。KitRebindList 保留(用户确认)。
