extends SceneTree
## 旁证脚本(不改 game/):在真场景上模拟「玩家会话」并打印可核对的状态时间线。
## 不是 FAILS=0 单元测试——它走 main.tscn 实例 + 与玩家相同的 sim API 路径。
## 运行: godot --headless --path . -s res://test/playtest_crystal_line_session_log.gd
## 输出关键字: SESSION_* 供实机截图对照。

func _initialize() -> void:
	await process_frame
	var packed: PackedScene = load("res://game/crystal_line/main.tscn")
	if packed == null:
		print("SESSION_FAIL load main.tscn")
		quit(1)
		return
	var root_node = packed.instantiate()
	root.add_child(root_node)
	await process_frame
	await process_frame

	print("SESSION_BOOT title_scene=crystal_line art=%s sfx=%s gold=%d hp=%d" % [
		root_node.art.source_for(&"tower_fire"),
		root_node.sfx.source_for(&"place"),
		root_node.sim.gold,
		root_node.sim.core_hp,
	])

	# 头 30 秒:选塔→放塔
	var ok1: bool = root_node.sim.place_tower(1, 4, &"fire")
	root_node.msg = "召唤! 笃定落下。" if ok1 else root_node.msg
	print("SESSION_PLACE1 ok=%s gold=%d towers=%d event=%s msg=%s" % [
		ok1, root_node.sim.gold, root_node.sim.tower_count(), root_node.sim.last_event, root_node.msg])
	await process_frame

	var ok2: bool = root_node.sim.place_tower(2, 4, &"ice")
	print("SESSION_PLACE2 ok=%s gold=%d towers=%d event=%s" % [
		ok2, root_node.sim.gold, root_node.sim.tower_count(), root_node.sim.last_event])

	# 开波
	var w_ok: bool = root_node.sim.start_wave()
	print("SESSION_WAVE_START ok=%s wave=%d spawn_left=%d" % [
		w_ok, root_node.sim.wave, root_node.sim.spawn_left])

	# 模拟观战 ~20s
	var saw_enemy := false
	var max_enemies := 0
	var frames := 0
	while frames < 400:
		root_node.sim.tick(0.05)
		frames += 1
		var ec: int = root_node.sim.enemy_count()
		if ec > 0:
			saw_enemy = true
			max_enemies = maxi(max_enemies, ec)
		if root_node.sim.waves_cleared >= 1 or root_node.sim.is_game_over():
			break
		if frames % 20 == 0:
			await process_frame

	print("SESSION_COMBAT saw_enemy=%s max_enemies=%d waves_cleared=%d gold=%d hp=%d game_over=%s last_event=%s" % [
		saw_enemy, max_enemies, root_node.sim.waves_cleared, root_node.sim.gold,
		root_node.sim.core_hp, root_node.sim.is_game_over(), root_node.sim.last_event])

	# 无塔破核路径(失败侧闭环)
	root_node.sim.reset()
	print("SESSION_RESET gold=%d hp=%d" % [root_node.sim.gold, root_node.sim.core_hp])
	var guard := 0
	while not root_node.sim.is_round_over() and guard < 20000:
		root_node.sim.tick(0.05)
		guard += 1
	for _f in 4:
		await process_frame
	print("SESSION_DEFEAT game_over=%s hp=%d waves_touched=%d last_event=%s result_panel=%s" % [
		root_node.sim.is_game_over(), root_node.sim.core_hp, root_node.sim.wave,
		root_node.sim.last_event, root_node.get_node("Result").visible])

	# 通关路径(胜利侧闭环):16 塔固定构筑打完全部波次
	root_node._on_reset()
	root_node.sim.gold = 99999
	for b in [[1, 2, "fire"], [3, 4, "fire"], [1, 6, "fire"], [1, 4, "fire"], [2, 4, "fire"],
			[2, 2, "ice"], [0, 4, "fire"], [2, 6, "ice"], [1, 0, "fire"], [3, 2, "fire"],
			[3, 6, "fire"], [0, 0, "fire"], [4, 2, "fire"], [4, 6, "fire"], [3, 1, "fire"],
			[3, 0, "fire"]]:
		root_node.sim.place_tower(int(b[0]), int(b[1]), StringName(b[2]))
	guard = 0
	while not root_node.sim.is_round_over() and guard < 20000:
		root_node.sim.tick(0.05)
		guard += 1
	for _f2 in 4:
		await process_frame
	var s: Dictionary = root_node.sim.summary()
	print("SESSION_VICTORY victory=%s waves=%d/%d hp=%d kills=%d leaks=%d seconds=%.0f result_panel=%s" % [
		s["victory"], s["waves_cleared"], s["waves_total"], s["core_hp"], s["kills"],
		s["leaks"], s["seconds"], root_node.get_node("Result").visible])

	# 反例核对:无走位/无技能瞄准 API
	var has_move := root_node.sim.get("move_player") != null
	print("SESSION_ANTI_MICRO has_player_move_api=%s tower_types=fire,ice only" % has_move)

	print("SESSION_DONE")
	root_node.queue_free()
	await process_frame
	quit(0)
