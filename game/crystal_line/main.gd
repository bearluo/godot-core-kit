extends Control
## 《晶核防线》生产场景 —— 阶段 2 productionize + R1 体验修复。
## 逻辑: CrystalLineSim; 图: CrystalArtBank; 音: CrystalSoundBank(+CoreKit.audio 优先)。
## 运行: godot --path . res://game/crystal_line/main.tscn

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
var msg: String = "选塔 → 点路径旁格子。守住顶部晶核。"
var _prev_event: String = ""
var _cell: float = 64.0
var _grid_origin: Vector2 = Vector2.ZERO

@onready var _info: Label = $Margin/VBox/Info
@onready var _board: Control = $Margin/VBox/Board
@onready var _hint: Label = $Margin/VBox/Hint
@onready var _player: AudioStreamPlayer = $SfxPlayer
@onready var _result: Control = $ResultOverlay
@onready var _result_title: Label = $ResultOverlay/Panel/VBox/Title
@onready var _result_body: Label = $ResultOverlay/Panel/VBox/Body


func _ready() -> void:
	sim = SimScript.new()
	art = ArtScript.new()
	sfx = SfxScript.new()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_board.draw.connect(_draw_board)
	_board.gui_input.connect(_on_board_input)
	_board.resized.connect(func(): _board.queue_redraw())
	$Margin/VBox/Bar/Fire.pressed.connect(func(): _select(&"fire"))
	$Margin/VBox/Bar/Ice.pressed.connect(func(): _select(&"ice"))
	$Margin/VBox/Bar/Wave.pressed.connect(_on_wave)
	$Margin/VBox/Bar/Reset.pressed.connect(_on_reset)
	$ResultOverlay/Panel/VBox/Again.pressed.connect(_on_again)
	_result.visible = false
	_apply_button_icons()
	_refresh_ui()
	var kit = get_node_or_null("/root/CoreKit")
	if kit and kit.log:
		kit.log.info("CrystalLine ready — source tower_fire=%s place_sfx=%s" % [
			art.source_for(&"tower_fire"), sfx.source_for(&"place")])


func _select(t: StringName) -> void:
	if sim.is_game_over():
		return
	selected = t
	_play(&"ui")
	_refresh_ui()


func _on_wave() -> void:
	if sim.is_game_over():
		return
	if sim.start_wave():
		_play(&"ui")
		msg = "第 %d 波来了。" % sim.wave
	else:
		_play(&"deny")
		msg = "现在不能开波。"
	_refresh_ui()


func _on_reset() -> void:
	_do_reset("重置。再构筑一次。")


func _on_again() -> void:
	_result.visible = false
	_do_reset("再来一局。换站位验证假设。")


func _do_reset(hint: String) -> void:
	sim.reset()
	juice = 0.0
	clear_flash = 0.0
	_prev_event = ""
	msg = hint
	_play(&"ui")
	_refresh_ui()


func _process(dt: float) -> void:
	juice = maxf(0.0, juice - dt * 3.0)
	clear_flash = maxf(0.0, clear_flash - dt * 2.0)
	sim.tick(dt)
	if int(sim.hits_this_tick) > 0:
		_play(&"hit")
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
			msg = "破核了——复盘站位再来。"
			_play(&"leak")
			_show_result(false)
		"victory":
			msg = "防线守住! 构筑成立。"
			_play(&"clear")
			clear_flash = 1.0
			_show_result(true)
		"placed":
			pass


func _show_result(won: bool) -> void:
	_result.visible = true
	if won:
		_result_title.text = "胜利 · 晶核安然"
		_result_body.text = "清完 %d 波\n击杀 %d · 漏怪 %d\n本局赚金 %d · 剩余核血 %d\n\n短失败成本 + 换站位再验证。" % [
			sim.waves_cleared, sim.kills, sim.leaks, sim.gold_earned, sim.core_hp]
	else:
		_result_title.text = "失败 · 破核"
		_result_body.text = "撑到第 %d 波(清 %d)\n击杀 %d · 漏怪 %d\n本局赚金 %d\n\n差一格/一种塔——再来一局。" % [
			sim.wave, sim.waves_cleared, sim.kills, sim.leaks, sim.gold_earned]


func _refresh_ui() -> void:
	var cost := 40 if selected == &"fire" else 45
	var sel_name := "火" if selected == &"fire" else "冰"
	var phase := "战斗中" if sim.wave_active else ("已结束" if sim.is_game_over() else "构筑中")
	_info.text = "晶核 %d  |  金 %d  |  波 %d/%d  |  %s  |  选中 %s(%d)  |  塔 %d" % [
		sim.core_hp, sim.gold, sim.wave, sim.WIN_WAVES, phase, sel_name, cost, sim.tower_count()]
	_hint.text = msg
	if clear_flash > 0.0 and sim.core_hp > 0 and not sim.is_game_over():
		_hint.text = "清波! 松一口气。再构筑,再开一波。"
	var can_act: bool = not sim.is_game_over()
	$Margin/VBox/Bar/Fire.disabled = not can_act
	$Margin/VBox/Bar/Ice.disabled = not can_act
	$Margin/VBox/Bar/Wave.disabled = not can_act


func _apply_button_icons() -> void:
	$Margin/VBox/Bar/Fire.icon = art.texture_for(&"tower_fire", 32)
	$Margin/VBox/Bar/Ice.icon = art.texture_for(&"tower_ice", 32)


