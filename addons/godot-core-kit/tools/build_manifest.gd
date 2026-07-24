extends SceneTree
## 导出管线 CLI —— 读 build-spec JSON,组装下载 URL,生成并原子写 manifest.json。
##
## 用法(用**导出这些包的同一个 Godot** 跑,以戳对引擎版本):
##   godot --headless --path . --script res://addons/godot-core-kit/tools/build_manifest.gd \
##     -- <spec.json> <out/manifest.json>
##
## spec.json:
##   {
##     "engine": "",                          // 空 = 运行引擎 major.minor
##     "url_base": "https://cdn.example.com/", // 相对 url 拼在其后;可空
##     "packs": [
##       {"id":"content","version":3,"order":0,"file":"out/content-v3.pck","url":"content-v3.pck"}
##     ]
##   }
##
## url 组装:以 http:// 或 https:// 开头的原样用;否则拼到 url_base 之后。
## 产物直接可作 CoreKit.updater.check(<manifest_url>) 的下发内容。
##
## 本 CLI 需真实磁盘文件、走命令行,**不进 headless 测试门**(同 http_pack_transport.gd);
## 其可测核心 KitPackManifest 由 test_pack_manifest.gd 覆盖。

const KitPackManifestScript := preload("res://addons/godot-core-kit/tools/pack_manifest.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: build_manifest.gd -- <spec.json> <out/manifest.json>")
		quit(1)
		return
	var spec_path := args[0]
	var out_path := args[1]

	var spec = _read_json(spec_path)
	if not (spec is Dictionary) or not spec.has("packs"):
		printerr("build_manifest: bad or missing spec: %s" % spec_path)
		quit(1)
		return

	var url_base := String(spec.get("url_base", ""))
	var specs: Array = []
	for pack in spec.get("packs", []):
		var d: Dictionary = (pack as Dictionary).duplicate()
		d["url"] = _compose_url(url_base, String(pack.get("url", "")))
		specs.append(d)

	var gen = KitPackManifestScript.new()
	var manifest = gen.build(specs, String(spec.get("engine", "")))

	var problems = gen.validate(manifest)
	if not problems.is_empty():
		printerr("build_manifest: un-hashable packs (missing/unreadable .pck): %s" % ", ".join(problems))
		quit(1)
		return

	var err = gen.write_manifest(manifest, out_path)
	if err != OK:
		printerr("build_manifest: write failed (err=%d) -> %s" % [err, out_path])
		quit(1)
		return

	print("build_manifest: wrote %s  (engine=%s, packs=%d)" % [out_path, manifest["engine"], manifest["packs"].size()])
	quit(0)


func _compose_url(base: String, u: String) -> String:
	if u.begins_with("http://") or u.begins_with("https://"):
		return u
	if base.is_empty():
		return u
	return base + u if base.ends_with("/") else base + "/" + u


func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(txt) != OK:
		return null
	return j.data
