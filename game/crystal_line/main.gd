extends Control
## 《晶核防线》生产场景 —— 阶段 2 productionize + R1 修复。
## 逻辑: CrystalLineSim; 图: CrystalArtBank; 音: CrystalSoundBank(经 CoreKit.audio)。
## 运行: godot --path . res://game/crystal_line/main.tscn
##
## 布局约定(CL-001): 棋盘不再硬撑固定像素,而是按 Board 控件的实际尺寸算格边长,
## 于是 540x960 / 720x1280 / 1152x648 三种分辨率下 HUD + 棋盘 + 底栏同时完整可见。

const SimScript := preload("res://game/crystal_line/sim/crystal_line_sim.gd")
const ArtScript := preload("res://game/crystal_line/gfx/art_bank.gd")
const SfxScript := preload("res://game/crystal_line/sfx/sound_bank.gd")

const SAVE_SLOT := "crystal_line"
const BEAM_LIFE := 0.16
const HIT_SFX_COOLDOWN := 0.09

var sim
var art
var sfx
var selected: StringName = &"fire"
var juice: float = 0.0
var juice_cell: Vector2i = Vector2i(-1, -1)
var clear_flash: float = 0.0
var msg: String = "选塔 → 点路径旁格子。守住晶核。"
## 跨局进度(经 CoreKit.saves 持久化)
var record: Dictionary = {"best_wave": 0, "wins": 0, "plays": 0}
## "corekit" = 音效走 CoreKit.audio.play_sfx;"local" = 回退到场景内播放器
var sfx_route: String = "local"
## key -> 播放次数。给 headless 断言用(证明 hit 等音效真的在流程中被播放,不是死资源)
var sfx_plays: Dictionary = {}

var _prev_event: String = ""
var _prev_phase: StringName = &""
var _prev_hits: int = 0
var _hit_sfx_cd: float = 0.0
var _beams: Array = []
var _cov_cache: Dictionary = {}
var _kit: Node = null

@onready var _hp: Label = $Root/Hud/Hp
@onready var _gold: Label = $Root/Hud/Gold
@onready var _wave: Label = $Root/Hud/Wave
@onready var _towers: Label = $Root/Hud/Towers
@onready var _board: Control = $Root/Board
@onready var _hint: Label = $Root/Hint
@onready var _btn_fire: Button = $Root/Bar/Fire
@onready var _btn_ice: Button = $Root/Bar/Ice
@onready var _btn_wave: Button = $Root/Bar/Wave
@onready var _result: Control = $Result
@onready var _r_title: Label = $Result/Center/Panel/Box/RTitle
@onready var _r_body: Label = $Result/Center/Panel/Box/RBody
@onready var _r_record: Label = $Result/Center/Panel/Box/RRecord
@onready var _player: AudioStreamPlayer = $SfxPlayer


func _ready() -> void:
	sim = SimScript.new()
	art = ArtScript.new()
	sfx = SfxScript.new()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_kit = get_node_or_null("/root/CoreKit")
	if _kit != null and _kit.audio != null:
		sfx_route = "corekit"
	_board.draw.connect(_draw_board)
	_board.gui_input.connect(_on_board_input)
	_btn_fire.pressed.connect(func(): _select(&"fire"))
	_btn_ice.pressed.connect(func(): _select(&"ice"))
	_btn_wave.pressed.connect(_on_wave)
	$Root/Bar/Reset.pressed.connect(_on_reset)
	$Result/Center/Panel/Box/Again.pressed.connect(_on_reset)
	_apply_button_icons()
	_load_record()
	_prev_phase = sim.phase
	_refresh_ui()
	if _kit != null and _kit.log != null:
		_kit.log.info("CrystalLine ready — art=%s sfx=%s route=%s" % [
			art.source_for(&"tower_fire"), sfx.source_for(&"place"), sfx_route])


# ---------------------------------------------------------------- 输入 / 命令

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
	_beams.clear()
	_prev_hits = sim.hits
	_prev_event = "reset"
	_prev_phase = sim.phase
	msg = "新的一局。换一套站位试试。"
	_result.visible = false
	_play(&"ui")
	_refresh_ui()


func _on_board_input(ev: InputEvent) -> void:
	var pos := Vector2.ZERO
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		pos = ev.position
	elif ev is InputEventScreenTouch and ev.pressed:
		pos = ev.position
	else:
		return
	var m := board_metrics()
	var cell: float = m["cell"]
	if cell <= 0.0:
		return
	var local: Vector2 = (pos - Vector2(m["origin"])) / cell
	if local.x < 0.0 or local.y < 0.0:
		return
	_try_place(Vector2i(int(local.x), int(local.y)))


