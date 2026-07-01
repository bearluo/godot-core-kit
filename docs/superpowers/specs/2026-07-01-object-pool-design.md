# godot-core-kit ObjectPool 子系统设计

- 日期：2026-07-01
- 状态：已确认，待实现
- 版本目标：0.3.0
- 参考基线：`log.gd` / `2026-07-01-logger-design.md`（同款 autoload + 可测接缝约定）
- 前置：`2026-07-01-godot-core-kit-scaffold-design.md`、`2026-07-01-logger-design.md`
- 范围：本文档为已确认设计，覆盖 `ObjectPool` 子系统本身的公开 API 与行为。autoload
  接线（`plugin.gd`/`project.godot`）、版本号落地（`plugin.cfg`/`CoreKit.VERSION`）、
  `README.md`、demo 场景均属**后续独立集成步骤**，不在本文档范围内（配套实现计划
  `2026-07-01-object-pool.md` 同样只覆盖 `object_pool.gd` + 测试）。

## Purpose（目标与定位）

`ObjectPool` 是全局对象池单例：按**字符串 key** 管理若干个具名节点池，复用子弹、敌人、粒子等
高频 spawn/despawn 的 `Node` 实例，避免反复 `instantiate()`/`free()` 造成的实例化开销与内存
抖动（尤其在 Web/WASM 导出下更明显）。

定位边界：

- 只管“实例复用”这一件事：借出（acquire）、归还（release）、按 key 分桶记账、可选预热与上限。
  **不管**对象的具体游戏逻辑（伤害、AI、动画）——那些仍由被池化场景自己的脚本负责。
- 纯内存操作，无文件 IO，不用线程；对 `Log` 子系统单向可选依赖（记录告警/错误），不依赖
  EventBus / SceneManager / SaveManager（独立性原则）。
- 首版严格 YAGNI：不做场景切换时自动清池（那是调用方结合 `clear()` 自己接的事）、不做池的
  运行时动态扩缩容策略、不做多线程预热、不做池优先级/权重、不做“挤掉最旧实例”式的抢占策略。

## Public API（GDScript 精确签名）

```gdscript
extends Node
## ObjectPool —— godot-core-kit 全局对象池单例。
## 以 autoload "ObjectPool" 注册。

## 节点上的元数据 key：本子系统创建的每个实例都会打上（归属的池 key）。
## release() 靠它判定“这是不是我这个池发出去的节点”，不需要额外维护一份反查表。
const META_POOL_KEY := "__object_pool_key"

## 注册一个池。scene 的根节点类型会被反复 instantiate() 复用。
## prewarm：注册时立即创建并放入空闲队列的实例数，默认 0（不预热）。
## max_count：该 key 允许存在的实例总数上限（in_use + available），0 = 不限（默认）。
## manage_visibility：true（默认）时 acquire()/release() 对称管理 CanvasItem/Node3D 的
## visible 属性（借出时显示、归还时隐藏）；false 时池完全不碰可见性，交给调用方自行
## 处理（例如自定义淡入淡出过渡）。
## 若 key 已存在且 scene 与原来是同一个 Resource：幂等重复注册，静默忽略。
## 若 key 已存在但 scene 不同：Log.warn，保留原池，不覆盖。
func register(key: String, scene: PackedScene, prewarm: int = 0, max_count: int = 0, manage_visibility: bool = true) -> void

## key 是否已注册过池。
func has_pool(key: String) -> bool

## 取一个可用实例：优先复用空闲队列（LIFO），为空则按 max_count 决定新建或返回 null。
## key 未注册 → Log.error 并返回 null。已达 max_count 且无空闲 → Log.warn 并返回 null
## （不做“挤掉最旧实例”式的抢占，见 Key design decisions #8）。
## 返回的节点处于游离态（不在任何场景树上）；是否/何时 add_child 由调用方决定。
func acquire(key: String) -> Node

## 归还一个由 acquire() 借出的节点。安全处理：node 为 null / 已失效、非本子系统创建的
## 节点、对同一节点重复 release，均为静默 no-op（附 Log.warn），绝不抛错/崩溃。
## 正常路径：调用节点的可选钩子 _pool_reset()（若定义）→ 隐藏（manage_visibility 且为
## CanvasItem/Node3D）→ 记账挪回所属池的空闲队列 → 用 call_deferred 从当前父节点摘下
## （见下节“为什么 deferred”）。
func release(node: Node) -> void

## 释放指定 key 当前空闲（available）的全部实例（queue_free）并清空空闲队列；
## 仍在使用中（in_use）的实例不受影响（若非空会 Log.warn，但不阻止 clear 执行）。
## 池的注册信息（scene / max_count / manage_visibility）保留，之后仍可 acquire()
## （空闲队列为空时会重新 instantiate）。
func clear(key: String) -> void

func available_count(key: String) -> int
func in_use_count(key: String) -> int
func total_count(key: String) -> int   # available_count + in_use_count
```