func _on_board_input(ev: InputEvent) -> void:
	if sim.is_game_over():
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_try_place(_screen_to_cell(ev.position))
	elif ev is InputEventScreenTouch and ev.pressed:
		_try_place(_screen_to_cell(ev.position))


func _screen_to_cell(local: Vector2) -> Vector2i:
	var p := local - _grid_origin
	if _cell <= 0.0:
		return Vector2i(-1, -1)
	return Vector2i(int(floor(p.x / _cell)), int(floor(p.y / _cell)))


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
	var stream: AudioStream = sfx.stream_for(key)
	var kit = get_node_or_null("/root/CoreKit")
	if kit and kit.audio and kit.audio.has_method("play_sfx"):
		kit.audio.play_sfx(stream)
		return
	_player.stream = stream
	_player.play()


func _layout_grid() -> void:
	var cols: int = sim.COLS
	var rows: int = sim.ROWS
	var sz: Vector2 = _board.size
	if sz.x < 1.0 or sz.y < 1.0:
		sz = Vector2(cols * 64.0, rows * 64.0)
	_cell = minf(sz.x / float(cols), sz.y / float(rows))
	var gw := _cell * float(cols)
	var gh := _cell * float(rows)
	_grid_origin = Vector2((sz.x - gw) * 0.5, (sz.y - gh) * 0.5)


func _draw_board() -> void:
	_layout_grid()
	var cols: int = sim.COLS
	var rows: int = sim.ROWS
	var w := cols * _cell
	var h := rows * _cell
	var o := _grid_origin
	var col_bg := Color("1a1f3a")
	var col_path: Color = art.color_for(&"path")
	var col_cell: Color = art.color_for(&"cell")
	_board.draw_rect(Rect2(0, 0, _board.size.x, _board.size.y), col_bg, true)
	for y in rows:
		for x in cols:
			var r := Rect2(o.x + x * _cell + 2, o.y + y * _cell + 2, _cell - 4, _cell - 4)
			if sim.is_path_cell(x, y):
				_board.draw_rect(r, col_path, true)
			else:
				_board.draw_rect(r, col_cell, true)
				_board.draw_rect(r, Color("2f3c66"), false, 2.0)
	# 路径方向小箭头(朝晶核)
	for i in range(sim.PATH_LEN - 1):
		var a: Vector2i = sim.PATH[i]
		var b: Vector2i = sim.PATH[i + 1]
		var pa := o + (Vector2(a) + Vector2(0.5, 0.5)) * _cell
		var pb := o + (Vector2(b) + Vector2(0.5, 0.5)) * _cell
		_board.draw_line(pa, pb, Color(0.55, 0.65, 0.85, 0.35), 2.0)
	# 晶核(路径终点 · 顶部)
	var core_tex: Texture2D = art.texture_for(&"core", int(_cell * 0.7))
	var cs := float(core_tex.get_width())
	var core_cell: Vector2i = sim.CORE_CELL
	var core_pos := o + Vector2(core_cell) * _cell + Vector2((_cell - cs) * 0.5, (_cell - cs) * 0.5)
	_board.draw_texture(core_tex, core_pos)
	# 塔
	for k in sim.towers.keys():
		var tw: Dictionary = sim.towers[k]
		var cell := Vector2i(int(tw["col"]), int(tw["row"]))
		var key: StringName = &"tower_fire" if tw["type"] == &"fire" else &"tower_ice"
		var ts := int(_cell * 0.55)
		var tex: Texture2D = art.texture_for(key, ts)
		var tws := float(tex.get_width())
		var pos := o + Vector2(cell) * _cell + Vector2((_cell - tws) * 0.5, (_cell - tws) * 0.5)
		if juice > 0.0 and cell == juice_cell:
			_board.draw_circle(o + (Vector2(cell) + Vector2(0.5, 0.5)) * _cell, _cell * 0.4,
				Color(1, 1, 1, juice * 0.45))
		_board.draw_texture(tex, pos)
	# 交火射线
	for sh in sim.shots:
		var from_p := o + Vector2(float(sh["from_col"]), float(sh["from_row"])) * _cell
		var to_p := o + Vector2(float(sh["to_col"]), float(sh["to_row"])) * _cell
		var col := Color("e67e22") if sh.get("type", &"fire") == &"fire" else Color("4fc3f7")
		col.a = clampf(float(sh["life"]) / 0.18, 0.0, 1.0)
		_board.draw_line(from_p, to_p, col, 3.0)
		_board.draw_circle(to_p, 4.0, col)
	# 怪 + 血条
	var es := int(_cell * 0.38)
	var enemy_tex: Texture2D = art.texture_for(&"enemy", es)
	var ews := float(enemy_tex.get_width())
	for e in sim.enemies:
		var wp: Vector2 = sim.enemy_world_pos(e)
		var center := o + wp * _cell
		var pos := center - Vector2(ews, ews) * 0.5
		_board.draw_texture(enemy_tex, pos)
		var ratio := clampf(float(e["hp"]) / maxf(float(e["max_hp"]), 1.0), 0.0, 1.0)
		var bar_w := _cell * 0.55
		var bar_h := 5.0
		var bar_pos := center + Vector2(-bar_w * 0.5, -ews * 0.55)
		_board.draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.15, 0.15, 0.2, 0.85), true)
		_board.draw_rect(Rect2(bar_pos, Vector2(bar_w * ratio, bar_h)), Color("e74c5e"), true)
	if clear_flash > 0.0:
		_board.draw_rect(Rect2(o.x, o.y, w, h), Color(1, 1, 1, clear_flash * 0.15), true)
