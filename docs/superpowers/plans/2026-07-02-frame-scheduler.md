# FrameScheduler 子系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现帧分频器 FrameScheduler(every_n 降频错峰 tick + 每帧限时预算任务队列)。

**Architecture:** 见 spec `docs/superpowers/specs/2026-07-02-frame-scheduler-design.md`。单文件 Node,`_process` 驱动;门面接线(`CoreKit.ticker`)留给集成任务。

**Tech Stack:** Godot 4.7 / 纯 GDScript / headless `-s` 断言测试(手动驱动 `_process` 模拟帧、注入假时钟)

## Global Constraints

- 分支:全部工作在 `feat/framework-v0.4` 上(从 main 切出);线性历史,不得产生 merge commit。
- 纯 GDScript、Tab 缩进;无 C#、无 GDExtension、无第三方依赖;命令行 `godot` 已在 PATH。
- Web 导出兼容:禁用线程/平台专属 API。
- 依赖纪律:本子系统零跨子系统调用(诊断场景当前不存在);初始化期诊断用 `push_warning`/`push_error`。
- 测试纪律(`-s` 避坑手册):可能接住已 free 实例的变量/形参不标注类型;untyped 值的下游变量显式标注类型(不用 `:=`);测试无论成败必须到达 `quit()`。
- 运行测试用硬超时模板(PowerShell,单测 60s 上限):

```powershell
$p = Start-Process godot -ArgumentList '--headless','--path','.','-s','res://test/test_frame_scheduler.gd' -RedirectStandardOutput "$env:TEMP\gck-out.txt" -RedirectStandardError "$env:TEMP\gck-err.txt" -PassThru -NoNewWindow; if (-not $p.WaitForExit(60000)) { $p.Kill(); 'TIMEOUT(疑似测试报错未达 quit)' }; Get-Content "$env:TEMP\gck-out.txt"
```

- git 提交消息不得含英文双引号(PowerShell here-string 坑)。

---

### Task 1: FrameScheduler 核心

**Files:**
- Create: `addons/godot-core-kit/frame_scheduler.gd`
- Test: `test/test_frame_scheduler.gd`

**Interfaces:**
- Consumes: 无(零依赖)。
- Produces: `signal queue_drained`;`var budget_msec: float = 2.0`;`every_n(callable: Callable, n: int) -> int`(handle);`cancel(handle: int) -> void`;`queue_task(callable: Callable) -> void`;`pending_task_count() -> int`;接缝 `var _ticks_usec_func: Callable`(默认 `Time.get_ticks_usec`,测试注入假时钟)。ResourceManager 任务将经 `bind_ticker()` 拿到本实例并调用 `queue_task`。

- [ ] **Step 1: 写失败测试 test/test_frame_scheduler.gd**

