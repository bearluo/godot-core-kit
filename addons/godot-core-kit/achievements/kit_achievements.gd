class_name KitAchievements
extends RefCounted
## 成就引擎(off-facade 纯逻辑类,不挂节点树)。三件事:数据驱动阈值判定 + 触发去重 + 平台抽象层。
##
## 持有:成就定义表 _defs(每条 = [[achievement_def]]:{id, stat_key, threshold},或任何带这三字段的
## 对象)+ 已解锁集合 _unlocked。核心是 evaluate(stats):扫全部 def,凡「未解锁」且
## stats.get_value(stat_key) >= threshold → 解锁,返回本次【新解锁】id 列表(def 表顺序)供上层弹 toast;
## 已解锁的绝不重触(去重的核心,取代散落各处「解锁前先查有没有解锁过」的样板)。
##
## 平台抽象层:set_steam_sink 注入回调(如 Steam.setAchievement / Google Play Games),新解锁时触发一次;
## 默认空(kit 不绑定任何平台 SDK)。统计源见 [[kit-stats]](evaluate 的入参鸭子类型读 get_value)。
##
## 纯数据(不挂门面、不挂节点树、不碰事件总线)。存档只存已解锁 id 集合——def 表是只读数据、统计另存,
## 派生态(哪些达阈值)由 evaluate 重算。零依赖(纯 GDScript + 引擎内建)。

var _defs: Array = []            # AchievementDef(或鸭子类型)列表,只读数据不入存档
var _unlocked: Dictionary = {}   # StringName(id) -> true(当集合用)
var _steam_sink: Callable = Callable()


## 装入成就定义表(通常来自 KitDataRegistry.all(&"achievement") 或代码构建的数组)。
func set_defs(defs: Array) -> void:
	_defs = defs


## 注入平台成就回调:新解锁时 sink.call(id) 一次。默认不设 = 无平台绑定。
func set_steam_sink(sink: Callable) -> void:
	_steam_sink = sink


func is_unlocked(id: StringName) -> bool:
	return _unlocked.has(id)


func count() -> int:
	return _unlocked.size()


func total() -> int:
	return _defs.size()


func unlocked_ids() -> Array:
	return _unlocked.keys()


## 手动解锁一条(去重)。新解锁 → 触发平台 sink 并返回 true;已解锁 → false(不重触)。
func unlock(id: StringName) -> bool:
	if _unlocked.has(id):
		return false
	_unlocked[id] = true
	_fire_sink(id)
	return true


## 扫全部 def,解锁所有「已达阈值且未解锁」者(去重内建)。返回本次新解锁 id 列表(def 表顺序)。
## stats 鸭子类型:任何暴露 get_value(key, default) 的对象皆可(通常是 KitStats)。
func evaluate(stats) -> Array:
	var newly: Array = []
	for d in _defs:
		if _unlocked.has(d.id):
			continue
		if stats.get_value(d.stat_key, 0.0) >= float(d.threshold):
			_unlocked[d.id] = true
			newly.append(d.id)
			_fire_sink(d.id)
	return newly


func _fire_sink(id: StringName) -> void:
	if _steam_sink.is_valid():
		_steam_sink.call(id)


## 存档:只存已解锁 id 集合(String 化)。
func to_dict() -> Dictionary:
	var ids: Array = []
	for id in _unlocked:
		ids.append(String(id))
	return {"unlocked": ids}


func from_dict(d: Dictionary) -> void:
	_unlocked.clear()
	for id in d.get("unlocked", []):
		_unlocked[StringName(id)] = true
