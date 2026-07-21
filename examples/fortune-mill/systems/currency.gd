class_name Currency
extends RefCounted
## 货币值类型(P0 内部 float,日后可整体换 Decimal)。全游戏货币运算必经此类,
## 不出现裸 float。format 为静态,供 UI 格式化任意数(余额/成本/产出)。

var _amount: float = 0.0

func _init(amount: float = 0.0) -> void:
	_amount = amount


func get_amount() -> float:
	return _amount


func set_amount(x: float) -> void:
	_amount = x


func add(x: float) -> void:
	_amount += x


func can_afford(cost: float) -> bool:
	return _amount >= cost


## 够则扣款返 true;不够不动余额返 false。
func spend(cost: float) -> bool:
	if _amount < cost:
		return false
	_amount -= cost
	return true


## 格式化任意数值。style: "kMBT"(默认,千分位符号) / "plain"(整数)。
## scientific 留待 P4。
static func format(x: float, style: String = "kMBT") -> String:
	if style == "plain":
		return str(int(round(x)))
	var neg := x < 0.0
	var v := absf(x)
	var s := ""
	if v < 1000.0:
		s = str(int(round(v)))
	else:
		var units := ["K", "M", "B", "T"]
		var idx := -1
		while v >= 1000.0 and idx < units.size() - 1:
			v /= 1000.0
			idx += 1
		s = "%.2f%s" % [v, units[idx]]
	return ("-" + s) if neg else s
