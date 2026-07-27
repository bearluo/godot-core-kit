class_name CrystalLineSim
extends RefCounted
## 《晶核防线》纯逻辑模拟——无 Node,headless 可测。
## 波次塔防:路径纵向,两侧可放塔;火塔高伤,冰塔减速。

const COLS := 5
const ROWS := 8
const PATH_COL := 2

const TOWER_DEFS := {
	&"fire": {"cost": 40, "dmg": 8.0, "range": 1.6, "cd": 0.45, "slow": 0.0},
	&"ice": {"cost": 45, "dmg": 4.0, "range": 1.9, "cd": 0.55, "slow": 0.45},
}

var gold: int = 80
var core_hp: int = 10
var wave: int = 0
var wave_active: bool = false
var spawn_left: int = 0
var spawn_cd: float = 0.0
var towers: Dictionary = {}  # "x,y" -> {type, dmg, range, cd, t, slow}
var enemies: Array = []      # {row_pos 0..ROWS, hp, max_hp, slow}
var last_event: String = ""
var waves_cleared: int = 0
var gold_earned: int = 0


func reset() -> void:
	gold = 80
	core_hp = 10
	wave = 0
	wave_active = false
	spawn_left = 0
	spawn_cd = 0.0
	towers.clear()
	enemies.clear()
	last_event = "reset"
	waves_cleared = 0
	gold_earned = 0


func can_place(col: int, row: int) -> bool:
	if core_hp <= 0:
		return false
	if col < 0 or row < 0 or col >= COLS or row >= ROWS:
		return false
	if col == PATH_COL:
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
	if wave_active or core_hp <= 0:
		last_event = "wave_denied"
		return false
	wave += 1
	spawn_left = 4 + wave * 2
	spawn_cd = 0.0
	wave_active = true
	last_event = "wave_start"
	return true


func tick(dt: float) -> void:
	if not wave_active or core_hp <= 0:
		return
	_spawn(dt)
	_towers_fire(dt)
	_move_enemies(dt)
	if spawn_left <= 0 and enemies.is_empty():
		wave_active = false
		waves_cleared += 1
		var bonus := 15
		gold += bonus
		gold_earned += bonus
		last_event = "wave_clear"


func is_game_over() -> bool:
	return core_hp <= 0


func tower_count() -> int:
	return towers.size()


func enemy_count() -> int:
	return enemies.size()


func _spawn(dt: float) -> void:
	if spawn_left <= 0:
		return
	spawn_cd -= dt
	if spawn_cd > 0.0:
		return
	spawn_left -= 1
	spawn_cd = 0.55
	var hp := 18.0 + wave * 6.0
	enemies.append({"row_pos": 0.0, "hp": hp, "max_hp": hp, "slow": 1.0})


func _towers_fire(dt: float) -> void:
	for k in towers.keys():
		var tw: Dictionary = towers[k]
		tw["t"] = float(tw["t"]) - dt
		if float(tw["t"]) > 0.0:
			continue
		var best_i := -1
		var best_d := 9999.0
		var tc := float(tw["col"])
		var tr := float(tw["row"])
		for i in enemies.size():
			var er := float(enemies[i]["row_pos"])
			# 路径在 PATH_COL,塔在侧格;距离用格子度量
			var d: float = Vector2(tc, tr).distance_to(Vector2(float(PATH_COL), er))
			if d <= float(tw["range"]) and d < best_d:
				best_d = d
				best_i = i
		if best_i < 0:
			continue
		tw["t"] = float(tw["cd"])
		enemies[best_i]["hp"] = float(enemies[best_i]["hp"]) - float(tw["dmg"])
		if float(tw["slow"]) > 0.0:
			enemies[best_i]["slow"] = 1.0 - float(tw["slow"])
		if float(enemies[best_i]["hp"]) <= 0.0:
			enemies.remove_at(best_i)
			var gain := 6 + wave
			gold += gain
			gold_earned += gain


func _move_enemies(dt: float) -> void:
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		var speed := 1.35 * float(e["slow"])  # 行/秒
		e["row_pos"] = float(e["row_pos"]) + speed * dt
		e["slow"] = minf(1.0, float(e["slow"]) + dt * 0.35)
		if float(e["row_pos"]) >= float(ROWS - 1) + 0.5:
			enemies.remove_at(i)
			core_hp -= 1
			last_event = "leak"
			if core_hp <= 0:
				wave_active = false
				last_event = "defeat"
			continue
		i += 1


func _key(col: int, row: int) -> String:
	return "%d,%d" % [col, row]
