extends Control
## 飞镖墙房(全屏进入式)。读 FortuneMill 命令层:玩家控发射角(aim)+蓄力(power) →
## do_throw → 飞镖走「解算发射速度命中 model 判定档」的真重力抛物线(落点确定)→ 命中爆金币,
## 金币落地堆积、每隔 COLLECT_INTERVAL 成批扫进右上计数器(空中的不收)→ 右=看守 Verminous(攒够门槛贿赂放行)。
## 换皮不换核:结算/经济全在 FortuneMill/DartsRoom;本类只做输入 + 表现。8 档奖墙读 FortuneWheelLayout.SEGMENTS。

const WORLD_SCENE := "res://examples/fortune-mill/scenes/world.tscn"

# 8 档配色(seg -> Color,与 world._wheel_palette 一致)
const PALETTE := {
	&"jackpot": Color("f4d35e"),
	&"x2a": Color("4a7c59"), &"x2b": Color("3f6b4e"),
	&"x20a": Color("6a9fb5"), &"x20b": Color("5a8fa5"),
	&"x5": Color("8a7fb5"),
	&"x100": Color("e08a3c"),
	&"vermin": Color("7a3b3b"),
}
# 档内显示标签
const MULT_LABEL := {
	&"jackpot": "★500", &"x2a": "×2", &"x2b": "×2",
	&"x20a": "×20", &"x20b": "×20", &"x5": "×5", &"x100": "×100", &"vermin": "劫",
}

const CYAN := Color("46e0ff")
const CYAN_GLOW := Color(0.28, 0.88, 1.0, 0.22)
const GOLD := Color("f4c542")
const GOLD_HI := Color("ffdf6e")
const RAT := Color("8a8f96")
const RAT_BELLY := Color("b9bec4")
const RAT_DARK := Color("3a3d42")
const PINK := Color("d98a9a")
const GRAY := Color("9aa0a6")
const RED_SOFT := Color("e0857f")

const GRAV := 1000.0
const FLIGHT_T := 0.5           ## 飞镖飞行时长(s);解算发射速度使其在 T 时刻恰落在目标档
const FLOOR_Y := 588.0
const COLLECT_INTERVAL := 3.0

var _font: Font
var _t: float = 0.0
var _bob: float = 0.0
var _power: float = 0.0
var _wind: float = 0.0
var _shake: float = 0.0
var _freeze: float = 0.0
var _counter_pulse: float = 0.0
var _collect_t: float = COLLECT_INTERVAL
var _flash: Dictionary = {}     # seg(StringName) -> flash 0..1
var _darts: Array = []
var _stuck: Array = []
var _coins: Array = []
var _pops: Array = []

# 输入 / 态机
var _darts_input                 # FortuneDartsInput
var _throw_fsm                   # KitStateMachine
var _cur_aim: float = 0.5        # 跟踪当前发射角(经 aim_changed),供瞄准预览

# HUD
var _gold_label: Label
var _rate_label: Label
var _bribe_button: Button
var _throw_button: Button
var _upgrade_buttons: Dictionary = {}   # id -> Button


func _ready() -> void:
	_font = load("res://examples/fortune-mill/scenes/proto_font.tres")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_hud()
	_build_throw_fsm()
	_darts_input = FortuneDartsInput.new()
	add_child(_darts_input)
	_apply_input_mode()
	_darts_input.thrown.connect(_on_dart_thrown)
	_darts_input.power_changed.connect(_on_power_changed)
	_darts_input.aim_changed.connect(func(a: float) -> void: _cur_aim = a)
	CoreKit.bus.subscribe("fortune:currency_changed", _on_dirty)
	CoreKit.bus.subscribe("fortune:upgrade_purchased", _on_dirty)
	CoreKit.bus.subscribe("fortune:room_cleared", _on_dirty)
	_refresh()


func _exit_tree() -> void:
	CoreKit.bus.unsubscribe("fortune:currency_changed", _on_dirty)
	CoreKit.bus.unsubscribe("fortune:upgrade_purchased", _on_dirty)
	CoreKit.bus.unsubscribe("fortune:room_cleared", _on_dirty)


