extends Node
## PackUpdater —— 内容包下载/校验/挂载子系统(CoreKit.updater)。
## 骨架:行为随 TDD 切片逐步长出。

const STATE_FILE := "state.json"
const HttpPackTransportScript := preload("res://addons/godot-core-kit/systems/http_pack_transport.gd")

## 相 B:运行期,异步。
signal update_available(plan: Dictionary)  ## 有更新;plan 可直接喂给 download()
signal up_to_date()                        ## 已是最新
signal check_failed(reason: String)
signal progress(pack_id: String, done_bytes: int, total_bytes: int)
signal downloaded(pack_id: String)
signal download_failed(pack_id: String, reason: String)
signal ready_to_apply()                    ## 全部包已校验落盘并写入暂存状态

var _base_dir := "user://kit_updater"
var _mounter = null
var _transport = null
var _mounted: Array[String] = []
var _mount_errors: Dictionary = {}


func set_base_dir(dir: String) -> void:
	_base_dir = dir


func set_mounter(m) -> void:
	_mounter = m


func set_transport(t) -> void:
	_transport = t


## 相 A:按记录的 order 依次挂载已安装的包。
## 若 state 声明的目标引擎与运行引擎不符,一个都不挂并全部记入 mount_errors
## (研究 §3:包头会拒收更新版引擎导出的包,须在挂载前自行拦下)。
func mount_installed() -> void:
	_mounted.clear()
	_mount_errors.clear()
	var state := _read_state()
	var installed: Array = state.get("installed", [])

	var declared := String(state.get("engine", ""))
	if not _engine_ok(declared):
		for entry in installed:
			_mount_errors[String(entry.get("id", ""))] = "engine_mismatch:%s" % declared
		return

	var ordered := installed.duplicate()
	ordered.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	for entry in ordered:
		var id := String(entry.get("id", ""))
		if _mount_one(String(entry.get("file", ""))):
			_mounted.append(id)
		else:
			_mount_errors[id] = "mount_failed"


## 挂一个包。未注入 _mounter 时走真 ProjectSettings.load_resource_pack。
func _mount_one(path: String) -> bool:
	if _mounter != null:
		return _mounter.mount(path)
	return ProjectSettings.load_resource_pack(path)


## 本次启动成功挂载的 pack id,按挂载序。
func mounted_packs() -> Array[String]:
	return _mounted.duplicate()


## 启动期挂载失败记录:pack_id -> reason。
func mount_errors() -> Dictionary:
	return _mount_errors.duplicate()


## 相 B:拉取 manifest,与本地已安装版本比对,算出更新计划。
## 结果经信号广播:update_available(plan) / up_to_date / check_failed(reason)。
## 失败(传输/畸形/引擎不符)一律不改动本地状态。
func check(manifest_url: String) -> void:
	_ensure_transport()
	_transport.fetch_text(manifest_url, func(ok: bool, text: String):
		if not ok:
			check_failed.emit("transport")
			return
		var manifest = _parse_json(text)
		if not (manifest is Dictionary) or not manifest.has("packs"):
			check_failed.emit("malformed")
			return
		var declared := String(manifest.get("engine", ""))
		if not _engine_ok(declared):
			check_failed.emit("engine_mismatch:%s" % declared)
			return
		var plan := _plan(manifest)
		if plan["packs"].is_empty():
			up_to_date.emit()
		else:
			update_available.emit(plan)
	)


## 相 B:按 plan 串行下载各包到暂存区,逐包 sha256 校验。全部通过后**原子**
## 改写 state.json(合并进已安装集合)并发 ready_to_apply;任何一包失败即
## 丢弃暂存、state.json 逐字节不变、发 download_failed(不留半更新状态)。
func download(plan: Dictionary) -> void:
	_ensure_transport()
	var packs: Array = plan.get("packs", [])
	_download_next(packs, 0, [])


## 未注入传输时惰性兜底为生产 HttpPackTransport(挂为子节点,联网所需)。
func _ensure_transport() -> void:
	if _transport == null:
		var t = HttpPackTransportScript.new()
		t.name = "HttpPackTransport"
		add_child(t)
		_transport = t


func _download_next(packs: Array, i: int, staged: Array) -> void:
	if i >= packs.size():
		_commit_staged(staged)
		ready_to_apply.emit()
		return
	var pack: Dictionary = packs[i]
	var id := String(pack.get("id", ""))
	var url := String(pack.get("url", ""))
	var tmp := "%s/staging/%s-v%d.pck" % [_base_dir, id, int(pack.get("version", 0))]
	_transport.fetch_file(url, tmp, func(ok: bool, reason: String):
		if not ok:
			_discard_staging()
			download_failed.emit(id, reason)
			return
		var want := String(pack.get("sha256", ""))
		if not want.is_empty() and _file_sha256(tmp) != want:
			_discard_staging()
			download_failed.emit(id, "checksum")
			return
		var final_path := "%s/packs/%s-v%d.pck" % [_base_dir, id, int(pack.get("version", 0))]
		progress.emit(id, int(pack.get("size", 0)), int(pack.get("size", 0)))
		downloaded.emit(id)
		var next := staged.duplicate()
		next.append({
			"id": id, "version": int(pack.get("version", 0)),
			"tmp": tmp, "file": final_path,
			"sha256": want, "order": int(pack.get("order", 0)),
		})
		_download_next(packs, i + 1, next)
	)


