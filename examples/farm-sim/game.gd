extends Node
## 农场经营 MVP 骨架的驱动 —— 用一条确定性剧情把三个新子系统串起来验证:
##   1. KitDataRegistry.load_dir 从 data/*.tres 载入作物表;
##   2. KitInventory 当背包:发种子、播种扣种子、收获入库;
##   3. CoreKit.clock 逐日推进,每天经 CoreKit.bus 广播 clock:day_changed 驱动作物生长。
## 这是"框架消费者"视角的 dogfood:整段只调 CoreKit.* 与两个 class_name 类库,不碰 kit 内部。
##
## 跑法:把 game.tscn 设为主场景运行,或 headless:
##   godot --headless --path . res://examples/farm-sim/game.tscn --quit-after 120
## (首次需先 godot --headless --path . --import 生成 KitInventory/KitDataRegistry 类缓存。)

const FarmScript := preload("res://examples/farm-sim/farm.gd")

var _registry
var _bag


func _ready() -> void:
	# 1. 载作物表(KitDataRegistry.load_dir 扫 data/ 下的 .tres)
	_registry = KitDataRegistry.new()
	var n = _registry.load_dir(&"crop", "res://examples/farm-sim/data")
	var ids = _registry.ids(&"crop")
	ids.sort()
	var names := PackedStringArray()
	for id in ids:
		names.append(String(id))
	CoreKit.log.info("[Farm] 载入 %d 种作物: %s" % [n, ", ".join(names)])

	# 2. 背包(KitInventory)+ 发种子
	_bag = KitInventory.new(20)
	_bag.add(&"turnip_seed", 3)
	_bag.add(&"parsnip_seed", 3)
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

	# 6. 收获成熟作物,产物入背包
	farm.harvest_all()

	# 7. 结算
	CoreKit.log.info("[Bag] 最终库存: turnip=%d parsnip=%d turnip_seed=%d parsnip_seed=%d" % [
		_bag.count(&"turnip"), _bag.count(&"parsnip"),
		_bag.count(&"turnip_seed"), _bag.count(&"parsnip_seed")])
	CoreKit.log.info("[Clock] 结束 %s" % _date_str())


func _date_str() -> String:
	var c = CoreKit.clock
	return "y%d %s d%d %02d:%02d" % [c.year(), c.season_name(), c.day(), c.hour(), c.minute()]
