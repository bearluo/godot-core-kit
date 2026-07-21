class_name KitStats
extends RefCounted
## 统计计数器持久化(孵化于本 example,拟反哺 kit)。key(StringName) -> float。
## 三种写法各司其职:
##   add(key, n)        —— 累加(里程碑计数:累计投镖数、抽卡次数、贿赂次数…)
##   record_max(key, v) —— 单调取大(峰值:最高单次收益、最高周目 ng_level…)
##   set_value(key, v)  —— 直接置(权威快照:jackpot 累计次数直接读房间计数)
## 读用 get_value(阈值判定的唯一入口)。纯数据、不挂树、不碰 bus;存档 to_dict/from_dict。
## 零依赖(仅引擎)。成就阈值判定见 [[kit_achievements]]。

var _values: Dictionary = {}   # StringName -> float


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
