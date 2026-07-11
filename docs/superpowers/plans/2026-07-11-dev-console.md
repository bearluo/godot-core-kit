# DevConsole(运行时调试控制台)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 godot-core-kit 加第 11 个子系统 `CoreKit.console` —— 运行时调试控制台(日志 overlay + 命令/作弊注册 + GDScript 表达式执行 + 变量 watch),debug 门控、纯 GDScript、可 Web 导出。

**Architecture:** 逻辑拆三个纯逻辑 RefCounted 单元(`console_command_registry` / `console_evaluator` / `console_watch_list`)各自 headless 单测;`dev_console.gd`(extends CanvasLayer)代码建 UI + 编排 + 公共 API,`execute(text)->String` 作程序化提交命门;`core/log.gd` 增补 `line_logged` 信号 + 有界环形缓冲喂 overlay(向后兼容);`core_kit.gd` 构造第 11 子系统 + `bind_core` 接线 + 版本升 0.9.0。

**Tech Stack:** Godot 4.7 GDScript,`Expression` 类做表达式求值,`extends SceneTree` headless 断言测试,PowerShell `test/run_all.ps1` 全量。

## Global Constraints

（每个任务的要求都隐含包含本节，值逐字取自 spec §12）

- **版本**:三处一致 `0.9.0`(`core_kit.gd VERSION` / `plugin.cfg version` / `test_core_kit` 断言)。
- **向后兼容**:`core/log.gd` 只增不改,既有 `format_line`/`_should_log`/`_log`/`set_level`/`get_level`/`debug/info/warn/error` 行为与签名不变。
- **纯 GDScript、零重依赖、可 Web 导出**:不引入 `.tscn`、不引入 C#、控制台不做文件 IO(不落盘)。
- **门控**:发行版默认整体 no-op、零开销(`set_process(false)`+`set_process_input(false)`+不建 UI+不连 `log.line_logged` 信号);逻辑层(命令/求值/watch)始终可调用。
- **命令契约**:命令 callable 恒为 `func(args: PackedStringArray) -> Variant`。
- **求值错误**:evaluator 永不抛异常到 UI,一律折成 `{ok, value, error}`。
- **TDD**:每单元先写失败测试;全绿判据 = `test/run_all.ps1` 末行 `=== SUMMARY FAILS=0 ===` 且 demo stderr 无 `ERROR:`/`SCRIPT ERROR:`。
- **marker/断言用 ASCII**:PowerShell 5.1 误读非 BOM UTF-8 中文,`run_all.ps1` 断言串保持 ASCII(测试脚本内的中文 `print` 无妨,只要 marker 串是 ASCII)。
- **Godot 运行**:仅经前台跑,不后台化。单测 `godot --headless --path . -s res://test/<t>.gd`,看 `<t>: ALL PASS` + exit 0。
- **环境坑**:自定义 `SceneTree` 脚本 `_initialize()` 在主循环前跑,`root` 未真入树;凡 `root.add_child()` 后须 `await process_frame` 补一帧再断言(见 `test/test_state_machine.gd` 头注释)。首次引用需先 `godot --headless --path . --import` 生成类缓存。

---

### Task 1: Log 增补(line_logged 信号 + 有界环形缓冲)

**Files:**
- Modify: `addons/godot-core-kit/core/log.gd`
- Test: `test/test_log.gd`

**Interfaces:**
- Consumes: 无(仅扩展既有 `Log`)。
- Produces(后续 Task 3 经 `bind_core` 消费):
  - `signal line_logged(level: int, text: String)` —— 每条已打印行广播,`level` 为 `Level` 枚举整数,`text` 为已格式化整行。
  - `const HISTORY_MAX := 256`
  - `func history() -> Array[String]` —— 只读历史副本。
  - `func clear_history() -> void`

- [ ] **Step 1: 写失败测试(追加到 `test/test_log.gd`,插在 `logger.free()` 之前、即当前第 45 行前)**

```gdscript
	# 5. line_logged 信号 + history 缓冲(新 logger,默认 DEBUG 阈值放行 INFO)
	var logger2 = LogScript.new()
	var captured := {"count": 0, "last_level": -1, "last_text": ""}
	logger2.line_logged.connect(func(lvl: int, text: String) -> void:
		captured["count"] += 1
		captured["last_level"] = lvl
		captured["last_text"] = text)
	logger2.info("buffered line")
	if captured["count"] != 1:
		print("FAIL 5: line_logged 应触发一次,实际 %d" % captured["count"])
		failures += 1
	if captured["last_level"] != LogScript.Level.INFO:
		print("FAIL 5: line_logged level 应为 INFO")
		failures += 1
	if not String(captured["last_text"]).ends_with("buffered line"):
		print("FAIL 5: line_logged text 应以 'buffered line' 结尾,实际 '%s'" % captured["last_text"])
		failures += 1
	var hist: Array = logger2.history()
	if hist.size() != 1 or not String(hist[0]).ends_with("buffered line"):
		print("FAIL 5: history 应含一条 'buffered line'")
		failures += 1

	# 6. history 环形上限:压 HISTORY_MAX + 10 条后 size == HISTORY_MAX,最旧被丢
	var logger3 = LogScript.new()
	for i in range(LogScript.HISTORY_MAX + 10):
		logger3.info("line-%d" % i)
	if logger3.history().size() != LogScript.HISTORY_MAX:
		print("FAIL 6: history 应截断至 %d,实际 %d" % [LogScript.HISTORY_MAX, logger3.history().size()])
		failures += 1
	var h3: Array = logger3.history()
	if h3.size() > 0 and not String(h3[h3.size() - 1]).ends_with("line-%d" % (LogScript.HISTORY_MAX + 9)):
		print("FAIL 6: history 末条应为最新 line")
		failures += 1
	logger3.clear_history()
	if logger3.history().size() != 0:
		print("FAIL 6: clear_history 后应为空")
		failures += 1
	logger2.free()
	logger3.free()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `godot --headless --path . -s res://test/test_log.gd`
Expected: FAIL —— 出现 `SCRIPT ERROR` 或 `Invalid call`(`line_logged`/`history`/`HISTORY_MAX` 不存在),或 `test_log: N FAILURE(S)` + exit 1。

