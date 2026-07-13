# UI 栈导航(KitUiStack / KitUiScreen)

> `class_name KitUiStack`(`ui/kit_ui_stack.gd`,extends Control) / `KitUiScreen`(`ui/kit_ui_screen.gd`,extends Node) · off-facade 可复用 UI 类库(不挂门面)

## 职责

通用 UI 屏栈导航。`KitUiStack` 是一个挂到任意父节点(某 `CanvasLayer`/`Control`)下的全屏容器,`push`/`pop`/`replace`/`clear` 管一叠 UI 屏(LIFO)。push 进来的屏成为它的子节点——**只管加进来的、不碰你手动摆进同一层的节点**。被上层盖住的屏 `process_mode=DISABLED` 一刀切停用(键鼠/动作/tick 全惰性),栈顶保持活动、用自己的输入回调;返回键(`ui_cancel`)经宿主 `_unhandled_input` 兜底弹顶。`KitUiScreen` 是可选组件:屏根挂它做子节点,就能收生命周期信号(entered/exited/covered/revealed)+ 得公共方法(pop/push/replace)+ 拿到宿主回指。**组合而非继承**——屏根随意 `extends` 任意 Control 子类,不被侵入。

## 公开 API

### KitUiStack(extends Control)

| 成员 | 说明 |
|---|---|
| `push(scene_or_node, opts := {}) -> Control` | 压一屏。`PackedScene` 则实例化、现成 `Control` 则直接收。盖住旧顶(停用;`hide_below` 则隐藏)。返回屏实例;非法参数→`push_error`+`null`。 |
| `pop() -> void` | 弹栈顶:旧顶 `exited`→移挡层→按 `own` free/detach→恢复新顶(`revealed`)。空栈→`push_warning`+no-op。 |
| `replace(scene_or_node, opts := {}) -> Control` | 换顶,栈深不变。**不走 pop()+push()**(避免下层被 `revealed`→`covered` 抖动):拆旧顶但不 reveal 下层,再把新屏盖到同一下层。空栈时等价纯 `push`。 |
| `clear() -> void` | 从顶到底逐个弹空,末发 `emptied`。 |
| `top() -> Control` / `depth() -> int` / `is_empty() -> bool` | 栈顶屏(空→`null`)/ 栈深 / 空判。 |
| `@export cancel_action: StringName = &"ui_cancel"` | 返回键动作名;为空 `StringName` 则关闭「返回键弹栈」。 |
| `signal screen_pushed(screen)` / `screen_popped(screen)` / `emptied()` | 入栈 / 出栈 / 栈清空广播。 |

**opts 键**(全部可省):

| 键 | 默认 | 说明 |
|---|---|---|
| `hide_below` | `true` | 盖住下层时是否 `visible=false`。全屏导航 `true`;模态浮层设 `false` 保留下层可见。 |
| `dim` | `Color(0,0,0,0)` | 仅 `hide_below==false` 时用:模态挡层压暗色(透明=不压暗但仍挡输入)。 |
| `cancellable` | `true` | 本屏是否可被 `cancel_action` 弹出。 |
| `own` | `true` | pop 时是否 `queue_free` 屏节点。`false`=仅 `remove_child`(交回调用方,给对象池/预建屏)。 |

### KitUiScreen(extends Node,可选组件)

| 成员 | 说明 |
|---|---|
| `signal entered(prev_name)` / `exited(next_name)` / `covered()` / `revealed()` | 生命周期,由宿主驱动;prev/next 为对手屏节点名,无则 `""`。 |
| `var stack` | 宿主回指;push 时注入。 |
| `pop()` / `push(scene_or_node, opts := {})` / `replace(...)` | 转发到宿主(语法糖)。 |
| `static of(node) -> KitUiScreen` | 从任意(深层)子节点往上找到所属屏的组件;无则 `null`。 |

## 依赖

**零框架依赖**:两类只用 `push_warning`/`push_error` 诊断,不引 `CoreKit`,可脱离门面单独用、headless 断言。`KitUiScreen.stack` 变量不标注 `KitUiStack` 类型(单向类型引用,破 `class_name` 循环引用)。off-facade:不挂门面,`.new()`+`add_child` 即用。

## 用法示例

```gdscript
# 建栈:挂到你选的层(如一个 CanvasLayer),游戏全程持有
var ui := KitUiStack.new()
$UiLayer.add_child(ui)
ui.push(preload("res://ui/main_menu.tscn"))

# 打开设置(全屏导航,盖住并停用主菜单)
ui.push(preload("res://ui/settings.tscn"))

# 弹出模态对话框(保留下层可见 + 压暗 + 自动挡输入)
ui.push(preload("res://ui/confirm.tscn"), {"hide_below": false, "dim": Color(0, 0, 0, 0.5)})
```

屏脚本挂 `KitUiScreen` 组件收回调 / 用公共方法:

```gdscript
extends PanelContainer   # 屏根随意 extends,不被侵入
@onready var screen: KitUiScreen = $KitUiScreen

func _ready() -> void:
    screen.entered.connect(func(_prev): _play_open_anim())
    screen.covered.connect(_pause_bg)      # 被上层盖住
    screen.revealed.connect(_resume_bg)    # 上层弹走、重回栈顶
    $CloseButton.pressed.connect(screen.pop)
    $NextButton.pressed.connect(screen.push.bind(preload("res://ui/next.tscn")))

# 深层子节点无需层层传引用:
func _on_deep_button() -> void:
    KitUiScreen.of(self).pop()
```

## 注意事项

- **被盖屏被完全停用**:盖住一屏时它 `process_mode=DISABLED`——键鼠/动作/`_process`/`_physics_process` 全惰性,**不依赖触发顺序、无裸 `_input` 绕过**。副作用是**被盖屏的动画 / tick 也一并暂停**;要「模态浮层下背景继续动、只挡输入」的场景,本 v1 不支持(需要的话单列扩展)。
- **模态挡输入**:`hide_below=false` 时宿主自动插一层铺满的 `ColorRect`(`mouse_filter=STOP`,颜色 `dim`)作为该屏的同生共死伙伴,对「GUI 鼠标拾取可能不受 `process_mode` 约束」这一路兜底挡住点穿。
- **返回键是兜底**:`_unhandled_input` 只在**没人消费**该输入时才弹顶——栈顶屏若自己消费了 `ui_cancel`(自定义返回行为)则宿主收不到、不弹。设 `cancel_action = &""` 完全关闭。
- **屏自控布局**:宿主不强改 push 进来的屏的锚点,屏按自己场景里设的 anchors 在全屏容器内布局(全屏屏设 full-rect,居中对话框设居中)。
- **归属**:`push(PackedScene)` 与默认 `own=true` 的屏由宿主 `queue_free`;`own=false` 时 pop 只 `remove_child`,节点交回你手上。
- **组合非继承**:屏不继承任何基类,靠可选 `KitUiScreen` 组件接入——这是为了不抢占 UI 根节点的 Control 基类名额(与 `KitStateMachine`/`KitState` 的继承式不同)。
- **v1 范围外**:命名路由 / 深链、焦点 gamepad 自动管理、push/pop 转场动画(留 `KitTransition` 复用扩展位)、跨栈协调、层级/画布管理器(另一件事)。