func _try_place(c: Vector2i) -> void:
	if sim.place_tower(c.x, c.y, selected):
		juice = 1.0
		juice_cell = c
		var cov: float = sim.coverage_at(c.x, c.y, sim.range_of(selected))
		msg = "召唤! 笃定落下。这一格覆盖 %.1f 格路径。" % cov
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
	_refresh_ui()


# ---------------------------------------------------------------- 主循环

func _process(dt: float) -> void:
	juice = maxf(0.0, juice - dt * 3.0)
	clear_flash = maxf(0.0, clear_flash - dt * 2.0)
	_hit_sfx_cd = maxf(0.0, _hit_sfx_cd - dt)
	sim.tick(dt)
	_collect_shots()
	_decay_beams(dt)
	_react_events()
	_board.queue_redraw()
	_refresh_ui()


func _collect_shots() -> void:
	for s in sim.shots:
		_beams.append({
			"from": Vector2(s["from"]),
			"to": Vector2(s["to"]),
			"life": BEAM_LIFE,
			"kill": bool(s["kill"]),
			"type": s["type"],
		})
	if sim.hits > _prev_hits:
		_prev_hits = sim.hits
		if _hit_sfx_cd <= 0.0:
			_hit_sfx_cd = HIT_SFX_COOLDOWN
			_play(&"hit")


func _decay_beams(dt: float) -> void:
	var i := 0
	while i < _beams.size():
		_beams[i]["life"] = float(_beams[i]["life"]) - dt
		if float(_beams[i]["life"]) <= 0.0:
			_beams.remove_at(i)
		else:
			i += 1


func _react_events() -> void:
	if sim.phase != _prev_phase:
		_prev_phase = sim.phase
		if sim.is_round_over():
			_finish_round()
	var e: String = sim.last_event
	if e == _prev_event:
		return
	_prev_event = e
	match e:
		"wave_start":
			msg = "第 %d 波来了。" % sim.wave
			_play(&"ui")
		"wave_clear":
			clear_flash = 1.0
			msg = "清波! 松一口气。再构筑。"
			_play(&"clear")
		"leak":
			msg = "漏怪! 晶核 -1"
			_play(&"leak")
		"defeat":
			msg = "破核了——换站位再来。"
			_play(&"leak")
		"victory":
			clear_flash = 1.0
			msg = "全部 %d 波清空,晶核安然。" % sim.waves_total()
			_play(&"clear")


# ---------------------------------------------------------------- 结算 / 存档

func _finish_round() -> void:
	var s: Dictionary = sim.summary()
	record["plays"] = int(record.get("plays", 0)) + 1
	record["best_wave"] = maxi(int(record.get("best_wave", 0)), int(s["waves_cleared"]))
	if bool(s["victory"]):
		record["wins"] = int(record.get("wins", 0)) + 1
	_save_record()
	_r_title.text = "守住了!" if bool(s["victory"]) else "晶核破碎"
	_r_body.text = "波次 %d/%d   晶核 %d   击杀 %d   漏怪 %d\n塔 %d 座   赚取 %d 金   用时 %s" % [
		s["waves_cleared"], s["waves_total"], s["core_hp"], s["kills"], s["leaks"],
		s["towers"], s["gold_earned"], _fmt_time(float(s["seconds"]))]
	_r_record.text = "历史最好 第 %d 波   通关 %d 次   第 %d 局" % [
		int(record.get("best_wave", 0)), int(record.get("wins", 0)), int(record.get("plays", 0))]
	_result.visible = true


func _load_record() -> void:
	if _kit == null or _kit.saves == null:
		return
	if not _kit.saves.has_slot(SAVE_SLOT):
		return
	var d: Dictionary = _kit.saves.load(SAVE_SLOT)
	for k in ["best_wave", "wins", "plays"]:
		if d.has(k):
			record[k] = int(d[k])


func _save_record() -> void:
	if _kit == null or _kit.saves == null:
		return
	_kit.saves.save(SAVE_SLOT, record.duplicate())


func _fmt_time(sec: float) -> String:
	var t := int(sec)
	return "%d:%02d" % [t / 60, t % 60]


# ---------------------------------------------------------------- UI 刷新

func _refresh_ui() -> void:
	_hp.text = "晶核 %d" % sim.core_hp
	_gold.text = "金币 %d" % sim.gold
	_wave.text = "波次 %d/%d" % [sim.wave, sim.waves_total()]
	_towers.text = "塔 %d" % sim.tower_count()
	_btn_fire.text = ("▶ " if selected == &"fire" else "") + "火塔 %d" % sim.cost_of(&"fire")
	_btn_ice.text = ("▶ " if selected == &"ice" else "") + "冰塔 %d" % sim.cost_of(&"ice")
	if sim.is_round_over():
		_btn_wave.text = "本局结束"
		_btn_wave.disabled = true
	elif sim.phase == sim.PHASE_PREP:
		_btn_wave.text = "立即开波 %d" % int(ceil(sim.prep_left))
		_btn_wave.disabled = false
	else:
		_btn_wave.text = "作战中 %d" % sim.enemy_count()
		_btn_wave.disabled = true
	_hint.text = "%s\n%s" % [msg, _status_line()]


