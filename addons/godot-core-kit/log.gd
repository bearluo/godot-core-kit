extends Node
## Log —— godot-core-kit 全局日志单例(骨架首版)。
##
## 以 autoload "Log" 注册。四级分级(DEBUG/INFO/WARN/ERROR)+ 统一格式
## [HH:MM:SS.mmm][LEVEL] message + 全局阈值过滤(默认 DEBUG,运行时 set_level 可改)
## + print_rich 彩色输出。WARN/ERROR 额外走 push_warning/push_error 进编辑器
## "错误"面板并带调用栈。纯 GDScript、无文件 IO,支持 Web 导出。
##
## 用法:Log.info("msg")、Log.warn("x=%d" % x)、Log.set_level(Log.Level.WARN)

enum Level { DEBUG, INFO, WARN, ERROR }

const _LEVEL_NAMES := ["DEBUG", "INFO", "WARN", "ERROR"]
## 颜色映射:INFO 用 "" 表示默认色,不包 [color] 标签。
const _LEVEL_COLORS := ["gray", "", "yellow", "red"]

var _level: Level = Level.DEBUG


func set_level(level: Level) -> void:
	_level = level


func get_level() -> Level:
	return _level


func debug(message) -> void:
	_log(Level.DEBUG, message)


func info(message) -> void:
	_log(Level.INFO, message)


func warn(message) -> void:
	_log(Level.WARN, message)


func error(message) -> void:
	_log(Level.ERROR, message)


func _should_log(level: Level) -> bool:
	return level >= _level


## 返回格式化后的一行,不打印(供测试与内部复用)。
func format_line(level: Level, message) -> String:
	var unix := Time.get_unix_time_from_system()
	var ms := int(fmod(unix, 1.0) * 1000.0)
	var time_str := Time.get_time_string_from_system()
	return "[%s.%03d][%s] %s" % [time_str, ms, _LEVEL_NAMES[level], str(message)]


func _log(level: Level, message) -> void:
	if not _should_log(level):
		return
	var line := format_line(level, message)
	var color: String = _LEVEL_COLORS[level]
	if color.is_empty():
		print_rich(line)
	else:
		print_rich("[color=%s]%s[/color]" % [color, line])
	if level == Level.WARN:
		push_warning(line)
	elif level == Level.ERROR:
		push_error(line)
