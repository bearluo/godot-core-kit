extends SceneTree
## DevConsole headless 断言测试。
## 运行:godot --headless --path . -s res://test/test_dev_console.gd
## 逻辑单元(registry/evaluator/watch)直接实例化;dev_console 需入树,故 await 一帧。

const RegistryScript := preload("res://addons/godot-core-kit/console/console_command_registry.gd")
const EvaluatorScript := preload("res://addons/godot-core-kit/console/console_evaluator.gd")
const WatchScript := preload("res://addons/godot-core-kit/console/console_watch_list.gd")
const ProbeScript := preload("res://test/fixtures/console_probe.gd")
const ConsoleScript := preload("res://addons/godot-core-kit/console/dev_console.gd")


func _initialize() -> void:
	var failures := 0
	failures += _test_registry()
	failures += _test_evaluator()
	failures += _test_watch()
	failures += await _test_console()

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
