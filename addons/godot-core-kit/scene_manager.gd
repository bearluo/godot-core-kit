extends Node
## SceneManager —— godot-core-kit 全局场景切换单例（首版：仅替换，无场景栈）。
##
## 以 autoload "SceneManager" 注册（注册步骤属后续集成任务，不在本文件内）。统一入口
## change_scene(target, options) 把"替换当前活动场景"这件事从零散的
## get_tree().change_scene_to_*() 调用收敛为一个可选带淡入淡出过渡、带切换生命周期信号
## 的协程。同步 load()（不用线程，Web 导出安全）；默认过渡 NONE，可选 FADE
## （CanvasLayer + ColorRect + Tween，常驻本节点下、不受场景替换影响）。拒绝重入
## （_is_changing 守卫），不做排队。
##
## 用法：
##   SceneManager.change_scene("res://levels/level_2.tscn")
##   SceneManager.change_scene(preload("res://levels/boss.tscn"), {"transition": SceneManager.Transition.FADE})
##   await SceneManager.change_scene(...)   # 原地等待切换完成

signal scene_changing(target_path: String)
signal scene_changed(scene_path: String, scene: Node)
signal scene_change_failed(target_path: String, error: int)  # error 为 Error 枚举取值

enum Transition { NONE, FADE }

const DEFAULT_TRANSITION := Transition.NONE
const DEFAULT_FADE_DURATION := 0.3
const DEFAULT_FADE_COLOR := Color.BLACK
const _FADE_LAYER := 4096

var _is_changing := false
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect


func _ready() -> void:
	_ensure_fade_overlay()


# --- 公开运行时 API ---

## 把当前活动场景替换为 target。target 为 res:// 路径（String）或 PackedScene。
## options 支持 transition/duration/color，未识别或类型不对的键静默回退默认值。
## 协程：可 fire-and-forget（靠信号感知结果），也可 await 原地等待切换完成。
func change_scene(target, options: Dictionary = {}) -> void:
	var target_path := _resolve_target_path(target)

	if _is_changing:
		CoreKit.log.warn("SceneManager.change_scene: 拒绝重入，目标 '%s' 被忽略（当前正在切换中）" % target_path)
		scene_change_failed.emit(target_path, ERR_BUSY)
		return

	var validation := _validate_target(target)
	if validation != OK:
		CoreKit.log.error("SceneManager.change_scene: 非法 target '%s'" % target_path)
		scene_change_failed.emit(target_path, ERR_INVALID_PARAMETER)
		return

	var opts := _merge_options(options)
	var use_fade: bool = opts["transition"] == Transition.FADE

	_is_changing = true
	scene_changing.emit(target_path)

	if use_fade:
		_ensure_fade_overlay()
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		await _fade_to(1.0, opts["duration"], opts["color"])

	var packed_scene := _load_packed_scene(target)
	if packed_scene == null:
		CoreKit.log.error("SceneManager.change_scene: 加载失败 '%s'" % target_path)
		if use_fade:
			await _fade_to(0.0, opts["duration"], opts["color"])
			_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_is_changing = false
		scene_change_failed.emit(target_path, ERR_CANT_OPEN)
		return

	# 等一帧再动树：避免在触发调用的信号回调栈内（例如按钮 pressed 冒泡途中）直接冻结/
	# 移除仍在处理事件的旧场景节点。NONE 过渡也统一走这一步，语义与内置
	# change_scene_to_* 系列的"延迟切换"保持一致。
	await get_tree().process_frame

	var new_scene := packed_scene.instantiate()
	var old_scene := get_tree().current_scene
	get_tree().root.add_child(new_scene)
	get_tree().current_scene = new_scene
	if is_instance_valid(old_scene):
		old_scene.queue_free()

	if use_fade:
		await _fade_to(0.0, opts["duration"], opts["color"])
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_is_changing = false
	scene_changed.emit(target_path, new_scene)


func is_changing() -> bool:
	return _is_changing


func get_current_scene() -> Node:
	return get_tree().current_scene


func get_current_scene_path() -> String:
	var scene := get_tree().current_scene
	if scene == null:
		return ""
	return scene.scene_file_path


# --- 可测纯逻辑接缝（不碰场景树、不调 Log）---

## target 是 PackedScene 时检查 can_instantiate()；是 String 时检查非空、以 res:// 开头、
## 以 .tscn/.scn 结尾（不检查文件是否真实存在，存在性检查留给运行时 ResourceLoader.exists）；
## 其余类型一律无效。返回 Error 枚举值 OK 或 ERR_INVALID_PARAMETER。
func _validate_target(target) -> int:
	if target is PackedScene:
		if target.can_instantiate():
			return OK
		return ERR_INVALID_PARAMETER
	if target is String:
		if target.is_empty():
			return ERR_INVALID_PARAMETER
		if not target.begins_with("res://"):
			return ERR_INVALID_PARAMETER
		if not (target.ends_with(".tscn") or target.ends_with(".scn")):
			return ERR_INVALID_PARAMETER
		return OK
	return ERR_INVALID_PARAMETER


## String 原样返回；PackedScene 返回其 resource_path（可能为空字符串）；其余类型返回空字符串。
func _resolve_target_path(target) -> String:
	if target is String:
		return target
	if target is PackedScene:
		return target.resource_path
	return ""


## 归一化 options，始终返回包含 transition/duration/color 三键的字典。
## 未识别键忽略；已识别键类型不对或超范围一律静默回退默认值。
func _merge_options(options: Dictionary) -> Dictionary:
	var transition = options.get("transition", DEFAULT_TRANSITION)
	if not (transition is int) or transition < Transition.NONE or transition > Transition.FADE:
		transition = DEFAULT_TRANSITION

	var duration = options.get("duration", DEFAULT_FADE_DURATION)
	if not (duration is int or duration is float):
		duration = DEFAULT_FADE_DURATION
	duration = max(0.0, float(duration))

	var color = options.get("color", DEFAULT_FADE_COLOR)
	if not (color is Color):
		color = DEFAULT_FADE_COLOR

	return {"transition": transition, "duration": duration, "color": color}


# --- 内部：加载 + 淡入淡出遮罩（碰场景树/资源系统，不做 headless 断言）---

## target 是 PackedScene 直接返回；是 String 先 ResourceLoader.exists 预检再同步 load()。
## 失败（不存在，或 load() 返回非 PackedScene）返回 null。
func _load_packed_scene(target) -> PackedScene:
	if target is PackedScene:
		return target
	var path: String = target
	if not ResourceLoader.exists(path):
		return null
	var loaded := load(path)
	if loaded is PackedScene:
		return loaded
	return null


## 一次性创建常驻淡入淡出遮罩（CanvasLayer + 铺满全屏 ColorRect），幂等：已创建且节点
## 仍有效则直接返回。挂在 SceneManager 节点下，天然不受场景替换影响，跨场景常驻。
func _ensure_fade_overlay() -> void:
	if _fade_layer != null and is_instance_valid(_fade_layer):
		return

	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = _FADE_LAYER
	add_child(_fade_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = DEFAULT_FADE_COLOR
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)


## 把遮罩的可见度 Tween 到 target_alpha。color 的 RGB 写入 ColorRect.color（alpha 归一化为
## 1.0），可见度完全由 modulate:a 驱动，避免 color.a 与 modulate.a 两个 alpha 通道相乘导致
## 淡入淡出不到位。
func _fade_to(target_alpha: float, duration: float, color: Color) -> void:
	_fade_rect.color = Color(color.r, color.g, color.b, 1.0)
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", target_alpha, duration)
	await tween.finished