func _on_dirty(_p = null) -> void:
	_refresh()


func _font_or_fallback() -> Font:
	return _font if _font != null else ThemeDB.fallback_font


# --- 几何 ---

func _board() -> Rect2:
	return Rect2(size.x * 0.375, 168.0, 292.0, 348.0)


func _thrower() -> Vector2:
	return Vector2(size.x * 0.12, 504.0)


func _hand() -> Vector2:
	return _thrower() + Vector2(30.0, -80.0)


func _guard() -> Vector2:
	return Vector2(size.x - 150.0, 360.0)


func _counter_target() -> Vector2:
	return Vector2(size.x - 78.0, 34.0)


## 按 SEGMENTS 的 span 比例把奖墙竖切成 8 带,返回该档矩形。
func band_rect_for(seg_name: StringName) -> Rect2:
	var b := _board()
	var acc := 0.0
	for s in FortuneWheelLayout.SEGMENTS:
		var frac := float(s["span"]) / 360.0
		if s["name"] == seg_name:
			return Rect2(b.position.x, b.position.y + acc * b.size.y, b.size.x, frac * b.size.y)
		acc += frac
	return b


# --- 输入 / 态机(移植自 world.gd) ---

func _apply_input_mode() -> void:
	var forced = CoreKit.settings.get_value("darts_input", "")
	if forced == "desktop" or forced == "touch":
		_darts_input.set_mode(StringName(forced))
	else:
		_darts_input.set_mode(_darts_input.detect_mode())


func _build_throw_fsm() -> void:
	_throw_fsm = KitStateMachine.new()
	for sname in ["Idle", "Aim", "Charge", "Resolve"]:
		var st := _ThrowState.new()
		st.name = sname
		st.host = self
		_throw_fsm.add_child(st)
	add_child(_throw_fsm)


func _on_throw_down() -> void:
	if _darts_input == null or _darts_input.current_mode() != &"desktop":
		return
	_darts_input.begin_charge()
	if _throw_fsm != null:
		_throw_fsm.transition_to("Charge")


func _on_throw_up() -> void:
	if _darts_input == null or _darts_input.current_mode() != &"desktop":
		return
	_darts_input.release()


func _on_power_changed(p: float) -> void:
	_power = p
	_wind = p


## 命令 model + 表现:每支镖扎进其 seg 对应的墙带,金币按命中档爆量,浮字显示真金额。
func _on_dart_thrown(aim: float, power: float) -> void:
	if _throw_fsm != null:
		_throw_fsm.transition_to("Resolve")
	var r: Dictionary = FortuneMill.do_throw(aim, power)
	for h in r.get("hits", []):
		var seg: StringName = h.get("seg", &"")
		var rect := band_rect_for(seg)
		var target := Vector2(rect.position.x + 18.0 + randf() * (rect.size.x - 40.0), rect.get_center().y)
		_spawn_dart_to(target, seg, float(h.get("gold", 0.0)), bool(h.get("vermin", false)))
	_refresh()


func _resolve_then_idle() -> void:
	await get_tree().create_timer(0.15).timeout
	if _throw_fsm != null and _throw_fsm.is_in("Resolve"):
		_throw_fsm.transition_to("Idle")


## 解算发射速度:飞镖从手在 FLIGHT_T 时刻恰落在 target(真重力抛物线,落点确定)。
func _spawn_dart_to(target: Vector2, seg: StringName, gold: float, vermin: bool) -> void:
	var p0 := _hand()
	var t := FLIGHT_T
	var vx := (target.x - p0.x) / t
	var vy := (target.y - p0.y) / t - 0.5 * GRAV * t
	_darts.append({"p": p0, "vel": Vector2(vx, vy), "t": 0.0, "target": target, "seg": seg, "gold": gold, "vermin": vermin})