- [ ] **Step 3: 最小实现(改 `addons/godot-core-kit/core/log.gd`)**

3a. 在文件顶部 `enum Level { ... }`(当前第 12 行)之前、`## 用法` 行之后,加信号声明:

```gdscript
## 每条经阈值放行(即实际打印)的行都广播,供调试控制台等消费方订阅。
signal line_logged(level: int, text: String)
```

3b. 在 `var _level: Level = Level.DEBUG`(当前第 18 行)之后,加缓冲常量与成员:

```gdscript

## 供调试控制台 overlay 拉取的行历史上限(有界环形,防无界增长)。
const HISTORY_MAX := 256
var _history: Array[String] = []
```

3c. 在 `_log` 里,`var line := format_line(level, message)` 之后、`var color: String = ...` 之前,插入缓冲与广播:

```gdscript
	if _history.size() >= HISTORY_MAX:
		_history.pop_front()
	_history.append(line)
	line_logged.emit(level, line)
```

3d. 在文件末尾(`_log` 函数之后)追加两个方法:

```gdscript


## 只读历史副本(供控制台开启时灌入积压行)。
func history() -> Array[String]:
	return _history.duplicate()


## 清空历史缓冲。
func clear_history() -> void:
	_history.clear()
```

- [ ] **Step 4: 跑测试确认通过**

Run: `godot --headless --path . -s res://test/test_log.gd`
Expected: `test_log: ALL PASS` + exit 0。(注:Step 1 的第 6 段会打印约 266 行 `line-N` 到 stdout,属正常噪声,不进 stderr。)

- [ ] **Step 5: 提交**

```bash
git add addons/godot-core-kit/core/log.gd test/test_log.gd
git commit -m "feat(log): add line_logged signal + bounded history ring buffer for console overlay"
```

---

### Task 2: 三个纯逻辑单元(命令表 / 求值器 / watch 表)

**Files:**
- Create: `addons/godot-core-kit/console/console_command_registry.gd`
- Create: `addons/godot-core-kit/console/console_evaluator.gd`
- Create: `addons/godot-core-kit/console/console_watch_list.gd`
- Create: `test/fixtures/console_probe.gd`
- Create: `test/test_dev_console.gd`

**Interfaces:**
- Consumes: 无。
- Produces(Task 3 经 `preload` 消费):
  - **RegistryScript**:`register(name:String, callable:Callable, description:String="") -> void`;`unregister(name) -> void`;`has(name) -> bool`;`names() -> PackedStringArray`(升序);`description_of(name) -> String`;`dispatch(name:String, args:PackedStringArray) -> Variant`。
  - **EvaluatorScript**:`set_base(base:Object) -> void`;`bind_context(name:String, object) -> void`;`unbind_context(name) -> void`;`evaluate(text:String) -> Dictionary`(返回 `{ok:bool, value:Variant, error:String}`)。
  - **WatchScript**:`add(expr:String) -> void`(空串忽略、去重);`remove(expr) -> void`;`entries() -> Array[String]`;`clear() -> void`;`evaluate_all(evaluator) -> Array`(返回 `[{expr, ok, value, error}, ...]`)。
  - **console_probe.gd**(测试 fixture):`var hp: int = 100`;`var tag: String = "hero"`;`func greet(who:String) -> String`。

- [ ] **Step 1: 写测试文件 `test/test_dev_console.gd`(先失败:被测脚本尚不存在)**

```gdscript
extends SceneTree
## DevConsole headless 断言测试。
## 运行:godot --headless --path . -s res://test/test_dev_console.gd
## 逻辑单元(registry/evaluator/watch)直接实例化;dev_console 需入树,故 await 一帧。

const RegistryScript := preload("res://addons/godot-core-kit/console/console_command_registry.gd")
const EvaluatorScript := preload("res://addons/godot-core-kit/console/console_evaluator.gd")
const WatchScript := preload("res://addons/godot-core-kit/console/console_watch_list.gd")
const ProbeScript := preload("res://test/fixtures/console_probe.gd")


func _initialize() -> void:
	var failures := 0
	failures += _test_registry()
	failures += _test_evaluator()
	failures += _test_watch()

	if failures == 0:
		print("test_dev_console: ALL PASS")
		quit(0)
	else:
		print("test_dev_console: %d FAILURE(S)" % failures)
		quit(1)


func _test_registry() -> int:
	var f := 0
	var reg = RegistryScript.new()
	# 用 var 承接 lambda 再传描述,避免「单行 lambda 后跟参数」的解析歧义
	var echo_cmd := func(args: PackedStringArray) -> Variant: return " ".join(args)
	reg.register("echo", echo_cmd, "echo args")
	if not reg.has("echo"):
		print("FAIL registry: has('echo') 应为 true"); f += 1
	var r = reg.dispatch("echo", PackedStringArray(["a", "b"]))
	if r != "a b":
		print("FAIL registry: dispatch 应返回 'a b',实际 '%s'" % str(r)); f += 1
	if reg.description_of("echo") != "echo args":
		print("FAIL registry: description_of 错误"); f += 1
	reg.register("alpha", func(args: PackedStringArray) -> Variant: return null)
	var names := reg.names()
	if names.size() != 2 or names[0] != "alpha" or names[1] != "echo":
		print("FAIL registry: names() 应升序 [alpha, echo]"); f += 1
	reg.unregister("echo")
	if reg.has("echo"):
		print("FAIL registry: unregister 后 has 应为 false"); f += 1
	reg.register("", func(a: PackedStringArray) -> Variant: return 1)
	if reg.has(""):
		print("FAIL registry: 空名不应注册"); f += 1
	if reg.dispatch("nope", PackedStringArray()) != null:
		print("FAIL registry: dispatch 未注册应返回 null"); f += 1
	return f


func _test_evaluator() -> int:
	var f := 0
	var ev = EvaluatorScript.new()
	var r := ev.evaluate("1 + 2")
	if not r["ok"] or r["value"] != 3:
		print("FAIL evaluator: '1 + 2' 应为 3"); f += 1
	var probe = ProbeScript.new()
	ev.bind_context("player", probe)
	var r2 := ev.evaluate("player.hp")
	if not r2["ok"] or r2["value"] != 100:
		print("FAIL evaluator: player.hp 应为 100"); f += 1
	var r3 := ev.evaluate("player.greet(\"x\")")
	if not r3["ok"] or r3["value"] != "hi x":
		print("FAIL evaluator: player.greet 应为 'hi x'"); f += 1
	ev.set_base(probe)
	var r4 := ev.evaluate("hp")
	if not r4["ok"] or r4["value"] != 100:
		print("FAIL evaluator: base 裸 hp 应为 100"); f += 1
	var r5 := ev.evaluate("1 +")
	if r5["ok"] or String(r5["error"]).is_empty():
		print("FAIL evaluator: '1 +' 应 parse 失败带 error"); f += 1
	var r6 := ev.evaluate("nonexistent_member_xyz")
	if r6["ok"]:
		print("FAIL evaluator: 未知成员应求值失败"); f += 1
	return f


func _test_watch() -> int:
	var f := 0
	var wl = WatchScript.new()
	wl.add("1 + 1")
	wl.add("1 + 1")  # 去重
	wl.add("2 * 3")
	wl.add("")       # 空串忽略
	if wl.entries().size() != 2:
		print("FAIL watch: 去重/空串后应 2 条,实际 %d" % wl.entries().size()); f += 1
	var ev = EvaluatorScript.new()
	var results := wl.evaluate_all(ev)
	if results.size() != 2:
		print("FAIL watch: evaluate_all 应 2 条"); f += 1
	elif not results[0]["ok"] or results[0]["value"] != 2 or results[1]["value"] != 6:
		print("FAIL watch: evaluate_all 值错误"); f += 1
	wl.add("bad +")
	var results2 := wl.evaluate_all(ev)
	if results2.size() != 3 or results2[2]["ok"]:
		print("FAIL watch: 错误项应 ok=false 且不中断"); f += 1
	wl.remove("1 + 1")
	if wl.entries().has("1 + 1"):
		print("FAIL watch: remove 后不应含"); f += 1
	return f
```

