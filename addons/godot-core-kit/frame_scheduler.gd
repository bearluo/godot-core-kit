extends Node
## FrameScheduler(帧分频器)—— 降频 tick + 每帧限时预算任务队列。
##
## ① every_n(cb, n):回调每 n 帧执行一次,不同 handle 自动错峰
##    ((_frame + handle) % n == 0),上百实体的低频 AI 不会挤在同一帧。
## ② queue_task(cb):一次性任务 FIFO 入队,每帧在 budget_msec 预算内消化,
##    超预算让出本帧;每帧至少执行 1 个(防预算过小饿死)。
## 仅 _process(渲染帧)驱动;需要物理帧节奏的逻辑请写在消费方自己的
## _physics_process 里。零跨子系统依赖。

## 预算队列从非空消化到空时广播一次。
signal queue_drained

## 每帧消化预算(毫秒),可运行时调整。
var budget_msec: float = 2.0

## 测试接缝:预算计时经此取时(usec),测试注入假时钟即可确定性验证预算切分。
var _ticks_usec_func: Callable = Time.get_ticks_usec

var _frame: int = 0
var _repeating: Dictionary = {}  # handle(int) -> {"callable": Callable, "n": int}
var _queue: Array = []           # FIFO;元素为 Callable(不标注,失效项照常入列由消化时跳过)
var _next_handle: int = 1


## 注册降频回调(零参 Callable);n < 1 按 1 处理。返回句柄供 cancel();
## callable 失效(宿主被 free)后自动剪除,无需手动 cancel。
func every_n(callable: Callable, n: int) -> int:
	var handle := _next_handle
	_next_handle += 1
	_repeating[handle] = {"callable": callable, "n": maxi(1, n)}
	return handle


## 取消降频回调;句柄无效/已取消则空操作。
func cancel(handle: int) -> void:
	_repeating.erase(handle)


## 入队一次性任务(零参 Callable),按 FIFO 在预算内分帧执行。
func queue_task(callable: Callable) -> void:
	_queue.append(callable)


func pending_task_count() -> int:
	return _queue.size()


func _process(_delta: float) -> void:
	_frame += 1
	_tick_repeating()
	_drain_queue()


func _tick_repeating() -> void:
	# keys() 返回新数组,天然是本帧快照:回调内 every_n/cancel 只影响下一帧。
	for handle in _repeating.keys():
		var entry: Dictionary = _repeating.get(handle, {})
		if entry.is_empty():
			continue  # 本帧内被 cancel
		var cb: Callable = entry["callable"]
		if not cb.is_valid():
			_repeating.erase(handle)
			continue
		if (_frame + handle) % int(entry["n"]) == 0:
			cb.call()


func _drain_queue() -> void:
	if _queue.is_empty():
		return
	var start: int = _ticks_usec_func.call()
	var budget_usec := int(budget_msec * 1000.0)
	while not _queue.is_empty():
		var task: Callable = _queue.pop_front()
		if task.is_valid():
			task.call()
		# 预算检查放在执行之后:保证每帧至少执行 1 个,预算再小也不饿死。
		var elapsed: int = _ticks_usec_func.call() - start
		if elapsed >= budget_usec:
			break
	if _queue.is_empty():
		queue_drained.emit()
