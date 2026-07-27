extends Control
## 《晶核防线》生产场景 —— 阶段 2 productionize。
## 逻辑: CrystalLineSim; 图: CrystalArtBank; 音: CrystalSoundBank(+本地播放器)。
## 运行: godot --path . res://game/crystal_line/main.tscn

const CELL := 96.0
const SimScript := preload("res://game/crystal_line/sim/crystal_line_sim.gd")
const ArtScript := preload("res://game/crystal_line/gfx/art_bank.gd")
const SfxScript := preload("res://game/crystal_line/sfx/sound_bank.gd")

var sim
var art
var sfx
var selected: StringName = &"fire"
var juice: float = 0.0
var juice_cell: Vector2i = Vector2i(-1, -1)
var clear_flash: float = 0.0
var msg: String = "选塔 → 点路径旁格子。守住晶核。"
var _prev_event: String = ""

@onready var _info: Label = $VBox/Info
@onready var _board: Control = $VBox/Board
@onready var _hint: Label = $VBox/Hint
@onready var _player: AudioStreamPlayer = $SfxPlayer


func _ready() -> void:
	sim = SimScript.new()
	art = ArtScript.new()
	sfx = SfxScript.new()
	custom_minimum_size = Vector2(720, 1280)
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_board.draw.connect(_draw_board)
	_board.gui_input.connect(_on_board_input)
	$VBox/Bar/Fire.pressed.connect(func(): _select(&"fire"))
	$VBox/Bar/Ice.pressed.connect(func(): _select(&"ice"))
	$VBox/Bar/Wave.pressed.connect(_on_wave)
	$VBox/Bar/Reset.pressed.connect(_on_reset)
	_apply_button_icons()
	_refresh_ui()
	if Engine.has_singleton("CoreKit") or get_node_or_null("/root/CoreKit"):
		var kit = get_node_or_null("/root/CoreKit")
		if kit and kit.log:
			kit.log.info("CrystalLine ready — source tower_fire=%s place_sfx=%s" % [
				art.source_for(&"tower_fire"), sfx.source_for(&"place")])


func _select(t: StringName) -> void:
	selected = t
	_play(&"ui")
	_refresh_ui()


func _on_wave() -> void:
	if sim.start_wave():
		_play(&"ui")
		msg = "第 %d 波来了。" % sim.wave
	else:
		_play(&"deny")
		msg = "现在不能开波。"
	_refresh_ui()


func _on_reset() -> void:
	sim.reset()
	juice = 0.0
	clear_flash = 0.0
	msg = "重置。再构筑一次。"
	_play(&"ui")
	_refresh_ui()


func _process(dt: float) -> void:
	juice = maxf(0.0, juice - dt * 3.0)
	clear_flash = maxf(0.0, clear_flash - dt * 2.0)
	sim.tick(dt)
	_react_events()
	_board.queue_redraw()
	_refresh_ui()


func _react_events() -> void:
	var e: String = sim.last_event
	if e == _prev_event:
		return
	_prev_event = e
	match e:
		"wave_clear":
			clear_flash = 1.0
			msg = "清波! 松一口气。再构筑。"
			_play(&"clear")
		"leak":
			msg = "漏怪! 晶核 -1"
			_play(&"leak")
		"defeat":
			msg = "破核了——换站位再来。(重置)"
			_play(&"leak")
		"placed":
			pass  # 已在 place 时播


func _refresh_ui() -> void:
	var cost := 40 if selected == &"fire" else 45
	_info.text = "晶核 %d  |  金 %d  |  波 %d  |  选中 %s(%d)  |  塔 %d" % [
		sim.core_hp, sim.gold, sim.wave, selected, cost, sim.tower_count()]
	_hint.text = msg
	if clear_flash > 0.0 and sim.core_hp > 0:
		_hint.text = "清波! 松一口气。再构筑,再开一波。"


func _apply_button_icons() -> void:
	$VBox/Bar/Fire.icon = art.texture_for(&"tower_fire", 32)
	$VBox/Bar/Ice.icon = art.texture_for(&"tower_ice", 32)


func _on_board_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_try_place(Vector2i(int(ev.position.x / CELL), int(ev.position.y / CELL)))
	elif ev is InputEventScreenTouch and ev.pressed:
		_try_place(Vector2i(int(ev.position.x / CELL), int(ev.position.y / CELL)))


func _try_place(c: Vector2i) -> void:
	if sim.place_tower(c.x, c.y, selected):
		juice = 1.0
		juice_cell = c
		msg = "召唤! 笃定落下。"
		_play(&"place")
		_prev_event = "placed"
	else:
		match sim.last_event:
			"no_gold":
				msg = "金币不够。"
			"place_denied":
				msg = "不能放这里(路径/已有塔/越界)。"
			_:
				msg = "无法放置。"
		_play(&"deny")


func _play(key: StringName) -> void:
	_player.stream = sfx.stream_for(key)
	_player.play()


func _draw_board() -> void:
	var cols: int = sim.COLS
	var rows: int = sim.ROWS
	var path_col: int = sim.PATH_COL
	var w := cols * CELL
	var h := rows * CELL
	_board.custom_minimum_size = Vector2(w, h)
	var col_bg := Color("1a1f3a")
	var col_path: Color = art.color_for(&"path")
	var col_cell: Color = art.color_for(&"cell")
	_board.draw_rect(Rect2(0, 0, w, h), col_bg, true)
	for y in rows:
		for x in cols:
			var r := Rect2(x * CELL + 2, y * CELL + 2, CELL - 4, CELL - 4)
			if x == path_col:
				_board.draw_rect(r, col_path, true)
			else:
				_board.draw_rect(r, col_cell, true)
				_board.draw_rect(r, Color("2f3c66"), false, 2.0)
	# 晶核
	var core_tex: Texture2D = art.texture_for(&"core", 64)
	var core_pos := Vector2(path_col * CELL + (CELL - 64) * 0.5, (rows - 1) * CELL + (CELL - 64) * 0.5)
	_board.draw_texture(core_tex, core_pos)
	# 塔
	for k in sim.towers.keys():
		var tw: Dictionary = sim.towers[k]
		var cell := Vector2i(int(tw["col"]), int(tw["row"]))
		var key: StringName = &"tower_fire" if tw["type"] == &"fire" else &"tower_ice"
		var tex: Texture2D = art.texture_for(key, 48)
		var pos := Vector2(cell.x * CELL + (CELL - 48) * 0.5, cell.y * CELL + (CELL - 48) * 0.5)
		if juice > 0.0 and cell == juice_cell:
			_board.draw_circle(Vector2(cell.x + 0.5, cell.y + 0.5) * CELL, CELL * 0.4,
				Color(1, 1, 1, juice * 0.45))
		_board.draw_texture(tex, pos)
	# 怪
	var enemy_tex: Texture2D = art.texture_for(&"enemy", 32)
	for e in sim.enemies:
		var y := float(e["row_pos"]) * CELL + CELL * 0.5 - 16.0
		var x := path_col * CELL + (CELL - 32) * 0.5
		_board.draw_texture(enemy_tex, Vector2(x, y))
	if clear_flash > 0.0:
		_board.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, clear_flash * 0.15), true)
