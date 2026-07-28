extends SceneTree
## 《晶核防线》逻辑 headless 断言(R1 修复后)
## 运行: godot --headless --path . -s res://test/test_crystal_line_sim.gd
##
## 覆盖 R1 缺陷: CL-003 一局闭环/时长、CL-004 开火遥测、CL-005 站位对照、
##               CL-007 开局经济与首波压力、CL-008 晶核位置。

const Sim := preload("res://game/crystal_line/sim/crystal_line_sim.gd")
const DT := 0.05

## CL-005 对照:同样 4 座火塔,中路长廊 vs 贴右边缘
## ⚠️ 两组都必须是**有效样本**——每座塔的路径覆盖都 > 0。
##    早先的 POOR 用 (4,0)(4,1),这两格覆盖恰好为 0(见 balance_probe 覆盖表),
##    等于拿「4 座塔 vs 2 座塔」冒充「同样 4 座塔换个位置」,对照本身是假的。
const GOOD_SPOTS := [Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4)]
const POOR_SPOTS := [Vector2i(3, 0), Vector2i(3, 1), Vector2i(4, 2), Vector2i(4, 6)]

const SimPlayer := preload("res://test/tools/sim_player.gd")

var failures := 0


func _initialize() -> void:
	_basics()
	_path_shape()
	_economy_cl007()
	_first_wave_pressure_cl007()
	_combat_telemetry_cl004()
	_placement_contrast_cl005()
	_victory_path_cl003()
	_defeat_path_cl003()
	_round_guards_cl003()

	if failures == 0:
		print("test_crystal_line_sim: ALL PASS")
		quit(0)
	else:
		print("test_crystal_line_sim: %d FAILURE(S)" % failures)
		quit(1)


func _fail(msg: String) -> void:
	print("FAIL %s" % msg)
	failures += 1


# ---------------------------------------------------------------- 基础

func _basics() -> void:
	var sim = Sim.new()
	if sim.gold != 100 or sim.core_hp != 10:
		_fail("初始 gold/hp 不对 gold=%d hp=%d" % [sim.gold, sim.core_hp])
	if sim.phase != sim.PHASE_PREP:
		_fail("初始应为备战阶段,实际 %s" % sim.phase)

	# 路径格不可建造(取路径中段一格)
	var p: Vector2i = sim.PATH[7]
	if sim.place_tower(p.x, p.y, &"fire"):
		_fail("路径上不应能放塔 %s" % p)

	# 侧格可建造并扣金
	if not sim.place_tower(1, 4, &"fire"):
		_fail("侧格应能放火塔 event=%s" % sim.last_event)
	if sim.gold != 60 or sim.tower_count() != 1:
		_fail("扣金/计数 gold=%d towers=%d" % [sim.gold, sim.tower_count()])

	# 同格重复放置拒绝
	if sim.place_tower(1, 4, &"ice"):
		_fail("同格重复放置应失败")

	# 金币不足拒绝
	sim.gold = 10
	if sim.place_tower(3, 2, &"ice"):
		_fail("金币不足仍放置")
	if sim.last_event != "no_gold":
		_fail("last_event 应为 no_gold 实际 %s" % sim.last_event)

	# CL-008: 晶核 = 路径终点,且在棋盘底部(与一页纸「底部晶核」一致)
	var core: Vector2i = sim.core_cell()
	if core != sim.PATH[sim.PATH.size() - 1]:
		_fail("晶核应位于路径终点 core=%s" % core)
	if core.y != sim.ROWS - 1:
		_fail("CL-008 晶核应在底行 core=%s ROWS=%d" % [core, sim.ROWS])
	if sim.PATH[0].y != 0:
		_fail("敌人入口应在顶行 entry=%s" % sim.PATH[0])


# ---------------------------------------------------------------- CL-005 路径形状

