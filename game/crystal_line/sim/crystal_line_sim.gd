class_name CrystalLineSim
extends RefCounted
## 《晶核防线》纯逻辑模拟——无 Node,headless 可测。
## 一局 = 备战/波次交替推进 WAVES_TO_WIN 波:全清 = 胜利,晶核破 = 失败。
## 路径是**蜿蜒**的(见 PATH):同数量同类型的塔,摆在不同格子结果显著不同。

const COLS := 5
const ROWS := 8

## 裂隙路径:顶部裂口 → 折返三段 → 底部晶核。相邻两点必须正交相邻。
## 布局(# = 路径,. = 可建造,C = 晶核):
##   . . # . .
##   # # # . .
##   # . . . .
##   # # # # #
##   . . . . #
##   # # # # #
##   # . . . .
##   # # C . .
## 中间两条横向长廊(row3 / row5)夹着 row4 的四个可建造格 —— 站在那里的一座塔
## 能同时覆盖两段长廊;而右上角 (4,0)/(4,1) 附近的格子几乎覆盖不到路径。
## 「放哪一格」因此是真决策,不再等价于「放第几行」。
const PATH: Array[Vector2i] = [
	Vector2i(2, 0), Vector2i(2, 1),
	Vector2i(1, 1), Vector2i(0, 1),
	Vector2i(0, 2), Vector2i(0, 3),
	Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3),
	Vector2i(4, 4), Vector2i(4, 5),
	Vector2i(3, 5), Vector2i(2, 5), Vector2i(1, 5), Vector2i(0, 5),
	Vector2i(0, 6), Vector2i(0, 7),
	Vector2i(1, 7), Vector2i(2, 7),
]

const TOWER_DEFS := {
	&"fire": {"cost": 40, "dmg": 8.0, "range": 1.6, "cd": 0.45, "slow": 0.0},
	&"ice": {"cost": 45, "dmg": 4.0, "range": 1.9, "cd": 0.55, "slow": 0.45},
}

## 一局参数(整局时长 = WAVES_TO_WIN 波的战斗 + 波间备战,详见 test_crystal_line_sim)
const WAVES_TO_WIN := 14
const START_GOLD := 100     # 火 40 + 冰 45 = 85,开局即可同时拥有两种塔
const START_HP := 10
const PREP_FIRST := 8.0     # 第一波前的建造窗口
const PREP_BETWEEN := 6.0   # 波间「松一口气」窗口
const SPAWN_INTERVAL := 0.7
const ENEMY_SPEED := 1.0    # 格/秒
const SLOW_RECOVER := 0.35  # 减速每秒回复量

const PHASE_PREP := &"prep"
const PHASE_WAVE := &"wave"
const PHASE_VICTORY := &"victory"
const PHASE_DEFEAT := &"defeat"

var gold: int = START_GOLD
var core_hp: int = START_HP
var wave: int = 0
var phase: StringName = PHASE_PREP
var prep_left: float = PREP_FIRST
var wave_active: bool = false
var spawn_left: int = 0
var spawn_cd: float = 0.0
var towers: Dictionary = {}  # "x,y" -> {type, col, row, dmg, range, cd, t, slow, aim, has_aim}
var enemies: Array = []      # {t 路程(格), hp, max_hp, slow}
var last_event: String = ""
var waves_cleared: int = 0
var gold_earned: int = 0
var kills: int = 0
var leaks: int = 0
var elapsed: float = 0.0     # 本局已进行的游戏内秒数(备战 + 战斗)
## 表现层消费:本 tick 发生的开火。{from:Vector2(格坐标), to:Vector2, kill:bool, type:StringName}
var shots: Array = []
var hits: int = 0            # 累计命中次数(表现层据此节流播 hit 音)

var _path_cells: Dictionary = {}


func _init() -> void:
	for p in PATH:
		_path_cells[_key(p.x, p.y)] = true


func reset() -> void:
	gold = START_GOLD
	core_hp = START_HP
	wave = 0
	phase = PHASE_PREP
	prep_left = PREP_FIRST
	wave_active = false
	spawn_left = 0
	spawn_cd = 0.0
	towers.clear()
	enemies.clear()
	shots.clear()
	last_event = "reset"
	waves_cleared = 0
	gold_earned = 0
	kills = 0
	leaks = 0
	hits = 0
	elapsed = 0.0


# ---------------------------------------------------------------- 路径 / 几何

func is_path_cell(col: int, row: int) -> bool:
	return _path_cells.has(_key(col, row))


func core_cell() -> Vector2i:
	return PATH[PATH.size() - 1]


func path_length() -> float:
	return float(PATH.size() - 1)


## 路程 t(单位:格)→ 格坐标(浮点,格中心为整数坐标)
func path_point(t: float) -> Vector2:
	var last := PATH.size() - 1
	var tc := clampf(t, 0.0, float(last))
	var i := int(floor(tc))
	if i >= last:
		return Vector2(PATH[last])
	return Vector2(PATH[i]).lerp(Vector2(PATH[i + 1]), tc - float(i))


func enemy_point(e: Dictionary) -> Vector2:
	return path_point(float(e["t"]))


## 某格上一座射程 rng 的塔能覆盖多长的路径(单位:格)。UI 用它做站位提示,
## 测试用它证明「不同格子的覆盖长度确实不同」。
func coverage_at(col: int, row: int, rng: float) -> float:
	var step := 0.05
	var covered := 0.0
	var origin := Vector2(float(col), float(row))
	var t := 0.0
	var total := path_length()
	while t <= total:
		if origin.distance_to(path_point(t)) <= rng:
			covered += step
		t += step
	return covered


