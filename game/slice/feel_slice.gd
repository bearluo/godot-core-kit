extends Control
## 阶段 1 · 抛弃式手感切片《晶核防线》
## 只验证核心瞬间:点格放塔 → 召唤反馈 → 怪入场被打 → 清波松一口气。
## 不接 CoreKit、不接 asset-bank、不写测试——感觉对了再 productionize。
## 运行: 把 project main 临时指到 res://game/slice/feel_slice.tscn,或
##   godot --path . res://game/slice/feel_slice.tscn

const COL_BG := Color("1a1f3a")
const COL_PATH := Color("3d4a6b")
const COL_CORE := Color("e74c5e")
const COL_FIRE := Color("e67e22")
const COL_ICE := Color("4fc3f7")
const COL_GOLD_UI := Color("f1c40f")
const COL_ENEMY := Color("c0392b")
const COL_TEXT := Color("ecf0f1")

const COLS := 5
const ROWS := 8
const CELL := 96.0
const PATH_COL := 2

var gold: int = 80
var core_hp: int = 10
var wave: int = 0
var selected: StringName = &"fire"
var towers: Dictionary = {}   # Vector2i -> {type, dmg, range, cd, t}
var enemies: Array = []       # {pos:float 0..1 along path, hp, max_hp, slow}
var spawn_left: int = 0
var spawn_cd: float = 0.0
var wave_active: bool = false
var msg: String = "选塔 → 点路径旁格子。守住晶核。"
var juice: float = 0.0        # 放塔闪白
var juice_cell: Vector2i = Vector2i(-1, -1)
var clear_flash: float = 0.0

@onready var _info: Label = $VBox/Info
@onready var _board: Control = $VBox/Board
@onready var _hint: Label = $VBox/Hint


func _ready() -> void:
	# 竖屏意图
	custom_minimum_size = Vector2(720, 1280)
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_refresh_ui()
	_board.draw.connect(_draw_board)
	_board.gui_input.connect(_on_board_input)
	$VBox/Bar/Fire.pressed.connect(func(): selected = &"fire"; _refresh_ui())
	$VBox/Bar/Ice.pressed.connect(func(): selected = &"ice"; _refresh_ui())
	$VBox/Bar/Wave.pressed.connect(_start_wave)


func _process(dt: float) -> void:
	juice = maxf(0.0, juice - dt * 3.0)
	clear_flash = maxf(0.0, clear_flash - dt * 2.0)
	if wave_active:
		_tick_combat(dt)
	_board.queue_redraw()
	_refresh_ui()


func _refresh_ui() -> void:
	var cost := _cost(selected)
	_info.text = "晶核 %d  |  金 %d  |  波 %d  |  选中 %s(%d金)" % [
		core_hp, gold, wave, selected, cost]
	_hint.text = msg
	if core_hp <= 0:
		_hint.text = "破核了——换站位再来一局。(R 重置)"
	elif clear_flash > 0.0:
		_hint.text = "清波! 松一口气。再构筑,再开一波。"


func _cost(t: StringName) -> int:
	match t:
		&"ice":
			return 45
		_:
			return 40


func _start_wave() -> void:
	if wave_active or core_hp <= 0:
		return
	wave += 1
	spawn_left = 4 + wave * 2
	spawn_cd = 0.0
	wave_active = true
	msg = "第 %d 波来了——塔在打,你在看构筑对不对。" % wave


