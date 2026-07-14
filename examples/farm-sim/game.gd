extends Node
## 农场经营 MVP 骨架的驱动 —— 用一条确定性剧情把子系统串起来做"框架消费者视角"的 dogfood。
## 整段只调 CoreKit.* 与 KitInventory/KitDataRegistry 两个 class_name 类库,不碰 kit 内部。
##
## 剧情:载数据表(crop + item 两类型)→ 发种子(上限走数据表)→ 播种 → 逐日推进(bus 驱动
##       作物生长)→ 收获(单格上限数据驱动)→ 结算。
##
## 跑法:把 game.tscn 设为主场景运行,或 headless:
##   godot --headless --path . res://examples/farm-sim/game.tscn --quit-after 120
## (首次需先 godot --headless --path . --import 生成 KitInventory/KitDataRegistry 类缓存。)

const FarmScript := preload("res://examples/farm-sim/farm.gd")

var _registry
var _bag


func _ready() -> void:
	# 1. 载数据表:crop + item 两种类型同存一个 KitDataRegistry(多类型验证)
	_registry = KitDataRegistry.new()
	var n_crop = _registry.load_dir(&"crop", "res://examples/farm-sim/data/crops")
	var n_item = _registry.load_dir(&"item", "res://examples/farm-sim/data/items")
	CoreKit.log.info("[Farm] 载入 %d 作物 + %d 物品,registry 类型: [%s]" % [
		n_crop, n_item, _join(_registry.types())])

	# 2. 背包 + 发种子(数量走参数,单格上限走 item 表,不再硬编码)
	_bag = KitInventory.new(20)
	for crop_id in _sorted(_registry.ids(&"crop")):
		var cdef = _registry.get_def(&"crop", crop_id)
		var sdef = _registry.get_def(&"item", cdef.seed_item)
		_bag.add(cdef.seed_item, 3, {}, sdef.max_stack)
	CoreKit.log.info("[Bag] 初始种子: turnip_seed=%d parsnip_seed=%d" % [
		_bag.count(&"turnip_seed"), _bag.count(&"parsnip_seed")])

	# 3. 农田,注入 registry + bag
	var farm := FarmScript.new()
	farm.name = "Farm"
	farm.bind(_registry, _bag)
	add_child(farm)

	# 4. 播种(消耗种子)
	farm.plant(&"turnip")
	farm.plant(&"parsnip")
	CoreKit.log.info("[Bag] 播种后种子: turnip_seed=%d parsnip_seed=%d" % [
		_bag.count(&"turnip_seed"), _bag.count(&"parsnip_seed")])

	# 5. 时钟逐日推进 —— 每天 clock:day_changed 触发 Crop 生长(见输出的 [Crop:*] 行)
	CoreKit.log.info("[Clock] 开局 %s" % _date_str())
	for i in range(4):
		CoreKit.clock.advance_day()

	# 6. 收获成熟作物入背包(防风草 item 表 max_stack=1 → 2 株产物占 2 格,数据驱动堆叠)
	farm.harvest_all()
	CoreKit.log.info("[Bag] 收获后: turnip=%d parsnip=%d,已用格数=%d" % [
		_bag.count(&"turnip"), _bag.count(&"parsnip"), _bag.used_slots()])
	CoreKit.log.info("[Clock] 结束 %s" % _date_str())


func _date_str() -> String:
	var c = CoreKit.clock
	return "y%d %s d%d %02d:%02d" % [c.year(), c.season_name(), c.day(), c.hour(), c.minute()]


## 排序副本(不改原数组)。
func _sorted(a) -> Array:
	var c := Array(a)
	c.sort()
	return c


## 把(StringName)数组排序后拼成干净的 "a, b, c"(避免 str() 打出 &"...")。
func _join(a) -> String:
	var parts := PackedStringArray()
	for x in _sorted(a):
		parts.append(String(x))
	return ", ".join(parts)
