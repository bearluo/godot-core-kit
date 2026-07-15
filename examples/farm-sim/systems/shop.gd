extends Node
## 农场经济:商店 + 钱包(游戏侧,kit 无货币子系统)。卖产物换钱、花钱买种子,
## 价格取自 item 表(buy_price/sell_price,数据驱动)。交易成功经 CoreKit.bus 广播
## 游戏自定义命名空间事件 shop:bought / shop:sold ——演示 bus 命名约定 namespace:event
## 在【游戏侧作为发布方】同样适用(约定见 docs/core/event-bus.md;shop 是游戏自有命名空间)。

const EV_BOUGHT := "shop:bought"   ## payload {item, qty, cost, gold}
const EV_SOLD := "shop:sold"       ## payload {item, qty, earn, gold}

var _registry   ## KitDataRegistry(读 item.buy_price/sell_price)
var _bag        ## KitInventory
var gold := 0   ## 钱包余额(游戏侧状态,随存档 to_dict/from_dict 一起走)


## 注入依赖 + 起始金币(驱动方在 add_child 前调用)。
func bind(registry, bag, starting_gold: int) -> void:
	_registry = registry
	_bag = bag
	gold = starting_gold


## 买 qty 个 item:有可购定义且钱够 → 扣钱入包、广播 shop:bought。返回是否成功。
func buy(item_id: StringName, qty: int) -> bool:
	var idef = _registry.get_def_or(&"item", item_id, null)
	if idef == null or idef.buy_price <= 0:
		CoreKit.log.warn("[Shop] %s 不可购买" % item_id)
		return false
	var cost = idef.buy_price * qty
	if gold < cost:
		CoreKit.log.warn("[Shop] 金币不足,买 %s x%d 需 %d,现有 %d" % [item_id, qty, cost, gold])
		return false
	gold -= cost
	_bag.add(item_id, qty, {}, idef.max_stack)
	CoreKit.bus.publish(EV_BOUGHT, {"item": item_id, "qty": qty, "cost": cost, "gold": gold})
	CoreKit.log.info("[Shop] 买入 %s x%d 花 %d,余额 %d" % [idef.display_name, qty, cost, gold])
	return true


## 卖 qty 个 item:有可售定义且库存够 → 扣物入账、广播 shop:sold。返回是否成功。
func sell(item_id: StringName, qty: int) -> bool:
	var idef = _registry.get_def_or(&"item", item_id, null)
	if idef == null or idef.sell_price <= 0:
		CoreKit.log.warn("[Shop] %s 不可出售" % item_id)
		return false
	if _bag.count(item_id) < qty:
		CoreKit.log.warn("[Shop] 库存不足,卖 %s x%d,现有 %d" % [item_id, qty, _bag.count(item_id)])
		return false
	_bag.remove(item_id, qty)
	var earn = idef.sell_price * qty
	gold += earn
	CoreKit.bus.publish(EV_SOLD, {"item": item_id, "qty": qty, "earn": earn, "gold": gold})
	CoreKit.log.info("[Shop] 卖出 %s x%d 得 %d,余额 %d" % [idef.display_name, qty, earn, gold])
	return true
