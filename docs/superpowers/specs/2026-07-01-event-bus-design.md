# godot-core-kit EventBus 子系统设计

- 日期：2026-07-01
- 状态：已确认，待实现
- 版本目标：0.3.0
- 前置：`2026-07-01-godot-core-kit-scaffold-design.md`（脚手架）、`2026-07-01-logger-design.md`（同款 autoload + 可测接缝约定，本子系统的参考基线）
- 来源：`.superpowers/sdd/proposals/event-bus.md`（设计提案），本文档为用户拍板 Open Questions 后的定稿版

**本文档范围**：`EventBus` 的公开 API、行为语义与测试计划。autoload 注册（`plugin.gd`/`project.godot`）、版本号落地（`plugin.cfg`/`core_kit.gd`）、README、demo 冒烟属于后续独立的**集成步骤**，不在本设计文档展开（参见配套的 TDD 实现计划 `2026-07-01-event-bus.md` 中的显式说明）。

---

## 目标与定位

`EventBus` 是一个全局发布/订阅（pub/sub）中枢，用**字符串事件名**解耦"发出事件的一方"与"关心事件的一方"，用于 Godot 节点树里没有直接父子/引用关系、不方便直连 Godot 原生 `signal` 的跨模块通信场景（如 UI 关心"存档完成"但不认识存档模块、成就系统关心"敌人死亡"但不想被每个敌人节点单独 `connect`）。

定位边界：

- **补充**而非取代 Godot 原生 `signal`——两节点有直接引用关系时，原生 `signal`/`connect` 仍是首选（更快、类型更强、编辑器可视化）。`EventBus` 只用于"谁会关心不确定/没有引用关系"的广播场景。
- **可选、零依赖**：不依赖 `SceneManager`/`ObjectPool`/`SaveManager`，也不依赖本仓库的 `Log`；那些子系统若要用 `EventBus`，反过来通过其公开 API 接入（不反向耦合）。
- 首版严格 YAGNI：只做"按字符串事件名订阅/发布 + 安全的生命周期与重入语义"，不做事件优先级、跨帧延迟队列、网络同步、事件录制回放、未订阅事件的拼写诊断。

---

## Public API（GDScript 精确签名）

```gdscript
extends Node
## EventBus —— godot-core-kit 全局发布/订阅事件总线。
## 以 autoload "EventBus" 注册。

## 每次 publish() 之后广播一次，payload 为 null 表示无载荷。
## 用于旁路监听"全部事件"（调试面板、埋点），常规业务订阅请用 subscribe()。
signal event_published(event_name: String, payload: Variant)

## 订阅 event_name。listener 应为形如 func(payload: Variant) -> void 的 Callable。
## 同一 (event_name, listener) 重复订阅为幂等空操作（不会重复触发）。
## once = true 等价于 subscribe_once()。event_name 不可为空字符串（保留给 clear() 语义）。
func subscribe(event_name: String, listener: Callable, once: bool = false) -> void

## 语法糖：subscribe(event_name, listener, true)。触发一次后自动取消订阅。
func subscribe_once(event_name: String, listener: Callable) -> void

## 取消订阅指定 (event_name, listener)。listener 未订阅时为空操作，不报错。
func unsubscribe(event_name: String, listener: Callable) -> void

## 取消 target 在所有事件上的全部订阅（Callable.get_object() == target 的都移除）。
## 用于对象在 _exit_tree()/queue_free 前主动清理，是自动失效清理（见下）之外的显式手段。
func unsubscribe_all(target: Object) -> void

## 同步派发 event_name。按订阅顺序（FIFO）依次调用当前快照里的 listener.call(payload)。
## 派发期间对该事件的 subscribe/unsubscribe 只影响下一次 publish()，不影响本次快照。
## 无论是否有订阅者，都会额外广播一次 event_published 信号（供旁路监听）。
func publish(event_name: String, payload: Variant = null) -> void

## 是否存在至少一个有效订阅（查询时惰性剔除已失效的 Callable）。
func has_listeners(event_name: String) -> bool

## 返回 event_name 当前有效订阅数（查询时惰性剔除已失效的 Callable）。
func get_listener_count(event_name: String) -> int

## 清空指定事件的全部订阅；event_name 为空字符串（默认）时清空所有事件的全部订阅。
## 供测试隔离 / 场景切换重置使用。
func clear(event_name: String = "") -> void
```

命名说明（避开与 `Node` 内置 API 混淆）：`EventBus extends Node`，`Node` 自带 `emit_signal`/`connect`/`disconnect`。发布方法故意不叫 `emit`——若叫 `emit`，容易被读成"是不是该用 `emit_signal`"。本设计用 **`publish`/`subscribe`/`unsubscribe`** 这套 pub/sub 术语，与 Godot 原生信号的 `emit_signal`/`connect`/`disconnect` 在词汇上明确区分，降低"两套机制混着读代码"的认知负担。