func _path_shape() -> void:
	var sim = Sim.new()
	# 路径自身合法:相邻 waypoint 正交相邻、无重复
	var seen := {}
	for i in sim.PATH.size():
		var c: Vector2i = sim.PATH[i]
		if seen.has(c):
			_fail("路径重复经过 %s" % c)
		seen[c] = true
		if c.x < 0 or c.y < 0 or c.x >= sim.COLS or c.y >= sim.ROWS:
			_fail("路径越界 %s" % c)
		if i > 0:
			var d: Vector2i = c - sim.PATH[i - 1]
			if absi(d.x) + absi(d.y) != 1:
				_fail("路径 %d→%d 非正交相邻 %s→%s" % [i - 1, i, sim.PATH[i - 1], c])

	# 路径必须真的蜿蜒:至少 4 次转向(直线单列会退化成「放第几行」)
	var turns := 0
	for i in range(1, sim.PATH.size() - 1):
		var a: Vector2i = sim.PATH[i] - sim.PATH[i - 1]
		var b: Vector2i = sim.PATH[i + 1] - sim.PATH[i]
		if a != b:
			turns += 1
	if turns < 4:
		_fail("路径转向次数过少 turns=%d(站位决策会退化)" % turns)

	# 不同可建造格的覆盖长度必须显著不同
	var rng: float = sim.range_of(&"fire")
	var best := 0.0
	var worst := 1e9
	for row in sim.ROWS:
		for col in sim.COLS:
			if sim.is_path_cell(col, row):
				continue
			var cov: float = sim.coverage_at(col, row, rng)
			best = maxf(best, cov)
			worst = minf(worst, cov)
	if best < worst + 3.0:
		_fail("格子覆盖长度差异过小 best=%.2f worst=%.2f" % [best, worst])


# ---------------------------------------------------------------- CL-007 经济

func _economy_cl007() -> void:
	var sim = Sim.new()
	var fire_cost: int = sim.cost_of(&"fire")
	var ice_cost: int = sim.cost_of(&"ice")
	if sim.START_GOLD < fire_cost + ice_cost:
		_fail("CL-007 起始金 %d 买不起火(%d)+冰(%d)" % [sim.START_GOLD, fire_cost, ice_cost])
	if not sim.place_tower(1, 4, &"fire"):
		_fail("CL-007 第一座火塔应可放")
	if not sim.place_tower(2, 4, &"ice"):
		_fail("CL-007 第一波前应买得起冰塔 gold=%d event=%s" % [sim.gold, sim.last_event])
	if sim.wave != 0:
		_fail("CL-007 两塔应在第一波开始前落地 wave=%d" % sim.wave)


## 首波压力:开局标准双塔应「有把握」——零漏怪、晶核满血
func _first_wave_pressure_cl007() -> void:
	var sim = Sim.new()
	sim.place_tower(1, 4, &"fire")
	sim.place_tower(2, 4, &"ice")
	sim.start_wave()
	var t := 0.0
	while sim.wave == 1 and sim.phase == sim.PHASE_WAVE and t < 200.0:
		sim.tick(DT)
		t += DT
	if sim.leaks != 0 or sim.core_hp != 10:
		_fail("CL-007 首波压力过大 leaks=%d hp=%d" % [sim.leaks, sim.core_hp])
	if sim.waves_cleared != 1:
		_fail("CL-007 首波应被双塔清完 waves_cleared=%d" % sim.waves_cleared)


# ---------------------------------------------------------------- CL-004 开火遥测

