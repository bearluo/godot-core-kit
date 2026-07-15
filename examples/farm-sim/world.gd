extends "res://examples/farm-sim/area_base.gd"
## 农田区域场景(P3 多区域的 farm 区,继承 area_base)。持久状态全在 Farm autoload;本场景建农田网格
## 渲染 + 面前格高亮 + 天气视觉 + 通往农舍/小镇的门,farm_use(J)=用工具。切到别区时本场景整替换,
## 农田状态(已种作物/浇水/生长)留在 Farm 不丢。
## P5 手感:美术全走 ArtBank 贴图;玩法动作成功经 Farm.fx_requested → Fx.burst 爆粒子 + 目标格顿挫;门转场带缓动。
##
## 操作:WASD 走动;J 用工具(耕→种→浇→收,可升级 3×3);N 睡觉;Q 切种子;
##   走进右侧门→农舍(FADE)、下方门→小镇(SLIDE);I 背包 / P 商店 / L 任务成就 / Esc 菜单(存读档/设置)。

const FarmGridView = preload("res://examples/farm-sim/farm_grid_view.gd")
const TargetHighlight = preload("res://examples/farm-sim/target_highlight.gd")
const WeatherView = preload("res://examples/farm-sim/weather_view.gd")
const DoorScript = preload("res://examples/farm-sim/door.gd")
const Fx = preload("res://examples/farm-sim/fx.gd")

var _view
var _highlight


func _area_name() -> String:
	return "farm"


func _default_spawn() -> Vector2:
	return Farm.grid.cell_to_world(Vector2i(Farm.GRID_W / 2, Farm.GRID_H / 2)) + Vector2(16, 16)


func _build_area() -> void:
	# 农田渲染:绑 Farm.grid;grid 变更(耕种浇收/生长/读档)经信号重绘
	_view = FarmGridView.new()
	_view.bind(Farm.grid)
	add_child(_view)
	Farm.grid_changed.connect(_view.queue_redraw)

	# 雨天视觉覆盖(仅农田):挂 layer=1 CanvasLayer(农田之上、HUD 之下)
	var weather_layer := CanvasLayer.new()
	weather_layer.layer = 1
	add_child(weather_layer)
	var weather_view = WeatherView.new()
	weather_view.bind(Farm.weather)
	weather_layer.add_child(weather_view)

	# 通往农舍(网格右侧,FADE)与小镇(网格下方,SLIDE 向下)的门
	var to_house := DoorScript.new()
	to_house.position = Vector2(Farm.GRID_W * 32 + 40, 60)
	to_house.setup(Farm.AREA_HOUSE, Farm.HOUSE_ENTRY, Farm.fade(), "农舍 →", Color(0.5, 0.35, 0.6))
	add_child(to_house)
	var to_town := DoorScript.new()
	to_town.position = Vector2(140, Farm.GRID_H * 32 + 40)
	to_town.setup(Farm.AREA_TOWN, Farm.TOWN_ENTRY, Farm.slide(KitTransition.Dir.DOWN), "小镇 ↓", Color(0.3, 0.5, 0.6))
	add_child(to_town)

	# 玩法动作粒子:model 成功动作(耕/种/浇/收)→ 本区爆粒子 + 目标格顿挫
	Farm.fx_requested.connect(_on_fx_requested)

	CoreKit.log.info("[World] 农田就绪:WASD 走动,J 用工具,N 睡觉,走进门→农舍/小镇")


func _after_player() -> void:
	_highlight = TargetHighlight.new()
	_highlight.bind(_player, Farm.grid)
	add_child(_highlight)


func _on_use() -> void:
	Farm.use_tool_on(_player.facing_cell())


## 玩法动作成功 → 该格中心爆一簇粒子 + 高亮框"顿一下"。
func _on_fx_requested(kind, cell) -> void:
	Fx.burst(self, Farm.grid.cell_to_world(cell) + Vector2(16, 16), kind)
	if _highlight != null:
		_highlight.punch(cell)
