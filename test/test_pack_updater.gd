extends SceneTree
## PackUpdater(CoreKit.updater)测试(kit 门)。全部经公开接口 + 信号观察,
## 不直接测私有纯函数(_plan/_engine_ok/_mount_order)。依赖用 set_* 注入。
## 运行:godot --headless --path . -s res://test/test_pack_updater.gd

const BASE := "user://test_pack_updater"

var _UpdaterScript


## 记录调用的假挂载器。fail_on 命中的路径返回 false,模拟挂载失败。
class FakeMounter:
	var calls: Array[String] = []
	var fail_on: String = ""

	func mount(path: String) -> bool:
		calls.append(path)
		return path != fail_on


## 假传输。内存里预置 manifest 与各 url 的字节;fail=true 模拟网络失败。
## 接口(生产 HttpPackTransport 亦满足):
##   fetch_text(url, on_done: Callable(ok: bool, text: String))
##   fetch_file(url, dest_path, on_done: Callable(ok: bool, reason: String))
class FakeTransport:
	var manifest_text := ""
	var manifest_fail := false
	var files: Dictionary = {}          # url -> PackedByteArray
	var file_fail_on: String = ""       # 命中此 url 的 fetch_file 失败

	func fetch_text(_url: String, on_done: Callable) -> void:
		if manifest_fail:
			on_done.call(false, "")
		else:
			on_done.call(true, manifest_text)

	func fetch_file(url: String, dest_path: String, on_done: Callable) -> void:
		if url == file_fail_on or not files.has(url):
			on_done.call(false, "network")
			return
		DirAccess.make_dir_recursive_absolute(dest_path.get_base_dir())
		var f := FileAccess.open(dest_path, FileAccess.WRITE)
		f.store_buffer(files[url])
		f.close()
		on_done.call(true, "")


## 把每个信号的 payload 记进 events。signals_of 列出要连的信号名。
class SignalRec:
	var events: Array = []

	func bind_all(obj: Object, names: Array) -> void:
		for n in names:
			obj.connect(n, _make(n))

	func _make(n: String) -> Callable:
		return func(a = null, b = null, c = null):
			events.append([n, a, b, c])

	func names() -> Array:
		return events.map(func(e): return e[0])

	func first(n: String) -> Array:
		for e in events:
			if e[0] == n:
				return e
		return []


func _initialize() -> void:
	var failures := 0
	_UpdaterScript = load("res://addons/godot-core-kit/systems/pack_updater.gd")

	failures += _test_mount_order()
	failures += _test_mount_failure_isolated()
	failures += _test_local_version()
	failures += _test_engine_gate()
	failures += _test_check_up_to_date()
	failures += _test_check_update_available()
	failures += _test_check_engine_mismatch()
	failures += _test_check_transport_failure()
	failures += _test_check_malformed()
	failures += _test_download_success()
	failures += _test_download_checksum_atomic()
	failures += _test_download_interrupt_atomic()
	failures += _test_restart_contract()
	failures += _test_real_pack_integration()

	_rm_rf(BASE)
	if failures == 0:
		print("test_pack_updater: ALL PASS")
		quit(0)
	else:
		print("test_pack_updater: %d FAILURE(S)" % failures)
		quit(1)


## 1) 相 A:按记录的 order 挂载,而非照数组顺序(state 里刻意乱序)。
func _test_mount_order() -> int:
	var failures := 0
	_write_state({
		"engine": _engine_str(),
		"installed": [
			_entry("second", 1, 1),
			_entry("first", 2, 0),
		],
	})
	var fake := FakeMounter.new()
	var u = _new_updater(fake)
	u.mount_installed()

	var got := ",".join(u.mounted_packs())
	if got != "first,second":
		print("FAIL 1a: mounted_packs 应按 order 为 'first,second',实际 '%s'" % got); failures += 1
	var want := "%s/packs/first.pck,%s/packs/second.pck" % [BASE, BASE]
	if ",".join(fake.calls) != want:
		print("FAIL 1b: 挂载调用应为 '%s',实际 '%s'" % [want, ",".join(fake.calls)]); failures += 1
	u.free()
	return failures


