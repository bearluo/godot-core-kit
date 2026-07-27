class_name CrystalLineSim
extends RefCounted
## 《晶核防线》纯逻辑模拟——无 Node,headless 可测。
## 波次塔防:蜿蜒路径,两侧可放塔;火塔高伤,冰塔减速。
## 一局:守住晶核清完 WIN_WAVES 波 = 胜利;核破 = 失败。

const COLS := 5
const ROWS := 8
## 蜿蜒路径(spawn → 晶核)。晶核在路径终点(顶部),敌人自底部涌入。
## 布局让「拐弯外侧」与「远端死角」覆盖长度显著不同 → 站位有决策。
const PATH: Array[Vector2i] = [
	Vector2i(2, 7), # spawn
	Vector2i(2, 6),
	Vector2i(2, 5),
	Vector2i(1, 5),
	Vector2i(0, 5),
	Vector2i(0, 4),
	Vector2i(0, 3),
	Vector2i(0, 2),
	Vector2i(1, 2),
	Vector2i(2, 2),
	Vector2i(3, 2),
	Vector2i(4, 2),
	Vector2i(4, 1),
	Vector2i(4, 0),
	Vector2i(3, 0),
	Vector2i(2, 0), # crystal (top)
]
const PATH_LEN := 16  # PATH.size(); kept explicit for clarity in tests
const CORE_CELL := Vector2i(2, 0)
const SPAWN_CELL := Vector2i(2, 7)

## 通关波数。估算:波间构筑 15–25s + 波内 20–35s × 8 ≈ 5–8 分钟(见 fix-report)。
const WIN_WAVES := 8

const TOWER_DEFS := {
	&"fire": {"cost": 40, "dmg": 8.0, "range": 1.75, "cd": 0.45, "slow": 0.0},
	&"ice": {"cost": 45, "dmg": 4.0, "range": 2.0, "cd": 0.55, "slow": 0.45},
}

## 起始金:火 40 + 冰 45 = 85,留少量余量 → 开局可同时拥有两种塔(CL-007)。
const START_GOLD := 100
const START_HP := 10

var gold: int = START_GOLD
var core_hp: int = START_HP
var wave: int = 0
var wave_active: bool = false
var spawn_left: int = 0
var spawn_cd: float = 0.0
var towers: Dictionary = {}  # "x,y" -> {type, col, row, dmg, range, cd, t, slow}
var enemies: Array = []      # {path_pos 0..PATH_LEN, hp, max_hp, slow}
var last_event: String = ""
var waves_cleared: int = 0
var gold_earned: int = 0
var leaks: int = 0
var kills: int = 0
## 本 tick 命中次数(UI 播 hit 音效用)
var hits_this_tick: int = 0
## 短时弹道/射线 {from_col, from_row, to_col, to_row, life}
var shots: Array = []
## "" | "victory" | "defeat"
var outcome: String = ""


func reset() -> void:
	gold = START_GOLD
	core_hp = START_HP
	wave = 0
	wave_active = false
	spawn_left = 0
	spawn_cd = 0.0
	towers.clear()
	enemies.clear()
	last_event = "reset"
	waves_cleared = 0
	gold_earned = 0
	leaks = 0
	kills = 0
	hits_this_tick = 0
	shots.clear()
	outcome = ""


func is_path_cell(col: int, row: int) -> bool:
	return PATH.has(Vector2i(col, row))


func path_index_of(col: int, row: int) -> int:
	return PATH.find(Vector2i(col, row))


func enemy_cell(e: Dictionary) -> Vector2i:
	var p: float = float(e["path_pos"])
	var i: int = clampi(int(floor(p)), 0, PATH_LEN - 1)
	return PATH[i]


func enemy_world_pos(e: Dictionary) -> Vector2:
	## 连续坐标:在路径格子之间插值(格子中心)。
	var p: float = clampf(float(e["path_pos"]), 0.0, float(PATH_LEN - 1))
	var i0: int = clampi(int(floor(p)), 0, PATH_LEN - 1)
	var i1: int = mini(i0 + 1, PATH_LEN - 1)
	var t: float = p - float(i0)
	var a: Vector2 = Vector2(PATH[i0]) + Vector2(0.5, 0.5)
	var b: Vector2 = Vector2(PATH[i1]) + Vector2(0.5, 0.5)
	return a.lerp(b, t)


func can_place(col: int, row: int) -> bool:
	if outcome != "":
		return false
	if core_hp <= 0:
		return false
	if col < 0 or row < 0 or col >= COLS or row >= ROWS:
		return false
	if is_path_cell(col, row):
		return false
	return not towers.has(_key(col, row))


func place_tower(col: int, row: int, type: StringName) -> bool:
	if not can_place(col, row):
		last_event = "place_denied"
		return false
	if not TOWER_DEFS.has(type):
		last_event = "bad_type"
		return false
	var def: Dictionary = TOWER_DEFS[type]
	var cost: int = int(def["cost"])
	if gold < cost:
		last_event = "no_gold"
		return false
	gold -= cost
	towers[_key(col, row)] = {
		"type": type,
		"col": col,
		"row": row,
		"dmg": float(def["dmg"]),
		"range": float(def["range"]),
		"cd": float(def["cd"]),
		"t": 0.0,
		"slow": float(def["slow"]),
	}
	last_event = "placed"
	return true


