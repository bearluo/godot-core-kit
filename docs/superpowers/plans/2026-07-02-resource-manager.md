# ResourceManager 子系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现资源子系统 ResourceManager(异步批量预热双通道 + 缓存 + 手动释放,进度/完成信号)。

**Architecture:** 见 spec `docs/superpowers/specs/2026-07-02-resource-manager-design.md`。单文件 Node;依赖 FrameScheduler(波 1,经 `bind_ticker()` 注入,Web/无线程通道用);门面接线留给集成任务。

**Tech Stack:** Godot 4.7 / 纯 GDScript / headless `-s` 断言测试(分帧通道注入真 FrameScheduler 手动驱动;线程通道轮询 + 上限次数防挂死;测试资源用仓库内 `.gd` 文件——GDScript 本身就是 Resource)

## Global Constraints

- 分支:全部工作在 `feat/framework-v0.4` 上(从 main 切出);线性历史,不得产生 merge commit。
- 纯 GDScript、Tab 缩进;无 C#、无 GDExtension、无第三方依赖;命令行 `godot` 已在 PATH。
- Web 导出兼容:平台双通道是本子系统 spec 明确授权的唯一分叉;通道探测 `not OS.has_feature("web") and OS.can_use_threads()`,`use_threads` 为 var 可覆写(测试接缝 + 消费方逃生门)。
- 依赖纪律:仅 `CoreKit.log.error`(运行期)与注入的 ticker(未注入且非线程通道时降级当帧同步);初始化期诊断用 `push_warning`。
- 测试纪律(`-s` 避坑手册):`-s` 主脚本不得在类作用域 preload 任何引用 `CoreKit` 全局的脚本(`_initialize()` 内运行时 `load()`);untyped 值的下游变量显式标注类型(不用 `:=`);测试无论成败必须到达 `quit()`。
- 运行测试用硬超时模板(PowerShell,单测 120s 上限——线程通道冒烟含真实 IO):

```powershell
$p = Start-Process godot -ArgumentList '--headless','--path','.','-s','res://test/test_resource_manager.gd' -RedirectStandardOutput "$env:TEMP\gck-out.txt" -RedirectStandardError "$env:TEMP\gck-err.txt" -PassThru -NoNewWindow; if (-not $p.WaitForExit(120000)) { $p.Kill(); 'TIMEOUT(疑似测试报错未达 quit)' }; Get-Content "$env:TEMP\gck-out.txt"
```

- git 提交消息不得含英文双引号(PowerShell here-string 坑)。

---

### Task 1: ResourceManager 核心

**Files:**
- Create: `addons/godot-core-kit/resource_manager.gd`
- Test: `test/test_resource_manager.gd`

**Interfaces:**
- Consumes: FrameScheduler 实例(波 1):`queue_task(callable: Callable) -> void`、`var _ticks_usec_func`(测试里控制每帧消化 1 个任务)、手动 `_process(delta)` 驱动;`CoreKit.log.error(msg: String)`。
- Produces: `signal batch_progress(loaded: int, total: int)`、`signal batch_completed`;`var use_threads: bool`;`bind_ticker(ticker) -> void`;`preload_batch(paths: Array) -> void`;`get_resource(path: String) -> Resource`;`release(path: String) -> bool`;`clear() -> void`;`is_cached(path: String) -> bool`;`cached_count() -> int`;内部 `var _cache: Dictionary`、`var _in_flight: Dictionary`、`var _batch_total/_batch_loaded: int`。集成任务将调用 `CoreKit.res.bind_ticker(CoreKit.ticker)`。

- [ ] **Step 1: 写失败测试 test/test_resource_manager.gd**

```gdscript
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
```

- [ ] **Step 2: 跑测试确认失败**

用 Global Constraints 的硬超时模板运行。Expected: 报错退出,退出码非 0。

- [ ] **Step 3: 实现 addons/godot-core-kit/resource_manager.gd**

```gdscript
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
	use_threads = not OS.has_feature("web") and OS.can_use_threads()
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
```

- [ ] **Step 4: 跑测试确认全绿**

同 Step 2 命令(120s 上限)。Expected: `test_resource_manager: ALL PASS`,退出码 0。
若测试 4 的分帧断言失败,先确认 FrameScheduler(波 1)已合入当前分支。

- [ ] **Step 5: 提交**

```powershell
git add addons/godot-core-kit/resource_manager.gd test/test_resource_manager.gd
git commit -m 'feat: add ResourceManager core (dual-channel async preload, cache, manual release)'
```