func _tick_combat(dt: float) -> void:
	# 刷怪
	if spawn_left > 0:
		spawn_cd -= dt
		if spawn_cd <= 0.0:
			spawn_left -= 1
			spawn_cd = 0.55
			enemies.append({
				"pos": 0.0,
				"hp": 18.0 + wave * 6.0,
				"max_hp": 18.0 + wave * 6.0,
				"slow": 1.0,
			})
	# 塔攻击
	for cell in towers.keys():
		var tw: Dictionary = towers[cell]
		tw["t"] = float(tw["t"]) - dt
		if tw["t"] > 0.0:
			continue
		var origin := _cell_center(cell)
		var best_i := -1
		var best_d := 9999.0
		for i in enemies.size():
			var ep := _path_point(float(enemies[i]["pos"]))
			var d: float = origin.distance_to(ep)
			if d < float(tw["range"]) and d < best_d:
				best_d = d
				best_i = i
		if best_i >= 0:
			tw["t"] = float(tw["cd"])
			enemies[best_i]["hp"] = float(enemies[best_i]["hp"]) - float(tw["dmg"])
			if tw["type"] == &"ice":
				enemies[best_i]["slow"] = 0.55
			if float(enemies[best_i]["hp"]) <= 0.0:
				enemies.remove_at(best_i)
				gold += 6 + wave
	# 移动
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		var speed := 0.12 * float(e["slow"])
		e["pos"] = float(e["pos"]) + speed * dt
		e["slow"] = minf(1.0, float(e["slow"]) + dt * 0.35)
		if float(e["pos"]) >= 1.0:
			enemies.remove_at(i)
			core_hp -= 1
			msg = "漏怪! 晶核 -1"
			if core_hp <= 0:
				wave_active = false
			continue
		i += 1
	# 清波
	if spawn_left <= 0 and enemies.is_empty():
		wave_active = false
		clear_flash = 1.0
		gold += 15
		msg = "清波。"


func _on_board_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = ev.position
		var c := Vector2i(int(local.x / CELL), int(local.y / CELL))
		_try_place(c)
	if ev is InputEventScreenTouch and ev.pressed:
		var c2 := Vector2i(int(ev.position.x / CELL), int(ev.position.y / CELL))
		_try_place(c2)


func _try_place(c: Vector2i) -> void:
	if core_hp <= 0:
		return
	if c.x < 0 or c.y < 0 or c.x >= COLS or c.y >= ROWS:
		return
	if c.x == PATH_COL:
		msg = "路径上不能放——护住裂隙两侧。"
		return
	if towers.has(c):
		msg = "这里已有塔。"
		return
	var cost := _cost(selected)
	if gold < cost:
		msg = "金币不够。"
		return
	gold -= cost
	var dmg := 8.0 if selected == &"fire" else 4.0
	var rng := 130.0 if selected == &"fire" else 150.0
	var cd := 0.45 if selected == &"fire" else 0.55
	towers[c] = {"type": selected, "dmg": dmg, "range": rng, "cd": cd, "t": 0.0}
	juice = 1.0
	juice_cell = c
	msg = "召唤! 听这「笃定」——下一波就靠它。"


func _draw_board() -> void:
	var w := COLS * CELL
	var h := ROWS * CELL
	_board.custom_minimum_size = Vector2(w, h)
	_board.draw_rect(Rect2(0, 0, w, h), COL_BG, true)
	for y in ROWS:
		for x in COLS:
			var r := Rect2(x * CELL + 2, y * CELL + 2, CELL - 4, CELL - 4)
			if x == PATH_COL:
				_board.draw_rect(r, COL_PATH, true)
			else:
				_board.draw_rect(r, Color("243056"), true)
				_board.draw_rect(r, Color("2f3c66"), false, 2.0)
	# 晶核
	var core_r := Rect2(PATH_COL * CELL + 12, (ROWS - 1) * CELL + 12, CELL - 24, CELL - 24)
	_board.draw_rect(core_r, COL_CORE, true)
	# 塔
	for cell in towers.keys():
		var tw: Dictionary = towers[cell]
		var col := COL_FIRE if tw["type"] == &"fire" else COL_ICE
		var center := _cell_center(cell)
		if juice > 0.0 and cell == juice_cell:
			col = col.lerp(Color.WHITE, juice * 0.7)
		_board.draw_circle(center, CELL * 0.32, col)
		_board.draw_circle(center, CELL * 0.12, Color.WHITE)
	# 怪
	for e in enemies:
		var p := _path_point(float(e["pos"]))
		var t := clampf(float(e["hp"]) / float(e["max_hp"]), 0.0, 1.0)
		_board.draw_circle(p, 14.0, COL_ENEMY.lerp(Color("f5b7b1"), 1.0 - t))
	if clear_flash > 0.0:
		_board.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, clear_flash * 0.15), true)


func _cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)


func _path_point(t: float) -> Vector2:
	t = clampf(t, 0.0, 1.0)
	var y := t * (ROWS - 1) * CELL + CELL * 0.5
	return Vector2((PATH_COL + 0.5) * CELL, y)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_R:
		gold = 80
		core_hp = 10
		wave = 0
		towers.clear()
		enemies.clear()
		wave_active = false
		msg = "重置。再构筑一次。"