func _process(dt: float) -> void:
	if _freeze > 0.0:
		_freeze -= dt
		queue_redraw()
		return
	_t += dt
	_bob = sin(_t * 2.0) * 4.0
	_shake = maxf(0.0, _shake - dt * 3.2)
	_counter_pulse = maxf(0.0, _counter_pulse - dt * 2.4)
	for k in _flash.keys():
		_flash[k] = maxf(0.0, float(_flash[k]) - dt * 3.0)
	# 桌面蓄力中:鼠标 y 定发射角(aim)
	if _darts_input != null and _darts_input.current_mode() == &"desktop" and _throw_fsm != null and _throw_fsm.is_in("Charge"):
		var vp := get_viewport()
		if vp != null:
			var vh := float(vp.get_visible_rect().size.y)
			_darts_input.set_aim(FortuneDartsInput.desktop_aim(vp.get_mouse_position().y, vh))
	# 飞镖:真重力抛物线,t 到 FLIGHT_T 落在目标档
	var kept: Array = []
	for d in _darts:
		d["t"] = float(d["t"]) + dt
		d["vel"] = d["vel"] + Vector2(0.0, GRAV * dt)
		d["p"] = d["p"] + d["vel"] * dt
		if float(d["t"]) >= FLIGHT_T:
			_resolve_dart(d)
		else:
			kept.append(d)
	_darts = kept
	for s in _stuck:
		s["life"] = float(s["life"]) - dt
	_stuck = _stuck.filter(func(x): return float(x["life"]) > 0.0)
	# 收集计时:满则把「已落地」金币成批扫走(空中飞的不收)
	_collect_t -= dt
	if _collect_t <= 0.0:
		_collect_t = COLLECT_INTERVAL
		for co in _coins:
			if co["state"] == "rest":
				co["state"] = "seek"
	# 金币:burst 迸射落地 → rest 堆积 → seek 被收走
	var tgt := _counter_target()
	for co in _coins:
		var st: String = co["state"]
		if st == "seek":
			var to: Vector2 = tgt - co["p"]
			if to.length() < 26.0:
				co["life"] = 0.0
				_counter_pulse = 1.0
				continue
			co["vel"] = co["vel"].lerp(to.normalized() * 1150.0, clampf(dt * 6.0, 0.0, 1.0))
			co["p"] = co["p"] + co["vel"] * dt
		elif st == "rest":
			pass
		else:
			co["vel"] = co["vel"] + Vector2(0.0, GRAV * dt)
			co["p"] = co["p"] + co["vel"] * dt
			var cp: Vector2 = co["p"]
			if cp.y >= float(co["rest_y"]) and co["vel"].y >= 0.0:
				co["p"] = Vector2(cp.x, float(co["rest_y"]))
				co["vel"] = Vector2.ZERO
				co["state"] = "rest"
	_coins = _coins.filter(func(c): return float(c["life"]) > 0.0)
	for pp in _pops:
		pp["p"] = pp["p"] - Vector2(0.0, 40.0 * dt)
		pp["life"] = float(pp["life"]) - dt
	_pops = _pops.filter(func(p): return float(p["life"]) > 0.0)
	queue_redraw()


## 飞镖落定:扎在目标档 + 按档爆金币 + 浮字显示真金额(vermin=劫,不出金币)。
func _resolve_dart(d: Dictionary) -> void:
	var sp: Vector2 = d["target"]
	var seg: StringName = d["seg"]
	var gold: float = d["gold"]
	var vel: Vector2 = d["vel"]
	_stuck.append({"pos": sp, "life": 1.1, "dir": vel.normalized()})
	_flash[seg] = 1.0
	if bool(d["vermin"]):
		_shake = maxf(_shake, 0.45)
		_pops.append({"p": sp + Vector2(-14.0, -20.0), "txt": "劫  0", "life": 0.9, "big": false, "col": RED_SOFT})
		return
	var n := _coins_for(seg)
	if seg == &"jackpot":
		_shake = 1.0; _freeze = 0.07
	elif seg == &"x100":
		_shake = 0.6; _freeze = 0.045
	else:
		_shake = maxf(_shake, 0.32)
	_spawn_coins(sp, n)
	var big := seg == &"jackpot"
	_pops.append({"p": sp + Vector2(-8.0, -20.0), "txt": "+%s" % Currency.format(gold), "life": 0.95, "big": big, "col": GOLD_HI})


