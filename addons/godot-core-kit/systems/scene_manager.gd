extends Node
## SceneManager —— godot-core-kit 全局场景切换单例（首版：仅替换，无场景栈）。
##
## 由 CoreKit 门面在 _init 中构造并 add_child，不再是独立注册的 project autoload，
## 经 CoreKit.scenes 访问（唯一 autoload 是 CoreKit 本身）。统一入口
## change_scene(target, options) 把"替换当前活动场景"这件事从零散的
## get_tree().change_scene_to_*() 调用收敛为一个可选带淡入淡出过渡、带切换生命周期信号
## 的协程。默认同步 load()；options.preload 时经注入的 ResourceManager 预载直接依赖（它在
## Web 走分帧通道、桌面走线程通道，对本类透明）。第 2 参接受 KitTransition（FADE/SLIDE/MASK）
## 或 legacy options 字典，默认无过渡（CanvasLayer + ColorRect + Tween 遮罩常驻本节点下、不受
## 场景替换影响）。拒绝重入
## （_is_changing 守卫，cover 期间同样占用），不做排队。
##
## 用法：
##   CoreKit.scenes.change_scene("res://levels/level_2.tscn")
##   CoreKit.scenes.change_scene(preload("res://levels/boss.tscn"), {"transition": CoreKit.scenes.Transition.FADE})
##   CoreKit.scenes.change_scene(path, fade, {"preload": true, "loading_screen": screen, "after_swap": place_player})
##   await CoreKit.scenes.change_scene(...)   # 原地等待切换完成

signal scene_changing(target_path: String)
signal scene_changed(scene_path: String, scene: Node)
signal scene_change_failed(target_path: String, error: int)  # error 为 Error 枚举取值
## options.preload 时转发预载进度；单位是资源个数（单线程平台拿不到单个资源内部的进度）。
signal scene_load_progress(loaded: int, total: int)

enum Transition { NONE, FADE }  # legacy Dictionary API 用;KitTransition.Type 为新规范
enum _Phase { COVER, REVEAL }

const DEFAULT_TRANSITION := Transition.NONE
const DEFAULT_FADE_DURATION := 0.3
const DEFAULT_FADE_COLOR := Color.BLACK
const _FADE_LAYER := 4096  # = CoreKit.layers.TRANSITION(权威保留带常量,见 systems/layer_manager.gd)

const _MASK_SHADER := preload("res://addons/godot-core-kit/transitions/kit_mask.gdshader")

var _is_changing := false
var _covered := false
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _mask_material: ShaderMaterial
## bind_resources 注入的 ResourceManager;untyped,未注入时 preload 选项退化为普通同步加载。
var _res = null


func bind_resources(res) -> void:
	_res = res


func _ready() -> void:
	_ensure_fade_overlay()


# --- 公开运行时 API ---

## 把当前活动场景替换为 target。target 为 res:// 路径（String）或 PackedScene。
## transition 接受 KitTransition，或 legacy options 字典（{transition/duration/color}，未识别键
## 静默回退默认），默认 {} = 无过渡。options 管转场以外的能力（未识别键静默忽略）：
##   preload: bool          —— 只对路径形式生效：遮住后经 CoreKit.res 预载直接依赖，发 scene_load_progress
##   loading_screen: PackedScene —— 预载期间挂在遮罩之上；kit 不调它任何方法，它自己连 scene_load_progress
##   before_swap: Callable  —— 已遮住、旧场景还在（存档、记录状态）；可为协程，会被 await
##   after_swap: Callable(new_scene) —— 新场景已是 current_scene、还没揭开（挪玩家、设出生点）
## 协程：可 fire-and-forget（靠信号感知结果），也可 await 原地等待切换完成。
func change_scene(target, transition = {}, options: Dictionary = {}) -> void:
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

	var t := _resolve_transition(transition)
	var animated: bool = t.type != KitTransition.Type.NONE

	_is_changing = true
	scene_changing.emit(target_path)

	if animated:
		_ensure_fade_overlay()
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		await _play_transition(t, _Phase.COVER)

	var screen: Node = null
	var fresh: Array = []
	if options.get("preload", false) == true and target is String:
		screen = _mount_loading_screen(options.get("loading_screen"))
		if screen != null:
			await get_tree().process_frame  # 让加载屏先画出来再开始加载
		fresh = await _preload_deps(target)

	var packed_scene := _load_packed_scene(target)
	if packed_scene == null:
		CoreKit.log.error("SceneManager.change_scene: 加载失败 '%s'" % target_path)
		_release(fresh)
		_unmount(screen)
		if animated:
			await _play_transition(t, _Phase.REVEAL)
			_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_is_changing = false
		scene_change_failed.emit(target_path, ERR_CANT_OPEN)
		return

	# 等一帧再动树：避免在触发调用的信号回调栈内（例如按钮 pressed 冒泡途中）直接冻结/
	# 移除仍在处理事件的旧场景节点。NONE 过渡也统一走这一步，语义与内置
	# change_scene_to_* 系列的"延迟切换"保持一致。
	await get_tree().process_frame

	await _call_hook(options.get("before_swap"), [])

	var new_scene := packed_scene.instantiate()
	var old_scene := get_tree().current_scene
	get_tree().root.add_child(new_scene)
	get_tree().current_scene = new_scene
	if is_instance_valid(old_scene):
		old_scene.queue_free()

	await _call_hook(options.get("after_swap"), [new_scene])

	_release(fresh)  # 新场景实例自己持有引用，kit 不再长期钉住整张关卡的资源
	_unmount(screen)

	if animated:
		await _play_transition(t, _Phase.REVEAL)
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_is_changing = false
	scene_changed.emit(target_path, new_scene)


