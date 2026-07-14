extends Node2D
## 面前格高亮(占位):每帧读玩家朝向格,在网格内则描边高亮该格,提示工具会作用在哪。

var _player
var _grid


func bind(player, grid) -> void:
	_player = player
	_grid = grid


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _player == null or _grid == null:
		return
	var c: Vector2i = _player.facing_cell()
	if not _grid.cell_valid(c):
		return
	var cell: int = _grid.cell_size()
	draw_rect(Rect2(_grid.cell_to_world(c), Vector2(cell, cell)), Color(1, 1, 0.3, 0.9), false, 2.0)