---

## Behavior & data flow（行为与数据流）

### 内部数据结构

```gdscript
# event_name(String) -> Array[_Subscription]
var _listeners: Dictionary = {}

class _Subscription:
    extends RefCounted
    var callable: Callable
    var once: bool
```

- 用内部类 `_Subscription` 而非裸 `Callable` 数组，是为了让 `once` 标记跟随每条订阅记录本身，不需要额外一份平行数组或把状态编码进 `Callable.bind()` 里。
- `Dictionary` 的 key 是事件名字符串；value 是该事件当前订阅记录的有序数组（插入顺序 = 触发顺序）。

### subscribe / subscribe_once

1. `event_name` 为空字符串 → 视为非法调用，直接返回（不新增订阅）；空字符串保留给 `clear()` 的"全清"语义。
2. 在该事件桶里查找是否已存在 `callable == listener` 的记录（`Callable` 支持 `==` 比较目标对象 + 方法 + 绑定参数）；存在则视为幂等重复订阅，直接返回，不新增第二条记录、不报错、不打日志。
3. 否则在桶尾追加新的 `_Subscription`。桶不存在则先创建空数组。

### unsubscribe / unsubscribe_all

- `unsubscribe`：在事件桶里按 `callable == listener` 查找并移除；未找到则空操作。桶被清空后从 `_listeners` 里删掉该 key（保持内部状态干净，`has_listeners` 语义简单）。
- `unsubscribe_all(target)`：遍历所有事件桶，移除 `callable.get_object() == target` 的记录；同样清理空桶。

### publish（核心：快照 + 惰性剔除失效监听）

1. 取出 `event_name` 对应的实时订阅数组（不存在则视为空数组）。
2. **对该实时数组做一次快照**（浅拷贝，如 `bucket.duplicate()`），后续遍历只读快照，不读实时数组——这样，若某个 handler 在被调用过程中对同一事件 `subscribe`/`unsubscribe`，只会影响*下一次* `publish()`，本次快照里已经固定的调用列表和顺序不受干扰。这是本设计对"重入安全"的核心保证。
3. 按快照顺序（= 订阅顺序，FIFO）逐个处理每条订阅记录：
   - 若 `not subscription.callable.is_valid()`（目标对象已被 `free()`）→ 记入"待剔除"列表，不调用。这就是监听对象被释放后的**自动清理**：不需要监听方手动 `unsubscribe()`，下次该事件 `publish()` 时会被静默从实时数组里摘除。
   - 否则 `subscription.callable.call(payload)`；若 `subscription.once` 为真，同样记入"待剔除"列表（一次性订阅触发后即失效）。
4. 遍历结束后，把"待剔除"列表里的记录从**实时**数组（不是快照）里摘除，桶变空则删 key。
5. 无论第 1 步桶是否为空、是否有任何有效监听者，都执行 `emit_signal("event_published", event_name, payload)`——这是 `EventBus` 自身的原生 Godot 信号，供不关心具体某个事件名、只想"旁观全部事件流"的用途（调试面板、埋点/回放）订阅，不需要逐个 `subscribe()`。此信号在**目标订阅者都调用完之后**才发，语义是"这轮 publish 已完成"。

### has_listeners / get_listener_count

- 两者在读取前都对目标事件桶做一次与 `publish()` 相同的"剔除失效 Callable"扫描（不触发调用，只判 `is_valid()` 并摘除），再返回剩余数量/是否非空。选择"读时也顺手剔除"而非"只有 publish 才剔除"，是为了让"对象释放后订阅立刻消失"这件事在自动化测试和调试工具里可直接断言，不必先手动 `publish()` 一次才能验证清理生效。

### RefCounted 监听者的边界情况（需要写进代码注释与后续 README）

`Callable` 绑定到 `RefCounted`（含普通 `class ... extends RefCounted` 脚本对象、`Resource` 等）的方法时，`Callable` 本身会持有该对象的一份强引用，**只要订阅还在，目标对象就不会被引用计数归零**——也就是说，纯 `RefCounted` 监听者*不会*自然触发"自动剔除失效 Callable"这条路径（它压根不会变成 invalid），必须显式 `unsubscribe()`/`unsubscribe_all()`。自动剔除主要覆盖的是 **`Node`/`Object`（非引用计数）监听者**——它们的 `free()`/`queue_free()` 会让引用它的 `Callable` 立刻变 `invalid`，即使还有 `EventBus` 内部数组"引用"着它。这正好覆盖了 Godot 项目里最常见的"UI 节点/游戏实体订阅、随场景切换被销毁"场景；纯逻辑对象监听仍需自律。

