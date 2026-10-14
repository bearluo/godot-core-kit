extends SceneTree
## SceneManager 运行时流程断言(经 CoreKit autoload 跑真实场景切换):
## 钩子顺序 / cover-reveal 守卫 / reload_scene / 预载进度与 release / MASK 后遮罩复位。
## 运行:godot --headless --path . -s res://test/test_scene_flow.gd

const SCENE_A := "res://test/fixtures/scene_a.tscn"
const SCENE_B := "res://test/fixtures/scene_b.tscn"
const DEP_1 := "res://test/fixtures/scene_dep_1.tres"
const DEP_2 := "res://test/fixtures/scene_dep_2.tres"

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL " + msg)
		failures += 1


func _run() -> void:
	await process_frame
	var core = root.get_node("CoreKit")
	var sm = core.scenes
	var KT = load("res://addons/godot-core-kit/transitions/kit_transition.gd")

	# 1. reload_scene:当前场景不是从文件来的 → ERR_UNAVAILABLE
	var fails: Array = []
	var on_fail := func(p, e): fails.append(e)
	sm.scene_change_failed.connect(on_fail)
	await sm.reload_scene()
	_check(fails == [ERR_UNAVAILABLE], "1: reload_scene 无路径应发 ERR_UNAVAILABLE,得到 %s" % [fails])

	# 2. 钩子顺序 + 协程钩子被等待 + after_swap 拿到的是 current_scene
	var log: Array = []
	var on_changing := func(_p): log.append("changing")
	var on_changed := func(_p, _s): log.append("changed")
	sm.scene_changing.connect(on_changing)
	sm.scene_changed.connect(on_changed)
	var before := func() -> void:
		await process_frame
		log.append("before")
	var after := func(s: Node) -> void:
		log.append("after:%s" % (s == current_scene))
	await sm.change_scene(SCENE_A, {}, {"before_swap": before, "after_swap": after})
	_check(log == ["changing", "before", "after:true", "changed"], "2: 钩子顺序错 %s" % [log])
	sm.scene_changing.disconnect(on_changing)
	sm.scene_changed.disconnect(on_changed)

	# 3. reload_scene 有路径时重开当前场景(新实例)
	var old_a := current_scene
	await sm.reload_scene()
	_check(current_scene != old_a and current_scene.scene_file_path == SCENE_A, "3: reload_scene 应重开 scene_a")

	# 4. cover → change_scene 被拒 ERR_BUSY → reveal 后恢复;单独 reveal 只 warn
	fails.clear()
	var fade = KT.new()
	fade.duration = 0.0
	await sm.cover(fade)
	await sm.change_scene(SCENE_B)
	_check(fails == [ERR_BUSY], "4: cover 期间 change_scene 应 ERR_BUSY,得到 %s" % [fails])
	await sm.reveal(fade)
	_check(not sm.is_changing(), "4: reveal 后应不在切换中")
	await sm.reveal(fade)  # 无 cover:只 warn,不崩
	_check(not sm.is_changing(), "4: 单独 reveal 不应改变状态")

	# 5. 预载:进度 total = 直接依赖数、最后 loaded == total;新进缓存的被 release
	var res = core.res
	res.clear()
	var prog: Array = []
	var on_prog := func(l, t): prog.append([l, t])
	sm.scene_load_progress.connect(on_prog)
	var screen := PackedScene.new()
	var screen_root := Control.new()
	screen_root.name = "LoadingScreen"
	screen.pack(screen_root)
	screen_root.free()
	var seen_screen := [false]
	var before_b := func() -> void:
		seen_screen[0] = sm.find_child("LoadingScreen", true, false) != null
	await sm.change_scene(SCENE_B, {}, {"preload": true, "loading_screen": screen, "before_swap": before_b})
	sm.scene_load_progress.disconnect(on_prog)
	_check(not prog.is_empty() and prog[-1] == [2, 2], "5: 预载进度末项应为 [2, 2],得到 %s" % [prog])
	_check(seen_screen[0], "5: 换场景前加载屏应已挂上")
	_check(sm.find_child("LoadingScreen", true, false) == null, "5: 切完加载屏应被移除")
	_check(not res.is_cached(DEP_1) and not res.is_cached(DEP_2), "5: 预载新进缓存的依赖应被 release")
	_check(current_scene.scene_file_path == SCENE_B, "5: 应已切到 scene_b")

	# 6. 预载前已在缓存的依赖保留
	res.clear()
	res.get_resource(DEP_1)
	await sm.change_scene(SCENE_B, {}, {"preload": true})
	_check(res.is_cached(DEP_1), "6: 预载前已缓存的 DEP_1 应保留")
	_check(not res.is_cached(DEP_2), "6: 新进缓存的 DEP_2 应被 release")

	# 7. MASK cover→reveal 后遮罩完全透明;之后 FADE 时 material 已清掉
	var mask = KT.new()
	mask.type = KT.Type.MASK
	mask.mask = GradientTexture2D.new()
	mask.duration = 0.05
	await sm.change_scene(SCENE_A, mask)
	_check(sm._mask_progress() == 0.0, "7: MASK 揭开后 progress 应为 0,得到 %s" % sm._mask_progress())
	fade.duration = 0.05
	await sm.change_scene(SCENE_B, fade)
	_check(sm._fade_rect.material == null, "7: FADE 时 material 应被清掉")
	_check(sm._fade_rect.modulate.a == 0.0, "7: FADE 揭开后应完全透明")

	sm.scene_change_failed.disconnect(on_fail)
	if failures == 0:
		print("test_scene_flow: ALL PASS")
		quit(0)
	else:
		print("test_scene_flow: %d FAILURE(S)" % failures)
		quit(1)
