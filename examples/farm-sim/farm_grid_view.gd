extends Node2D
## 农田占位渲染(薄 renderer):只读 FarmGrid 逐格画瓦片贴图 + 作物贴图(按生长比例缩放 + 绿→金着色)。
## 逻辑全在 FarmGrid,这里零逻辑。贴图经 ArtBank 接缝取(程序化默认,真素材可换入)——P5 从 draw_rect
## 升级到 draw_texture_rect;P5 后期转 TileMapLayer/真 tileset 时本文件整体替换,不动模型。

const FarmGrid = preload("res://examples/farm-sim/farm_grid.gd")
const ArtBank = preload("res://examples/farm-sim/art_bank.gd")

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
			draw_texture_rect(ArtBank.tex(_tile_key(_grid.tile_state(c))), rect, false)
			if _grid.has_crop(c):
				var r: float = _grid.crop_ratio(c)
				var side: float = cell * lerpf(0.35, 0.85, r)    # 刚种下小苗,越熟越大
				var off: float = (cell - side) * 0.5             # 居中
				var crop_rect := Rect2(origin + Vector2(off, off), Vector2(side, side))
				var tint := Color(0.3, 0.8, 0.3).lerp(Color(0.95, 0.85, 0.2), r)   # 绿→金
				draw_texture_rect(ArtBank.tex(&"crop"), crop_rect, false, tint)
				if _grid.crop_mature(c):
					draw_rect(crop_rect, Color(1, 1, 1, 0.9), false, 1.5)          # 成熟描边


func _tile_key(state: int) -> StringName:
	match state:
		FarmGrid.State.TILLED:
			return &"tile_tilled"
		FarmGrid.State.WATERED:
			return &"tile_watered"
		_:
			return &"tile_grass"
