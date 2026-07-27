extends SceneTree
## 引擎内截图工具(非 headless)。在进程内 save_png,可复现。
## 用法:
##   godot --path . -s res://test/tools/screenshot.gd -- --out=docs/vision/fix-r1-evidence/hud-720x1280.png --size=720x1280
##   godot --path . -s res://test/tools/screenshot.gd -- --out=... --size=540x960 --scenario=combat
## 场景: boot | placed | combat | result_defeat
## 禁止 computer-use / 系统截屏。

func _initialize() -> void:
	var args := _parse_args()
	var size_s: String = str(args.get("size", "720x1280"))
	var out_path: String = str(args.get("out", "user://crystal_line_shot.png"))
	var scenario: String = str(args.get("scenario", "boot"))
	var parts := size_s.split("x")
	if parts.size() != 2:
		print("SHOT_FAIL bad size=%s" % size_s)
		quit(1)
		return
	var w := int(parts[0])
	var h := int(parts[1])
	DisplayServer.window_set_size(Vector2i(w, h))
	# 给窗口/渲染一帧缓冲
	await process_frame
	await process_frame

	var packed: PackedScene = load("res://game/crystal_line/main.tscn")
	if packed == null:
		print("SHOT_FAIL load main.tscn")
		quit(1)
		return
	var scene = packed.instantiate()
	root.add_child(scene)
	# 等 Control 布局稳定
	for _i in 8:
		await process_frame

	await _apply_scenario(scene, scenario)
	for _i in 10:
		await process_frame

	var img: Image = root.get_texture().get_image()
	if img == null:
		print("SHOT_FAIL get_image null (did you pass --headless?)")
		quit(1)
		return
	# 确保目录
	var abs_out := out_path
	if out_path.begins_with("res://"):
		abs_out = ProjectSettings.globalize_path(out_path)
	elif not out_path.begins_with("user://") and not out_path.contains(":") and not out_path.begins_with("/"):
		abs_out = ProjectSettings.globalize_path("res://").path_join(out_path)
	var dir_path := abs_out.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	var err := img.save_png(abs_out)
	if err != OK:
		print("SHOT_FAIL save_png err=%d path=%s" % [err, abs_out])
		quit(1)
		return
	print("SHOT_OK path=%s size=%dx%d scenario=%s" % [abs_out, w, h, scenario])
	scene.queue_free()
	await process_frame
	quit(0)


func _apply_scenario(scene, scenario: String) -> void:
	match scenario:
		"placed":
			scene.sim.place_tower(1, 6, &"fire")
			scene.sim.place_tower(1, 4, &"ice")
			scene.juice = 1.0
			scene.juice_cell = Vector2i(1, 6)
			scene.msg = "召唤! 笃定落下。"
			scene._refresh_ui()
		"combat":
			scene.sim.gold = 200
			scene.sim.place_tower(1, 6, &"fire")
			scene.sim.place_tower(1, 4, &"ice")
			scene.sim.place_tower(3, 3, &"fire")
			scene.sim.start_wave()
			# 推进到有怪+有弹道
			for _i in 80:
				scene.sim.tick(0.05)
				if scene.sim.enemy_count() > 0 and scene.sim.shots.size() > 0:
					break
			scene.msg = "第 %d 波 · 交火中" % scene.sim.wave
			scene._refresh_ui()
		"result_defeat":
			scene.sim.reset()
			var g := 0
			while not scene.sim.is_defeat() and g < 10000:
				g += 1
				if not scene.sim.wave_active and scene.sim.outcome == "":
					if not scene.sim.start_wave():
						break
				scene.sim.tick(0.05)
			scene.msg = "破核了——复盘站位再来。"
			scene._prev_event = "defeat"
			scene._show_result(true if scene.sim.is_victory() else false)
			scene._refresh_ui()
		"result_victory":
			scene.sim.reset()
			scene.sim.gold = 2000
			scene.sim.core_hp = 20
			for y in range(1, 7):
				for x in [1, 3]:
					if scene.sim.can_place(x, y):
						scene.sim.place_tower(x, y, &"fire" if x == 1 else &"ice")
			var guard := 0
			while not scene.sim.is_victory() and guard < 15000:
				guard += 1
				if not scene.sim.wave_active and scene.sim.outcome == "":
					if not scene.sim.start_wave():
						break
				scene.sim.tick(0.05)
			scene._show_result(scene.sim.is_victory())
			scene._refresh_ui()
		_:
			# boot: 初始画面
			scene._refresh_ui()


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var body := a.substr(2)
			var eq := body.find("=")
			if eq >= 0:
				out[body.substr(0, eq)] = body.substr(eq + 1)
			else:
				out[body] = true
	# 兼容部分环境把参数放在完整 cmdline
	for a in OS.get_cmdline_args():
		if a.begins_with("--out=") or a.begins_with("--size=") or a.begins_with("--scenario="):
			var body := a.substr(2)
			var eq := body.find("=")
			if eq >= 0:
				out[body.substr(0, eq)] = body.substr(eq + 1)
	return out
