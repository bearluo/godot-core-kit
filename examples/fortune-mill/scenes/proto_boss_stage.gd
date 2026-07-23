@tool
extends Control
## 原型舞台:命运磨坊·飞镖房(抛物线投掷 + 落地堆积 + 间隔收集)。
## 左=火柴人按「发射角 + 力度」抛飞镖 → 飞镖走真抛物线(重力下坠)扎中墙上奖区 → 命中爆金币,
## 金币落地堆积,每隔「收集间隔」把「已落地」金币成批扫进右上计数器(空中飞的不收) → 右=看守 Verminous
## (守铁门的门神,攒够门槛「贿赂」才放行,不是攻击目标)。含一块「劫」没收区;抛飞/落空 = miss。
## 纯表现层:运行(F6)自动扫角度+蓄力演示 (angle,power);编辑器画静态构图。真像素 sprite 后续 art_bank drop-in 顶替。

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

## 抛物线 / 收集参数
const GRAV := 1000.0
const ANG_MIN := 12.0
const ANG_MAX := 56.0
const SPD_MIN := 700.0
const SPD_MAX := 820.0
const FLOOR_Y := 588.0
const COLLECT_INTERVAL := 3.0

## 墙上奖区(上→下)。jackpot(★500)居中最大,末位「劫」为没收区。
const ZONES := [
	{"mult": "x2",    "col": Color("4a7c59")},
	{"mult": "x20",   "col": Color("6a9fb5")},
	{"mult": "★ 500", "col": Color("f4d35e")},
	{"mult": "x100",  "col": Color("e08a3c")},
	{"mult": "x5",    "col": Color("8a7fb5")},
	{"mult": "劫",    "col": Color("7a3b3b")},
]

var _font: Font
var _t: float = 0.0
var _wind: float = 0.0
var _bob: float = 0.0
var _angle: float = 30.0
var _ang_dir: float = 1.0
var _power: float = 0.0
var _release_at: float = 0.7
var _shake: float = 0.0
var _freeze: float = 0.0
var _counter_pulse: float = 0.0
var _collect_t: float = COLLECT_INTERVAL
var _zone_flash := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _darts: Array = []
var _stuck: Array = []
var _coins: Array = []
var _pops: Array = []


func _ready() -> void:
	_font = load("res://examples/fortune-mill/scenes/proto_font.tres")


func _font_or_fallback() -> Font:
	return _font if _font != null else ThemeDB.fallback_font


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


func _launch_vel(angle_deg: float, speed: float) -> Vector2:
	var r := deg_to_rad(angle_deg)
	return Vector2(cos(r), -sin(r)) * speed


func _process(dt: float) -> void:
	if Engine.is_editor_hint():
		return
	# 扎中顿挫:短暂冻结整帧(hitstop),制造打击感
	if _freeze > 0.0:
		_freeze -= dt
		queue_redraw()
		return
	_t += dt
	_bob = sin(_t * 2.0) * 4.0
	_shake = maxf(0.0, _shake - dt * 3.2)
	_counter_pulse = maxf(0.0, _counter_pulse - dt * 2.4)
	for i in _zone_flash.size():
		_zone_flash[i] = maxf(0.0, _zone_flash[i] - dt * 3.0)
	# 发射角上下扫(演示玩家控制发射角度)
	_angle += _ang_dir * dt * 22.0
	if _angle >= ANG_MAX:
		_angle = ANG_MAX
		_ang_dir = -1.0
	elif _angle <= ANG_MIN:
		_angle = ANG_MIN
		_ang_dir = 1.0
	# 蓄力,满即投
	_power += dt * 1.35
	_wind = clampf(_power / maxf(_release_at, 0.01), 0.0, 1.0)
	if _power >= _release_at:
		_throw_dart(_angle, clampf(_power, 0.0, 1.0))
		_power = 0.0
		_release_at = 0.6 + randf() * 0.5
	# 飞镖:真抛物线积分
	var kept: Array = []
	for d in _darts:
		d["vel"] = d["vel"] + Vector2(0.0, GRAV * dt)
		d["p"] = d["p"] + d["vel"] * dt
		var dp: Vector2 = d["p"]
		if dp.x >= d["stick_x"]:
			_resolve_dart(d)
		elif dp.y >= FLOOR_Y:
			_miss_dart(dp)
		elif dp.x > size.x + 40.0 or dp.y < -60.0:
			pass
		else:
			kept.append(d)
	_darts = kept
	for s in _stuck:
		s["life"] -= dt
	_stuck = _stuck.filter(func(x): return x["life"] > 0.0)
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
			if cp.y >= co["rest_y"] and co["vel"].y >= 0.0:
				co["p"] = Vector2(cp.x, co["rest_y"])
				co["vel"] = Vector2.ZERO
				co["state"] = "rest"
	_coins = _coins.filter(func(c): return c["life"] > 0.0)
	for pp in _pops:
		pp["p"] = pp["p"] - Vector2(0.0, 40.0 * dt)
		pp["life"] -= dt
	_pops = _pops.filter(func(p): return p["life"] > 0.0)
	queue_redraw()


