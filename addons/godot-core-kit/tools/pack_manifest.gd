class_name KitPackManifest
extends RefCounted
## 内容包 manifest 生成器 —— 「导出管线」的可测核心。
##
## 读已经 `--export-pack` 导出好的 `.pck`,算出每包的 size + sha256、戳上引擎版本,
## 产出一份 `CoreKit.updater.check()` 能**逐字消费**的 `manifest.json`。
##
## 这是**构建期工具**,不是运行时子系统:不接门面、不进 `core_kit.gd` 构造链、
## 不参与存档、游戏运行时永不实例化。消费者导出游戏时应把 `tools/` 排除出包。
## headless CLI 封装见 `tools/build_manifest.gd`;完整管线见
## `docs/tools/export-pipeline.md`。

## 从包规格产出 manifest,与 `PackUpdater` 的 manifest 格式逐字对齐(见其 §7)。
##
## specs 每项(Dictionary):
##   id      —— pack 标识(与 updater 的 state.json 同名,决定覆盖/版本比对)
##   version —— int,内容版本号(updater 只下 version 高于本地已装的)
##   url     —— 客户端下载地址(最终值;相对/绝对由调用方组装)
##   order   —— int,挂载顺序(研究 §1:同路径后挂者胜,顺序敏感)
##   file    —— 磁盘上已导出的 `.pck` 路径,仅用于算 size + sha256,**不进输出**
##
## engine 空 → 戳运行引擎 "major.minor"(= updater 挂载/检查所校验的值,研究 §3
## 包头引擎闸门)。**务必用导出这些包的同一个 Godot 跑本工具**,否则戳错版本。
##
## 返回 {engine, packs:[{id, version, url, size, sha256, order}]},packs 按 order 升序。
func build(specs: Array, engine := "") -> Dictionary:
	var eng := engine if not engine.is_empty() else _running_engine()
	var packs: Array = []
	for spec in specs:
		var file := String(spec.get("file", ""))
		var size := 0
		var sha := ""
		if FileAccess.file_exists(file):
			sha = FileAccess.get_sha256(file)
			var f := FileAccess.open(file, FileAccess.READ)
			if f != null:
				size = f.get_length()
				f.close()
		packs.append({
			"id": String(spec.get("id", "")),
			"version": int(spec.get("version", 0)),
			"url": String(spec.get("url", "")),
			"size": size,
			"sha256": sha,
			"order": int(spec.get("order", 0)),
		})
	packs.sort_custom(func(a, b): return int(a["order"]) < int(b["order"]))
	return {"engine": eng, "packs": packs}


## manifest 里 size<=0 或 sha256 为空的 pack id 列表(引用了缺失/不可读的 `.pck`)。
## CLI 在写盘前用它拦下会让所有客户端 checksum 失败的「哑弹」manifest。
func validate(manifest: Dictionary) -> Array:
	var bad: Array = []
	for pack in manifest.get("packs", []):
		if int(pack.get("size", 0)) <= 0 or String(pack.get("sha256", "")).is_empty():
			bad.append(String(pack.get("id", "")))
	return bad


## 原子写 manifest 到 out_path(temp + rename,照 SaveManager / PackUpdater 先例)。
## 返回 Error(OK 为成功)。
func write_manifest(manifest: Dictionary, out_path: String) -> int:
	var dir := out_path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	var tmp := out_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(manifest, "\t"))
	f.close()
	if DirAccess.rename_absolute(tmp, out_path) == OK:
		return OK
	# 目标已存在时 rename 可能失败:先删旧再改名。
	if FileAccess.file_exists(out_path):
		DirAccess.remove_absolute(out_path)
		return DirAccess.rename_absolute(tmp, out_path)
	return FAILED


## 运行引擎的 "major.minor" 字符串(与 PackUpdater._running_engine 同定义)。
func _running_engine() -> String:
	var info := Engine.get_version_info()
	return "%d.%d" % [info.major, info.minor]