```gdscript
extends SceneTree
## FrameScheduler headless 断言测试(直接实例化;frame_scheduler.gd 零依赖,
## 但沿用运行时 load() 惯例)。手动调用 fs._process(0.016) 即模拟一帧;
## 预算判定经 _ticks_usec_func 注入假时钟,确定性验证,不写 sleep 型脆弱测试。
## 运行:godot --headless --path . -s res://test/test_frame_scheduler.gd


func _drive(fs, frames: int) -> void:
	for i in frames:
		fs._process(0.016)


func _initialize() -> void:
	var failures := 0
	var fs = load("res://addons/godot-core-kit/frame_scheduler.gd").new()

	# 1. every_n(cb, 1):每帧都调
	var count1 := {"n": 0}
	var h1: int = fs.every_n(func() -> void: count1["n"] += 1, 1)
	_drive(fs, 3)
	if count1["n"] != 3:
		print("FAIL 1: n=1 驱动 3 帧应调 3 次,实际 %d" % count1["n"])
		failures += 1
	fs.cancel(h1)

	# 2. every_n(cb, 3):9 帧恰调 3 次
	var count2 := {"n": 0}
	var h2: int = fs.every_n(func() -> void: count2["n"] += 1, 3)
	_drive(fs, 9)
	if count2["n"] != 3:
		print("FAIL 2: n=3 驱动 9 帧应调 3 次,实际 %d" % count2["n"])
		failures += 1
	fs.cancel(h2)

	# 3. 错峰:两个 n=4 的注册项命中的帧号集合不相交
	var hits_a := []
	var hits_b := []
	var frame_box := {"f": 0}
	var ha: int = fs.every_n(func() -> void: hits_a.append(frame_box["f"]), 4)
	var hb: int = fs.every_n(func() -> void: hits_b.append(frame_box["f"]), 4)
	for i in 8:
		frame_box["f"] = i
		fs._process(0.016)
	for hit in hits_a:
		if hits_b.has(hit):
			print("FAIL 3: 错峰失败,帧 %d 同时命中两个注册项" % hit)
			failures += 1
	if hits_a.is_empty() or hits_b.is_empty():
		print("FAIL 3: 8 帧内两个 n=4 注册项都应至少命中一次")
		failures += 1
	fs.cancel(ha)
	fs.cancel(hb)

	# 4. cancel 后不再调;无效句柄 cancel 空操作
	var count4 := {"n": 0}
	var h4: int = fs.every_n(func() -> void: count4["n"] += 1, 1)
	_drive(fs, 1)
	fs.cancel(h4)
	fs.cancel(99999)  # 空操作,不崩
	_drive(fs, 2)
	if count4["n"] != 1:
		print("FAIL 4: cancel 后不应再调,实际 %d" % count4["n"])
		failures += 1

	# 5. 失效剪除:宿主 free 后驱动一帧,不崩且注册表条目消失
	var host = Node.new()
	fs.every_n(Callable(host, "get_name"), 1)
	host.free()
	_drive(fs, 1)  # 不崩即通过前半
	if not fs._repeating.is_empty():
		print("FAIL 5: 失效回调应被剪除,注册表剩 %d 条" % fs._repeating.size())
		failures += 1

	# 6. tick 回调内再注册:本帧不生效,后续帧生效(快照语义)
	# (多行 lambda 先赋给局部变量再传参:lambda 体后面跟 ", 1)" 的写法解析器易翻车)
	var late := {"n": 0}
	var outer := {"h": 0}
	var register_inner := func() -> void:
		if outer.get("inner", 0) == 0:
			outer["inner"] = fs.every_n(func() -> void: late["n"] += 1, 1)
	outer["h"] = fs.every_n(register_inner, 1)
	_drive(fs, 1)
	if late["n"] != 0:
		print("FAIL 6: 回调内注册的项本帧不应执行")
		failures += 1
	_drive(fs, 1)
	if late["n"] != 1:
		print("FAIL 6: 回调内注册的项下一帧应执行,实际 %d" % late["n"])
		failures += 1
	fs.cancel(outer["h"])
	fs.cancel(outer["inner"])

	# 7/8/9. 预算队列:假时钟每次取时前进 1000us(=1ms);budget 2.0ms 时
	#        每帧恰消化 2 个(执行 1 个后检查:1ms < 2ms 继续,2 个后 2ms >= 2ms 停)
	var clock := {"now": 0}
	fs._ticks_usec_func = func() -> int:
		clock["now"] += 1000
		return clock["now"]
	fs.budget_msec = 2.0
	var order := []
	var drained := {"n": 0}
	fs.queue_drained.connect(func() -> void: drained["n"] += 1)
	for tag in ["A", "B", "C"]:
		var captured: String = tag
		fs.queue_task(func() -> void: order.append(captured))
	if fs.pending_task_count() != 3:
		print("FAIL 7: 入队后 pending 应为 3")
		failures += 1
	_drive(fs, 1)
	if order != ["A", "B"] or fs.pending_task_count() != 1:
		print("FAIL 7: 第 1 帧应恰消化 A、B,实际 %s(剩 %d)" % [order, fs.pending_task_count()])
		failures += 1
	if drained["n"] != 0:
		print("FAIL 9: 队列未空不应广播 queue_drained")
		failures += 1
	_drive(fs, 1)
	if order != ["A", "B", "C"] or fs.pending_task_count() != 0:
		print("FAIL 7: 第 2 帧应消化 C,实际 %s" % [order])
		failures += 1
	if drained["n"] != 1:
		print("FAIL 9: 清空那一帧应恰广播一次 queue_drained,实际 %d" % drained["n"])
		failures += 1
	_drive(fs, 1)
	if drained["n"] != 1:
		print("FAIL 9: 空队列驱动帧不应再广播")
		failures += 1

	# 8. 至少执行 1 个:单任务耗时(3ms)超预算(2ms),每帧仍恰执行 1 个
	var order8 := []
	for tag in ["X", "Y"]:
		var captured8: String = tag
		var slow_task := func() -> void:
			order8.append(captured8)
			clock["now"] += 3000
		fs.queue_task(slow_task)
	_drive(fs, 1)
	if order8 != ["X"]:
		print("FAIL 8: 超预算任务每帧应恰执行 1 个,实际 %s" % [order8])
		failures += 1
	_drive(fs, 1)
	if order8 != ["X", "Y"]:
		print("FAIL 8: 第 2 帧应执行 Y,实际 %s" % [order8])
		failures += 1

	# 10. 失效任务出队静默跳过,不影响后续任务与 drained
	var host2 = Node.new()
	fs.queue_task(Callable(host2, "get_name"))
	host2.free()
	var after := {"ran": false}
	fs.queue_task(func() -> void: after["ran"] = true)
	var drained_before: int = drained["n"]
	_drive(fs, 1)
	if not after["ran"]:
		print("FAIL 10: 失效任务后的正常任务应照常执行")
		failures += 1
	if drained["n"] != drained_before + 1:
		print("FAIL 10: 含失效任务的批清空后应广播 drained")
		failures += 1

	fs.free()

	if failures == 0:
		print("test_frame_scheduler: ALL PASS")
		quit(0)
	else:
		print("test_frame_scheduler: %d FAILURE(S)" % failures)
		quit(1)
```

- [ ] **Step 2: 跑测试确认失败**

用 Global Constraints 的硬超时模板运行。Expected: 报错退出,退出码非 0。

- [ ] **Step 3: 实现 addons/godot-core-kit/frame_scheduler.gd**

```gdscript
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
```

- [ ] **Step 4: 跑测试确认全绿**

同 Step 2 命令。Expected: `test_frame_scheduler: ALL PASS`,退出码 0。

- [ ] **Step 5: 提交**

```powershell
git add addons/godot-core-kit/frame_scheduler.gd test/test_frame_scheduler.gd
git commit -m 'feat: add FrameScheduler core (every_n staggered tick, budgeted task queue)'
```