## 2) 单个包挂载失败:记进 mount_errors(),其余包照常挂上(不中断、不崩)。
func _test_mount_failure_isolated() -> int:
	var failures := 0
	_write_state({
		"engine": _engine_str(),
		"installed": [_entry("a", 1, 0), _entry("bad", 1, 1), _entry("c", 1, 2)],
	})
	var fake := FakeMounter.new()
	fake.fail_on = BASE + "/packs/bad.pck"
	var u = _new_updater(fake)
	u.mount_installed()

	var got := ",".join(u.mounted_packs())
	if got != "a,c":
		print("FAIL 2a: 失败包应被跳过、其余照挂 'a,c',实际 '%s'" % got); failures += 1
	var errs: Dictionary = u.mount_errors()
	if not errs.has("bad"):
		print("FAIL 2b: mount_errors 应含 'bad',实际 %s" % errs); failures += 1
	if errs.size() != 1:
		print("FAIL 2c: mount_errors 应只有 1 条,实际 %s" % errs); failures += 1
	u.free()
	return failures


## 3) local_version:已安装返回其版本,未安装返回 0。
func _test_local_version() -> int:
	var failures := 0
	_write_state({
		"engine": _engine_str(),
		"installed": [_entry("content", 7, 0)],
	})
	var u = _new_updater(FakeMounter.new())
	if u.local_version("content") != 7:
		print("FAIL 3a: local_version('content') 应为 7,实际 %s" % u.local_version("content")); failures += 1
	if u.local_version("nope") != 0:
		print("FAIL 3b: 未安装应返回 0,实际 %s" % u.local_version("nope")); failures += 1
	u.free()
	return failures


## 4) 引擎版本闸门:state 声明的引擎与运行引擎不符 → 一个都不挂,全部记错。
##    (研究 §3:包头会拒收更新版引擎导出的包,须在挂载前自行拦下)
func _test_engine_gate() -> int:
	var failures := 0
	_write_state({
		"engine": "9.9",
		"installed": [_entry("first", 1, 0)],
	})
	var fake := FakeMounter.new()
	var u = _new_updater(fake)
	u.mount_installed()

	if u.mounted_packs().size() != 0:
		print("FAIL 4a: 引擎不匹配时不应挂载任何包,实际 %s" % [u.mounted_packs()]); failures += 1
	if fake.calls.size() != 0:
		print("FAIL 4b: 引擎不匹配时不应调用 mounter,实际 %s" % [fake.calls]); failures += 1
	var reason := String(u.mount_errors().get("first", ""))
	if not reason.begins_with("engine_mismatch"):
		print("FAIL 4c: 失败原因应以 engine_mismatch 开头,实际 '%s'" % reason); failures += 1
	u.free()
	return failures


const CHECK_SIGNALS := ["update_available", "up_to_date", "check_failed"]


## 5) check:本地已是 manifest 版本 → up_to_date,不 update_available。
func _test_check_up_to_date() -> int:
	var failures := 0
	_write_state({"engine": _engine_str(), "installed": [_entry("content", 3, 0)]})
	var tr := FakeTransport.new()
	tr.manifest_text = _manifest(3)
	var u = _new_updater(FakeMounter.new())
	u.set_transport(tr)
	var rec := SignalRec.new()
	rec.bind_all(u, CHECK_SIGNALS)

	u.check("http://x/manifest.json")
	if rec.names() != ["up_to_date"]:
		print("FAIL 5: 已最新应只发 up_to_date,实际 %s" % [rec.names()]); failures += 1
	u.free()
	return failures