## 命中档 → 金币颗数(表现量,不等于金额;金额由浮字显示)。
func _coins_for(seg: StringName) -> int:
	match seg:
		&"jackpot": return 16 + (randi() % 5)
		&"x100": return 12 + (randi() % 4)
		&"x20a", &"x20b": return 9 + (randi() % 3)
		&"x5": return 7 + (randi() % 3)
		_: return 5 + (randi() % 3)


func _spawn_coins(origin: Vector2, n: int) -> void:
	if _coins.size() > 150:
		_coins = _coins.slice(_coins.size() - 150)
	for i in n:
		var ang := randf() * TAU
		var spd := 150.0 + randf() * 230.0
		var ry := FLOOR_Y - randf() * 10.0
		_coins.append({"p": origin, "vel": Vector2(cos(ang), sin(ang) - 1.3) * spd, "state": "burst", "rest_y": ry, "life": 999.0})


# --- HUD ---

func _build_hud() -> void:
	# 返回按钮(左上)
	var back := Button.new()
	back.text = "← 返回世界"
	back.position = Vector2(20.0, 18.0)
	back.pressed.connect(_on_back_pressed)
	add_child(back)
	# 金币 / 自动(右上)
	_gold_label = Label.new()
	_gold_label.position = Vector2(size.x - 280.0, 18.0); _gold_label.size = Vector2(256.0, 28.0)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gold_label.add_theme_font_override("font", _font_or_fallback())
	_gold_label.add_theme_font_size_override("font_size", 24)
	_gold_label.add_theme_color_override("font_color", GOLD)
	add_child(_gold_label)
	_rate_label = Label.new()
	_rate_label.position = Vector2(size.x - 280.0, 48.0); _rate_label.size = Vector2(256.0, 22.0)
	_rate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rate_label.add_theme_font_override("font", _font_or_fallback())
	_rate_label.add_theme_font_size_override("font_size", 15)
	add_child(_rate_label)
	# 投掷按钮(下中,按住蓄力松手投)
	_throw_button = Button.new()
	_throw_button.text = "按住蓄力 · 松手投镖"
	_throw_button.position = Vector2(size.x * 0.5 - 110.0, size.y - 52.0)
	_throw_button.size = Vector2(220.0, 40.0)
	_throw_button.button_down.connect(_on_throw_down)
	_throw_button.button_up.connect(_on_throw_up)
	add_child(_throw_button)
	# 升级按钮(左侧竖排)
	var box := VBoxContainer.new()
	box.position = Vector2(20.0, 92.0); box.custom_minimum_size = Vector2(240.0, 0.0)
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	for id in FortuneMill.registry.ids(&"dart_upgrade", true):
		var btn := Button.new()
		btn.pressed.connect(func() -> void: FortuneMill.buy_dart_upgrade(id))
		box.add_child(btn)
		_upgrade_buttons[id] = btn
	# 贿赂按钮(右下)
	_bribe_button = Button.new()
	_bribe_button.position = Vector2(size.x - 300.0, size.y - 52.0)
	_bribe_button.size = Vector2(276.0, 40.0)
	_bribe_button.pressed.connect(func() -> void: FortuneMill.bribe_guard())
	add_child(_bribe_button)


func _on_back_pressed() -> void:
	await CoreKit.scenes.change_scene(WORLD_SCENE, {"transition": CoreKit.scenes.Transition.FADE})


func _refresh() -> void:
	if _gold_label == null:
		return
	_gold_label.text = "Gold: %s" % Currency.format(FortuneMill.currency.get_amount())
	_rate_label.text = "自动: %s gold/s" % Currency.format(FortuneMill.darts.auto_gold_rate())
	for id in _upgrade_buttons:
		var def = FortuneMill.registry.get_def(&"dart_upgrade", id)
		var cost := FortuneMill.darts.cost_of(id)
		var btn: Button = _upgrade_buttons[id]
		btn.text = "%s  Lv.%d  (%s)" % [def.title, FortuneMill.darts.level_of(id), Currency.format(cost)]
		btn.disabled = not FortuneMill.currency.can_afford(cost)
	if FortuneMill.darts.is_cleared():
		_bribe_button.text = "✅ 已贿赂 Verminous — 放行"
		_bribe_button.disabled = true
	else:
		_bribe_button.text = "贿赂 Verminous (需 %s)" % Currency.format(FortuneMill.darts.bribe_threshold())
		_bribe_button.disabled = not FortuneMill.can_bribe()


