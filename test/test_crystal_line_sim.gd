extends SceneTree
## 《晶核防线》逻辑 headless 断言
## 运行: godot --headless --path . -s res://test/test_crystal_line_sim.gd

func _initialize() -> void:
	var failures := 0
	var Sim = load("res://game/crystal_line/sim/crystal_line_sim.gd")
	var sim = Sim.new()

	# 1. 初始状态(开局可同时买火+冰: 100 >= 40+45)
	if sim.gold != 100 or sim.core_hp != 10:
		print("FAIL 1: 初始 gold/hp 不对 gold=%d hp=%d" % [sim.gold, sim.core_hp])
		failures += 1
	if sim.gold < 40 + 45:
		print("FAIL 1b: 起始金不足以同时买火+冰 gold=%d" % sim.gold)
		failures += 1

	# 2. 不能放路径(蜿蜒 PATH 上任意格)
	var path_cell: Vector2i = sim.PATH[3]
	if sim.place_tower(path_cell.x, path_cell.y, &"fire"):
		print("FAIL 2: 路径上不应能放塔 cell=%s" % path_cell)
		failures += 1

	# 3. 能放侧格并扣金
	if not sim.place_tower(1, 6, &"fire"):
		print("FAIL 3: 侧格应能放火塔 event=%s" % sim.last_event)
		failures += 1
	if sim.gold != 60 or sim.tower_count() != 1:
		print("FAIL 3b: 扣金/计数 gold=%d towers=%d" % [sim.gold, sim.tower_count()])
		failures += 1

	# 3c. 开局第二座冰塔(CL-007)
	if not sim.place_tower(3, 6, &"ice"):
		print("FAIL 3c: 起始金应能再放冰塔 event=%s gold=%d" % [sim.last_event, sim.gold])
		failures += 1
	if sim.gold != 15 or sim.tower_count() != 2:
		print("FAIL 3d: 火+冰后 gold=%d towers=%d" % [sim.gold, sim.tower_count()])
		failures += 1

	# 4. 金币不足拒绝
	sim.gold = 10
	if sim.place_tower(1, 4, &"ice"):
		print("FAIL 4: 金币不足仍放置")
		failures += 1
	if sim.last_event != "no_gold":
		print("FAIL 4b: last_event 应为 no_gold 实际 %s" % sim.last_event)
		failures += 1

	# 5. 开波 + 刷怪 + 塔击杀/清波(给足塔火力)
	sim.reset()
	sim.gold = 500
	# 贴路径拐弯的强覆盖
	for cell in [Vector2i(1, 6), Vector2i(1, 4), Vector2i(1, 3), Vector2i(1, 1),
			Vector2i(3, 6), Vector2i(3, 3), Vector2i(3, 1)]:
		if sim.can_place(cell.x, cell.y):
			sim.place_tower(cell.x, cell.y, &"fire" if cell.x == 1 else &"ice")
	if not sim.start_wave():
		print("FAIL 5: start_wave 失败")
		failures += 1
	for _i in 800:
		sim.tick(0.05)
		if sim.waves_cleared >= 1:
			break
	if sim.waves_cleared < 1:
		print("FAIL 5b: 第一波未清完 enemies=%d spawn_left=%d core=%d" % [
			sim.enemy_count(), sim.spawn_left, sim.core_hp])
		failures += 1
	else:
		print("OK wave_clear gold=%d earned=%d leaks=%d" % [sim.gold, sim.gold_earned, sim.leaks])

	# 5c. 首波双塔压力(有把握的紧张: 火+冰合理站位,漏怪少)
	sim.reset()
	sim.place_tower(1, 6, &"fire")
	sim.place_tower(1, 4, &"ice")
	sim.start_wave()
	for _i in 800:
		sim.tick(0.05)
		if sim.waves_cleared >= 1 or sim.is_game_over():
			break
	if sim.waves_cleared < 1:
		print("FAIL 5c: 火+冰应能清第一波 leaks=%d hp=%d enemies=%d" % [
			sim.leaks, sim.core_hp, sim.enemy_count()])
		failures += 1
	elif sim.leaks > 3:
		print("FAIL 5d: 首波漏怪过多(应有把握的紧张) leaks=%d" % sim.leaks)
		failures += 1
	else:
		print("OK first_wave_dual_tower leaks=%d hp=%d" % [sim.leaks, sim.core_hp])

	# 6. 无塔时连续开波,漏怪应破核(失败路径)
	sim.reset()
	for _w in 5:
		if sim.is_game_over():
			break
		if not sim.wave_active:
			sim.start_wave()
		for _j in 500:
			sim.tick(0.05)
			if sim.is_game_over():
				break
	if not sim.is_defeat():
		print("FAIL 6: 无塔应破核 core=%d waves_cleared=%d outcome=%s" % [
			sim.core_hp, sim.waves_cleared, sim.outcome])
		failures += 1
	else:
		print("OK defeat_path outcome=%s" % sim.outcome)

	# 7. 重复放置拒绝
	sim.reset()
	sim.place_tower(1, 6, &"fire")
	if sim.place_tower(1, 6, &"ice"):
		print("FAIL 7: 同格重复放置应失败")
		failures += 1

	# 8. 通关路径: 足量好站位能清完 WIN_WAVES(胜利)
	sim.reset()
	sim.gold = 2000
	sim.core_hp = 20
	for y in range(1, 7):
		for x in [1, 3]:
			if sim.can_place(x, y):
				sim.place_tower(x, y, &"fire" if x == 1 else &"ice")
	# 补外拐
	for c in [Vector2i(1, 0), Vector2i(3, 0)]:
		if sim.can_place(c.x, c.y):
			sim.place_tower(c.x, c.y, &"fire")
	var guard := 0
	while not sim.is_victory() and guard < 20000:
		guard += 1
		if not sim.wave_active and sim.outcome == "":
			if not sim.start_wave():
				break
		sim.tick(0.05)
	if not sim.is_victory():
		print("FAIL 8: 应存在通关路径 outcome=%s cleared=%d/%d hp=%d enemies=%d" % [
			sim.outcome, sim.waves_cleared, sim.WIN_WAVES, sim.core_hp, sim.enemy_count()])
		failures += 1
	else:
		print("OK victory_path waves=%d kills=%d leaks=%d" % [sim.waves_cleared, sim.kills, sim.leaks])

	# 9. 站位决策:同数同型塔,不同摆法结果显著不同(CL-005)
	var leaks_good := _run_placement_leaks(Sim, true)
	var leaks_bad := _run_placement_leaks(Sim, false)
	if leaks_good < 0 or leaks_bad < 0:
		print("FAIL 9: 站位对照跑失败")
		failures += 1
	elif leaks_bad <= leaks_good:
		print("FAIL 9b: 坏站位应漏更多 good_leaks=%d bad_leaks=%d" % [leaks_good, leaks_bad])
		failures += 1
	else:
		print("OK placement_matters good_leaks=%d bad_leaks=%d delta=%d" % [
			leaks_good, leaks_bad, leaks_bad - leaks_good])

	# 10. 晶核在顶部 + 路径终点
	if sim.CORE_CELL != Vector2i(2, 0):
		print("FAIL 10: CORE_CELL 应为 (2,0) 顶部 实际 %s" % sim.CORE_CELL)
		failures += 1
	var end_cell: Vector2i = sim.PATH[sim.PATH_LEN - 1]
	if end_cell != sim.CORE_CELL:
		print("FAIL 10b: 路径终点应是晶核 end=%s core=%s" % [end_cell, sim.CORE_CELL])
		failures += 1

	# 11. 局时长量级旁证
	var est: Dictionary = Sim.estimate_session_seconds()
	var emin: float = float(est["estimate_min"])
	print("OK session_estimate min=%.2f (target 5-8)" % emin)
	if emin < 4.0 or emin > 12.0:
		print("FAIL 11: 估算局时偏离 5-8 分钟量级 estimate_min=%.2f" % emin)
		failures += 1

	# 12. 命中产生 shots / hits_this_tick(CL-004 逻辑侧)
	sim.reset()
	sim.gold = 200
	sim.place_tower(1, 6, &"fire")
	sim.start_wave()
	var saw_hit := false
	for _i in 200:
		sim.tick(0.05)
		if sim.hits_this_tick > 0 or sim.shots.size() > 0:
			saw_hit = true
			break
	if not saw_hit:
		print("FAIL 12: 开火应产生 hit/shots")
		failures += 1
	else:
		print("OK combat_shots hits=%d shots=%d" % [sim.hits_this_tick, sim.shots.size()])

	if failures == 0:
		print("test_crystal_line_sim: ALL PASS")
		quit(0)
	else:
		print("test_crystal_line_sim: %d FAILURE(S)" % failures)
		quit(1)


## 两座火塔: good=贴长弯外侧; bad=远离路径的角落。跑满 2 波比漏怪。
func _run_placement_leaks(Sim, good: bool) -> int:
	var s = Sim.new()
	s.gold = 200
	s.core_hp = 30
	if good:
		# 左侧长弯 (0,2)-(0,5) 外侧
		s.place_tower(1, 4, &"fire")
		s.place_tower(1, 3, &"fire")
	else:
		# 右下远离当前路径段的弱位(路径在左/上绕)
		s.place_tower(3, 7, &"fire")
		s.place_tower(4, 7, &"fire")
	for _w in 2:
		if s.is_game_over():
			break
		if not s.wave_active:
			s.start_wave()
		for _i in 1000:
			s.tick(0.05)
			if not s.wave_active or s.is_game_over():
				break
	return s.leaks
