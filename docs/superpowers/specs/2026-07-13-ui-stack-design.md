# UI 栈导航设计(KitUiStack + KitUiScreen,可复用界面栈)

> 阶段⑤ 补 UI 层缺口。给用 core-kit 的游戏一个**通用界面栈导航器**:一个挂在任意父节点下的宿主,管一叠 UI 屏幕的 push/pop/replace,路由输入给栈顶,并用一个**可选组件**给屏幕递生命周期回调 + 公共方法。对标各引擎的 UI Stack / Screen Manager,但保持 core-kit 的最小侵入与 off-facade 纪律。

**版本:** v0.13.0(承 scene-transition v0.12.0)

## 目标

给游戏一个 `.new()` 即用的 **`KitUiStack`**:挂到你选的任意父节点(某 `CanvasLayer` / `Control`)下,`push(PackedScene)` 压入一屏、`pop()` 弹出、`replace()` 换顶、`clear()` 清空;每次 push 盖住下层并把输入独占给栈顶;下层是否隐藏可配(全屏导航 vs 模态浮层)。屏幕若需要生命周期钩子(进入/被盖/揭回/离开)或公共操作(pop/push/replace/回指宿主),挂一个 **`KitUiScreen`** 组件子节点即可;不挂的傻瓜屏照样被完整托管,只是收不到回调。返回键(`ui_cancel`)默认弹栈顶。

核心取舍:**组合而非继承**。UI 屏幕的根节点几乎总要 `extends PanelContainer/MarginContainer/Control` 吃布局,继承基类会抢占这个"基类名额";故用组件挂载(`KitUiScreen` 是子节点),生命周期经**组件上的信号**、公共方法经**组件上的转发方法**。这是与 `KitState`(继承式,因状态无别的基类可继承)的关键区别。

## 非目标(YAGNI v1)

- **薄层级 / 画布管理器**:命名层(HUD/POPUP/MODAL…)与跨场景常驻 overlay 根是**另一件事**,`KitUiStack` 只认你给的一个父节点,不含层级编排。要的话本轮后单列。
- **焦点 / gamepad focus 自动管理**:不自动接管 `grab_focus`/焦点邻居链;栈只做"输入独占给栈顶"。屏幕自行管焦点。
- **转场动画**:v1 留可选钩子、默认瞬切;复用 v0.12.0 `KitTransition` 做 push/pop 淡入淡出**列后续扩展**,本次不塞。
- **命名路由 / 深链**:v1 是纯 LIFO 栈(push/pop/replace/clear),不做 `goto("settings")` 具名路由表、URL 深链。
- **多栈协调 / 全局单例**:不上 `CoreKit` 门面,不做跨栈仲裁;一个游戏可自建多个 `KitUiStack` 实例,互不感知。
- **持久化 / 历史序列化**:栈状态不落盘,不与 `SaveManager` 交互。

## 架构 / 定位

复用**已存在的 off-facade UI 类库目录** `addons/godot-core-kit/ui/`(现有 `KitRebindButton`/`KitRebindList` 同居),新增两文件,同为不挂门面的 `class_name` 类库:

- `ui/kit_ui_stack.gd` — `class_name KitUiStack extends Control`
- `ui/kit_ui_screen.gd` — `class_name KitUiScreen extends Node`

**不接门面、不改 12 子系统计数**,`core_kit.gd` 仅 bump `VERSION`。命名沿用 `Kit` 前缀。

依赖纪律:两类**零框架依赖**(诊断走 `push_warning`/`push_error`,不引 `CoreKit`),可脱离门面单独用、headless 断言。二者互引采用与 `KitStateMachine`↔`KitState` 相同的**单向类型引用**破环手法——`KitUiScreen.stack` 回指**不标注** `KitUiStack` 类型(避免两个 `class_name` 循环类型引用在 headless class 缓存下的编译风险)。

`KitUiStack extends Control`(非 `Node`):屏幕都是 Control,需要 Control 父节点锚定;宿主 `_ready` 自设 `PRESET_FULL_RECT` + `mouse_filter=IGNORE`(自身不吃鼠标,子屏正常收)。push 进来的屏幕成为**宿主的子节点**——这条物理边界天然实现「只管加进来的、不碰你手动摆进层里的节点」。

## 组件

### a. `KitUiScreen`(`ui/kit_ui_screen.gd`,`class_name KitUiScreen extends Node`)

可选组件。屏幕想要生命周期/公共方法就挂它做子节点;宿主 push 时注入回指并驱动其信号。