### `_pool_reset()` 契约（被池化场景可选实现，非 `ObjectPool` 自身方法）

```gdscript
## 可选：由被池化场景的根节点脚本自行实现。release() 归还时若存在会调用一次，
## 用于清空本轮使用留下的状态（计时器、目标引用、动画进度……）。
## 调用时机保证节点已至少完整经历过一次 _ready()（正常用法下 release() 前调用方
## 已 add_child() 过至少一次），@onready 引用可安全访问。
## prewarm 阶段创建的实例、从未被 acquire 过就直接调用 release() 的节点不受此保证
## 约束（后者属误用，@onready 判空是钩子实现自己的责任）。
func _pool_reset() -> void
```

`release()` 用 `has_method("_pool_reset")` 探测是否存在（duck-typing，不要求实现任何接口/
继承任何基类），不存在则跳过，不报错。

## Behavior & data flow（行为与数据流）

### 内部数据结构

```gdscript
class _PoolEntry:
    extends RefCounted
    var scene: PackedScene
    var max_count: int = 0            # 0 = 不限
    var manage_visibility: bool = true
    var total_count: int = 0          # 已创建的实例总数（in_use + available）
    var available: Array = []         # 空闲栈，LIFO（pop_back 复用最近归还的一个）
    var in_use: Dictionary = {}       # instance_id(int) -> true，当前借出的实例

# key(String) -> _PoolEntry
var _pools: Dictionary = {}
```

`_PoolEntry` 不对外暴露（不是 `class_name`），只是把每个 key 的记账封装成独立单元，供 headless
测试直接构造 `ObjectPool` 脚本实例后访问 `_pools[key]` 断言（同 `Log` 把 `_should_log`/
`format_line` 设计成可直接调用的私有方法一个思路）。`manage_visibility` 随 `register()` 的参数
落到对应 `_PoolEntry` 实例上，是池级别（per-key）配置，不是全局开关——同一进程里可以同时存在
“对称管理可见性”的子弹池与“调用方自定义过渡”的特效池。

### `register(key, scene, prewarm, max_count, manage_visibility)`

1. 校验 `scene` 非空且 `scene.can_instantiate()`；否则 `Log.error(...)`，不注册，直接返回
   （即便 `key` 已存在也不动已有池——校验在“是否已注册”判断之前）。
2. `key` 已存在：`entry.scene == scene`（同一 Resource 引用）→ 幂等忽略；不同 → `Log.warn(...)`，
   保留原 `_PoolEntry`，不覆盖。两种情况都直接返回，不重建 `_PoolEntry`。
3. 新建 `_PoolEntry`，`max_count`/`manage_visibility` 原样落到实例字段。若 `max_count != 0`
   且 `prewarm > max_count`：把 `prewarm` **向下收紧**到 `max_count`（附 `Log.warn`，配置矛盾
   时优先满足上限约束而不是把上限抬高去迁就 prewarm）。
