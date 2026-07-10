extends Node
## SaveManager —— godot-core-kit 全局存档单例。
##
## 以 autoload "SaveManager" 注册。把任意 Dictionary 状态以具名"存档位"(slot)
## 形式经可插拔 SaveSerializer(默认 JsonSaveSerializer,.json)序列化、
## 原子写(temp+rename)落盘到 user://saves/<slot>.<ext>,{_version, data} 信封包裹。
## 桌面与 Web 导出行为一致(user:// 在 HTML5 由 IndexedDB 支持,FileAccess/
## DirAccess/JSON 全平台同步 API,无需 await)。纯 GDScript、无第三方依赖;
## 除 CoreKit.log(仅用于版本不匹配警告)外不依赖其它子系统。
##
## 用法:CoreKit.saves.save("hero1", {"hp": 100})
##       var data := CoreKit.saves.load("hero1")
##
## v1 范围之外(YAGNI):无自动收集存档的 registry、无加密、无迁移引擎
## (仅保留版本号字段)、无自动存档调度、无存档位元数据(缩略图/时长)。
##
## 资源引用安全约定:落盘数据只存 resource_path 引用而非整个 Resource,
## 避开 load 时 ResourceLoader 重建任意资源带来的代码注入面。
##
## 命名坑:load() 在本脚本体内会遮蔽 GDScript 内置全局函数 load(path)
## (与 Log 遮蔽全局 log() 同理);本脚本内部从不需要调用全局 load(),
## 外部通过 SaveManager.load(...) 调用不受影响。

signal saved(slot: String)
signal save_failed(slot: String, reason: String)
signal loaded(slot: String)
signal load_failed(slot: String, reason: String)
signal slot_deleted(slot: String)

const SAVE_DIR := "user://saves"
const SCHEMA_VERSION := 1

## 当前序列化策略(默认 JSON,逐字节兼容旧 .json 存档)。经 set_serializer 替换。
var _serializer: SaveSerializer = JsonSaveSerializer.new()


## 替换序列化策略。null 忽略并 push_error;换后影响后续 save/load(不改动已落盘文件)。
func set_serializer(s: SaveSerializer) -> void:
	if s == null:
		push_error("SaveManager.set_serializer: 拒绝 null")
		return
	_serializer = s


## 把 data 写入 slot,若该存档位已存在则覆盖。
## 成功返回 true;失败返回 false 并 emit save_failed(slot, reason)。
func save(slot: String, data: Dictionary) -> bool:
	var safe_slot := _sanitize_slot_name(slot)
	if safe_slot.is_empty():
		save_failed.emit(slot, "invalid_slot_name")
		return false

	if _has_unserializable(data):
		save_failed.emit(slot, "unserializable")
		return false

	var envelope := {"_version": SCHEMA_VERSION, "data": data}
	var bytes := _serializer.encode(envelope)
	if bytes.is_empty():
		save_failed.emit(slot, "encode_error")
		return false

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var target := _slot_path(safe_slot)
	var tmp := target + ".tmp"

	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		save_failed.emit(slot, "open_error:%d" % FileAccess.get_open_error())
		return false
	file.store_buffer(bytes)
	file.close()

	if not _atomic_replace(tmp, target):
		DirAccess.remove_absolute(tmp)
		save_failed.emit(slot, "rename_error")
		return false

	saved.emit(safe_slot)
	return true


