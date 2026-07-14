extends Node
## 农场经营 MVP 骨架的驱动 —— 一条确定性剧情把子系统串起来做"框架消费者视角"的 dogfood。
## 整段只调 CoreKit.* 与 KitInventory/KitDataRegistry 两个 class_name 类库,不碰 kit 内部。
##
## 剧情:载数据表(crop+item 两类型)→ 开店买种子(钱走 item 价、事件走 shop: 命名空间)→
##       播种 → 逐日推进(bus 驱动生长)→ 收获 → 卖产物换钱 → 存档往返(含金币)→ 背包 UI 入栈。
##
## 跑法:把 game.tscn 设为主场景运行,或 headless:
##   godot --headless --path . res://examples/farm-sim/game.tscn --quit-after 120
## (首次需先 godot --headless --path . --import 生成 class_name 缓存。)

const FarmScript := preload("res://examples/farm-sim/farm.gd")
const ShopScript := preload("res://examples/farm-sim/shop.gd")
const QuestLogScript := preload("res://examples/farm-sim/quest_log.gd")
const BackpackPanelScript := preload("res://examples/farm-sim/backpack_panel.gd")

var _registry
var _bag
var _shop
var _quest_log
var _total_earned := 0   ## 由订阅 shop:sold 累计:演示游戏侧既发布又订阅自有命名空间事件