4. 循环收紧后的 `prewarm` 次：`scene.instantiate()` → `node.set_meta(META_POOL_KEY, key)` →
   `entry.available.append(node)`、`entry.total_count += 1`。**不**调用 `_pool_reset()`（这些
   实例从未被使用过，没有状态需要重置；调用时机的坑见下方专节）。

### `acquire(key)`

1. `_pools.get(key)` 为空 → `Log.error("acquire: 未注册的 key")`，返回 `null`。
2. 若 `entry.available` 非空：循环 `pop_back()`，用 `is_instance_valid()` 校验——有效则跳出并
   使用；无效（被外部绕过 `release()` 直接 `free()` 掉的僵尸引用）则丢弃、`entry.total_count -=
   1`，继续弹下一个，直到拿到有效实例或队列耗尽。
3. 队列耗尽仍需新建：若 `entry.max_count > 0 and entry.total_count >= entry.max_count` →
   `Log.warn("acquire: 池 '%s' 已达上限")`，返回 `null`；否则 `entry.scene.instantiate()` →
   打 `META_POOL_KEY` 标签 → `entry.total_count += 1`。
4. 若节点仍挂着父节点（例如上一次 `release()` 的 `call_deferred` 摘除还没执行到，见下方竞态
   说明）：同步 `remove_child` 兜底摘除。
5. 若 `entry.manage_visibility` 为真且节点是 `CanvasItem` 或 `Node3D`：`visible = true`。
6. `entry.in_use[node.get_instance_id()] = true`，返回节点。

### `release(node)`

1. `node == null` 或 `not is_instance_valid(node)` → `Log.warn(...)`，返回。
2. `not node.has_meta(META_POOL_KEY)` → 非本子系统创建的节点 → `Log.warn(...)`，返回（不触碰、
   不代为释放，节点归属权仍在调用方）。
3. `key = node.get_meta(META_POOL_KEY)`；`entry = _pools.get(key)` 为空（池已被某种方式移除的
   极端情况）→ `Log.warn(...)`，返回。
4. `not entry.in_use.has(node.get_instance_id())` → 该节点当前并未处于“借出”状态（重复
   release，或从未被 acquire 过就直接调用）→ `Log.warn(...)`，返回。
5. 正常路径：`entry.in_use.erase(node.get_instance_id())`；若 `node.has_method("_pool_reset")`
   → 调用一次；若 `entry.manage_visibility` 为真且为 `CanvasItem`/`Node3D` → `visible = false`；
   `entry.available.append(node)`；若 `node.get_parent() != null` →
   `node.get_parent().remove_child.call_deferred(node)`。

### `clear(key)`

1. `entry = _pools.get(key)` 为空 → 直接返回（`has_pool` 语义下的空操作，不算错误）。
2. 若 `entry.in_use.size() > 0` → `Log.warn("clear: 池 '%s' 仍有 N 个实例在使用中")`（仅提示，
   不阻止后续步骤）。
3. 对 `entry.available` 里的每个节点 `queue_free()`；清空 `entry.available`；
   `entry.total_count -= 释放的数量`（即回落到仅剩 in_use 部分）。
4. `_pools[key]` 本身保留（`scene`/`max_count`/`manage_visibility` 不变），不等于
   `unregister`。

### `release()` 里的 `remove_child` 为什么要 `call_deferred`

`release()` 在真实用法里经常从节点自己的碰撞信号回调（`area_entered`/`body_entered`）里同步
调用（“子弹撞到敌人 → 自己触发归还”是最典型的池化场景）。Godot 对物理体在自身碰撞回调内被同步
改动场景树（含 `remove_child`/`free()`/重新挂父节点）有已知的 “flushing queries” 报错风险。
`queue_free()` 之所以在这类回调里天然安全，是因为它本来就把真正的释放推迟到当帧末尾；本设计让
`release()` 的树结构变更部分（`remove_child`）复刻同一保证——`call_deferred`，而记账、隐藏、
`_pool_reset()` 都是纯属性/字典操作，没有这个风险，保持同步执行以便测试与调用方立刻能读到最新
计数。副作用：`release()` 之后紧接着同一帧内再 `acquire()` 到*同一个*节点时，它可能还没真正被
摘下父节点——这正是 `acquire()` 步骤 4 那次同步兜底 `remove_child` 存在的原因，把竞态在拿到节点
交给调用方之前关闭掉。