- [ ] **Step 2: 跑测试确认失败**

Run: `godot --headless --path . -s res://test/test_dev_console.gd`
Expected: FAIL —— `preload` 解析不到脚本 → 解析/编译错误(`SCRIPT ERROR` 或 `Parse Error`),测试无法进入 `ALL PASS`。

- [ ] **Step 3a: 建 fixture `test/fixtures/console_probe.gd`**

```gdscript
extends RefCounted
## test fixture:供 evaluator 测试绑定的上下文对象(带属性 + 方法)。

var hp: int = 100
var tag: String = "hero"


func greet(who: String) -> String:
	return "hi " + who
```

- [ ] **Step 3b: 建 `addons/godot-core-kit/console/console_command_registry.gd`**

```gdscript
extends RefCounted
## 控制台命令表(纯逻辑,无 UI)。命令 callable 契约:func(args: PackedStringArray) -> Variant。
## 零依赖(诊断用 push_warning),可脱离框架单测。

var _commands: Dictionary = {}   # name(String) -> {callable: Callable, description: String}


## 登记命令。空名 → 忽略;无效 callable → 忽略;同名 → 覆盖 + 告警。
func register(name: String, callable: Callable, description: String = "") -> void:
	if name.is_empty():
		push_warning("ConsoleCommandRegistry.register: 空命令名,忽略")
		return
	if not callable.is_valid():
		push_warning("ConsoleCommandRegistry.register('%s'): 无效 callable,忽略" % name)
		return
	if _commands.has(name):
		push_warning("ConsoleCommandRegistry.register('%s'): 重复命令,覆盖" % name)
	_commands[name] = {"callable": callable, "description": description}


func unregister(name: String) -> void:
	_commands.erase(name)


func has(name: String) -> bool:
	return _commands.has(name)


## 已注册命令名,升序。
func names() -> PackedStringArray:
	var out := PackedStringArray(_commands.keys())
	out.sort()
	return out


func description_of(name: String) -> String:
	if _commands.has(name):
		return _commands[name]["description"]
	return ""


## 派发:以单参形式调用命令 callable(args 作为唯一实参)并返回其返回值;
## 未注册 → push_warning + 返回 null。
func dispatch(name: String, args: PackedStringArray) -> Variant:
	if not _commands.has(name):
		push_warning("ConsoleCommandRegistry.dispatch('%s'): 未注册" % name)
		return null
	var callable: Callable = _commands[name]["callable"]
	return callable.call(args)
```

- [ ] **Step 3c: 建 `addons/godot-core-kit/console/console_evaluator.gd`**

```gdscript
extends RefCounted
## 控制台表达式求值(纯逻辑,包 GDScript Expression)。
## parse/execute 错误全折成 {ok, value, error},永不抛到调用方。

var _base: Object = null          # 求值 base instance(裸标识符对它解析,通常 = CoreKit 门面)
var _contexts: Dictionary = {}    # name(String) -> object(作为 Expression input 变量注入)


func set_base(base: Object) -> void:
	_base = base


func bind_context(name: String, object) -> void:
	if name.is_empty():
		push_warning("ConsoleEvaluator.bind_context: 空名,忽略")
		return
	_contexts[name] = object


func unbind_context(name: String) -> void:
	_contexts.erase(name)


## 求值。返回 {ok: bool, value: Variant, error: String}。
func evaluate(text: String) -> Dictionary:
	var expr := Expression.new()
	var names := PackedStringArray(_contexts.keys())
	var err := expr.parse(text, names)
	if err != OK:
		return {"ok": false, "value": null, "error": expr.get_error_text()}
	var inputs: Array = []
	for n in names:                 # 与 names 同序(Dictionary 保插入序)
		inputs.append(_contexts[n])
	var result: Variant = expr.execute(inputs, _base, false)
	if expr.has_execute_failed():
		return {"ok": false, "value": null, "error": expr.get_error_text()}
	return {"ok": true, "value": result, "error": ""}
```

- [ ] **Step 3d: 建 `addons/godot-core-kit/console/console_watch_list.gd`**