func start_wave() -> bool:
	if outcome != "":
		last_event = "wave_denied"
		return false
	if wave_active or core_hp <= 0:
		last_event = "wave_denied"
		return false
	if waves_cleared >= WIN_WAVES:
		last_event = "wave_denied"
		return false
	wave += 1
	spawn_left = 4 + wave * 2
	spawn_cd = 0.0
	wave_active = true
	last_event = "wave_start"
	return true


func tick(dt: float) -> void:
	hits_this_tick = 0
	_age_shots(dt)
	if outcome != "":
		return
	if not wave_active or core_hp <= 0:
		return
	_spawn(dt)
	_towers_fire(dt)
	_move_enemies(dt)
	if spawn_left <= 0 and enemies.is_empty() and outcome == "":
		wave_active = false
		waves_cleared += 1
		var bonus := 15 + wave * 2
		gold += bonus
		gold_earned += bonus
		if waves_cleared >= WIN_WAVES:
			outcome = "victory"
			last_event = "victory"
		else:
			last_event = "wave_clear"


func is_game_over() -> bool:
	return outcome == "victory" or outcome == "defeat" or core_hp <= 0


func is_victory() -> bool:
	return outcome == "victory"


func is_defeat() -> bool:
	return outcome == "defeat" or (core_hp <= 0 and outcome != "victory")


func tower_count() -> int:
	return towers.size()


func enemy_count() -> int:
	return enemies.size()


## 估算一局玩家时长(秒):构筑喘息 + 波内刷怪/行进。用于文档与测试旁证。
static func estimate_session_seconds() -> Dictionary:
	var build_per_wave := 20.0  # 玩家点塔/思考
	var combat := 0.0
	for w in range(1, WIN_WAVES + 1):
		var n: int = 4 + w * 2
		var spawn_span: float = float(n) * 0.55
		var travel: float = float(PATH_LEN) / 1.2  # 平均有效速度(含减速)
		combat += maxf(spawn_span, travel) + 6.0  # 清场余量
	var total: float = float(WIN_WAVES) * build_per_wave + combat
	return {
		"win_waves": WIN_WAVES,
		"build_per_wave_s": build_per_wave,
		"combat_total_s": combat,
		"estimate_s": total,
		"estimate_min": total / 60.0,
	}


func _spawn(dt: float) -> void:
	if spawn_left <= 0:
		return
	spawn_cd -= dt
	if spawn_cd > 0.0:
		return
	spawn_left -= 1
	spawn_cd = 0.55
	var hp := 16.0 + wave * 5.0
	enemies.append({"path_pos": 0.0, "hp": hp, "max_hp": hp, "slow": 1.0})


func _towers_fire(dt: float) -> void:
	for k in towers.keys():
		var tw: Dictionary = towers[k]
		tw["t"] = float(tw["t"]) - dt
		if float(tw["t"]) > 0.0:
			continue
		var best_i := -1
		var best_d := 9999.0
		var tc := float(tw["col"]) + 0.5
		var tr := float(tw["row"]) + 0.5
		for i in enemies.size():
			var pos: Vector2 = enemy_world_pos(enemies[i])
			var d: float = Vector2(tc, tr).distance_to(pos)
			if d <= float(tw["range"]) and d < best_d:
				best_d = d
				best_i = i
		if best_i < 0:
			continue
		tw["t"] = float(tw["cd"])
		var epos: Vector2 = enemy_world_pos(enemies[best_i])
		shots.append({
			"from_col": float(tw["col"]) + 0.5,
			"from_row": float(tw["row"]) + 0.5,
			"to_col": epos.x,
			"to_row": epos.y,
			"life": 0.18,
			"type": tw["type"],
		})
		enemies[best_i]["hp"] = float(enemies[best_i]["hp"]) - float(tw["dmg"])
		hits_this_tick += 1
		if float(tw["slow"]) > 0.0:
			enemies[best_i]["slow"] = 1.0 - float(tw["slow"])
		if float(enemies[best_i]["hp"]) <= 0.0:
			enemies.remove_at(best_i)
			kills += 1
			var gain := 6 + wave
			gold += gain
			gold_earned += gain


func _move_enemies(dt: float) -> void:
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		var speed := 1.2 * float(e["slow"])  # 路径格/秒
		e["path_pos"] = float(e["path_pos"]) + speed * dt
		e["slow"] = minf(1.0, float(e["slow"]) + dt * 0.35)
		if float(e["path_pos"]) >= float(PATH_LEN - 1) + 0.45:
			enemies.remove_at(i)
			core_hp -= 1
			leaks += 1
			last_event = "leak"
			if core_hp <= 0:
				core_hp = 0
				wave_active = false
				outcome = "defeat"
				last_event = "defeat"
			continue
		i += 1


func _age_shots(dt: float) -> void:
	var i := 0
	while i < shots.size():
		shots[i]["life"] = float(shots[i]["life"]) - dt
		if float(shots[i]["life"]) <= 0.0:
			shots.remove_at(i)
			continue
		i += 1


func _key(col: int, row: int) -> String:
	return "%d,%d" % [col, row]
