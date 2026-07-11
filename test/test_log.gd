extends SceneTree
## Log headless 断言测试(不依赖 autoload,直接实例化脚本)。
## 运行:godot --headless -s res://test/test_log.gd

const LogScript := preload("res://addons/godot-core-kit/core/log.gd")


func _initialize() -> void:
	var failures := 0
	var logger = LogScript.new()  # 变量名避开内置 log() 函数

	# 1. format_line 结构:[HH:MM:SS.mmm][INFO] hello
	var line: String = logger.format_line(LogScript.Level.INFO, "hello")
	var re := RegEx.new()
	re.compile("^\\[\\d\\d:\\d\\d:\\d\\d\\.\\d\\d\\d\\]\\[INFO\\] hello$")
	if re.search(line) == null:
		print("FAIL format_line: 得到 '%s'" % line)
		failures += 1

	# 2. 默认阈值 DEBUG 放行 DEBUG
	if not logger._should_log(LogScript.Level.DEBUG):
		print("FAIL 默认阈值应放行 DEBUG")
		failures += 1

	# 3. set_level(WARN) 后过滤 DEBUG/INFO,放行 WARN/ERROR
	logger.set_level(LogScript.Level.WARN)
	if logger._should_log(LogScript.Level.DEBUG):
		print("FAIL WARN 阈值不应放行 DEBUG")
		failures += 1
	if logger._should_log(LogScript.Level.INFO):
		print("FAIL WARN 阈值不应放行 INFO")
		failures += 1
	if not logger._should_log(LogScript.Level.WARN):
		print("FAIL WARN 阈值应放行 WARN")
		failures += 1
	if not logger._should_log(LogScript.Level.ERROR):
		print("FAIL WARN 阈值应放行 ERROR")
		failures += 1

	# 4. get_level 反映 set_level
	if logger.get_level() != LogScript.Level.WARN:
		print("FAIL get_level 应为 WARN")
		failures += 1

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
	logger.free()

	if failures == 0:
		print("test_log: ALL PASS")
		quit(0)
	else:
		print("test_log: %d FAILURE(S)" % failures)
		quit(1)
