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

func transition_to(state_name: String) -> void    # 按状态名转换;未知名字 push_warning + 空操作
func get_state(state_name: String) -> KitState    # 按名取状态节点;未知名字返回 null
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

## 注意事项

- **状态即直接子节点**:只有 `KitStateMachine` 的直接子节点且 `is KitState` 才会被注册;子节点名就是状态名,改名即改状态名。
- **initial_state 回退**:`@export var initial_state` 为 null 时,取遍历到的第一个 `KitState` 子节点(按子节点顺序,非按名排序)。
- **自转换会重进**:`transition_to(当前态名)` 照常走 `exit → enter`,可用作"重进重置"当前状态,不是空操作。
- **连锁转换有上限**:`enter`/`exit` 执行期间再调 `transition_to` 会入队(`_pending`),等当前转换完成后按序处理(可实现"决策态"在 `enter` 里立即转走);但同一次外部触发内最多连续转换 `MAX_CHAIN`(= 8)次,超过按死循环处理——`push_error` 并丢弃剩余待处理队列。
- **未知状态名不报错**:`transition_to` 传入未注册的名字只 `push_warning`,不抛异常也不会发生转换。
- **`machine` 故意不标类型**:`KitState.machine` 不写成 `: KitStateMachine`,是为了打破 `KitState` ↔ `KitStateMachine` 两个 `class_name` 间的循环类型引用——机器到状态单向引用即可,循环引用在 headless class 缓存下有编译风险。
- **`class_name` 缓存**:首次引用 `KitStateMachine`/`KitState` 前,须先跑一次 `godot --headless --path . --import` 生成全局类缓存,否则编译期解析不到这两个类名。
- 没有任何 `KitState` 子节点时状态机空转(`push_warning`),`current_state` 保持 `null`,不会报错但也没有任何状态生效。
