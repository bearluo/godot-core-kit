class_name KitInventory
extends RefCounted
## KitInventory —— 槽位制物品容器(off-facade 类库,游戏每个容器各 new 一个)。
## 固定 capacity 格,每格 null(空)或 {id:StringName, count:int, data:Dictionary}。
## add 自动堆叠(id 且 data 相同)进已有格→再填空格→按 max_stack 溢出多格,返回没塞下的余量。
## per-slot data 为 opaque 字典(品质/耐久),data 不同视为不可堆叠异物。
## 零依赖;max_stack 从 KitDataRegistry 取是游戏侧粘合。持久化 to_dict/from_dict。
##
## 用法:
##   var bag := KitInventory.new(30)            # 30 格,默认单格上限 99
##   bag.changed.connect(_refresh_ui)
##   var overflow := bag.add(&"wood", 120)      # 溢出到 2 格,返回 0
##   bag.move(0, 5)                             # 拖拽:空移/同 id 合并/否则交换

## 容器任何变更后发一次(增删改移)。UI 连此重绘。
signal changed

var _capacity: int
var _default_max_stack: int
var _slots: Array   # 长度 == _capacity,元素 null 或 {id,count,data}


func _init(capacity: int, default_max_stack: int = 99) -> void:
	_capacity = maxi(0, capacity)
	_default_max_stack = maxi(1, default_max_stack)
	_slots = []
	_slots.resize(_capacity)   # 全 null


func capacity() -> int:
	return _capacity


## 加 amount 个 id(data 为品质等附加,默认空)。先堆进 id 且 data 相同且未满的已有格,
## 再填空格;每格不超过 max_stack(-1=默认)。返回没塞下的余量(0=全进)。有变化发 changed。
func add(id: StringName, amount: int, data: Dictionary = {}, max_stack: int = -1) -> int:
	if amount <= 0:
		return 0
	var cap := _cap_for(max_stack)
	var remaining := amount
	var mutated := false
	for i in _capacity:                       # 1) 堆进已有可叠格
		if remaining <= 0: break
		var s = _slots[i]
		if s != null and s["id"] == id and _data_eq(s["data"], data) and s["count"] < cap:
			var put := mini(cap - s["count"], remaining)
			s["count"] += put
			remaining -= put
			mutated = true
	for i in _capacity:                       # 2) 填空格
		if remaining <= 0: break
		if _slots[i] == null:
			var put := mini(cap, remaining)
			_slots[i] = {"id": id, "count": put, "data": data.duplicate(true)}
			remaining -= put
			mutated = true
	if mutated:
		changed.emit()
	return remaining


## 移除至多 amount 个 id(从前往后跨格)。返回实际移除数。有变化发 changed。
func remove(id: StringName, amount: int) -> int:
	if amount <= 0:
		return 0
	var removed := 0
	for i in _capacity:
		if removed >= amount: break
		var s = _slots[i]
		if s != null and s["id"] == id:
			var take := mini(s["count"], amount - removed)
			s["count"] -= take
			removed += take
			if s["count"] <= 0:
				_slots[i] = null
	if removed > 0:
		changed.emit()
	return removed


## id 的总数(跨格,忽略 data 差异)。
func count(id: StringName) -> int:
	var total := 0
	for s in _slots:
		if s != null and s["id"] == id:
			total += s["count"]
	return total


## 全部物品的 id -> 总数聚合(跨格合并同 id,忽略 data 分堆);空背包返回 {}。
## 便于背包 UI / 存量查询按 id 汇总,免手动遍历 capacity()×slot()。
func totals() -> Dictionary:
	var out := {}
	for s in _slots:
		if s != null:
			var id = s["id"]
			out[id] = int(out.get(id, 0)) + int(s["count"])
	return out


func has(id: StringName, amount: int = 1) -> bool:
	return count(id) >= amount


## 取第 i 格只读快照(深拷 data);空格或越界返回 {}。
func slot(i: int) -> Dictionary:
	if i < 0 or i >= _capacity or _slots[i] == null:
		return {}
	var s = _slots[i]
	return {"id": s["id"], "count": s["count"], "data": s["data"].duplicate(true)}