## 对当前场景路径重做一次 change_scene（转场和 options 照传）。当前场景不是从文件来的
## （路径为空）→ scene_change_failed("", ERR_UNAVAILABLE)。
func reload_scene(transition = {}, options: Dictionary = {}) -> void:
	var path := get_current_scene_path()
	if path.is_empty():
		CoreKit.log.warn("SceneManager.reload_scene: 当前场景没有文件路径，无法重开")
		scene_change_failed.emit("", ERR_UNAVAILABLE)
		return
	await change_scene(path, transition, options)


## 同场景内的黑屏（如传送）：遮住并占用切换守卫，直到 reveal。期间 change_scene 返回 ERR_BUSY。
func cover(transition = {}) -> void:
	if _is_changing:
		CoreKit.log.warn("SceneManager.cover: 正在切换或已遮住，忽略")
		return
	_is_changing = true
	_covered = true
	var t := _resolve_transition(transition)
	if not t.is_none():
		_ensure_fade_overlay()
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		await _play_transition(t, _Phase.COVER)


## 揭开 cover 的遮罩并释放切换守卫。没有先 cover：warn 并返回。
func reveal(transition = {}) -> void:
	if not _covered:
		CoreKit.log.warn("SceneManager.reveal: 没有先 cover，忽略")
		return
	var t := _resolve_transition(transition)
	if not t.is_none():
		await _play_transition(t, _Phase.REVEAL)
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_covered = false
	_is_changing = false


func is_changing() -> bool:
	return _is_changing


func get_current_scene() -> Node:
	return get_tree().current_scene


func get_current_scene_path() -> String:
	var scene := get_tree().current_scene
	if scene == null:
		return ""
	return scene.scene_file_path


# --- 可测纯逻辑接缝（不碰场景树、不调 CoreKit.log）---

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


## 把 change_scene 第 2 参归一为 KitTransition（纯逻辑，不碰场景树）。KitTransition→normalized()；
## Dictionary→复用 _merge_options 走 legacy 路径映射；其余类型（含非法）→NONE。
func _resolve_transition(arg) -> KitTransition:
	if arg is KitTransition:
		return arg.normalized()
	var t := KitTransition.new()
	if arg is Dictionary:
		var opts := _merge_options(arg)
		t.type = _legacy_transition_to_type(opts["transition"])
		t.duration = opts["duration"]
		t.color = opts["color"]
	else:
		t.type = KitTransition.Type.NONE
	return t.normalized()


## ResourceLoader.get_dependencies 的一项 → res:// 路径。4.x 可能是 "uid://…::Type::res://…"
## 三段式，取 res:// 那段；纯路径原样返回。
func _dep_path(dep: String) -> String:
	for part in dep.split("::"):
		if part.begins_with("res://"):
			return part
	return dep


## legacy Transition 枚举 → KitTransition.Type（FADE→FADE，其余→NONE；SLIDE 仅 KitTransition 可达）。
func _legacy_transition_to_type(legacy: int) -> int:
	match legacy:
		Transition.FADE:
			return KitTransition.Type.FADE
		_:
			return KitTransition.Type.NONE


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