```gdscript
extends RefCounted
## 控制台 watch 表(纯逻辑)。去重、保序;evaluate_all 复用传入 evaluator。

var _exprs: Array[String] = []


func add(expr: String) -> void:
	if expr.is_empty():
		return
	if not _exprs.has(expr):
		_exprs.append(expr)


func remove(expr: String) -> void:
	_exprs.erase(expr)


func entries() -> Array[String]:
	return _exprs.duplicate()


func clear() -> void:
	_exprs.clear()


## 逐条用 evaluator 求值。返回 [{expr, ok, value, error}, ...]。
func evaluate_all(evaluator) -> Array:
	var out: Array = []
	for e in _exprs:
		var r: Dictionary = evaluator.evaluate(e)
		out.append({"expr": e, "ok": r["ok"], "value": r["value"], "error": r["error"]})
	return out
```

- [ ] **Step 4: 跑测试确认通过**

Run: `godot --headless --path . --import`(首次生成缓存)然后 `godot --headless --path . -s res://test/test_dev_console.gd`
Expected: `test_dev_console: ALL PASS` + exit 0。

- [ ] **Step 5: 提交**

```bash
git add addons/godot-core-kit/console/console_command_registry.gd addons/godot-core-kit/console/console_evaluator.gd addons/godot-core-kit/console/console_watch_list.gd test/fixtures/console_probe.gd test/test_dev_console.gd
git commit -m "feat(console): add command registry, expression evaluator, watch list logic units + tests"
```

---

### Task 3: DevConsole 编排 + UI + 门控 + 公共 API

**Files:**
- Create: `addons/godot-core-kit/console/dev_console.gd`
- Test: `test/test_dev_console.gd`(追加 `_test_console` 协程 + 在 `_initialize` 里调用)

**Interfaces:**
- Consumes:
  - Task 1 `Log`:`line_logged(level, text)` 信号、`history() -> Array[String]`(经 `bind_core` 拿到的 core 的 `log` 属性)。
  - Task 2 三单元(`preload` 三脚本):Registry/Evaluator/Watch 的全部方法(见 Task 2 Produces)。
- Produces(Task 4 经门面消费):
  - `bind_core(core: Object) -> void`(由 `CoreKit._ready` 调用:设 evaluator base = core、按需连 log feed)。
  - `register_command(name, callable, description:="")` / `unregister_command(name)`。
  - `execute(text) -> String`(程序化提交,返回输出串)。
  - `bind_context(name, object)` / `unbind_context(name)`。
  - `watch(expr)` / `unwatch(expr)`。
  - `toggle()` / `open()` / `close()` / `is_open() -> bool`。
  - `set_enabled(v)` / `is_enabled() -> bool` / `force_enable()`。
  - `set_toggle_key(keycode:int)` / `set_pause_on_open(v:bool)`。

- [ ] **Step 1: 写失败测试(改 `test/test_dev_console.gd`)**

1a. 在文件顶部 `const ProbeScript := ...` 之后加一行 preload:

```gdscript
const ConsoleScript := preload("res://addons/godot-core-kit/console/dev_console.gd")
```

1b. 在 `_initialize()` 里,`failures += _test_watch()` 之后、`if failures == 0:` 之前,插入一行:

```gdscript
	failures += await _test_console()
```

1c. 在文件末尾追加协程:

```gdscript


func _test_console() -> int:
	var f := 0
	var c = ConsoleScript.new()
	root.add_child(c)
	await process_frame   # 让 _ready 跑(headless=debug build → _enabled=true → 建 UI)

	if not c.is_enabled():
		print("FAIL console: headless 应为 debug build → enabled"); f += 1

	if c.execute("1 + 2") != "3":
		print("FAIL console: execute('1 + 2') 应为 '3',实际 '%s'" % c.execute("1 + 2")); f += 1

	c.register_command("god", func(args: PackedStringArray) -> Variant: return "godmode on")
	if c.execute("god") != "godmode on":
		print("FAIL console: execute('god') 应为 'godmode on'"); f += 1

	c.register_command("add", func(args: PackedStringArray) -> Variant: return int(args[0]) + int(args[1]))
	if c.execute("add 2 5") != "7":
		print("FAIL console: execute('add 2 5') 应为 '7'"); f += 1

	if not c.execute("1 +").begins_with("ERROR:"):
		print("FAIL console: 错误表达式应 ERROR: 前缀"); f += 1

	if c.execute("2 + 2") != "4":
		print("FAIL console: 未命中命令应落表达式求值(不误判 '2' 为命令)"); f += 1

	# UI 冒烟:open/close 翻转 is_open
	c.open()
	if not c.is_open():
		print("FAIL console: open 后 is_open 应真"); f += 1
	c.close()
	if c.is_open():
		print("FAIL console: close 后 is_open 应假"); f += 1

	# 门控:disabled 下 UI/toggle 死,但 execute 逻辑层仍工作
	c.set_enabled(false)
	if c.is_enabled():
		print("FAIL console: set_enabled(false) 后应 disabled"); f += 1
	c.toggle()
	if c.is_open():
		print("FAIL console: disabled 下 toggle 不应打开"); f += 1
	if c.execute("3 + 4") != "7":
		print("FAIL console: disabled 下 execute 逻辑层仍应工作"); f += 1

	# watch 委托冒烟(不崩即可)
	c.set_enabled(true)
	c.watch("1 + 1")
	c.unwatch("1 + 1")

	c.queue_free()
	return f
```

- [ ] **Step 2: 跑测试确认失败**

Run: `godot --headless --path . -s res://test/test_dev_console.gd`
Expected: FAIL —— `preload` `dev_console.gd` 不存在 → 解析错误,或 `_test_console` 调用不到方法。

- [ ] **Step 3: 实现 `addons/godot-core-kit/console/dev_console.gd`**

```gdscript
extends CanvasLayer
## DevConsole —— 运行时调试控制台(CoreKit 第 11 子系统,面向前端 UI)。
## 完整四件套:日志 overlay + 命令/作弊注册 + GDScript 表达式执行 + 变量 watch。
## 门控:默认仅 OS.is_debug_build() 启用;发行版整体 no-op、零开销(可 force_enable 强开)。
## 全代码建 UI(无 .tscn),纯 GDScript、可 Web 导出。
##
## 用法:CoreKit.console.register_command("god", func(a): return "on")
##       CoreKit.console.bind_context("player", $Player)   # 后 player.hp=100 可求值
##       CoreKit.console.watch("player.hp")
##       控制台输入行:命中命令则派发,否则整行走 GDScript 表达式求值。
## 默认切换键 `(KEY_QUOTELEFT / ~),set_toggle_key 可改。

