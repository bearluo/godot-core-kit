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

	logger.free()

	if failures == 0:
		print("test_log: ALL PASS")
		quit(0)
	else:
		print("test_log: %d FAILURE(S)" % failures)
		quit(1)
