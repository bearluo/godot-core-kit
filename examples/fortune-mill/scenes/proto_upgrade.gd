@tool
extends Control
## 原型:命运磨坊·飞镖房「升级/技能树」屏(商店页)。
## 深棕羊皮纸底 + 左侧磨工剪影 + 金边节点用发光线连成技能树 + 每节点图标/等级点/花费(可升显绿箭头)+
## 选中节点青光高亮 + 右侧详情卡 + 左上「商店/飞镖」页签 + 右上金币。纯表现层:运行(F6)选中节点青光呼吸、
## 绿箭头上下浮;编辑器画静态构图。真像素 sprite 后续 art_bank drop-in 顶替。数值仅示意,未接 DartsRoom。

const BG_TOP := Color("342617")
const BG_BOT := Color("17100a")
const PANEL := Color("40301f")
const PANEL_SEL := Color("173038")
const GOLD := Color("f4c542")
const GOLD_HI := Color("ffdf6e")
const GOLD_DIM := Color("9a7412")
const BORDER := Color("c8912e")
const CYAN := Color("46e0ff")
const GREEN := Color("6ad06a")
const INK := Color("e8dcc0")
const INK_DIM := Color("a9987a")
const LINK := Color("caa23a")
const LOCK := Color("6b5a3f")
const SILVER := Color("d7dde1")

var _font: Font
var _t: float = 0.0
var _nodes: Array = []
var _selected: int = 4


func _ready() -> void:
	_font = load("res://examples/fortune-mill/scenes/proto_font.tres")
	# 技能树:pos=节点中心,parent=上游索引(-1 根),lv/maxlv 等级,cost 花费,icon 图标类型
	_nodes = [
		{"name": "锋利镖头", "icon": "dart",   "pos": Vector2(400, 330), "parent": -1, "lv": 4, "maxlv": 8, "cost": 120,
			"eff": "每镖金币 +2", "nxt": "每镖金币 +3"},
		{"name": "镀金镖尖", "icon": "coin",   "pos": Vector2(560, 205), "parent": 0,  "lv": 2, "maxlv": 6, "cost": 500,
			"eff": "金币 ×1.5", "nxt": "金币 ×1.8"},
		{"name": "双飞镖",   "icon": "double", "pos": Vector2(560, 455), "parent": 0,  "lv": 1, "maxlv": 4, "cost": 800,
			"eff": "每次投 2 支", "nxt": "每次投 3 支"},
		{"name": "稳手",     "icon": "hand",   "pos": Vector2(720, 150), "parent": 1,  "lv": 3, "maxlv": 6, "cost": 1500,
			"eff": "落点抖动 -20%", "nxt": "落点抖动 -30%"},
		{"name": "拓宽甜区", "icon": "target", "pos": Vector2(720, 320), "parent": 1,  "lv": 2, "maxlv": 5, "cost": 2600,
			"eff": "★500 命中带 +15%", "nxt": "★500 命中带 +25%"},
		{"name": "雇佣磨工", "icon": "robot",  "pos": Vector2(720, 470), "parent": 2,  "lv": 0, "maxlv": 3, "cost": 4000,
			"eff": "自动投掷 0.8/s", "nxt": "自动投掷 1.1/s"},
		{"name": "贿赂折扣", "icon": "gate",   "pos": Vector2(858, 300), "parent": 4,  "lv": 0, "maxlv": 4, "cost": 9000,
			"eff": "过关门槛 未减", "nxt": "过关门槛 -5%"},
	]


func _font_or_fallback() -> Font:
	return _font if _font != null else ThemeDB.fallback_font