const RegistryScript := preload("res://addons/godot-core-kit/console/console_command_registry.gd")
const EvaluatorScript := preload("res://addons/godot-core-kit/console/console_evaluator.gd")
const WatchScript := preload("res://addons/godot-core-kit/console/console_watch_list.gd")

const TOGGLE_KEY_DEFAULT := KEY_QUOTELEFT
const WATCH_INTERVAL := 0.1
const INPUT_HISTORY_MAX := 64
## 日志 level → bbcode 颜色(镜像 Log._LEVEL_COLORS;INFO 用 "" 表默认色)。
const _LEVEL_COLOR := ["gray", "", "yellow", "red"]

var _registry
var _evaluator
var _watch
var _core: Object = null
var _enabled: bool = false
var _toggle_key: int = TOGGLE_KEY_DEFAULT
var _pause_on_open: bool = false
var _was_paused: bool = false
var _ui_built: bool = false
var _log_connected: bool = false
var _watch_accum: float = 0.0
var _input_history: Array[String] = []
var _history_index: int = 0

# UI 节点(建后持有)
var _root: Control
var _output: RichTextLabel
var _input: LineEdit
var _watch_label: RichTextLabel


func _init() -> void:
	_registry = RegistryScript.new()
	_evaluator = EvaluatorScript.new()
	_watch = WatchScript.new()
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_enabled = OS.is_debug_build()
	if _enabled:
		_activate()
	else:
		set_process(false)
		set_process_input(false)


# --- 门面接线(由 CoreKit._ready 调用)------------------------------------
func bind_core(core: Object) -> void:
	_core = core
	_evaluator.set_base(core)
	if _enabled:
		_connect_log_feed()


# --- 启停 -----------------------------------------------------------------
func _activate() -> void:
	if not _ui_built:
		_build_ui()
	set_process(true)
	set_process_input(true)
	if _core != null:
		_connect_log_feed()


func _deactivate() -> void:
	close()
	set_process(false)
	set_process_input(false)
	_disconnect_log_feed()


func set_enabled(v: bool) -> void:
	if v:
		force_enable()
	else:
		_enabled = false
		_deactivate()


func is_enabled() -> bool:
	return _enabled


func force_enable() -> void:
	if _enabled and _ui_built:
		return
	_enabled = true
	_activate()


func _connect_log_feed() -> void:
	if _log_connected or _core == null:
		return
	var logger = _core.get("log")
	if logger == null:
		return
	logger.line_logged.connect(_on_log_line)
	_log_connected = true
	for line in logger.history():
		_append_output(String(line))


func _disconnect_log_feed() -> void:
	if not _log_connected or _core == null:
		return
	var logger = _core.get("log")
	if logger != null and logger.line_logged.is_connected(_on_log_line):
		logger.line_logged.disconnect(_on_log_line)
	_log_connected = false


# --- 公共 API:命令 / 上下文 / watch(委托逻辑单元)------------------------
func register_command(name: String, callable: Callable, description: String = "") -> void:
	_registry.register(name, callable, description)


func unregister_command(name: String) -> void:
	_registry.unregister(name)


func bind_context(name: String, object) -> void:
	_evaluator.bind_context(name, object)


func unbind_context(name: String) -> void:
	_evaluator.unbind_context(name)


func watch(expr: String) -> void:
	_watch.add(expr)


func unwatch(expr: String) -> void:
	_watch.remove(expr)


func set_toggle_key(keycode: int) -> void:
	_toggle_key = keycode


func set_pause_on_open(v: bool) -> void:
	_pause_on_open = v


# --- 提交 -----------------------------------------------------------------
## 程序化提交:回显 "> text",执行,返回输出串(UI 未建也可用 —— headless 命门)。
func execute(text: String) -> String:
	var out := _run(text)
	if _ui_built:
		_append_output("> " + text)
		if out != "":
			_append_output(out)
	return out


func _run(text: String) -> String:
	var trimmed := text.strip_edges()
	if trimmed == "":
		return ""
	var parts := trimmed.split(" ", false)
	var head := String(parts[0])
	if _registry.has(head):
		var args: PackedStringArray = parts.slice(1)
		var r = _registry.dispatch(head, args)
		return "" if r == null else str(r)
	var res: Dictionary = _evaluator.evaluate(trimmed)
	return str(res["value"]) if res["ok"] else "ERROR: " + String(res["error"])


# --- 显隐 -----------------------------------------------------------------
func toggle() -> void:
	if not _enabled or not _ui_built:
		return
	if is_open():
		close()
	else:
		open()


func open() -> void:
	if not _enabled or not _ui_built:
		return
	_root.visible = true
	_input.grab_focus()
	if _pause_on_open:
		_was_paused = get_tree().paused
		get_tree().paused = true


func close() -> void:
	if not _ui_built:
		return
	_root.visible = false
	if _pause_on_open:
		get_tree().paused = _was_paused


func is_open() -> bool:
	return _ui_built and _root.visible


# --- 每帧 watch(仅启用且可见)---------------------------------------------
func _process(delta: float) -> void:
	if not _enabled or not is_open():
		return
	_watch_accum += delta
	if _watch_accum < WATCH_INTERVAL:
		return
	_watch_accum = 0.0
	_refresh_watch()


func _refresh_watch() -> void:
	if _watch_label == null:
		return
	var results := _watch.evaluate_all(_evaluator)
	var sb := ""
	for entry in results:
		if entry["ok"]:
			sb += "%s = %s\n" % [entry["expr"], str(entry["value"])]
		else:
			sb += "[color=red]%s ! %s[/color]\n" % [entry["expr"], _escape_bbcode(String(entry["error"]))]
	_watch_label.text = sb


# --- 输入 -----------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == _toggle_key:
		toggle()
		get_viewport().set_input_as_handled()


