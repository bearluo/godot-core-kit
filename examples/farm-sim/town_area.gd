extends "res://examples/farm-sim/area_base.gd"
## 小镇区域(P3 多区域,继承 area_base)。占位:地面 + 商店牌子(走到牌子边按 J → 开商店面板)+
## 回农田的门(SLIDE 向上)。NPC 在 Task3 加入。farm_use(J)= 与身边物件/NPC 交互。

const DoorScript = preload("res://examples/farm-sim/door.gd")

const GROUND_SIZE := Vector2(384, 256)
const SHOP_POS := Vector2(296, 56)
const SHOP_SIZE := Vector2(72, 56)


func _area_name() -> String:
	return "town"


func _default_spawn() -> Vector2:
	return Vector2(96, 128)


func _build_area() -> void:
	queue_redraw()   # 画地面 + 商店牌
	var to_farm := DoorScript.new()
	to_farm.position = Vector2(24, 128)
	to_farm.setup(Farm.AREA_FARM, Farm.FARM_FROM_TOWN, Farm.slide(KitTransition.Dir.UP), "↑ 农田", Color(0.4, 0.6, 0.35))
	add_child(to_farm)
	CoreKit.log.info("[Town] 小镇:走到商店牌子按 J 开商店,左侧门回农田")


func _on_use() -> void:
	# 靠近商店牌 → 开商店面板
	if _player != null and _player.global_position.distance_to(SHOP_POS + SHOP_SIZE * 0.5) < 60.0:
		Farm.toggle_ui("shop")
	else:
		CoreKit.log.info("[Town] 这里没什么可交互")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, GROUND_SIZE), Color(0.5, 0.5, 0.45))               # 地面
	draw_rect(Rect2(Vector2.ZERO, GROUND_SIZE), Color(0, 0, 0, 0.2), false, 2.0)
	draw_rect(Rect2(SHOP_POS, SHOP_SIZE), Color(0.72, 0.6, 0.3))                     # 商店牌
	draw_rect(Rect2(SHOP_POS, SHOP_SIZE), Color(1, 1, 1, 0.5), false, 2.0)
	var lbl := Vector2(SHOP_POS.x + 10, SHOP_POS.y + SHOP_SIZE.y + 14)
	draw_string(ThemeDB.fallback_font, lbl, "商店", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
