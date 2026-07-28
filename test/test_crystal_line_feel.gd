extends SceneTree
## 阶段 4「体验前提」门 —— 断言的不是「好不好玩」(测不了),
## 而是**好玩的必要条件里有没有哪一条是空的**。必要条件不成立 → 一定不好玩。
##
## 一页纸(docs/vision/vision-one-pager.md)写的情绪 → 这里断言的结构前提:
##   「有把握的紧张」 → 会玩的能赢,但过程中真被逼近过(不是全程碾压)
##   「波间松一口气」 → 每个备战窗口都有可执行的选择(不是干等倒计时)
##   「小棋复盘欲」   → 输了能指出从第几波开始扛不住(不是只报一个总数)
##   反例「不要无脑铺满」 → 铺满在经济上不可能
## 外加一条 skill 通用判据:**技巧梯度**——三档打法结果单调且拉得开,
## 不能是「会玩就零伤通关 / 差一点就秒死」的二值游戏。
##
## 运行: godot --headless --path . -s res://test/test_crystal_line_feel.gd

const Sim := preload("res://game/crystal_line/sim/crystal_line_sim.gd")
const SimPlayer := preload("res://test/tools/sim_player.gd")
const DT := 0.05
## 敌人推进过全路径这个比例还没死 = 玩家真的被逼近过一次
const THREAT := 0.75

var failures := 0


func _initialize() -> void:
	_tension()
	_prep_agency()
	_attribution()
	_skill_gradient()
	_no_carpet()
	if failures == 0:
		print("test_crystal_line_feel: ALL PASS")
		quit(0)
	else:
		print("test_crystal_line_feel: %d FAILURE(S)" % failures)
		quit(1)


func _fail(m: String) -> void:
	print("FAIL %s" % m)
	failures += 1


func _run(mode: String) -> Dictionary:
	var sim = Sim.new()
	SimPlayer.new(mode).play(sim, DT)
	var threat := 0
	var deep_sum := 0.0
	for r in sim.wave_log:
		if float(r["deepest"]) >= THREAT and int(r["hp"]) > 0:
			threat += 1
		deep_sum += float(r["deepest"])
	var n: int = maxi(sim.wave_log.size(), 1)
	return {
		"sim": sim, "victory": sim.is_victory(), "waves": sim.waves_cleared,
		"threat": threat, "avg_deep": deep_sum / float(n), "hp": sim.core_hp,
	}


## 「有把握的紧张」:会玩的要赢(把握),但过程里至少被逼近过一次(紧张)。
## ⚠️ 只断言「赢了」是不够的——实测曾经会玩的**全程满血 14/14**,
##    测试全绿、玩起来毫无悬念。赢得毫无悬念和输一样不是想要的体验。
func _tension() -> void:
	var g := _run(SimPlayer.GOOD)
	if not bool(g["victory"]):
		_fail("紧张门: 会玩的打法应当能通关,实际死在第 %d 波" % int(g["waves"]))
	if int(g["threat"]) < 1:
		_fail("紧张门: 整局没有任何一波被逼近过(推进 ≥%d%%),赢得毫无悬念" % int(THREAT * 100))
	# 平均推进太浅 = 怪还没走几步就死光,全程零压力
	if float(g["avg_deep"]) < 0.28:
		_fail("紧张门: 平均推进仅 %.0f%%,敌人根本没靠近过晶核" % (float(g["avg_deep"]) * 100.0))
	print("紧张门 通关=%s 终局晶核=%d 险波=%d 平均推进=%.0f%%" % [
		g["victory"], int(g["hp"]), int(g["threat"]), float(g["avg_deep"]) * 100.0])


## 「波间松一口气」:松的时候得有得选。买不起任何东西 = 只能盯倒计时,那是空转不是喘息。
## 实测踩过:格子被填满后 14 个备战窗口里有 7 个玩家无事可做(钱有 3027,没地方花)。
func _prep_agency() -> void:
	var sim = Sim.new()
	var player = SimPlayer.new(SimPlayer.GOOD)
	var idle := 0
	var total := 0
	var seen := -1
	var guard := 0
	while not sim.is_round_over() and guard < 40000:
		guard += 1
		if sim.phase == sim.PHASE_PREP and sim.wave != seen:
			seen = sim.wave
			total += 1
			if not _has_move(sim):
				idle += 1
		if sim.phase == sim.PHASE_PREP:
			player.spend(sim)
		sim.tick(DT)
	if idle > 0:
		_fail("喘息门: %d/%d 个备战窗口玩家无事可做(买不起塔且升不动)" % [idle, total])
	print("喘息门 备战窗口=%d 只能干等=%d" % [total, idle])


