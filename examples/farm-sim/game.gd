extends Node
## 农场经营 MVP 骨架的驱动 —— 一条确定性剧情把子系统串起来做"框架消费者视角"的 dogfood。
## 整段只调 CoreKit.* 与 KitInventory/KitDataRegistry 两个 class_name 类库,不碰 kit 内部。
##
## 剧情:载数据表(crop+item+quest+achievement)→ 开店买种子(钱走 item 价、事件走 shop:)→
##       播种(从对象池借出)→ 逐日推进(clock→weather→crop 事件链驱动生长,雨天 +1)→
##       收获(归还池)→ 卖钱 → 存档往返(含金币/任务)→ 背包 UI 入栈 → 任务结算 →
##       对象池复用第二茬(两茬共用 2 个实例)→ 成就结算(账号级存 settings,非存档)。
##
## 跑法:把 game.tscn 设为主场景运行,或 headless:
##   godot --headless --path . res://examples/farm-sim/game.tscn --quit-after 120
## (首次需先 godot --headless --path . --import 生成 class_name 缓存。)

const FarmScript := preload("res://examples/farm-sim/farm.gd")
const ShopScript := preload("res://examples/farm-sim/shop.gd")
const QuestLogScript := preload("res://examples/farm-sim/quest_log.gd")
const BackpackPanelScript := preload("res://examples/farm-sim/backpack_panel.gd")
const WeatherSystemScript := preload("res://examples/farm-sim/weather_system.gd")
const AchievementTrackerScript := preload("res://examples/farm-sim/achievement_tracker.gd")

var _registry
var _bag
var _shop
var _quest_log
var _total_earned := 0   ## 由订阅 shop:sold 累计:演示游戏侧既发布又订阅自有命名空间事件


