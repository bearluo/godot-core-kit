extends SceneTree
## ResourceManager headless 断言测试(直接实例化,不入树 → _ready 的
## use_threads 自动探测不跑,由测试显式指定通道)。
## 分帧通道:注入真 FrameScheduler,其假时钟每次取时前进 2001us(预算 2ms)
## → 每帧恰消化 1 个任务,手动驱动 ticker._process 逐帧推进,完全确定性。
## 线程通道:真实 load_threaded,轮询 rm._process + OS.delay_msec,上限次数防挂死。
## 测试资源用仓库内 .gd 文件(GDScript 即 Resource)。
## 运行:godot --headless --path . -s res://test/test_resource_manager.gd
##
## 加载注:resource_manager.gd 运行期引用全局 autoload 标识符 CoreKit,故不在
## 类作用域 preload,延迟到 _initialize() 内 load()。
## 空批次的 batch_completed 是 call_deferred 语义,单次 _initialize 内不会
## flush(与 ObjectPool 的 remove_child 同款已知例外)——只断言簿记与
## "不同步广播",投递本身由集成任务的 demo 冒烟验证。

var ResourceManagerScript
var SchedulerScript

const PATH_A := "res://addons/godot-core-kit/log.gd"
const PATH_B := "res://addons/godot-core-kit/event_bus.gd"
const PATH_C := "res://addons/godot-core-kit/save_manager.gd"
const PATH_BAD := "res://__no_such_resource__.tres"


func _make_frame_channel() -> Array:
	var rm = ResourceManagerScript.new()
	rm.use_threads = false
	var ticker = SchedulerScript.new()
	var clock := {"now": 0}
	ticker._ticks_usec_func = func() -> int:
		clock["now"] += 2001
		return clock["now"]
	rm.bind_ticker(ticker)
	return [rm, ticker]