## 6) check:manifest 版本高于本地 → update_available,plan 里含该包。
func _test_check_update_available() -> int:
	var failures := 0
	_write_state({"engine": _engine_str(), "installed": [_entry("content", 2, 0)]})
	var tr := FakeTransport.new()
	tr.manifest_text = _manifest(5)
	var u = _new_updater(FakeMounter.new())
	u.set_transport(tr)
	var rec := SignalRec.new()
	rec.bind_all(u, CHECK_SIGNALS)

	u.check("http://x/manifest.json")
	if rec.names() != ["update_available"]:
		print("FAIL 6a: 有新版应只发 update_available,实际 %s" % [rec.names()]); failures += 1
	var plan = rec.first("update_available")[1]
	var packs: Array = plan.get("packs", []) if plan is Dictionary else []
	if packs.size() != 1 or String(packs[0].get("id", "")) != "content" or int(packs[0].get("version", 0)) != 5:
		print("FAIL 6b: plan 应含 content v5,实际 %s" % [plan]); failures += 1
	u.free()
	return failures


## 7) check:manifest 目标引擎与运行引擎不符 → check_failed(engine_mismatch),不下载。
func _test_check_engine_mismatch() -> int:
	var failures := 0
	_write_state({"engine": _engine_str(), "installed": []})
	var tr := FakeTransport.new()
	tr.manifest_text = JSON.stringify({"engine": "9.9", "packs": [
		{"id": "content", "version": 1, "url": "http://x/c.pck", "size": 0, "sha256": "", "order": 0}]})
	var u = _new_updater(FakeMounter.new())
	u.set_transport(tr)
	var rec := SignalRec.new()
	rec.bind_all(u, CHECK_SIGNALS)

	u.check("http://x/manifest.json")
	var reason := String(rec.first("check_failed")[1]) if rec.names().has("check_failed") else ""
	if not reason.begins_with("engine_mismatch"):
		print("FAIL 7: 引擎不符应 check_failed(engine_mismatch...),实际 %s" % [rec.names()]); failures += 1
	u.free()
	return failures


## 8) check:传输拉 manifest 失败 → check_failed,本地状态不变。
func _test_check_transport_failure() -> int:
	var failures := 0
	_write_state({"engine": _engine_str(), "installed": [_entry("content", 2, 0)]})
	var tr := FakeTransport.new()
	tr.manifest_fail = true
	var u = _new_updater(FakeMounter.new())
	u.set_transport(tr)
	var rec := SignalRec.new()
	rec.bind_all(u, CHECK_SIGNALS)

	u.check("http://x/manifest.json")
	if not rec.names().has("check_failed"):
		print("FAIL 8a: 传输失败应发 check_failed,实际 %s" % [rec.names()]); failures += 1
	if u.local_version("content") != 2:
		print("FAIL 8b: 失败不应改动本地状态,local_version 实际 %s" % u.local_version("content")); failures += 1
	u.free()
	return failures


## 9) check:manifest 不是合法 JSON → check_failed(malformed)。
func _test_check_malformed() -> int:
	var failures := 0
	_write_state({"engine": _engine_str(), "installed": []})
	var tr := FakeTransport.new()
	tr.manifest_text = "{ this is not json"
	var u = _new_updater(FakeMounter.new())
	u.set_transport(tr)
	var rec := SignalRec.new()
	rec.bind_all(u, CHECK_SIGNALS)

	u.check("http://x/manifest.json")
	if not rec.names().has("check_failed"):
		print("FAIL 9: 畸形 manifest 应发 check_failed,实际 %s" % [rec.names()]); failures += 1
	u.free()
	return failures


const DL_SIGNALS := ["progress", "downloaded", "download_failed", "ready_to_apply"]