func _ready() -> void:
	# 1. 载数据表:crop + item 两种类型同存一个 KitDataRegistry(多类型验证)
	_registry = KitDataRegistry.new()
	var n_crop = _registry.load_dir(&"crop", "res://examples/farm-sim/data/crops")
	var n_item = _registry.load_dir(&"item", "res://examples/farm-sim/data/items")
	var n_quest = _registry.load_dir(&"quest", "res://examples/farm-sim/data/quests")
	CoreKit.log.info("[Farm] 载入 %d 作物 + %d 物品 + %d 任务,registry 类型: [%s]" % [
		n_crop, n_item, n_quest, _join(_registry.types(true))])   # types(true) = 字符串字典序(v0.18.0)

	# 1b. 任务日志:载入 quest 定义,订阅 clock:day_changed + shop:sold 追踪目标。
	#     dogfood:CoreKit.bus 作【多来源事件聚合器】;quest: 是游戏第 3 个自有命名空间。
	#     必须在时钟推进/卖出之前入树(其 _ready 里订阅,晚了会漏事件)。
	_quest_log = QuestLogScript.new()
	_quest_log.name = "QuestLog"
	_quest_log.bind(_registry)
	add_child(_quest_log)

	# 2. 背包 + 商店(起始金币 200)+ 买种子。价格走 item 表,交易广播 shop: 命名空间事件。
	#    并订阅自家 shop:sold 累计总收入 —— 游戏侧既发布又消费自有命名空间事件,验证约定通用。
	_bag = KitInventory.new(20)
	_shop = ShopScript.new()
	_shop.name = "Shop"
	_shop.bind(_registry, _bag, 200)
	add_child(_shop)
	CoreKit.bus.subscribe(_shop.EV_SOLD, _on_sold)
	CoreKit.log.info("[Shop] 开局金币 %d" % _shop.gold)
	for crop_id in _registry.ids(&"crop", true):   # ids(type, true) = 字母序(v0.18.0,免手写 sort_custom)
		_shop.buy(_registry.get_def(&"crop", crop_id).seed_item, 3)

	# 3. 农田,注入 registry + bag
	var farm := FarmScript.new()
	farm.name = "Farm"
	farm.bind(_registry, _bag)
	add_child(farm)

	# 4. 播种(消耗种子)
	farm.plant(&"turnip")
	farm.plant(&"parsnip")

	# 5. 时钟逐日推进 —— 每天 clock:day_changed 触发 Crop 生长(见输出的 [Crop:*] 行)
	CoreKit.log.info("[Clock] 开局 %s" % _date_str())
	for i in range(4):
		CoreKit.clock.advance_day()

	# 6. 收获成熟作物入背包(防风草 item 表 max_stack=1 → 2 株占 2 格,数据驱动堆叠)
	farm.harvest_all()

	# 7. 卖掉白萝卜换钱(留着防风草给背包 UI 看);sell_price 走 item 表,shop:sold 触发收入累计
	_shop.sell(&"turnip", _bag.count(&"turnip"))
	CoreKit.log.info("[Shop] 结算:金币 %d,累计收入 %d" % [_shop.gold, _total_earned])

	# 8. 存档往返 —— clock+bag+金币 存进 CoreKit.saves,读回 from_dict 复原。
	#    验证第 4 个子系统 saves 接入,以及 to_dict/from_dict 扛得住 JSON int→float 往返。
	var slot := "farm_demo"
	CoreKit.saves.save(slot, {
		"clock": CoreKit.clock.to_dict(), "bag": _bag.to_dict(),
		"gold": _shop.gold, "quests": _quest_log.to_dict()})
	CoreKit.log.info("[Save] 已存档 '%s' @ %s gold=%d 完成任务=%d" % [
		slot, _date_str(), _shop.gold, _quest_log.done_count()])
	# 存档后继续游戏(推进 5 天 + 清空钱包 + 遗忘任务),制造与存档点的差异
	for i in range(5):
		CoreKit.clock.advance_day()
	_shop.gold = 0
	_quest_log.forget_all()
	CoreKit.log.info("[Save] 读档前(已变化): %s gold=%d 完成任务=%d" % [
		_date_str(), _shop.gold, _quest_log.done_count()])
	# 读回存档:from_dict 把时钟/背包/任务复原,金币手动读回(游戏侧状态)
	var snap = CoreKit.saves.load(slot)
	CoreKit.clock.from_dict(snap["clock"])
	_bag.from_dict(snap["bag"])
	_shop.gold = int(snap["gold"])
	_quest_log.from_dict(snap["quests"])
	CoreKit.log.info("[Save] 读档后(已复原): %s gold=%d 完成任务=%d" % [
		_date_str(), _shop.gold, _quest_log.done_count()])
	CoreKit.saves.delete_slot(slot)   # 清掉存档槽,保证示例可重复跑

	# 9. 背包 UI 面板入栈 —— dogfood KitUiStack:push 一个反映背包内容的 Control 面板。
	var stack := KitUiStack.new()
	stack.name = "UiStack"
	add_child(stack)
	var panel = BackpackPanelScript.new()
	panel.setup(_bag, _registry)
	stack.push(panel)
	CoreKit.log.info("[UI] 背包面板入栈,depth=%d" % stack.depth())
	for line in panel.lines():
		CoreKit.log.info("[UI]   %s" % line)

	# 10. 任务结算概览(进度由 clock:/shop: 事件在整局中聚合而来)
	CoreKit.log.info("[Quest] 结算(%d/%d 完成):" % [_quest_log.done_count(), _quest_log.quest_count()])
	for line in _quest_log.summary_lines():
		CoreKit.log.info("[Quest]   %s" % line)


## 订阅 shop:sold 累计总收入(游戏侧消费自有命名空间事件)。
func _on_sold(payload: Dictionary) -> void:
	_total_earned += int(payload.get("earn", 0))


func _date_str() -> String:
	var c = CoreKit.clock
	return "y%d %s d%d %02d:%02d" % [c.year(), c.season_name(), c.day(), c.hour(), c.minute()]


## 把(StringName)数组拼成干净的 "a, b, c"(避免 str() 打出 &"...")。
## 排序交给上游 registry.ids/types(sorted=true)(v0.18.0),这里只做 String 转换。
func _join(a) -> String:
	var parts := PackedStringArray()
	for x in a:
		parts.append(String(x))
	return ", ".join(parts)
