extends CharacterBody2D
## 玩家角色(P0 占位)。键盘 WASD 走动 + 4 向朝向;"面前那一格" = 所在格 + 朝向,供工具作用。
## 占位视觉用 _draw 画(身体方块 + 朝向点),Camera2D 跟随。P5 换真 sprite + 动画不动本逻辑。

const SPEED := 140.0

var facing := Vector2i(0, 1)   ## 4 向朝向(默认朝下)
var _grid                       ## FarmGrid(取 world_to_cell 换算)


func setup(grid) -> void:
	_grid = grid


func _ready() -> void:
	var cam := Camera2D.new()
	add_child(cam)   # 唯一启用的 Camera2D 自动成为当前相机,跟随玩家


func _physics_process(_delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED
	move_and_slide()
	if dir.length() > 0.1:
		# 量化到 4 向:取绝对值较大的轴
		var nf := Vector2i(int(signf(dir.x)), 0) if absf(dir.x) > absf(dir.y) else Vector2i(0, int(signf(dir.y)))
		if nf != facing:
			facing = nf
			queue_redraw()


## 玩家所在格。
func tile_pos() -> Vector2i:
	return _grid.world_to_cell(global_position)


## 面前那一格(= 所在格 + 朝向)。
func facing_cell() -> Vector2i:
	return tile_pos() + facing


func _draw() -> void:
	var s := 24.0
	draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), Color(0.9, 0.85, 0.7))   # 身体
	draw_circle(Vector2(facing) * (s * 0.5), 4.0, Color(0.85, 0.2, 0.2))  # 朝向点
