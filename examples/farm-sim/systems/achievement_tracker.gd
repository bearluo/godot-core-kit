extends Node
## 成就追踪器。与任务(quest_log)刻意对照——展示"什么进存档、什么进偏好"的边界:
##   - 任务:每【存档槽】的进度,随 to_dict/from_dict 进存档,删档即失(见 quest_log);
##   - 成就:【账号级】里程碑,解锁写 CoreKit.settings 的 "achievements" 分区,跨存档、
##     删档不丢(Settings 文档明言"设置 ≠ 存档")。
##
## dogfood 点:
## - CoreKit.settings 作【账号级持久化】:解锁写 settings、启动读 settings,与存档槽完全无关;
## - bus 多命名空间聚合:一个订阅方汇聚 shop:bought + quest:completed + weather:changed 三来源
##   (与 quest_log 的 clock:+shop: 是不同组合),各自判定不同里程碑;
## - achievement: 是游戏第 4 个自有命名空间。

const SECTION := "achievements"                  ## settings 分区名
const EV_UNLOCKED := "achievement:unlocked"      ## payload {id, title}

var _registry
var _defs: Array = []            ## achievement def 列表(按 id 字母序,判定/输出确定)
var _quest_completed := 0        ## 已完成任务计数(供 all_quests 判定,本局累计)


## 注入 registry(驱动方在 add_child 前调用)。
func bind(registry) -> void:
	_registry = registry


func _ready() -> void:
	for aid in _registry.ids(&"achievement", true):
		_defs.append(_registry.get_def(&"achievement", aid))
	CoreKit.bus.subscribe("shop:bought", _on_bought)         # 首次采购
	CoreKit.bus.subscribe("quest:completed", _on_quest_done) # 完成全部任务
	CoreKit.bus.subscribe("weather:changed", _on_weather)    # 遇到雨天


func _exit_tree() -> void:
	CoreKit.bus.unsubscribe_all(self)


## 是否已解锁(读 settings,账号级)。
func is_unlocked(aid: StringName) -> bool:
	return bool(CoreKit.settings.get_value(SECTION, String(aid), false))


func unlocked_count() -> int:
	var n := 0
	for a in _defs:
		if is_unlocked(a.id):
			n += 1
	return n


func total() -> int:
	return _defs.size()


## 解锁概览行(供结算日志),按 _defs 字母序。
func summary_lines() -> Array:
	var out := []
	for a in _defs:
		var mark := "★" if is_unlocked(a.id) else "☆"
		out.append("%s %s" % [mark, a.title])
	return out


## 解锁:写 settings(账号级持久化,立即落盘)+ 广播 achievement:unlocked。已解锁则幂等跳过。
func _unlock(a) -> void:
	if is_unlocked(a.id):
		return
	CoreKit.settings.set_value(SECTION, String(a.id), true)
	CoreKit.bus.publish(EV_UNLOCKED, {"id": a.id, "title": a.title})
	CoreKit.log.info("[Achieve] 解锁:%s" % a.title)


func _find(kind: StringName):
	for a in _defs:
		if a.kind == kind:
			return a
	return null


func _on_bought(_payload) -> void:
	var a = _find(&"first_purchase")
	if a != null:
		_unlock(a)


func _on_quest_done(_payload) -> void:
	_quest_completed += 1
	var a = _find(&"all_quests")
	if a != null and _quest_completed >= a.target:
		_unlock(a)


func _on_weather(payload: Dictionary) -> void:
	if payload.get("kind", &"") == &"rainy":
		var a = _find(&"rain_dancer")
		if a != null:
			_unlock(a)


## 账号级重置(demo 收尾,保证可重复跑;真实游戏一般不调)。
func reset_all() -> void:
	CoreKit.settings.erase_section(SECTION)
