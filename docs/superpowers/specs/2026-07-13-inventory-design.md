# 物品背包设计(KitInventory)

> 模拟经营农场三件套之二(2/3)。给用 core-kit 的游戏一个**槽位制物品容器**类库:固定格数,自动堆叠 + 填空 + 溢出,拖拽移动/合并/交换,per-slot 附加数据(品质/耐久)。off-facade `class_name`——游戏每个容器(背包/箱子/商店/机器进出料)各 `new` 一个。

**版本:** v0.16.0(承 game-clock v0.15.0)

## 目标

新增 off-facade 类库 **`class_name KitInventory`**(`inventory/kit_inventory.gd`,`extends RefCounted`):

- **槽位制**:`KitInventory.new(capacity, default_max_stack := 99)`;内部定长数组,每格 `null`(空)或 `{id: StringName, count: int, data: Dictionary}`。
- **自动堆叠**:`add(id, amount, data, max_stack)` 先堆进 **id 且 data 相同且未满**的已有格,再填空格,按 `max_stack` 溢出到多格,**返回没塞下的余量**(0 = 全进,>0 = 满)。
- **拖拽语义**:`move(from, to)` = 目标空则移动 / 同 id 且 data 同则合并(溢出留 from)/ 否则交换;`swap(a, b)`。
- **查询/预判**:`count/has/can_add/is_full/first_empty/used_slots/slot`。
- **per-slot `data`**:opaque 字典,留给品质(金星/普通)、耐久;data 不同的同 id 视为不可堆叠异物。
- **信号**:`changed`(任何变更后发一次),UI 连它重绘。
- **持久化**:`to_dict/from_dict`。
- **零依赖**:`max_stack` 从 `KitDataRegistry` 取是**游戏侧粘合**(`inv.add(id, n, {}, def.max_stack)`),背包本身不认识数据表。

## 非目标(YAGNI v1)

- **上门面/全局单例**:背包是多实例容器,不挂 `CoreKit`;要"当前玩家背包"由游戏自己持有一个 `KitInventory` 引用(或 `CoreKit.provide("bag", bag)`)。
- **UI 组件**:本类是纯数据容器 + `changed` 信号;格子 UI / 拖拽控件是游戏或后续 UI 库的事。
- **重量/体积/分类限制**:只有格数 + 单格堆叠上限两种约束。
- **配方/合成**:不在背包里做,属独立生产系统(路线图外)。
- **跨容器转移的原子事务**:游戏用 `remove` + `add`(+ `can_add` 预判)自行组合;不提供 `transfer(a→b)` 事务。
- **物品实例唯一 id / 数据库校验**:`id` 是裸 `StringName`,背包不校验其是否在 `KitDataRegistry` 登记(解耦)。

## 架构 / 定位

**off-facade `class_name` 类库**,置于新目录 `inventory/`,`extends RefCounted`(纯数据容器,不入树,GC 友好,可带 `signal`)。与 `KitStateMachine`/`KitContext`/`KitUiStack` 同为"游戏侧直接 `new` 的可复用类",**不挂门面、不被 core/systems 依赖、不进 `test_core_kit` 子系统清单**。仅升 plugin 版本(`plugin.cfg` + `core_kit.gd VERSION` + `test_core_kit` 版本断言)。

`class_name` 首次运行需 `godot --headless --path . --import` 生成类缓存(demo 经 `KitInventory` 引用它;测试用运行时 `load()` 不受影响)。

**依赖纪律**:零跨系统依赖,不 `preload` 任何子系统。诊断(越界等)静默/夹取,不引 `CoreKit.log`。

## 组件

### `KitInventory`(`inventory/kit_inventory.gd`,`class_name KitInventory extends RefCounted`)

> **命名坑**:数量参数一律用 `amount`,**不叫 `count`**——避免与方法 `count(id)` 同名遮蔽(参见既往 member-vs-name 踩坑)。

```gdscript
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
```

## 数据流

`bag.add(&"wood", 120, {}, 99)` → 无同 id 格 → 填空格:slot0 = 99、slot1 = 21 → `remaining == 0` → 发 `changed`。UI `_refresh_ui()` 读 `slot(0)`/`slot(1)` 重绘。
拖拽:玩家把 slot0 拖到 slot5 → `bag.move(0, 5)`。
存档:`CoreKit.saves` 序列化时收 `bag.to_dict()`;读档 `bag.from_dict(d)` 后发 `changed`。

## 错误处理