func _initialize() -> void:
	ResourceManagerScript = load("res://addons/godot-core-kit/resource_manager.gd")
	SchedulerScript = load("res://addons/godot-core-kit/frame_scheduler.gd")
	var failures := 0

	# 1. get_resource:未命中同步加载入缓存;二次调用同一实例;is_cached/cached_count
	var rm0 = ResourceManagerScript.new()
	rm0.use_threads = false
	var res_a = rm0.get_resource(PATH_A)
	if res_a == null:
		print("FAIL 1: get_resource 应加载成功")
		failures += 1
	if not rm0.is_cached(PATH_A) or rm0.cached_count() != 1:
		print("FAIL 1: 加载后应入缓存")
		failures += 1
	if rm0.get_resource(PATH_A) != res_a:
		print("FAIL 1: 二次 get_resource 应返回同一实例")
		failures += 1

	# 2. 坏路径:null 不崩
	if rm0.get_resource(PATH_BAD) != null:
		print("FAIL 2: 坏路径应返回 null")
		failures += 1
	if rm0.is_cached(PATH_BAD):
		print("FAIL 2: 坏路径不应入缓存")
		failures += 1

	# 3. release / clear
	if not rm0.release(PATH_A):
		print("FAIL 3: release 已缓存路径应返回 true")
		failures += 1
	if rm0.release(PATH_A):
		print("FAIL 3: release 不存在的路径应返回 false")
		failures += 1
	rm0.get_resource(PATH_A)
	rm0.get_resource(PATH_B)
	rm0.clear()
	if rm0.cached_count() != 0:
		print("FAIL 3: clear 后缓存应为空")
		failures += 1
	rm0.free()

	# 4. 分帧通道:3 路径逐帧加载,progress 序列与 completed 恰一次
	var built: Array = _make_frame_channel()
	var rm = built[0]
	var ticker = built[1]
	var progress := []
	var completed := {"n": 0}
	rm.batch_progress.connect(func(loaded: int, total: int) -> void:
		progress.append([loaded, total]))
	rm.batch_completed.connect(func() -> void: completed["n"] += 1)
	rm.preload_batch([PATH_A, PATH_B, PATH_C])
	if ticker.pending_task_count() != 3:
		print("FAIL 4: 分帧通道应入队 3 个任务")
		failures += 1
	ticker._process(0.016)  # 每帧恰 1 个(假时钟 2001us/次 >= 2ms 预算)
	if progress != [[1, 3]] or completed["n"] != 0:
		print("FAIL 4: 第 1 帧后应 (1,3) 且未完成,实际 %s / %d" % [progress, completed["n"]])
		failures += 1
	ticker._process(0.016)
	ticker._process(0.016)
	if progress != [[1, 3], [2, 3], [3, 3]]:
		print("FAIL 4: progress 序列不正确,实际 %s" % [progress])
		failures += 1
	if completed["n"] != 1:
		print("FAIL 4: batch_completed 应恰广播一次,实际 %d" % completed["n"])
		failures += 1
	if not (rm.is_cached(PATH_A) and rm.is_cached(PATH_B) and rm.is_cached(PATH_C)):
		print("FAIL 4: 批次完成后应全部入缓存")
		failures += 1

	# 5. 去重:已缓存 + 批内重复,计入 total 与 progress,不重复加载
	progress.clear()
	completed["n"] = 0
	rm.release(PATH_B)
	rm.preload_batch([PATH_A, PATH_A, PATH_B])  # A 已缓存 ×2(缓存+重复),B 待载
	if progress != [[2, 3]]:
		print("FAIL 5: 跳过项应立即计入 progress,实际 %s" % [progress])
		failures += 1
	ticker._process(0.016)
	if progress != [[2, 3], [3, 3]] or completed["n"] != 1:
		print("FAIL 5: B 加载后应完成,实际 %s / %d" % [progress, completed["n"]])
		failures += 1

	# 6. 坏路径混入批次:progress 推进到 total、completed 正常、坏路径不入缓存
	progress.clear()
	completed["n"] = 0
	rm.release(PATH_B)
	rm.preload_batch([PATH_BAD, PATH_B])
	ticker._process(0.016)
	ticker._process(0.016)
	if completed["n"] != 1 or progress != [[1, 2], [2, 2]]:
		print("FAIL 6: 含坏路径批次应照常完成,实际 %s / %d" % [progress, completed["n"]])
		failures += 1
	if rm.is_cached(PATH_BAD):
		print("FAIL 6: 坏路径不应入缓存")
		failures += 1

	# 7. 空批次:簿记归零,不同步广播(deferred 投递由 demo 冒烟验证)
	progress.clear()
	completed["n"] = 0
	rm.preload_batch([])
	if completed["n"] != 0:
		print("FAIL 7: 空批次不应同步广播 completed(应 deferred)")
		failures += 1
	if rm._batch_total != 0 or rm._batch_loaded != 0:
		print("FAIL 7: 空批次簿记应保持归零")
		failures += 1

	# 8. 追加批次:进行中再 preload_batch,total 增长,completed 只在全完后一次
	progress.clear()
	completed["n"] = 0
	rm.release(PATH_B)
	rm.release(PATH_C)
	rm.preload_batch([PATH_B])
	rm.preload_batch([PATH_C])  # 追加
	ticker._process(0.016)
	if completed["n"] != 0:
		print("FAIL 8: 追加批次未全完不应广播 completed")
		failures += 1
	ticker._process(0.016)
	if completed["n"] != 1 or progress != [[1, 2], [2, 2]]:
		print("FAIL 8: 追加批次应合并簿记,实际 %s / %d" % [progress, completed["n"]])
		failures += 1

	# 9. get_resource 对分帧队列中的路径:立刻同步给,任务完成时只推进度
	progress.clear()
	completed["n"] = 0
	rm.release(PATH_B)
	rm.preload_batch([PATH_B])
	var eager = rm.get_resource(PATH_B)  # 在途:立刻同步加载给调用方
	if eager == null or not rm.is_cached(PATH_B):
		print("FAIL 9: 在途路径 get_resource 应立刻返回并入缓存")
		failures += 1
	ticker._process(0.016)  # 队列任务发现已缓存 → 只推进度
	if completed["n"] != 1 or progress != [[1, 1]]:
		print("FAIL 9: 队列消化后应正常完成,实际 %s / %d" % [progress, completed["n"]])
		failures += 1
	rm.free()
	ticker.free()

	# 10. 线程通道冒烟:真实 load_threaded,轮询至完成(上限防挂死)
	var rm_t = ResourceManagerScript.new()
	rm_t.use_threads = true
	var done_t := {"n": 0}
	rm_t.batch_completed.connect(func() -> void: done_t["n"] += 1)
	rm_t.preload_batch([PATH_A, PATH_B])
	var rounds := 0
	while done_t["n"] == 0 and rounds < 500:
		OS.delay_msec(10)
		rm_t._process(0.016)
		rounds += 1
	if done_t["n"] != 1:
		print("FAIL 10: 线程通道 500 轮内未完成")
		failures += 1
	if not (rm_t.is_cached(PATH_A) and rm_t.is_cached(PATH_B)):
		print("FAIL 10: 线程通道加载结果应入缓存")
		failures += 1
	rm_t.free()

	if failures == 0:
		print("test_resource_manager: ALL PASS")
		quit(0)
	else:
		print("test_resource_manager: %d FAILURE(S)" % failures)
		quit(1)
