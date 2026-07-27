class_name SubpackRuntime
extends RefCounted

signal _wechat_subpackage_loaded(pack_name: String, success: bool, pack_path: String)

const DEFAULT_MANIFEST_PATH := "res://subpacks/subpack_manifest.json"
const EDITOR_DEMO_MANIFEST_PATH := "res://dist/subpacks/subpack_manifest.json"
const EXTERNAL_SUBPACK_MANIFEST_RELATIVE_PATH := "subpacks/subpack_manifest.json"
const CACHE_ROOT := "user://godot_subpack_cache"
const CACHE_PACK_ROOT := "user://godot_subpack_cache/packs"
const CACHE_INDEX_PATH := "user://godot_subpack_cache/cache_index.json"
const DEFAULT_CACHE_BUDGET_MB := 45

var _manifest: Dictionary = {}
var _packs_by_name: Dictionary = {}
var _loaded_subpacks := PackedStringArray()
var _loaded_subpack_paths: Dictionary = {}
var _loaded_subpack_sources: Dictionary = {}
var _runtime_events: Array[Dictionary] = []
var _loaded_manifest_path := ""
var _loaded_manifest_url := ""
var _cache_budget_mb := DEFAULT_CACHE_BUDGET_MB
var _http_timeout_seconds := 30.0
var _wechat_callbacks: Dictionary = {}