### `_pool_reset()` 为什么选在 `release()` 时机，而不是 `acquire()`/prewarm 时机

`@onready` 变量与 `_ready()` 只在节点**第一次进入场景树**时执行。`register()` 的 prewarm 阶段
只是 `instantiate()`，节点还从未进过树；如果在这个时间点或“首次 acquire() 返回前”调用
`_pool_reset()`，任何依赖 `@onready` 子节点引用的重置逻辑都会摸到 `null`。而到 `release()` 被
调用时，节点在正常用法下已经被调用方 `add_child` 过至少一次（本设计不认为“从未挂树就直接
release” 是被鼓励的用法，即便发生也只是钩子实现里 `@onready` 判空的责任）。因此约定
`_pool_reset()` 只在 `release()` 里调用一次，prewarm 创建的实例完全跳过。

## Key design decisions（关键决定，已确认）

| # | 维度 | 结论 | 理由 |
|---|---|---|---|
| 1 | API 形态 | 仅全局 autoload `ObjectPool`（无 `class_name Pool`），内部用私有 `_PoolEntry` 分桶 | 与 `Log` 先例一致（`Log` 首版已否决可实例化 `Logger` 类）；无独立持池实例的具体场景，YAGNI；`_PoolEntry` 已封装成独立单元，将来要拆出公开类成本低 |
| 2 | `acquire()` 是否自动挂树 | 调用方自行 `add_child`，池不主动决定挂哪个父节点/图层 | 池不知道该挂在子弹层、特效层还是别处，把有语境的决定交回调用方；池保持“不主动写场景树”的最小职责边界 |
| 3 | `release()` 的 `remove_child` 时机 | `call_deferred`；`acquire()` 弹出节点时做一次同步兜底 `remove_child` | `release()` 常从节点自身碰撞回调里同步触发，物理体在自己碰撞回调里同步改树有 “flushing queries” 报错风险；`call_deferred` 复刻 `queue_free()` 那种“回调里调用安全”的心智模型 |
| 4 | 是否代管 `set_process`/`set_physics_process` 系列 | 完全不碰 | 节点被摘出场景树后引擎本就不会再调用它的 `_process`/`_physics_process`/`_input`，手动关闭是重复劳动；强行接管还可能覆盖节点脚本自己对 process 状态的管理意图 |
| 5 | 可见性 | 对称隐藏/显示，**默认开启**：`release()` 时若为 `CanvasItem`/`Node3D` 设 `visible=false`，`acquire()` 时设回 `visible=true`；`register()` 新增 **`manage_visibility: bool = true`** 参数，设为 `false` 可整池关闭 | 防止“忘记手动显示”这个高频坑；同时给需要自定义淡入淡出等过渡效果的池一个显式 opt-out，不与调用方自身显隐逻辑打架；成本只是一次类型判断+属性赋值，对非可视节点安全跳过 |
| 6 | 复用前重置约定 | 可选钩子 `_pool_reset()`，`has_method` 探测；仅在真实 `release()` 时调用一次，prewarm 不调用 | duck-typing 沿用 `_ready()`/`_process()` 式 Godot 惯例，学习成本低；`release()` 时机节点通常已完整经历过 `_ready()`，`@onready` 引用可安全访问（放在 prewarm/首次 acquire 前调用会摸到 null） |
| 7 | 归属判定 & 双重释放/非本池节点安全性 | `set_meta(META_POOL_KEY, key)` 打标签定位所属池；池内 `in_use`（以 `get_instance_id()` 为键）判定“当前确实处于借出状态” | 元数据跟着节点实例走，不需要额外维护“节点→key”反查表；`instance_id` 做键天然规避引用比较的坑，也是双重释放/误释放的唯一可靠判据 |
| 8 | 空/满时的扩容与上限 | `max_count=0`（默认）不限；`max_count>0` 是硬上限，达到后 `acquire()` 返回 `null` + `Log.warn`，不新建不崩溃。**不做“挤掉最旧实例”（steal-oldest）** | 多数池不需要上限，默认最省心；真正想“封顶”的场景（子弹雨）给显式 opt-in；返回 `null` 而非断言/崩溃/抢占，让 gameplay 代码自己决定这一帧要不要跳过生成，池不代替调用方杀死一个仍在使用中的对象 |
| 9 | 弹出空闲实例时发现已被外部 `free()` | `is_instance_valid()` 校验，无效则丢弃（`total_count -= 1`）继续找下一个 | 防御“绕过 `release()` 直接 `free()`”这种误用不至于让上层代码拿到野指针直接崩溃；这是 v1 明确愿意兜底的一类误用（反向场景——正被借出的实例被外部直接 `free()`——不做，见下方“被否决的选项”） |
| 10 | 重复 `register()` 同一 key | 同一 `PackedScene` 引用 → 幂等忽略；不同 → `Log.warn` 并保留原池 | 允许多个系统各自防御性地在自己的 `_ready()` 里调用同一份 `register()` 而不报噪音，同时仍能拦住“同一 key 被意外注册成不同场景”这种配置错误，不会无声吞掉正在使用中的池 |
| 11 | `clear(key)` 的语义范围 | **v1 纳入**最小版本：只 `queue_free()` 并清空当前空闲队列；`in_use` 不受影响（非空仅告警）；注册信息保留 | 没有任何回收手段会让长期运行、按关卡切换不同池化场景的游戏永久占内存；只清空闲队列既能回收内存又不会在调用方毫无防备时把“正被使用的节点”从脚下抽走；是否接入关卡卸载时机完全交给调用方，不引入对 `SceneManager` 的依赖 |
| 12 | `_pool_reset()` 钩子命名 | 维持 `_pool_reset()` | 已在 #6 确立为对外契约；未收到需要向已有项目习惯用法（如 `reset()`/`on_recycle()`）对齐的反馈，一旦定下改名成本高，现状即最终结论 |