# --- 绘制(移植自原型,奖墙换 8 档) ---

func _draw() -> void:
	var shake_off := Vector2.ZERO
	if _shake > 0.0:
		shake_off = Vector2(randf() - 0.5, randf() - 0.5) * 11.0 * _shake
	draw_set_transform(shake_off, 0.0, Vector2.ONE)
	_draw_bg()
	_draw_board(_board())
	_draw_guard(_guard())
	_draw_thrower(_thrower())
	_draw_aim_preview()
	_draw_power_bar()
	for s in _stuck:
		var age: float = 1.1 - float(s["life"])
		if age < 0.26:
			var rr := 8.0 + age * 150.0
			draw_arc(s["pos"], rr, 0.0, TAU, 20, Color(1.0, 1.0, 1.0, (0.26 - age) / 0.26 * 0.7), 3.0)
	for s in _stuck:
		_draw_dart(s["pos"], s["dir"])
	for co in _coins:
		_draw_coin(co["p"], 7.0)
	for d in _darts:
		_draw_dart(d["p"], (d["vel"] as Vector2).normalized())
	_draw_collect_ring()
	_draw_counter_pulse()
	var font := _font_or_fallback()
	for pp in _pops:
		var life: float = pp["life"]
		var a: float = clampf(life / 0.9, 0.0, 1.0)
		var base: Color = pp["col"]
		var fs := 30 if bool(pp["big"]) else 22
		draw_string(font, pp["p"], pp["txt"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(base.r, base.g, base.b, a))


func _draw_bg() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0.0, 0.0, w, h), Color("241d1a"))
	var brick := Color(0.0, 0.0, 0.0, 0.18)
	var y := 36.0
	var row := 0
	while y < 540.0:
		draw_line(Vector2(0.0, y), Vector2(w, y), brick, 2.0)
		var off := 0.0 if row % 2 == 0 else 48.0
		var x := off
		while x < w:
			draw_line(Vector2(x, y), Vector2(x, y + 32.0), brick, 2.0)
			x += 96.0
		y += 32.0
		row += 1
	# 右侧铁门(出口,守卫把守)
	var gx := w - 214.0
	draw_rect(Rect2(gx, 150.0, 190.0, 392.0), Color("100c0a"))
	draw_rect(Rect2(gx, 150.0, 190.0, 392.0), Color("2a231c"), false, 5.0)
	var bx := gx + 22.0
	while bx < gx + 190.0:
		draw_line(Vector2(bx, 158.0), Vector2(bx, 534.0), Color("39342c"), 5.0)
		bx += 26.0
	draw_rect(Rect2(0.0, 540.0, w, h - 540.0), Color("161210"))
	draw_line(Vector2(0.0, 540.0), Vector2(w, 540.0), Color("0c0a08"), 4.0)


## 奖墙:8 档竖带(读 SEGMENTS,按 span 比例),命中闪白,jackpot 描金。
func _draw_board(b: Rect2) -> void:
	draw_rect(b.grow(10.0), Color("3a2c1e"))
	draw_rect(b.grow(10.0), Color("14100b"), false, 4.0)
	var font := _font_or_fallback()
	var acc := 0.0
	for s in FortuneWheelLayout.SEGMENTS:
		var seg: StringName = s["name"]
		var frac := float(s["span"]) / 360.0
		var zr := Rect2(b.position.x, b.position.y + acc * b.size.y, b.size.x, frac * b.size.y)
		acc += frac
		draw_rect(zr, PALETTE.get(seg, Color(0.4, 0.4, 0.4)))
		var fl: float = float(_flash.get(seg, 0.0))
		if fl > 0.0:
			draw_rect(zr, Color(1.0, 1.0, 1.0, fl * 0.55))
		var border := GOLD if seg == &"jackpot" else Color(0.0, 0.0, 0.0, 0.28)
		var bw := 3.0 if seg == &"jackpot" else 2.0
		draw_rect(zr, border, false, bw)
		var txt: String = MULT_LABEL.get(seg, "?")
		var fs := 24 if seg == &"jackpot" else 18
		var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var lp := zr.position + zr.size * 0.5 - ts * 0.5 + Vector2(0.0, ts.y * 0.35)
		draw_string(font, lp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.09, 0.06))