## 把 slot 读回一个 Dictionary。任何错误(文件不存在、字节损坏/信封非法)都返回 {}
## 并 emit load_failed;存档位本身合法地存了 {} 时同样返回 {},但 emit 的是 loaded。
func load(slot: String) -> Dictionary:
	var safe_slot := _sanitize_slot_name(slot)
	if safe_slot.is_empty():
		load_failed.emit(slot, "invalid_slot_name")
		return {}

	var path := _slot_path(safe_slot)
	if not FileAccess.file_exists(path):
		load_failed.emit(safe_slot, "not_found")
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		load_failed.emit(safe_slot, "open_error:%d" % FileAccess.get_open_error())
		return {}
	var bytes := file.get_buffer(file.get_length())
	file.close()

	var envelope := _serializer.decode(bytes)
	if envelope.is_empty() or not _is_valid_envelope(envelope):
		load_failed.emit(safe_slot, "corrupt")
		return {}

	if int(envelope["_version"]) != SCHEMA_VERSION:
		CoreKit.log.warn("SaveManager: slot '%s' 版本 %s 与当前 SCHEMA_VERSION %d 不一致,v1 无迁移逻辑,按原样加载" % [safe_slot, str(envelope["_version"]), SCHEMA_VERSION])

	loaded.emit(safe_slot)
	return envelope["data"]


## 存档位对应的文件是否存在。
func has_slot(slot: String) -> bool:
	var safe_slot := _sanitize_slot_name(slot)
	if safe_slot.is_empty():
		return false
	return FileAccess.file_exists(_slot_path(safe_slot))


## 删除存档位对应文件。成功返回 true 并 emit slot_deleted;不存在或删除
## 失败返回 false。无专属失败信号——返回值已足够表达失败。
func delete_slot(slot: String) -> bool:
	var safe_slot := _sanitize_slot_name(slot)
	if safe_slot.is_empty():
		return false
	var path := _slot_path(safe_slot)
	if not FileAccess.file_exists(path):
		return false
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return false
	slot_deleted.emit(safe_slot)
	return true


## 列出所有存档位名称(不含扩展名),升序排列,仅名称、无元数据。
## 存档目录尚不存在时返回 []。
func list_slots() -> Array[String]:
	var result: Array[String] = []
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return result
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension() == _serializer.extension():
			result.append(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


## --- 可测接缝(纯函数,不碰磁盘/autoload) ---

## 原子替换:优先 rename(桌面平台原子覆盖已存在目标);个别平台 rename 不覆盖时,
## 回退"先删目标再 rename"。整个过程 tmp 始终是完整文件,消除目标被写一半的窗口。
func _atomic_replace(tmp: String, target: String) -> bool:
	if DirAccess.rename_absolute(tmp, target) == OK:
		return true
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
		return DirAccess.rename_absolute(tmp, target) == OK
	return false

## 白名单方式清洗存档位名称:删除所有不在 [A-Za-z0-9_-] 内的字符;
## 若清洗后为空(原始输入为空/纯空白/全部字符都不合法),返回 ""(拒绝,
## 不回退到某个默认存档位)。
func _sanitize_slot_name(slot: String) -> String:
	var re := RegEx.new()
	re.compile("[^A-Za-z0-9_-]+")
	return re.sub(slot, "", true)


## 纯路径拼接;不做清洗——调用方需先自行清洗。扩展名由当前序列化器决定。
func _slot_path(slot: String) -> String:
	return "%s/%s.%s" % [SAVE_DIR, slot, _serializer.extension()]


## 信封结构校验(承接旧 _decode 的 has/类型检查):有 _version/data 键、_version 为标量、
## data 是 Dictionary。非标量 _version 会让 load() 里的 int(...) 抛错,故当作损坏。
func _is_valid_envelope(env: Dictionary) -> bool:
	if not env.has("_version") or not env.has("data"):
		return false
	if typeof(env["_version"]) not in [TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
		return false
	return typeof(env["data"]) == TYPE_DICTIONARY

## data 中是否存在不可持久化的值(递归 Dictionary 值 + Array 元素)。挡"永不该落盘"的
## 句柄/对象类型(Object/Resource/Node/Callable/Signal/RID);不拒 Vector2/Color 等值类型
## (那是 JSON 格式局限而非注入面,二进制 serializer 可原生存)。
func _has_unserializable(v: Variant) -> bool:
	match typeof(v):
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return true
		TYPE_DICTIONARY:
			for k in v:
				if _has_unserializable(v[k]):
					return true
			return false
		TYPE_ARRAY:
			for e in v:
				if _has_unserializable(e):
					return true
			return false
		_:
			return false
