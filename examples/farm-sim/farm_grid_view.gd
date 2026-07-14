extends Node2D
## 农田占位渲染(薄 renderer):只读 FarmGrid 逐格画彩色方块 + 作物按生长比例的小方块。
## 逻辑全在 FarmGrid,这里零逻辑——P5 换成 TileMapLayer + 真 tileset 时本文件整体替换,不动模型。

const FarmGrid = preload("res://examples/farm-sim/farm_grid.gd")

var _grid


func bind(grid) -> void:
	_grid = grid
	queue_redraw()


func _draw() -> void:
	if _grid == null:
		return
	var sz: Vector2i = _grid.size()
	var cell: int = _grid.cell_size()
	for y in range(sz.y):
		for x in range(sz.x):
			var c := Vector2i(x, y)
			var origin: Vector2 = _grid.cell_to_world(c)
			var rect := Rect2(origin, Vector2(cell, cell))
			draw_rect(rect, _tile_color(_grid.tile_state(c)))
			draw_rect(rect, Color(0, 0, 0, 0.15), false, 1.0)   # 网格线
			if _grid.has_crop(c):
				var r: float = _grid.crop_ratio(c)
				var inset: float = cell * (0.5 - 0.32 * r)      # 越熟越大
				var crop_rect := Rect2(origin + Vector2(inset, inset), Vector2(cell - inset * 2, cell - inset * 2))
				draw_rect(crop_rect, Color(0.3, 0.8, 0.3).lerp(Color(0.95, 0.85, 0.2), r))  # 绿→金
				if _grid.crop_mature(c):
					draw_rect(crop_rect, Color(1, 1, 1, 0.9), false, 1.5)  # 成熟描边


func _tile_color(state: int) -> Color:
	match state:
		FarmGrid.State.TILLED:
			return Color(0.55, 0.35, 0.2)    # 已耕:棕
		FarmGrid.State.WATERED:
			return Color(0.35, 0.22, 0.12)   # 已浇:深棕
		_:
			return Color(0.35, 0.6, 0.25)    # 空地:草绿