```gdscript
class_name KitUiScreen
extends Node

## 生命周期(由宿主 KitUiStack 驱动;prev/next 为对手屏节点名,无则 "")。
signal entered(prev_name: String)   ## 本屏成为栈顶、激活
signal exited(next_name: String)    ## 本屏被 pop、即将移除
signal covered()                    ## 被上层 push 盖住、被 process_mode 停用
signal revealed()                   ## 上层 pop 后重新成为栈顶、恢复活动

## 宿主回指;push 时由 KitUiStack 注入。不标注类型(破 class_name 循环引用)。
var stack

## --- 转发到宿主的公共方法(语法糖)---
func pop() -> void:
    if stack != null:
        stack.pop()

func push(scene_or_node, opts := {}) -> Control:
    return stack.push(scene_or_node, opts) if stack != null else null

func replace(scene_or_node, opts := {}) -> Control:
    return stack.replace(scene_or_node, opts) if stack != null else null

## 从任意(深层)子节点往上找到所属屏的 KitUiScreen 组件;无则 null。
static func of(node: Node) -> KitUiScreen:
    var n := node
    while n != null:
        for c in n.get_children():
            if c is KitUiScreen:
                return c
        n = n.get_parent()
    return null
```

- **信号而非虚方法**:子节点无法被父屏脚本"覆写方法",信号是子→父通知的地道方式。屏幕 `@onready var ui := $KitUiScreen` 后 `ui.entered.connect(...)`。
- **`of()`** 让深层按钮无需层层传引用:`KitUiScreen.of(self).pop()`。
- 屏幕根随意 `extends` 任意 Control 子类,不被侵入。

### b. `KitUiStack`(`ui/kit_ui_stack.gd`,`class_name KitUiStack extends Control`)

宿主。管一叠屏幕(LIFO),路由输入,驱动栈顶/被盖屏的组件信号。

```gdscript
class_name KitUiStack
extends Control

signal screen_pushed(screen: Control)
signal screen_popped(screen: Control)
signal emptied()

## 返回键动作名;为空 StringName 则关闭"返回键弹栈"。
@export var cancel_action: StringName = &"ui_cancel"

## 每个栈条目:{screen, backdrop, own, hide_below, cancellable, prev_process_mode}。栈底->栈顶。
var _stack: Array[Dictionary] = []
```

**栈 API**

| 方法 | 语义 |
|---|---|
| `push(scene_or_node, opts := {}) -> Control` | 压一屏。`PackedScene` → 宿主实例化;现成 `Control` → 直接收。盖住旧顶(旧顶 `covered()`;`hide_below` 则隐藏),新顶入树、注入回指、`entered(prev_name)`。返回屏实例。 |
| `pop() -> void` | 弹栈顶:顶 `exited(next_name)` → 按 `own` 决定 `queue_free`/仅 `remove_child` → 移除其挡层 → 恢复新顶(`visible=true` + `revealed()`)。空栈 → `push_warning` + no-op。 |
| `replace(scene_or_node, opts := {}) -> Control` | 换顶,栈深不变。**不走 pop()+push() 朴素组合**(那会让下层被 `revealed()`→`covered()` 抖一下):仅让旧顶 `exited(new_name)` + 按 `own` free/detach + 移旧顶挡层,**不恢复下层**(下层保持停用/隐藏),再把新屏盖到同一下层上、`entered(prev_name)`。空栈时等价纯 `push`。 |
| `clear() -> void` | 从顶到底逐个弹空,末发 `emptied()`。 |
| `top() -> Control` | 栈顶屏;空栈返回 `null`。 |
| `depth() -> int` / `is_empty() -> bool` | 只读栈深 / 空判。 |

**opts 键**(全部可省)

| 键 | 默认 | 说明 |
|---|---|---|
| `hide_below` | `true` | 盖住下层时是否 `visible=false`。全屏导航 `true`;模态浮层设 `false` 保留下层可见。 |
| `dim` | `Color(0,0,0,0)` | 仅 `hide_below==false` 时用:模态挡层的压暗色(透明=不压暗但仍挡输入)。 |
| `cancellable` | `true` | 本屏是否可被 `cancel_action`(返回键)弹出。 |
| `own` | `true` | pop 时是否 `queue_free` 屏节点。`false` = 仅 `remove_child`(交回调用方,给对象池/预建屏)。`PackedScene` 源默认随 `own=true` 被释放。 |

**覆盖 & 输入语义**