func load_manifest(manifest_path: String = "") -> bool:
	var resolved_manifest_path := _resolve_manifest_path(manifest_path)

	if not FileAccess.file_exists(resolved_manifest_path):
		push_warning("SubpackRuntime could not open manifest: %s" % resolved_manifest_path)
		return false

	var text := FileAccess.get_file_as_string(resolved_manifest_path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SubpackRuntime expects a JSON object at the manifest root.")
		return false

	_manifest = parsed
	_packs_by_name.clear()

	var packs_value: Variant = _manifest.get("packs", [])
	if typeof(packs_value) == TYPE_ARRAY:
		for entry: Variant in packs_value:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var pack: Dictionary = entry
			var pack_name := String(pack.get("name", ""))
			if not pack_name.is_empty():
				_packs_by_name[pack_name] = pack

	_loaded_manifest_path = resolved_manifest_path
	_loaded_manifest_url = ""
	_apply_manifest_runtime_options()
	_loaded_subpacks.clear()
	_loaded_subpack_paths.clear()
	_loaded_subpack_sources.clear()
	_record_event("manifest_loaded", "", resolved_manifest_path, "", "", {"pack_count": _packs_by_name.size()})
	return true


func load_remote_manifest(manifest_url: String, cache_path: String = "") -> bool:
	var resolved_url := manifest_url.strip_edges()
	if resolved_url.is_empty() or not _is_http_url(resolved_url):
		push_warning("SubpackRuntime.load_remote_manifest() requires an HTTP(S) manifest URL.")
		return false

	var resolved_cache_path := cache_path.strip_edges()
	if resolved_cache_path.is_empty():
		resolved_cache_path = CACHE_ROOT.path_join("remote_manifest.json")

	if not _ensure_user_directory(resolved_cache_path.get_base_dir()):
		return false

	_record_event("manifest_download_start", "", resolved_cache_path, resolved_url)
	if not await _download_to_file(resolved_url, resolved_cache_path):
		return false
	_record_event("manifest_download_complete", "", resolved_cache_path, resolved_url)

	if not load_manifest(resolved_cache_path):
		return false

	_loaded_manifest_url = resolved_url
	return true


func has_subpack(name: String) -> bool:
	return _packs_by_name.has(name)


func is_subpack_loaded(name: String) -> bool:
	return _loaded_subpacks.has(name)


func load_subpack(name: String, resolved_pack_path: String = "", source: String = "local") -> bool:
	if name.is_empty():
		push_warning("SubpackRuntime.load_subpack() requires a non-empty pack name.")
		return false
	if not has_subpack(name):
		push_warning("SubpackRuntime has no manifest entry for subpack: %s" % name)
		return false
	if is_subpack_loaded(name):
		_record_event(
			"pack_already_loaded",
			name,
			String(_loaded_subpack_paths.get(name, "")),
			"",
			String(_loaded_subpack_sources.get(name, ""))
		)
		return true

	var pack_path := _resolve_pack_path(name, resolved_pack_path, "")
	if pack_path.is_empty():
		push_warning("SubpackRuntime could not resolve a pack path for: %s" % name)
		return false

	if not ProjectSettings.load_resource_pack(pack_path, true, 0):
		push_warning("SubpackRuntime failed to load subpack pack file: %s" % pack_path)
		return false

	_loaded_subpacks.append(name)
	_loaded_subpack_paths[name] = pack_path
	_loaded_subpack_sources[name] = source.strip_edges() if not source.strip_edges().is_empty() else "local"
	_record_event("pack_mounted", name, pack_path, "", String(_loaded_subpack_sources[name]))
	return true


func load_subpack_with_dependencies(name: String, base_path: String = "") -> bool:
	if not has_subpack(name):
		push_warning("SubpackRuntime has no manifest entry for subpack: %s" % name)
		return false

	var stack := PackedStringArray()
	return _load_subpack_recursive(name, base_path, stack)


func ensure_subpack(name: String, base_path: String = "") -> bool:
	return await ensure_subpack_with_dependencies(name, base_path)


func ensure_subpack_with_dependencies(name: String, base_path: String = "") -> bool:
	if not has_subpack(name):
		push_warning("SubpackRuntime has no manifest entry for subpack: %s" % name)
		return false

	var stack := PackedStringArray()
	return await _ensure_subpack_recursive(name, base_path, stack)


func get_loaded_subpacks() -> PackedStringArray:
	return _loaded_subpacks.duplicate()


func clear_loaded_subpacks() -> void:
	_loaded_subpacks.clear()
	_loaded_subpack_paths.clear()
	_loaded_subpack_sources.clear()


func get_loaded_subpack_path(name: String) -> String:
	return String(_loaded_subpack_paths.get(name, ""))


func get_loaded_subpack_source(name: String) -> String:
	return String(_loaded_subpack_sources.get(name, ""))


func get_runtime_events() -> Array:
	return _runtime_events.duplicate(true)


func clear_runtime_events() -> void:
	_runtime_events.clear()


func drain_runtime_events() -> Array:
	var events := _runtime_events.duplicate(true)
	_runtime_events.clear()
	return events


func get_manifest() -> Dictionary:
	return _manifest.duplicate(true)


func get_loaded_manifest_path() -> String:
	return _loaded_manifest_path


func get_default_manifest_candidates() -> PackedStringArray:
	var candidates := PackedStringArray()

	if OS.has_feature("editor"):
		candidates = _append_unique_string(candidates, EDITOR_DEMO_MANIFEST_PATH)

	var executable_dir := OS.get_executable_path().get_base_dir()
	if not executable_dir.is_empty():
		candidates = _append_unique_string(candidates, executable_dir.path_join(EXTERNAL_SUBPACK_MANIFEST_RELATIVE_PATH))

	candidates = _append_unique_string(candidates, DEFAULT_MANIFEST_PATH)

	if not OS.has_feature("editor"):
		candidates = _append_unique_string(candidates, EDITOR_DEMO_MANIFEST_PATH)

	return candidates


func get_pack_names() -> PackedStringArray:
	var names := PackedStringArray()
	for pack_name in _packs_by_name.keys():
		names.append(String(pack_name))
	return names


func get_pack(pack_name: String) -> Dictionary:
	if not _packs_by_name.has(pack_name):
		return {}
	var pack: Dictionary = _packs_by_name[pack_name]
	return pack.duplicate(true)


func get_pack_dependencies(pack_name: String) -> PackedStringArray:
	if not _packs_by_name.has(pack_name):
		return PackedStringArray()
	var pack: Dictionary = _packs_by_name[pack_name]
	return _to_packed_string_array(pack.get("dependencies", PackedStringArray()))


func get_pack_relative_path(pack_name: String) -> String:
	if not _packs_by_name.has(pack_name):
		return ""
	var pack: Dictionary = _packs_by_name[pack_name]
	return String(pack.get("relative_pack_path", ""))


func _load_subpack_recursive(pack_name: String, base_path: String, stack: PackedStringArray) -> bool:
	if is_subpack_loaded(pack_name):
		return true
	if stack.has(pack_name):
		push_warning("SubpackRuntime detected a dependency cycle while loading: %s" % pack_name)
		return false

	stack.append(pack_name)

	for dependency in get_pack_dependencies(pack_name):
		if not _load_subpack_recursive(dependency, base_path, stack):
			return false

	var pack_path := _resolve_pack_path(pack_name, "", base_path)
	if pack_path.is_empty():
		push_warning("SubpackRuntime could not resolve a dependent pack path for: %s" % pack_name)
		return false

	return load_subpack(pack_name, pack_path, "local")


func _ensure_subpack_recursive(pack_name: String, base_path: String, stack: PackedStringArray) -> bool:
	if is_subpack_loaded(pack_name):
		return true
	if stack.has(pack_name):
		push_warning("SubpackRuntime detected a dependency cycle while loading: %s" % pack_name)
		return false

	stack.append(pack_name)

	for dependency in get_pack_dependencies(pack_name):
		if not await _ensure_subpack_recursive(dependency, base_path, stack):
			return false

	return await _ensure_single_subpack(pack_name, base_path)


func _ensure_single_subpack(pack_name: String, base_path: String) -> bool:
	var local_pack_path := _resolve_pack_path(pack_name, "", base_path)
	if not local_pack_path.is_empty() and not _is_http_url(local_pack_path) and FileAccess.file_exists(local_pack_path):
		_record_event("pack_local_found", pack_name, local_pack_path, "", "local")
		return load_subpack(pack_name, local_pack_path, "local")

	var wechat_pack_path := await _ensure_wechat_subpackage_pack(pack_name)
	if not wechat_pack_path.is_empty():
		return load_subpack(pack_name, wechat_pack_path, "wechat_subpackage")

	var cached_pack_path := _resolve_cache_pack_path(pack_name)
	if FileAccess.file_exists(cached_pack_path) and _verify_pack_file(pack_name, cached_pack_path):
		_record_event("pack_cache_hit", pack_name, cached_pack_path, "", "cache")
		_touch_cache_entry(pack_name, cached_pack_path)
		return load_subpack(pack_name, cached_pack_path, "cache")

	var remote_url := _resolve_remote_pack_url(pack_name)
	if remote_url.is_empty():
		push_warning("SubpackRuntime has no local or remote pack path for: %s" % pack_name)
		return false

	if not _ensure_user_directory(cached_pack_path.get_base_dir()):
		return false

	var temp_path := cached_pack_path + ".download"
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))

	_record_event("pack_download_start", pack_name, temp_path, remote_url, "remote")
	if not await _download_to_file(remote_url, temp_path):
		return false
	_record_event("pack_download_complete", pack_name, temp_path, remote_url, "remote", {"size_bytes": _file_size(temp_path)})
	if not _verify_pack_file(pack_name, temp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false

	if FileAccess.file_exists(cached_pack_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cached_pack_path))
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(cached_pack_path))
	if rename_error != OK:
		push_warning("SubpackRuntime failed to move downloaded pack into cache: %s" % cached_pack_path)
		return false

	_record_event("pack_cached", pack_name, cached_pack_path, remote_url, "remote", {"size_bytes": _file_size(cached_pack_path)})
	_touch_cache_entry(pack_name, cached_pack_path)
	_evict_lru_cache(cached_pack_path)
	return load_subpack(pack_name, cached_pack_path, "remote")


