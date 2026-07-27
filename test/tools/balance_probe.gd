extends SceneTree
## 数值探针(不是断言测试):用几种「模拟玩家」跑完整局,打印时长/漏怪/胜负。
## 用于给 docs/vision/fix-report-r1.md 的一局时长与首波压力提供可复跑依据。
## 运行: godot --headless --path . -s res://test/tools/balance_probe.gd

const Sim := preload("res://game/crystal_line/sim/crystal_line_sim.gd")
const DT := 0.05


## CL-005 对照:同样 4 座火塔,中路长廊 vs 右上角
const GOOD_SPOTS := [Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4)]
const POOR_SPOTS := [Vector2i(3, 0), Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2)]

## 通关截图用的固定构筑(gold 不限,一次性摆满)
const WIN_BUILD := [
	[1, 2, "fire"], [3, 4, "fire"], [1, 6, "fire"], [1, 4, "fire"], [2, 4, "fire"],
	[2, 2, "ice"], [0, 4, "fire"], [2, 6, "ice"], [1, 0, "fire"], [3, 2, "fire"],
	[3, 6, "fire"], [0, 0, "fire"], [4, 2, "fire"], [4, 6, "fire"], [3, 1, "fire"],
	[3, 0, "fire"],
]


func _initialize() -> void:
	_probe_coverage()
	print("")
	_probe_first_wave()
	print("")
	_probe_placement("中路长廊 4 火塔", GOOD_SPOTS)
	_probe_placement("右上角 4 火塔", POOR_SPOTS)
	print("")
	_probe_build("16 塔固定构筑(截图用)", WIN_BUILD)
	print("")
	_run("贪心站位(每次挑覆盖最大的空格)", true)
	_run("糟糕站位(每次挑覆盖最小的空格)", false)
	print("")
	_probe_no_tower()
	quit(0)


## 打印每个可建造格对火塔射程的覆盖长度,证明「放哪一格」不等价
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


## 固定构筑跑完整局(gold 不限)
func _probe_build(label: String, build: Array) -> void:
	var sim = Sim.new()
	sim.gold = 99999
	for b in build:
		sim.place_tower(int(b[0]), int(b[1]), StringName(b[2]))
	var t := 0.0
	while not sim.is_round_over() and t < 900.0:
		sim.tick(DT)
		t += DT
	var s: Dictionary = sim.summary()
	print("PROBE_BUILD %-22s victory=%s waves=%d/%d hp=%d towers=%d leaks=%d seconds=%.0f (%d:%02d)" % [
		label, s["victory"], s["waves_cleared"], s["waves_total"], s["core_hp"],
		s["towers"], s["leaks"], s["seconds"], int(s["seconds"]) / 60, int(s["seconds"]) % 60])


## 同数量同类型塔,两种摆法跑同样的前 N 波
func _probe_placement(label: String, spots: Array) -> void:
	var sim = Sim.new()
	sim.gold = 9999
	for s in spots:
		sim.place_tower(s.x, s.y, &"fire")
	var t := 0.0
	while not sim.is_round_over() and sim.waves_cleared < 4 and t < 400.0:
		sim.tick(DT)
		t += DT
	print("PROBE_PLACEMENT %-16s towers=%d waves_cleared=%d leaks=%d hp=%d kills=%d" % [
		label, sim.tower_count(), sim.waves_cleared, sim.leaks, sim.core_hp, sim.kills])


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


func _probe_no_tower() -> void:
	var sim = Sim.new()
	var t := 0.0
	while not sim.is_round_over() and t < 600.0:
		sim.tick(DT)
		t += DT
	print("PROBE_NO_TOWER defeat=%s hp=%d wave=%d seconds=%.1f" % [
		sim.is_game_over(), sim.core_hp, sim.wave, t])


func _run(label: String, greedy: bool) -> void:
	var sim = Sim.new()
	var t := 0.0
	var guard := 0
	while not sim.is_round_over() and guard < 40000:
		guard += 1
		if sim.phase == sim.PHASE_PREP:
			_buy(sim, greedy)
		sim.tick(DT)
		t += DT
	var s: Dictionary = sim.summary()
	print("PROBE_ROUND %-28s victory=%s waves=%d/%d hp=%d towers=%d kills=%d leaks=%d seconds=%.0f (%d:%02d)" % [
		label, s["victory"], s["waves_cleared"], s["waves_total"], s["core_hp"],
		s["towers"], s["kills"], s["leaks"], s["seconds"],
		int(s["seconds"]) / 60, int(s["seconds"]) % 60])


func _buy(sim, greedy: bool) -> void:
	while true:
		var type: StringName = &"fire" if sim.tower_count() % 3 != 2 else &"ice"
		var cost: int = sim.cost_of(type)
		if sim.gold < cost:
			return
		var cell := _pick_cell(sim, sim.range_of(type), greedy)
		if cell.x < 0:
			return
		if not sim.place_tower(cell.x, cell.y, type):
			return


func _pick_cell(sim, rng: float, greedy: bool) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_cov := -1.0 if greedy else 1e9
	for row in sim.ROWS:
		for col in sim.COLS:
			if not sim.can_place(col, row):
				continue
			var cov: float = sim.coverage_at(col, row, rng)
			if greedy:
				if cov > best_cov:
					best_cov = cov
					best = Vector2i(col, row)
			elif cov < best_cov:
				best_cov = cov
				best = Vector2i(col, row)
	return best
