# Fortune Mill P0 · 飞镖竖切片 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `examples/fortune-mill/` 建一个飞镖房竖切片，能从 $1 gold 手动投镖、买升级、攒够 100 万 gold 贿赂守卫 Verminous 过关，并通过 `FORTUNE_SMOKE=1` headless 端到端自测。

**Architecture:** headless-first 数据/表现分离。经济逻辑跑纯 `RefCounted` 数据模型（`Currency` / `KitModifiers` / `DartsRoom`），由 `FortuneMill` autoload 持有；表现层（`world.gd` + 代码构建 HUD）只读模型 + 发命令；`CoreKit.bus` 只广播 `fortune:*` 脏标记，不做数值求值；存档经 `CoreKit.saves` 存纯 Dictionary。

**Tech Stack:** Godot 4.7，纯 GDScript，godot-core-kit 0.18.0（`CoreKit.bus` / `.saves` / `.log` + `KitDataRegistry`）。

## Global Constraints

以下为 spec（`docs/superpowers/specs/2026-07-20-fortune-mill-incremental-design.md`）的项目级约束，每个任务都隐含遵守：

- **纯 GDScript，禁 GDExtension**（保 Web/Android 导出）。不引入任何大数库。
- **headless-first**：经济逻辑跑纯 `RefCounted`，**不挂节点树**、不 `extends Node`。
- **不出现裸 float 货币运算**：货币一律经 `Currency`（内部 float，P0 就封接口，日后可换 Decimal）。
- **`bus` 只广播脏标记**：事件名 `fortune:currency_changed` / `fortune:upgrade_purchased` / `fortune:room_cleared`，payload 仅通知，UI 收到后回模型拉数；协同/数值求值绝不走 bus。
- **存档只存 Dictionary**（float / String / 嵌套 dict），**不存 Object/Resource**——`SaveManager._has_unserializable` 会拒。模型经 `to_dict()/from_dict()` 转换。
- **class_name 缓存**：新增带 `class_name` 的脚本后，运行任何测试前先 `godot --headless --path . --import`。
- **飞镖门槛常量**：贿赂 Verminous 需 `gold >= 1_000_000`（`DartsRoom.BRIBE_COST`）。
- **靶心 17 档倍率表照抄 spec §5.1**，不得改数值：`[1.5, 2, 3, 5, 8, 12, 20, 30, 50, 80, 125, 200, 300, 500, 800, 1200, 2500]`。

---

## 文件结构

```
examples/fortune-mill/
├─ README.md                         游戏门面 + 怎么跑
├─ defs/
│  └─ dart_upgrade_def.gd            升级定义 Resource schema (class_name DartUpgradeDef)
├─ systems/                          纯数据层(RefCounted / autoload)
│  ├─ currency.gd                    class_name Currency  值类型 + 静态 format
│  ├─ kit_modifiers.gd               class_name KitModifiers  修正器栈雏形(反哺预备)
│  ├─ darts_room.gd                  class_name DartsRoom  飞镖房 model
│  └─ fortune_state.gd               FortuneMill autoload  状态支柱
├─ scenes/
│  ├─ world.tscn                     主场景(根 Node + world.gd)
│  └─ world.gd                       表现层根 + FORTUNE_SMOKE 入口
├─ data/
│  └─ dart_upgrades/                 升级 .tres(load_dir 扫这里)
│     ├─ sharper_darts.tres
│     ├─ golden_tips.tres
│     ├─ steady_hand.tres
│     ├─ bullseye_training.tres
│     └─ double_dart.tres
├─ gfx/                              (P0 空,P5 放 art_bank)
└─ docs/
   └─ README.md                      P0 功能简述

test/
├─ test_fortune_currency.gd          进 run_all
├─ test_fortune_modifiers.gd         进 run_all
└─ test_fortune_darts.gd             进 run_all
```

对应关系：`Currency` 只管货币值与格式化；`KitModifiers` 只管修正器聚合；`DartsRoom` 只管飞镖房规则；`FortuneMill` 只做装配 + 命令 + 存档接线；`world.gd` 只做表现 + smoke。各文件单一职责，可独立测。

---

## Task 1: 目录骨架 + README

**Files:**
- Create: `examples/fortune-mill/README.md`
- Create: `examples/fortune-mill/docs/README.md`
- Create: `examples/fortune-mill/gfx/.gitkeep`
- Create: `examples/fortune-mill/data/dart_upgrades/.gitkeep`

**Interfaces:**
- Consumes: 无
- Produces: 目录结构（后续任务往里填文件）

- [ ] **Step 1: 建目录与占位文件**

`examples/fortune-mill/README.md`:

```markdown
# fortune-mill —— godot-core-kit 的 incremental 放置游戏示例

复刻 Steam《财富磨坊 / Fortune Mill》风格的房间闯关式放置游戏,建在
[godot-core-kit](../../addons/godot-core-kit/) 上,用真实玩法 dogfood 验证框架并反哺
四个缺口子系统(KitModifiers/KitOffline/KitStats/存档迁移)。

**当前进度:P0 飞镖竖切片** —— 手动投镖 → 买升级 → 攒 100 万 gold 贿赂守卫 Verminous 过关。

## 快速开始

- **编辑器里玩**:运行工程(主场景 `scenes/world.tscn`)。点「投镖」赚 gold,买升级,攒够 100 万点「贿赂」过关。
- **headless 自测**:`FORTUNE_SMOKE=1 godot --headless --path . res://examples/fortune-mill/scenes/world.tscn --quit-after 600` → `[Fortune][SMOKE] PASS`。
- 首次跑先 `godot --headless --path . --import` 生成 class_name 缓存。

## 设计

见 [docs/superpowers/specs/2026-07-20-fortune-mill-incremental-design.md](../../docs/superpowers/specs/2026-07-20-fortune-mill-incremental-design.md)。
```

`examples/fortune-mill/docs/README.md`:

```markdown
# fortune-mill 功能文档

P0 阶段只有飞镖房。目录:

- `defs/` —— 升级定义 Resource schema
- `systems/` —— 纯数据层(Currency/KitModifiers/DartsRoom/FortuneMill autoload)
- `scenes/` —— world 场景 + 表现层
- `data/dart_upgrades/` —— 升级 .tres
- `test/test_fortune_*.gd` —— headless 断言(进 kit 门 run_all)

