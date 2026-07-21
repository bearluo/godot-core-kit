class_name FortuneFx
extends CanvasLayer
## UI 手感层(纯表现;仅可玩路径实例化,不参与 headless smoke 数值)。
## 浮动数字冒泡 popup + 全屏闪光 flash + 控件按下脉冲 pulse。全走 Tween,播完自清理。
## 挂高层级(z 表 SYSTEM 之下),不拦鼠标,不持有权威数值。

const POP_RISE := 44.0
const POP_TIME := 0.9


func _init() -> void:
	layer = 50


## 在 pos(视口坐标)冒一条上浮渐隐文字(如 "+123 gold")。
func popup(text: String, pos: Vector2, color: Color = Color.WHITE) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.position = pos
	lbl.z_index = 100
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", pos.y - POP_RISE, POP_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, POP_TIME).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(lbl.queue_free)


## 全屏一闪(JACKPOT / 过关庆祝)。color 带 alpha,快速淡出后自清理。
func flash(color: Color) -> void:
	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = 90
	add_child(rect)
	var tw := create_tween()
	tw.tween_property(rect, "modulate:a", 0.0, 0.5).from(1.0)
	tw.tween_callback(rect.queue_free)


## 控件按下脉冲:快速放大回弹(附着在已入树的 Control 上)。
func pulse(node: Control) -> void:
	if node == null or not node.is_inside_tree():
		return
	node.pivot_offset = node.size * 0.5
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector2(1.08, 1.08), 0.06).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(node, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_QUAD)
