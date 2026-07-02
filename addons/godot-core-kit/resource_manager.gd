extends Node
## ResourceManager —— 异步批量预热 + 缓存 + 手动释放。
##
## preload_batch 平台双通道、对外 API/信号完全一致:
## - 线程通道(桌面):ResourceLoader.load_threaded_request + _process 轮询;
## - 分帧通道(Web/无线程):逐个同步 load() 塞进注入的 FrameScheduler 预算
##   队列分帧消化。粒度是整资源:单个超大资源仍会在其加载帧超预算(预算
##   队列"至少执行 1 个"保证不停摆);Web 上超大资源请拆分或进场景前加载。
## 即使 Web 启用了线程支持,v1 仍走分帧通道(避免跨浏览器 COOP/COEP 配置
## 差异带来的行为分裂,保守选择)。
##
## release 的语义是"kit 不再钉住它":Resource 引用计数由引擎管理,最后一个
## 使用方释放后才真正回收。无引用计数、无优先级、无热重载(YAGNI)。

## 批次内每完成一个资源广播一次。
signal batch_progress(loaded: int, total: int)

## 当前批次全部完成(含失败项)后广播一次。
## 注意:空批次/全缓存批次经 call_deferred 投递(晚一帧),
## 使 "先 preload_batch 再 connect" 的调用顺序也能收到信号。
signal batch_completed

## 双通道开关;入树时自动探测(非 Web 且线程可用 → true),测试/消费方可覆写。
var use_threads: bool = true

## bind_ticker 注入;untyped:未注入且非线程通道时 preload_batch 降级为
## 当帧同步全量加载(仍发进度/完成信号)。
var _ticker = null
var _cache: Dictionary = {}      # path(String) -> Resource
var _in_flight: Dictionary = {}  # path(String) -> true(两通道共用的在途集)
var _batch_total: int = 0
var _batch_loaded: int = 0


func _ready() -> void:
	use_threads = not OS.has_feature("web") and OS.has_feature("threads")
	set_process(false)


func bind_ticker(ticker) -> void:
	_ticker = ticker


## 异步预热一批资源路径。已缓存/重复/在途路径去重跳过但计入 total 与
## progress(加载条不缺格);批次进行中再次调用 → 合并进当前批次。
func preload_batch(paths: Array) -> void:
	var to_load: Array = []
	var skipped := 0
	for p in paths:
		var path := String(p)
		if _cache.has(path) or _in_flight.has(path):
			skipped += 1
			continue
		_in_flight[path] = true
		to_load.append(path)
	_batch_total += paths.size()
	_batch_loaded += skipped
	if skipped > 0:
		batch_progress.emit(_batch_loaded, _batch_total)
	if to_load.is_empty():
		if _in_flight.is_empty():
			# 空批次/全缓存批次:deferred 投递,调用方 connect 晚于调用也收得到
			call_deferred("_finish_batch")
		return
	if use_threads:
		for path in to_load:
			ResourceLoader.load_threaded_request(path)
		set_process(true)
	else:
		for path in to_load:
			var captured: String = path
			if _ticker != null:
				_ticker.queue_task(func() -> void: _frame_load(captured))
			else:
				_frame_load(captured)  # 降级:未注入 ticker → 当帧同步


## 命中缓存直接返回;未命中同步加载并入缓存;失败返回 null。
## 对在途路径:线程通道阻塞取回,分帧通道直接同步 load(引擎内部缓存使其
## 接近免费);两通道都保证"要就立刻给",队列里的原任务完成时只推进度。
func get_resource(path: String) -> Resource:
	if _cache.has(path):
		return _cache[path]
	var res: Resource = null
	if use_threads and _in_flight.has(path):
		res = ResourceLoader.load_threaded_get(path)
	else:
		res = load(path)
	if res != null:
		_cache[path] = res
	else:
		CoreKit.log.error("ResourceManager: 加载失败 '%s'" % path)
	if _in_flight.has(path):
		_mark_done(path)
	return res


## 从缓存移除;存在返回 true,不存在返回 false。
func release(path: String) -> bool:
	return _cache.erase(path)


func clear() -> void:
	_cache.clear()


func is_cached(path: String) -> bool:
	return _cache.has(path)


func cached_count() -> int:
	return _cache.size()


## 线程通道轮询:逐个查在途项状态,完成/失败都推进批次。
func _process(_delta: float) -> void:
	for path in _in_flight.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_cache[path] = ResourceLoader.load_threaded_get(path)
		else:
			CoreKit.log.error("ResourceManager: 加载失败 '%s'(threaded status %d)" % [path, status])
		_mark_done(path)
	if _in_flight.is_empty():
		set_process(false)


## 分帧通道单项加载(经 FrameScheduler 预算队列逐帧执行)。
func _frame_load(path: String) -> void:
	if not _cache.has(path):
		var res := load(path)
		if res == null:
			CoreKit.log.error("ResourceManager: 加载失败 '%s'" % path)
		else:
			_cache[path] = res
	if _in_flight.has(path):
		_mark_done(path)


func _mark_done(path: String) -> void:
	_in_flight.erase(path)
	_batch_loaded += 1
	batch_progress.emit(_batch_loaded, _batch_total)
	if _in_flight.is_empty():
		_finish_batch()


func _finish_batch() -> void:
	_batch_total = 0
	_batch_loaded = 0
	batch_completed.emit()
