# godot-core-kit FrameScheduler 子系统设计

- 日期:2026-07-02
- 状态:已确认,待实现
- 版本目标:0.4.0
- 前置:`2026-07-02-corekit-facade-design.md`(总纲;门面属性 `CoreKit.ticker`)

---

## 目标与定位

`FrameScheduler`(帧分频器)把"不需要每帧做的事"从每帧里拿出来,两个互补能力:

1. **降频 tick**:回调按 every-N-frames 频率执行,且**自动错峰**——上百个敌人的 AI 决策各自落在不同帧,消灭同帧尖峰。
2. **预算队列**:一次性任务排队,每帧在时间预算内消化,超预算让出本帧——大批量工作(资源加载、程序化生成)分帧摊平。

定位边界:不做协程调度器、不做优先级队列、不做跨帧 await 语法糖;`_process`(渲染帧)驱动,不提供物理帧变体(需要物理帧节奏的逻辑应写在消费方自己的 `_physics_process` 里)。

## Public API(GDScript 精确签名)

```gdscript
extends Node
## FrameScheduler —— 降频 tick + 每帧限时预算任务队列。

## 预算队列从非空消化到空时广播一次。
signal queue_drained

## 每帧消化预算(毫秒),可运行时调整。
var budget_msec: float = 2.0

## 注册降频回调:callable 每 n 帧被调用一次(n < 1 按 1 处理),不同 handle 自动错峰。
## 返回句柄供 cancel();callable 失效(宿主被 free)后自动剪除。
func every_n(callable: Callable, n: int) -> int

## 取消降频回调;句柄无效/已取消则空操作。
func cancel(handle: int) -> void

## 入队一次性任务,按 FIFO 在预算内分帧执行;失效 callable 出队时静默跳过。
func queue_task(callable: Callable) -> void

## 预算队列当前待执行任务数。
func pending_task_count() -> int
```

## Behavior & data flow

- 内部:`var _frame: int = 0`(自身 `_process` 计数);`_repeating: Dictionary`(handle → {callable, n});`_queue: Array[Callable]`;`_next_handle: int = 1`。
- **降频 tick**:每帧对每条注册项判 `(_frame + handle) % n == 0` → 命中则调用。`handle % n` 即错峰偏移:同为 n=10 的一批注册项被均匀撒在 10 个相位上。回调调用前判 `is_valid()`,失效即从注册表剪除(与 EventBus 同策略,不需要宿主手动 cancel)。tick 遍历基于当帧快照(`keys()` 拷贝),回调内 `every_n`/`cancel` 只影响下一帧。
- **预算队列**:降频 tick 之后,`while` 从队头依次取任务执行,每执行完一个检查已耗时;耗时 ≥ `budget_msec` 或队列空即停(至少执行 1 个,防预算过小饿死)。本帧从非空消化到空 → `emit queue_drained`。
- **时钟接缝**:`var _ticks_usec_func: Callable = Time.get_ticks_usec` —— 预算判断经它取时,测试注入假时钟即可确定性验证预算切分,不依赖真实耗时。

## Key decisions

| # | 维度 | 结论 | 理由 |
|---|---|---|---|
| 1 | 驱动源 | 仅 `_process`(渲染帧) | 降频 AI/预算加载天然是"视觉节奏"工作;物理帧变体 YAGNI |
| 2 | 错峰算法 | `(_frame + handle) % n == 0` | 零配置、零额外状态;handle 单调递增天然均匀 |
| 3 | 失效回调 | 调用前 `is_valid()` 惰性剪除 | 与 EventBus 同一心智模型;宿主 free 即自动消失 |
| 4 | 预算语义 | 每帧至少执行 1 个任务 | 防 budget_msec 被设得过小导致队列永久饿死 |
| 5 | 任务返回值/完成回调 | 不做,任务自带后续(闭包里自己发信号) | 单 `queue_drained` 已覆盖"批量做完"场景;per-task promise 是 YAGNI |
| 6 | 时钟 | `_ticks_usec_func` 可注入 | 预算逻辑可确定性单测,不写 sleep 型脆弱测试 |

## Web-export considerations

零线程、零定时器、零文件 IO;完全跟随主循环 `_process`。浏览器标签页隐藏时 `_process` 降频/暂停 → 降频 tick 与预算队列同步变慢,语义仍正确(帧驱动本来就不承诺墙钟时间)。

## Testable seams + test plan

核心接缝:**手动调用 `_process(0.016)` 即模拟一帧**(headless `-s` 下主循环不跑,测试自己驱动帧);`_ticks_usec_func` 注入假时钟控制预算判定。

`test/test_frame_scheduler.gd`(headless,直接实例化):

1. `every_n(cb, 1)`:驱动 3 帧被调 3 次。
2. `every_n(cb, 3)`:驱动 9 帧恰被调 3 次,且间隔恒为 3 帧。
3. 错峰:两个 n=4 的注册项,驱动 8 帧,断言二者命中的帧号集合不相交。
4. `cancel(handle)` 后不再被调;无效句柄 cancel 空操作。
5. 失效剪除:宿主 Node 注册后 `free()`,驱动一帧不报错,注册表条目消失。
6. tick 回调内再 `every_n` 注册:本帧不生效,后续帧生效(快照语义)。
7. 预算队列 FIFO:入队 A/B/C,假时钟设"每任务耗时 1ms、预算 2.5ms",第 1 帧执行 A、B,第 2 帧执行 C;`pending_task_count` 逐帧递减正确。
8. 至少执行 1 个:假时钟设"单任务耗时 > 预算",每帧仍恰执行 1 个。
9. `queue_drained` 恰在队列清空那一帧广播一次;空队列驱动帧不广播。
10. 失效任务出队跳过:入队宿主已 free 的 callable,驱动一帧静默跳过、不崩、正常继续后续任务。

## 版本

FrameScheduler v0.4.0 起:`every_n` 降频错峰 tick、`cancel`、`queue_task` 预算队列、`budget_msec`、`queue_drained`、失效自动剪除。依赖:log(仅运行期诊断);被 res 经 `bind_ticker()` 依赖。