func _on_submit(text: String) -> void:
	execute(text)
	if not text.strip_edges().is_empty():
		_input_history.append(text)
		if _input_history.size() > INPUT_HISTORY_MAX:
			_input_history.pop_front()
	_history_index = _input_history.size()
	_input.clear()


func _on_input_gui(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			_recall_history(-1)
			_input.accept_event()
		elif event.keycode == KEY_DOWN:
			_recall_history(1)
			_input.accept_event()


func _recall_history(dir: int) -> void:
	if _input_history.is_empty():
		return
	_history_index = clampi(_history_index + dir, 0, _input_history.size())
	if _history_index >= _input_history.size():
		_input.text = ""
	else:
		_input.text = _input_history[_history_index]
	_input.caret_column = _input.text.length()


# --- 输出 -----------------------------------------------------------------
func _append_output(text: String) -> void:
	if not _ui_built or _output == null:
		return
	_output.append_text(_escape_bbcode(text) + "\n")


func _on_log_line(level: int, text: String) -> void:
	if not _ui_built or _output == null:
		return
	var color: String = _LEVEL_COLOR[level] if level >= 0 and level < _LEVEL_COLOR.size() else ""
	if color.is_empty():
		_append_output(text)
	else:
		_output.append_text("[color=%s]%s[/color]\n" % [color, _escape_bbcode(text)])


## 转义 bbcode:日志/结果文本里的 '[' 不应被 RichTextLabel 当标签解析。
func _escape_bbcode(s: String) -> String:
	return s.replace("[", "[lb]")


# --- UI 建构(全代码,无 .tscn)-------------------------------------------
func _build_ui() -> void:
	_root = Control.new()
	_root.name = "ConsoleRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 320.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	_output = RichTextLabel.new()
	_output.bbcode_enabled = true
	_output.scroll_following = true
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.custom_minimum_size = Vector2(0, 260)
	vbox.add_child(_output)

	_input = LineEdit.new()
	_input.placeholder_text = "命令或 GDScript 表达式,回车执行"
	_input.text_submitted.connect(_on_submit)
	_input.gui_input.connect(_on_input_gui)
	vbox.add_child(_input)

	_watch_label = RichTextLabel.new()
	_watch_label.bbcode_enabled = true
	_watch_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_watch_label.offset_left = -240.0
	_watch_label.offset_bottom = 160.0
	_watch_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_watch_label)

	_ui_built = true
```

- [ ] **Step 4: 跑测试确认通过**

Run: `godot --headless --path . -s res://test/test_dev_console.gd`
Expected: `test_dev_console: ALL PASS` + exit 0。

- [ ] **Step 5: 提交**

```bash
git add addons/godot-core-kit/console/dev_console.gd test/test_dev_console.gd
git commit -m "feat(console): add DevConsole CanvasLayer subsystem (UI + gating + public API)"
```

---

### Task 4: 门面接线 + 版本 0.9.0 + 文档 + demo + run_all

**Files:**
- Modify: `addons/godot-core-kit/core_kit.gd`
- Modify: `addons/godot-core-kit/plugin.cfg`
- Modify: `test/test_core_kit.gd`
- Create: `addons/godot-core-kit/docs/console.md`
- Modify: `addons/godot-core-kit/docs/architecture.md`
- Modify: `README.md`
- Modify: `demo/demo.gd`
- Modify: `test/run_all.ps1`

**Interfaces:**
- Consumes: Task 3 `dev_console.gd`(第 11 子系统 + `bind_core`);Task 1 `Log.VERSION` 无关(VERSION 在 core_kit)。
- Produces: `CoreKit.console`(门面属性)、`CoreKit.VERSION == "0.9.0"`、`RESERVED_KEYS` 含 `"console"`。

- [ ] **Step 1: 写失败测试(改 `test/test_core_kit.gd`)**

1a. 版本断言(第 25-27 行)改为 0.9.0:

```gdscript
	# 1. 版本
	if kit.VERSION != "0.9.0":
		print("FAIL 1: VERSION 应为 0.9.0,实际 %s" % kit.VERSION)
		failures += 1
```

1b. `expected` 数组(第 30-41 行)末尾、`["res", ...]` 行之后加一行:

```gdscript
		["console", "res://addons/godot-core-kit/console/dev_console.gd"],
```

1c. `order` 数组(第 54-55 行)末尾加 `"DevConsole"`:

```gdscript
	var order := ["Log", "Settings", "EventBus", "SceneManager", "ObjectPool",
		"SaveManager", "FrameScheduler", "InputManager", "AudioManager", "ResourceManager", "DevConsole"]
```

1d. `builtin_keys` 数组(第 88-89 行)末尾加 `"console"`:

```gdscript
	var builtin_keys := ["log", "settings", "bus", "scenes", "pool", "saves",
		"ticker", "input", "audio", "res", "console"]
```

- [ ] **Step 2: 跑测试确认失败**

Run: `godot --headless --path . -s res://test/test_core_kit.gd`
Expected: FAIL —— VERSION 仍 0.8.0、`CoreKit.console` 为 null、子节点数 10≠11 → 多条 `FAIL` + exit 1。

- [ ] **Step 3a: 门面接线(改 `addons/godot-core-kit/core_kit.gd`)**

版本(第 13 行):
```gdscript
const VERSION := "0.9.0"
```

`RESERVED_KEYS`(第 17-18 行)加 `"console"`:
```gdscript
const RESERVED_KEYS := ["log", "settings", "bus", "scenes", "pool", "saves",
	"ticker", "input", "audio", "res", "console"]
```

preload 常量区(第 29 行 `ResourceManagerScript` 之后)加:
```gdscript
const ConsoleScript := preload("res://addons/godot-core-kit/console/dev_console.gd")
```

强类型属性区(第 40 行 `var res:` 之后)加:
```gdscript
var console: ConsoleScript
```

`_init()` 里(第 84-86 行 `res` 构造块之后)加第 11 子系统构造:
```gdscript

	console = ConsoleScript.new()
	console.name = "DevConsole"
	add_child(console)
```

`_ready()` 接线块里(第 93 行 `res.bind_ticker(ticker)` 之后)加:
```gdscript
	console.bind_core(self)
```

