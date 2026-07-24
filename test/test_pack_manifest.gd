extends SceneTree
## KitPackManifest —— 导出管线 manifest 生成器的断言测试。
## 运行时 load(不顶层 preload):KitPackManifest 虽是 class_name,但握手测试要 load
## PackUpdater,后者路径引用同仓库脚本,统一走运行时 load 稳妥。

var failures := 0


func _initialize() -> void:
	var K = load("res://addons/godot-core-kit/tools/pack_manifest.gd")
	if K == null:
		printerr("test_pack_manifest: cannot load KitPackManifest — hard fail")
		quit(1)
		return
	_test_build_shape(K)
	_test_sha256_known_literal(K)
	_test_size(K)
	_test_sorted_by_order(K)
	_test_engine_stamp(K)
	_test_validate(K)
	_test_write_manifest(K)
	_test_handshake_with_updater(K)

	if failures == 0:
		print("test_pack_manifest: ALL PASS")
		quit(0)
	else:
		printerr("test_pack_manifest: %d FAILURE(S)" % failures)
		quit(1)


# --- 断言脚手架 ---
func _fail(msg: String) -> void:
	failures += 1
	print("FAIL: " + msg)


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _write_file(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	f.close()


func _rmrf(path: String) -> void:
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
			_rmrf(child)
		else:
			DirAccess.remove_absolute(child)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


# --- 1. 输出形状与字段透传 ---
func _test_build_shape(K) -> void:
	var m = K.new()
	var p := "user://tpm_a.pck"
	_write_file(p, "abc")
	var manifest = m.build([
		{"id": "content", "version": 3, "url": "https://cdn/content-v3.pck", "order": 0, "file": p},
	])
	_ok(manifest is Dictionary, "manifest is Dictionary")
	_ok(manifest.has("engine"), "manifest has engine")
	_ok(manifest.has("packs"), "manifest has packs")
	var packs: Array = manifest.get("packs", [])
	_ok(packs.size() == 1, "one pack out")
	if packs.size() == 1:
		var e: Dictionary = packs[0]
		_ok(String(e.get("id")) == "content", "id passthrough")
		_ok(int(e.get("version")) == 3, "version passthrough")
		_ok(String(e.get("url")) == "https://cdn/content-v3.pck", "url passthrough")
		_ok(int(e.get("order")) == 0, "order passthrough")
		_ok(not e.has("file"), "file dropped from output")


# --- 2. sha256 = 已知字面量(独立真值,非自算,防同义反复)---
func _test_sha256_known_literal(K) -> void:
	var m = K.new()
	var p := "user://tpm_abc.pck"
	_write_file(p, "abc")  # SHA-256("abc") 为 NIST 标准测试向量
	var manifest = m.build([{"id": "c", "version": 1, "url": "u", "order": 0, "file": p}])
	var sha := String(manifest["packs"][0].get("sha256"))
	_ok(sha == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
		"sha256(abc) matches known NIST vector, got=%s" % sha)


# --- 3. size = 真实字节数 ---
func _test_size(K) -> void:
	var m = K.new()
	var p := "user://tpm_size.pck"
	_write_file(p, "abc")  # 3 字节
	var manifest = m.build([{"id": "c", "version": 1, "url": "u", "order": 0, "file": p}])
	_ok(int(manifest["packs"][0].get("size")) == 3, "size = 3 bytes")


# --- 4. 按 order 升序排列 ---
func _test_sorted_by_order(K) -> void:
	var m = K.new()
	var a := "user://tpm_o1.pck"; _write_file(a, "a")
	var b := "user://tpm_o2.pck"; _write_file(b, "b")
	var manifest = m.build([
		{"id": "z", "version": 1, "url": "uz", "order": 5, "file": a},
		{"id": "y", "version": 1, "url": "uy", "order": 2, "file": b},
	])
	var packs: Array = manifest["packs"]
	_ok(int(packs[0].get("order")) == 2, "sorted first order=2")
	_ok(String(packs[0].get("id")) == "y", "sorted first id=y")
	_ok(int(packs[1].get("order")) == 5, "sorted second order=5")


# --- 5. 引擎版本:默认戳运行引擎,可显式覆盖 ---
func _test_engine_stamp(K) -> void:
	var m = K.new()
	var p := "user://tpm_e.pck"; _write_file(p, "x")
	var info := Engine.get_version_info()
	var running := "%d.%d" % [info.major, info.minor]
	var manifest = m.build([{"id": "c", "version": 1, "url": "u", "order": 0, "file": p}])
	_ok(String(manifest.get("engine")) == running, "engine defaults to running %s" % running)
	var manifest2 = m.build([{"id": "c", "version": 1, "url": "u", "order": 0, "file": p}], "4.7")
	_ok(String(manifest2.get("engine")) == "4.7", "engine override honored")


# --- 6. validate:缺失/不可读 .pck 被拦下,干净 manifest 放行 ---
func _test_validate(K) -> void:
	var m = K.new()
	var bad = m.build([{"id": "ghost", "version": 1, "url": "u", "order": 0, "file": "user://tpm_missing.pck"}])
	_ok("ghost" in m.validate(bad), "validate flags un-hashable pack")
	var p := "user://tpm_good.pck"; _write_file(p, "ok")
	var good = m.build([{"id": "g", "version": 1, "url": "u", "order": 0, "file": p}])
	_ok(m.validate(good).is_empty(), "validate passes clean manifest")


# --- 7. write_manifest 原子落盘且可回读 ---
func _test_write_manifest(K) -> void:
	var m = K.new()
	var p := "user://tpm_w.pck"; _write_file(p, "abc")
	var manifest = m.build([{"id": "c", "version": 2, "url": "u", "order": 0, "file": p}])
	var out := "user://tpm_out/manifest.json"
	var err = m.write_manifest(manifest, out)
	_ok(err == OK, "write_manifest returns OK")
	_ok(FileAccess.file_exists(out), "manifest file written")
	var j := JSON.new()
	j.parse(FileAccess.get_file_as_string(out))
	_ok(j.data is Dictionary and j.data.get("packs", []).size() == 1, "manifest round-trips via JSON")


# --- 8. 握手:生成器产出 → 喂 PackUpdater check/download → 格式与 sha256 咬合 ---
func _test_handshake_with_updater(K) -> void:
	var m = K.new()
	var src := "user://tpm_hs_src.pck"
	_write_file(src, "HANDSHAKE-PACK-BYTES")  # download() 只校验 sha256,不挂载,任意字节可
	var info := Engine.get_version_info()
	var running := "%d.%d" % [info.major, info.minor]
	var manifest = m.build([
		{"id": "content", "version": 2, "url": "http://fake/content-v2.pck", "order": 0, "file": src},
	], running)

	var PackUpdater = load("res://addons/godot-core-kit/systems/pack_updater.gd")
	var u = PackUpdater.new()
	var base := "user://tpm_hs_base"
	_rmrf(base)  # user:// 跨运行持久:清掉旧 state 才不会被判 up_to_date
	u.set_base_dir(base)
	var ft = FakeTransport.new()
	ft.manifest_text = JSON.stringify(manifest)
	ft.file_src = src
	u.set_transport(ft)

	var rec := {"plan": null, "ready": false, "failed": ""}
	u.update_available.connect(func(plan): rec["plan"] = plan)
	u.ready_to_apply.connect(func(): rec["ready"] = true)
	u.download_failed.connect(func(id, reason): rec["failed"] = "%s:%s" % [id, reason])

	u.check("http://fake/manifest.json")
	_ok(rec["plan"] != null, "handshake: check() → update_available (shape+engine accepted)")
	if rec["plan"] != null:
		var plan: Dictionary = rec["plan"]
		_ok(plan["packs"].size() == 1, "handshake: plan has 1 pack")
		_ok(String(plan["packs"][0].get("id")) == "content", "handshake: plan pack id=content")
		u.download(plan)
		_ok(rec["ready"], "handshake: download → ready_to_apply (generator sha256 accepted by updater)")
		_ok(String(rec["failed"]) == "", "handshake: no download_failed, got=%s" % rec["failed"])
	u.free()


# 同步假传输:check 直接回 manifest 文本;fetch_file 把真源字节拷进 dest,
# 使 updater 算出的 sha256 == 生成器算出的 sha256(握手的关键)。
class FakeTransport:
	var manifest_text := ""
	var file_src := ""

	func fetch_text(_url: String, on_done: Callable) -> void:
		on_done.call(true, manifest_text)

	func fetch_file(_url: String, dest_path: String, on_done: Callable) -> void:
		DirAccess.make_dir_recursive_absolute(dest_path.get_base_dir())
		var data := FileAccess.get_file_as_bytes(file_src)
		var f := FileAccess.open(dest_path, FileAccess.WRITE)
		f.store_buffer(data)
		f.close()
		on_done.call(true, "")