func _status_line() -> String:
	if sim.is_victory():
		return "本局胜利 —— 点「再来一局」换一套站位。"
	if sim.is_game_over():
		return "本局失败 —— 点「再来一局」换一套站位。"
	if sim.phase == sim.PHASE_PREP:
		return "备战 %.1fs → 第 %d 波(%d 只)。亮点越大的格子覆盖路径越长。" % [
			maxf(sim.prep_left, 0.0), sim.wave + 1, sim.wave_size(sim.wave + 1)]
	return "第 %d 波作战中 — 场上 %d 只,还剩 %d 只未出。" % [sim.wave, sim.enemy_count(), sim.spawn_left]


func _apply_button_icons() -> void:
	_btn_fire.icon = art.texture_for(&"tower_fire", 32)
	_btn_ice.icon = art.texture_for(&"tower_ice", 32)


# ---------------------------------------------------------------- 棋盘绘制

## 棋盘度量:格边长 + 左上原点。绘制与点击共用同一份,分辨率变化自动跟随。
func board_metrics() -> Dictionary:
	var s := _board.size
	var cell := minf(s.x / float(sim.COLS), s.y / float(sim.ROWS))
	cell = maxf(cell, 0.0)
	var origin := Vector2(
		(s.x - cell * float(sim.COLS)) * 0.5,
		(s.y - cell * float(sim.ROWS)) * 0.5)
	return {"cell": cell, "origin": origin, "size": Vector2(cell * sim.COLS, cell * sim.ROWS)}


func _px(m: Dictionary, grid: Vector2) -> Vector2:
	return Vector2(m["origin"]) + (grid + Vector2(0.5, 0.5)) * float(m["cell"])


func _coverage_map(type: StringName) -> Dictionary:
	if _cov_cache.has(type):
		return _cov_cache[type]
	var out := {}
	var rng: float = sim.range_of(type)
	for row in sim.ROWS:
		for col in sim.COLS:
			if sim.is_path_cell(col, row):
				continue
			out[Vector2i(col, row)] = sim.coverage_at(col, row, rng)
	_cov_cache[type] = out
	return out


