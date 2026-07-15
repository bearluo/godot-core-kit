extends Node2D
## 面前格高亮(占位):每帧读玩家朝向格,在网格内则描边高亮该格,提示工具会作用在哪。

var _player
var _grid
var _punch_cell := Vector2i.ZERO
var _punch_t := 0.0        ## 顿挫计时(1→0),用工具命中该格时置 1


func bind(player, grid) -> void:
	_player = player
	_grid = grid


## 用工具命中该格时调用:触发一次向外扩散并淡出的"顿挫"描边。
func punch(cell: Vector2i) -> void:
	_punch_cell = cell
	_punch_t = 1.0


func _process(delta: float) -> void:
	if _punch_t > 0.0:
		_punch_t = maxf(0.0, _punch_t - delta * 4.0)   # ~0.25s 淡出
	queue_redraw()


func _draw() -> void:
	if _grid == null:
		return
	# 常驻:面前格黄框
	if _player != null:
		var c: Vector2i = _player.facing_cell()
		if _grid.cell_valid(c):
			var cell: int = _grid.cell_size()
			draw_rect(Rect2(_grid.cell_to_world(c), Vector2(cell, cell)), Color(1, 1, 0.3, 0.9), false, 2.0)
	# 顿挫:命中格白框向外扩散 + 淡出
	if _punch_t > 0.0 and _grid.cell_valid(_punch_cell):
		var cs: int = _grid.cell_size()
		var grow := (1.0 - _punch_t) * 8.0
		var r := Rect2(_grid.cell_to_world(_punch_cell) - Vector2(grow, grow), Vector2(cs + grow * 2.0, cs + grow * 2.0))
		draw_rect(r, Color(1.0, 1.0, 1.0, _punch_t), false, 3.0)
