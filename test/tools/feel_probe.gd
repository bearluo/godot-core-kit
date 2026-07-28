extends SceneTree
## 情绪前提探针(阶段 4 用)——不是断言测试,是量数据。
##
## 阶段 3 的门全是**存在性**的(有没有血条/有没有一局/有没有结算),
## 它筛不出「元素齐但没味道」。这个探针换一个问法:
## **不测「好不好玩」(测不了,一测就退化成自评),测「好玩的必要条件里哪一条是空的」。**
##
## 一页纸写的情绪 → 结构性必要条件 → 这里量的东西:
##   「有把握的紧张」 → 余量曲线既不全程满、也不单调崩   → _pressure_curve
##   「波间松一口气」 → 每个喘息窗口都有可执行的有意义选择 → _prep_agency
##   「小棋复盘欲」   → 失败可归因(结算能指出哪一波开始不对) → _attribution
##
## 运行: godot --headless --path . -s res://test/tools/feel_probe.gd

const Sim := preload("res://game/crystal_line/sim/crystal_line_sim.gd")
const DT := 0.05
## 「敌人逼近到这个进度还没死」就算一次真正的紧张
const THREAT := 0.75


## 三档模拟玩家。只有极好/极差两端量不出手感——真实玩家在中间,
## 「随手放」这一档才代表第一次上手的人,难度曲线要对着它调。
const MODES := [
	["good", "会玩(挑覆盖最大的格子)"],
	["mid", "随手放(第一个空格就放)"],
	["bad", "乱放(挑覆盖最小的格子)"],
]


func _initialize() -> void:
	if "--sweep" in OS.get_cmdline_user_args():
		_sweep()
		quit(0)
		return
	for m in MODES:
		_pressure_curve(String(m[1]), String(m[0]))
	print("")
	_prep_agency()
	print("")
	_attribution()
	quit(0)


## 扫难度旋钮网格,一次跑完看形状,别手调两个变量猜五轮。
## 目标形状: 会玩的**险胜通关**(赢 + 有险波) / 随手放的死在中后段 / 前中期不能全程碾压。
func _sweep() -> void:
	print("PROBE_SWEEP base growth | good:胜 波数 险波 平均推进%% | mid:波数 | bad:波数")
	for base in [14.0, 17.0, 20.0, 23.0]:
		for growth in [1.15, 1.18, 1.21, 1.24]:
			var g := _play(base, growth, "good")
			var m := _play(base, growth, "mid")
			var b := _play(base, growth, "bad")
			print("PROBE_SWEEP %4.0f %5.2f | %-5s %2d %2d %3d%% | %2d | %2d" % [
				base, growth, g["victory"], g["waves"], g["threat"], g["avg_deep"],
				m["waves"], b["waves"]])


## 跑一整局,返回形状指标
func _play(base: float, growth: float, mode: String) -> Dictionary:
	var sim = Sim.new()
	sim.hp_base = base
	sim.hp_growth = growth
	var guard := 0
	while not sim.is_round_over() and guard < 40000:
		guard += 1
		if sim.phase == sim.PHASE_PREP:
			_buy(sim, mode)
		sim.tick(DT)
	var threat := 0
	var deep_sum := 0.0
	for r in sim.wave_log:
		if float(r["deepest"]) >= THREAT and int(r["hp"]) > 0:
			threat += 1
		deep_sum += float(r["deepest"])
	var n: int = maxi(sim.wave_log.size(), 1)
	return {
		"victory": sim.is_victory(), "waves": sim.waves_cleared, "threat": threat,
		"avg_deep": int(round(deep_sum / float(n) * 100.0)), "seconds": sim.elapsed,
	}


## 余量曲线:每波结束时晶核还剩多少。
## 全程 10 = 没有紧张(赢得毫无悬念);一路直落 = 没有把握(输得莫名其妙)。
func _pressure_curve(label: String, mode: String) -> void:
	var sim = Sim.new()
	var guard := 0
	while not sim.is_round_over() and guard < 40000:
		guard += 1
		if sim.phase == sim.PHASE_PREP:
			_buy(sim, mode)
		sim.tick(DT)

	var hp_curve: Array = []
	var deep_curve: Array = []
	# 险波 = 敌人逼近过晶核(推进 ≥ THREAT)但没破核。**紧张感的真实来源在这儿**,
	# 不在漏怪数——一波全部死在路径 95% 处,漏怪 0,但玩家全程屏住呼吸。
	var threat := 0
	for r in sim.wave_log:
		hp_curve.append(int(r["hp"]))
		deep_curve.append(int(round(float(r["deepest"]) * 100.0)))
		if float(r["deepest"]) >= THREAT and int(r["hp"]) > 0:
			threat += 1
	print("PROBE_PRESSURE %-24s victory=%-5s waves=%2d/%d 用时=%.0fs 险波=%d" % [
		label, sim.is_victory(), sim.waves_cleared, sim.waves_total(), sim.elapsed, threat])
	print("PROBE_PRESSURE %-24s 晶核=%s" % [label, str(hp_curve)])
	print("PROBE_PRESSURE %-24s 最深推进%%=%s" % [label, str(deep_curve)])