func _throw_dart(angle: float, power: float) -> void:
	var b := _board()
	var spd := lerpf(SPD_MIN, SPD_MAX, power)
	var v := _launch_vel(angle, spd)
	var sx := b.position.x + 10.0 + randf() * 70.0
	_darts.append({"p": _hand(), "vel": v, "stick_x": sx})


func _resolve_dart(d: Dictionary) -> void:
	var p: Vector2 = d["p"]
	var b := _board()
	var dir: Vector2 = d["vel"].normalized()
	if p.y < b.position.y or p.y > b.position.y + b.size.y:
		_miss_dart(p)
		return
	var zh := b.size.y / 6.0
	var zi := clampi(int((p.y - b.position.y) / zh), 0, 5)
	var sp := Vector2(clampf(p.x, b.position.x + 6.0, b.position.x + b.size.x - 6.0), p.y)
	_stuck.append({"pos": sp, "life": 1.1, "dir": dir})
	_zone_flash[zi] = 1.0
	if zi == 5:
		# 劫:没收
		_shake = maxf(_shake, 0.45)
		_pops.append({"p": sp + Vector2(-14.0, -20.0), "txt": "劫  0", "life": 0.9, "big": false, "col": RED_SOFT})
		return
	var big := zi == 2
	var mid := zi == 1 or zi == 3
	var n := 5 + (randi() % 4)
	if big:
		n = 14 + (randi() % 5)
		_shake = 1.0
		_freeze = 0.07
	elif mid:
		n = 8 + (randi() % 5)
		_shake = 0.6
		_freeze = 0.045
	else:
		_shake = maxf(_shake, 0.32)
	_spawn_coins(sp, n)
	_pops.append({"p": sp + Vector2(-8.0, -20.0), "txt": "+%d" % (n * 4), "life": 0.95, "big": big, "col": GOLD_HI})


func _miss_dart(p: Vector2) -> void:
	# 抛飞/落空:插一下、灰字提示,不出金币
	_stuck.append({"pos": p, "life": 0.55, "dir": Vector2(0.3, 1.0)})
	_shake = maxf(_shake, 0.18)
	_pops.append({"p": p + Vector2(-16.0, -16.0), "txt": "落空", "life": 0.7, "big": false, "col": GRAY})


func _spawn_coins(origin: Vector2, n: int) -> void:
	if _coins.size() > 150:
		_coins = _coins.slice(_coins.size() - 150)
	for i in n:
		var ang := randf() * TAU
		var spd := 150.0 + randf() * 230.0
		var ry := FLOOR_Y - randf() * 10.0
		_coins.append({"p": origin, "vel": Vector2(cos(ang), sin(ang) - 1.3) * spd, "state": "burst", "rest_y": ry, "life": 999.0})


func _draw() -> void:
	# 震屏:整个舞台内容按 _shake 抖动(HUD 是父节点,不受影响)
	var shake_off := Vector2.ZERO
	if _shake > 0.0:
		shake_off = Vector2(randf() - 0.5, randf() - 0.5) * 11.0 * _shake
	draw_set_transform(shake_off, 0.0, Vector2.ONE)
	_draw_bg()
	_draw_board(_board())
	_draw_guard(_guard())
	_draw_thrower(_thrower())
	_draw_launch()
	_draw_power_bar()
	# 扎中冲击环
	for s in _stuck:
		var age: float = 1.1 - s["life"]
		if age < 0.26:
			var rr := 8.0 + age * 150.0
			draw_arc(s["pos"], rr, 0.0, TAU, 20, Color(1.0, 1.0, 1.0, (0.26 - age) / 0.26 * 0.7), 3.0)
	for s in _stuck:
		var sd: Vector2 = s["dir"]
		_draw_dart(s["pos"], sd)
	# 金币(堆积 + 飞行)
	for co in _coins:
		_draw_coin(co["p"], 7.0)
	# 飞行中的飞镖(顺弹道朝向)
	for d in _darts:
		var dp: Vector2 = d["p"]
		var dv: Vector2 = d["vel"]
		_draw_dart(dp, dv.normalized())
	_draw_collect_ring()
	_draw_counter_pulse()
	var font := _font_or_fallback()
	for pp in _pops:
		var life: float = pp["life"]
		var a: float = clampf(life / 0.9, 0.0, 1.0)
		var base: Color = pp["col"]
		var fs := 30 if pp["big"] else 22
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
	draw_rect(Rect2(58.0, 66.0, 132.0, 84.0), Color("2f2a25"))
	draw_rect(Rect2(58.0, 66.0, 132.0, 84.0), Color("15110e"), false, 3.0)
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
	draw_line(Vector2(w * 0.40, 0.0), Vector2(w * 0.50, h), Color(GOLD.r, GOLD.g, GOLD.b, 0.09), 3.0)


