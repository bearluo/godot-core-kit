extends Node
## Settings —— 玩家偏好分区键值,写透落盘 user://settings.json。
##
## 定位:设置 ≠ 存档。音量/键位/语言这类"跨存档、装完游戏就该记住"的键值
## 落这里,不走 SaveManager(不出现在存档槽列表、不被删档误删)。
## 由 CoreKit 门面构造并经 CoreKit.settings 访问;InputManager/AudioManager
## 经 bind_settings() 注入本实例做持久化。
##
## 注意:JSON 往返会把 int 变 float(与 SaveManager 同款,JSON 规范决定),
## 取整用 int(get_value(...))。value 限 JSON 可表达类型(bool/int/float/
## String/Array/Dictionary),调用方自律,不做运行时校验。

## 任何 set_value/erase_* 实际改变了值之后广播(值未变化的 set 不广播);
## erase_value 广播 value=null;erase_section 广播一次 (section, "", null)。
signal value_changed(section: String, key: String, value: Variant)

## 落盘路径。var 而非 const:测试注入接缝(重定向到一次性文件),语义不变。
var settings_path: String = "user://settings.json"

## 内存态,形状 {section(String): {key(String): value}}。
var _data: Dictionary = {}


func _ready() -> void:
	_load_from_disk()


func get_value(section: String, key: String, default: Variant = null) -> Variant:
	if not _data.has(section):
		return default
	var sec: Dictionary = _data[section]
	if not sec.has(key):
		return default
	var value: Variant = sec[key]
	# 容器返回深拷贝:调用方 read-modify-write 不会别名到 _data,否则 set_value
	# 的"值未变化"判等会因同一引用恒真而静默跳过落盘(silent data loss)。
	if typeof(value) == TYPE_DICTIONARY or typeof(value) == TYPE_ARRAY:
		return value.duplicate(true)
	return value


func set_value(section: String, key: String, value: Variant) -> void:
	if _data.has(section) and _data[section].has(key) and _data[section][key] == value:
		return
	if not _data.has(section):
		_data[section] = {}
	# 容器存深拷贝:调用方之后再改自己那份引用,不会静默改到 _data / 落盘不同步。
	var to_store: Variant = value
	if typeof(value) == TYPE_DICTIONARY or typeof(value) == TYPE_ARRAY:
		to_store = value.duplicate(true)
	_data[section][key] = to_store
	_save_to_disk()
	value_changed.emit(section, key, to_store)


func has_value(section: String, key: String) -> bool:
	return _data.has(section) and _data[section].has(key)


func erase_value(section: String, key: String) -> void:
	if not has_value(section, key):
		return
	_data[section].erase(key)
	if _data[section].is_empty():
		_data.erase(section)
	_save_to_disk()
	value_changed.emit(section, key, null)


func erase_section(section: String) -> void:
	if not _data.has(section):
		return
	_data.erase(section)
	_save_to_disk()
	value_changed.emit(section, "", null)


## --- 可测接缝 ---

func _encode(data: Dictionary) -> String:
	return JSON.stringify(data, "\t")


## 任何失败(JSON 非法、根不是 Dictionary)返回 {};非 Dictionary 的
## section 值在此丢弃(schema 不符视同损坏的局部)。
func _decode(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var result: Dictionary = {}
	for section in parsed:
		if typeof(parsed[section]) == TYPE_DICTIONARY:
			result[section] = parsed[section]
	return result


func _load_from_disk() -> void:
	if not FileAccess.file_exists(settings_path):
		return
	var file := FileAccess.open(settings_path, FileAccess.READ)
	if file == null:
		push_warning("Settings: 无法读取 %s(错误码 %d),从空配置开始" % [settings_path, FileAccess.get_open_error()])
		return
	var text := file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return
	var decoded := _decode(text)
	if decoded.is_empty() and text.strip_edges() != "{}":
		push_warning("Settings: %s 内容损坏,从空配置开始(不删除原文件)" % settings_path)
	_data = decoded


func _save_to_disk() -> void:
	var file := FileAccess.open(settings_path, FileAccess.WRITE)
	if file == null:
		CoreKit.log.error("Settings: 无法写入 %s(错误码 %d),本次变更只在内存生效" % [settings_path, FileAccess.get_open_error()])
		return
	file.store_string(_encode(_data))
	file.close()