## 10) download 成功:全部包落盘校验通过 → ready_to_apply,state.json 记录新版本。
func _test_download_success() -> int:
	var failures := 0
	_write_state({"engine": _engine_str(), "installed": []})
	var bytes := "PACK-CONTENT-V4".to_utf8_buffer()
	var url := "http://x/content-v4.pck"
	var tr := FakeTransport.new()
	tr.files[url] = bytes
	var u = _new_updater(FakeMounter.new())
	u.set_transport(tr)
	var rec := SignalRec.new()
	rec.bind_all(u, DL_SIGNALS)

	var plan := {"engine": _engine_str(), "packs": [{
		"id": "content", "version": 4, "url": url,
		"size": bytes.size(), "sha256": _sha256(bytes), "order": 0,
	}]}
	u.download(plan)

	if not rec.names().has("ready_to_apply"):
		print("FAIL 10a: 全部成功应发 ready_to_apply,实际 %s" % [rec.names()]); failures += 1
	if not rec.names().has("downloaded"):
		print("FAIL 10b: 应发 downloaded,实际 %s" % [rec.names()]); failures += 1
	if u.local_version("content") != 4:
		print("FAIL 10c: 落盘后 local_version 应为 4,实际 %s" % u.local_version("content")); failures += 1
	# 暂存的文件应真实存在且内容一致(经 file 字段)
	var file := String(_installed_entry(u, "content").get("file", ""))
	if file.is_empty() or not FileAccess.file_exists(file):
		print("FAIL 10d: 已安装包文件应存在,实际 '%s'" % file); failures += 1
	elif FileAccess.get_file_as_bytes(file) != bytes:
		print("FAIL 10e: 落盘字节应与下载一致"); failures += 1
	u.free()
	return failures


## 11) sha256 不符:download_failed(checksum),且 state.json 逐字节未变(原子性)。
func _test_download_checksum_atomic() -> int:
	var failures := 0
	_write_state({"engine": _engine_str(), "installed": [_entry("content", 2, 0)]})
	var before := FileAccess.get_file_as_bytes(BASE + "/state.json")
	var url := "http://x/content-v3.pck"
	var tr := FakeTransport.new()
	tr.files[url] = "REAL-BYTES".to_utf8_buffer()
	var u = _new_updater(FakeMounter.new())
	u.set_transport(tr)
	var rec := SignalRec.new()
	rec.bind_all(u, DL_SIGNALS)

	# manifest 声明一个与真实字节不符的 sha256 → 校验必失败
	var plan := {"engine": _engine_str(), "packs": [{
		"id": "content", "version": 3, "url": url,
		"size": 10, "sha256": _sha256("DIFFERENT".to_utf8_buffer()), "order": 0,
	}]}
	u.download(plan)

	var reason := String(rec.first("download_failed")[2]) if rec.names().has("download_failed") else ""
	if reason != "checksum":
		print("FAIL 11a: sha256 不符应 download_failed(...,'checksum'),实际 %s" % [rec.names()]); failures += 1
	if rec.names().has("ready_to_apply"):
		print("FAIL 11b: 校验失败不应发 ready_to_apply"); failures += 1
	if u.local_version("content") != 2:
		print("FAIL 11c: 失败后 local_version 应仍为 2,实际 %s" % u.local_version("content")); failures += 1
	var after := FileAccess.get_file_as_bytes(BASE + "/state.json")
	if before != after:
		print("FAIL 11d: 下载失败后 state.json 应逐字节未变(原子性)"); failures += 1
	u.free()
	return failures


## 12) 传输中断(某包 fetch 失败):download_failed,state.json 逐字节未变。
func _test_download_interrupt_atomic() -> int:
	var failures := 0
	_write_state({"engine": _engine_str(), "installed": [_entry("content", 2, 0)]})
	var before := FileAccess.get_file_as_bytes(BASE + "/state.json")
	var url := "http://x/content-v3.pck"
	var tr := FakeTransport.new()
	tr.file_fail_on = url    # files 里没有该 url → fetch_file 直接失败
	var u = _new_updater(FakeMounter.new())
	u.set_transport(tr)
	var rec := SignalRec.new()
	rec.bind_all(u, DL_SIGNALS)

	var plan := {"engine": _engine_str(), "packs": [{
		"id": "content", "version": 3, "url": url,
		"size": 10, "sha256": "", "order": 0,
	}]}
	u.download(plan)

	if not rec.names().has("download_failed"):
		print("FAIL 12a: 传输中断应发 download_failed,实际 %s" % [rec.names()]); failures += 1
	if rec.names().has("ready_to_apply"):
		print("FAIL 12b: 中断不应发 ready_to_apply"); failures += 1
	var after := FileAccess.get_file_as_bytes(BASE + "/state.json")
	if before != after:
		print("FAIL 12c: 中断后 state.json 应逐字节未变"); failures += 1
	u.free()
	return failures


