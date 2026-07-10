# KitStateMachine 增强设计 —— 事件 dispatch 解耦 + pushdown 栈

> 日期:2026-07-10 ｜ 阶段:2「借鉴纳入」3/3(前两轮:KitContext 订阅+scope v0.6.0、SaveManager 序列化+原子写+守卫 v0.7.0)
> 借鉴对象:LimboAI HSM 部分(事件/dispatch 解耦、`ANYSTATE` 通配)+ 经典 pushdown 自动机
> 路线依据:`docs/research/2026-07-10-godot-ecosystem-survey-and-roadmap.md` §2、§7.2

## 1. 背景与现状

`KitStateMachine`(`addons/godot-core-kit/state_machine/kit_state_machine.gd`,104 行)是节点式有限状态机:直接子节点中的 `KitState` 按【节点名】注册,`transition_to(name)` 走 `exit → 切 current_state → enter → state_changed` 广播,`enter`/`exit` 中再触发的转换入 `_pending` 队列、单次外部触发内连转上限 `MAX_CHAIN=8`(死循环守卫)。零依赖(诊断只用引擎原生 `push_warning`/`push_error`)、不挂 `CoreKit` 门面、per-entity(每实体各持一台)。

`KitState`(`addons/godot-core-kit/state_machine/kit_state.gd`,41 行)是状态基类:虚方法 `enter/exit/update/physics_update/handle_input` 按需覆写 + 语法糖 `transition_to`;`machine` 引用故意不标类型(打破两 `class_name` 循环类型引用)。

**现状缺口**:无事件解耦(状态里写死后继态名 `machine.transition_to("Idle")`,转移逻辑散落各状态)、无通配转移、无 pushdown/层级。

## 2. 目标与范围

在现有已测子系统上做**向后兼容的纯增量增强**,叠加两组正交能力:

1. **事件 dispatch 解耦**(核心):集中转移表 `add_transition(from, to, event)`(`from` 支持 `ANYSTATE` 通配)+ `dispatch(event)` —— 状态发命名事件、由机器集中决定后继,状态不再写死后继态名。与现有 `transition_to` **并存**。
2. **pushdown 栈**:`push_state(name)` / `pop_state()` —— 压当前态(暂停语义)、临时进另一态、弹回(菜单/暂停等)。给 `KitState` 增 `pause()`/`resume()` 生命周期钩子。

**明确不做**(YAGNI,见 §9):层级 HSM、consumed 事件处理器、StateMachine 作 Resource、可视化连线编辑器、链式 builder。

## 3. 设计

### 3.1 架构决策:叠加单文件

新增能力**叠加进 `kit_state_machine.gd`**,复用现有转换核心(`_run_transition`/`_transitioning`/`_pending`/`MAX_CHAIN`),与 `transition_to` 并存;`kit_state.gd` 加两个 default-pass 虚方法。**不拆 mixin/新文件**:状态机核心应能一屏读完(叠加后约 190 行仍合理),拆文件会割裂核心、引入跨文件耦合。保持零依赖、不挂门面、per-entity。

### 3.2 事件 dispatch 解耦

**转移表**:`_transitions: Dictionary`,key 为 `"%s|%s" % [from_name, event]`,value 为 `to_name`。`from_name` 可为已注册状态名或 `ANYSTATE`("*")通配。

**匹配优先级**:`dispatch(event)` 先查具体当前态 `(current_state.name, event)`,未命中再查 `(ANYSTATE, event)`。**具体 from 优先于通配**。两者都无匹配 → 静默返回 false(事件派发的常态:多数事件在多数状态无转移)。

**转移执行**:命中后解析出 `to_name`,复用现有转换路径 —— 非转换中直接走 `_run_transition`(exit→enter→state_changed,连锁/`MAX_CHAIN` 语义完全不变);转换进行中则把 `to_name` 入 `_pending`(与 `transition_to` 转换中行为一致)。

**返回值**:`dispatch` 返回 `bool` —— 命中并发起转移(或入队)返回 `true`,无匹配返回 `false`。调用方可据此判断事件是否被消费(轻量、无副作用)。

### 3.3 pushdown 栈(暂停语义)

**栈**:`_stack: Array[String]`,存被压的挂起态**名**(栈底→栈顶)。存名字(非节点引用)与 `_pending` 一致;节点不销毁,`resume` 时仍是同一节点,现场天然保留。`current_state` 始终是活动态(不在栈里,栈存被挂起的态)。

**push_state(name)**:
1. 未知 `name` → `push_warning` + no-op。
2. 转换进行中(`_transitioning`)→ `push_warning` + 拒绝(pushdown 不应在 `enter`/`exit` 里发)。
3. 栈深 ≥ `MAX_STACK` → `push_error` + 拒绝(防无限 push)。
4. 否则:`current_state.pause()` → 当前态名入 `_stack` → `current_state` 切为 `name` 对应态 → 新态 `enter(被压态名)` → `state_changed.emit(被压态名, name)`。

