@tool
extends Control
## 原型:命运转盘自绘视图(赌场皮肤)。@tool → 编辑器内也绘制,便于 MCP 截图预览。
## 几何/奖区取自 FortuneWheelLayout(权威);纯表现层,不入 model。

const PALETTE := {
	&"jackpot": Color("f4d35e"),
	&"x2a": Color("4a7c59"), &"x2b": Color("3f6b4e"),
	&"x20a": Color("6a9fb5"), &"x20b": Color("5a8fa5"),
	&"x5": Color("8a7fb5"),
	&"x100": Color("e08a3c"),
	&"vermin": Color("7a3b3b"),
}
const LABELS := {
	&"jackpot": "500", &"x2a": "x2", &"x2b": "x2",
	&"x20a": "x20", &"x20b": "x20", &"x5": "x5",
	&"x100": "x100", &"vermin": "X",
}

@export var angle_deg: float = -9.0:
	set(v):
		angle_deg = v
		queue_redraw()
@export var win_bonus: float = 28.0:
	set(v):
		win_bonus = v
		queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var radius := minf(size.x, size.y) * 0.46
	var font := ThemeDB.fallback_font
	# 金色外环底盘
	draw_circle(c, radius + 12.0, Color("caa24a"))
	draw_circle(c, radius + 7.0, Color("1a120a"))
	# 扇区 + 分隔线 + 倍率标签
	var acc := 0.0
	for s in FortuneWheelLayout.SEGMENTS:
		var seg_name: StringName = s["name"]
		var span := float(s["span"])
		var col: Color = PALETTE.get(seg_name, Color(0.4, 0.4, 0.4))
		_wedge(c, radius, acc + angle_deg, acc + span + angle_deg, col)
		var a0 := deg_to_rad(acc + angle_deg)
		draw_line(c, c + Vector2(cos(a0), sin(a0)) * radius, Color(0, 0, 0, 0.30), 2.0)
		var mid := deg_to_rad(acc + span * 0.5 + angle_deg)
		var lp := c + Vector2(cos(mid), sin(mid)) * radius * 0.64
		var txt: String = LABELS.get(seg_name, "")
		var fs := 24 if seg_name == &"jackpot" else 18
		var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, lp - ts * 0.5 + Vector2(0.0, ts.y * 0.32), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.09, 0.08, 0.05))
		acc += span
	# jackpot 加宽命中带(金弧,示 win_zone 升级看得见)
	var jc := FortuneWheelLayout.jackpot_center()
	var half := FortuneWheelLayout.jackpot_half_base() + maxf(0.0, win_bonus) * 0.5
	draw_arc(c, radius + 4.0, deg_to_rad(jc - half + angle_deg), deg_to_rad(jc + half + angle_deg), 24, Color(1, 0.96, 0.62), 6.0, true)
	# 中心 hub
	draw_circle(c, 26.0, Color("caa24a"))
	draw_circle(c, 21.0, Color("13201a"))
	# 固定命中指针(盘右 0°,不随盘转)
	var tip := c + Vector2(radius + 16.0, 0.0)
	var tri := PackedVector2Array([tip + Vector2(2, 0), tip + Vector2(30, -16), tip + Vector2(30, 16)])
	draw_colored_polygon(tri, Color("e6c260"))
	draw_polyline(PackedVector2Array([tip + Vector2(30, -16), tip + Vector2(2, 0), tip + Vector2(30, 16)]), Color("1a120a"), 2.0)

func _wedge(c: Vector2, radius: float, a0: float, a1: float, col: Color) -> void:
	var pts := PackedVector2Array()
	pts.append(c)
	var steps := maxi(2, int((a1 - a0) / 5.0))
	for i in range(steps + 1):
		var a := deg_to_rad(lerpf(a0, a1, float(i) / float(steps)))
		pts.append(c + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(pts, col)