### 被否决的选项（存档）

- **`acquire()` 时也调用 `_pool_reset()`**：与决定表 #6 冲突——首次 acquire 发生在节点还没
  `add_child` 过、`_ready()` 尚未跑过的时间点，`@onready` 引用会摸空。
- **`class_name Pool` 独立可实例化类**：与决定表 #1 一致，理由同 `Log` 先例，v1 无具体场景支撑，YAGNI。
- **`release()`/`acquire()` 主动接管 `set_process` 系列**：与决定表 #4 一致，脱离场景树已等价于
  停止 process 回调，多此一举且可能覆盖节点自身意图。
- **`acquire(key, parent: Node = null)` 附带可选父节点参数自动 `add_child`**：为保持 API 只有
  一种用法、行为可预期，v1 不加语法糖；调用方永远显式 `add_child`。如果后续反馈这确实是高频
  样板代码，可以再加。
- **对处于 `in_use` 状态、被外部直接 `free()` 的节点做自动检测/纠正**：Godot `Object` 没有通用
  可订阅的“已释放”信号，只能覆盖“仍在空闲队列里被 free()”这一种场景（决定表 #9 已覆盖借出前的
  情形），完整方案（比如轮询扫描全部 in_use 集合校验 `is_instance_valid`）成本远大于收益，v1 只
  在文档里写清楚这是误用，要求调用方总是走 `release()`。
- **`max_count` 耗尽时“挤掉最旧的一个 `in_use` 实例”（steal-oldest）**：与决定表 #8 一致。
  视觉上通常不违和（最老的特效/子弹先消失），但语义上更复杂——相当于池代替调用方杀死一个仍在
  使用中的对象，且需要维护“借出顺序”这一额外数据结构。v1 明确拒绝，`acquire()` 达到上限就返回
  `null`，交给调用方决定。