**pop_state()**:
1. 栈空 → `push_warning` + no-op。
2. 转换进行中 → `push_warning` + 拒绝。
3. 否则:`current_state.exit(栈顶态名)` → 弹出栈顶态名 → `current_state` 切为该态 → 该态 `resume()` → `state_changed.emit(被弹出的活动态名, 恢复的栈顶态名)`。

**关键**:push 用 `pause()`(不 `exit`)、pop 用 `resume()`(不重新 `enter`),故被压态**现场保留、不重置** —— 这是暂停语义相对普通转移的本质区别。

**KitState 新增虚方法**(default-pass,老代码不覆写无感):
- `func pause() -> void: pass` —— 本态被 `push_state` 压栈、让位给新态时调用。
- `func resume() -> void: pass` —— 本态经 `pop_state` 从栈顶弹回、重新成为活动态时调用。

### 3.4 关键交互边界

1. **信号复用**:push/pop 改变 `current_state`,复用 `state_changed` 广播(push 发 `(被压态, 新态)`、pop 发 `(被弹活动态, 恢复态)`);不新增 `state_pushed`/`state_popped` 专用信号(YAGNI —— 消费方监听"当前态变化"即可)。
2. **栈非空时** `transition_to`/`dispatch` 正常替换 `current_state`(栈不动),`pop_state` 仍弹回栈下挂起态。栈是"挂起态的历史",活动态照常可转移。
3. **转换进行中**(`_transitioning`):`dispatch` 入 `_pending`;`push_state`/`pop_state` 拒绝(warning)。
4. pushdown **不参与** `MAX_CHAIN` 连锁计数;栈深由 `MAX_STACK` 独立守卫。
5. `ANYSTATE`/事件表在 `_ready` 后随时可 `add_transition`,不与 `initial_state` 冲突。
6. **状态名保留**:`ANYSTATE`("*")为保留名;若某 `KitState` 子节点名恰为 "*",`_ready` 注册时 `push_error`(该名会与通配 key 混淆)。

## 4. API 增量(精确签名)

**KitStateMachine 新增:**
```gdscript
const ANYSTATE := "*"           # 通配 from 状态名
const MAX_STACK := 32           # pushdown 栈深守卫

var _transitions: Dictionary = {}   # "from|event" -> to_name
var _stack: Array[String] = []      # 被压挂起态名(栈底->栈顶)

## 登记一条事件转移。from_name 可为已注册态名或 ANYSTATE;event 为命名事件。
## to_name 未注册 -> push_warning + 忽略;同 (from,event) 重复登记 -> 覆盖 + push_warning。
func add_transition(from_name: String, to_name: String, event: String) -> void

## 按当前态派发事件:先查 (current, event) 再查 (ANYSTATE, event),命中则转移
## (非转换中走 _run_transition;转换中入 _pending)返回 true;无匹配静默返回 false。
func dispatch(event: String) -> bool

## 压栈:current.pause() -> 当前态入栈 -> 进 state_name(enter)。未知态/转换中/栈满 -> 拒绝。
func push_state(state_name: String) -> void

## 弹栈:current.exit(栈顶) -> 弹栈顶 -> 该态 resume()。栈空/转换中 -> 拒绝。
func pop_state() -> void

## 只读当前栈深(调试/测试)。
func stack_depth() -> int
```

**KitState 新增:**
```gdscript
## 本态被 push_state 压栈、让位给新态时调用(暂停语义,现场保留)。默认空。
func pause() -> void

## 本态经 pop_state 从栈顶弹回、重新成为活动态时调用。默认空。
func resume() -> void
```

## 5. 数据流

**事件派发**:
```
状态内 machine.dispatch("hit")  或  外部 sm.dispatch("hit")
  -> 查 _transitions["<current>|hit"],未命中查 _transitions["*|hit"]
  -> 命中 to_name:非转换中 _run_transition(exit->enter->state_changed,连锁/MAX_CHAIN 不变)
                   转换中 _pending.append(to_name)
  -> 返回 true;无匹配返回 false(静默)
```

**pushdown**:
```
sm.push_state("PauseMenu")
  -> current.pause() -> _stack.append(current 名) -> current 切 PauseMenu -> PauseMenu.enter(旧名) -> state_changed
sm.pop_state()
  -> current.exit(栈顶名) -> 弹栈顶 -> current 切回该态 -> 该态.resume() -> state_changed
update/physics_update/handle_input:始终只转发 current_state(栈下挂起态不收)
```

