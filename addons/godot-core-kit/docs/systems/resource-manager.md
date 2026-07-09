# ResourceManager —— 异步批量预热 + 缓存 + 手动释放

> `CoreKit.res` · `systems/resource_manager.gd`

## 职责

`preload_batch` 提供双通道、对外 API/信号完全一致的批量异步预热:线程通道(桌面)用 `ResourceLoader.load_threaded_request` + `_process` 轮询;分帧通道(Web/无线程)逐个同步 `load()` 塞进注入的 FrameScheduler 预算队列分帧消化。粒度是整资源:单个超大资源仍会在其加载帧超预算(预算队列"至少执行 1 个"保证不停摆)。`release` 的语义是"kit 不再钉住它"——Resource 引用计数由引擎管理,最后一个使用方释放后才真正回收;无引用计数、无优先级、无热重载(YAGNI)。

## 公开 API

```gdscript
signal batch_progress(loaded: int, total: int)  # 批次内每完成一个资源广播一次
signal batch_completed
    # 当前批次全部完成(含失败项)后广播一次;空批次/全缓存批次经 call_deferred 投递(晚一帧),
    # 使"先 preload_batch 再 connect"的调用顺序也能收到信号

var use_threads: bool = true  # 双通道开关;入树时自动探测(非 Web 且线程可用 → true),可覆写

func bind_ticker(ticker) -> void
    # 注入 FrameScheduler:分帧通道复用其预算队列逐帧消化加载任务

func preload_batch(paths: Array) -> void
    # 异步预热一批资源路径。已缓存/重复/在途路径去重跳过但计入 total 与 progress(加载条不缺格);
    # 批次进行中再次调用 → 合并进当前批次

func get_resource(path: String) -> Resource
    # 命中缓存直接返回;未命中同步加载并入缓存,失败返回 null。
    # 对在途路径:线程通道阻塞取回,分帧通道直接同步 load(引擎内部缓存使其接近免费)

func release(path: String) -> bool
    # 从缓存移除;存在返回 true,不存在返回 false

func clear() -> void       # 清空整个缓存
func is_cached(path: String) -> bool  # 是否已在缓存中
func cached_count() -> int             # 当前缓存资源数
```

## 依赖

被 `CoreKit` 门面经 `bind_ticker(ticker)` 注入 FrameScheduler,分帧通道(Web/无线程)靠它的预算队列逐帧消化加载任务;未注入且走分帧通道时降级为当帧同步全量加载(仍发进度/完成信号)。加载失败经 `CoreKit.log.error` 输出。

## 用法示例

```gdscript
CoreKit.res.batch_completed.connect(_on_level_assets_ready)
CoreKit.res.preload_batch([
    "res://levels/level1/level1.tscn",
    "res://levels/level1/bgm.ogg",
])

func _on_level_assets_ready() -> void:
    var scene: PackedScene = CoreKit.res.get_resource("res://levels/level1/level1.tscn")
```

## 注意事项

- **双通道自动探测,但 Web 恒走分帧通道**:`_ready` 按"非 Web 且支持线程"设置 `use_threads`;即便 Web 平台支持线程,v1 仍走分帧通道,避免跨浏览器 COOP/COEP 配置差异带来的行为分裂(保守选择)。
- **分帧粒度是整资源**:单个超大资源仍可能在其加载帧超预算,预算队列只保证"至少执行 1 个"不停摆;Web 上超大资源应拆分或在进场景前预先加载。
- **批次去重不漏进度**:`preload_batch` 对已缓存/在途路径去重跳过,但仍计入 `total`/`progress`,加载条不会缺格;批次进行中再次调用会合并进当前批次而非另开新批。
- **`batch_completed` 保证每批恰一次**:空批次/全缓存批次经 `call_deferred` 投递,让"先调用 `preload_batch` 再 connect"的顺序也能收到信号;若投递到点时已有新的真实批次在途,新鲜度守卫会跳过此次触发,留给该批真正完成时再发。
- **release 不是引用计数管理**:只是让 kit 不再持有引用,Resource 本身的引擎级引用计数、优先级、热重载均不在本系统职责内。
