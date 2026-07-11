# KitStateMachine —— 有限状态机类库

> class_name KitStateMachine / KitState · state_machine/

## 职责

一个挂在具体实体节点下的 Node 型有限状态机:`KitStateMachine` 收集自己的直接子节点中的 `KitState`,按【节点名】注册为状态(改节点名即改状态名),并转发 `_process`/`_physics_process`/`_unhandled_input` 给当前状态。编辑器里可视化组装——实体节点 → `KitStateMachine` → 一态一子节点一脚本。

`KitState` 全部方法为虚方法,子类按需覆写;不覆写的钩子什么也不做。

两个类都**零依赖**(诊断只用引擎原生 `push_warning`/`push_error`),**不挂在 `CoreKit` 门面上**——不经 `CoreKit.x` 访问,谁要用状态机就在自己的场景/脚本里 `new()`/实例化一台,可脱离整个框架单独使用。

## 公开 API

```gdscript
class_name KitState
extends Node

## 宿主状态机;由 KitStateMachine 在 _ready 时注入。
## 不标注 KitStateMachine 类型,打破两个 class_name 间的循环类型引用。
var machine

func enter(_prev_state_name: String) -> void      # 进入本状态;初始进入 prev 为 ""
func exit(_next_state_name: String) -> void        # 离开本状态,next 为将进入的状态名
func update(_delta: float) -> void                 # 宿主 _process 转发(仅当前状态收到)
func physics_update(_delta: float) -> void         # 宿主 _physics_process 转发(仅当前状态收到)
func handle_input(_event: InputEvent) -> void      # 宿主 _unhandled_input 转发(仅当前状态收到)
func transition_to(state_name: String) -> void     # 语法糖:machine.transition_to(state_name)
func pause() -> void                                # 被 push_state 压栈让位时调用(暂停,现场保留)
func resume() -> void                               # 经 pop_state 弹回成为活动态时调用
```

```gdscript
class_name KitStateMachine
extends Node

## 每次完成一次转换后广播(初始进入也广播,from_name 为 "")。
signal state_changed(from_name: String, to_name: String)

const MAX_CHAIN := 8

## 初始状态;为 null 时取第一个 KitState 子节点。
@export var initial_state: KitState

## 当前状态(只读约定;转换请走 transition_to)。
var current_state: KitState

const ANYSTATE := "*"                              # 事件转移表通配 from(保留名)
const MAX_STACK := 32                              # pushdown 栈深守卫

func transition_to(state_name: String) -> void    # 按状态名转换;未知名字 push_warning + 空操作
func get_state(state_name: String) -> KitState    # 按名取状态节点;未知名字返回 null
func add_transition(from_name: String, to_name: String, event: String) -> void  # 登记事件转移(from 可为 ANYSTATE)
func dispatch(event: String) -> bool               # 派发事件:命中则转移返回 true;无匹配静默 false
func push_state(state_name: String) -> void        # 压栈进新态(暂停语义,current.pause())
func pop_state() -> void                            # 弹栈回挂起态(current 弹出态.resume())
func stack_depth() -> int                           # 只读当前 pushdown 栈深
```

## 依赖

零依赖、不挂门面、per-entity:每个需要状态机的实体各自持有一台 `KitStateMachine` 实例,互不共享,也不经 `CoreKit` 注册或查找。与 CoreKit 其余子系统没有任何耦合,可原样复制到别的项目使用。

## 用法示例

场景里可视化组装(子节点名即状态名,`initial_state` 留空则取第一个 `KitState` 子节点):

```
Enemy (CharacterBody2D)
  └─ StateMachine (KitStateMachine)
       ├─ Idle    (脚本 extends KitState)
       ├─ Chase   (脚本 extends KitState)
       └─ Attack  (脚本 extends KitState)
```

也可以纯代码组装:

```gdscript
var machine := KitStateMachine.new()
var idle := Idle.new()
idle.name = "Idle"
var chase := Chase.new()
chase.name = "Chase"
machine.add_child(idle)
machine.add_child(chase)
add_child(machine)  # _ready 时按子节点名注册状态,并进入 initial_state(或第一个)
```

自定义状态子类,覆写 `enter`/`update`,通过 `machine` 回引发起转换:

```gdscript
class_name Chase
extends KitState

func enter(_prev_state_name: String) -> void:
    print("进入追击")

func update(_delta: float) -> void:
    if target_out_of_range():
        machine.transition_to("Idle")
```

## 事件派发解耦(add_transition / dispatch)

除了状态里写死后继态名(`machine.transition_to("Idle")`),还可把转移集中登记到机器上,让状态只发**命名事件**、由机器决定后继:

```gdscript
machine.add_transition("Run", "Idle", "stop")            # Run 收到 stop → Idle
machine.add_transition(machine.ANYSTATE, "Dead", "die")  # 任意态收到 die → Dead(通配)

machine.dispatch("stop")   # 命中当前态转移,返回 true;无匹配静默返回 false
```