## 6. 错误处理(沿用"诊断用 push_warning/push_error、不抛异常、零依赖"风格)

| 场景 | 处理 |
|---|---|
| `add_transition` to 未注册 | `push_warning` + 忽略 |
| `add_transition` 同 (from,event) 重复 | 覆盖 + `push_warning` |
| `dispatch` 无匹配 | 静默返回 `false`(常态) |
| `push_state` 未知态 | `push_warning` + no-op |
| `push_state` 栈满(≥MAX_STACK) | `push_error` + 拒绝 |
| `push_state`/`pop_state` 转换进行中 | `push_warning` + 拒绝 |
| `pop_state` 栈空 | `push_warning` + no-op |
| 子节点名撞 `ANYSTATE`("*") | `_ready` 注册时 `push_error` |

## 7. 测试策略(扩展 `test/test_state_machine.gd`,headless 断言)

复用现有 `_build` 探针组树 + journal 机制。探针状态需记录 `pause`/`resume` 调用(扩展 `probe_state.gd` 或新增探针)。

**事件派发:**
1. `add_transition` + `dispatch` 命中具体 from → 转移到目标态。
2. `ANYSTATE` 通配:任意态 dispatch 该事件都转移。
3. **具体 from 优先 ANYSTATE**:同 event 既有具体又有通配,当前态命中具体的。
4. 无匹配:`dispatch` 返回 `false`、current_state 不变、无 exit/enter。
5. 重复 `add_transition` 覆盖:后者生效。
6. dispatch 复用转换核心:journal 序列为 exit→enter、发 state_changed。
7. 转换中 dispatch 入队:决策态 enter 里 dispatch,最终落队列目标态。

**pushdown:**
8. `push_state`:旧态 `pause()` 被调、栈深+1、新态 `enter(旧名)`、state_changed。
9. `pop_state`:活动态 `exit(栈顶名)`、栈深-1、恢复态 `resume()` 被调、**未重新 enter**(探针验 resume 计数=1 且 enter 计数不增)、state_changed。
10. 栈空 `pop_state`:no-op、current 不变。
11. `MAX_STACK` 守卫:连续 push 超上限被拒、栈深不超 `MAX_STACK`。
12. push 后 `update` 只转发栈顶活动态(栈下挂起态不收 update)。
13. push/pop 转换中拒绝:`_transitioning` 时调用 no-op。

**向后兼容:**
14. 现有 9 组断言(注册/初始进入/transition_to/未知名/转发/决策态连转/死循环守卫/自转换重进/空机器)全绿不变。

## 8. 版本与文档

- **版本 `0.7.0 → 0.8.0`**:`core_kit.gd` 的 `const VERSION`、`plugin.cfg` 的 `version` + `description`、`test/test_core_kit.gd` 硬编码版本断言(既定维护模式,三处同步)。
- **`addons/godot-core-kit/docs/state-machine.md`**:增「事件派发解耦」「pushdown 栈」两节 + `pause`/`resume` 虚方法 + `add_transition`/`dispatch`/`push_state`/`pop_state`/`stack_depth` API + 注意事项(ANYSTATE 保留名、暂停语义现场保留、栈深守卫)。
- **`addons/godot-core-kit/docs/architecture.md`**:「## 版本」段补 0.8.0。
- **`README.md`**:changelog 补 0.8.0。
- **`demo/demo.gd`**:状态机冒烟增 `dispatch` + `push_state`/`pop_state` 演练(marker present、stderr clean)。

## 9. YAGNI / 明确排除

- **层级 HSM**(嵌套状态、leaf→root 事件冒泡):成本高,留待有真实需求再单独立项。
- **consumed 事件处理器**(状态可消费事件而不转移):本轮范围未选。
- **StateMachine 作 Resource**(gd-YAFSM 式一图多实体复用)、可视化连线编辑器。
- **链式 builder API**、专用 `state_pushed`/`state_popped` 信号、`clear_stack` 等便利方法。

## 10. 向后兼容保证

纯叠加:现有公开面(`transition_to`/`get_state`/`current_state`/`state_changed`/`initial_state`/`MAX_CHAIN`、`KitState` 五虚方法 + 语法糖)签名与语义**零改动**;新增 `pause`/`resume` 为 default-pass 虚方法,老状态子类不覆写完全无感;`_run_transition`/`_transitioning`/`_pending` 逻辑不改,事件派发/pushdown 都复用或旁路,不侵入既有转换语义。扩展后测试共约 22 个断言块(现有 9 组 + 本 spec §7 新增 13 项);现有 9 组断言(注册/初始进入/`transition_to`/未知名/转发/决策态连转/死循环守卫/自转换重进/空机器)逐字保留、必须全绿。