func _ensure_wechat_subpackage_pack(pack_name: String) -> String:
	if not _can_use_wechat_subpackage_loader(pack_name):
		return ""

	var js_pack_path := _get_wechat_pack_path(pack_name)
	if js_pack_path.is_empty():
		return ""

	var godot_pack_path := _wechat_pack_path_to_godot_path(js_pack_path)
	if FileAccess.file_exists(godot_pack_path):
		_record_event("wechat_subpackage_pack_found", pack_name, godot_pack_path, "", "wechat_subpackage")
		return godot_pack_path

	var package_name := _get_wechat_subpackage_name(pack_name)
	var sdk = JavaScriptBridge.get_interface("GODOTSDK")
	if sdk == null:
		return ""

	var done_callback = JavaScriptBridge.create_callback(Callable(self, "_on_wechat_subpackage_done").bind(pack_name, godot_pack_path))
	var progress_callback = JavaScriptBridge.create_callback(Callable(self, "_on_wechat_subpackage_progress").bind(pack_name))
	_wechat_callbacks[pack_name] = {
		"done": done_callback,
		"progress": progress_callback,
	}

	_record_event("wechat_subpackage_load_start", pack_name, godot_pack_path, js_pack_path, "wechat_subpackage", {"subpackage": package_name})
	sdk.load_pack(package_name, js_pack_path, progress_callback, done_callback)

	while true:
		var result: Array = await _wechat_subpackage_loaded
		if result.size() < 3 or String(result[0]) != pack_name:
			continue
		_wechat_callbacks.erase(pack_name)
		if bool(result[1]):
			return String(result[2])
		return ""
	return ""