---

## Key decisions（关键决定，已确认）

| # | 维度 | 结论 | 理由 |
|---|---|---|---|
| 1 | 事件标识 | 任意字符串事件名；`EventBus` 不内置枚举/校验，消费方自建 `const` 目录收敛命名（如 `const PLAYER_DIED := "player_died"`） | `EventBus` 要跨任意游戏项目复用，不该预知任何具体游戏的事件词汇；字符串命名空间的收敛交给消费方自己的常量文件 |
| 2 | 方法命名 | `publish`/`subscribe`/`subscribe_once`/`unsubscribe`/`unsubscribe_all`/`clear`/`has_listeners`/`get_listener_count` | 与 `Node` 继承来的 `emit_signal`/`connect`/`disconnect` 在词汇上明确区分，避免"两套广播机制混读" |
| 3 | payload 形状 | 单个 `Variant`（默认 `null`），多值由调用方自行打包 Dictionary/自定义 Resource | 纯 GDScript 用户函数没有真正的 varargs，仿 varargs 只能靠一串占位参数，签名丑且有歧义；单参数最简单无歧义 |
| 4 | 监听者生命周期 | 惰性自动剔除失效 `Callable`（`is_valid()`），无需手动 `unsubscribe` | 游戏里 Node 频繁随场景销毁，忘记 `unsubscribe()` 是最常见的一类隐蔽 bug；`Callable.is_valid()` 检查代价极低，在 `publish()`/查询时顺手做，不需要轮询或定时器（Web 友好） |
| 5 | `subscribe_once` | 首版内置，作为 `subscribe(..., once=true)` 的语法糖 | 实现成本只是给订阅记录加一个 bool 标记，但"等下一次 XX 事件"是非常高频的真实需求，不该被 YAGNI 砍掉 |
| 6 | 重入 / 派发期间增删订阅 | 派发前做一次浅拷贝快照，只遍历快照 | 唯一能同时保证"本次派发不因 handler 内部 subscribe/unsubscribe 而崩溃或产生不确定行为"且实现简单（一行 `duplicate()`）的方案；派发中新增订阅延后到下次 `publish()` 生效，语义清晰可文档化 |
| 7 | "监听全部事件"的旁路能力 | **v1 保留**：额外提供 `EventBus` 自身的原生 Godot `signal event_published(event_name, payload)`，每次 `publish()` 后广播 | 调试面板/埋点这类"旁观全部事件流"的需求，用一个原生 `signal` 比强迫使用方对每个事件名都 `subscribe` 一个转发函数更省事，实现成本只是一行 `emit_signal`；同时是本子系统"须在相关之处使用自己的 Godot signal"这条独立性原则最自然的落点 |
| 8 | 重复订阅同一 `(event_name, Callable)` | 幂等去重，静默忽略第二次 `subscribe` | 与 Godot 原生 `connect()` 默认拒绝重复连接的直觉一致；游戏里 `_ready()` 因编辑器热重载/节点复用被多次调用是常见诱因，去重比"惊喜地被调用两次"更安全 |
| 9 | 是否依赖 `Log` 做未订阅事件/拼写诊断 | **不做**：v1 完全不依赖 `Log`，不加任何诊断开关，所有边界情况静默处理，`EventBus` 保持零依赖 | 保持 `EventBus` 在测试环境（`SceneTree` headless 直接 `.new()` 实例化，`Log` autoload 是否就绪不确定）下的行为与生产环境完全一致，零外部依赖，最大化可测性；拼写不一致的问题交给消费方自建的 `const` 事件名目录约定兜底 |

---

## Web-export considerations（Web 导出兼容性）

- **零线程依赖**：`publish()` 全程同步执行（遍历快照 → 逐个 `Callable.call()`），没有 `Thread`/`Mutex`/`WorkerThreadPool`，天然满足 Web 导出对"不能依赖真线程"的约束，也让派发顺序可预测（不会有跨线程的调用交织）。
- **无轮询/定时器**：自动剔除失效监听靠"下次访问该事件桶时惰性检查 `Callable.is_valid()`"，不用 `_process`/`Timer` 周期扫描全部事件——既省性能，也避免 Web 导出下 `_process` 节奏受浏览器标签页可见性影响导致的清理延迟问题。
- **无文件 IO、无桌面专有 API**：不落盘、不读写 `OS`/`DisplayServer` 桌面专属接口、不用 `OS.execute`、不用 GDExtension；用到的 `Callable`/`Dictionary`/`Array`/`Object.is_instance_valid`/原生 `signal` 均是纯 GDScript/Variant 层 API，Web 导出下行为与桌面一致。
- **同步派发 vs `call_deferred`**：v1 故意不提供"延迟到下一帧派发"的选项——同步语义最简单可预测，且 Web 导出的单线程主循环模型本来就不排斥未来加一个可选的 `call_deferred` 派发模式；这条留到有真实需求（比如某个监听者要求不能在当前调用栈里被重入触发）时再加，不在 v1 抢跑。