架构纪律:经济逻辑跑纯 RefCounted 数据层不挂节点树;UI 只读模型发命令;
bus 只广播 `fortune:*` 脏标记;货币全走 Currency;存档只存 Dictionary。
```

`examples/fortune-mill/gfx/.gitkeep` 和 `examples/fortune-mill/data/dart_upgrades/.gitkeep`：空文件（占位，让空目录进 git；.tres 建好后可删 dart_upgrades 下的 .gitkeep）。

- [ ] **Step 2: Commit**

```bash
git add examples/fortune-mill/
git commit -m "chore(fortune-mill): P0 目录骨架 + README"
```

---

## Task 2: Currency 值类型 + 格式化

**Files:**
- Create: `examples/fortune-mill/systems/currency.gd`
- Test: `test/test_fortune_currency.gd`

**Interfaces:**
- Consumes: 无
- Produces:
  - `class_name Currency extends RefCounted`
  - `Currency.new(amount: float = 0.0)`
  - `get_amount() -> float` / `set_amount(x: float) -> void`
  - `add(x: float) -> void`
  - `can_afford(cost: float) -> bool`
  - `spend(cost: float) -> bool`（够则扣返 true，不够返 false 不扣）
  - `static format(x: float, style: String = "kMBT") -> String`

- [ ] **Step 1: 建 stub + 写失败测试**

`examples/fortune-mill/systems/currency.gd`（stub）:

```gdscript
class_name Currency
extends RefCounted
## 货币值类型(P0 内部 float,日后可整体换 Decimal)。全游戏货币运算必经此类,
## 不出现裸 float。format 为静态,供 UI 格式化任意数(余额/成本/产出)。

var _amount: float = 0.0

func _init(amount: float = 0.0) -> void:
	_amount = amount
```

`test/test_fortune_currency.gd`:

```gdscript
extends SceneTree
## Currency headless 断言。运行:godot --headless --path . -s res://test/test_fortune_currency.gd
const Currency := preload("res://examples/fortune-mill/systems/currency.gd")


func _initialize() -> void:
	var failures := 0

	# 1. 构造 + get_amount
	var c = Currency.new(100.0)
	if c.get_amount() != 100.0:
		print("FAIL 1: get_amount 应 100"); failures += 1

	# 2. add
	c.add(50.0)
	if c.get_amount() != 150.0:
		print("FAIL 2: add 后应 150"); failures += 1

	# 3. can_afford
	if not c.can_afford(150.0) or c.can_afford(150.01):
		print("FAIL 3: can_afford 边界错"); failures += 1

	# 4. spend 够 → 扣款返 true
	if not c.spend(30.0) or c.get_amount() != 120.0:
		print("FAIL 4: spend 够应扣到 120"); failures += 1

	# 5. spend 不够 → 不扣返 false
	if c.spend(1000.0) or c.get_amount() != 120.0:
		print("FAIL 5: spend 不够应不扣且返 false"); failures += 1

	# 6. set_amount
	c.set_amount(1_000_000.0)
	if c.get_amount() != 1_000_000.0:
		print("FAIL 6: set_amount 错"); failures += 1

	# 7. format kMBT
	if Currency.format(0.0) != "0":
		print("FAIL 7a: format(0) 应 '0',实际 '%s'" % Currency.format(0.0)); failures += 1
	if Currency.format(999.0) != "999":
		print("FAIL 7b: format(999) 应 '999',实际 '%s'" % Currency.format(999.0)); failures += 1
	if Currency.format(1500.0) != "1.50K":
		print("FAIL 7c: format(1500) 应 '1.50K',实际 '%s'" % Currency.format(1500.0)); failures += 1
	if Currency.format(2_500_000.0) != "2.50M":
		print("FAIL 7d: format(2.5e6) 应 '2.50M',实际 '%s'" % Currency.format(2_500_000.0)); failures += 1
	if Currency.format(1_000_000_000.0) != "1.00B":
		print("FAIL 7e: format(1e9) 应 '1.00B',实际 '%s'" % Currency.format(1_000_000_000.0)); failures += 1

	# 8. format plain
	if Currency.format(1500.0, "plain") != "1500":
		print("FAIL 8: format plain 应 '1500',实际 '%s'" % Currency.format(1500.0, "plain")); failures += 1

	if failures == 0:
		print("test_fortune_currency: ALL PASS")
		quit(0)
	else:
		print("test_fortune_currency: %d FAILURE(S)" % failures)
		quit(1)
```

- [ ] **Step 2: import + 跑测试验证失败**

```bash
godot --headless --path . --import
godot --headless --path . -s res://test/test_fortune_currency.gd
```

Expected: FAIL —— `get_amount`/`add`/`spend`/`format` 未定义（stub 只有 `_amount`）。

- [ ] **Step 3: 实现方法**

在 `currency.gd` 追加:

```gdscript
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
```

- [ ] **Step 4: 跑测试验证通过**

```bash
godot --headless --path . -s res://test/test_fortune_currency.gd
```

Expected: `test_fortune_currency: ALL PASS`

- [ ] **Step 5: Commit**

```bash
git add examples/fortune-mill/systems/currency.gd test/test_fortune_currency.gd
git commit -m "feat(fortune-mill): Currency 值类型 + kMBT 格式化 + 8 断言"
```

---

## Task 3: KitModifiers 修正器栈雏形

**Files:**
- Create: `examples/fortune-mill/systems/kit_modifiers.gd`
- Test: `test/test_fortune_modifiers.gd`

**Interfaces:**
- Consumes: 无
- Produces:
  - `class_name KitModifiers extends RefCounted`
  - `set_modifier(target: StringName, source_id: StringName, op: StringName, value: float) -> void`（`op` ∈ `&"add"` / `&"mul"`；同 `source_id` 覆盖）
  - `remove_source(target: StringName, source_id: StringName) -> void`
  - `value_for(target: StringName, base: float) -> float` → `(base + Σadd) × Πmul`
  - `clear(target: StringName = &"") -> void`

> P0 放在 example 内长熟；P2 跨房协同定型后按 spec §4 移入 `addons/godot-core-kit/`。

- [ ] **Step 1: 建 stub + 写失败测试**

`examples/fortune-mill/systems/kit_modifiers.gd`（stub）:

```gdscript
class_name KitModifiers
extends RefCounted
## 数值修正器栈雏形。target -> { source_id -> {op, value} }。
## value_for(target, base) = (base + Σ add.value) × Π mul.value。
## 脏标缓存聚合结果(add_sum, mul_product),set/remove 置脏,value_for 惰性重算。
## bus 只广播脏标记;真正的求值只在这里发生(spec §5.6 的唯一求值点)。

var _mods: Dictionary = {}    # StringName(target) -> { StringName(source_id) -> {"op":StringName,"value":float} }
var _cache: Dictionary = {}   # StringName(target) -> {"add":float,"mul":float}
var _dirty: Dictionary = {}   # StringName(target) -> bool
```

`test/test_fortune_modifiers.gd`:

```gdscript
extends SceneTree
## KitModifiers headless 断言。运行:godot --headless --path . -s res://test/test_fortune_modifiers.gd
const KitModifiers := preload("res://examples/fortune-mill/systems/kit_modifiers.gd")