- **被盖屏一刀切停用**:push 盖住下层时,下层 `process_mode = Node.PROCESS_MODE_DISABLED`——Godot 据此停掉该子树的 `_input`/`_unhandled_input`/`_gui_input`/`_process`/`_physics_process`,故被盖屏对键鼠/动作/tick 全部惰性,**不依赖任何触发顺序、也无裸 `_input` 绕过**。reveal 时恢复 `PROCESS_MODE_INHERIT`。记录并还原每屏被盖前的原 `process_mode`。
- `hide_below==true`:下层再加 `visible=false`(隐藏 + 停用双保险)。
- `hide_below==false`(模态):下层保留可见但已停用;宿主**自动插一层铺满的 `ColorRect` 挡层**(`mouse_filter=STOP`,颜色 `dim`)作为该屏的**同生共死伙伴**(与屏一起入栈、一起 pop),对"GUI 鼠标拾取可能不受 `process_mode` 约束"这一路兜底挡住点穿;`dim` 透明则纯挡不压暗。`hide_below==true` 不插挡层(下层已隐藏)。
- **栈顶屏**保持活动,用自己的 `_input`/`_unhandled_input`/`_gui_input` 照常收输入(无需经组件转发)。
- **返回键兜底**:宿主重写 `_unhandled_input`——`event.is_action_pressed(cancel_action)` 且栈顶 `cancellable` 时 `pop()` 并 `set_input_as_handled()`。用 `_unhandled_input` 的语义天然正确:栈顶屏若自己消费了 cancel(自定义返回行为)则宿主收不到、不弹;没人消费才由栈兜底弹顶。

**宿主初始化**

```gdscript
func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE   # 自身不吃鼠标,子屏正常收
```

## 数据流

`push(scene, opts)` → 归一为 Control 实例(PackedScene 则 `instantiate()`)→ 旧顶 `process_mode=DISABLED` + `covered()`、`hide_below` 则 `visible=false` →(模态)插挡层 → 新屏 `add_child` + 注入 `KitUiScreen.stack=self`(若有组件)→ 记 `_stack` 条目 → 新屏组件 `entered(prev_name)` → `screen_pushed`。
`pop()` → 顶组件 `exited(next_name)` → 移挡层 → 按 `own` free/detach 屏 → 新顶恢复 `process_mode`(+ `visible=true`)+ `revealed()` → `screen_popped`(栈空则续 `emptied`)。
`_unhandled_input(e)` → cancel_action 命中且栈顶 `cancellable` → `pop()` + `set_input_as_handled()`;否则不拦(留给栈顶屏自己的输入回调)。

## 错误处理

- 空栈 `pop()`/`top()` → `push_warning` + no-op / `null`,不崩。
- `push` 收到非 `PackedScene`/`Control`(如传了 `Node`/`Resource`)→ `push_error` + 返回 `null`,不入栈。
- `PackedScene.instantiate()` 结果非 `Control` → `push_error` + free 该实例 + 返回 `null`。
- 无 `KitUiScreen` 组件的屏:所有生命周期广播静默跳过(`of`/直接持有的组件为 `null` 即不 emit),不报错。
- `cancel_action` 未在 InputMap 注册:`is_action_pressed` 恒 false,退化为"无返回键弹栈",不崩。

## 测试(headless)

测试在 headless `SceneTree` 下跑;宿主需入树才能 `_ready`/管子节点,故各用例把 `KitUiStack.new()` `add_child` 到 `get_tree().root`(或临时容器),末尾 `queue_free` 清理。屏幕用**代码建的最小 `Control`**(部分挂 `KitUiScreen` 子节点)作 fixture,不依赖 `.tscn`。

### 新 `test/test_ui_stack.gd`