func _can_use_wechat_subpackage_loader(pack_name: String) -> bool:
	if OS.get_name() != "Web":
		return false
	if not _packs_by_name.has(pack_name):
		return false
	if String(_manifest.get("mode", "")).strip_edges().to_lower() != "minigame":
		return false
	var sdk = JavaScriptBridge.get_interface("GODOTSDK")
	return sdk != null


func _get_wechat_subpackage_name(pack_name: String) -> String:
	var pack: Dictionary = _packs_by_name.get(pack_name, {})
	for key in ["wechat_subpackage_name", "wechat_subpackage", "minigame_subpackage_name"]:
		var value := String(pack.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return pack_name


func _get_wechat_pack_path(pack_name: String) -> String:
	var pack: Dictionary = _packs_by_name.get(pack_name, {})
	for key in ["wechat_pack_path", "minigame_pack_path"]:
		var value := String(pack.get(key, "")).strip_edges().replace("\\", "/")
		if not value.is_empty():
			return _normalize_wechat_file_path(value)

	var relative_path := String(pack.get("relative_pack_path", "")).strip_edges().replace("\\", "/")
	if relative_path.is_empty():
		return ""
	return "/subpackages/%s/%s" % [_sanitize_cache_name(pack_name), relative_path.get_file()]


func _normalize_wechat_file_path(path: String) -> String:
	var normalized := path.strip_edges().replace("\\", "/")
	if normalized.begins_with("res://"):
		normalized = normalized.trim_prefix("res://")
	if not normalized.begins_with("/"):
		normalized = "/" + normalized
	return normalized


func _wechat_pack_path_to_godot_path(path: String) -> String:
	var normalized := path.strip_edges().replace("\\", "/")
	if normalized.begins_with("res://") or normalized.begins_with("user://"):
		return normalized
	return "res://" + normalized.trim_prefix("/")


func _on_wechat_subpackage_progress(args: Array, pack_name: String) -> void:
	var progress := 0
	if args.size() > 0 and (typeof(args[0]) == TYPE_INT or typeof(args[0]) == TYPE_FLOAT):
		progress = int(args[0])
	_record_event("wechat_subpackage_progress", pack_name, "", "", "wechat_subpackage", {"progress": progress})


func _on_wechat_subpackage_done(args: Array, pack_name: String, godot_pack_path: String) -> void:
	var success := true
	if args.size() > 0 and args[0] != null:
		var message := String(args[0])
		if not message.is_empty() and message != "100":
			success = false

	_record_event(
		"wechat_subpackage_load_complete" if success else "wechat_subpackage_load_failed",
		pack_name,
		godot_pack_path,
		"",
		"wechat_subpackage"
	)
	emit_signal("_wechat_subpackage_loaded", pack_name, success, godot_pack_path)


func _resolve_manifest_path(manifest_path: String) -> String:
	var requested_path := manifest_path.strip_edges()
	if requested_path.is_empty() or requested_path == DEFAULT_MANIFEST_PATH:
		for candidate_path in get_default_manifest_candidates():
			if FileAccess.file_exists(candidate_path):
				return candidate_path
		return DEFAULT_MANIFEST_PATH if requested_path.is_empty() else requested_path

	return requested_path


func _resolve_pack_path(pack_name: String, explicit_pack_path: String, base_path: String) -> String:
	if _manifest.is_empty():
		return ""

	var pack_path := explicit_pack_path.strip_edges()
	if pack_path.is_empty():
		pack_path = get_pack_relative_path(pack_name).strip_edges()
	if pack_path.is_empty():
		return ""

	var resolved_base_path := base_path.strip_edges()
	if resolved_base_path.is_empty() and explicit_pack_path.strip_edges().is_empty() and not _loaded_manifest_path.is_empty():
		var manifest_directory := _loaded_manifest_path.get_base_dir()
		resolved_base_path = manifest_directory.get_base_dir() if String(_manifest.get("pack_path_base", "manifest_dir")) == "export_dir" else manifest_directory

	if not pack_path.contains("://") and not resolved_base_path.is_empty():
		pack_path = resolved_base_path.path_join(pack_path)

	if pack_path.begins_with("res://") or pack_path.begins_with("user://"):
		pack_path = ProjectSettings.globalize_path(pack_path)

	return pack_path


func _apply_manifest_runtime_options() -> void:
	var budget_value: Variant = _manifest.get("cache_budget_mb", DEFAULT_CACHE_BUDGET_MB)
	if typeof(budget_value) == TYPE_INT or typeof(budget_value) == TYPE_FLOAT:
		_cache_budget_mb = max(1, int(budget_value))

	var remote_value: Variant = _manifest.get("remote", {})
	if typeof(remote_value) == TYPE_DICTIONARY:
		var remote: Dictionary = remote_value
		var remote_budget: Variant = remote.get("cache_budget_mb", _cache_budget_mb)
		if typeof(remote_budget) == TYPE_INT or typeof(remote_budget) == TYPE_FLOAT:
			_cache_budget_mb = max(1, int(remote_budget))


func _resolve_remote_pack_url(pack_name: String) -> String:
	if not _packs_by_name.has(pack_name):
		return ""

	var pack: Dictionary = _packs_by_name[pack_name]
	var raw_url := String(pack.get("remote_url", "")).strip_edges()
	if raw_url.is_empty():
		raw_url = String(pack.get("url", "")).strip_edges()
	if _is_http_url(raw_url):
		return raw_url

	var remote_path := String(pack.get("remote_path", "")).strip_edges()
	if remote_path.is_empty():
		remote_path = String(pack.get("relative_pack_path", "")).strip_edges()
	if remote_path.is_empty():
		return ""
	if _is_http_url(remote_path):
		return remote_path

	var base_url := ""
	var remote_value: Variant = _manifest.get("remote", {})
	if typeof(remote_value) == TYPE_DICTIONARY:
		var remote: Dictionary = remote_value
		base_url = String(remote.get("base_url", "")).strip_edges()
	if base_url.is_empty():
		base_url = String(_manifest.get("remote_base_url", "")).strip_edges()
	if base_url.is_empty() and not _loaded_manifest_url.is_empty():
		base_url = _loaded_manifest_url.get_base_dir()
	if base_url.is_empty():
		return ""

	return _join_url(base_url, remote_path)


func _resolve_cache_pack_path(pack_name: String) -> String:
	if not _packs_by_name.has(pack_name):
		return CACHE_PACK_ROOT.path_join(_sanitize_cache_name(pack_name) + _pack_cache_extension())

	var pack: Dictionary = _packs_by_name[pack_name]
	var sha := String(pack.get("sha256", "")).strip_edges().to_lower()
	var suffix := sha.substr(0, 16) if not sha.is_empty() else _sanitize_cache_name(pack_name)
	return CACHE_PACK_ROOT.path_join("%s-%s%s" % [_sanitize_cache_name(pack_name), suffix, _pack_cache_extension()])


func _pack_cache_extension() -> String:
	var explicit_extension := String(_manifest.get("pack_file_extension", "")).strip_edges().to_lower()
	if explicit_extension in [".bin", "bin"]:
		return ".bin"
	if String(_manifest.get("mode", "")).strip_edges().to_lower() == "minigame":
		return ".bin"
	return ".pck"


func _verify_pack_file(pack_name: String, path: String) -> bool:
	if not _packs_by_name.has(pack_name):
		return false
	var pack: Dictionary = _packs_by_name[pack_name]
	var expected_sha := String(pack.get("sha256", "")).strip_edges().to_lower()
	if expected_sha.is_empty():
		return true

	var actual_sha := _sha256_file(path)
	if actual_sha != expected_sha:
		_record_event("pack_sha_failed", pack_name, path, "", "", {"expected_sha256": expected_sha, "actual_sha256": actual_sha})
		push_warning("SubpackRuntime SHA-256 mismatch for %s." % pack_name)
		return false
	_record_event("pack_sha_verified", pack_name, path, "", "", {"sha256": expected_sha})
	return true


func _download_to_file(url: String, target_path: String) -> bool:
	var parent := _get_http_request_parent()
	if parent == null:
		_record_event("download_failed", "", target_path, url, "", {"message": "没有可用的 SceneTree，无法创建 HTTPRequest。"})
		push_warning("SubpackRuntime could not find a SceneTree for HTTP downloads.")
		return false

	var request := HTTPRequest.new()
	request.use_threads = not OS.has_feature("web")
	request.timeout = _http_timeout_seconds
	request.download_file = target_path
	if not await _attach_http_request(parent, request):
		request.free()
		_record_event("download_failed", "", target_path, url, "", {"message": "HTTPRequest 没有进入 SceneTree，无法启动请求。"})
		return false

	var error := request.request(url)
	if error != OK:
		request.queue_free()
		_record_event("download_failed", "", target_path, url, "", {"message": "请求启动失败: %s" % _error_name(error), "error": error})
		push_warning("SubpackRuntime failed to start HTTP request: %s" % url)
		return false

	var completed: Array = await request.request_completed
	request.queue_free()
	if completed.size() < 4:
		_record_event("download_failed", "", target_path, url, "", {"message": "HTTP 完成信号格式无效。"})
		push_warning("SubpackRuntime received an invalid HTTP completion signal: %s" % url)
		return false

	var result := int(completed[0])
	var response_code := int(completed[1])
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		var message := "HTTP 下载失败: %s，状态码 %d" % [_http_request_result_name(result), response_code]
		if response_code == 0:
			message += "；如果当前是 Web/小游戏运行环境，优先检查远端域名 CORS、HTTPS 证书和平台合法域名白名单。"
		_record_event(
			"download_failed",
			"",
			target_path,
			url,
			"",
			{
				"message": message,
				"result": result,
				"response_code": response_code,
			}
		)
		push_warning("SubpackRuntime HTTP download failed (%s, %s): %s" % [result, response_code, url])
		return false

	if FileAccess.file_exists(target_path):
		return true

	_record_event("download_failed", "", target_path, url, "", {"message": "HTTP 请求成功，但目标文件没有写入。"})
	push_warning("SubpackRuntime HTTP request succeeded but no file was written: %s" % target_path)
	return false


func _attach_http_request(parent: Node, request: HTTPRequest) -> bool:
	if parent == null or not parent.is_inside_tree():
		return false

	parent.add_child.call_deferred(request)
	var tree := parent.get_tree()
	for _i in range(8):
		await tree.process_frame
		if is_instance_valid(request) and request.is_inside_tree():
			return true
	return false


func _get_http_request_parent() -> Node:
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		return (main_loop as SceneTree).root
	return null


func _ensure_user_directory(path: String) -> bool:
	var absolute_path := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute_path)
	if error != OK:
		push_warning("SubpackRuntime failed to create directory: %s" % path)
		return false
	return true