func _initialize() -> void:
	var failures := 0
	var m = KitModifiers.new()

	# 1. 空栈 → 返回 base
	if m.value_for(&"gold", 10.0) != 10.0:
		print("FAIL 1: 空栈应返 base 10"); failures += 1

	# 2. 单 add
	m.set_modifier(&"gold", &"a", &"add", 5.0)
	if m.value_for(&"gold", 10.0) != 15.0:
		print("FAIL 2: (10+5) 应 15"); failures += 1

	# 3. 加 mul → (10+5)*2 = 30
	m.set_modifier(&"gold", &"b", &"mul", 2.0)
	if m.value_for(&"gold", 10.0) != 30.0:
		print("FAIL 3: (10+5)*2 应 30"); failures += 1

	# 4. 多 mul 叠乘 → (10+5)*2*1.5 = 45
	m.set_modifier(&"gold", &"c", &"mul", 1.5)
	if m.value_for(&"gold", 10.0) != 45.0:
		print("FAIL 4: (10+5)*2*1.5 应 45"); failures += 1

	# 5. 同 source 覆盖 → a 改 8 → (10+8)*3 = 54
	m.set_modifier(&"gold", &"a", &"add", 8.0)
	if m.value_for(&"gold", 10.0) != 54.0:
		print("FAIL 5: 覆盖后 (10+8)*3 应 54"); failures += 1

	# 6. remove_source(c) → (10+8)*2 = 36
	m.remove_source(&"gold", &"c")
	if m.value_for(&"gold", 10.0) != 36.0:
		print("FAIL 6: 移除 c 后 (10+8)*2 应 36"); failures += 1

	# 7. target 隔离:另一 target 不受影响
	if m.value_for(&"speed", 1.0) != 1.0:
		print("FAIL 7: 未设修正的 target 应返 base"); failures += 1

	# 8. 缓存一致:连续两次 value_for 相同(无副作用)
	var v1 = m.value_for(&"gold", 10.0)
	var v2 = m.value_for(&"gold", 10.0)
	if v1 != v2:
		print("FAIL 8: 连续 value_for 应一致"); failures += 1

	# 9. clear(target)
	m.clear(&"gold")
	if m.value_for(&"gold", 10.0) != 10.0:
		print("FAIL 9: clear 后应返 base"); failures += 1

	if failures == 0:
		print("test_fortune_modifiers: ALL PASS")
		quit(0)
	else:
		print("test_fortune_modifiers: %d FAILURE(S)" % failures)
		quit(1)
```

- [ ] **Step 2: import + 跑测试验证失败**

```bash
godot --headless --path . --import
godot --headless --path . -s res://test/test_fortune_modifiers.gd
```

Expected: FAIL —— `value_for`/`set_modifier`/`remove_source`/`clear` 未定义。

- [ ] **Step 3: 实现方法**

在 `kit_modifiers.gd` 追加:

```gdscript
func set_modifier(target: StringName, source_id: StringName, op: StringName, value: float) -> void:
	if not _mods.has(target):
		_mods[target] = {}
	(_mods[target] as Dictionary)[source_id] = {"op": op, "value": value}
	_dirty[target] = true


func remove_source(target: StringName, source_id: StringName) -> void:
	if _mods.has(target) and (_mods[target] as Dictionary).has(source_id):
		(_mods[target] as Dictionary).erase(source_id)
		_dirty[target] = true


## (base + Σadd) × Πmul。惰性重算聚合并缓存。
func value_for(target: StringName, base: float) -> float:
	_ensure(target)
	var agg: Dictionary = _cache[target]
	return (base + float(agg["add"])) * float(agg["mul"])


func clear(target: StringName = &"") -> void:
	if String(target).is_empty():
		_mods.clear()
		_cache.clear()
		_dirty.clear()
	else:
		_mods.erase(target)
		_cache.erase(target)
		_dirty[target] = true


## 若脏(或未缓存)则重算 target 的 (add_sum, mul_product)。
func _ensure(target: StringName) -> void:
	if _cache.has(target) and not bool(_dirty.get(target, true)):
		return
	var add_sum := 0.0
	var mul_prod := 1.0
	if _mods.has(target):
		for sid in (_mods[target] as Dictionary):
			var mod: Dictionary = _mods[target][sid]
			if mod["op"] == &"add":
				add_sum += float(mod["value"])
			elif mod["op"] == &"mul":
				mul_prod *= float(mod["value"])
	_cache[target] = {"add": add_sum, "mul": mul_prod}
	_dirty[target] = false
```

- [ ] **Step 4: 跑测试验证通过**

```bash
godot --headless --path . -s res://test/test_fortune_modifiers.gd
```

Expected: `test_fortune_modifiers: ALL PASS`

- [ ] **Step 5: Commit**

```bash
git add examples/fortune-mill/systems/kit_modifiers.gd test/test_fortune_modifiers.gd
git commit -m "feat(fortune-mill): KitModifiers 修正器栈雏形(add/mul + source_id + 脏标缓存) + 9 断言"
```

---

## Task 4: 升级定义 schema + 5 条 .tres

**Files:**
- Create: `examples/fortune-mill/defs/dart_upgrade_def.gd`
- Create: `examples/fortune-mill/data/dart_upgrades/sharper_darts.tres`
- Create: `examples/fortune-mill/data/dart_upgrades/golden_tips.tres`
- Create: `examples/fortune-mill/data/dart_upgrades/steady_hand.tres`
- Create: `examples/fortune-mill/data/dart_upgrades/bullseye_training.tres`
- Create: `examples/fortune-mill/data/dart_upgrades/double_dart.tres`

**Interfaces:**
- Consumes: 无
- Produces:
  - `class_name DartUpgradeDef extends Resource`，字段:
    - `id: StringName` / `title: String` / `kind: StringName`（`&"value"`/`&"unlock"`/`&"multi"`，UI 分组用）
    - `target: StringName`（modifier target，`kind==&"unlock"` 时忽略）
    - `op: StringName`（`&"add"`/`&"mul"`）
    - `effect_per_level: float`
    - `base_cost: float` / `growth: float` / `max_level: int`（-1=无上限）
  - 5 条升级定义，`KitDataRegistry.load_dir(&"dart_upgrade", ...)` 可扫入

- [ ] **Step 1: 写 def schema**

`examples/fortune-mill/defs/dart_upgrade_def.gd`:

```gdscript
class_name DartUpgradeDef
extends Resource
## 飞镖房升级定义(.tres 用的 schema)。一条升级 = 对某 modifier target 的一层贡献,
## 或(kind==unlock)解锁靶心档位数。成本几何曲线 base_cost × growth^level。