1. **push/depth/top**:连 push 3 屏 → `depth()==3`、`top()==` 第 3 屏。
2. **pop 顺序 + 空栈守卫**:pop 两次 → `depth()==1`、`top()==` 第 1 屏;pop 到空后再 pop → no-op(`depth()==0`,不崩)。
3. **replace 换顶不改深**:push A、push B、`replace(C)` → `depth()==2`、`top()==C`;B 已被 free(下帧 `is_instance_valid` 为假)。
4. **clear + emptied**:push 2 屏、连 `clear()` → `depth()==0`,`emptied` 收到 1 次。
5. **hide_below=true 隐藏 + 停用下层**:push A、push B(默认)→ `A.visible==false` 且 `A.can_process()==false`;pop → `A.visible==true` 且 `A.can_process()==true`(原 `process_mode` 还原)。
6. **模态 hide_below=false 保留可见 + 停用 + 插挡层**:push A、push B `{hide_below=false, dim=Color(0,0,0,0.5)}` → `A.visible==true` 但 `A.can_process()==false`;B 条目含 backdrop 子节点,`backdrop.mouse_filter==STOP`、`backdrop.color==Color(0,0,0,0.5)`;pop B → `A.can_process()==true`、挡层随之移除(不再是宿主子节点)。
7. **生命周期信号 + 顺序**(屏挂 `KitUiScreen`):push A → A `entered("")`;push B → A `covered()`、B `entered("A")`;pop B → B `exited("A")`、A `revealed()`。用计数/时序数组断言。
8. **`own` 归属**:push 现成节点 `n` with `{own=false}` → pop 后 `is_instance_valid(n)` 仍真(仅 detach);默认 `own=true` 的另一节点 pop 后下帧失效。
9. **`KitUiScreen.of()` 解析**:在栈顶屏的深层子按钮上 `KitUiScreen.of(btn)` → 命中该屏组件;无组件屏上 → `null`。
10. **回指注入**:挂组件屏 push 后 `ui.stack == 该 KitUiStack`;`ui.pop()` 等价宿主 `pop()`(深 -1)。
11. **cancel 弹栈**:构造 `InputEventAction`(action=cancel_action,pressed)喂宿主 `_unhandled_input(e)` → 栈顶弹出;栈顶 `{cancellable=false}` 时同 event → 不弹。
12. **非法 push**:`push(Resource.new())` / `push(Node.new())` → 返回 `null`、`depth` 不变。

### `test/test_core_kit.gd`

- 版本断言 `VERSION == "0.13.0"`。

## 收尾件

- 新 `ui/kit_ui_stack.gd`(+`.uid`)、`ui/kit_ui_screen.gd`(+`.uid`)。
- 新 `test/test_ui_stack.gd`(+`.uid`)。
- 新 `docs/ui/ui-stack.md`(五段式:职责/公开 API/依赖/用法示例/注意事项),记组合式取舍、opts 表、被盖屏 `process_mode=DISABLED` 停用语义(含"被盖屏动画/tick 一并暂停"这一副作用)、模态挡层对 GUI 拾取兜底。
- `docs/ui/rebind.md` 无关不动;`docs/README.md` 的「### ui/」段加 `KitUiStack`/`KitUiScreen` 行;`docs/architecture.md` 版本 → 0.13.0、测试文件数(17→18)、依赖纪律注(`KitUiStack`↔`KitUiScreen` 零依赖、单向类型引用破环)。
- 根 `README.md` 子系统表加 `KitUiStack`/`KitUiScreen`(类库)行 + 版本 0.13.0 条目。
- `plugin.cfg` version 0.13.0 + description;`core_kit.gd` `VERSION` → `"0.13.0"`(**不改**子系统构造/接线,12 计数不变);`test/test_core_kit.gd` 版本断言 → `"0.13.0"`。
- `demo/demo.gd`:建一个 `KitUiStack`,程序化 push 3 屏 + 一屏模态,打印确定性 marker(如 `UiStack: depth=3 top=ScreenC modal_backdrop=true`,**不依赖真实输入**,headless 确定性),末 `clear`。
- `test/run_all.ps1`:加 `test_ui_stack`(测试文件 17→18)+ demo marker `UiStack: depth=3` + 计数。

## 我替你拍的默认(实现时若无异议即照此)

复用 `ui/` 目录 + `Kit` 前缀 · 宿主 `extends Control`(全屏 full-rect、自身 `mouse_filter=IGNORE`)· 屏为宿主子节点(物理边界=只管加进来的)· 组合式:`KitUiScreen` 组件挂子节点、生命周期走信号、公共方法走转发方法 · `hide_below` 默认 `true`、模态自动插 `ColorRect` 挡层(`STOP`,`dim` 可压暗)· **被盖屏 `process_mode=DISABLED` 一刀切停用**(键鼠/动作/tick 全惰性、无裸 `_input` 绕过,reveal 还原原 process_mode)· 栈顶用自身输入回调 · 返回键经宿主 `_unhandled_input` 兜底(栈顶消费则不弹)· `cancel_action=&"ui_cancel"`、`cancellable` 可关 · `own` 默认 `true`(pop 即 free,`false` 仅 detach)· LIFO 纯栈无具名路由 · off-facade 不接门面、12 子系统计数不变 · 版本 0.13.0。
