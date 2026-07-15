extends Node2D
## 农田区域场景(P3:多区域中的 farm 区)。持久状态全在 `Farm` autoload;本场景只做**表现 + 输入派发**:
## 建农田渲染 + 玩家 + 高亮 + 天气视觉,把按键转成 Farm 的玩法动作。切到农舍/小镇时本场景被整替换,
## 农田状态留在 Farm 不丢(见 farm_state.gd)。P2 之前是单场景全包,P3 Task1 把 model 上移到 Farm。
##
## 操作:WASD 走动;J 用工具(耕→种→浇→收,可升级 3×3);N 睡觉;Q 切种子;
##   I 背包 / P 商店 / L 任务成就 / Esc 菜单(存读档/设置)。

const FarmGridView = preload("res://examples/farm-sim/farm_grid_view.gd")
const PlayerScript = preload("res://examples/farm-sim/player.gd")
const TargetHighlight = preload("res://examples/farm-sim/target_highlight.gd")
const WeatherView = preload("res://examples/farm-sim/weather_view.gd")

var _view
var _player


func _ready() -> void:
	Farm.start()                       # 幂等:首次进农田才建全部持久状态
	Farm.current_area = "farm"

	# 农田渲染:绑 Farm.grid;grid 变更(耕种浇收/生长/读档)经信号重绘
	_view = FarmGridView.new()
	_view.bind(Farm.grid)
	add_child(_view)
	Farm.grid_changed.connect(_view.queue_redraw)

	# 玩家(出生点:切区来的用 pending_spawn,否则网格中央)+ 面前格高亮
	_player = PlayerScript.new()
	_player.setup(Farm.grid)
	if Farm.pending_spawn != Vector2.ZERO:
		_player.position = Farm.pending_spawn
		Farm.pending_spawn = Vector2.ZERO
	else:
		_player.position = Farm.grid.cell_to_world(Vector2i(Farm.GRID_W / 2, Farm.GRID_H / 2)) + Vector2(16, 16)
	add_child(_player)
	Farm.bind_player(_player)
	var hl = TargetHighlight.new()
	hl.bind(_player, Farm.grid)
	add_child(hl)

	# 雨天视觉覆盖(仅农田):挂 layer=1 CanvasLayer(农田之上、HUD 之下)
	var weather_layer := CanvasLayer.new()
	weather_layer.layer = 1
	add_child(weather_layer)
	var weather_view = WeatherView.new()
	weather_view.bind(Farm.weather)
	weather_layer.add_child(weather_view)

	CoreKit.log.info("[World] 农田就绪:WASD 走动,J 用工具,N 睡觉")
	if OS.get_environment("FARM_SMOKE") == "1":
		Farm.call_deferred("run_smoke")   # headless 端到端自测(env 门控)


func _unhandled_input(event: InputEvent) -> void:
	# 面板开关(任何时候可用)
	if event.is_action_pressed("toggle_inventory"):
		Farm.toggle_ui("inventory"); return
	if event.is_action_pressed("toggle_shop"):
		Farm.toggle_ui("shop"); return
	if event.is_action_pressed("toggle_menu"):
		Farm.toggle_ui("menu"); return
	if event.is_action_pressed("toggle_log"):
		Farm.toggle_ui("log"); return
	# 面板开着:导航/确认 路由给活动面板,其余吞掉
	if Farm.is_ui_open():
		for a in ["move_up", "move_down", "farm_use"]:
			if event.is_action_pressed(a):
				Farm.route_action(a); return
		return
	# 无面板:农田操作
	if event.is_action_pressed("farm_use"):
		Farm.use_tool_on(_player.facing_cell())
	elif event.is_action_pressed("farm_next_day"):
		Farm.sleep()
	elif event.is_action_pressed("cycle_seed"):
		Farm.cycle_seed()
