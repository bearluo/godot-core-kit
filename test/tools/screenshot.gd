extends SceneTree
## 引擎内截图工具(**非 headless**,进程内 save_png,不用任何系统截屏工具/外设)。
##
## 用法:
##   godot --path . -s res://test/tools/screenshot.gd -- \
##       --w=720 --h=1280 --out=docs/vision/evidence-r1/02.png --steps=wait:30
##
## 参数:
##   --w= / --h=     目标**物理**分辨率(玩家窗口/手机屏幕的像素尺寸)
##   --out=          输出 png 路径(res:// 相对或绝对)
##   --scene=        被截场景,默认 res://game/crystal_line/main.tscn
##   --steps=        分号分隔的脚本步骤,在截图前依次执行:
##                     wait:<帧数>          等 N 帧(默认动作)
##                     run:<秒>             以真实帧推进 N 游戏秒(带渲染)
##                     sim:<秒>             以 0.05s 步进直接推进逻辑 N 秒(不等真实时间)
##                     select:<fire|ice>    选塔
##                     place:<col>,<row>[,<type>]  放塔
##                     gold:<数>            设金币(摆拍用)
##                     wave                 立即开波
##                     reset                重开一局
##
## 两种取景模式(SHOT 行的 mode= 字段标明用了哪种):
##   mode=window   —— 直接把 OS 窗口设成 WxH 截窗口纹理(最接近玩家所见)。
##   mode=viewport —— 桌面装不下该窗口(如 720x1280 高于本机可用高度)时的等价还原:
##                    按 project.godot 的 stretch 规则算出该物理尺寸对应的 viewport
##                    (scale = min(w/base_w, h/base_h),viewport = 物理尺寸 / scale),
##                    在同尺寸 SubViewport 内渲染后再缩到 WxH —— 与窗口管线同一条路径。
##
## 输出: 一行 `SHOT out=... size=WxH mode=... vp=... steps=...`,供报告与复跑核对。

const DEFAULT_SCENE := "res://game/crystal_line/main.tscn"

var _out: String = "res://docs/vision/evidence-r1/shot.png"
var _steps: String = "wait:30"
var _scene: String = DEFAULT_SCENE
var _w: int = 0
var _h: int = 0


func _initialize() -> void:
	_parse_args()
	var base := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 720)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 1280)))
	if _w <= 0:
		_w = base.x
	if _h <= 0:
		_h = base.y

	root.title = "晶核防线 · shot"
	DisplayServer.window_set_size(Vector2i(_w, _h))
	root.size = Vector2i(_w, _h)
	for _i in 3:
		await process_frame
	var mode := "window" if DisplayServer.window_get_size() == Vector2i(_w, _h) else "viewport"

	var packed: PackedScene = load(_scene)
	if packed == null:
		print("SHOT_FAIL load scene %s" % _scene)
		quit(1)
		return
	var node = packed.instantiate()

	var sub: SubViewport = null
	var vp_size := Vector2i(_w, _h)
	if mode == "window":
		root.add_child(node)
		vp_size = Vector2i(root.get_visible_rect().size)
	else:
		# 桌面放不下该窗口:按工程 stretch 规则在等价 SubViewport 里还原
		var scale := minf(float(_w) / float(base.x), float(_h) / float(base.y))
		vp_size = Vector2i(roundi(float(_w) / scale), roundi(float(_h) / scale))
		sub = SubViewport.new()
		sub.size = vp_size
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(sub)
		sub.add_child(node)
	for _i in 4:
		await process_frame

	for raw in _steps.split(";", false):
		await _run_step(node, raw.strip_edges())

	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw

	var img: Image = sub.get_texture().get_image() if sub != null else root.get_texture().get_image()
	if img.get_width() != _w or img.get_height() != _h:
		img.resize(_w, _h, Image.INTERPOLATE_LANCZOS)
	var path := _abs(_out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := img.save_png(path)
	if err != OK:
		print("SHOT_FAIL save %s err=%d" % [path, err])
		quit(1)
		return
	print("SHOT out=%s size=%dx%d mode=%s vp=%dx%d steps=%s" % [
		path, img.get_width(), img.get_height(), mode, vp_size.x, vp_size.y, _steps])
	# 退出前拆掉场景 / SubViewport,免得 Godot 在 cleanup 阶段报资源泄漏(会带出非 0 退出码)
	node.queue_free()
	if sub != null:
		sub.queue_free()
	for _i in 3:
		await process_frame
	quit(0)


func _run_step(node, step: String) -> void:
	if step.is_empty():
		return
	var head := step
	var arg := ""
	var sep := step.find(":")
	if sep >= 0:
		head = step.substr(0, sep)
		arg = step.substr(sep + 1)
	match head:
		"wait":
			for _i in maxi(1, int(arg)):
				await process_frame
		"run":
			var target := float(arg)
			var acc := 0.0
			while acc < target:
				await process_frame
				acc += root.get_process_delta_time()
		"sim":
			var secs := float(arg)
			var t := 0.0
			while t < secs and not node.sim.is_round_over():
				node.sim.tick(0.05)
				t += 0.05
			await process_frame
		"select":
			node._select(StringName(arg))
		"place":
			# ⚠️ 走 _try_place(玩家点格子的那条路),不是直接调 sim.place_tower。
			# 摆拍走后门就证明不了前门能用:直接调 sim 会绕过「点已有塔 = 升级」的分支,
			# 截图里于是永远看不到升级效果,而那正是要取证的东西。
			var p := arg.split(",")
			if p.size() > 2:
				node._select(StringName(p[2]))
			node._try_place(Vector2i(int(p[0]), int(p[1])))
			await process_frame
		"gold":
			node.sim.gold = int(arg)
			await process_frame
		"wave":
			node.sim.start_wave()
			await process_frame
		"reset":
			node._on_reset()
			await process_frame
		_:
			print("SHOT_WARN unknown step %s" % step)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--steps="):
			_steps = a.substr(8)
		elif a.begins_with("--scene="):
			_scene = a.substr(8)
		elif a.begins_with("--w="):
			_w = int(a.substr(4))
		elif a.begins_with("--h="):
			_h = int(a.substr(4))


func _abs(p: String) -> String:
	if p.begins_with("res://") or p.begins_with("user://"):
		return ProjectSettings.globalize_path(p)
	if p.is_absolute_path() and p.length() > 2 and p[1] == ":":
		return p
	return ProjectSettings.globalize_path("res://" + p)