## 13) restart_to_apply 契约:headless/桌面下平台不支持自重启 → 返回 false
##     (真机自重启验证排后续轮次;此处只钉接口契约,不崩)。
func _test_restart_contract() -> int:
	var failures := 0
	_write_state({"engine": _engine_str(), "installed": []})
	var u = _new_updater(FakeMounter.new())
	var r = u.restart_to_apply()
	if typeof(r) != TYPE_BOOL:
		print("FAIL 13: restart_to_apply 应返回 bool,实际 %s" % [r]); failures += 1
	u.free()
	return failures


## 14) 真集成测(零假件):造真 zip → state 指向它 → updater 用**默认真挂载器**
##     mount_installed() → 经 res:// 读到包内文件。证明子系统端到端接线成立,
##     而非假件之间自洽。
func _test_real_pack_integration() -> int:
	var failures := 0
	# 先写 state(_write_state 内部会 _rm_rf(BASE) 清场),再造 zip——否则 zip 会被清掉。
	var zip_path := BASE + "/packs/real.zip"
	_write_state({
		"engine": _engine_str(),
		"installed": [{"id": "real", "version": 1, "file": zip_path, "sha256": "", "order": 0}],
	})

	# 用引擎自带 ZIPPacker 造一个真 zip 内容包(含一个 res:// 路径下的文件)
	DirAccess.make_dir_recursive_absolute(BASE + "/packs")
	var packer := ZIPPacker.new()
	if packer.open(zip_path) != OK:
		print("FAIL 14a: ZIPPacker.open 失败"); return failures + 1
	packer.start_file("kit_updater_probe.txt")
	packer.write_file("MOUNTED-OK".to_utf8_buffer())
	packer.close_file()
	packer.close()

	# 不注入 mounter → 走默认真 ProjectSettings.load_resource_pack。
	var u = _UpdaterScript.new()
	u.set_base_dir(BASE)
	u.mount_installed()

	if ",".join(u.mounted_packs()) != "real":
		print("FAIL 14b: mount_installed 应挂上 'real',实际 %s" % [u.mounted_packs()]); failures += 1
	# 经 res:// 读到包内文件(路径来自 zip 内 start_file 的名字)
	var got := FileAccess.get_file_as_string("res://kit_updater_probe.txt").strip_edges()
	if got != "MOUNTED-OK":
		print("FAIL 14c: 挂载后应经 res:// 读到 'MOUNTED-OK',实际 '%s'" % got); failures += 1
	u.free()
	return failures


## --- 测试辅助 ---

## 独立算法(不复用被测代码):PackedByteArray 的 sha256 hex,作为 sha256 的
## 可信来源,避免同义反复。
func _sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


func _installed_entry(u, id: String) -> Dictionary:
	var f := FileAccess.open(BASE + "/state.json", FileAccess.READ)
	var state = JSON.parse_string(f.get_as_text())
	f.close()
	for e in state.get("installed", []):
		if String(e.get("id", "")) == id:
			return e
	return {}


## 单包 manifest,声明运行引擎、content 包为给定版本。
func _manifest(version: int) -> String:
	return JSON.stringify({
		"engine": _engine_str(),
		"packs": [{
			"id": "content", "version": version,
			"url": "http://x/content-v%d.pck" % version,
			"size": 0, "sha256": "", "order": 0,
		}],
	})


func _entry(id: String, version: int, order: int) -> Dictionary:
	return {
		"id": id, "version": version, "order": order,
		"file": "%s/packs/%s.pck" % [BASE, id], "sha256": "",
	}


func _new_updater(mounter):
	var u = _UpdaterScript.new()
	u.set_base_dir(BASE)
	u.set_mounter(mounter)
	return u


func _engine_str() -> String:
	var info := Engine.get_version_info()
	return "%d.%d" % [info.major, info.minor]


func _write_state(state: Dictionary) -> void:
	_rm_rf(BASE)
	DirAccess.make_dir_recursive_absolute(BASE)
	var f := FileAccess.open(BASE + "/state.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(state))
	f.close()


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
