# godot-core-kit KitStateMachine 状态机类库设计

- 日期:2026-07-02
- 状态:已确认,待实现
- 版本目标:0.4.0
- 前置:`2026-07-02-corekit-facade-design.md`(总纲)

---

## 目标与定位

有限状态机是 per-实体 构件(每个角色/敌人/UI 各挂一台),**不是全局单例**——因此它是随 addon 分发的 `class_name` 类库,不进 CoreKit 门面、不注册 autoload、**零依赖**(不引用 CoreKit/Log,诊断用引擎原生 `push_warning`/`push_error`),可完全脱离框架单独使用。

形态:**Node 型**。编辑器里可视化组装——实体节点 → `KitStateMachine` 子节点 → 一态一个 `KitState` 子节点一个脚本;调试时场景树直接看到当前态。

命名带 **Kit 前缀**(与门面同一命名纪律):`State`/`StateMachine` 是 class_name 撞车重灾区。

首版 YAGNI:不做分层/嵌套状态机(HSM)、不做转换条件表/守卫、不做历史状态、不做动画状态机集成。

## Public API(GDScript 精确签名)

```gdscript
class_name KitStateMachine
extends Node
## 有限状态机宿主。子节点中的 KitState 按【节点名】注册为状态。

## 每次完成一次转换后广播(初始进入也广播,from_name 为 "")。
signal state_changed(from_name: String, to_name: String)

## 初始状态;为 null 时取第一个 KitState 子节点。
@export var initial_state: KitState

## 当前状态(只读约定;转换请走 transition_to)。
var current_state: KitState

## 按状态名转换。未知名字 → push_warning + 空操作。
## 语义:old.exit(new_name) → 切换 current_state → new.enter(old_name) → state_changed。
func transition_to(state_name: String) -> void

## 按名取状态节点;未知名字返回 null。
func get_state(state_name: String) -> KitState
```

```gdscript
class_name KitState
extends Node
## 单个状态。全部方法为虚方法,子类按需覆写。

## 宿主状态机;由 KitStateMachine 在 _ready 时注入。
var machine: KitStateMachine

func enter(_prev_state_name: String) -> void
func exit(_next_state_name: String) -> void
func update(_delta: float) -> void            ## 由宿主 _process 转发
func physics_update(_delta: float) -> void    ## 由宿主 _physics_process 转发
func handle_input(_event: InputEvent) -> void ## 由宿主 _unhandled_input 转发

## 语法糖:machine.transition_to(state_name)。
func transition_to(state_name: String) -> void
```

## Behavior & data flow

- **注册**:`KitStateMachine._ready()` 遍历直接子节点,`is KitState` 的按 `node.name` 建 `_states: Dictionary`;为每个注入 `machine = self`。没有任何 KitState 子节点 → `push_warning`,机器保持空转(转发全为空操作)。
- **初始进入**:`_ready` 末尾对 `initial_state`(或第一个 KitState 子节点)执行 `current_state = it; it.enter(""); emit state_changed("", name)`。
- **转发**:宿主的 `_process`/`_physics_process`/`_unhandled_input` 分别调 `current_state.update/physics_update/handle_input`(current_state 为 null 时跳过)。
- **转换与重入**:`transition_to` 期间(exit/enter 执行中)再次调用 `transition_to` 时,请求**入队**而非立即执行;当前转换完成后按序处理队列。连锁上限:同一次外部触发内最多连转 8 次,超过 → `push_error` 并丢弃剩余队列(捕获 enter 里互相转换的死循环)。`enter()` 里立即转走(决策态)是支持的正常用法;`exit()` 里发起转换同样入队(文档注明不推荐)。
- 转换到当前态(`transition_to(current)`)照常执行 exit→enter(可用于"重进重置"),文档注明。

## Key decisions

| # | 维度 | 结论 | 理由 |
|---|---|---|---|
| 1 | 形态 | Node 型(用户拍板) | 编辑器可视化组装/调试;Godot 惯例 |
| 2 | 状态标识 | 节点名(String) | 零配置;场景树里即文档;改名即改 API 的风险文档注明 |
| 3 | 命名 | Kit 前缀 class_name | `State` 撞车重灾区;与门面同一命名纪律 |
| 4 | 依赖 | 零依赖(push_warning 诊断) | per-实体类库应可脱离框架使用与测试 |
| 5 | 重入 | 队列 + 连锁上限 8 | 支持决策态连转;死循环有底 |
| 6 | HSM/守卫/历史 | 不做 | YAGNI;Node 嵌套天然留了 HSM 演化空间 |

## Web-export considerations

纯节点/回调逻辑,零线程、零 IO、零平台 API;无风险面。

## Testable seams + test plan

代码组树即可测:`.new()` 出机器与状态、`add_child` 拼好后加入测试 SceneTree 的 root 触发 `_ready`;或直接手动调 `_ready()`。转发用手动调 `machine._process(0.016)` 驱动。测试用探针状态子类(fixtures 脚本,记录 enter/exit/update 调用序列与参数)。

`test/test_state_machine.gd`(headless):

1. 注册:三个 KitState 子节点按名可 `get_state`;`machine` 引用已注入。
2. 初始进入:`initial_state` 的 enter 被调(prev="")、`state_changed("", name)` 广播;不设 initial_state 时取第一个子节点。
3. `transition_to`:exit(next)/enter(prev) 参数与顺序正确(探针记录序列),`current_state` 更新,信号广播。
4. 未知名字:`push_warning` 路径空操作,current_state 不变。
5. 转发:`_process` 只转发给当前态;转换后旧态不再收到 update。
6. 决策态连转:A.enter 里 transition_to("B"),外部转 A 后最终落在 B,信号广播两次(→A、A→B)。
7. 连锁上限:A.enter→B、B.enter→A 互转,断言 push_error 路径触发后机器停在确定态、不死循环(用连转计数探针验证 ≤ 8)。
8. 转换到当前态:exit/enter 重跑一遍(重进重置语义)。
9. 空机器(无 KitState 子节点):`_ready` 不崩,转发空操作。

## 版本

KitStateMachine/KitState v0.4.0 起:节点名注册、enter/exit/update/physics_update/handle_input、转换队列 + 连锁上限、state_changed 信号、零依赖。