## 瞄准预览:蓄力中高亮当前 aim 命中的档 + 画弹道虚线。
func _draw_aim_preview() -> void:
	if _throw_fsm == null or not (_throw_fsm.is_in("Charge") or _throw_fsm.is_in("Aim")):
		return
	var aim := _cur_aim
	var win_bonus := FortuneMill.modifiers.value_for(&"win_zone", 0.0)
	var seg: StringName = FortuneWheelLayout.segment_at(clampf(aim, 0.0, 1.0) * 360.0, win_bonus)["name"]
	var rect := band_rect_for(seg)
	draw_rect(rect, Color(CYAN.r, CYAN.g, CYAN.b, 0.22))
	draw_rect(rect, CYAN, false, 2.0)
	# 弹道虚线(解算发射速度到档心)
	var p0 := _hand()
	var target := rect.get_center()
	var vx := (target.x - p0.x) / FLIGHT_T
	var vy := (target.y - p0.y) / FLIGHT_T - 0.5 * GRAV * FLIGHT_T
	var vv := Vector2(vx, vy)
	var pt := p0
	for i in 40:
		vv += Vector2(0.0, GRAV * 0.0125)
		pt += vv * 0.0125
		if i % 2 == 0:
			draw_circle(pt, 2.0, Color(CYAN.r, CYAN.g, CYAN.b, maxf(0.08, 0.5 - float(i) * 0.01)))


func _draw_power_bar() -> void:
	var f := _thrower()
	var bx := f.x - 46.0
	var top := 430.0
	var bh := 96.0
	var bw := 14.0
	draw_rect(Rect2(bx, top, bw, bh), Color("0e0b09"))
	draw_rect(Rect2(bx, top, bw, bh), Color("2a231c"), false, 2.0)
	var sweet_y := top + bh * (1.0 - 0.6)
	draw_rect(Rect2(bx - 3.0, sweet_y - 3.0, bw + 6.0, 6.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.85))
	var fh := bh * clampf(_power, 0.0, 1.0)
	var col := CYAN.lerp(GOLD, clampf(_power, 0.0, 1.0))
	draw_rect(Rect2(bx, top + bh - fh, bw, fh), col)


func _draw_collect_ring() -> void:
	var c := _counter_target()
	var prog := 1.0 - clampf(_collect_t / COLLECT_INTERVAL, 0.0, 1.0)
	draw_arc(c, 21.0, -PI / 2.0, -PI / 2.0 + TAU * prog, 26, Color(GOLD.r, GOLD.g, GOLD.b, 0.7), 2.5)


func _draw_counter_pulse() -> void:
	if _counter_pulse <= 0.0:
		return
	var c := _counter_target()
	var r := 16.0 + (1.0 - _counter_pulse) * 26.0
	draw_arc(c, r, 0.0, TAU, 22, Color(GOLD_HI.r, GOLD_HI.g, GOLD_HI.b, _counter_pulse * 0.8), 3.0)
	draw_circle(c, 6.0, Color(GOLD_HI.r, GOLD_HI.g, GOLD_HI.b, _counter_pulse * 0.5))


func _draw_thrower(foot: Vector2) -> void:
	_limbs(foot, CYAN_GLOW, 10.0)
	_limbs(foot, CYAN, 4.0)
	var head := foot + Vector2(0.0, -98.0)
	draw_circle(head, 11.0, CYAN_GLOW)
	draw_circle(head, 7.5, CYAN)


func _limbs(f: Vector2, col: Color, wdt: float) -> void:
	var hip := f + Vector2(0.0, -46.0)
	var sh := f + Vector2(0.0, -84.0)
	draw_line(hip, sh, col, wdt)
	draw_line(hip, f + Vector2(-14.0, -6.0), col, wdt)
	draw_line(hip, f + Vector2(13.0, -6.0), col, wdt)
	var reach := Vector2(18.0, -20.0).lerp(Vector2(36.0, 2.0), 1.0 - _wind)
	draw_line(sh, sh + reach, col, wdt)
	draw_line(sh, sh + Vector2(-12.0, 16.0), col, wdt)