---

## Testable seams + test plan（可测接缝与测试计划）

### 可测接缝

与 `Log` 不同，`EventBus` 的核心行为（`subscribe`/`unsubscribe`/`publish` 本身）**不需要额外拆一层 `_should_xxx` 纯函数**——因为整个公开 API 天然就是"纯 `Object` 层逻辑"：`Dictionary`/`Array`/`Callable.call()`/原生 `signal` 都不要求对象是活跃的 autoload、不依赖场景树、不依赖 `Log`。因此测试可以像 `test_log.gd` 一样，直接：

```gdscript
const EventBusScript := preload("res://addons/godot-core-kit/event_bus.gd")
var bus = EventBusScript.new()
```

在裸实例上调用全部公开方法即可覆盖核心行为，不需要 `EventBus` autoload 处于就绪状态。

### `test/test_event_bus.gd`（headless 断言，测试用例清单）

1. **基本订阅/发布**：`subscribe("evt", handler)` 后 `publish("evt", {"x": 1})`，断言 `handler` 恰好被调用一次且收到的 `payload` 与传入一致。
2. **多订阅顺序**：同一事件订阅 A、B、C 三个 handler，`publish` 一次，断言调用顺序为 A→B→C（FIFO）。
3. **`unsubscribe` 生效**：`unsubscribe("evt", handler)` 后再 `publish`，断言不再被调用。
4. **事件名隔离**：订阅 `"a"` 的 handler 在 `publish("b", ...)` 时不应被调用。
5. **`subscribe_once`**：触发一次后，第二次 `publish` 不再调用；`get_listener_count` 从 1 变回 0。
6. **重复订阅去重**：同一 `(event_name, Callable)` `subscribe` 两次，`publish` 一次只触发一次调用；`get_listener_count` 恒为 1。
7. **自动剔除失效监听（Node 场景）**：构造一个临时 `Node`、订阅其一个方法、`node.free()`；断言随后 `publish` 不报错、不再调用该方法，且 `get_listener_count` 回落到 0（验证读取路径的惰性剔除）。
8. **`unsubscribe_all(target)`**：同一对象的方法订阅了两个不同事件，`unsubscribe_all(target)` 后两个事件各自 `publish` 均不再触发。
9. **重入安全（派发中 subscribe）**：handler A 在被调用时对同一事件 `subscribe` 一个新 handler D；断言本次 `publish` 内 D 不被调用，但下一次 `publish` D 会被调用。
10. **重入安全（派发中 unsubscribe）**：handler A 在被调用时 `unsubscribe` 本轮快照里尚未轮到的 handler C；断言 C 在**本轮**仍被调用一次（快照语义），下一轮才真正消失。
11. **`event_published` 旁路信号**：用局部 lambda `connect` 到 `bus.event_published`，连续 `publish` 两个不同事件名（其中一个没有任何 `subscribe` 订阅者），断言旁路 lambda 两次都被触发、且拿到正确的 `(event_name, payload)`，包括零订阅者的那次。
12. **`clear(event_name)` 与 `clear()`**：分别验证清指定事件、清全部事件后，`has_listeners`/`get_listener_count` 归零，`publish` 不再触发任何已订阅的 handler。
13. **默认 payload**：`publish("evt")`（不传 payload）时 handler 收到的参数为 `null`。

沿用 `Log` 的 harness 形态：`test_event_bus.gd` `extends SceneTree`，`_initialize()` 里跑上述断言、累计 `failures`，全部通过 `quit(0)` 打印 `test_event_bus: ALL PASS`，否则逐条打印失败详情并 `quit(1)`。运行方式同 `test_log.gd`：`godot --headless --path . -s res://test/test_event_bus.gd`。

### 冒烟

demo 场景里加一小段：`EventBus.subscribe(...)` + `EventBus.publish(...)` 跑通一次，肉眼确认无报错、业务回调按预期触发；这部分与 autoload 接线一并留给后续集成步骤，不在本设计文档展开。

---

## 版本

EventBus v0.3.0 起：`EventBus` 全局单例，字符串事件名 pub/sub、单 `Variant` payload、惰性自动清理失效监听、`subscribe_once`、重入安全的快照派发、`event_published` 旁路信号、`clear`/`has_listeners`/`get_listener_count`。不依赖 `Log`/`SceneManager`/`ObjectPool`/`SaveManager`。autoload 接线属独立集成步骤，随该步骤一并完成版本落地（`plugin.cfg`、`core_kit.gd`、`README.md`）。
