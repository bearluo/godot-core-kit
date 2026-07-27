extends SceneTree
## 《晶核防线》逻辑 headless 断言
## 运行: godot --headless --path . -s res://test/test_crystal_line_sim.gd

func _initialize() -> void:
	var failures := 0
	var Sim = load("res://game/crystal_line/sim/crystal_line_sim.gd")
	var sim = Sim.new()

	# 1. 初始状态
	if sim.gold != 80 or sim.core_hp != 10:
		print("FAIL 1: 初始 gold/hp 不对 gold=%d hp=%d" % [sim.gold, sim.core_hp])
		failures += 1

	# 2. 不能放路径
	if sim.place_tower(sim.PATH_COL, 3, &"fire"):
		print("FAIL 2: 路径上不应能放塔")
		failures += 1

	# 3. 能放侧格并扣金
	if not sim.place_tower(1, 3, &"fire"):
		print("FAIL 3: 侧格应能放火塔 event=%s" % sim.last_event)
		failures += 1
	if sim.gold != 40 or sim.tower_count() != 1:
		print("FAIL 3b: 扣金/计数 gold=%d towers=%d" % [sim.gold, sim.tower_count()])
		failures += 1

	# 4. 金币不足拒绝
	sim.gold = 10
	if sim.place_tower(3, 3, &"ice"):
		print("FAIL 4: 金币不足仍放置")
		failures += 1
	if sim.last_event != "no_gold":
		print("FAIL 4b: last_event 应为 no_gold 实际 %s" % sim.last_event)
		failures += 1

	# 5. 开波 + 刷怪 + 塔击杀/清波(给足塔火力)
	sim.reset()
	sim.place_tower(1, 2, &"fire")
	sim.place_tower(1, 3, &"fire")
	sim.place_tower(1, 4, &"fire")
	sim.place_tower(3, 2, &"ice")
	sim.place_tower(3, 3, &"fire")
	sim.gold = 200  # 不受限
	if not sim.start_wave():
		print("FAIL 5: start_wave 失败")
		failures += 1
	# 模拟足够长时间让第一波结束
	for _i in 600:
		sim.tick(0.05)
		if sim.waves_cleared >= 1:
			break
	if sim.waves_cleared < 1:
		print("FAIL 5b: 第一波未清完 enemies=%d spawn_left=%d core=%d" % [
			sim.enemy_count(), sim.spawn_left, sim.core_hp])
		failures += 1
	else:
		print("OK wave_clear gold=%d earned=%d" % [sim.gold, sim.gold_earned])

	# 6. 无塔时连续开波,漏怪应破核
	sim.reset()
	for _w in 5:
		if sim.is_game_over():
			break
		if not sim.wave_active:
			sim.start_wave()
		for _j in 400:
			sim.tick(0.05)
			if sim.is_game_over():
				break
	if not sim.is_game_over():
		print("FAIL 6: 无塔应破核 core=%d waves_cleared=%d" % [sim.core_hp, sim.waves_cleared])
		failures += 1

	# 7. 重复放置拒绝
	sim.reset()
	sim.place_tower(1, 1, &"fire")
	if sim.place_tower(1, 1, &"ice"):
		print("FAIL 7: 同格重复放置应失败")
		failures += 1

	if failures == 0:
		print("test_crystal_line_sim: ALL PASS")
		quit(0)
	else:
		print("test_crystal_line_sim: %d FAILURE(S)" % failures)
		quit(1)