- **`clear(key)` 连 `in_use` 一起强制收回**：与决定表 #11 一致，会在调用方毫无防备时把“正被
  使用的节点”从脚下抽走，v1 只清空闲队列。

## Web-export considerations（Web 导出兼容性）

- 纯内存操作（`Dictionary`/`Array`/节点树操作），零文件 IO、零线程依赖：`register`/`acquire`/
  `release`/`clear` 全部同步方法，不用 `Thread`/`WorkerThreadPool`，天然满足 Web 导出“不能依赖
  真线程”的约束。
- 依赖的引擎 API（`PackedScene.instantiate()`、`add_child`/`remove_child`、`set_meta`/
  `get_meta`、`call_deferred`、`is_instance_valid`）在 Compatibility 渲染器与 HTML5/Web 导出下
  行为与桌面一致，无已知差异。
- Web 导出下 `PackedScene.instantiate()` 相对更贵（WASM 解释/编译开销、GC 压力更明显）；
  `prewarm` 把这部分开销挪到关卡加载/loading screen 阶段一次性支付，避免战斗高峰（如子弹雨）现
  造成掉帧——这是本子系统对 Web 目标最直接的价值，不只是“能跑”而已。
- `call_deferred` 在 Web 导出下的行为与桌面一致（仍是当前 `SceneTree` 帧尾统一 flush，不涉及
  真正的多线程调度），不会引入 Web 特有的时序问题。
- 无需任何 `OS.has_feature("web")` 之类的平台分支逻辑。

## Testable seams + test plan（可测接缝与测试计划）

### 可测接缝

`register`/`has_pool`/`acquire`/`release`/`clear`/`available_count`/`in_use_count`/
`total_count` 全部是不依赖场景树的纯 `Object` 层逻辑：它们只操作**传入的 `node` 参数**的父子
关系，从不对 `self`（`ObjectPool` 实例）调用 `add_child`，所以 `ObjectPool` 脚本本身是否已加入
真实场景树、autoload 是否就绪，跟这些方法的正确性无关——同 `test_log.gd` 的做法一样，可以直接
`preload("res://addons/godot-core-kit/object_pool.gd").new()` 拿到裸实例调用。测试可直接读
`_pools[key]` 内部字典做白盒断言（`_PoolEntry` 的设计初衷之一）。`Log` 已作为项目 autoload 注册
（Logger 子系统 0.2.0），headless 运行 `object_pool.gd` 内部对 `Log.warn`/`Log.error` 的调用
可正常解析，无需在测试里额外桩接。

**已知例外**：`release()` 里的 `remove_child` 是 `call_deferred`，在单次 `_initialize()` 内跑
完就 `quit()` 的 headless harness 中不会真正 flush（deferred 调用要等下一帧才执行，而这类
harness 通常不给自己下一帧的机会）。沿用本仓库 `Log` 子系统的既有先例（有真实引擎副作用、无法
在单帧 headless 断言的路径不做 headless 断言，只做源码审查+冒烟）——`ObjectPool` 同样把
“计数/元数据/钩子调用时机/可见性”这些同步、纯粹的部分放进 headless 断言，把“摘除父节点这个
deferred 副作用真的执行了”这一点留给 demo 场景冒烟（多跑几帧后断言 `get_parent() == null`）。

### `test/test_object_pool.gd`（headless 断言，规划的用例清单）

测试用**运行时现造的 trivial `PackedScene`**（`PackedScene.new()` + `pack(Node.new())`），不
需要额外的 `.tscn` 资源文件；验证 `_pool_reset()` 调用时机时额外用一个小 fixture 脚本
`test/fixtures/object_pool_probe.gd`（定义 `_pool_reset()`，每次调用把计数器 `reset_calls += 1`）
挂到某个 trivial 场景根节点上再 `pack()`。

