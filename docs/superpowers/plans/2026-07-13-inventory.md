# 物品背包 (KitInventory) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 godot-core-kit 增加 off-facade 类库 `KitInventory`——槽位制物品容器,自动堆叠 + 填空 + 溢出返余量,拖拽移动/合并/交换,per-slot 附加数据,`changed` 信号,`to_dict/from_dict`。游戏每个容器(背包/箱子/商店)各 `new` 一个。

**Architecture:** `inventory/kit_inventory.gd`(`class_name KitInventory extends RefCounted`,纯数据容器,不入树)。与 `KitStateMachine`/`KitUiStack` 同为游戏侧直接 `new` 的类库,**不挂门面、不进 test_core_kit 子系统清单**,仅升 plugin 版本。零跨系统依赖。

**Tech Stack:** Godot 4.7,纯 GDScript,Web 导出兼容。headless `SceneTree` 测试。

## Global Constraints

- 版本 **0.16.0**(承 game-clock v0.15.0)。三处一致:`plugin.cfg`、`core_kit.gd VERSION`、`test_core_kit.gd` 版本断言。
- **off-facade 类库**:`class_name KitInventory`,置于新目录 `inventory/`,`extends RefCounted`。**不改** `core_kit.gd` 的门面接线(preload/属性/构造/`_services`/`RESERVED_KEYS`),仅 `core_kit.gd` 的 `VERSION` 常量随版本升。**不进** `test_core_kit.gd` 子系统清单(仅版本断言随升)。
- **零依赖**:不 `preload` 任何子系统;`max_stack` 从 `KitDataRegistry` 取是游戏侧粘合。
- **命名坑**:数量参数一律 `amount`,不叫 `count`(避与方法 `count(id)` 遮蔽)。查询/移动方法名不与 `Object`/`RefCounted` 原生方法冲突。
- `class_name` 首次运行需 `godot --headless --path . --import` 生成类缓存;demo 经 `KitInventory` 引用它,测试用运行时 `load()`。
- 用 **Tab** 缩进。纯 GDScript,无 shader,Web 安全。
- 测试:`extends SceneTree` + `_initialize()`,顶层运行时 `load(...)`;末行 `ALL PASS` + `quit(0/1)`。`run_all.ps1` 测试文件数 20→21。

## File Structure

- **Create** `addons/godot-core-kit/inventory/kit_inventory.gd` — 槽位制物品容器类库。
- **Create** `test/test_kit_inventory.gd` — 14 条 headless 断言。
- **Modify** `test/run_all.ps1`(tests 加 `test_kit_inventory`;demo marker;`:1` 注释 20→21)。
- **Modify** `test/test_core_kit.gd`(仅版本断言 → 0.16.0)。
- **Modify** `addons/godot-core-kit/core_kit.gd`(仅 `VERSION` → 0.16.0)。
- **Modify** `addons/godot-core-kit/plugin.cfg`、`demo/demo.gd`、`README.md`、`addons/godot-core-kit/docs/README.md`、`addons/godot-core-kit/docs/architecture.md`。
- **Create** `addons/godot-core-kit/docs/inventory/kit-inventory.md`。

---

### Task 1: KitInventory 类库 + headless 测试

**Files:**
- Create: `addons/godot-core-kit/inventory/kit_inventory.gd`
- Create: `test/test_kit_inventory.gd`
- Modify: `test/run_all.ps1`(tests 数组末尾加 `test_kit_inventory`;`:1` 注释 20→21)

**Interfaces:**
- Produces:`KitInventory`(`class_name`,`extends RefCounted`)。构造 `KitInventory.new(capacity:int, default_max_stack:=99)`;signal `changed`;方法 `capacity()`、`add(id:StringName, amount:int, data:={}, max_stack:=-1)->int`(返余量)、`remove(id, amount)->int`、`count(id)->int`、`has(id, amount:=1)->bool`、`slot(i)->Dictionary`、`set_slot(i,id,amount,data:={})`、`clear_slot(i)`、`move(from,to)`、`swap(a,b)`、`can_add(id,amount,data:={},max_stack:=-1)->int`、`is_full()->bool`、`first_empty()->int`、`used_slots()->int`、`clear()`、`to_dict()`/`from_dict(d)`。