- **转移表**:key 为 `"<from>|<event>"`,`from` 为已注册态名或 `ANYSTATE`("*")。`add_transition` 目标态未注册 → `push_warning` 忽略;同 `(from, event)` 重复登记 → 覆盖并 `push_warning`。
- **匹配优先级**:`dispatch(event)` 先查当前态的具体转移 `(current, event)`,未命中再查通配 `(ANYSTATE, event)`;**具体 from 优先于通配**。两者都无匹配 → 静默返回 `false`(事件派发常态:多数事件在多数态无转移)。
- **复用转换核心**:命中后走与 `transition_to` 完全相同的路径——非转换中直接 `exit→enter→state_changed`(连锁 / `MAX_CHAIN` 语义不变),转换进行中则把目标入 `_pending` 队列。
- 与 `transition_to` **并存**:两种触发方式可混用,互不影响。

## pushdown 栈(push_state / pop_state,暂停语义)

菜单、暂停界面等"临时盖一层、回来还在原地"的场景,用 pushdown 栈:压当前态(**暂停**而非退出)、进临时态,弹回时被压态**现场保留**。

```gdscript
machine.push_state("PauseMenu")   # 暂停当前态(current.pause())、压栈、进 PauseMenu
# ……玩家在暂停菜单操作……
machine.pop_state()               # 退出 PauseMenu、弹回被压态、该态 resume()
machine.stack_depth()             # 当前栈深
```

- **暂停语义**:`push_state` 调被压态的 `pause()`(**不** `exit`),`pop_state` 调恢复态的 `resume()`(**不**重新 `enter`)。故被压态**不重置、现场保留**——这是与普通转移的本质区别。老状态子类不覆写 `pause`/`resume` 完全无感(default-pass)。
- **信号复用**:push/pop 改变 `current_state`,复用 `state_changed`(push 发 `(被压态, 新态)`、pop 发 `(被弹活动态, 恢复态)`),不新增专用信号。
- **栈存态名**:`_stack` 存被压态的名字;节点不销毁,`resume` 时仍是同一节点。`current_state` 始终是活动态(不在栈里)。
- **转发**:`update`/`physics_update`/`handle_input` 始终只转发 `current_state`,栈下挂起态不收。
- **守卫**:未知态 → `push_warning` no-op;栈满(≥ `MAX_STACK` = 32)→ `push_error` 拒绝;转换进行中(`_transitioning`)调 `push_state`/`pop_state` → `push_warning` 拒绝;栈空 `pop_state` → `push_warning` no-op。pushdown 不参与 `MAX_CHAIN` 连锁计数。
- **栈非空仍可转移**:`transition_to`/`dispatch` 照常替换 `current_state`(栈不动),`pop_state` 仍弹回栈下挂起态。

## 注意事项

- **状态即直接子节点**:只有 `KitStateMachine` 的直接子节点且 `is KitState` 才会被注册;子节点名就是状态名,改名即改状态名。
- **initial_state 回退**:`@export var initial_state` 为 null 时,取遍历到的第一个 `KitState` 子节点(按子节点顺序,非按名排序)。
- **自转换会重进**:`transition_to(当前态名)` 照常走 `exit → enter`,可用作"重进重置"当前状态,不是空操作。
- **连锁转换有上限**:`enter`/`exit` 执行期间再调 `transition_to` 会入队(`_pending`),等当前转换完成后按序处理(可实现"决策态"在 `enter` 里立即转走);但同一次外部触发内最多连续转换 `MAX_CHAIN`(= 8)次,超过按死循环处理——`push_error` 并丢弃剩余待处理队列。
- **未知状态名不报错**:`transition_to` 传入未注册的名字只 `push_warning`,不抛异常也不会发生转换。
- **`machine` 故意不标类型**:`KitState.machine` 不写成 `: KitStateMachine`,是为了打破 `KitState` ↔ `KitStateMachine` 两个 `class_name` 间的循环类型引用——机器到状态单向引用即可,循环引用在 headless class 缓存下有编译风险。
- **`class_name` 缓存**:首次引用 `KitStateMachine`/`KitState` 前,须先跑一次 `godot --headless --path . --import` 生成全局类缓存,否则编译期解析不到这两个类名。
- 没有任何 `KitState` 子节点时状态机空转(`push_warning`),`current_state` 保持 `null`,不会报错但也没有任何状态生效。
- **`ANYSTATE`("*")为保留名**:事件转移表用 "*" 表示通配 from;若某 `KitState` 子节点名恰为 "*",`_ready` 注册时 `push_error`(该名会与通配 key 混淆)。
- **pushdown 是暂停不是转移**:`push_state`/`pop_state` 走 `pause`/`resume` 钩子,被压态现场保留;需要重置就用 `transition_to`。
