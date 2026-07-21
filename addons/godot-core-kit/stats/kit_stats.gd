class_name KitStats
extends RefCounted
## 统计计数器存储(off-facade 纯逻辑类,不挂节点树)。放置 / 成就 / 数值向游戏的
## 「玩家生涯计数」心脏:把散落各处的 `player.kills += 1`、`if x > best: best = x` 收拢成
## 一个 key → 数值的表,配三种语义化写法,读档只需一个 to_dict/from_dict。
##
##   add(key, n)        —— 累加(里程碑计数:累计击杀、点击次数、通关次数……)
##   record_max(key, v) —— 单调取大(峰值:最高连击、最高单次伤害、最远距离……)
##   set_value(key, v)  —— 直接置(权威快照:把别处的权威计数镜像进来)
##
## 读一律走 get_value(阈值 / 展示的唯一入口)。常与 [[kit-achievements]] 搭配——成就把
## 「解锁条件」声明成「某统计键 >= 阈值」,由 KitStats 提供被判定的数。零依赖(纯 GDScript
## + 引擎内建),不挂门面、不挂节点树,游戏各存档 / 各档案自建一台。

var _values: Dictionary = {}   # StringName(key) -> float


## 累加(默认 +1)。返回累加后的新值。
func add(key: StringName, amount: float = 1.0) -> float:
	var v := float(_values.get(key, 0.0)) + amount
	_values[key] = v
	return v


## 单调取大(峰值统计;默认基线 0 → 仅适用非负峰值)。返回取大后的当前值。
func record_max(key: StringName, value: float) -> float:
	var v := maxf(float(_values.get(key, 0.0)), value)
	_values[key] = v
	return v


## 直接置值(权威快照,不累加)。
func set_value(key: StringName, value: float) -> void:
	_values[key] = value


func get_value(key: StringName, default: float = 0.0) -> float:
	return float(_values.get(key, default))


func has(key: StringName) -> bool:
	return _values.has(key)


func keys() -> Array:
	return _values.keys()


func clear() -> void:
	_values.clear()


## 存档:key 统一 String(JSON 键),值统一 float。
func to_dict() -> Dictionary:
	var d := {}
	for k in _values:
		d[String(k)] = float(_values[k])
	return d


func from_dict(d: Dictionary) -> void:
	_values.clear()
	for k in d:
		_values[StringName(k)] = float(d[k])