- [ ] **Step 1: 写 `addons/godot-core-kit/inventory/kit_inventory.gd`**

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

- [ ] **Step 2: 写 `test/test_kit_inventory.gd`**

```gdscript
extends SceneTree
## KitInventory headless 断言。RefCounted,直接 load().new(),无需入树/free。
## 运行:godot --headless --path . -s res://test/test_kit_inventory.gd

var Inv


func _initialize() -> void:
	Inv = load("res://addons/godot-core-kit/inventory/kit_inventory.gd")
	var failures := 0

	# 1. add + count + slot
	var a = Inv.new(10)
	a.add(&"wood", 5)
	if a.count(&"wood") != 5 or a.used_slots() != 1:
		print("FAIL 1: add wood5 应 count5 used1"); failures += 1
	var s0 = a.slot(0)
	if s0.get("id") != &"wood" or s0.get("count") != 5 or s0.get("data") != {}:
		print("FAIL 1: slot(0) 应 {wood,5,{}}"); failures += 1

	# 2. 堆进已有
	a.add(&"wood", 3)
	if a.count(&"wood") != 8 or a.used_slots() != 1:
		print("FAIL 2: 再 add wood3 应 count8 used1"); failures += 1

	# 3. 溢出多格
	var b = Inv.new(10, 99)
	if b.add(&"wood", 120) != 0 or b.count(&"wood") != 120 or b.used_slots() != 2:
		print("FAIL 3: add 120 应 rem0 count120 used2"); failures += 1

	# 4. 满 + 余量
	var c = Inv.new(1, 50)
	if c.add(&"wood", 120) != 70 or c.slot(0).get("count") != 50 or not c.is_full():
		print("FAIL 4: 单格50 add120 应 rem70 slot50 full"); failures += 1

	# 5. remove 部分/清格
	var d = Inv.new(10)
	d.add(&"wood", 30)
	if d.remove(&"wood", 10) != 10 or d.count(&"wood") != 20:
		print("FAIL 5: remove10 应返10 余20"); failures += 1
	if d.remove(&"wood", 100) != 20 or d.count(&"wood") != 0 or d.slot(0) != {}:
		print("FAIL 5: remove100 应返20 余0 空格"); failures += 1

	# 6. has
	var e = Inv.new(10)
	e.add(&"wood", 5)
	if not e.has(&"wood") or not e.has(&"wood", 5) or e.has(&"wood", 6) or e.has(&"stone"):
		print("FAIL 6: has 判定错"); failures += 1

	# 7. data 分格不误合
	var f = Inv.new(10)
	f.add(&"wood", 5, {"q": 1})
	f.add(&"wood", 5, {"q": 2})
	if f.used_slots() != 2 or f.count(&"wood") != 10:
		print("FAIL 7: 不同 data 应分 2 格,count 合计 10"); failures += 1

	# 8. move 到空
	var g = Inv.new(10)
	g.add(&"wood", 5)
	g.move(0, 3)
	if g.slot(0) != {} or g.slot(3).get("id") != &"wood":
		print("FAIL 8: move 到空格失败"); failures += 1

	# 9. move 合并同 id
	var h = Inv.new(10)
	h.set_slot(0, &"wood", 5)
	h.set_slot(1, &"wood", 3)
	h.move(0, 1)
	if h.slot(1).get("count") != 8 or h.slot(0) != {}:
		print("FAIL 9: move 合并同 id 失败"); failures += 1

	# 10. move 交换异物
	var i = Inv.new(10)
	i.set_slot(0, &"wood", 5)
	i.set_slot(1, &"stone", 5)
	i.move(0, 1)
	if i.slot(0).get("id") != &"stone" or i.slot(1).get("id") != &"wood":
		print("FAIL 10: move 异物应交换"); failures += 1

	# 11. can_add
	var j = Inv.new(2, 10)
	j.add(&"wood", 5)
	if j.can_add(&"wood", 100) != 15:
		print("FAIL 11: can_add 应 15,实际 %d" % j.can_add(&"wood", 100)); failures += 1

	# 12. is_full / first_empty
	var k = Inv.new(2, 10)
	k.set_slot(0, &"a", 1)
	k.set_slot(1, &"b", 1)
	if not k.is_full() or k.first_empty() != -1:
		print("FAIL 12: 填满应 is_full first_empty=-1"); failures += 1

	# 13. to_dict/from_dict 往返
	var m = Inv.new(4, 99)
	m.set_slot(0, &"wood", 50, {"q": 1})
	m.set_slot(2, &"stone", 12)
	var m2 = Inv.new(1)
	m2.from_dict(m.to_dict())
	if m2.capacity() != 4 or m2.slot(0).get("id") != &"wood" or m2.slot(0).get("count") != 50 or m2.slot(0).get("data") != {"q": 1} or m2.slot(2).get("id") != &"stone" or m2.count(&"stone") != 12:
		print("FAIL 13: from_dict 往返不一致"); failures += 1

	# 14. changed 信号
	var n = Inv.new(10)
	var fired := {"n": 0}
	n.changed.connect(func(): fired["n"] += 1)
	n.add(&"wood", 1)
	if fired["n"] < 1:
		print("FAIL 14: add 应发 changed"); failures += 1

	if failures == 0:
		print("test_kit_inventory: ALL PASS")
		quit(0)
	else:
		print("test_kit_inventory: %d FAILURE(S)" % failures)
		quit(1)
```