func _combat_telemetry_cl004() -> void:
	var sim = Sim.new()
	sim.gold = 999
	sim.place_tower(1, 4, &"fire")
	sim.start_wave()
	var saw_shot := false
	var saw_aim := false
	var saw_kill := false
	var hp_readable := false
	for _i in 600:
		sim.tick(DT)
		for s in sim.shots:
			saw_shot = true
			if bool(s["kill"]):
				saw_kill = true
			# 弹道起点必须落在某座塔上
			if not sim.towers.has("%d,%d" % [int(s["from"].x), int(s["from"].y)]):
				_fail("CL-004 弹道起点不是塔 %s" % s["from"])
		for k in sim.towers.keys():
			if bool(sim.towers[k]["has_aim"]):
				saw_aim = true
		for e in sim.enemies:
			if float(e["max_hp"]) > 0.0 and float(e["hp"]) < float(e["max_hp"]):
				hp_readable = true
		if sim.waves_cleared >= 1:
			break
	if not saw_shot:
		_fail("CL-004 没有任何开火记录(shots 空)")
	if not saw_aim:
		_fail("CL-004 塔从未锁定目标(has_aim 恒 false)")
	if not saw_kill:
		_fail("CL-004 没有击杀事件")
	if not hp_readable:
		_fail("CL-004 敌人剩余血量不可读(hp 从未低于 max_hp)")
	if sim.hits <= 0:
		_fail("CL-004 hits 计数未增长")
	# 非战斗阶段不应残留瞄准线
	sim.tick(DT)
	for k in sim.towers.keys():
		if bool(sim.towers[k]["has_aim"]):
			_fail("CL-004 清波后仍残留瞄准状态")


# ---------------------------------------------------------------- CL-005 站位对照

func _placement_contrast_cl005() -> void:
	_assert_no_degenerate_sample()
	var good := _run_placement(GOOD_SPOTS)
	var poor := _run_placement(POOR_SPOTS)
	print("CL-005 对照 好站位 waves=%d 用时=%.0fs | 坏站位 waves=%d 用时=%.0fs" % [
		good["waves"], good["elapsed"], poor["waves"], poor["elapsed"]])
	if int(good["towers"]) != int(poor["towers"]):
		_fail("CL-005 对照组塔数不同 %d vs %d" % [good["towers"], poor["towers"]])
	# 不比 leaks:核只有 START_HP 点血,漏满即破核停表,两边都输时 leaks 恒等于 10,
	# 是个**饱和指标**——看着在比较,实际约束不到任何东西(和退化样本同类毛病)。
	if int(good["waves"]) < int(poor["waves"]) + 2:
		_fail("CL-005 站位对结果无显著影响: 好站位撑 %d 波,坏站位撑 %d 波(覆盖 19.9 vs 6.6)" % [
			good["waves"], poor["waves"]])


## 对照实验的前置条件:两组里**每一座**塔都得真的够得着路径。
## 只断言「两组塔数相同」是拦不住退化样本的——数量相同、有效数不同,对照就是假的。
## 判据问法:这一组里有没有哪座塔换成空气结果都一样?有 = 退化样本。
func _assert_no_degenerate_sample() -> void:
	var sim = Sim.new()
	var rng: float = float(sim.TOWER_DEFS[&"fire"]["range"])
	for group in [["GOOD", GOOD_SPOTS], ["POOR", POOR_SPOTS]]:
		var total := 0.0
		for c in group[1]:
			var cov: float = sim.coverage_at(c.x, c.y, rng)
			total += cov
			if cov <= 0.0:
				_fail("CL-005 %s 含退化样本 (%d,%d) 覆盖=0,它证明不了站位有讲究" % [
					group[0], c.x, c.y])
		print("CL-005 样本有效性 %s 总覆盖=%.1f" % [group[0], total])


func _run_placement(spots: Array) -> Dictionary:
	var sim = Sim.new()
	sim.gold = 9999
	for s in spots:
		sim.place_tower(s.x, s.y, &"fire")
	var t := 0.0
	# 跑到局终而不是砍在第 4 波:4 座塔谁都通不了关,差距要有跑道才显出来。
	# 早先砍在第 4 波,是靠 POOR 组里的死塔才拉开差距的。
	while not sim.is_round_over() and t < 900.0:
		sim.tick(DT)
		t += DT
	return {"waves": sim.waves_cleared, "leaks": sim.leaks, "towers": sim.tower_count(),
		"elapsed": sim.elapsed}


# ---------------------------------------------------------------- CL-003 一局闭环

