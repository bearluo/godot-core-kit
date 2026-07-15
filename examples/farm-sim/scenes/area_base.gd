extends Node2D
## 区域基类(P3 多区域)。三个区域场景(农田/农舍/小镇)共享:调 Farm.start()、生成玩家(切区来的
## 落 Farm.pending_spawn,否则本区默认出生点)、面板开关与路由、睡觉/换种子等全局键、区域切换。
## 持久状态全在 Farm autoload,本类只管**表现 + 输入派发**;切区时本场景整替换,Farm 状态不丢。
##
## 子类覆盖点:
##   _area_name()      本区名(farm/house/town),写入 Farm.current_area
##   _default_spawn()  非切区进入(直接开场/读档同区)时玩家出生点
##   _build_area()     玩家生成前建本区布景/门/网格 view/NPC
##   _after_player()   依赖玩家的东西(如面前格高亮)
##   _on_use()         farm_use(J):农田=用工具,小镇/农舍=交互身边物件/NPC

const PlayerScript = preload("res://examples/farm-sim/scenes/player.gd")
const NpcScript = preload("res://examples/farm-sim/scenes/npc.gd")

var _player
var _npcs: Array = []   ## 本区当前在场 NPC 节点(供交互找最近者,P4)


# --- 子类覆盖点(默认空实现)---
func _area_name() -> String:
	return "area"


func _default_spawn() -> Vector2:
	return Vector2(96, 96)


func _build_area() -> void:
	pass


func _after_player() -> void:
	pass


func _on_use() -> void:
	pass


## 与玩家相邻(≤ ~1.5 格)的最近 NPC;无则 null。供小镇/农舍 _on_use 优先交互 NPC。
func _nearest_npc():
	if _player == null or _npcs.is_empty():
		return null
	var best = null
	var best_d := 48.0
	for npc in _npcs:
		var d = _player.global_position.distance_to(npc.position)
		if d <= best_d:
			best_d = d
			best = npc
	return best


## 按 Farm 日程实例化本区此刻在场的 NPC(cell*32 居中摆放)。
func _spawn_area_npcs() -> void:
	_npcs = []
	for e in Farm.npcs_in_area(_area_name(), CoreKit.clock.hour()):
		var npc = NpcScript.new()
		npc.setup(e.def, e.cell)
		npc.position = Vector2(e.cell) * 32.0 + Vector2(16, 16)
		add_child(npc)
		_npcs.append(npc)


func _ready() -> void:
	Farm.start()                       # 幂等:首次进农田才建全部持久状态
	Farm.current_area = _area_name()
	_build_area()
	_spawn_area_npcs()                 # 按日程摆放本区此刻在场的 NPC(farm 区通常无 → 空)
	# 玩家:切区来的用 pending_spawn,否则本区默认出生点
	_player = PlayerScript.new()
	_player.setup(Farm.grid)
	if Farm.pending_spawn != Vector2.ZERO:
		_player.position = Farm.pending_spawn
		Farm.pending_spawn = Vector2.ZERO
	else:
		_player.position = _default_spawn()
	if Farm.pending_facing != Vector2i.ZERO:
		_player.facing = Farm.pending_facing
		Farm.pending_facing = Vector2i.ZERO
	add_child(_player)
	Farm.bind_player(_player)
	_after_player()
	if _area_name() == "farm" and OS.get_environment("FARM_SMOKE") == "1":
		Farm.call_deferred("run_smoke")   # headless 端到端自测只从农田触发


func _unhandled_input(event: InputEvent) -> void:
	# 面板开关(任何区、任何时候可用)
	if event.is_action_pressed("toggle_inventory"):
		Farm.toggle_ui("inventory"); return
	if event.is_action_pressed("toggle_shop"):
		Farm.toggle_ui("shop"); return
	if event.is_action_pressed("toggle_menu"):
		Farm.toggle_ui("menu"); return
	if event.is_action_pressed("toggle_log"):
		Farm.toggle_ui("log"); return
	# 面板开着:导航/确认路由给活动面板,其余吞掉
	if Farm.is_ui_open():
		for a in ["move_up", "move_down", "farm_use"]:
			if event.is_action_pressed(a):
				Farm.route_action(a); return
		return
	# 无面板:J=区域交互(子类),N=睡觉,Q=切种子(走动由 player._physics_process 处理)
	if event.is_action_pressed("farm_use"):
		_on_use()
	elif event.is_action_pressed("farm_next_day"):
		Farm.sleep()
	elif event.is_action_pressed("cycle_seed"):
		Farm.cycle_seed()
