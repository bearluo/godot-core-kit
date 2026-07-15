extends Node2D
## 区域切换门/边界(P3 占位)。一块色块 + 头顶门牌 Label,玩家走进其矩形区域 → Farm.go_to 切到目标区。
## 位置轮询判定(玩家为无碰撞体的占位角色,故不用 Area2D 物理,直接读 Farm.current_player 位置)。
## 触发一次即锁(_triggered),切场景后随旧场景一起释放,不会重复触发。

const SIZE := Vector2(40, 40)
const ArtBank = preload("res://examples/farm-sim/art_bank.gd")

var _target_path := ""
var _target_spawn := Vector2.ZERO
var _transition                    ## KitTransition
var _color := Color(0.55, 0.4, 0.25)
var _triggered := false


## target_path=目标区 .tscn;target_spawn=到达后玩家落点(世界坐标);transition=KitTransition;
## label=门牌文字;color=占位色块颜色。
func setup(target_path: String, target_spawn: Vector2, transition, label: String, color: Color) -> void:
	_target_path = target_path
	_target_spawn = target_spawn
	_transition = transition
	_color = color
	var lb := Label.new()
	lb.text = label
	lb.position = Vector2(-SIZE.x * 0.5, -SIZE.y * 0.5 - 20)
	add_child(lb)
	queue_redraw()


func _process(_delta: float) -> void:
	if _triggered or _target_path == "":
		return
	var p = Farm.current_player()
	if p == null:
		return
	if Rect2(global_position - SIZE * 0.5, SIZE).has_point(p.global_position):
		_triggered = true
		Farm.go_to(_target_path, _target_spawn, _transition)


func _draw() -> void:
	# 门贴图(近白)用 modulate 上各门颜色;中心对齐
	draw_texture_rect(ArtBank.tex(&"door"), Rect2(-SIZE * 0.5, SIZE), false, _color)