func _draw_guard(c: Vector2) -> void:
	var rx := 78.0
	var ry := 74.0
	var cc := c + Vector2(0.0, _bob)
	draw_polyline(PackedVector2Array([cc + Vector2(rx * 0.7, 18.0), cc + Vector2(rx + 34.0, 2.0), cc + Vector2(rx + 58.0, 26.0)]), RAT_DARK, 5.0)
	_ellipse(cc, rx + 4.0, ry + 4.0, RAT_DARK)
	_ellipse(cc, rx, ry, RAT)
	_ellipse(cc + Vector2(0.0, 16.0), rx * 0.66, ry * 0.60, RAT_BELLY)
	draw_circle(cc + Vector2(-rx * 0.5, -ry * 0.78), 22.0, RAT)
	draw_circle(cc + Vector2(-rx * 0.5, -ry * 0.78), 12.0, PINK)
	draw_circle(cc + Vector2(rx * 0.5, -ry * 0.82), 22.0, RAT)
	draw_circle(cc + Vector2(rx * 0.5, -ry * 0.82), 12.0, PINK)
	_eye(cc + Vector2(-22.0, -8.0))
	_eye(cc + Vector2(24.0, -8.0))
	draw_circle(cc + Vector2(1.0, 20.0), 7.0, PINK)
	draw_circle(cc + Vector2(-32.0, ry - 6.0), 11.0, RAT_DARK)
	draw_circle(cc + Vector2(32.0, ry - 6.0), 11.0, RAT_DARK)


func _eye(p: Vector2) -> void:
	draw_circle(p, 13.0, Color("f4f2ee"))
	draw_circle(p + Vector2(2.0, 2.0), 7.0, Color("23262b"))
	draw_circle(p + Vector2(-2.0, -2.0), 3.0, Color(1.0, 1.0, 1.0, 0.9))


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 30:
		var a := TAU * float(i) / 30.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


func _draw_coin(p: Vector2, r: float) -> void:
	draw_circle(p, r, Color("9a7412"))
	draw_circle(p, r - 2.0, GOLD)
	draw_circle(p + Vector2(-r * 0.3, -r * 0.3), r * 0.28, GOLD_HI)


func _draw_dart(p: Vector2, dir: Vector2) -> void:
	var d := dir.normalized()
	var perp := Vector2(-d.y, d.x)
	var tail := p - d * 15.0
	draw_line(tail, p + d * 6.0, Color("d7dde1"), 3.0)
	var tip := p + d * 11.0
	draw_colored_polygon(PackedVector2Array([tip, p + perp * 4.0, p - perp * 4.0]), Color("ffe08a"))
	draw_line(tail, tail + (perp - d) * 6.0, CYAN, 2.5)
	draw_line(tail, tail - (perp + d) * 6.0, CYAN, 2.5)


## 投掷态机状态:桌面 Charge 由投掷按钮驱动;触屏在 Idle/Aim 接拉弓;Resolve 落定回 Idle。
class _ThrowState extends KitState:
	var host
	var drag: Vector2 = Vector2.ZERO

	func enter(_prev: String) -> void:
		if name == &"Resolve" and host != null:
			host._resolve_then_idle()
		elif name == &"Idle":
			drag = Vector2.ZERO

	func handle_input(event: InputEvent) -> void:
		if host == null or host._darts_input == null:
			return
		if host._darts_input.current_mode() != &"touch":
			return
		if name == &"Idle" and event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
			drag = Vector2.ZERO
			transition_to("Aim")
		elif name == &"Aim":
			if event is InputEventScreenDrag:
				drag += (event as InputEventScreenDrag).relative
			elif event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
				var aim := FortuneDartsInput.touch_aim(drag)
				var power := FortuneDartsInput.touch_power(drag, FortuneDartsInput.DRAG_MAX)
				host._darts_input.fire(aim, power)
				transition_to("Resolve")