func _draw_board() -> void:
	var m := board_metrics()
	var cell: float = m["cell"]
	if cell <= 1.0:
		return
	var origin := Vector2(m["origin"])
	var grid_size := Vector2(m["size"])
	var col_path: Color = art.color_for(&"path")
	var col_cell: Color = art.color_for(&"cell")
	_board.draw_rect(Rect2(origin, grid_size), Color("141834"), true)

	# 格子:路径 vs 可建造
	for y in sim.ROWS:
		for x in sim.COLS:
			var r := Rect2(origin + Vector2(x, y) * cell + Vector2(2, 2),
				Vector2(cell - 4, cell - 4))
			if sim.is_path_cell(x, y):
				_board.draw_rect(r, col_path, true)
			else:
				_board.draw_rect(r, col_cell, true)
				_board.draw_rect(r, Color("2f3c66"), false, 2.0)

	# 裂隙主干:沿路径中心连一条亮线,让「蜿蜒」一眼可读
	var pts := PackedVector2Array()
	for p in sim.PATH:
		pts.append(_px(m, Vector2(p)))
	_board.draw_polyline(pts, Color(0.42, 0.51, 0.72, 0.85), maxf(2.0, cell * 0.12))
	# 入口标记
	_board.draw_circle(_px(m, Vector2(sim.PATH[0])), cell * 0.18, Color(0.55, 0.65, 0.9, 0.8))

	# 站位提示(仅备战阶段,免得盖住交火画面):亮点越大 = 选中塔在该格覆盖的路径越长
	if sim.phase == sim.PHASE_PREP:
		var cov_map := _coverage_map(selected)
		var max_cov := 0.001
		for v in cov_map.values():
			max_cov = maxf(max_cov, float(v))
		for c in cov_map.keys():
			if sim.towers.has("%d,%d" % [c.x, c.y]):
				continue
			var ratio: float = clampf(float(cov_map[c]) / max_cov, 0.0, 1.0)
			if ratio <= 0.02:
				continue
			_board.draw_circle(_px(m, Vector2(c)), cell * (0.05 + 0.10 * ratio),
				Color(0.55, 0.85, 1.0, 0.10 + 0.22 * ratio))

	# 晶核
	var core: Vector2i = sim.core_cell()
	var core_size := int(cell * 0.7)
	var core_tex: Texture2D = art.texture_for(&"core", core_size)
	_board.draw_texture(core_tex, _px(m, Vector2(core)) - Vector2(core_size, core_size) * 0.5)
	var core_ratio: float = clampf(float(sim.core_hp) / float(sim.START_HP), 0.0, 1.0)
	_board.draw_arc(_px(m, Vector2(core)), cell * 0.44, -PI * 0.5,
		-PI * 0.5 + TAU * core_ratio, 32, Color(0.906, 0.298, 0.369, 0.9), maxf(2.0, cell * 0.05))

	# 塔 + 射程 + 瞄准线
	var tower_size := int(cell * 0.55)
	for k in sim.towers.keys():
		var tw: Dictionary = sim.towers[k]
		var gpos := Vector2(float(tw["col"]), float(tw["row"]))
		var center := _px(m, gpos)
		var tcol: Color = art.color_for(&"tower_fire" if tw["type"] == &"fire" else &"tower_ice")
		_board.draw_arc(center, float(tw["range"]) * cell, 0.0, TAU, 48,
			Color(tcol.r, tcol.g, tcol.b, 0.18), maxf(1.0, cell * 0.02))
		if bool(tw["has_aim"]):
			var target := _px(m, Vector2(tw["aim"]))
			_board.draw_line(center, target, Color(tcol.r, tcol.g, tcol.b, 0.55),
				maxf(1.5, cell * 0.045))
			_board.draw_arc(target, cell * 0.24, 0.0, TAU, 20,
				Color(tcol.r, tcol.g, tcol.b, 0.75), maxf(1.5, cell * 0.03))
		if juice > 0.0 and Vector2i(int(gpos.x), int(gpos.y)) == juice_cell:
			_board.draw_circle(center, cell * 0.42, Color(1, 1, 1, juice * 0.45))
		var key: StringName = &"tower_fire" if tw["type"] == &"fire" else &"tower_ice"
		var tex: Texture2D = art.texture_for(key, tower_size)
		_board.draw_texture(tex, center - Vector2(tower_size, tower_size) * 0.5)

	# 弹道闪光 + 枪口闪
	for b in _beams:
		var a: float = clampf(float(b["life"]) / BEAM_LIFE, 0.0, 1.0)
		var bcol: Color = art.color_for(&"tower_fire" if b["type"] == &"fire" else &"tower_ice")
		var from := _px(m, Vector2(b["from"]))
		var to := _px(m, Vector2(b["to"]))
		_board.draw_line(from, to, Color(bcol.r, bcol.g, bcol.b, a), maxf(2.0, cell * 0.09))
		_board.draw_circle(from, cell * 0.16 * a, Color(1, 1, 1, a * 0.8))
		if bool(b["kill"]):
			_board.draw_circle(to, cell * 0.3 * a, Color(1, 0.95, 0.8, a * 0.7))

	# 怪 + 血条
	var enemy_size := int(cell * 0.4)
	var enemy_tex: Texture2D = art.texture_for(&"enemy", enemy_size)
	var bar_w := cell * 0.62
	var bar_h := maxf(3.0, cell * 0.06)
	for e in sim.enemies:
		var center2 := _px(m, sim.enemy_point(e))
		_board.draw_texture(enemy_tex, center2 - Vector2(enemy_size, enemy_size) * 0.5)
		var ratio: float = clampf(float(e["hp"]) / maxf(float(e["max_hp"]), 0.001), 0.0, 1.0)
		var bar_pos := center2 - Vector2(bar_w * 0.5, cell * 0.34 + bar_h)
		_board.draw_rect(Rect2(bar_pos - Vector2(1, 1), Vector2(bar_w + 2, bar_h + 2)),
			Color(0, 0, 0, 0.65), true)
		_board.draw_rect(Rect2(bar_pos, Vector2(bar_w * ratio, bar_h)),
			Color(0.85, 0.25, 0.25).lerp(Color(0.35, 0.85, 0.4), ratio), true)

	if clear_flash > 0.0:
		_board.draw_rect(Rect2(origin, grid_size), Color(1, 1, 1, clear_flash * 0.15), true)


# ---------------------------------------------------------------- 音效

## CL-006: 优先经 CoreKit.audio.play_sfx(dogfood kit),无 autoload 时回退本地播放器。
func _play(key: StringName) -> void:
	var stream: AudioStream = sfx.stream_for(key)
	if stream == null:
		return
	sfx_plays[key] = int(sfx_plays.get(key, 0)) + 1
	if sfx_route == "corekit" and _kit != null and _kit.audio != null:
		_kit.audio.play_sfx(stream)
	else:
		_player.stream = stream
		_player.play()