@export var id: StringName
@export var title: String = ""
## 分类(UI 分组 + DartsRoom 特判):value(产出) / unlock(解锁靶心档) / multi(多镖)
@export var kind: StringName = &"value"
## modifier target(kind==unlock 时忽略):gold_per_dart / darts_per_throw
@export var target: StringName = &"gold_per_dart"
## 修正算子:add(每级 +effect×level) / mul(每级 ×(1+effect)^level)
@export var op: StringName = &"add"
@export var effect_per_level: float = 1.0
@export var base_cost: float = 10.0
@export var growth: float = 1.15
@export var max_level: int = -1
```

- [ ] **Step 2: import 验证 schema 编译**

```bash
godot --headless --path . --import
```

Expected: 无 `SCRIPT ERROR`（`DartUpgradeDef` class_name 注册成功）。

- [ ] **Step 3: 写 5 条 .tres**

`examples/fortune-mill/data/dart_upgrades/sharper_darts.tres`:

```
[gd_resource type="Resource" script_class="DartUpgradeDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://examples/fortune-mill/defs/dart_upgrade_def.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"sharper_darts"
title = "Sharper Darts"
kind = &"value"
target = &"gold_per_dart"
op = &"add"
effect_per_level = 1.0
base_cost = 10.0
growth = 1.15
max_level = -1
```

`examples/fortune-mill/data/dart_upgrades/golden_tips.tres`:

```
[gd_resource type="Resource" script_class="DartUpgradeDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://examples/fortune-mill/defs/dart_upgrade_def.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"golden_tips"
title = "Golden Tips"
kind = &"value"
target = &"gold_per_dart"
op = &"mul"
effect_per_level = 0.5
base_cost = 25.0
growth = 1.3
max_level = -1
```

`examples/fortune-mill/data/dart_upgrades/steady_hand.tres`:

```
[gd_resource type="Resource" script_class="DartUpgradeDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://examples/fortune-mill/defs/dart_upgrade_def.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"steady_hand"
title = "Steady Hand"
kind = &"value"
target = &"gold_per_dart"
op = &"mul"
effect_per_level = 0.25
base_cost = 40.0
growth = 1.25
max_level = -1
```

`examples/fortune-mill/data/dart_upgrades/bullseye_training.tres`:

```
[gd_resource type="Resource" script_class="DartUpgradeDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://examples/fortune-mill/defs/dart_upgrade_def.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"bullseye_training"
title = "Bullseye Training"
kind = &"unlock"
target = &"gold_per_dart"
op = &"add"
effect_per_level = 1.0
base_cost = 50.0
growth = 1.8
max_level = 16
```

`examples/fortune-mill/data/dart_upgrades/double_dart.tres`:

```
[gd_resource type="Resource" script_class="DartUpgradeDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://examples/fortune-mill/defs/dart_upgrade_def.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"double_dart"
title = "Double Dart"
kind = &"multi"
target = &"darts_per_throw"
op = &"add"
effect_per_level = 1.0
base_cost = 100.0
growth = 2.5
max_level = 9
```

> 若 `data/dart_upgrades/.gitkeep` 还在，删掉它（目录已有 .tres）。

- [ ] **Step 4: import 验证 .tres 载入**

```bash
godot --headless --path . --import
```

Expected: 无 `ERROR`/`Failed loading resource`（5 个 .tres 都能解析）。

- [ ] **Step 5: Commit**

```bash
git add examples/fortune-mill/defs/ examples/fortune-mill/data/
git commit -m "feat(fortune-mill): DartUpgradeDef schema + 5 条升级 .tres"
```

---

## Task 5: DartsRoom model

**Files:**
- Create: `examples/fortune-mill/systems/darts_room.gd`
- Test: `test/test_fortune_darts.gd`

**Interfaces:**
- Consumes: `Currency`（Task 2）、`KitModifiers`（Task 3）、`KitDataRegistry`（addons）、`DartUpgradeDef`（Task 4）
- Produces:
  - `class_name DartsRoom extends RefCounted`
  - `DartsRoom.new(currency: Currency, modifiers: KitModifiers, registry: KitDataRegistry)`
  - `const BULLSEYE: Array`（17 档倍率，照抄 spec §5.1）
  - `const DART_BASE := 1.0` / `const BRIBE_COST := 1_000_000.0`
  - `throw() -> Dictionary` → `{"gold": float, "darts": int}`（副作用:currency.add）
  - `buy_upgrade(id: StringName) -> bool`
  - `cost_of(id: StringName) -> float`
  - `level_of(id: StringName) -> int`
  - `can_bribe() -> bool` / `bribe() -> bool`（成功置 `_cleared`）
  - `is_cleared() -> bool`
  - `to_dict() -> Dictionary` / `from_dict(d: Dictionary) -> void`
  - `seed_rng(s: int) -> void`（测试可控随机）

- [ ] **Step 1: 建 stub + 写失败测试**

`examples/fortune-mill/systems/darts_room.gd`（stub）:

```gdscript
class_name DartsRoom
extends RefCounted
## 飞镖房 model(纯数据,不挂节点树)。手动投镖 → 命中靶心档 → 按倍率产 gold;
## 升级经 KitModifiers 聚合;攒够 BRIBE_COST 贿赂守卫 Verminous 过关。

## 靶心 17 档倍率(spec §5.1,照抄,勿改):red..Supernova。
const BULLSEYE := [1.5, 2.0, 3.0, 5.0, 8.0, 12.0, 20.0, 30.0, 50.0, 80.0, 125.0, 200.0, 300.0, 500.0, 800.0, 1200.0, 2500.0]
const DART_BASE := 1.0            ## 单镖基础 gold(未加成)
const BRIBE_COST := 1_000_000.0   ## 贿赂 Verminous 门槛

var _currency: Currency
var _modifiers: KitModifiers
var _registry: KitDataRegistry
var _levels: Dictionary = {}      # StringName(id) -> int(level)
var _bullseye_unlock: int = 0     # 已解锁的额外靶心档数(0 = 只有 tier1 red)
var _cleared: bool = false
var _rng := RandomNumberGenerator.new()


func _init(currency: Currency, modifiers: KitModifiers, registry: KitDataRegistry) -> void:
	_currency = currency
	_modifiers = modifiers
	_registry = registry
	_rng.randomize()
```

`test/test_fortune_darts.gd`:

```gdscript
extends SceneTree
## DartsRoom headless 断言。运行:godot --headless --path . -s res://test/test_fortune_darts.gd
const Currency := preload("res://examples/fortune-mill/systems/currency.gd")
const KitModifiers := preload("res://examples/fortune-mill/systems/kit_modifiers.gd")
const DartsRoom := preload("res://examples/fortune-mill/systems/darts_room.gd")
const DartUpgradeDef := preload("res://examples/fortune-mill/defs/dart_upgrade_def.gd")
const KitDataRegistry := preload("res://addons/godot-core-kit/data/kit_data_registry.gd")


func _make_room(reg) -> Array:
	var cur = Currency.new(0.0)
	var mods = KitModifiers.new()
	var room = DartsRoom.new(cur, mods, reg)
	room.seed_rng(12345)
	return [room, cur, mods]


func _def(id: StringName, kind: StringName, target: StringName, op: StringName, eff: float, base: float, growth: float, maxl: int):
	var d = DartUpgradeDef.new()
	d.id = id; d.kind = kind; d.target = target; d.op = op
	d.effect_per_level = eff; d.base_cost = base; d.growth = growth; d.max_level = maxl
	return d


func _initialize() -> void:
	var failures := 0

	# 注册两条升级:一条 add 值,一条 unlock
	var reg = KitDataRegistry.new()
	reg.register(&"dart_upgrade", &"sharper", _def(&"sharper", &"value", &"gold_per_dart", &"add", 1.0, 10.0, 1.15, -1))
	reg.register(&"dart_upgrade", &"unlock", _def(&"unlock", &"unlock", &"gold_per_dart", &"add", 1.0, 50.0, 1.8, 16))

	# 1. 靶心表 17 档 + 首尾值
	if DartsRoom.BULLSEYE.size() != 17 or DartsRoom.BULLSEYE[0] != 1.5 or DartsRoom.BULLSEYE[16] != 2500.0:
		print("FAIL 1: 靶心表应 17 档 1.5..2500"); failures += 1

	# 2. throw 产 gold > 0 且入账
	var t = _make_room(reg)
	var room = t[0]; var cur = t[1]
	var r = room.throw()
	if r["gold"] <= 0.0 or cur.get_amount() != r["gold"]:
		print("FAIL 2: throw 应产正 gold 并入账"); failures += 1

	# 3. 初始仅 1 档(未解锁)时命中倍率恒为 tier1=1.5
	var t3 = _make_room(reg)
	var room3 = t3[0]; var cur3 = t3[1]
	room3.throw()
	# 单镖 base=1.0 × 1.5 = 1.5(无值升级)
	if absf(cur3.get_amount() - 1.5) > 0.0001:
		print("FAIL 3: 初始单镖应 1.0×1.5=1.5,实际 %s" % cur3.get_amount()); failures += 1

	# 4. cost_of:level0 = base_cost
	var t4 = _make_room(reg)
	var room4 = t4[0]
	if absf(room4.cost_of(&"sharper") - 10.0) > 0.0001:
		print("FAIL 4: level0 成本应 base 10"); failures += 1

	# 5. buy_upgrade:钱不够 → false
	if room4.buy_upgrade(&"sharper"):
		print("FAIL 5: 没钱应买不了"); failures += 1

	# 6. 给钱 → 买 sharper → level1 + modifier 生效(gold_per_dart base+1)
	var t6 = _make_room(reg)
	var room6 = t6[0]; var cur6 = t6[1]; var mods6 = t6[2]
	cur6.add(100.0)
	if not room6.buy_upgrade(&"sharper") or room6.level_of(&"sharper") != 1:
		print("FAIL 6a: 买 sharper 应成功 level1"); failures += 1
	# gold_per_dart base=DART_BASE=1.0,加 +1 → value_for=2.0
	if absf(mods6.value_for(&"gold_per_dart", DartsRoom.DART_BASE) - 2.0) > 0.0001:
		print("FAIL 6b: sharper 后 gold_per_dart 应 2.0"); failures += 1
	# 扣款:100 - 10 = 90
	if absf(cur6.get_amount() - 90.0) > 0.0001:
		print("FAIL 6c: 扣款后应 90"); failures += 1

	# 7. 第二级成本 = 10 × 1.15 = 11.5
	if absf(room6.cost_of(&"sharper") - 11.5) > 0.0001:
		print("FAIL 7: level1 成本应 11.5,实际 %s" % room6.cost_of(&"sharper")); failures += 1

	# 8. unlock 升级抬高解锁档数
	var t8 = _make_room(reg)
	var room8 = t8[0]; var cur8 = t8[1]
	cur8.add(1000.0)
	room8.buy_upgrade(&"unlock")
	if room8.max_tier() != 2:  # 初始 1 + 解锁 1
		print("FAIL 8: unlock 一级后 max_tier 应 2,实际 %d" % room8.max_tier()); failures += 1

	# 9. can_bribe / bribe
	var t9 = _make_room(reg)
	var room9 = t9[0]; var cur9 = t9[1]
	if room9.can_bribe() or room9.bribe():
		print("FAIL 9a: 未达门槛不能贿赂"); failures += 1
	cur9.set_amount(DartsRoom.BRIBE_COST)
	if not room9.can_bribe() or not room9.bribe() or not room9.is_cleared():
		print("FAIL 9b: 达门槛应能贿赂并 cleared"); failures += 1

	# 10. to_dict/from_dict 往返:levels + cleared + modifier 重建
	var t10 = _make_room(reg)
	var room10 = t10[0]; var cur10 = t10[1]
	cur10.add(100.0)
	room10.buy_upgrade(&"sharper")
	var snap = room10.to_dict()
	var t10b = _make_room(reg)
	var room10b = t10b[0]; var mods10b = t10b[2]
	room10b.from_dict(snap)
	if room10b.level_of(&"sharper") != 1:
		print("FAIL 10a: from_dict 应恢复 level1"); failures += 1
	if absf(mods10b.value_for(&"gold_per_dart", DartsRoom.DART_BASE) - 2.0) > 0.0001:
		print("FAIL 10b: from_dict 应重建 modifier(gold_per_dart=2.0)"); failures += 1

	if failures == 0:
		print("test_fortune_darts: ALL PASS")
		quit(0)
	else:
		print("test_fortune_darts: %d FAILURE(S)" % failures)
		quit(1)
```

- [ ] **Step 2: import + 跑测试验证失败**

```bash
godot --headless --path . --import
godot --headless --path . -s res://test/test_fortune_darts.gd
```

Expected: FAIL —— `throw`/`buy_upgrade`/`cost_of`/`max_tier`/`bribe`/`to_dict` 等未定义。

- [ ] **Step 3: 实现方法**

在 `darts_room.gd` 追加:

```gdscript
func seed_rng(s: int) -> void:
	_rng.seed = s


## 当前可命中的最高靶心档(1-based,含)。初始 1(仅 red),每级 unlock +1,封顶 17。
func max_tier() -> int:
	return clampi(1 + _bullseye_unlock, 1, BULLSEYE.size())


func level_of(id: StringName) -> int:
	return int(_levels.get(id, 0))


## 下一级成本 = base_cost × growth^当前level。
func cost_of(id: StringName) -> float:
	var def = _registry.get_def(&"dart_upgrade", id)
	if def == null:
		return INF
	return float(def.base_cost) * pow(float(def.growth), level_of(id))


## 投一次(含多镖)。每镖:gold_per_dart 聚合值 × 命中靶心倍率。返回 {gold, darts}。
func throw() -> Dictionary:
	var darts := maxi(1, int(_modifiers.value_for(&"darts_per_throw", 1.0)))
	var per_dart := _modifiers.value_for(&"gold_per_dart", DART_BASE)
	var total := 0.0
	for _i in darts:
		total += per_dart * BULLSEYE[_roll_tier() - 1]
	_currency.add(total)
	return {"gold": total, "darts": darts}


## 加权随机命中档(1..max_tier);低档常见、高档稀有(权重 1/tier^2)。
func _roll_tier() -> int:
	var top := max_tier()
	if top <= 1:
		return 1
	var weights := []
	var sum := 0.0
	for tier in range(1, top + 1):
		var w := 1.0 / float(tier * tier)
		weights.append(w)
		sum += w
	var pick := _rng.randf() * sum
	var acc := 0.0
	for i in range(weights.size()):
		acc += weights[i]
		if pick <= acc:
			return i + 1
	return top


## 买一级升级。买不起 / 已满级 / 无此 def → false。
func buy_upgrade(id: StringName) -> bool:
	var def = _registry.get_def(&"dart_upgrade", id)
	if def == null:
		return false
	var lvl := level_of(id)
	if def.max_level >= 0 and lvl >= def.max_level:
		return false
	if not _currency.spend(cost_of(id)):
		return false
	_levels[id] = lvl + 1
	_apply_upgrade(def, lvl + 1)
	return true


## 把某升级在 level 时的效果落到 modifier(unlock 类改解锁档数)。覆盖式(同 source_id)。
func _apply_upgrade(def, level: int) -> void:
	if def.kind == &"unlock":
		_bullseye_unlock = level
		return
	var v := 0.0
	if def.op == &"add":
		v = float(def.effect_per_level) * level
	else:  # mul:每级 ×(1+effect)
		v = pow(1.0 + float(def.effect_per_level), level)
	_modifiers.set_modifier(def.target, def.id, def.op, v)


func can_bribe() -> bool:
	return _currency.get_amount() >= BRIBE_COST


## 达门槛则过关(P0 不扣货币,过关即本切片终点)。
func bribe() -> bool:
	if not can_bribe():
		return false
	_cleared = true
	return true


func is_cleared() -> bool:
	return _cleared


## 只存权威状态(levels/cleared);modifier 与 bullseye_unlock 是派生值,from_dict 重算。
func to_dict() -> Dictionary:
	var lv := {}
	for id in _levels:
		lv[String(id)] = int(_levels[id])   # JSON key 统一 String
	return {"levels": lv, "cleared": _cleared}


func from_dict(d: Dictionary) -> void:
	_levels.clear()
	_bullseye_unlock = 0
	_cleared = bool(d.get("cleared", false))
	var lv: Dictionary = d.get("levels", {})
	for k in lv:
		var id := StringName(k)
		var level := int(lv[k])
		_levels[id] = level
		var def = _registry.get_def(&"dart_upgrade", id)
		if def != null:
			_apply_upgrade(def, level)
```

- [ ] **Step 4: 跑测试验证通过**

```bash
godot --headless --path . -s res://test/test_fortune_darts.gd
```

Expected: `test_fortune_darts: ALL PASS`

- [ ] **Step 5: Commit**

```bash
git add examples/fortune-mill/systems/darts_room.gd test/test_fortune_darts.gd
git commit -m "feat(fortune-mill): DartsRoom model(17 档靶心/加权命中/升级聚合/贿赂/存档) + 10 断言"
```

---

## Task 6: FortuneMill autoload + 存档 + 接线

**Files:**
- Create: `examples/fortune-mill/systems/fortune_state.gd`
- Modify: `project.godot`（`[autoload]` 段加 `FortuneMill`）

**Interfaces:**
- Consumes: `Currency` / `KitModifiers` / `DartsRoom`（前序）、`KitDataRegistry`（addons）、`CoreKit.saves` / `.bus` / `.log`
- Produces（autoload 全局名 `FortuneMill`）:
  - `var currency: Currency` / `var modifiers: KitModifiers` / `var darts: DartsRoom` / `var registry: KitDataRegistry`
  - `do_throw() -> Dictionary`
  - `buy_dart_upgrade(id: StringName) -> bool`
  - `bribe_guard() -> bool`
  - `can_bribe() -> bool`
  - `save_game() -> void` / `load_game() -> void`
  - `to_dict() -> Dictionary` / `from_dict(d: Dictionary) -> void`
  - bus 事件:`fortune:currency_changed`(payload=float 余额) / `fortune:upgrade_purchased`(payload=id String) / `fortune:room_cleared`(payload="darts")

- [ ] **Step 1: 写 autoload**

`examples/fortune-mill/systems/fortune_state.gd`:

```gdscript
extends Node
## FortuneMill —— 状态支柱 autoload(唯一挂树的游戏级节点)。装配纯数据层、
## 暴露命令方法、接线存档与 bus。经济逻辑在 darts(DartsRoom)里,本节点只转发 + 广播脏标记。
## autoload 顺序必须在 CoreKit 之后(依赖 CoreKit.saves/.bus/.log)。

const SAVE_SLOT := "fortune"
const UPGRADES_DIR := "res://examples/fortune-mill/data/dart_upgrades"

var currency: Currency
var modifiers: KitModifiers
var registry: KitDataRegistry
var darts: DartsRoom


func _ready() -> void:
	currency = Currency.new(1.0)          # 开局 $1 gold(spec §5.1)
	modifiers = KitModifiers.new()
	registry = KitDataRegistry.new()
	var n := registry.load_dir(&"dart_upgrade", UPGRADES_DIR)
	darts = DartsRoom.new(currency, modifiers, registry)
	if CoreKit.saves.has_slot(SAVE_SLOT):
		load_game()
	CoreKit.log.info("[Fortune] ready: %d upgrades, gold=%s" % [n, Currency.format(currency.get_amount())])


## --- 命令(表现层唯一入口) ---

func do_throw() -> Dictionary:
	var r := darts.throw()
	CoreKit.bus.publish("fortune:currency_changed", currency.get_amount())
	return r


func buy_dart_upgrade(id: StringName) -> bool:
	if darts.buy_upgrade(id):
		CoreKit.bus.publish("fortune:upgrade_purchased", String(id))
		CoreKit.bus.publish("fortune:currency_changed", currency.get_amount())
		return true
	return false


func bribe_guard() -> bool:
	if darts.bribe():
		CoreKit.bus.publish("fortune:room_cleared", "darts")
		save_game()
		return true
	return false


func can_bribe() -> bool:
	return darts.can_bribe()


## --- 存档(只存 Dictionary,SaveManager 拒 Object) ---

func to_dict() -> Dictionary:
	return {"currency": currency.get_amount(), "darts": darts.to_dict()}


func from_dict(d: Dictionary) -> void:
	currency.set_amount(float(d.get("currency", 1.0)))
	darts.from_dict(d.get("darts", {}))


func save_game() -> void:
	CoreKit.saves.save(SAVE_SLOT, to_dict())


func load_game() -> void:
	from_dict(CoreKit.saves.load(SAVE_SLOT))
```

- [ ] **Step 2: project.godot 加 autoload**

Modify `project.godot` `[autoload]` 段（在 `CoreKit` 行后加一行）:

找到:
```
CoreKit="*res://addons/godot-core-kit/core_kit.gd"
_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"
```
改为:
```
CoreKit="*res://addons/godot-core-kit/core_kit.gd"
FortuneMill="*res://examples/fortune-mill/systems/fortune_state.gd"
_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"
```

- [ ] **Step 3: headless 验证 autoload 不崩 + 存档往返**

写一段临时验证脚本 `test/tmp_fortune_state.gd`:

```gdscript
extends SceneTree
## 临时验证(跑完即删):纯数据层装配 + 升级载入 + modifier 生效。
## fortune_state.gd 本体依赖 CoreKit autoload,而 `-s` 脚本模式无 autoload,
## 故这里只手动装配纯数据层(Currency/KitModifiers/DartsRoom/registry)校验;
## 完整 autoload(含 CoreKit.* 接线)在 Task 7 跑 world.tscn 时端到端验证。
func _initialize() -> void:
	var Currency := load("res://examples/fortune-mill/systems/currency.gd")
	var KitModifiers := load("res://examples/fortune-mill/systems/kit_modifiers.gd")
	var DartsRoom := load("res://examples/fortune-mill/systems/darts_room.gd")
	var KitDataRegistry := load("res://addons/godot-core-kit/data/kit_data_registry.gd")
	var reg = KitDataRegistry.new()
	var n = reg.load_dir(&"dart_upgrade", "res://examples/fortune-mill/data/dart_upgrades")
	var cur = Currency.new(1.0)
	var mods = KitModifiers.new()
	var room = DartsRoom.new(cur, mods, reg)
	print("[tmp] loaded upgrades = %d (应 5)" % n)
	cur.add(1000.0)
	room.buy_upgrade(&"sharper_darts")
	print("[tmp] after buy sharper_darts, gold_per_dart = %s (应 2.0)" % mods.value_for(&"gold_per_dart", DartsRoom.DART_BASE))
	quit(0)
```

Run:
```bash
godot --headless --path . --import
godot --headless --path . -s res://test/tmp_fortune_state.gd
```

Expected: `[tmp] loaded upgrades = 5 (应 5)` 且 `gold_per_dart = 2.0`。确认后删除临时脚本:
```bash
rm test/tmp_fortune_state.gd
```

> 完整的 autoload（含 `CoreKit.*` 接线）在 Task 7 通过跑 `world.tscn`（有 autoload 环境）端到端验证。

- [ ] **Step 4: Commit**

```bash
git add examples/fortune-mill/systems/fortune_state.gd project.godot
git commit -m "feat(fortune-mill): FortuneMill autoload(装配/命令/存档/bus 脏标记) + 接线 project.godot"
```

---

## Task 7: 表现层 world + HUD + FORTUNE_SMOKE

**Files:**
- Create: `examples/fortune-mill/scenes/world.gd`
- Create: `examples/fortune-mill/scenes/world.tscn`
- Modify: `project.godot`（`run/main_scene`）

**Interfaces:**
- Consumes: `FortuneMill` autoload、`Currency.format`、`CoreKit.bus`
- Produces: 可玩场景 + `[Fortune][SMOKE] PASS/FAIL` 端到端自测

- [ ] **Step 1: 写 world.gd（表现层 + smoke）**

`examples/fortune-mill/scenes/world.gd`:

```gdscript
extends Node
## 飞镖房表现层根 + FORTUNE_SMOKE headless 自测入口。
## UI 只读 FortuneMill 模型 + 发命令;订阅 bus 脏标记刷新,不持有权威数值。

const SMOKE_MAX_STEPS := 500000

var _gold_label: Label
var _status_label: Label
var _bribe_button: Button
var _upgrade_buttons: Dictionary = {}   # StringName(id) -> Button


func _ready() -> void:
	if OS.get_environment("FORTUNE_SMOKE") == "1":
		_run_smoke()
		return
	_build_ui()
	CoreKit.bus.subscribe("fortune:currency_changed", _on_dirty)
	CoreKit.bus.subscribe("fortune:upgrade_purchased", _on_dirty)
	CoreKit.bus.subscribe("fortune:room_cleared", _on_cleared)
	_refresh()


## --- FORTUNE_SMOKE:自动玩闭环,验证 $1 → 100 万 → 贿赂过关 ---

func _run_smoke() -> void:
	var fm = FortuneMill   # autoload;不用 := 以免静态类型退化为 Node
	var steps := 0
	while not fm.can_bribe() and steps < SMOKE_MAX_STEPS:
		fm.do_throw()
		if steps % 20 == 0:
			_smoke_buy_round(fm)
		steps += 1
	var gold_str := Currency.format(fm.currency.get_amount())
	var ok: bool = fm.can_bribe() and fm.bribe_guard()
	CoreKit.saves.delete_slot(fm.SAVE_SLOT)   # smoke 自清理,不留存档污染后续运行
	if ok:
		print("[Fortune][SMOKE] PASS gold=%s steps=%d cleared=%s" % [gold_str, steps, fm.darts.is_cleared()])
		get_tree().quit(0)
	else:
		print("[Fortune][SMOKE] FAIL gold=%s steps=%d" % [gold_str, steps])
		get_tree().quit(1)


## 每轮把每条买得起的升级各买一级(均衡成长,推动数值爬升)。
func _smoke_buy_round(fm) -> void:
	for id in fm.registry.ids(&"dart_upgrade", true):
		fm.buy_dart_upgrade(id)


## --- 可玩 UI(代码构建,P0 无美术) ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2(16, 16)
	layer.add_child(root)

	_gold_label = Label.new()
	root.add_child(_gold_label)

	_status_label = Label.new()
	root.add_child(_status_label)

	var throw_btn := Button.new()
	throw_btn.text = "投镖 (Throw)"
	throw_btn.pressed.connect(func(): FortuneMill.do_throw())
	root.add_child(throw_btn)

	root.add_child(HSeparator.new())
	var up_title := Label.new()
	up_title.text = "— 升级 —"
	root.add_child(up_title)

	for id in FortuneMill.registry.ids(&"dart_upgrade", true):
		var btn := Button.new()
		btn.pressed.connect(func(): FortuneMill.buy_dart_upgrade(id))
		root.add_child(btn)
		_upgrade_buttons[id] = btn

	root.add_child(HSeparator.new())
	_bribe_button = Button.new()
	_bribe_button.text = "贿赂 Verminous (需 1M gold)"
	_bribe_button.pressed.connect(func(): FortuneMill.bribe_guard())
	root.add_child(_bribe_button)


func _on_dirty(_payload) -> void:
	_refresh()


func _on_cleared(_payload) -> void:
	_status_label.text = "★ 已贿赂 Verminous,飞镖房通关! ★"


func _refresh() -> void:
	if _gold_label == null:
		return
	_gold_label.text = "Gold: %s" % Currency.format(FortuneMill.currency.get_amount())
	for id in _upgrade_buttons:
		var def = FortuneMill.registry.get_def(&"dart_upgrade", id)
		var lvl := FortuneMill.darts.level_of(id)
		var cost := FortuneMill.darts.cost_of(id)
		var btn: Button = _upgrade_buttons[id]
		btn.text = "%s  Lv.%d  (%s gold)" % [def.title, lvl, Currency.format(cost)]
		btn.disabled = not FortuneMill.currency.can_afford(cost)
	_bribe_button.disabled = not FortuneMill.can_bribe()
```

- [ ] **Step 2: 写 world.tscn**

`examples/fortune-mill/scenes/world.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://examples/fortune-mill/scenes/world.gd" id="1"]

[node name="World" type="Node"]
script = ExtResource("1")
```

> 不带 uid，Godot 首次 import 会自动补 `.uid`（无害 warning）。

- [ ] **Step 3: project.godot 改 main_scene**

Modify `project.godot`：找到
```
run/main_scene="res://demo/demo.tscn"
```
改为
```
run/main_scene="res://examples/fortune-mill/scenes/world.tscn"
```

- [ ] **Step 4: 跑 FORTUNE_SMOKE 端到端验证**

```bash
godot --headless --path . --import
FORTUNE_SMOKE=1 godot --headless --path . res://examples/fortune-mill/scenes/world.tscn --quit-after 600
```

Expected: 输出含 `[Fortune][SMOKE] PASS`，`cleared=true`，且退出码 0。

> 若打印 FAIL（500000 步内没爬到 1M）：说明初始数值太保守。**只调 .tres 数值**（提高 `effect_per_level` 或降 `growth`），不改逻辑，重跑直到 PASS。数值平衡本就是 P5 的活，P0 只需 smoke 能闭环。

> 存档副作用已由 `_run_smoke` 自清理（退出前 `CoreKit.saves.delete_slot`），smoke 跑完不会残留 `user://saves/fortune.json`，无需手动删。

- [ ] **Step 5: Commit**

```bash
git add examples/fortune-mill/scenes/ project.godot
git commit -m "feat(fortune-mill): world 表现层 + 代码 HUD + FORTUNE_SMOKE 端到端自测 + main_scene 切换"
```

---

## Task 8: 登记测试进 run_all + 全量回归

**Files:**
- Modify: `test/run_all.ps1`（`$tests` 数组加 3 个 fortune 测试）

**Interfaces:**
- Consumes: `test_fortune_currency` / `test_fortune_modifiers` / `test_fortune_darts`
- Produces: kit 门 `run_all.ps1` 覆盖 fortune 数据层单测

- [ ] **Step 1: 把 3 个测试加进 run_all.ps1**

Modify `test/run_all.ps1`：找到 `$tests = @(...)` 数组，在末尾 `'test_kit_data_registry')` 前加入三项。改为:

```powershell
$tests = @('test_log','test_event_bus','test_scene_manager','test_object_pool',
  'test_save_manager','test_settings','test_frame_scheduler','test_state_machine',
  'test_input_manager','test_audio_manager','test_resource_manager','test_kit_context','test_core_kit','test_dev_console','test_locale_manager','test_rebind','test_transition','test_ui_stack','test_layer_manager','test_game_clock','test_kit_inventory','test_kit_data_registry',
  'test_fortune_currency','test_fortune_modifiers','test_fortune_darts')
```

> 注意:`run_all.ps1` 的 demo smoke 段跑的是 `res://demo/demo.tscn`（kit 自带 demo，未受本 P0 影响）。main_scene 虽已切到 fortune world，但 run_all 显式传 demo.tscn，故 kit 门回归不受影响。

- [ ] **Step 2: 跑全量 run_all 验证**

```bash
powershell -File test/run_all.ps1
```

Expected: 末行 `=== SUMMARY FAILS=0 ===`，其中 `test_fortune_currency` / `test_fortune_modifiers` / `test_fortune_darts` 三行均 `pass=True OK`。

- [ ] **Step 3: 复跑 FORTUNE_SMOKE 确认无回归**

```bash
FORTUNE_SMOKE=1 godot --headless --path . res://examples/fortune-mill/scenes/world.tscn --quit-after 600
```

Expected: `[Fortune][SMOKE] PASS`

- [ ] **Step 4: Commit**

```bash
git add test/run_all.ps1
git commit -m "test(fortune-mill): 3 个 fortune 数据层单测登记进 kit 门 run_all"
```

---

## 完成定义（P0 验收）

- [ ] `powershell -File test/run_all.ps1` → `FAILS=0`（含 3 个 fortune 单测）
- [ ] `FORTUNE_SMOKE=1 godot --headless ... world.tscn` → `[Fortune][SMOKE] PASS`，`cleared=true`
- [ ] 编辑器运行 `world.tscn`：能点投镖攒 gold、买升级、攒够 100 万点贿赂过关（手动确认，可选）
- [ ] 全程无 GDExtension、无裸 float 货币运算、经济逻辑不挂节点树、bus 仅广播脏标记

## 下一阶段衔接（不在本计划内）

P1 起接 `ticker` 做自动投镖 + 新增 `KitOffline` 离线结算（spec §5.7、§9）。P2 加刮刮乐 + 跨房协同时，`KitModifiers` 定型后按 spec §4 移入 `addons/godot-core-kit/`。