func _draw_board(b: Rect2) -> void:
	draw_rect(b.grow(10.0), Color("3a2c1e"))
	draw_rect(b.grow(10.0), Color("14100b"), false, 4.0)
	var zh := b.size.y / float(ZONES.size())
	var font := _font_or_fallback()
	for i in ZONES.size():
		var zr := Rect2(b.position.x, b.position.y + zh * float(i), b.size.x, zh)
		draw_rect(zr, ZONES[i]["col"])
		var fl: float = _zone_flash[i]
		if fl > 0.0:
			draw_rect(zr, Color(1.0, 1.0, 1.0, fl * 0.55))
		draw_rect(zr, Color(0.0, 0.0, 0.0, 0.28), false, 2.0)
		var txt: String = ZONES[i]["mult"]
		var fs := 28 if i == 2 else 20
		var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var lp := zr.position + zr.size * 0.5 - ts * 0.5 + Vector2(0.0, ts.y * 0.35)
		draw_string(font, lp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.09, 0.06))


func _draw_launch() -> void:
	var h := _hand()
	var fill := clampf(_power / maxf(_release_at, 0.01), 0.0, 1.0)
	var spd := lerpf(SPD_MIN, SPD_MAX, fill)
	var v := _launch_vel(_angle, spd)
	# 发射方向箭头(长度随蓄力)
	var tip := h + v.normalized() * (26.0 + fill * 24.0)
	draw_line(h, tip, Color(CYAN.r, CYAN.g, CYAN.b, 0.95), 3.0)
	var pd := (tip - h).normalized()
	var pp := Vector2(-pd.y, pd.x)
	draw_colored_polygon(PackedVector2Array([tip + pd * 8.0, tip + pp * 5.0, tip - pp * 5.0]), CYAN)
	# 弹道预览(虚线抛物线)
	var stick := _board().position.x + 40.0
	var pt := h
	var vv := v
	for i in 48:
		vv += Vector2(0.0, GRAV * 0.016)
		pt += vv * 0.016
		if pt.x >= stick or pt.y >= FLOOR_Y:
			break
		if i % 2 == 0:
			draw_circle(pt, 2.2, Color(CYAN.r, CYAN.g, CYAN.b, maxf(0.08, 0.5 - float(i) * 0.008)))


func _draw_power_bar() -> void:
	var f := _thrower()
	var bx := f.x - 46.0
	var top := 430.0
	var bh := 96.0
	var bw := 14.0
	draw_rect(Rect2(bx, top, bw, bh), Color("0e0b09"))
	draw_rect(Rect2(bx, top, bw, bh), Color("2a231c"), false, 2.0)
	# 甜点带(power≈0.6 最佳)
	var sweet_y := top + bh * (1.0 - 0.6)
	draw_rect(Rect2(bx - 3.0, sweet_y - 3.0, bw + 6.0, 6.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.85))
	var fill := clampf(_power / maxf(_release_at, 0.01), 0.0, 1.0)
	var fh := bh * fill
	var col := CYAN.lerp(GOLD, fill)
	draw_rect(Rect2(bx, top + bh - fh, bw, fh), col)


func _draw_collect_ring() -> void:
	# 计数器旁「收集充能」环:满一圈即成批扫走地上金币
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
	var f := foot
	_limbs(f, CYAN_GLOW, 10.0)
	_limbs(f, CYAN, 4.0)
	var head := f + Vector2(0.0, -98.0)
	draw_circle(head, 11.0, CYAN_GLOW)
	draw_circle(head, 7.5, CYAN)


func _limbs(f: Vector2, col: Color, wdt: float) -> void:
	var hip := f + Vector2(0.0, -46.0)
	var sh := f + Vector2(0.0, -84.0)
	draw_line(hip, sh, col, wdt)
	draw_line(hip, f + Vector2(-14.0, -6.0), col, wdt)
	draw_line(hip, f + Vector2(13.0, -6.0), col, wdt)
	# 投掷臂:蓄力(_wind→1)时前伸,松手回收 → 甩镖动作
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