1. `register()` 后 `has_pool(key)` 为真；`acquire(key)` 返回非 null 的有效节点。
2. `prewarm = N` 时，`register()` 之后不调用任何 `acquire()`：`available_count == N`、
   `in_use_count == 0`、`total_count == N`；且 probe 节点的 `reset_calls` 仍为 0（验证 prewarm
   不触发 `_pool_reset()`）。
3. 池非空时 `acquire()` 复用空闲队列而非新建：`total_count` 不变，`available_count -= 1`、
   `in_use_count += 1`。
4. 池为空且未设上限时 `acquire()` 新建：`total_count += 1`。
5. `release()` 后再次 `acquire()` 返回**同一个**节点实例（比较 `get_instance_id()`），证明确实
   复用而非巧合计数相等。
6. `release()` 对定义了 `_pool_reset()` 的节点恰好调用一次（probe 计数从 0 变 1）；对没有定义
   该方法的普通节点 release 不报错（duck-typing 安全）。
7. `release()` 对 `CanvasItem` 子类节点同步设 `visible = false`；`acquire()` 复用同一节点后同步
   设回 `visible = true`；对纯 `Node`（无 `visible` 属性）release 不报错。
8. 双重释放安全：对同一节点连续 `release()` 两次，第二次为 no-op——`available_count` 不因此
   多出一份、空闲队列里不出现重复条目。
9. 非本池节点安全：`release()` 一个从未经过任何 `register()`/`acquire()` 产出的裸 `Node.new()`
   ——no-op，不崩溃，不影响任何已注册池的计数。
10. 上限安全：`register(key, scene, 0, 1)`（`max_count=1`）后，第一次 `acquire()` 成功；在其
    仍处于 in_use、池已空的情况下第二次 `acquire()` 返回 `null`，`total_count` 不超过 1。
11. 僵尸空闲实例安全：把一个节点放进空闲队列后直接对它调用 `free()`（绕过 `release()`），随后
    `acquire()`——不崩溃，返回一个新的有效节点，且 `total_count` 正确扣减了那个被丢弃的僵尸条目。
12. 重复注册幂等性：用**同一个** `PackedScene` 引用 `register()` 两次——第二次不清空/不重建已有
    的 `available`/`in_use` 状态（用先 `acquire()` 一个再重复 `register()`，确认 `in_use_count`
    未被重置来验证）。
13. `clear(key)`：`prewarm=N` 且从未 `acquire()` 过时，`clear(key)` 之后 `available_count == 0`
    且 `total_count == 0`；`has_pool(key)` 仍为真；之后再 `acquire(key)` 仍能成功（重新
    instantiate）。
14. `manage_visibility = false` 时 `acquire()`/`release()` 均不碰可见性：`register(..., false)`
    后手动把节点 `visible` 摆成与池默认行为相反的状态，穿过一轮 `release()`→`acquire()`，确认
    `visible` 始终维持调用方设置的值，不被池强改（分别验证 `release()` 不强制设 `false`、
    `acquire()` 不强制设 `true`）。

沿用 `Log`/`EventBus`/`SceneManager` 的 harness 形态：`extends SceneTree`，`_initialize()` 里
跑上述断言、累计 `failures`，全部通过 `quit(0)` 打印 `test_object_pool: ALL PASS`，否则逐条打印
失败详情并 `quit(1)`。运行方式：`godot --headless -s res://test/test_object_pool.gd`。

### 冒烟

demo 场景加一小段：`register()` 一个真实的小场景、循环 `acquire()`→`add_child`→（下一帧）
`release()` 若干次，肉眼/退出码确认无报错、`get_parent() == null`（验证 deferred detach 确实
执行）、`visible` 按预期切换；这部分留给后续集成步骤，不在本设计范围内展开。

## 验证工具

本机 Godot 4.7：
`D:\Program Files\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe`

1. `--headless --import` 导入工程。
2. `--headless -s test/test_object_pool.gd`（或作为主场景/脚本运行）跑断言，检查退出码。
3. 冒烟：留给后续集成步骤接入 demo 场景后再跑。