## 直接置第 i 格(载档/编辑器)。amount<=0 → 清空该格。越界 no-op。发 changed。
func set_slot(i: int, id: StringName, amount: int, data: Dictionary = {}) -> void:
	if i < 0 or i >= _capacity:
		return
	_slots[i] = null if amount <= 0 else {"id": id, "count": amount, "data": data.duplicate(true)}
	changed.emit()


func clear_slot(i: int) -> void:
	if i < 0 or i >= _capacity or _slots[i] == null:
		return
	_slots[i] = null
	changed.emit()


## 拖拽:to 空→移动;同 id 且 data 同→合并(按 default_max_stack,溢出留 from);否则交换。
func move(from: int, to: int) -> void:
	if from < 0 or from >= _capacity or to < 0 or to >= _capacity or from == to:
		return
	var a = _slots[from]
	if a == null:
		return
	var b = _slots[to]
	if b == null:
		_slots[to] = a
		_slots[from] = null
	elif b["id"] == a["id"] and _data_eq(a["data"], b["data"]):
		var moved := mini(_default_max_stack - b["count"], a["count"])
		b["count"] += moved
		a["count"] -= moved
		if a["count"] <= 0:
			_slots[from] = null
	else:
		_slots[from] = b
		_slots[to] = a
	changed.emit()


func swap(a: int, b: int) -> void:
	if a < 0 or a >= _capacity or b < 0 or b >= _capacity or a == b:
		return
	var tmp = _slots[a]
	_slots[a] = _slots[b]
	_slots[b] = tmp
	changed.emit()


## 还能塞几个 id(不改状态,放置前预判)。
func can_add(id: StringName, amount: int, data: Dictionary = {}, max_stack: int = -1) -> int:
	if amount <= 0:
		return 0
	var cap := _cap_for(max_stack)
	var room := 0
	for s in _slots:
		if s == null:
			room += cap
		elif s["id"] == id and _data_eq(s["data"], data) and s["count"] < cap:
			room += cap - s["count"]
	return mini(room, amount)


## 无空格(装不下全新 id)。精确判断某 id 能塞几个用 can_add。
func is_full() -> bool:
	return first_empty() == -1


func first_empty() -> int:
	for i in _capacity:
		if _slots[i] == null:
			return i
	return -1


func used_slots() -> int:
	var n := 0
	for s in _slots:
		if s != null:
			n += 1
	return n


func clear() -> void:
	for i in _capacity:
		_slots[i] = null
	changed.emit()


## 序列化:{capacity, default_max_stack, slots:[null 或 {id(String),count,data}]}。
func to_dict() -> Dictionary:
	var out_slots := []
	for s in _slots:
		out_slots.append(null if s == null else {"id": String(s["id"]), "count": s["count"], "data": s["data"].duplicate(true)})
	return {"capacity": _capacity, "default_max_stack": _default_max_stack, "slots": out_slots}


func from_dict(d: Dictionary) -> void:
	_capacity = int(d.get("capacity", _capacity))
	_default_max_stack = maxi(1, int(d.get("default_max_stack", _default_max_stack)))
	_slots = []
	_slots.resize(_capacity)
	var in_slots: Array = d.get("slots", [])
	for i in mini(_capacity, in_slots.size()):
		var s = in_slots[i]
		if s != null:
			var data: Dictionary = (s["data"] as Dictionary).duplicate(true) if s.has("data") else {}
			_slots[i] = {"id": StringName(s["id"]), "count": int(s["count"]), "data": data}
	changed.emit()


## 单格上限:>0 用参数,否则用 default。
func _cap_for(max_stack: int) -> int:
	return max_stack if max_stack > 0 else _default_max_stack


## data 相等(Godot 4 Dictionary == 为按值深比较;空 {} 相等)。
func _data_eq(a: Dictionary, b: Dictionary) -> bool:
	return a == b