# ---------------------------------------------------------------- 建造

func can_place(col: int, row: int) -> bool:
	if is_round_over():
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
		"aim": Vector2.ZERO,
		"has_aim": false,
	}
	last_event = "placed"
	return true


func cost_of(type: StringName) -> int:
	return int(TOWER_DEFS.get(type, {}).get("cost", 0))


func range_of(type: StringName) -> float:
	return float(TOWER_DEFS.get(type, {}).get("range", 0.0))


# ---------------------------------------------------------------- 一局流程

## 立即开波(跳过剩余备战)。备战阶段外一律拒绝。
func start_wave() -> bool:
	if phase != PHASE_PREP:
		last_event = "wave_denied"
		return false
	_begin_wave()
	return true


func is_game_over() -> bool:
	return phase == PHASE_DEFEAT


func is_victory() -> bool:
	return phase == PHASE_VICTORY


func is_round_over() -> bool:
	return phase == PHASE_VICTORY or phase == PHASE_DEFEAT


func waves_total() -> int:
	return WAVES_TO_WIN


## 结算面板 / 报告用
func summary() -> Dictionary:
	return {
		"victory": is_victory(),
		"waves_cleared": waves_cleared,
		"waves_total": WAVES_TO_WIN,
		"core_hp": core_hp,
		"kills": kills,
		"leaks": leaks,
		"towers": tower_count(),
		"gold_earned": gold_earned,
		"seconds": elapsed,
	}


func tick(dt: float) -> void:
	shots.clear()
	if is_round_over():
		_clear_aims()
		return
	elapsed += dt
	if phase == PHASE_PREP:
		_clear_aims()
		prep_left -= dt
		if prep_left <= 0.0:
			_begin_wave()
		return
	_spawn(dt)
	_towers_fire(dt)
	_move_enemies(dt)
	if phase != PHASE_WAVE:
		return
	if spawn_left <= 0 and enemies.is_empty():
		wave_active = false
		waves_cleared += 1
		var bonus := 12 + wave * 3
		gold += bonus
		gold_earned += bonus
		if waves_cleared >= WAVES_TO_WIN:
			phase = PHASE_VICTORY
			last_event = "victory"
		else:
			phase = PHASE_PREP
			prep_left = PREP_BETWEEN
			last_event = "wave_clear"


func tower_count() -> int:
	return towers.size()


func enemy_count() -> int:
	return enemies.size()


func wave_size(w: int) -> int:
	return 5 + w * 2


func _begin_wave() -> void:
	wave += 1
	spawn_left = wave_size(wave)
	spawn_cd = 0.0
	wave_active = true
	phase = PHASE_WAVE
	prep_left = 0.0
	last_event = "wave_start"


func _spawn(dt: float) -> void:
	if spawn_left <= 0:
		return
	spawn_cd -= dt
	if spawn_cd > 0.0:
		return
	spawn_left -= 1
	spawn_cd = SPAWN_INTERVAL
	# 前中段线性、后段(第 9 波起)二次加压 —— 让「差一格就破核」在末尾真的发生
	var over := maxf(0.0, float(wave - 8))
	var hp := 16.0 + wave * 7.0 + over * over * 1.2
	enemies.append({"t": 0.0, "hp": hp, "max_hp": hp, "slow": 1.0})


func _towers_fire(dt: float) -> void:
	for k in towers.keys():
		var tw: Dictionary = towers[k]
		tw["t"] = float(tw["t"]) - dt
		var tpos := Vector2(float(tw["col"]), float(tw["row"]))
		# 每 tick 都锁定目标(不受冷却影响),表现层据此画连续的瞄准线。
		var best_i := -1
		var best_d := 1e9
		for i in enemies.size():
			var d := tpos.distance_to(enemy_point(enemies[i]))
			if d <= float(tw["range"]) and d < best_d:
				best_d = d
				best_i = i
		if best_i < 0:
			tw["has_aim"] = false
			continue
		var e: Dictionary = enemies[best_i]
		tw["aim"] = enemy_point(e)
		tw["has_aim"] = true
		if float(tw["t"]) > 0.0:
			continue
		tw["t"] = float(tw["cd"])
		e["hp"] = float(e["hp"]) - float(tw["dmg"])
		if float(tw["slow"]) > 0.0:
			e["slow"] = minf(float(e["slow"]), 1.0 - float(tw["slow"]))
		var killed: bool = float(e["hp"]) <= 0.0
		hits += 1
		shots.append({
			"from": tpos,
			"to": Vector2(tw["aim"]),
			"kill": killed,
			"type": tw["type"],
		})
		if killed:
			enemies.remove_at(best_i)
			kills += 1
			var gain := 5 + wave
			gold += gain
			gold_earned += gain


func _move_enemies(dt: float) -> void:
	var goal := path_length()
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		var speed := ENEMY_SPEED * float(e["slow"])
		e["t"] = float(e["t"]) + speed * dt
		e["slow"] = minf(1.0, float(e["slow"]) + dt * SLOW_RECOVER)
		if float(e["t"]) >= goal:
			enemies.remove_at(i)
			leaks += 1
			core_hp -= 1
			last_event = "leak"
			if core_hp <= 0:
				core_hp = 0
				wave_active = false
				phase = PHASE_DEFEAT
				last_event = "defeat"
				return
			continue
		i += 1


## 非战斗阶段清掉瞄准状态,免得表现层画出「打空气」的残留瞄准线
func _clear_aims() -> void:
	for k in towers.keys():
		towers[k]["has_aim"] = false


func _key(col: int, row: int) -> String:
	return "%d,%d" % [col, row]
