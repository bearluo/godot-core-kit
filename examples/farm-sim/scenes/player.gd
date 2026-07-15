extends CharacterBody2D
## 玩家角色。键盘 WASD 走动 + 4 向朝向;"面前那一格" = 所在格 + 朝向,供工具作用。
## P5:视觉从色块 _draw 升级为 ArtBank 精灵贴图 + 走路踏步动画(2 帧交替 + 轻微上下 bob);逻辑不变。
## 贴图经接缝取(程序化默认,真素材 player_<dir>_<frame>.png 可换入)。Camera2D 跟随。

const SPEED := 140.0
const ArtBank = preload("res://examples/farm-sim/gfx/art_bank.gd")

var facing := Vector2i(0, 1)   ## 4 向朝向(默认朝下)
var input_locked := false       ## 开菜单时锁走动
var _grid                       ## FarmGrid(取 world_to_cell 换算)
var _walk_frame := 0            ## 踏步帧 0/1
var _step_accum := 0.0          ## 走过距离累加(切帧用)
var _bob := 0.0                 ## 走路上下位移(视觉)


func setup(grid) -> void:
	_grid = grid


func _ready() -> void:
	var cam := Camera2D.new()
	add_child(cam)   # 唯一启用的 Camera2D 自动成为当前相机,跟随玩家


func _physics_process(delta: float) -> void:
	if input_locked:
		velocity = Vector2.ZERO
		_set_idle()
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED
	move_and_slide()
	if dir.length() > 0.1:
		# 量化到 4 向:取绝对值较大的轴
		var nf := Vector2i(int(signf(dir.x)), 0) if absf(dir.x) > absf(dir.y) else Vector2i(0, int(signf(dir.y)))
		# 走路踏步:按走过距离每约 12px 切帧,frame 1 抬一下(bob)
		_step_accum += velocity.length() * delta
		var new_frame := (int(_step_accum / 12.0) % 2)
		var new_bob := -2.0 if new_frame == 1 else 0.0
		if nf != facing or new_frame != _walk_frame or new_bob != _bob:
			facing = nf
			_walk_frame = new_frame
			_bob = new_bob
			queue_redraw()
	else:
		_set_idle()


func _set_idle() -> void:
	if _walk_frame != 0 or _bob != 0.0:
		_walk_frame = 0
		_bob = 0.0
		queue_redraw()


## 玩家所在格。
func tile_pos() -> Vector2i:
	return _grid.world_to_cell(global_position)


## 面前那一格(= 所在格 + 朝向)。
func facing_cell() -> Vector2i:
	return tile_pos() + facing


func _draw() -> void:
	# 精灵 24²,中心对齐节点原点;bob 作视觉上下位移(不动碰撞/格坐标)
	var tex := ArtBank.tex(StringName("player_%s_%d" % [_dir_name(), _walk_frame]))
	draw_texture(tex, Vector2(-12, -12 + _bob))


func _dir_name() -> String:
	if facing == Vector2i(0, -1):
		return "up"
	if facing == Vector2i(-1, 0):
		return "left"
	if facing == Vector2i(1, 0):
		return "right"
	return "down"