## 这一刻玩家有没有一个能执行的动作?(建得起一座塔,或升得起一座塔)
func _has_move(sim) -> bool:
	for t in [&"fire", &"ice"]:
		if sim.gold >= sim.cost_of(t):
			for row in sim.ROWS:
				for col in sim.COLS:
					if sim.can_place(col, row):
						return true
			break
	for k in sim.towers.keys():
		var tw: Dictionary = sim.towers[k]
		if sim.can_upgrade(int(tw["col"]), int(tw["row"])):
			return true
	return false


## 「小棋复盘欲」的前提:输了要能归因。只报「漏怪 10」玩家不知道下一局改什么。
func _attribution() -> void:
	var sim = Sim.new()
	SimPlayer.new(SimPlayer.BAD).play(sim, DT)
	var s: Dictionary = sim.summary()
	if sim.is_victory():
		_fail("归因门: BAD 打法不该通关")
	if not s.has("wave_log") or (s["wave_log"] as Array).is_empty():
		_fail("归因门: 结算缺逐波账本,指不出哪一波开始扛不住")
		return
	if int(s["first_leak_wave"]) <= 0:
		_fail("归因门: 输了却报「全程未漏怪」first_leak_wave=%d" % int(s["first_leak_wave"]))
	# 收尾那一波也必须进账本,否则结算指不出是哪波崩的
	var last: Dictionary = (s["wave_log"] as Array).back()
	if int(last["hp"]) > 0:
		_fail("归因门: 账本最后一条 hp=%d,破核那一波没记进去" % int(last["hp"]))
	print("归因门 首次漏怪=第%d波 账本=%d 条" % [int(s["first_leak_wave"]), (s["wave_log"] as Array).size()])


## 技巧梯度:三档打法的结果要单调且拉得开。
## ⚠️ 这条最容易「看起来有区分度」其实是二值的。实测曾经是
##    会玩 14 波零伤通关 / 随手放 100 秒团灭 —— 中间没有过渡带,
##    玩家要么碾压要么秒死,学不到东西也没有复盘的余地。
func _skill_gradient() -> void:
	var g := _run(SimPlayer.GOOD)
	var m := _run(SimPlayer.MID)
	var b := _run(SimPlayer.BAD)
	var gw := int(g["waves"])
	var mw := int(m["waves"])
	var bw := int(b["waves"])
	if not (gw > mw and mw > bw):
		_fail("梯度门: 三档打法波数不单调 好=%d 中=%d 差=%d" % [gw, mw, bw])
	if mw - bw < 2:
		_fail("梯度门: 随手放(%d 波)和乱放(%d 波)几乎没差别,站位没有中间地带" % [mw, bw])
	# 随手放的人应当看到大半个游戏再输,而不是开局就死
	if mw < 4:
		_fail("梯度门: 随手放只撑 %d 波,新手没有学习窗口" % mw)
	if bool(m["victory"]):
		_fail("梯度门: 随手放也能通关,站位就不是决策了")
	print("梯度门 好=%d波 中=%d波 差=%d波" % [gw, mw, bw])


## 一页纸反例:「不要变成无脑铺满」。铺满必须在经济上不可能。
func _no_carpet() -> void:
	var g := _run(SimPlayer.GOOD)
	var sim = g["sim"]
	var buildable := 0
	for row in sim.ROWS:
		for col in sim.COLS:
			if not sim.is_path_cell(col, row):
				buildable += 1
	var used: int = sim.tower_count()
	if used >= buildable:
		_fail("铺满门: 整局结束时 %d/%d 格全被填满,「放哪一格」退化成「放满」" % [used, buildable])
	print("铺满门 用了 %d/%d 格(留白 %d)" % [used, buildable, buildable - used])