## 每个备战窗口,玩家是不是真的有事可做?
## 「波间松一口气」的前提是**松的时候有得选**;买不起任何塔 = 只能干等倒计时,
## 那不是喘息,是空转。
func _prep_agency() -> void:
	var sim = Sim.new()
	var min_cost: int = mini(sim.cost_of(&"fire"), sim.cost_of(&"ice"))
	var idle := 0
	var total := 0
	var seen := -1
	var guard := 0
	while not sim.is_round_over() and guard < 40000:
		guard += 1
		if sim.phase == sim.PHASE_PREP and sim.wave != seen:
			seen = sim.wave
			total += 1
			var afford: bool = sim.gold >= min_cost
			var space: bool = _has_space(sim)
			if not (afford and space):
				idle += 1
				print("PROBE_PREP  第%d波前 无事可做 gold=%d(最低%d) 有空格=%s" % [
					sim.wave + 1, sim.gold, min_cost, space])
		if sim.phase == sim.PHASE_PREP:
			_buy(sim, "good")
		sim.tick(DT)
	print("PROBE_PREP  备战窗口 %d 个,其中「只能干等」%d 个" % [total, idle])


## 输了之后,结算里的信息够不够让玩家知道「下一局该改什么」?
## 这里只列 summary() 实际给了什么 —— 缺什么一眼可见。
func _attribution() -> void:
	var sim = Sim.new()
	var guard := 0
	while not sim.is_round_over() and guard < 40000:
		guard += 1
		if sim.phase == sim.PHASE_PREP:
			_buy(sim, "bad")
		sim.tick(DT)
	var s: Dictionary = sim.summary()
	print("PROBE_ATTR  首次掉血=第%d波 逐波账本=%s" % [int(s["first_leak_wave"]), str(s["wave_log"])])
	print("PROBE_ATTR  能否回答「哪一波开始扛不住」: %s" % (
		"能" if int(s["first_leak_wave"]) > 0 else "不能"))


func _has_space(sim) -> bool:
	for row in sim.ROWS:
		for col in sim.COLS:
			if sim.can_place(col, row):
				return true
	return false


## 模拟玩家:优先加塔;加不动了(没钱/没格子)就升级。
## 升级路径必须模拟,否则量到的还是「只会铺满」的旧行为。
func _buy(sim, mode: String) -> void:
	while true:
		var type: StringName = &"fire" if sim.tower_count() % 3 != 2 else &"ice"
		var cell := _pick_cell(sim, sim.range_of(type), mode)
		if cell.x >= 0 and sim.gold >= sim.cost_of(type):
			if sim.place_tower(cell.x, cell.y, type):
				continue
		if not _upgrade_one(sim, mode):
			return


func _upgrade_one(sim, mode: String) -> bool:
	# 「随手放」的玩家也会升级(按钮就在那儿),只是不挑升哪座
	var best_key := ""
	var best_cov := -1.0 if mode == "good" else 1e9
	for k in sim.towers.keys():
		var tw: Dictionary = sim.towers[k]
		var col := int(tw["col"])
		var row := int(tw["row"])
		if not sim.can_upgrade(col, row):
			continue
		if mode == "mid":
			return sim.upgrade_tower(col, row)
		var cov: float = sim.coverage_at(col, row, float(tw["range"]))
		var better: bool = cov > best_cov if mode == "good" else cov < best_cov
		if better:
			best_cov = cov
			best_key = k
	if best_key == "":
		return false
	var t: Dictionary = sim.towers[best_key]
	return sim.upgrade_tower(int(t["col"]), int(t["row"]))


func _pick_cell(sim, rng: float, mode: String) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_cov := -1.0 if mode == "good" else 1e9
	for row in sim.ROWS:
		for col in sim.COLS:
			if not sim.can_place(col, row):
				continue
			if mode == "mid":
				return Vector2i(col, row)   # 不挑,第一个空格就放
			var cov: float = sim.coverage_at(col, row, rng)
			var better: bool = cov > best_cov if mode == "good" else cov < best_cov
			if better:
				best_cov = cov
				best = Vector2i(col, row)
	return best
