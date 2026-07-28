extends SceneTree
## 数值探针(不是断言测试):打印覆盖表、首波压力、站位对照、极端情况。
## 手感 / 情绪前提那一侧在 feel_probe.gd,两者分工:
##   balance_probe —— 静态几何与单点情形(覆盖表、首波、无塔)
##   feel_probe    —— 整局体验前提(张力/能动性/归因/梯度)+ --sweep 扫难度网格
##
## ⚠️ 模拟玩家统一用 test/tools/sim_player.gd,**不在这里再写一份**。
##    调参依据和回归断言必须是同一个玩家模型,否则调 A 测 B(见 vision-first-slice 4.2 坑三)。
##
## 运行: godot --headless --path . -s res://test/tools/balance_probe.gd

const Sim := preload("res://game/crystal_line/sim/crystal_line_sim.gd")
const SimPlayer := preload("res://test/tools/sim_player.gd")
const DT := 0.05

## CL-005 对照:同样 4 座火塔,中路长廊 vs 边缘。
## 两组每座塔的覆盖都必须 > 0,否则是退化样本(拿「4 座 vs 2 座」冒充「换个位置」)。
const GOOD_SPOTS := [Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4)]
const POOR_SPOTS := [Vector2i(3, 0), Vector2i(3, 1), Vector2i(4, 2), Vector2i(4, 6)]


func _initialize() -> void:
	_probe_coverage()
	print("")
	_probe_first_wave()
	print("")
	_probe_placement("中路长廊 4 火塔", GOOD_SPOTS)
	_probe_placement("边缘 4 火塔", POOR_SPOTS)
	print("")
	for mode in [SimPlayer.GOOD, SimPlayer.MID, SimPlayer.BAD]:
		_probe_round(mode)
	print("")
	_probe_no_tower()
	quit(0)


## 每个可建造格对火塔射程的覆盖长度,证明「放哪一格」不等价
func _probe_coverage() -> void:
	var sim = Sim.new()
	var rng: float = sim.range_of(&"fire")
	for row in sim.ROWS:
		var line := "PROBE_COV row%d " % row
		for col in sim.COLS:
			if sim.is_path_cell(col, row):
				line += "  ##  "
			else:
				line += "%5.1f " % sim.coverage_at(col, row, rng)
		print(line)


## 同数量同类型塔,两种摆法跑到局终(不截断:早先砍在第 4 波是靠死塔才拉开差距的)
func _probe_placement(label: String, spots: Array) -> void:
	var sim = Sim.new()
	sim.gold = 9999
	var cov_total := 0.0
	for s in spots:
		cov_total += sim.coverage_at(s.x, s.y, sim.range_of(&"fire"))
		sim.place_tower(s.x, s.y, &"fire")
	var t := 0.0
	while not sim.is_round_over() and t < 900.0:
		sim.tick(DT)
		t += DT
	print("PROBE_PLACEMENT %-16s 总覆盖=%4.1f towers=%d waves=%d leaks=%d hp=%d 用时=%.0fs" % [
		label, cov_total, sim.tower_count(), sim.waves_cleared, sim.leaks, sim.core_hp, sim.elapsed])


## 首波压力:开局火+冰各一座,放在中路长廊之间
func _probe_first_wave() -> void:
	var sim = Sim.new()
	var ok_fire: bool = sim.place_tower(1, 4, &"fire")
	var ok_ice: bool = sim.place_tower(2, 4, &"ice")
	var gold_left: int = sim.gold
	sim.start_wave()
	var t := 0.0
	while sim.wave == 1 and not sim.is_round_over() and t < 200.0:
		sim.tick(DT)
		t += DT
		if sim.phase == sim.PHASE_PREP:
			break
	print("PROBE_FIRST_WAVE fire=%s ice=%s gold_left=%d leaks=%d hp=%d kills=%d wave_seconds=%.1f" % [
		ok_fire, ok_ice, gold_left, sim.leaks, sim.core_hp, sim.kills, t])


## 走真实经济跑完整局(共用 SimPlayer,不另写一份打法)
func _probe_round(mode: String) -> void:
	var sim = Sim.new()
	SimPlayer.new(mode).play(sim, DT)
	var s: Dictionary = sim.summary()
	print("PROBE_ROUND %-5s victory=%-5s waves=%2d/%d hp=%d towers=%d kills=%d leaks=%d 首漏=第%d波 用时=%.0fs (%d:%02d)" % [
		mode, s["victory"], s["waves_cleared"], s["waves_total"], s["core_hp"],
		s["towers"], s["kills"], s["leaks"], int(s["first_leak_wave"]), s["seconds"],
		int(s["seconds"]) / 60, int(s["seconds"]) % 60])


func _probe_no_tower() -> void:
	var sim = Sim.new()
	var t := 0.0
	while not sim.is_round_over() and t < 600.0:
		sim.tick(DT)
		t += DT
	print("PROBE_NO_TOWER defeat=%s hp=%d wave=%d seconds=%.1f" % [
		sim.is_game_over(), sim.core_hp, sim.wave, t])