func _ready() -> void:
	# 1. 载数据表:crop + item + quest + achievement 四种类型同存一个 KitDataRegistry(多类型验证)
	_registry = KitDataRegistry.new()
	var n_crop = _registry.load_dir(&"crop", "res://examples/farm-sim/data/crops")
	var n_item = _registry.load_dir(&"item", "res://examples/farm-sim/data/items")
	var n_quest = _registry.load_dir(&"quest", "res://examples/farm-sim/data/quests")
	var n_ach = _registry.load_dir(&"achievement", "res://examples/farm-sim/data/achievements")
	CoreKit.log.info("[Farm] 载入 %d 作物 + %d 物品 + %d 任务 + %d 成就,registry 类型: [%s]" % [
		n_crop, n_item, n_quest, n_ach, _join(_registry.types(true))])   # types(true) = 字符串字典序(v0.18.0)

	# 1b. 任务日志:载入 quest 定义,订阅 clock:day_changed + shop:sold 追踪目标。
	#     dogfood:CoreKit.bus 作【多来源事件聚合器】;quest: 是游戏第 3 个自有命名空间。
	#     必须在时钟推进/卖出之前入树(其 _ready 里订阅,晚了会漏事件)。
	_quest_log = QuestLogScript.new()
	_quest_log.name = "QuestLog"
	_quest_log.bind(_registry)
	add_child(_quest_log)

	# 1c. 成就追踪器:载入 achievement 定义(registry 第 4 类型),聚合 shop:bought +
	#     quest:completed + weather:changed 三来源判定里程碑。dogfood 关键:成就是【账号级】,
	#     解锁写 CoreKit.settings("achievements" 分区)——不进存档槽、删档不丢(对照任务的
	#     每档进度)。achievement: 是游戏自有命名空间(与 shop:/quest:/weather: 并列)。
	#     必须在买/卖/天气事件之前入树(其 _ready 订阅这三个事件,晚了会漏)。
	var achievements := AchievementTrackerScript.new()
	achievements.name = "Achievements"
	achievements.bind(_registry)
	add_child(achievements)

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

	# 2c. 天气系统:订阅 clock:day_changed,每天掷晴/雨并广播 weather:changed(作物据此长)。
	#     dogfood:bus 事件链 clock→weather→crop;weather: 是游戏第 4 个自有命名空间。
	#     必须在 advance_day 之前入树(其 _ready 订阅 clock,晚了漏事件)。
	var weather := WeatherSystemScript.new()
	weather.name = "Weather"
	add_child(weather)

	# 3. 农田,注入 registry + bag。作物实例走对象池:先 register "crop" 池(prewarm 2 =
	#    预热 2 个空闲实例),之后 plant/harvest 借还复用,免反复 instantiate/free。
	CoreKit.pool.register("crop", preload("res://examples/farm-sim/crop.tscn"), 2)
	var farm := FarmScript.new()
	farm.name = "Farm"
	farm.bind(_registry, _bag)
	add_child(farm)

	# 4. 播种(消耗种子;从预热池借出,见 [Pool] 演示)
	farm.plant(&"turnip")
	farm.plant(&"parsnip")

	# 5. 时钟逐日推进 —— 每天 clock:day_changed 触发 Crop 生长(见输出的 [Crop:*] 行)
	CoreKit.log.info("[Clock] 开局 %s" % _date_str())
	for i in range(4):
		CoreKit.clock.advance_day()

	# 6. 收获成熟作物入背包(防风草 item 表 max_stack=1 → 2 株占 2 格,数据驱动堆叠)
	farm.harvest_all()
	# 池化注意点:pool.release() 用 call_deferred 摘父节点(躲物理回调重入),故归还的作物
	# 在本帧内仍挂树、仍订阅。本 demo 同步推进时钟,必须等一帧让延迟摘除落定、作物真正离树
	# 退订,后续 advance_day 才不会再喂到"已归还"的实例(否则它们会继续长)。
	await get_tree().process_frame

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
	# settings ≠ saves 边界演示:任务进度被清空了(每档状态),但成就解锁不受影响——它存
	# CoreKit.settings(账号级),既不进存档槽、也不被上面的 forget/复原动到。
	CoreKit.log.info("[Achieve] 存档清空了任务进度,但成就仍解锁 %d/%d(存 settings 非存档槽,不受删档影响)" % [
		achievements.unlocked_count(), achievements.total()])
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

	# 11. 对象池复用演示 —— dogfood CoreKit.pool:第一茬收获后 2 个实例已归还池;第二茬播种
	#     直接复用这两个空闲实例,total_count 始终为 2(而非新建到 4),证明"零新实例化"复用。
	CoreKit.log.info("[Pool] 第一茬收获后:空闲=%d 在用=%d 总实例=%d" % _pool_stat())
	farm.plant(&"turnip")     # 复用上一茬归还的实例(_pool_reset 已把生长清零、FSM 拨回 Growing)
	farm.plant(&"parsnip")
	CoreKit.log.info("[Pool] 第二茬播种后:空闲=%d 在用=%d 总实例=%d(复用未新建)" % _pool_stat())
	for i in range(4):
		CoreKit.clock.advance_day()
	farm.harvest_all()
	CoreKit.log.info("[Pool] 第二茬收获完,累计只 instantiate 过 %d 个 Crop(两茬共用)" % [
		CoreKit.pool.total_count("crop")])
	# 收尾:等一帧让最后一批 release 的延迟摘除落定,再 clear 释放池内空闲实例
	#(池持有的游离节点不在树上,退出时不被 SceneTree 回收,不清会报 resources still in use)。
	await get_tree().process_frame
	CoreKit.pool.clear("crop")

	# 12. 成就结算 —— 整局聚合 shop:/quest:/weather: 三来源解锁的账号级里程碑(存 settings)。
	CoreKit.log.info("[Achieve] 结算(%d/%d 解锁,账号级存 settings):" % [
		achievements.unlocked_count(), achievements.total()])
	for line in achievements.summary_lines():
		CoreKit.log.info("[Achieve]   %s" % line)
	achievements.reset_all()   # erase_section 清掉 settings 里的成就分区,保证示例可重复跑


## 订阅 shop:sold 累计总收入(游戏侧消费自有命名空间事件)。
func _on_sold(payload: Dictionary) -> void:
	_total_earned += int(payload.get("earn", 0))


## 对象池 "crop" 的记账三元组(空闲/在用/总数),供 [Pool] 演示行。
func _pool_stat() -> Array:
	return [CoreKit.pool.available_count("crop"), CoreKit.pool.in_use_count("crop"),
		CoreKit.pool.total_count("crop")]


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