func _sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""

	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""

	const CHUNK_SIZE := 65536
	while file.get_position() < file.get_length():
		var remaining := file.get_length() - file.get_position()
		context.update(file.get_buffer(min(CHUNK_SIZE, remaining)))

	return context.finish().hex_encode()


func _touch_cache_entry(pack_name: String, cached_pack_path: String) -> void:
	var index := _load_cache_index()
	var packs: Dictionary = index.get("packs", {})
	var pack: Dictionary = _packs_by_name.get(pack_name, {})
	packs[pack_name] = {
		"path": cached_pack_path,
		"sha256": String(pack.get("sha256", "")).strip_edges().to_lower(),
		"size_bytes": _file_size(cached_pack_path),
		"last_access": int(Time.get_unix_time_from_system()),
	}
	index["packs"] = packs
	_save_cache_index(index)


func _evict_lru_cache(exempt_path: String) -> void:
	var budget_bytes := int(_cache_budget_mb) * 1024 * 1024
	if budget_bytes <= 0:
		return

	var index := _load_cache_index()
	var packs: Dictionary = index.get("packs", {})
	var entries: Array = []
	var total_size := 0

	for pack_name in packs.keys():
		var entry: Dictionary = packs[pack_name]
		var path := String(entry.get("path", ""))
		var size_bytes := int(entry.get("size_bytes", _file_size(path)))
		total_size += size_bytes
		entries.append({
			"name": String(pack_name),
			"path": path,
			"size_bytes": size_bytes,
			"last_access": int(entry.get("last_access", 0)),
		})

	if total_size <= budget_bytes:
		return

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("last_access", 0)) < int(b.get("last_access", 0))
	)

	for entry in entries:
		if total_size <= budget_bytes:
			break
		var pack_name := String(entry.get("name", ""))
		var path := String(entry.get("path", ""))
		if path == exempt_path or _loaded_subpacks.has(pack_name):
			continue
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		total_size -= int(entry.get("size_bytes", 0))
		packs.erase(pack_name)

	index["packs"] = packs
	_save_cache_index(index)


