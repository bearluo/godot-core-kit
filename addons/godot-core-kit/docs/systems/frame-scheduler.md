# FrameScheduler —— 降频 tick + 分帧任务队列

> `CoreKit.ticker` · `systems/frame_scheduler.gd`

## 职责

降低高频逻辑对帧率的压力,提供两种手段:① `every_n` 把回调降频到每 n 帧执行一次,不同 handle 自动错峰,上百实体的低频 AI 不会挤在同一帧;② `queue_task` 把一次性任务 FIFO 入队,每帧在 `budget_msec` 预算内消化,超预算的部分让出本帧,分摊到后续帧,避免批量任务(如批量生成)卡顿单帧。仅 `_process`(渲染帧)驱动,零跨子系统依赖。

## 公开 API

```gdscript
signal queue_drained   # 预算队列从非空消化到空时广播一次

func every_n(callable: Callable, n: int) -> int   # 注册降频回调(零参),不同 handle 自动错峰;返回句柄供 cancel()
func cancel(handle: int) -> void                  # 取消降频回调;句柄无效/已取消则空操作
func queue_task(callable: Callable) -> void        # 入队一次性任务(零参 Callable),FIFO,按预算分帧执行
func pending_task_count() -> int                   # 查询队列剩余任务数

var budget_msec: float = 2.0                       # 每帧消化预算(毫秒),可运行时调整
var _ticks_usec_func: Callable = Time.get_ticks_usec  # 测试接缝:预算计时经此取时(usec),测试可注入假时钟做确定性验证
```

## 依赖

`FrameScheduler` 自身零跨子系统依赖(纯 `Node`,仅用 `Time.get_ticks_usec` 取时)。方向相反的是:`ResourceManager` 经门面 `res.bind_ticker(ticker)` 注入 `FrameScheduler` 引用,复用它的分帧通道处理资源异步预加载。

## 用法示例

```gdscript
# 错峰降频 tick:上百怪物的 AI 每 10 帧跑一次
var handle := CoreKit.ticker.every_n(_on_slow_tick, 10)

func _on_slow_tick() -> void:
    update_ai()

# 用完记得取消,或让回调所在对象被 free 后自动剪除
CoreKit.ticker.cancel(handle)

# 一次性任务分帧消化(如批量生成敌人)
for enemy_data in spawn_list:
    CoreKit.ticker.queue_task(func(): spawn_enemy(enemy_data))
CoreKit.ticker.queue_drained.connect(func(): print("批量生成完成"))
```

## 注意事项

- 仅 `_process`(渲染帧)驱动;需要物理帧节奏的逻辑请写在消费方自己的 `_physics_process` 里,`ticker` 不提供物理帧变体。
- 错峰规则是 `(_frame + handle) % n == 0`,不同 handle 天然错开,大量低频回调不会集中在同一帧。
- 预算队列**每帧至少执行 1 个任务**,预算检查放在执行之后:即使 `budget_msec` 设得很小,也不会把队列饿死。
- `every_n` 注册的回调失效(宿主 `free()`)后会在下次 tick 自动剪除,无需手动 `cancel()`;一次性队列里失效的 `Callable` 在消化时直接跳过。
- `budget_msec` 可运行时热改,立即影响下一帧的消化量。
