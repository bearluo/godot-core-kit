extends RefCounted
## 模拟玩家:三档打法,给 feel_probe(调参)和 test_crystal_line_sim(回归断言)共用。
##
## ⚠️ 抽出来共用是有理由的:「会玩的玩家能不能通关」**既是调参依据、又是回归断言**。
##    两边各写一份的话,调参调的是 A 模型、测试测的是 B 模型,数值调好了测试照样红,
##    或者更糟——测试绿着而实际手感是照另一个模型调的。
##
## 三档不是凑数:只有极好/极差两端量不出手感,真实玩家在中间,
## 难度曲线要对着 MID 调(见 docs/vision/experience-checkpoint.md)。

const GOOD := "good"   # 每次挑覆盖路径最长的空格;升级也挑覆盖最大的那座
const MID := "mid"     # 不挑,第一个空格就放 —— 代表第一次上手的人
const BAD := "bad"     # 每次挑覆盖最小的空格 —— 下界

var mode: String = GOOD


func _init(p_mode: String = GOOD) -> void:
	mode = p_mode


## 完整跑一局(备战窗口花钱 → tick 到局终)。返回跑完的 sim 便于链式取数。
func play(sim, dt: float = 0.05, max_steps: int = 40000):
	var guard := 0
	while not sim.is_round_over() and guard < max_steps:
		guard += 1
		if sim.phase == sim.PHASE_PREP:
			spend(sim)
		sim.tick(dt)
	return sim


## 在一个备战窗口里把能花的钱花掉:优先加塔,加不动(没钱/没空格)就升级。
func spend(sim) -> void:
	while true:
		var type: StringName = &"fire" if sim.tower_count() % 3 != 2 else &"ice"
		var cell := pick_cell(sim, sim.range_of(type))
		if cell.x >= 0 and sim.gold >= sim.cost_of(type):
			if sim.place_tower(cell.x, cell.y, type):
				continue
		if not upgrade_one(sim):
			return


func pick_cell(sim, rng: float) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_cov := -1.0 if mode == GOOD else 1e9
	for row in sim.ROWS:
		for col in sim.COLS:
			if not sim.can_place(col, row):
				continue
			if mode == MID:
				return Vector2i(col, row)
			var cov: float = sim.coverage_at(col, row, rng)
			var better: bool = cov > best_cov if mode == GOOD else cov < best_cov
			if better:
				best_cov = cov
				best = Vector2i(col, row)
	return best


func upgrade_one(sim) -> bool:
	var best_key := ""
	var best_cov := -1.0 if mode == GOOD else 1e9
	for k in sim.towers.keys():
		var tw: Dictionary = sim.towers[k]
		var col := int(tw["col"])
		var row := int(tw["row"])
		if not sim.can_upgrade(col, row):
			continue
		if mode == MID:
			return sim.upgrade_tower(col, row)
		var cov: float = sim.coverage_at(col, row, float(tw["range"]))
		var better: bool = cov > best_cov if mode == GOOD else cov < best_cov
		if better:
			best_cov = cov
			best_key = k
	if best_key == "":
		return false
	var t: Dictionary = sim.towers[best_key]
	return sim.upgrade_tower(int(t["col"]), int(t["row"]))