`_ready()` 预注册块里(第 106 行 `_services["res"] = res` 之后)加:
```gdscript
	_services["console"] = console
```

- [ ] **Step 3b: `plugin.cfg`(改 `addons/godot-core-kit/plugin.cfg`)**

`version`(第 6 行)改 `"0.9.0"`;`description`(第 4 行)末尾(闭合引号前)追加:
```
;0.9.0 新增 DevConsole 调试控制台(CoreKit.console 第 11 子系统,CanvasLayer,debug 门控):日志 overlay + 命令/作弊注册 + GDScript 表达式执行 + 变量 watch
```

- [ ] **Step 3c: 新建 `addons/godot-core-kit/docs/console.md`**

```markdown
# DevConsole 调试控制台(`CoreKit.console`)

> 版本 0.9.0 新增。core-kit 首个面向前端的 UI 子系统。纯 GDScript、可 Web 导出。

## 职责

运行时调试控制台(对标 PankuConsole 核心),四件套:

1. **日志 overlay** —— 实时显示 `CoreKit.log` 输出(开启时先灌历史、后续实时追加)。
2. **命令 / 作弊注册** —— 游戏代码注册命名命令,控制台输入行调用。
3. **表达式执行** —— 输入任意 GDScript 表达式,基于 `Expression` 求值,可读写运行时状态。
4. **变量 watch** —— 登记表达式,控制台可见时每帧(节流 ~10Hz)求值并显示。

## 门控与安全

- 默认仅 `OS.is_debug_build()` 下启用。发行版整体 no-op、零开销(不建 UI、不连日志信号、`set_process(false)`)。
- `force_enable()` / `set_enabled(true)` 可在发行版强开(自负其责)。
- **安全**:表达式执行会运行**任意 GDScript**。这是开发调试工具,勿在不可信输入或发行版随意开放;绑定的上下文对象会被暴露给求值。

## 公开 API

| 方法 | 说明 |
|---|---|
| `register_command(name, callable, description := "")` | 注册命令。callable 契约:`func(args: PackedStringArray) -> Variant`,返回值 `str()` 回显 |
| `unregister_command(name)` | 注销命令 |
| `execute(text) -> String` | 程序化提交一行,返回输出串(命中命令则派发,否则整行走表达式求值);UI 未建也可用 |
| `bind_context(name, object)` | 绑定求值上下文对象,之后 `name.member` 可在表达式里访问 |
| `unbind_context(name)` | 解绑 |
| `watch(expr)` / `unwatch(expr)` | 增删 watch 表达式(去重) |
| `toggle()` / `open()` / `close()` / `is_open()` | 显隐控制(未启用为 no-op) |
| `set_enabled(v)` / `is_enabled()` / `force_enable()` | 门控开关 |
| `set_toggle_key(keycode)` | 改切换键(默认 `KEY_QUOTELEFT` / ~) |
| `set_pause_on_open(v)` | 开启时是否暂停 `get_tree()`(默认 false,便于运行中实时 watch/作弊) |

## 依赖

- 由 `CoreKit._ready` 调 `console.bind_core(self)` 注入门面:设为表达式求值 base(裸标识符可达门面成员,如 `audio`、`saves`、`VERSION`)+ 订阅 `CoreKit.log.line_logged` 喂 overlay。
- 内部逻辑拆三个纯逻辑单元:`console_command_registry.gd` / `console_evaluator.gd` / `console_watch_list.gd`。

## 用法示例

```gdscript
# 注册作弊命令(args 是空格分隔的其余 token)
CoreKit.console.register_command("god", func(args): 
	player.invincible = true
	return "godmode on")

CoreKit.console.register_command("give", func(args):
	var n := int(args[1]) if args.size() > 1 else 1
	inventory.add(args[0], n)
	return "gave %d %s" % [n, args[0]])

# 绑定上下文 + watch
CoreKit.console.bind_context("player", $Player)
CoreKit.console.watch("player.hp")
CoreKit.console.watch("Engine.get_frames_per_second()")

# 程序化执行(也可玩家在控制台输入行手打)
CoreKit.console.execute("player.hp = 999")   # 表达式:直接改状态
CoreKit.console.execute("give sword 3")       # 命令:派发
```

按 `~`(反引号)开合控制台;输入行支持 up/down 历史回溯。

## 注意事项

- **命令 vs 表达式**:输入行首 token 命中已注册命令则按命令派发(其余 token 作 `PackedStringArray`),否则整行按 GDScript 表达式求值。故 `2 + 2` 不会被误判为「未知命令 2」。
- **求值错误**不崩:parse/execute 失败以 `ERROR: <text>` 回显。
- **日志 overlay** 仅镜像经阈值放行(实际打印)的行;`CoreKit.log.set_level(WARN)` 后 DEBUG/INFO 既不打印也不进 overlay。
- **watch 开销**:仅在启用且可见时按 `WATCH_INTERVAL`(0.1s)节流求值,隐藏/禁用零开销。
- **UI 全代码建**,无 `.tscn` 依赖;`layer = 128` 覆盖最上层,`process_mode = ALWAYS` 暂停也可用。
```

- [ ] **Step 3d: `docs/architecture.md`(改)**

- 第 3 行「统管 10 个子系统」→「统管 11 个子系统」。
- 第 7 行「构造全部 10 个子系统」→「构造全部 11 个子系统」。
- 门面属性表(第 20 行 `CoreKit.res` 行之后)加一行:
  ```markdown
  | `CoreKit.console` | DevConsole 调试控制台(UI,dev 门控) | `console/dev_console.gd` |
  ```
- 目录布局代码块(第 36 行 `di/` 行之后)加一行:
  ```
    console/               DevConsole 调试控制台(CanvasLayer 子系统)
  ```
- 构造顺序串(第 46 行)末尾加 `→ console`:
  ```
  log → settings → bus → scenes → pool → saves → ticker → input → audio → res → console
  ```
- `_ready` 代码块(第 52-56 行)在 `res.bind_ticker(ticker)` 之后加一行:
  ```gdscript
      console.bind_core(self)         # 注入门面:求值 base + 日志 overlay 源
  ```