- [ ] **Step 3: run_all 注册**

`test/run_all.ps1` 的 `$tests` 数组末尾(`'test_game_clock'` 后)加 `,'test_kit_inventory'`;`:1` 注释 `20 个断言测试` → `21 个断言测试`。

- [ ] **Step 4: import + 单跑测试**

```
godot --headless --path . --import
godot --headless --path . -s res://test/test_kit_inventory.gd
```
Expected: `test_kit_inventory: ALL PASS`,退出码 0。FAIL 则按打印修 `kit_inventory.gd`,重跑至绿。

- [ ] **Step 5: Commit**

```bash
git add addons/godot-core-kit/inventory/kit_inventory.gd test/test_kit_inventory.gd test/run_all.ps1
git commit -m "feat: KitInventory 槽位制物品容器 + 14 条 headless 断言"
```

---

### Task 2: 版本 / 文档 / demo / 全量收尾

**Files:**
- Modify: `addons/godot-core-kit/plugin.cfg`、`addons/godot-core-kit/core_kit.gd`(仅 VERSION)、`test/test_core_kit.gd`(仅版本断言)、`demo/demo.gd`、`test/run_all.ps1`(demo marker)
- Modify: `README.md`、`addons/godot-core-kit/docs/README.md`、`addons/godot-core-kit/docs/architecture.md`
- Create: `addons/godot-core-kit/docs/inventory/kit-inventory.md`

- [ ] **Step 1: 三处版本 → 0.16.0**

- `addons/godot-core-kit/plugin.cfg`:`version="0.15.0"` → `"0.16.0"`;description 末尾追加 `;0.16.0 新增 off-facade 槽位制物品容器 KitInventory(inventory/,extends RefCounted):固定 capacity 格,add 自动堆叠+填空+溢出返余量,move 空移/合并/交换,per-slot data 分品质,changed 信号,to_dict/from_dict`。
- `addons/godot-core-kit/core_kit.gd`:`const VERSION := "0.15.0"` → `"0.16.0"`。
- `test/test_core_kit.gd`:版本断言(2 行)`"0.15.0"` → `"0.16.0"`。

- [ ] **Step 2: demo 加 Inventory 冒烟 marker**

`demo/demo.gd` 的 Clock 段之后、末尾 `CoreKit.log.info("CoreKit v%s ..."` 之前插入:

```gdscript
	# 物品背包 冒烟:溢出到多格 + move 交换(经 off-facade KitInventory)
	var bag := KitInventory.new(4, 99)
	bag.add(&"wood", 120)          # slot0=99 slot1=21
	bag.set_slot(3, &"stone", 5)
	bag.move(3, 1)                 # 异物交换:slot1=stone slot3=wood
	CoreKit.log.info("Inventory: wood=%d used=%d moved=%s" % [
		bag.count(&"wood"), bag.used_slots(), bag.slot(1).get("id") == &"stone"])
```

- [ ] **Step 3: run_all demo marker**

`test/run_all.ps1` 的 demo marker 数组里,`'Clock: y1 spring d2 06:00 day_evt=true'` 后加 `,'Inventory: wood=120 used=3 moved=true'`。

- [ ] **Step 4: 写 `addons/godot-core-kit/docs/inventory/kit-inventory.md`(五段式)**

涵盖:**职责**(槽位制物品容器,off-facade,游戏多实例);**公开 API**(构造 `new(capacity, default_max_stack)`、`add`(返余量)/`remove`/`count`/`has`/`slot`/`set_slot`/`clear_slot`/`move`/`swap`/`can_add`/`is_full`/`first_empty`/`used_slots`/`clear`/`to_dict`/`from_dict` + `changed` 信号);**依赖**(零依赖;`max_stack` 从 KitDataRegistry 取是游戏侧粘合);**用法示例**(背包/箱子多实例、`changed` 连 UI、`add` 溢出提示满、拖拽 `move`、存档 `to_dict`/`from_dict`);**注意事项**(数量参数 `amount` 命名由来;`move` 合并按 `default_max_stack` 的已知局限;per-slot `data` 分品质且深比较;Godot 4 Dictionary `==` 深比较;JSON int→float 用 int() 包)。

- [ ] **Step 5: 更新索引文档**

- 根 `README.md`:类库段加 `KitInventory` 条目(指 `addons/godot-core-kit/docs/inventory/kit-inventory.md`)+ 版本 0.16.0 条目。
- `docs/README.md`:类库(off-facade)表加 `KitInventory` 行(指 `inventory/kit-inventory.md`)。
- `docs/architecture.md`:目录布局加 `inventory/`(off-facade 类库);版本 → 0.16.0;测试文件数(20→21);类库清单加 KitInventory;依赖纪律注(KitInventory 零依赖)。

- [ ] **Step 6: 全量验证**

Run: `powershell -File test\run_all.ps1`
Expected: 末行 `=== SUMMARY FAILS=0 ===`。21 个测试全 `OK`,demo marker `Inventory: wood=120 used=3 moved=true` present,demo stderr 无 ERROR。

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "docs+demo: KitInventory into version/docs/demo/run_all, bump 0.16.0"
```

---

## Self-Review

**Spec coverage:** add/count/slot(test 1)、堆进已有(test 2)、溢出多格(test 3)、满+余量(test 4)、remove(test 5)、has(test 6)、data 分格(test 7)、move 空移/合并/交换(test 8-10)、can_add(test 11)、is_full/first_empty(test 12)、to_dict/from_dict(test 13)、changed 信号(test 14);版本三处同步(Task 2 Step 1);docs/demo/runner(Task 2)——全覆盖。非目标(上门面、UI 组件、重量、配方、事务、数据库校验)均未纳入。

**Placeholder scan:** 无 TBD/TODO;每步含实际代码或精确编辑位置。

**Type consistency:** 数量参数全程 `amount`;方法 `add/remove/count/has/slot/set_slot/move/swap/can_add/is_full/first_empty/used_slots/to_dict/from_dict` 在 Task 1 定义、Task 2 demo(`add/set_slot/move/count/used_slots/slot`)一致;`class_name KitInventory`、脚本路径 `inventory/kit_inventory.gd`、`changed` 信号、版本 0.16.0 全程一致;**不**改 test_core_kit 子系统清单(仅版本断言)。