## 存在通关路径 —— **走真实经济**,不再 gold=99999 一次摆满。
## 无限金币下摆满 16 座只证明「够多的塔能赢」,证明不了「玩家攒得出这些塔」;
## 平衡一改这个区别就致命(实测新平衡下 16 座满级零升级的构筑死在第 12 波重潮)。
## 现在跑的是和 feel_probe 调参时同一个 GOOD 模拟玩家,两边不会各说各话。
func _victory_path_cl003() -> void:
	var sim = Sim.new()
	SimPlayer.new(SimPlayer.GOOD).play(sim, DT)
	if not sim.is_victory():
		_fail("CL-003 存在通关路径:该构筑应通关 waves=%d hp=%d" % [sim.waves_cleared, sim.core_hp])
	if sim.waves_cleared != sim.WAVES_TO_WIN:
		_fail("CL-003 通关波数不符 %d/%d" % [sim.waves_cleared, sim.WAVES_TO_WIN])
	var s: Dictionary = sim.summary()
	if not bool(s["victory"]):
		_fail("CL-003 summary 未标记胜利")
	# 一局时长落在 5–8 分钟量级
	if sim.elapsed < 300.0 or sim.elapsed > 480.0:
		_fail("CL-003 一局时长不在 5–8 分钟量级 elapsed=%.0fs" % sim.elapsed)
	print("CL-003 通关 waves=%d/%d hp=%d kills=%d 用时=%.0fs (%d:%02d)" % [
		sim.waves_cleared, sim.WAVES_TO_WIN, sim.core_hp, sim.kills, sim.elapsed,
		int(sim.elapsed) / 60, int(sim.elapsed) % 60])


func _defeat_path_cl003() -> void:
	var sim = Sim.new()
	var t := 0.0
	while not sim.is_round_over() and t < 600.0:
		sim.tick(DT)
		t += DT
	if not sim.is_game_over():
		_fail("CL-003 不建塔应必破核 hp=%d wave=%d" % [sim.core_hp, sim.wave])
	if sim.is_victory():
		_fail("CL-003 不建塔不应胜利")
	if sim.core_hp != 0:
		_fail("CL-003 失败时晶核应归零 hp=%d" % sim.core_hp)
	print("CL-003 失败路径 wave=%d 用时=%.0fs" % [sim.wave, sim.elapsed])


func _round_guards_cl003() -> void:
	var sim = Sim.new()
	# 备战阶段可立即开波;战斗中不可重复开波
	if not sim.start_wave():
		_fail("CL-003 备战阶段应可立即开波")
	if sim.start_wave():
		_fail("CL-003 战斗中不应能再开波")
	# 备战倒计时到点自动开下一波(一局能自己往前走)
	var sim2 = Sim.new()
	var t := 0.0
	while sim2.wave == 0 and t < 60.0:
		sim2.tick(DT)
		t += DT
	if sim2.wave != 1:
		_fail("CL-003 备战结束应自动开波 wave=%d" % sim2.wave)
	if t < sim2.PREP_FIRST - 0.2 or t > sim2.PREP_FIRST + 0.2:
		_fail("CL-003 首波备战时长应为 %.1fs,实际 %.2fs" % [sim2.PREP_FIRST, t])
	# 局终后拒绝一切开波与建造
	var sim3 = Sim.new()
	var t3 := 0.0
	while not sim3.is_round_over() and t3 < 600.0:
		sim3.tick(DT)
		t3 += DT
	if sim3.start_wave():
		_fail("CL-003 局终后不应能开波")
	sim3.gold = 9999
	if sim3.place_tower(1, 4, &"fire"):
		_fail("CL-003 局终后不应能建塔")
	# 再来一局:reset 必须把一局状态清干净
	sim3.reset()
	if sim3.is_round_over() or sim3.wave != 0 or sim3.core_hp != sim3.START_HP \
			or sim3.gold != sim3.START_GOLD or sim3.tower_count() != 0 \
			or sim3.kills != 0 or sim3.leaks != 0 or sim3.elapsed != 0.0:
		_fail("CL-003 reset 未清干净 phase=%s wave=%d hp=%d gold=%d" % [
			sim3.phase, sim3.wave, sim3.core_hp, sim3.gold])
