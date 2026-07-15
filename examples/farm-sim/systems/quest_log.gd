extends Node
## 任务日志:数据驱动的目标追踪器。从 registry("quest" 类型)载入任务定义,订阅游戏事件
## (clock:day_changed + shop:sold)推进进度,达标即完成并广播 quest:completed。
## dogfood 点:
## - CoreKit.bus 作【多来源事件聚合器】—— 一个订阅方汇聚多个命名空间(clock: + shop:)的事件;
## - quest: 是游戏第 3 个自有命名空间(与 clock:/shop: 并存);
## - 任务进度纳入存档 to_dict/from_dict(注意 StringName 键经 JSON 会退化为 String,from_dict 须归一)。

const EV_COMPLETED := "quest:completed"   ## payload {id, title}

var _registry
var _quests: Array = []          ## quest def 列表(按 id 排序,保证判定/输出确定性)
var _progress: Dictionary = {}   ## id(StringName) -> 当前进度值(int)
var _done: Dictionary = {}       ## id(StringName) -> true(已完成集合)


## 注入 registry(驱动方在 add_child 前调用)。
func bind(registry) -> void:
	_registry = registry


func _ready() -> void:
	for qid in _registry.ids(&"quest", true):   # ids(type, true) = 字母序(v0.18.0,免手写 sort_custom)
		_quests.append(_registry.get_def(&"quest", qid))
		_progress[qid] = 0
	CoreKit.bus.subscribe(CoreKit.clock.EV_DAY_CHANGED, _on_day)
	CoreKit.bus.subscribe("shop:sold", _on_sold)   # 游戏自有命名空间(见 shop.gd 的 EV_SOLD)


func _exit_tree() -> void:
	CoreKit.bus.unsubscribe_all(self)


## clock:day_changed —— 推进 reach_day 类任务(进度=当前天,直接取值不累加)。
func _on_day(snap: Dictionary) -> void:
	var day := int(snap.get("day", 0))
	for q in _quests:
		if q.kind == &"reach_day":
			_bump(q, day, true)


## shop:sold —— 推进 earn_gold(累加收入)与 sell_count(累加卖出数,可限定物品)。
func _on_sold(payload: Dictionary) -> void:
	var earn := int(payload.get("earn", 0))
	var sold_item = payload.get("item", &"")
	var qty := int(payload.get("qty", 0))
	for q in _quests:
		if q.kind == &"earn_gold":
			_bump(q, earn, false)
		elif q.kind == &"sell_count" and (q.item == &"" or q.item == sold_item):
			_bump(q, qty, false)


## 推进某任务进度:absolute=true 直接设值(reach_day),否则累加。达标 → 完成 + 广播 quest:completed。
func _bump(q, amount: int, absolute: bool) -> void:
	if _done.has(q.id):
		return
	_progress[q.id] = amount if absolute else int(_progress[q.id]) + amount
	if _progress[q.id] >= q.target:
		_done[q.id] = true
		CoreKit.bus.publish(EV_COMPLETED, {"id": q.id, "title": q.title})
		CoreKit.log.info("[Quest] 完成:%s" % q.title)


func is_done(qid: StringName) -> bool:
	return _done.has(qid)


func done_count() -> int:
	return _done.size()


func quest_count() -> int:
	return _quests.size()


## 完成度概览行(供结算日志),按 _quests 的 id 顺序。
func summary_lines() -> Array:
	var out := []
	for q in _quests:
		var mark := "✓" if _done.has(q.id) else "…"
		out.append("%s %d/%d %s" % [mark, int(_progress[q.id]), q.target, q.title])
	return out


## 持久化(纳入存档)。
func to_dict() -> Dictionary:
	return {"progress": _progress.duplicate(), "done": _done.keys()}


## 从存档恢复。经 JSON 往返:dict 键退化为 String、数值退化为 float,这里统一归一回
## StringName 键 + int 值(否则 _progress[q.id] 用 StringName 索引会 miss)。
func from_dict(d: Dictionary) -> void:
	_progress = {}
	var p: Dictionary = d.get("progress", {})
	for k in p:
		_progress[StringName(k)] = int(p[k])
	_done = {}
	for qid in d.get("done", []):
		_done[StringName(qid)] = true


## 清空全部进度与完成标记(存档复原演示用)。
func forget_all() -> void:
	_done = {}
	for q in _quests:
		_progress[q.id] = 0