func _process(dt: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += dt
	queue_redraw()


func _draw() -> void:
	_draw_bg()
	_draw_silhouette()
	_draw_title()
	# 连线(先画,压在节点下)
	for i in _nodes.size():
		var nd: Dictionary = _nodes[i]
		var par: int = nd["parent"]
		if par >= 0:
			var a: Vector2 = _nodes[par]["pos"]
			var b: Vector2 = nd["pos"]
			var lit: bool = int(nd["lv"]) > 0
			_draw_link(a, b, lit)
	# 节点
	for i in _nodes.size():
		_draw_node(_nodes[i], i == _selected)
	_draw_detail(_nodes[_selected])
	_draw_tabs()
	_draw_currency()


func _draw_bg() -> void:
	var w := size.x
	var h := size.y
	var bands := 40
	for i in bands:
		var f := float(i) / float(bands - 1)
		draw_rect(Rect2(0.0, h * f, w, h / float(bands) + 1.0), BG_TOP.lerp(BG_BOT, f))
	# 羊皮纸划痕
	for k in 7:
		var yy := 60.0 + float(k) * 82.0
		draw_line(Vector2(0.0, yy), Vector2(w, yy + 22.0), Color(0.0, 0.0, 0.0, 0.05), 1.0)
	# 顶部高光
	draw_line(Vector2(0.0, 2.0), Vector2(w, 2.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.10), 2.0)


func _draw_silhouette() -> void:
	# 左侧磨工(火柴人)剪影,青色极淡
	var f := Vector2(150.0, 470.0)
	var col := Color(CYAN.r, CYAN.g, CYAN.b, 0.06)
	var hip := f + Vector2(0.0, -92.0)
	var sh := f + Vector2(0.0, -168.0)
	draw_line(hip, sh, col, 22.0)
	draw_line(hip, f + Vector2(-28.0, -12.0), col, 22.0)
	draw_line(hip, f + Vector2(26.0, -12.0), col, 22.0)
	draw_line(sh, sh + Vector2(60.0, -30.0), col, 20.0)
	draw_line(sh, sh + Vector2(-24.0, 32.0), col, 20.0)
	draw_circle(sh + Vector2(0.0, -34.0), 26.0, col)


func _draw_title() -> void:
	var font := _font_or_fallback()
	draw_string(font, Vector2(44.0, 116.0), "磨 工 工 坊", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, INK)
	draw_string(font, Vector2(46.0, 146.0), "命运磨坊 · 飞镖房升级", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK_DIM)
	draw_line(Vector2(46.0, 158.0), Vector2(300.0, 158.0), Color(BORDER.r, BORDER.g, BORDER.b, 0.5), 2.0)


func _draw_link(a: Vector2, b: Vector2, lit: bool) -> void:
	var mid := (a + b) * 0.5 + Vector2(0.0, -18.0)
	var pts := PackedVector2Array()
	for i in 17:
		var t := float(i) / 16.0
		var p := a.lerp(mid, t).lerp(mid.lerp(b, t), t)
		pts.append(p)
	if lit:
		draw_polyline(pts, Color(LINK.r, LINK.g, LINK.b, 0.22), 8.0)
		draw_polyline(pts, Color(GOLD_HI.r, GOLD_HI.g, GOLD_HI.b, 0.85), 2.5)
	else:
		draw_polyline(pts, Color(LOCK.r, LOCK.g, LOCK.b, 0.5), 3.0)


func _draw_node(nd: Dictionary, is_sel: bool) -> void:
	var pos: Vector2 = nd["pos"]
	var lv: int = nd["lv"]
	var mx: int = nd["maxlv"]
	var locked: bool = lv <= 0
	var box := Rect2(pos - Vector2(42.0, 42.0), Vector2(84.0, 84.0))
	# 选中青光呼吸
	if is_sel:
		var g := 0.45 + 0.35 * sin(_t * 3.0)
		for k in 3:
			draw_rect(box.grow(6.0 + float(k) * 5.0), Color(CYAN.r, CYAN.g, CYAN.b, g * (0.20 - float(k) * 0.05)), false, 3.0)
	draw_rect(box, PANEL_SEL if is_sel else PANEL)
	draw_rect(box, Color(0.0, 0.0, 0.0, 0.35), false, 2.0)
	draw_rect(box.grow(2.0), CYAN if is_sel else (BORDER if not locked else LOCK), false, 3.0)
	_draw_icon(nd["icon"], pos + Vector2(0.0, -3.0), 22.0, locked)
	var font := _font_or_fallback()
	# 名称
	var nm: String = nd["name"]
	var ts := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
	draw_string(font, Vector2(pos.x - ts.x * 0.5, pos.y + 60.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK if not locked else INK_DIM)
	# 等级点
	var total_w := float(mx) * 9.0
	var px := pos.x - total_w * 0.5 + 4.0
	for i in mx:
		var filled := i < lv
		draw_circle(Vector2(px + float(i) * 9.0, pos.y + 74.0), 3.0, GOLD if filled else Color(0.0, 0.0, 0.0, 0.35))
	# 花费 / MAX / 可升绿箭头
	if lv >= mx:
		var mts := font.get_string_size("MAX", HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
		draw_string(font, Vector2(pos.x - mts.x * 0.5, pos.y + 94.0), "MAX", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK_DIM)
	else:
		var cost: int = nd["cost"]
		var ctxt := _money(cost)
		var cts := font.get_string_size(ctxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
		var bob := sin(_t * 4.0) * 2.0 if not Engine.is_editor_hint() else 0.0
		var ax := pos.x - (cts.x + 16.0) * 0.5
		# 绿色升级箭头
		var ay := pos.y + 90.0 + bob
		draw_colored_polygon(PackedVector2Array([Vector2(ax, ay + 2.0), Vector2(ax + 6.0, ay - 8.0), Vector2(ax + 12.0, ay + 2.0)]), GREEN)
		draw_string(font, Vector2(ax + 18.0, pos.y + 94.0), ctxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, GOLD)


func _draw_detail(nd: Dictionary) -> void:
	var card := Rect2(905.0, 150.0, 218.0, 372.0)
	draw_rect(card, Color("241a10"))
	draw_rect(card, BORDER, false, 2.0)
	draw_rect(Rect2(card.position, Vector2(card.size.x, 40.0)), Color(BORDER.r, BORDER.g, BORDER.b, 0.16))
	var font := _font_or_fallback()
	var nm: String = nd["name"]
	draw_string(font, Vector2(card.position.x + 16.0, card.position.y + 28.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, GOLD_HI)
	# 大图标
	var ic := card.position + Vector2(card.size.x * 0.5, 96.0)
	draw_rect(Rect2(ic - Vector2(34.0, 34.0), Vector2(68.0, 68.0)), Color("2f2213"))
	draw_rect(Rect2(ic - Vector2(34.0, 34.0), Vector2(68.0, 68.0)), CYAN, false, 2.0)
	_draw_icon(nd["icon"], ic, 30.0, false)
	# 等级
	var lv: int = nd["lv"]
	var mx: int = nd["maxlv"]
	draw_string(font, Vector2(card.position.x + 16.0, card.position.y + 168.0), "等级  %d / %d" % [lv, mx], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
	var px := card.position.x + 16.0
	for i in mx:
		draw_circle(Vector2(px + float(i) * 12.0, card.position.y + 186.0), 4.0, GOLD if i < lv else Color(0.0, 0.0, 0.0, 0.4))
	# 效果
	draw_string(font, Vector2(card.position.x + 16.0, card.position.y + 224.0), "当前", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK_DIM)
	draw_string(font, Vector2(card.position.x + 16.0, card.position.y + 246.0), str(nd["eff"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
	draw_string(font, Vector2(card.position.x + 16.0, card.position.y + 280.0), "下一级", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK_DIM)
	draw_string(font, Vector2(card.position.x + 16.0, card.position.y + 302.0), str(nd["nxt"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, GREEN)
	# 升级按钮
	var btn := Rect2(card.position.x + 16.0, card.position.y + 320.0, card.size.x - 32.0, 38.0)
	var maxed := lv >= mx
	draw_rect(btn, Color("1c3a1c") if not maxed else Color("2a2418"))
	draw_rect(btn, GREEN if not maxed else INK_DIM, false, 2.0)
	var btxt := "升 级   " + _money(int(nd["cost"])) if not maxed else "已 满 级"
	var bts := font.get_string_size(btxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	draw_string(font, btn.position + Vector2((btn.size.x - bts.x) * 0.5, 26.0), btxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GOLD_HI if not maxed else INK_DIM)


func _draw_tabs() -> void:
	var font := _font_or_fallback()
	# 商店(当前页,青色高亮)
	_tab(Rect2(24.0, 20.0, 100.0, 40.0), "商 店", true, font)
	# 飞镖(切回打飞镖)
	_tab(Rect2(132.0, 20.0, 100.0, 40.0), "飞 镖", false, font)


func _tab(r: Rect2, txt: String, active: bool, font: Font) -> void:
	draw_rect(r, Color("17262b") if active else Color("241c12"))
	draw_rect(r, CYAN if active else Color(BORDER.r, BORDER.g, BORDER.b, 0.6), false, 2.0)
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	draw_string(font, r.position + Vector2((r.size.x - ts.x) * 0.5, 27.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("bfeeff") if active else INK_DIM)
	if active:
		draw_line(r.position + Vector2(6.0, r.size.y - 2.0), r.position + Vector2(r.size.x - 6.0, r.size.y - 2.0), CYAN, 3.0)


func _draw_currency() -> void:
	var font := _font_or_fallback()
	var c := Vector2(size.x - 168.0, 38.0)
	draw_circle(c, 13.0, GOLD_DIM)
	draw_circle(c, 10.0, GOLD)
	draw_circle(c + Vector2(-3.0, -3.0), 3.0, GOLD_HI)
	draw_string(font, Vector2(c.x + 20.0, 48.0), "1,234", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, GOLD_HI)


func _money(v: int) -> String:
	var s := str(v)
	var out := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return out


# --- 图标 ---

func _draw_icon(kind: String, c: Vector2, s: float, locked: bool) -> void:
	var main := INK_DIM if locked else SILVER
	match kind:
		"dart":
			_icon_dart(c, s, main)
		"coin":
			draw_circle(c, s * 0.72, GOLD_DIM)
			draw_circle(c, s * 0.56, GOLD)
			draw_line(c + Vector2(-s * 0.3, -s * 0.3), c + Vector2(s * 0.3, s * 0.3), Color("6a4d0c"), 3.0)
			draw_line(c + Vector2(s * 0.3, -s * 0.3), c + Vector2(-s * 0.3, s * 0.3), Color("6a4d0c"), 3.0)
		"double":
			_icon_dart(c + Vector2(-s * 0.28, 0.0), s * 0.82, main)
			_icon_dart(c + Vector2(s * 0.28, 0.0), s * 0.82, main)
		"hand":
			draw_arc(c, s * 0.7, 0.0, TAU, 24, CYAN, 2.5)
			draw_line(c + Vector2(-s, 0.0), c + Vector2(-s * 0.4, 0.0), CYAN, 2.0)
			draw_line(c + Vector2(s, 0.0), c + Vector2(s * 0.4, 0.0), CYAN, 2.0)
			draw_line(c + Vector2(0.0, -s), c + Vector2(0.0, -s * 0.4), CYAN, 2.0)
			draw_line(c + Vector2(0.0, s), c + Vector2(0.0, s * 0.4), CYAN, 2.0)
			draw_circle(c, 2.5, CYAN)
		"target":
			draw_circle(c, s * 0.78, Color("6a9fb5"))
			draw_circle(c, s * 0.54, Color("e8dcc0"))
			draw_circle(c, s * 0.30, GOLD)
			draw_circle(c, s * 0.10, Color("7a3b3b"))
		"robot":
			draw_rect(Rect2(c - Vector2(s * 0.6, s * 0.5), Vector2(s * 1.2, s * 1.0)), Color("8a8f96"))
			draw_rect(Rect2(c - Vector2(s * 0.6, s * 0.5), Vector2(s * 1.2, s * 1.0)), Color("3a3d42"), false, 2.0)
			draw_circle(c + Vector2(-s * 0.26, -s * 0.05), s * 0.14, CYAN)
			draw_circle(c + Vector2(s * 0.26, -s * 0.05), s * 0.14, CYAN)
			draw_line(c + Vector2(0.0, -s * 0.5), c + Vector2(0.0, -s * 0.85), Color("3a3d42"), 2.0)
			draw_circle(c + Vector2(0.0, -s * 0.9), 3.0, GOLD)
		"gate":
			draw_line(c + Vector2(-s * 0.5, -s * 0.7), c + Vector2(-s * 0.5, s * 0.7), Color("6b5a3f"), 4.0)
			draw_line(c + Vector2(0.0, -s * 0.7), c + Vector2(0.0, s * 0.7), Color("6b5a3f"), 4.0)
			draw_line(c + Vector2(s * 0.5, -s * 0.7), c + Vector2(s * 0.5, s * 0.7), Color("6b5a3f"), 4.0)
			draw_circle(c + Vector2(s * 0.28, s * 0.18), s * 0.42, GOLD_DIM)
			draw_circle(c + Vector2(s * 0.28, s * 0.18), s * 0.32, GOLD)
		_:
			draw_circle(c, s * 0.5, main)


func _icon_dart(c: Vector2, s: float, main: Color) -> void:
	var d := Vector2(0.72, -0.72).normalized()
	var perp := Vector2(-d.y, d.x)
	var tail := c - d * s * 0.72
	draw_line(tail, c + d * s * 0.42, main, 3.0)
	var tp := c + d * s * 0.86
	var mid := c + d * s * 0.36
	draw_colored_polygon(PackedVector2Array([tp, mid + perp * s * 0.22, mid - perp * s * 0.22]), GOLD_HI)
	draw_line(tail, tail + (perp - d) * s * 0.3, CYAN, 2.0)
	draw_line(tail, tail - (perp + d) * s * 0.3, CYAN, 2.0)