- 依赖纪律「当前经 bind_* 建立的依赖」(第 65 行)末尾补:`console → core(门面自身,注入求值 base + 日志源)`。
- 「测试」段(第 85 行)「import → 13 测试 → demo」→「import → 14 测试 → demo」。
- 「版本」段(第 89 行)段首把「当前 `0.8.0`」改「当前 `0.9.0`」,并在句首补一句:
  ```
  0.8.0→0.9.0 新增 DevConsole 调试控制台(`CoreKit.console` 第 11 子系统,CanvasLayer,debug 门控:日志 overlay + 命令/作弊注册 + GDScript 表达式执行 + 变量 watch),纯增量、向后兼容;
  ```

- [ ] **Step 3e: `README.md`(改)**

- 第 3 行子系统一句话里的类库列举保持;门面属性表(第 27 行 `CoreKit.res` 行之后)加一行:
  ```markdown
  | `CoreKit.console` | 运行时调试控制台(dev) | [console](addons/godot-core-kit/docs/console.md) |
  ```
- 「版本」段(第 46 行 `- **0.8.0**` 之前)加一行:
  ```markdown
  - **0.9.0** — 新增 `DevConsole` 调试控制台(`CoreKit.console` 第 11 子系统,CanvasLayer,`OS.is_debug_build()` 门控):日志 overlay + 命令/作弊注册 + GDScript 表达式执行(`Expression`)+ 变量 watch;`core/log.gd` 增补 `line_logged` 信号 + 有界历史缓冲(向后兼容);纯增量,API 无破坏。
  ```

- [ ] **Step 3f: `demo/demo.gd`(改)**

在 `CoreKit.log.info("CoreKit v%s — all subsystems smoke-tested" % CoreKit.VERSION)`(当前第 96 行)**之前**插入 DevConsole 冒烟段:

```gdscript
	# DevConsole 冒烟:注册作弊命令 + 绑定上下文 + watch + 程序化 execute(经门面)
	var cheat := func(args: PackedStringArray) -> Variant: return "god mode"
	CoreKit.console.register_command("god", cheat, "toggle god mode")
	CoreKit.console.bind_context("demo_ctx", self)
	CoreKit.console.watch("1 + 1")
	CoreKit.log.info("DevConsole: execute(1+2)=%s" % CoreKit.console.execute("1 + 2"))
	CoreKit.log.info("DevConsole: god cheat -> %s" % CoreKit.console.execute("god"))

```

- [ ] **Step 3g: `test/run_all.ps1`(改)**

- 第 1 行注释「13 个断言测试」→「14 个断言测试」。
- `$tests` 数组(第 55-57 行)末尾 `'test_core_kit'` 之后加 `'test_dev_console'`:
  ```powershell
  $tests = @('test_log','test_event_bus','test_scene_manager','test_object_pool',
    'test_save_manager','test_settings','test_frame_scheduler','test_state_machine',
    'test_input_manager','test_audio_manager','test_resource_manager','test_kit_context','test_core_kit','test_dev_console')
  ```
- demo markers 数组(第 72 行)末尾追加两个 ASCII marker:
  ```powershell
  foreach ($e in @('all subsystems smoke-tested','FrameScheduler:','ResourceManager:','KitContext:','-> [Idle]','-> [Run]','-> [Menu]','dispatch(stop) hit=true','stack_depth=0','execute(1+2)=3','god cheat -> god mode')) {
  ```

- [ ] **Step 4: 跑全量确认通过**

Run: `powershell -File test\run_all.ps1`
Expected: 末行 `=== SUMMARY FAILS=0 ===`;`test_dev_console` 行 `pass=True OK`;`test_core_kit` 行 `OK`;两个新 demo marker `present`;`demo stderr has ERROR: no`。

- [ ] **Step 5: 提交**

```bash
git add addons/godot-core-kit/core_kit.gd addons/godot-core-kit/plugin.cfg test/test_core_kit.gd addons/godot-core-kit/docs/console.md addons/godot-core-kit/docs/architecture.md README.md demo/demo.gd test/run_all.ps1
git commit -m "feat(console): wire DevConsole as 11th subsystem, bump 0.9.0, docs + demo + run_all"
```

---

## Self-Review(计划自审 —— 对照 spec)

**1. Spec 覆盖:**
- §1 架构/接入(第 11 子系统 + bind_core + 门控)→ Task 3(门控/API)+ Task 4(接线)。✅
- §2 组件文件结构 → Task 2(三单元)+ Task 3(dev_console)+ Task 1(log)。✅
- §3 command_registry / §4 evaluator / §5 watch_list → Task 2(含逐方法签名 + 测试)。✅
- §6 Log 增补(signal + 环形缓冲)→ Task 1。✅
- §7 dev_console(生命周期/提交/输入/显隐/watch/API)→ Task 3。✅
- §8 数据流 / §9 错误处理 → Task 1(缓冲上限)+ Task 2(evaluate 折错)+ Task 3(_run 落表达式、ERROR: 前缀、门控 no-op)。✅
- §10 测试计划 → Task 1/2/3 的测试步骤 + Task 4 run_all marker。✅
- §11 收尾件 & 版本 → Task 4(core_kit/plugin.cfg/test_core_kit/console.md/architecture.md/README.md/demo/run_all)。✅
- §12 全局约束 → 本计划 Global Constraints(逐字)。✅

**2. 占位符扫描:** 无 TBD/TODO;每个改码步骤都给了完整代码或精确 old→new edit。✅

**3. 类型一致性:** `evaluate` 返回 `{ok, value, error}` 在 Task 2 定义、Task 3 `_run`/`_refresh_watch` 消费一致;命令契约 `func(args: PackedStringArray) -> Variant` 在 Task 2/3/4 一致;`bind_core` 在 Task 3 定义、Task 4 调用一致;`history()`/`line_logged` 在 Task 1 定义、Task 3 `_connect_log_feed` 消费一致;`RESERVED_KEYS`/`order`/`expected`/`builtin_keys` 在 Task 4 同步加 `console`/`DevConsole`,与 Task 3 属性名 `console`、节点名 `"DevConsole"`、脚本路径一致。✅