func _load_cache_index() -> Dictionary:
	if not FileAccess.file_exists(CACHE_INDEX_PATH):
		return {"packs": {}}

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CACHE_INDEX_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"packs": {}}
	var index: Dictionary = parsed
	if typeof(index.get("packs", {})) != TYPE_DICTIONARY:
		index["packs"] = {}
	return index


func _save_cache_index(index: Dictionary) -> void:
	if not _ensure_user_directory(CACHE_ROOT):
		return
	var file := FileAccess.open(CACHE_INDEX_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(index, "\t"))


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return int(file.get_length()) if file != null else 0


func _record_event(kind: String, pack_name: String = "", path: String = "", url: String = "", source: String = "", details: Dictionary = {}) -> void:
	var event := {
		"kind": kind,
		"pack": pack_name,
		"path": path,
		"url": url,
		"source": source,
		"time_msec": Time.get_ticks_msec(),
	}
	for key in details.keys():
		event[key] = details[key]
	_runtime_events.append(event)


func _http_request_result_name(result: int) -> String:
	match result:
		HTTPRequest.RESULT_SUCCESS:
			return "成功"
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "分块响应大小不匹配"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "无法连接服务器"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "无法解析域名"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "连接中断"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS/HTTPS 握手失败"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "服务器无响应"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "响应体超过限制"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "响应体解压失败"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "请求失败"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "无法打开下载文件"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "下载文件写入失败"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "重定向次数过多"
		HTTPRequest.RESULT_TIMEOUT:
			return "请求超时"
		_:
			return "未知错误 %d" % result