## 把全部暂存包原子并入已安装集合:先各自 rename 到最终路径,再原子改写 state.json。
func _commit_staged(staged: Array) -> void:
	DirAccess.make_dir_recursive_absolute(_base_dir + "/packs")
	var state := _read_state()
	if state.is_empty():
		state = {"engine": _running_engine(), "installed": []}
	var installed: Array = state.get("installed", [])
	for s in staged:
		_replace_file(s["tmp"], s["file"])
		# 同 id 覆盖旧条目
		installed = installed.filter(func(e): return String(e.get("id", "")) != s["id"])
		installed.append({
			"id": s["id"], "version": s["version"], "file": s["file"],
			"sha256": s["sha256"], "order": s["order"],
		})
	state["installed"] = installed
	_write_state_atomic(state)


func _discard_staging() -> void:
	_rm_rf(_base_dir + "/staging")


## 已安装版本;未安装返回 0。
func local_version(pack_id: String) -> int:
	for entry in _read_state().get("installed", []):
		if String(entry.get("id", "")) == pack_id:
			return int(entry.get("version", 0))
	return 0


## 重启屏障:含 GDScript 逻辑的包只能靠重启换逻辑(研究 §4b)。桌面/移动端
## 用 OS.set_restart_on_exit + 退出主循环触发自重启;Web 与 headless 无法
## 自重启,返回 false 交由接入方降级(提示玩家手动重开)。
## ⚠️ Android 真机自重启能力未验证(设计 §11),接口契约先立。
func restart_to_apply() -> bool:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return false
	var tree := get_tree()
	if tree == null:
		return false
	OS.set_restart_on_exit(true)
	tree.quit()
	return true


## --- 内部纯函数(不直接测,经公开接口覆盖) ---

## 运行引擎的 "major.minor" 字符串。
func _running_engine() -> String:
	var info := Engine.get_version_info()
	return "%d.%d" % [info.major, info.minor]


## state 声明的引擎是否与运行引擎相符。空声明视为放行(向后兼容)。
func _engine_ok(declared: String) -> bool:
	return declared.is_empty() or declared == _running_engine()


## 从 manifest 算出要下载的包:版本高于本地已安装的才进 plan。
## 返回 {engine, packs:[manifest 里的 pack 条目原样]}。
func _plan(manifest: Dictionary) -> Dictionary:
	var out: Array = []
	for pack in manifest.get("packs", []):
		if int(pack.get("version", 0)) > local_version(String(pack.get("id", ""))):
			out.append(pack)
	return {"engine": String(manifest.get("engine", "")), "packs": out}


func _read_state() -> Dictionary:
	var path := _base_dir + "/" + STATE_FILE
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = _parse_json(txt)
	return parsed if parsed is Dictionary else {}


## 原子写 state.json:temp + rename(照 SaveManager 先例),消除写一半的窗口。
## web 上直写目标——微信小游戏 FS shim 的 rename 会丢内容,理由同 SaveManager.save。
func _write_state_atomic(state: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(_base_dir)
	var target := _base_dir + "/" + STATE_FILE
	var use_tmp := not OS.has_feature("web")
	var write_path := target + ".tmp" if use_tmp else target
	var f := FileAccess.open(write_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(state))
	f.close()
	if not use_tmp:
		return
	if DirAccess.rename_absolute(write_path, target) != OK:
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)
			DirAccess.rename_absolute(write_path, target)


## 把暂存文件搬到最终路径。web 上 rename 会报成功但丢内容(微信小游戏 FS shim
## 实测),故整读整写复制后删源;暂存语义不变(下载全部完成才提交)。
## ponytail: web 分支整包进内存,包大到吃紧时再换分块流式复制。
func _replace_file(tmp: String, target: String) -> void:
	if not OS.has_feature("web"):
		DirAccess.rename_absolute(tmp, target)
		return
	var bytes := FileAccess.get_file_as_bytes(tmp)
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()
	DirAccess.remove_absolute(tmp)


## 文件内容的 sha256 hex。用流式 HashingContext,大包不必整读进内存。
func _file_sha256(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while not f.eof_reached():
		ctx.update(f.get_buffer(1 << 16))
	f.close()
	return ctx.finish().hex_encode()


## 递归删目录(暂存区清理)。
func _rm_rf(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var child := path + "/" + name
		if dir.current_is_dir():
			_rm_rf(child)
		else:
			DirAccess.remove_absolute(child)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


## 实例式 JSON 解析:失败返回 null 且不打引擎级 ERROR 日志(区别于静态
## JSON.parse_string,后者对畸形输入会 push_error 刷屏)。畸形 manifest 是
## 正常失败路径,不该污染日志。
func _parse_json(text: String) -> Variant:
	var j := JSON.new()
	if j.parse(text) != OK:
		return null
	return j.data
