extends Node
## SaveManager —— godot-core-kit 全局存档单例。
##
## 以 autoload "SaveManager" 注册。把任意 Dictionary 状态以具名"存档位"(slot)
## 形式落盘到 user://saves/<slot>.json,JSON 格式、{_version, data} 信封包裹。
## 桌面与 Web 导出行为一致(user:// 在 HTML5 由 IndexedDB 支持,FileAccess/
## DirAccess/JSON 全平台同步 API,无需 await)。纯 GDScript、无第三方依赖;
## 除 CoreKit.log(仅用于版本不匹配警告)外不依赖其它子系统。
##
## 用法:CoreKit.saves.save("hero1", {"hp": 100})
##       var data := CoreKit.saves.load("hero1")
##
## v1 范围之外(YAGNI):无自动收集存档的 registry、无加密、无迁移引擎
## (仅保留版本号字段)、无自动存档调度、无存档位元数据(缩略图/时长)、
## 无原子写(temp+rename)。
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


## 把 data 写入 slot,若该存档位已存在则覆盖。
## 成功返回 true;失败返回 false 并 emit save_failed(slot, reason)。
func save(slot: String, data: Dictionary) -> bool:
	var safe_slot := _sanitize_slot_name(slot)
	if safe_slot.is_empty():
		save_failed.emit(slot, "invalid_slot_name")
		return false

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var file := FileAccess.open(_slot_path(safe_slot), FileAccess.WRITE)
	if file == null:
		save_failed.emit(slot, "open_error:%d" % FileAccess.get_open_error())
		return false

	file.store_string(_encode(data))
	file.close()

	saved.emit(safe_slot)
	return true


## 把 slot 读回一个 Dictionary。任何错误(文件不存在、JSON 损坏/非法)都
## 返回 {} 并 emit load_failed;存档位本身合法地存了 {} 时同样返回 {},
## 但 emit 的是 loaded —— 见 _decode 的信封,可用于区分"空"与"损坏"。
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
	var text := file.get_as_text()
	file.close()

	var envelope := _decode(text)
	if envelope.is_empty():
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
		if not dir.current_is_dir() and file_name.get_extension() == "json":
			result.append(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


## --- 可测接缝(纯函数,不碰磁盘/autoload) ---

## 白名单方式清洗存档位名称:删除所有不在 [A-Za-z0-9_-] 内的字符;
## 若清洗后为空(原始输入为空/纯空白/全部字符都不合法),返回 ""(拒绝,
## 不回退到某个默认存档位)。
func _sanitize_slot_name(slot: String) -> String:
	var re := RegEx.new()
	re.compile("[^A-Za-z0-9_-]+")
	return re.sub(slot, "", true)


## 纯路径拼接;不做清洗——调用方需先自行清洗。
func _slot_path(slot: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, slot]


## Dictionary -> JSON 字符串,包裹为 {_version, data} 信封,缩进美化输出。
func _encode(data: Dictionary) -> String:
	var envelope := {"_version": SCHEMA_VERSION, "data": data}
	return JSON.stringify(envelope, "\t")


## JSON 字符串 -> 信封 Dictionary({_version:int, data:Dictionary});
## 任何失败(JSON 非法、根不是 Dictionary、信封键缺失、data 类型不对)
## 都返回 {}。
func _decode(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var envelope: Dictionary = parsed
	if not envelope.has("_version") or not envelope.has("data"):
		return {}
	# _version 必须是标量:非标量(如 {}/[])会让 load() 里的 int(...) 抛错,
	# 破坏 "任何错误都返回 {}" 的契约,故在此当作损坏处理。
	if typeof(envelope["_version"]) not in [TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
		return {}
	if typeof(envelope["data"]) != TYPE_DICTIONARY:
		return {}
	return envelope