func _error_name(error: int) -> String:
	match error:
		OK:
			return "OK"
		FAILED:
			return "FAILED"
		ERR_UNAVAILABLE:
			return "ERR_UNAVAILABLE"
		ERR_UNCONFIGURED:
			return "ERR_UNCONFIGURED"
		ERR_UNAUTHORIZED:
			return "ERR_UNAUTHORIZED"
		ERR_PARAMETER_RANGE_ERROR:
			return "ERR_PARAMETER_RANGE_ERROR"
		ERR_OUT_OF_MEMORY:
			return "ERR_OUT_OF_MEMORY"
		ERR_FILE_NOT_FOUND:
			return "ERR_FILE_NOT_FOUND"
		ERR_FILE_BAD_DRIVE:
			return "ERR_FILE_BAD_DRIVE"
		ERR_FILE_BAD_PATH:
			return "ERR_FILE_BAD_PATH"
		ERR_FILE_NO_PERMISSION:
			return "ERR_FILE_NO_PERMISSION"
		ERR_FILE_ALREADY_IN_USE:
			return "ERR_FILE_ALREADY_IN_USE"
		ERR_FILE_CANT_OPEN:
			return "ERR_FILE_CANT_OPEN"
		ERR_FILE_CANT_WRITE:
			return "ERR_FILE_CANT_WRITE"
		ERR_INVALID_PARAMETER:
			return "ERR_INVALID_PARAMETER"
		ERR_ALREADY_IN_USE:
			return "ERR_ALREADY_IN_USE"
		ERR_BUSY:
			return "ERR_BUSY"
		ERR_CANT_CONNECT:
			return "ERR_CANT_CONNECT"
		ERR_CANT_RESOLVE:
			return "ERR_CANT_RESOLVE"
		ERR_CONNECTION_ERROR:
			return "ERR_CONNECTION_ERROR"
		ERR_CANT_ACQUIRE_RESOURCE:
			return "ERR_CANT_ACQUIRE_RESOURCE"
		ERR_TIMEOUT:
			return "ERR_TIMEOUT"
		_:
			return "错误码 %d" % error


func _is_http_url(value: String) -> bool:
	var lower := value.to_lower()
	return lower.begins_with("https://") or lower.begins_with("http://")


func _join_url(base_url: String, relative_path: String) -> String:
	if _is_http_url(relative_path):
		return relative_path
	return base_url.trim_suffix("/") + "/" + relative_path.trim_prefix("/")


func _sanitize_cache_name(value: String) -> String:
	var result := value.strip_edges()
	result = result.replace("://", "_")
	result = result.replace("/", "_")
	result = result.replace("\\", "_")
	result = result.replace(":", "_")
	result = result.replace("?", "_")
	result = result.replace("&", "_")
	result = result.replace("=", "_")
	result = result.replace(" ", "_")
	return result


static func _to_packed_string_array(value: Variant) -> PackedStringArray:
	if typeof(value) == TYPE_PACKED_STRING_ARRAY:
		return value

	var result := PackedStringArray()
	if typeof(value) != TYPE_ARRAY:
		return result

	for entry: Variant in value:
		if typeof(entry) == TYPE_STRING:
			result.append(String(entry))
	return result


static func _append_unique_string(values: PackedStringArray, value: String) -> PackedStringArray:
	if value.is_empty() or values.has(value):
		return values
	values.append(value)
	return values
