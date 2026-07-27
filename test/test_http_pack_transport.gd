extends SceneTree
## HttpPackTransport 的可测部分(kit 门)。真实 HTTP 收发无法在无网络的门里测,故只覆盖
## 「把下载到内存的字节可靠落盘」这一 Web 修复要害(_store_body_to_file)——正是
## HTTPRequest.download_file 在 Web 上失守的那一步(request 报成功,字节却没落进 user://)。
## 运行:godot --headless --path . -s res://test/test_http_pack_transport.gd

const BASE := "user://test_http_pack_transport"

var _TransportScript


func _initialize() -> void:
	var failures := 0
	_TransportScript = load("res://addons/godot-core-kit/systems/http_pack_transport.gd")

	failures += _test_store_body_roundtrip()
	failures += _test_store_body_creates_parent_dir()
	failures += _test_store_body_empty()

	_rm_rf(BASE)
	if failures == 0:
		print("test_http_pack_transport: ALL PASS")
		quit(0)
	else:
		print("test_http_pack_transport: %d FAILURE(S)" % failures)
		quit(1)


## 1) 写入后能逐字节读回——含 0x00/0xFF 等任意二进制(pck 是二进制)。这是下载落盘的
##    核心保证,也正是 download_file 在 Web 上失守的地方(字节没真正落进 user://)。
func _test_store_body_roundtrip() -> int:
	var failures := 0
	_rm_rf(BASE)
	var t = _TransportScript.new()
	var bytes := PackedByteArray([0x47, 0x44, 0x50, 0x43, 0x00, 0x01, 0x02, 0xFF, 0xFE, 0x0A, 0x7A])
	var dest := BASE + "/packs/content-v1.pck"
	var ok: bool = t._store_body_to_file(bytes, dest)
	if not ok:
		print("FAIL 1a: _store_body_to_file 应返回 true"); failures += 1
	if not FileAccess.file_exists(dest):
		print("FAIL 1b: 目标文件应存在"); failures += 1
	elif FileAccess.get_file_as_bytes(dest) != bytes:
		print("FAIL 1c: 落盘字节应与输入逐字节一致(含 0x00/0xFF)"); failures += 1
	t.free()
	return failures


## 2) 父目录不存在时应自动建(下载暂存路径通常在尚未创建的 staging 子目录里)。
func _test_store_body_creates_parent_dir() -> int:
	var failures := 0
	_rm_rf(BASE)
	var t = _TransportScript.new()
	var dest := BASE + "/staging/deep/nested/x.pck"
	var ok: bool = t._store_body_to_file(PackedByteArray([1, 2, 3]), dest)
	if not ok or not FileAccess.file_exists(dest):
		print("FAIL 2: 应自动建父目录并写入,ok=%s exists=%s" % [ok, FileAccess.file_exists(dest)]); failures += 1
	t.free()
	return failures


## 3) 空 body 也应写出一个 0 字节文件(而非失败/不写)。
func _test_store_body_empty() -> int:
	var failures := 0
	_rm_rf(BASE)
	var t = _TransportScript.new()
	var dest := BASE + "/empty.pck"
	var ok: bool = t._store_body_to_file(PackedByteArray(), dest)
	if not ok or not FileAccess.file_exists(dest):
		print("FAIL 3a: 空 body 也应成功写出文件"); failures += 1
	elif FileAccess.get_file_as_bytes(dest).size() != 0:
		print("FAIL 3b: 空 body 文件应为 0 字节"); failures += 1
	t.free()
	return failures


func _rm_rf(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var child := path + "/" + entry
		if dir.current_is_dir():
			_rm_rf(child)
		else:
			DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