## 按 t.type 驱动常驻遮罩色板演一段（COVER 覆盖 / REVEAL 揭开）。碰视口/场景树，运行时驱动，
## 不做 headless 断言。每次 COVER 都完整重置遮罩起始态，故上次转场遗留态不影响本次。
## FADE 走 modulate:a（色板全屏、alpha 0↔1）；SLIDE 走 position（全屏不透明色板按 direction 掠过）。
func _play_transition(t: KitTransition, phase: int) -> void:
	match t.type:
		KitTransition.Type.FADE:
			_fade_rect.material = null
			_fade_rect.color = Color(t.color.r, t.color.g, t.color.b, 1.0)
			if phase == _Phase.COVER:
				_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
				_fade_rect.position = Vector2.ZERO
				_fade_rect.modulate.a = 0.0
			var target_a: float = 1.0 if phase == _Phase.COVER else 0.0
			var tween := create_tween().set_ease(t.ease_type).set_trans(t.trans_type)
			tween.tween_property(_fade_rect, "modulate:a", target_a, t.duration)
			await tween.finished
		KitTransition.Type.SLIDE:
			_fade_rect.material = null
			var size := _overlay_size()
			_fade_rect.color = Color(t.color.r, t.color.g, t.color.b, 1.0)
			_fade_rect.modulate.a = 1.0
			_fade_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
			_fade_rect.size = size
			var from_pos: Vector2 = t.slide_cover_from(size) if phase == _Phase.COVER else Vector2.ZERO
			var to_pos: Vector2 = Vector2.ZERO if phase == _Phase.COVER else t.slide_reveal_to(size)
			_fade_rect.position = from_pos
			var tween := create_tween().set_ease(t.ease_type).set_trans(t.trans_type)
			tween.tween_property(_fade_rect, "position", to_pos, t.duration)
			await tween.finished
		KitTransition.Type.MASK:
			var mat := _mask_mat()
			mat.set_shader_parameter("mask", t.mask)
			mat.set_shader_parameter("smoothness", t.smoothness)
			mat.set_shader_parameter("invert", t.invert)
			mat.set_shader_parameter("cover_color", t.color)
			_fade_rect.material = mat
			_fade_rect.color = Color.WHITE
			_fade_rect.modulate.a = 1.0
			if phase == _Phase.COVER:
				_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
				_fade_rect.position = Vector2.ZERO
				mat.set_shader_parameter("progress", 0.0)
			# ponytail: 首次 MASK 有一帧 shader 编译卡顿(落在 COVER 第一帧,仍透明);真成问题时启动时 0 时长 cover/reveal 预热
			var target_p: float = 1.0 if phase == _Phase.COVER else 0.0
			var tween := create_tween().set_ease(t.ease_type).set_trans(t.trans_type)
			tween.tween_property(mat, "shader_parameter/progress", target_p, t.duration)
			await tween.finished
		_:
			pass


## 遮罩尺寸 = 当前视口可见矩形；无视口时回退 1080p（仅运行时用）。
func _overlay_size() -> Vector2:
	var vp := get_viewport()
	if vp != null:
		return vp.get_visible_rect().size
	return Vector2(1920, 1080)


func _mask_mat() -> ShaderMaterial:
	if _mask_material == null:
		_mask_material = ShaderMaterial.new()
		_mask_material.shader = _MASK_SHADER
	return _mask_material


## 当前 MASK 进度(测试/调试用);从没用过 MASK 时为 0。
func _mask_progress() -> float:
	if _mask_material == null:
		return 0.0
	return float(_mask_material.get_shader_parameter("progress"))


## 实例化加载屏挂到遮罩之上;没传或类型不对返回 null。
func _mount_loading_screen(screen) -> Node:
	if not (screen is PackedScene):
		return null
	_ensure_fade_overlay()
	var node: Node = screen.instantiate()
	_fade_layer.add_child(node)
	return node


func _unmount(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.get_parent().remove_child(node)
		node.queue_free()


## 经 CoreKit.res 预载 path 的直接依赖并转发进度,等整批完成。返回本次新进缓存的路径
## (切完场景后要 release 的那些)。未注入 ResourceManager → 什么都不做。
## ponytail: 只展开一层依赖,进度格数偏少;单个依赖很大时再考虑递归展开
func _preload_deps(path: String) -> Array:
	if _res == null:
		return []
	var deps: Array = []
	for dep in ResourceLoader.get_dependencies(path):
		deps.append(_dep_path(dep))
	var fresh := deps.filter(func(p): return not _res.is_cached(p))
	var done := [false]
	var on_done := func() -> void: done[0] = true
	var on_progress := func(loaded: int, total: int) -> void: scene_load_progress.emit(loaded, total)
	_res.batch_completed.connect(on_done)
	_res.batch_progress.connect(on_progress)
	_res.preload_batch(deps)
	# 用标志轮询而不是 await 信号:未注入 ticker 的分帧降级会在 preload_batch 内同步发完成信号
	while not done[0]:
		await get_tree().process_frame
	_res.batch_completed.disconnect(on_done)
	_res.batch_progress.disconnect(on_progress)
	return fresh


func _release(paths: Array) -> void:
	for p in paths:
		_res.release(p)


func _call_hook(hook, args: Array) -> void:
	if hook is Callable and hook.is_valid():
		await hook.callv(args)