- 越界索引(`slot/set_slot/clear_slot/move/swap`)一律夹取判断后 no-op / 返回 `{}`,不崩。
- `add/remove/can_add` 的 `amount<=0` no-op。
- `add` 满时返回余量 > 0(调用方据此提示"背包已满");不丢弃、不报错。
- `move` 合并按 `default_max_stack`(move 不知道 per-item max)——**已知局限,文档注明**;绝大多数游戏堆叠上限全局统一,默认正确。
- `from_dict` 全字段 `int()/StringName()` 包裹容 JSON 往返;`slots` 超出 capacity 的尾项忽略。

## 测试(headless)

### 新 `test/test_kit_inventory.gd`

`load(...)`.new() 实例化(RefCounted,无需入树/free)。

1. **add + count + slot**:`new(10)`;`add(&"wood",5)`→`count==5`、`used_slots==1`、`slot(0)=={id:wood,count:5,data:{}}`。
2. **堆进已有**:再 `add(&"wood",3)`→`count==8`、`used_slots==1`。
3. **溢出多格**:`new(10,99)`;`add(&"wood",120)`→返回 `0`、`count==120`、`used_slots==2`(99+21)。
4. **满 + 余量**:`new(1,50)`;`add(&"wood",120)`→slot0 count 50、返回 `70`、`is_full()==true`。
5. **remove 部分/清格**:`add(&"wood",30)`;`remove(&"wood",10)`→返回 10、`count==20`;`remove(&"wood",100)`→返回 20、`count==0`、`slot(0)=={}`。
6. **has**:`add(&"wood",5)`;`has(&"wood")`true、`has(&"wood",5)`true、`has(&"wood",6)`false、`has(&"stone")`false。
7. **data 分格不误合**:`add(&"wood",5,{"q":1})`;`add(&"wood",5,{"q":2})`→`used_slots==2`、`count(&"wood")==10`、两格 data 各异。
8. **move 到空**:slot0=wood5;`move(0,3)`→`slot(0)=={}`、`slot(3).id==&"wood"`。
9. **move 合并同 id**:`set_slot(0,&"wood",5)`、`set_slot(1,&"wood",3)`;`move(0,1)`→`slot(1).count==8`、`slot(0)=={}`。
10. **move 交换异物**:slot0=wood、slot1=stone;`move(0,1)`→两格互换。
11. **can_add**:`new(2,10)`;`add(&"wood",5)`→`can_add(&"wood",100)==15`(slot0 余 5 + 空 slot1 10)。
12. **is_full / first_empty**:填满 → `is_full()`true、`first_empty()==-1`。
13. **to_dict/from_dict 往返**:造多格(含 data)→`to_dict()`→`new(1).from_dict(d)`→逐格 `slot(i)` 等价、`count` 等价、`capacity()` 恢复。
14. **changed 信号**:连计数器,`add` 一次 → 收到 ≥1 次。

### `test/test_core_kit.gd`

仅版本断言(2 行)`"0.15.0"` → `"0.16.0"`(off-facade 不进子系统清单)。

## 收尾件

- 新 `inventory/kit_inventory.gd`(+`.uid`);新 `test/test_kit_inventory.gd`(+`.uid`)。
- `test/test_core_kit.gd`:版本断言 → 0.16.0。
- 新 `docs/inventory/kit-inventory.md`(五段式),记槽位模型、自动堆叠/溢出、move 语义与 default_max_stack 局限、per-slot data 品质、changed 信号、to_dict/from_dict、与 KitDataRegistry 粘合(max_stack)。
- `docs/README.md`:类库表加 `KitInventory` 行(指 `inventory/kit-inventory.md`)。
- `docs/architecture.md`:目录布局加 `inventory/`、版本 0.16.0、测试文件数(20→21)、类库清单加 KitInventory、依赖纪律注(零依赖)。
- 根 `README.md`:加 `KitInventory` 条目 + 版本 0.16.0。
- `plugin.cfg`:version 0.16.0 + description 追加。
- `demo/demo.gd`:`KitInventory` 冒烟——`new(4)` + `add` 溢出 + `move`,打 marker(如 `Inventory: wood=120 used=2 moved=true`);`test/run_all.ps1`:加 `test_kit_inventory`(20→21)+ demo marker `Inventory: ` + 计数。

## 我替你拍的默认(实现时若无异议即照此)

off-facade `class_name KitInventory`(`inventory/kit_inventory.gd`,`extends RefCounted`)· 槽位制固定 capacity + default_max_stack=99 · 每格 {id,count,data} · add 自动堆叠+填空+溢出返回余量 · move 空移/同 id 合并(按 default_max_stack)/交换 · 数量参数名 `amount`(避 count 遮蔽)· data 深比较分格 · `changed` 信号 · to_dict/from_dict · 不上门面、不进 test_core_kit 子系统清单(仅升版本)· 版本 0.16.0。
