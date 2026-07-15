extends Node2D
## NPC 占位节点(P3)。色块 + 头顶名字 Label,按日程站到区域指定格。逻辑数据在 npc_def(Resource),
## 本节点只表现 + 暴露定义/格坐标供交互(相邻判定 → 对话,P4)。P5 换真 sprite 不动此接口。

var _def
var _cell := Vector2i.ZERO


## def = npc_def Resource;cell = 本区站位格坐标(区域按 cell*32 摆放)。
func setup(def, cell: Vector2i) -> void:
	_def = def
	_cell = cell
	var lb := Label.new()
	lb.text = def.display_name
	lb.position = Vector2(-18, -34)
	add_child(lb)
	queue_redraw()


## 本 NPC 的定义 Resource(供交互/送礼)。
func npc_def():
	return _def


## 站位格坐标(供相邻判定)。
func tile_pos() -> Vector2i:
	return _cell


func _draw() -> void:
	var s := 24.0
	draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), Color(0.4, 0.55, 0.85))       # 身体(蓝,区别于玩家)
	draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), Color(1, 1, 1, 0.7), false, 2.0)
