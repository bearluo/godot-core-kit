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
const BackpackPanelScript := preload("res://examples/farm-sim/backpack_panel.gd")

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

	# 7. 存档往返 —— clock.to_dict + bag.to_dict 存进 CoreKit.saves,读回 from_dict 复原。
	#    验证第 4 个子系统 saves 接入,以及 to_dict/from_dict 扛得住 JSON int→float 往返。
	var slot := "farm_demo"
	CoreKit.saves.save(slot, {"clock": CoreKit.clock.to_dict(), "bag": _bag.to_dict()})
	CoreKit.log.info("[Save] 已存档 '%s' @ %s turnip=%d" % [slot, _date_str(), _bag.count(&"turnip")])
	# 存档后继续游戏(推进 5 天 + 凭空吃进 10 白萝卜),制造与存档点的差异
	for i in range(5):
		CoreKit.clock.advance_day()
	_bag.add(&"turnip", 10)
	CoreKit.log.info("[Save] 读档前(已变化): %s turnip=%d" % [_date_str(), _bag.count(&"turnip")])
	# 读回存档:from_dict 把时钟与背包一并复原到存档点
	var snap = CoreKit.saves.load(slot)
	CoreKit.clock.from_dict(snap["clock"])
	_bag.from_dict(snap["bag"])
	CoreKit.log.info("[Save] 读档后(已复原): %s turnip=%d" % [_date_str(), _bag.count(&"turnip")])
	CoreKit.saves.delete_slot(slot)   # 清掉存档槽,保证示例可重复跑

	# 8. 背包 UI 面板入栈 —— dogfood KitUiStack:push 一个反映背包内容的 Control 面板。
	var stack := KitUiStack.new()
	stack.name = "UiStack"
	add_child(stack)
	var panel = BackpackPanelScript.new()
	panel.setup(_bag, _registry)
	stack.push(panel)
	CoreKit.log.info("[UI] 背包面板入栈,depth=%d" % stack.depth())
	for line in panel.lines():
		CoreKit.log.info("[UI]   %s" % line)


func _date_str() -> String:
	var c = CoreKit.clock
	return "y%d %s d%d %02d:%02d" % [c.year(), c.season_name(), c.day(), c.hour(), c.minute()]


## 按字符串字典序排的副本(不改原数组)。注意:StringName 数组的原生 .sort() 是按
## 指针地址排、非字典序(Godot 的坑),故这里用 String(x) 比较拿到稳定的字母序。
func _sorted(a) -> Array:
	var c := Array(a)
	c.sort_custom(func(x, y): return String(x) < String(y))
	return c


## 把(StringName)数组排序后拼成干净的 "a, b, c"(避免 str() 打出 &"...")。
func _join(a) -> String:
	var parts := PackedStringArray()
	for x in _sorted(a):
		parts.append(String(x))
	return ", ".join(parts)
