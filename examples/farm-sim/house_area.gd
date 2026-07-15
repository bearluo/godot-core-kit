extends "res://examples/farm-sim/area_base.gd"
## 农舍区域(P3 多区域,继承 area_base)。占位室内:地板 + 一张床(走到床边按 J → 睡觉推进天+回体力)+
## 回农田的门(FADE)。无农田网格;farm_use(J)= 与身边物件交互。

const DoorScript = preload("res://examples/farm-sim/door.gd")

const FLOOR_SIZE := Vector2(256, 192)
const BED_POS := Vector2(200, 56)
const BED_SIZE := Vector2(48, 64)


func _area_name() -> String:
	return "house"


func _default_spawn() -> Vector2:
	return Vector2(96, 96)


func _build_area() -> void:
	queue_redraw()   # 画地板 + 床
	var to_farm := DoorScript.new()
	to_farm.position = Vector2(24, 96)
	to_farm.setup(Farm.AREA_FARM, Farm.FARM_FROM_HOUSE, Farm.fade(), "← 农田", Color(0.4, 0.6, 0.35))
	add_child(to_farm)
	CoreKit.log.info("[House] 农舍:走到床边按 J 睡觉,左侧门回农田")


func _on_use() -> void:
	# 靠近床 → 睡觉(推进一天 + 回体力)
	if _player != null and _player.global_position.distance_to(BED_POS + BED_SIZE * 0.5) < 52.0:
		Farm.sleep()
	else:
		CoreKit.log.info("[House] 这里没什么可交互")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, FLOOR_SIZE), Color(0.32, 0.26, 0.22))              # 地板
	draw_rect(Rect2(Vector2.ZERO, FLOOR_SIZE), Color(0, 0, 0, 0.25), false, 2.0)
	draw_rect(Rect2(BED_POS, BED_SIZE), Color(0.7, 0.4, 0.4))                        # 床
	draw_rect(Rect2(BED_POS, BED_SIZE), Color(1, 1, 1, 0.5), false, 2.0)
