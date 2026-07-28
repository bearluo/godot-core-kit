extends Node
## SaveManager —— godot-core-kit 全局存档单例。
##
## 作为 CoreKit.saves 门面子节点。把任意 Dictionary 状态以具名"存档位"(slot)
## 形式经可插拔 SaveSerializer(默认 JsonSaveSerializer,.json)序列化、
## 原子写(temp+rename)落盘到 user://saves/<slot>.<ext>,{_version, data} 信封包裹。
## 桌面与 Web 导出行为一致(user:// 在 HTML5 由 IndexedDB 支持,FileAccess/
## DirAccess/JSON 全平台同步 API,无需 await)。纯 GDScript、无第三方依赖;
## 除 CoreKit.log(版本迁移/不匹配告警)外不依赖其它子系统。
##
## 用法:CoreKit.saves.save("hero1", {"hp": 100})
##       var data := CoreKit.saves.load("hero1")
##
## 版本迁移:游戏改版会重构存档结构,老档不能直接读。信封的 _version 记录写档时的
## 数据版本;set_data_version(v) 声明当前版本,register_migration(from, fn) 注册
## v(n)→v(n+1) 的迁移函数。load() 时若存档版本低于当前,按序跑迁移链逐级升级;缺迁移
## 函数 / 迁移函数返回非字典 / 存档版本高于当前(未来版本)→ load_failed + migration_failed,
## 返回 {}(由调用方保底新档,不静默覆盖旧文件)。默认 data_version=1 且无迁移注册时,
## 行为与旧版逐字节一致(向后兼容)。
##
## v1 范围之外(YAGNI):无自动收集存档的 registry、无加密、无自动存档调度、
## 无存档位元数据(缩略图/时长)。
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
## 加载时存档版本低于当前、迁移链成功升级后广播(slot, 存档原版本, 当前版本)。
signal migrated(slot: String, from_version: int, to_version: int)
## 迁移失败(缺迁移函数 / 迁移函数返回非字典 / 未来版本)广播;load 同时返回 {} 并 emit load_failed。
signal migration_failed(slot: String, reason: String)

const SAVE_DIR := "user://saves"
## 默认数据版本(向后兼容基线)。未调 set_data_version 的游戏,存档恒盖此版本。
const SCHEMA_VERSION := 1

## 当前序列化策略(默认 JSON,逐字节兼容旧 .json 存档)。经 set_serializer 替换。
var _serializer: SaveSerializer = JsonSaveSerializer.new()
## 当前数据版本(save 盖此版本;load 时低于它的存档走迁移链)。默认 = SCHEMA_VERSION。
var _data_version: int = SCHEMA_VERSION
## from_version(int) -> Callable(data: Dictionary) -> Dictionary 迁移函数注册表。
var _migrations: Dictionary = {}


## 替换序列化策略。null 忽略并 push_error;换后影响后续 save/load(不改动已落盘文件)。
func set_serializer(s: SaveSerializer) -> void:
	if s == null:
		push_error("SaveManager.set_serializer: 拒绝 null")
		return
	_serializer = s


## 声明当前数据版本(save 时盖此版本;load 时低于它的存档会被迁移到此版本)。
## 须 ≥ 1;非法值忽略并 push_error。默认 1(向后兼容)。
func set_data_version(v: int) -> void:
	if v < 1:
		push_error("SaveManager.set_data_version: 版本须 ≥ 1,忽略 %d" % v)
		return
	_data_version = v


## 当前数据版本。
func data_version() -> int:
	return _data_version


## 注册一步迁移:把 from_version 的 data 升级为 from_version+1 的 data 并返回。
## from_version 须 ≥ 1;重复注册覆盖。迁移函数签名 func(data: Dictionary) -> Dictionary。
func register_migration(from_version: int, migrator: Callable) -> void:
	if from_version < 1:
		push_error("SaveManager.register_migration: from_version 须 ≥ 1,忽略 %d" % from_version)
		return
	_migrations[from_version] = migrator


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

	var envelope := {"_version": _data_version, "data": data}
	var bytes := _serializer.encode(envelope)
	if bytes.is_empty():
		save_failed.emit(slot, "encode_error")
		return false

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var target := _slot_path(safe_slot)
	# web 上不走 temp+rename:微信小游戏的 user:// 是 weapp-adapter FS shim,
	# rename_absolute 会返回 OK 且目标文件存在,但内容为空(实测,见 v0.24.3)。
	# 直写在同一 FS 上验过是好的,且 web 无多进程并发写,原子替换本就没有对手。
	var use_tmp := not OS.has_feature("web")
	var write_path := target + ".tmp" if use_tmp else target

	var file := FileAccess.open(write_path, FileAccess.WRITE)
	if file == null:
		save_failed.emit(slot, "open_error:%d" % FileAccess.get_open_error())
		return false
	file.store_buffer(bytes)
	file.close()

	if use_tmp and not _atomic_replace(write_path, target):
		DirAccess.remove_absolute(write_path)
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

	var stored_version := int(envelope["_version"])
	var payload: Dictionary = envelope["data"]
	if stored_version != _data_version:
		var res := _run_migrations(safe_slot, stored_version, payload)
		if not res["ok"]:
			migration_failed.emit(safe_slot, res["reason"])
			load_failed.emit(safe_slot, res["reason"])
			return {}
		payload = res["data"]

	loaded.emit(safe_slot)
	return payload


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


## 把 payload 从 stored_version 迁移到 _data_version。返回 {ok, data, reason}。
## stored > current → 未来版本(不降级)future_version;缺迁移函数 → migration_missing:N;
## 迁移函数返回非字典 → migration_error:N。成功 emit migrated(slot, from, to)。
## 迁移函数就地/返回改数据均可(Dictionary 引用语义);失败时不保证 payload 未被前几步改动
## ——调用方失败即弃档(保底新档),故不影响正确性。
func _run_migrations(slot: String, stored_version: int, payload: Dictionary) -> Dictionary:
	if stored_version > _data_version:
		CoreKit.log.warn("SaveManager: slot '%s' 版本 %d 高于当前 %d(未来版本),拒绝加载" % [slot, stored_version, _data_version])
		return {"ok": false, "data": payload, "reason": "future_version"}
	var cur = payload
	var v := stored_version
	while v < _data_version:
		if not _migrations.has(v):
			CoreKit.log.warn("SaveManager: slot '%s' 缺 v%d→v%d 迁移函数,拒绝加载" % [slot, v, v + 1])
			return {"ok": false, "data": payload, "reason": "migration_missing:%d" % v}
		var out = _migrations[v].call(cur)
		if not (out is Dictionary):
			CoreKit.log.warn("SaveManager: slot '%s' v%d→v%d 迁移返回非字典,拒绝加载" % [slot, v, v + 1])
			return {"ok": false, "data": payload, "reason": "migration_error:%d" % v}
		cur = out
		v += 1
	migrated.emit(slot, stored_version, _data_version)
	return {"ok": true, "data": cur, "reason": ""}


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
