# Fortune Mill P1 自动化 + 离线结算 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 飞镖房买到 Rattling Gunner 自动投后数据层持续产 gold(`ticker` 驱动),关游戏再回来按墙钟差结算离线收益(封顶 8h、时间回拨按 0)。

**Architecture:** 沿用 P0 的 headless-first 数据/表现分离。新增一个确定性期望产率 `DartsRoom.auto_gold_rate()`——在线 `produce(dt)` 与离线 `KitOffline.settle()` **共用同一产率**,保证「离线 1h ≈ 在线 1h」。KitOffline 是纯 `RefCounted`(照 KitModifiers 先例在 `examples/fortune-mill/systems/` 内孵化,P2+ 定型后才由 kit cycle 移入 `addons/`,**本分支绝不碰 addons/main**)。`FortuneMill` autoload 用 `CoreKit.ticker.every_n` 挂降频 tick + 周期自动存,`load_game` 时做离线结算;autoload 接线只能靠 `FORTUNE_SMOKE` 整项目验证(`-s` 脚本模式不实例化 autoload)。

**Tech Stack:** Godot 4.7 mono GDScript;godot-core-kit `CoreKit.ticker`(FrameScheduler)/`CoreKit.saves`(SaveManager)/`CoreKit.bus`;纯 GDScript,无 GDExtension。

## Global Constraints

- **headless-first 数据/表现分离**:经济逻辑跑纯 `RefCounted`(`systems/`),不挂节点树、与 UI 是否可见无关;表现层只读模型发命令,永不持有权威数值。
- **不出现裸 float 货币运算**:一切经 `Currency`(`add/spend/get_amount/set_amount`)。
- **`bus` 只广播脏标记,绝不做数值求值**。
- **不引入 GDExtension / 大数库**(撞多架构 .so 坑,断 Web/Android 导出)。
- **存档只存 Dictionary**(`SaveManager` 拒 Object/Callable/Resource);只存权威状态(货币、升级等级、`last_seen` 时间戳),不存派生值(modifier 结果 `from_dict` 重算)。
- **离线结算**:墙钟差 `Time.get_unix_time_from_system()`;**封顶 8 小时**(28800s);系统时间回拨(`now < last_seen`)按 **0** 结算;离线用**确定性期望值**(不 roll RNG)。
- **靶心 17 档倍率表 `BULLSEYE` 逐字不动**(P0 已定,`_roll_tier` 与 `_expected_bullseye` 同分布 权重 `1/tier^2`)。
- **分支纪律**:本 example 全部产物留在 `examples/fortune-mill/` + kit `test/`(fortune 数据层单测),**不改 `addons/`、不并 main**。
- **测试落点**:KitOffline / DartsRoom 纯类单测进 kit 门 `test/run_all.ps1`(grep `ALL PASS`);`FORTUNE_SMOKE` 端到端独立于 kit 门(照 farm-sim 约定)。

---

## File Structure

- `examples/fortune-mill/systems/kit_offline.gd` — **新建**。`class_name KitOffline`,纯离线结算器(静态 `settle`)。
- `examples/fortune-mill/systems/darts_room.gd` — **改**。加 `auto_gold_rate()` / `_expected_bullseye()` / `produce(dt)`。
- `examples/fortune-mill/data/dart_upgrades/rattling_gunner.tres` — **新建**。自动投升级(kind=automation,target=throws_per_sec)。
- `examples/fortune-mill/systems/fortune_state.gd` — **改**。`ticker` 接线 tick + 周期自动存 + `last_seen` 存档 + `settle_offline` + `_notification` 退出存。
- `examples/fortune-mill/scenes/world.gd` — **改**。HUD 加自动产率行 + 离线回归横幅(从 `FortuneMill.offline_report` 拉取)。
- `test/test_fortune_offline.gd` — **新建**。KitOffline 纯数学单测(SceneTree)。
- `test/test_fortune_darts.gd` — **改**。扩 `auto_gold_rate`/`produce` 断言。
- `test/run_all.ps1` — **改**。`$tests` 加 `test_fortune_offline`。
- `examples/fortune-mill/docs/README.md` — **改**。补 P1 自动化/离线段。

---

### Task 1: KitOffline 离线结算器 + 纯单测

**Files:**
- Create: `examples/fortune-mill/systems/kit_offline.gd`
- Create: `test/test_fortune_offline.gd`

**Interfaces:**
- Produces: `KitOffline.settle(last_seen: float, now: float, rate_per_sec: float, cap_seconds := 28800.0) -> Dictionary`,返回 `{earned: float, elapsed: float, capped: bool, rolled_back: bool}`。静态方法,纯函数,不碰墙钟(`now` 由调用方传入),便于确定性测试。

- [ ] **Step 1: 写失败测试** `test/test_fortune_offline.gd`

```gdscript
extends SceneTree
## KitOffline 纯数学单测:墙钟差 × 产率、封顶 8h、时间回拨按 0、零产率、无上次时间戳。

const KitOfflineScript = preload("res://examples/fortune-mill/systems/kit_offline.gd")


func _initialize() -> void:
	var day := 86400.0
	var base := 1_000_000.0   # 任意墙钟基准秒

	# 1) 正常结算:1 小时 × 10 gold/s = 36000
	var r := KitOfflineScript.settle(base, base + 3600.0, 10.0)
	assert(is_equal_approx(r.earned, 36000.0), "1h×10/s=36000, got %f" % r.earned)
	assert(is_equal_approx(r.elapsed, 3600.0), "elapsed=3600")
	assert(r.capped == false, "1h 不封顶")
	assert(r.rolled_back == false, "正常不回拨")

	# 2) 封顶 8 小时:过 10 小时只计 8 小时
	var r2 := KitOfflineScript.settle(base, base + 10.0 * 3600.0, 10.0)
	assert(is_equal_approx(r2.elapsed, 28800.0), "封顶 8h=28800, got %f" % r2.elapsed)
	assert(is_equal_approx(r2.earned, 288000.0), "8h×10/s=288000, got %f" % r2.earned)
	assert(r2.capped == true, "超 8h 应 capped")

	# 3) 恰好 8 小时边界:不算 capped(<= cap)
	var r3 := KitOfflineScript.settle(base, base + 28800.0, 1.0)
	assert(is_equal_approx(r3.elapsed, 28800.0), "边界 elapsed=28800")
	assert(r3.capped == false, "恰好 8h 不算超")

	# 4) 时间回拨:now < last → earned 0 + rolled_back
	var r4 := KitOfflineScript.settle(base, base - 500.0, 10.0)
	assert(is_equal_approx(r4.earned, 0.0), "回拨 earned=0, got %f" % r4.earned)
	assert(r4.rolled_back == true, "回拨应标记")
	assert(r4.capped == false, "回拨非封顶")

	# 5) 零/负产率:无自动化 → earned 0(但 elapsed 照算)
	var r5 := KitOfflineScript.settle(base, base + 3600.0, 0.0)
	assert(is_equal_approx(r5.earned, 0.0), "零产率 earned=0")
	assert(is_equal_approx(r5.elapsed, 3600.0), "零产率 elapsed 照算")

	# 6) 无上次时间戳(last_seen<=0):首次运行,earned 0、不回拨
	var r6 := KitOfflineScript.settle(0.0, base, 10.0)
	assert(is_equal_approx(r6.earned, 0.0), "无时间戳 earned=0")
	assert(r6.rolled_back == false, "无时间戳非回拨")

	# 7) now == last(无时间流逝):earned 0、不回拨
	var r7 := KitOfflineScript.settle(base, base, 10.0)
	assert(is_equal_approx(r7.earned, 0.0), "now==last earned=0")
	assert(r7.rolled_back == false, "now==last 非回拨")

	# 8) 自定义封顶(day 天上限)覆盖默认 8h
	var r8 := KitOfflineScript.settle(base, base + 10.0 * 3600.0, 1.0, day)
	assert(is_equal_approx(r8.elapsed, 36000.0), "自定义 cap=day 时 10h 全计, got %f" % r8.elapsed)

	print("test_fortune_offline: ALL PASS")
	quit(0)
```

- [ ] **Step 2: 跑测试确认失败(类不存在)**

```
godot --headless --path . -s res://test/test_fortune_offline.gd
```
Expected: 报错找不到 `kit_offline.gd` / 断言前崩溃(FAIL)。

- [ ] **Step 3: 实现** `examples/fortune-mill/systems/kit_offline.gd`

```gdscript
class_name KitOffline
extends RefCounted
## 离线结算器(纯函数,不挂树、无 autoload 依赖)。给定上次在线墙钟、当前墙钟、
## 每秒产率、封顶秒数,算离线收益;检测系统时间回拨(now<last → 按 0,防作弊)。
##
## 当前恒定产率:离线期间进程关闭、玩家无操作,产率不变,故 elapsed×rate 即精确解。
## 「跨升级边界分段积分」(spec §4)是多房/在线追赶的未来扩展,P0/P1 单房用不到(YAGNI)。
##
## 与 DartsRoom.auto_gold_rate() 配合:在线 produce 与离线 settle 同用一个确定性期望产率,
## 保证「离线 1h ≈ 在线 1h」。孵化于 example,P2+ 定型后再随 kit cycle 移入 addons/。

const DEFAULT_CAP_SECONDS := 28800.0   # 封顶 8 小时(spec §5.7)


## 结算离线收益。
##   last_seen / now:Unix 秒(Time.get_unix_time_from_system())。
##   rate_per_sec:每秒产出;<=0 → earned 0。
##   cap_seconds:计入的最大秒数;<=0 → 用 DEFAULT_CAP_SECONDS。
## 返回 {earned, elapsed, capped, rolled_back}。
static func settle(last_seen: float, now: float, rate_per_sec: float, cap_seconds: float = DEFAULT_CAP_SECONDS) -> Dictionary:
	var cap: float = cap_seconds if cap_seconds > 0.0 else DEFAULT_CAP_SECONDS
	# 无有效上次时间戳(首次运行)或时间回拨:不结算
	if last_seen <= 0.0 or now <= last_seen:
		return {"earned": 0.0, "elapsed": 0.0, "capped": false, "rolled_back": now < last_seen}
	var raw := now - last_seen
	var elapsed: float = minf(raw, cap)
	var earned := 0.0
	if rate_per_sec > 0.0:
		earned = elapsed * rate_per_sec
	return {"earned": earned, "elapsed": elapsed, "capped": raw > cap, "rolled_back": false}
```

- [ ] **Step 4: 跑测试确认通过**

```
godot --headless --path . -s res://test/test_fortune_offline.gd
```
Expected: `test_fortune_offline: ALL PASS`,exit 0。

> 注:若首跑因 `class_name KitOffline` 未进类缓存报错,先 `godot --headless --path . --import` 再跑。

- [ ] **Step 5: Commit**

```
git add examples/fortune-mill/systems/kit_offline.gd examples/fortune-mill/systems/kit_offline.gd.uid test/test_fortune_offline.gd test/test_fortune_offline.gd.uid
git commit -m "feat(fortune-mill): KitOffline 离线结算器 + 纯数学单测(P1)"
```
> `.uid` sidecar 由 godot import 生成,本仓库约定一并提交;若 import 未生成 `.uid` 则省略对应文件。

---

### Task 2: DartsRoom 自动产率 + produce(dt) + Rattling Gunner 升级

**Files:**
- Modify: `examples/fortune-mill/systems/darts_room.gd`
- Create: `examples/fortune-mill/data/dart_upgrades/rattling_gunner.tres`
- Modify: `test/test_fortune_darts.gd`

**Interfaces:**
- Consumes: `KitModifiers.value_for(target, base)`、既有 `max_tier()` / `BULLSEYE` / `DART_BASE`。
- Produces: `DartsRoom.auto_gold_rate() -> float`(确定性期望 gold/秒,无自动化时 0)、`DartsRoom.produce(dt: float) -> float`(按产率加 gold,返回本次新增)、新 modifier target `&"throws_per_sec"`(基值 0)。

- [ ] **Step 1: 在 `test/test_fortune_darts.gd` 末尾断言前追加自动化测试**

先读现有文件,在其 `print("...: ALL PASS")`/`quit(0)` **之前**插入以下断言块(沿用该文件已装配的 `room`/`modifiers`/`registry`/`currency` 变量名;若变量名不同则按实际改名)。若现有测试未装配到可复用的局部变量,则在文件内新建一段独立装配:

```gdscript
	# --- P1 自动化产率 ---
	# 无自动投升级:throws_per_sec 基值 0 → auto_gold_rate 0、produce 不加 gold
	assert(is_equal_approx(auto_room.auto_gold_rate(), 0.0), "无自动化产率应为 0")
	var g0 := auto_cur.get_amount()
	auto_room.produce(5.0)
	assert(is_equal_approx(auto_cur.get_amount(), g0), "无自动化 produce 不加 gold")

	# 直接注入产率相关 modifier,验证确定性公式:
	#   tps=2, per_dart=DART_BASE(1.0), darts=1, top=1 → E[bullseye]=BULLSEYE[0]=1.5
	#   rate = 2 × 1 × 1.0 × 1.5 = 3.0 gold/s
	auto_mods.set_modifier(&"throws_per_sec", &"test_auto", &"add", 2.0)
	assert(is_equal_approx(auto_room.auto_gold_rate(), 3.0), "rate=2×1×1×1.5=3, got %f" % auto_room.auto_gold_rate())

	# produce(dt) 按 rate×dt 加 gold(确定性,无 RNG)
	var g1 := auto_cur.get_amount()
	var made := auto_room.produce(4.0)
	assert(is_equal_approx(made, 12.0), "produce(4s)=3×4=12, got %f" % made)
	assert(is_equal_approx(auto_cur.get_amount(), g1 + 12.0), "produce 应加 12 gold")

	# produce(dt<=0) 空操作
	assert(is_equal_approx(auto_room.produce(0.0), 0.0), "produce(0) 应为 0")
```

在该文件 `_initialize()` 顶部(其它装配旁)加独立装配,避免污染现有断言用的 room 状态:

```gdscript
	var auto_cur := Currency.new(0.0)
	var auto_mods := KitModifiers.new()
	var auto_reg := KitDataRegistry.new()
	auto_reg.load_dir(&"dart_upgrade", "res://examples/fortune-mill/data/dart_upgrades")
	var auto_room := DartsRoom.new(auto_cur, auto_mods, auto_reg)
```

- [ ] **Step 2: 跑测试确认失败**

```
godot --headless --path . -s res://test/test_fortune_darts.gd
```
Expected: `auto_gold_rate` / `produce` 未定义 → FAIL。

- [ ] **Step 3: 在 `darts_room.gd` 的 `_roll_tier()` 之后追加三个方法**

```gdscript
## 自动产出的期望 gold/秒(确定性:throws/s × 多镖 × 单镖聚合值 × 靶心期望倍率)。
## throws_per_sec 基值 0,买 Rattling Gunner 才 >0。在线 produce 与离线结算同用此率,
## 故「离线 1h ≈ 在线 1h」。手动 throw() 仍走 RNG(有起伏),自动化走期望值(平滑)。
func auto_gold_rate() -> float:
	var tps := _modifiers.value_for(&"throws_per_sec", 0.0)
	if tps <= 0.0:
		return 0.0
	var darts := maxi(1, int(_modifiers.value_for(&"darts_per_throw", 1.0)))
	var per_dart := _modifiers.value_for(&"gold_per_dart", DART_BASE)
	return tps * float(darts) * per_dart * _expected_bullseye()


## 当前可命中档位(1..max_tier)的靶心倍率期望;权重 1/tier^2,与 _roll_tier 同分布。
func _expected_bullseye() -> float:
	var top := max_tier()
	var sum := 0.0
	var wsum := 0.0
	for tier in range(1, top + 1):
		var w := 1.0 / float(tier * tier)
		wsum += w
		sum += w * BULLSEYE[tier - 1]
	return sum / wsum


## 自动化产出 dt 秒的 gold(确定性,按 auto_gold_rate)。返回本次新增 gold。
func produce(dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	var g := auto_gold_rate() * dt
	if g <= 0.0:
		return 0.0
	_currency.add(g)
	return g
```

- [ ] **Step 4: 建 `examples/fortune-mill/data/dart_upgrades/rattling_gunner.tres`**

```
[gd_resource type="Resource" script_class="DartUpgradeDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://examples/fortune-mill/defs/dart_upgrade_def.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"rattling_gunner"
title = "Rattling Gunner"
kind = &"automation"
target = &"throws_per_sec"
op = &"add"
effect_per_level = 0.5
base_cost = 500.0
growth = 1.9
max_level = 25
```

> `kind=&"automation"` 不需 `_apply_upgrade` 特判:它不是 `&"unlock"`,走 else 分支把 `add` 修正器打到 `throws_per_sec`(每级 +0.5×level throws/s)。`from_dict` 重算也自动覆盖(automation 非 unlock,会先 `remove_source` 再重放)。

- [ ] **Step 5: 跑测试确认通过 + 复跑既有断言无回归**

```
godot --headless --path . --import
godot --headless --path . -s res://test/test_fortune_darts.gd
```
Expected: `test_fortune_darts: ALL PASS`(含新自动化断言 + P0 既有 12 断言)。

- [ ] **Step 6: Commit**

```
git add examples/fortune-mill/systems/darts_room.gd examples/fortune-mill/data/dart_upgrades/rattling_gunner.tres examples/fortune-mill/data/dart_upgrades/rattling_gunner.tres.uid test/test_fortune_darts.gd
git commit -m "feat(fortune-mill): DartsRoom 自动产率+produce(dt)+Rattling Gunner 升级(P1)"
```

---

### Task 3: FortuneMill 接线 tick / 自动存 / 离线结算 / last_seen

**Files:**
- Modify: `examples/fortune-mill/systems/fortune_state.gd`

**Interfaces:**
- Consumes: `CoreKit.ticker.every_n(cb, n)`(零参 Callable,`_process` 驱动)、`DartsRoom.produce/auto_gold_rate`、`KitOffline.settle`、`CoreKit.saves`。
- Produces: `FortuneMill.tick(dt)`、`FortuneMill.settle_offline(last_seen, now) -> Dictionary`、`FortuneMill.offline_report`(最近一次离线数据包,UI 拉取)、bus `fortune:offline_settled`(payload=报告 Dictionary)、存档新增键 `last_seen`。

> autoload 在 `-s` 脚本模式不实例化,本任务无独立单测;接线由 Task 5 的 `FORTUNE_SMOKE` 在整项目里验证。

- [ ] **Step 1: 全量替换 `examples/fortune-mill/systems/fortune_state.gd`**

```gdscript
extends Node
## FortuneMill —— 状态支柱 autoload(唯一挂树的游戏级节点)。装配纯数据层、
## 暴露命令方法、接线存档与 bus。经济逻辑在 darts(DartsRoom)里,本节点只转发 + 广播脏标记。
## autoload 顺序必须在 CoreKit 之后(依赖 CoreKit.saves/.bus/.log/.ticker)。

const SAVE_SLOT := "fortune"
const UPGRADES_DIR := "res://examples/fortune-mill/data/dart_upgrades"
const OFFLINE_CAP_SECONDS := 28800.0   # 封顶 8 小时(spec §5.7)
const TICK_EVERY_N := 15               # ~4Hz @60fps 的自动产出结算
const AUTOSAVE_EVERY_N := 300          # ~5s @60fps 的周期自动存

var currency: Currency
var modifiers: KitModifiers
var registry: KitDataRegistry
var darts: DartsRoom

## 最近一次离线结算数据包(空=无);UI 首帧拉取展示回归横幅。
var offline_report: Dictionary = {}

var _tick_handle: int = -1
var _autosave_handle: int = -1
var _last_tick_ms: int = 0


func _ready() -> void:
	currency = Currency.new(1.0)          # 开局 $1 gold(spec §5.1)
	modifiers = KitModifiers.new()
	registry = KitDataRegistry.new()
	var n := registry.load_dir(&"dart_upgrade", UPGRADES_DIR)
	darts = DartsRoom.new(currency, modifiers, registry)
	if CoreKit.saves.has_slot(SAVE_SLOT):
		load_game()                       # 内部做离线结算
	_last_tick_ms = Time.get_ticks_msec()
	_tick_handle = CoreKit.ticker.every_n(_on_tick, TICK_EVERY_N)
	_autosave_handle = CoreKit.ticker.every_n(save_game, AUTOSAVE_EVERY_N)
	CoreKit.log.info("[Fortune] ready: %d upgrades, gold=%s" % [n, Currency.format(currency.get_amount())])


## --- ticker 驱动的自动产出(降频 tick,真实 dt 自算) ---

func _on_tick() -> void:
	var now := Time.get_ticks_msec()
	var dt := float(now - _last_tick_ms) / 1000.0
	_last_tick_ms = now
	if dt > 0.0:
		tick(dt)


func tick(dt: float) -> void:
	var g := darts.produce(dt)
	if g > 0.0:
		CoreKit.bus.publish("fortune:currency_changed", currency.get_amount())


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


## --- 离线结算(load 时按墙钟差补收益;可注入 now 供 smoke 确定性验证) ---

func settle_offline(last_seen: float, now: float) -> Dictionary:
	var rep := KitOffline.settle(last_seen, now, darts.auto_gold_rate(), OFFLINE_CAP_SECONDS)
	offline_report = rep
	if rep.earned > 0.0:
		currency.add(rep.earned)
		CoreKit.bus.publish("fortune:currency_changed", currency.get_amount())
		CoreKit.bus.publish("fortune:offline_settled", rep)
	return rep


## --- 存档(只存 Dictionary,SaveManager 拒 Object;含 last_seen 时间戳) ---

func to_dict() -> Dictionary:
	return {
		"currency": currency.get_amount(),
		"darts": darts.to_dict(),
		"last_seen": Time.get_unix_time_from_system(),
	}


func from_dict(d: Dictionary) -> void:
	currency.set_amount(float(d.get("currency", 1.0)))
	darts.from_dict(d.get("darts", {}))


func save_game() -> void:
	CoreKit.saves.save(SAVE_SLOT, to_dict())


func load_game() -> void:
	var d := CoreKit.saves.load(SAVE_SLOT)
	from_dict(d)
	settle_offline(float(d.get("last_seen", 0.0)), Time.get_unix_time_from_system())


## 窗口关闭时存一次(退出存)。只挂 WM_CLOSE_REQUEST——不挂 EXIT_TREE,
## 避免 headless smoke 退出时重建被清理的存档位、污染下次运行。周期自动存兜底菜单退出。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
```

- [ ] **Step 2: import 无脚本错误**

```
godot --headless --path . --import
```
Expected: 无 `SCRIPT ERROR` / parse error(接线在 Task 5 smoke 里功能验证)。

- [ ] **Step 3: Commit**

```
git add examples/fortune-mill/systems/fortune_state.gd
git commit -m "feat(fortune-mill): FortuneMill 接 ticker 自动产出+周期自动存+离线结算+last_seen(P1)"
```

---

### Task 4: world 表现层 —— 自动产率 HUD + 离线回归横幅

**Files:**
- Modify: `examples/fortune-mill/scenes/world.gd`

**Interfaces:**
- Consumes: `FortuneMill.darts.auto_gold_rate()`、`FortuneMill.offline_report`、`Currency.format`。
- Produces: 无(纯表现)。

> autoload `_ready`(含 `settle_offline` 发 `fortune:offline_settled`)先于 world 场景 `_ready`,故回归横幅必须**拉取** `FortuneMill.offline_report`,不能靠订阅事件(会错过首帧)。

- [ ] **Step 1: 加两个字段** —— 在 `world.gd` 顶部字段区(`_bribe_button` 附近)加:

```gdscript
var _rate_label: Label
var _offline_label: Label
```

- [ ] **Step 2: 非 smoke 分支 `_ready` 末尾拉取离线报告** —— 把现有:

```gdscript
	CoreKit.bus.subscribe("fortune:room_cleared", _on_cleared)
	_refresh()
```
改为:

```gdscript
	CoreKit.bus.subscribe("fortune:room_cleared", _on_cleared)
	_refresh()
	_maybe_show_offline()
```

- [ ] **Step 3: `_build_ui()` 里加产率行与离线横幅** —— 在 `_status_label` 之后、`throw_btn` 之前插入产率 Label;在 `root` 末尾加离线横幅 Label:

```gdscript
	_rate_label = Label.new()
	root.add_child(_rate_label)
```
并在 `_build_ui()` 末尾(`_bribe_button` 之后)追加:

```gdscript
	_offline_label = Label.new()
	_offline_label.visible = false
	root.add_child(_offline_label)
```

- [ ] **Step 4: `_refresh()` 里刷新产率行** —— 在设置 `_gold_label.text` 之后加:

```gdscript
	if _rate_label != null:
		_rate_label.text = "自动: %s gold/s" % Currency.format(FortuneMill.darts.auto_gold_rate())
```

- [ ] **Step 5: 加离线横幅方法** —— 在文件末尾追加:

```gdscript
## 从模型拉取最近离线结算,earned>0 才显示回归横幅(不靠事件,避免错过首帧)。
func _maybe_show_offline() -> void:
	if _offline_label == null:
		return
	var rep: Dictionary = FortuneMill.offline_report
	if rep.is_empty() or float(rep.get("earned", 0.0)) <= 0.0:
		return
	var mins := int(float(rep.get("elapsed", 0.0)) / 60.0)
	var capped := " (已封顶)" if bool(rep.get("capped", false)) else ""
	_offline_label.visible = true
	_offline_label.text = "欢迎回来!离线 %d 分钟%s,自动攒了 %s gold" % [mins, capped, Currency.format(float(rep.get("earned", 0.0)))]
```

- [ ] **Step 6: import 无错**

```
godot --headless --path . --import
```
Expected: 无 parse error。(视觉呈现由编辑器运行 world.tscn 手动确认,可选;功能路径由 Task 5 smoke 覆盖。)

- [ ] **Step 7: Commit**

```
git add examples/fortune-mill/scenes/world.gd
git commit -m "feat(fortune-mill): HUD 自动产率行 + 离线回归横幅(拉取 offline_report)(P1)"
```

---

### Task 5: 扩 FORTUNE_SMOKE + 登记 test_fortune_offline + 全量回归

**Files:**
- Modify: `examples/fortune-mill/scenes/world.gd`(`_run_smoke` 加自动化 + 离线断言)
- Modify: `test/run_all.ps1`
- Modify: `examples/fortune-mill/docs/README.md`

**Interfaces:**
- Consumes: `FortuneMill.tick`、`FortuneMill.settle_offline`、`FortuneMill.darts.auto_gold_rate`。

- [ ] **Step 1: 在 `world.gd` 的 `_run_smoke()` 里,把过关判定+收尾整块替换成含 P1 回归的版本**

找到这一整块(P0 现状,`while` 循环之后):

```gdscript
	var gold_str := Currency.format(fm.currency.get_amount())
	var ok: bool = fm.can_bribe() and fm.bribe_guard()
	CoreKit.saves.delete_slot(fm.SAVE_SLOT)   # smoke 自清理,不留存档污染后续运行
	if ok:
		print("[Fortune][SMOKE] PASS gold=%s steps=%d cleared=%s" % [gold_str, steps, fm.darts.is_cleared()])
		get_tree().quit(0)
	else:
		print("[Fortune][SMOKE] FAIL gold=%s steps=%d" % [gold_str, steps])
		get_tree().quit(1)
```

整块**替换**为(先算 `ok`,再跑 P1 自动化+离线断言,最后合并判定):

```gdscript
	var ok: bool = fm.can_bribe() and fm.bribe_guard()
	# --- P1 回归:自动化产出 + 离线结算(过关后 gold 充裕,可买自动投) ---
	fm.buy_dart_upgrade(&"rattling_gunner")            # 确保 ≥1 级(已满级则 no-op,产率仍 >0)
	var rate: float = fm.darts.auto_gold_rate()
	var before_auto: float = fm.currency.get_amount()
	fm.tick(1.0)                                       # 模拟 1 秒自动产出
	var auto_ok: bool = rate > 0.0 and fm.currency.get_amount() > before_auto
	var t_now: float = Time.get_unix_time_from_system()
	var g_before: float = fm.currency.get_amount()
	var rep: Dictionary = fm.settle_offline(t_now - 3600.0, t_now)   # 模拟关游戏 1 小时
	var offline_ok: bool = float(rep.get("earned", 0.0)) > 0.0 and fm.currency.get_amount() > g_before
	var gold_str := Currency.format(fm.currency.get_amount())
	CoreKit.saves.delete_slot(fm.SAVE_SLOT)   # smoke 自清理,不留存档污染后续运行
	if ok and auto_ok and offline_ok:
		print("[Fortune][SMOKE] PASS gold=%s steps=%d cleared=%s auto_rate=%.2f offline_earn=%.0f" % [gold_str, steps, fm.darts.is_cleared(), rate, float(rep.get("earned", 0.0))])
		get_tree().quit(0)
	else:
		print("[Fortune][SMOKE] FAIL gold=%s steps=%d ok=%s auto_ok=%s offline_ok=%s" % [gold_str, steps, ok, auto_ok, offline_ok])
		get_tree().quit(1)
```

> 收敛性说明:现有 `_smoke_buy_round` 每轮买全部升级(含 `rattling_gunner`),它是额外 gold sink。P0 手动循环 227/500000 步到 1M,余量极大,多一个 sink 不影响收敛(手动单投 gold 随乘数几何增长,远超升级成本)。若实测未到 bribe,回退措施:在 `_smoke_buy_round` 里 `continue` 跳过 `kind==&"automation"` 的升级(自动投只在本 P1 段显式买一次)。

- [ ] **Step 2: 跑 FORTUNE_SMOKE 确认 PASS**

PowerShell(godot 只在 PowerShell PATH;环境变量用 `$env:`):
```
$env:FORTUNE_SMOKE='1'; godot --headless --path . res://examples/fortune-mill/scenes/world.tscn --quit-after 600; Remove-Item Env:\FORTUNE_SMOKE
```
Expected: `[Fortune][SMOKE] PASS ... auto_rate=<>0 offline_earn=<>0`,exit 0。

- [ ] **Step 3: `test/run_all.ps1` 的 `$tests` 数组加 `test_fortune_offline`** —— 把:

```powershell
  'test_fortune_currency','test_fortune_modifiers','test_fortune_darts')
```
改为:

```powershell
  'test_fortune_currency','test_fortune_modifiers','test_fortune_darts','test_fortune_offline')
```

- [ ] **Step 4: 补 `examples/fortune-mill/docs/README.md` 的 P1 段** —— 在 `systems/` 行后追加说明,并把 P0 存档语义注补上 P1 变化:

```markdown

## P1 自动化 + 离线

- **自动投**:买 `Rattling Gunner`(kind=automation → `throws_per_sec` 修正器)后,`ticker` 驱动
  `FortuneMill.tick(dt)` → `DartsRoom.produce(dt)` 按**确定性期望产率** `auto_gold_rate()` 持续产 gold
  (在线与离线同率,保证「离线 1h ≈ 在线 1h」;手动投仍走 RNG,自动投走期望值)。
- **离线结算**:`KitOffline.settle(last_seen, now, rate, cap=8h)`,墙钟差 × 产率,封顶 8 小时,
  时间回拨(`now<last`)按 0(防作弊)。`load_game` 时结算,回归横幅从 `FortuneMill.offline_report` 拉取。
- **自动存**:`ticker` 每 ~5s 周期自动存 + 窗口关闭(`WM_CLOSE_REQUEST`)退出存;存档新增 `last_seen` 时间戳。
- `KitOffline` 照 KitModifiers 先例在 `systems/` 内孵化,定型后随 kit cycle 移入 `addons/`。
```

- [ ] **Step 5: 全量 kit 门回归**

```
powershell -File test/run_all.ps1
```
Expected: 末行 `=== SUMMARY FAILS=0 ===`;`test_fortune_offline` / `test_fortune_darts` 行 `pass=True OK`。

- [ ] **Step 6: Commit**

```
git add examples/fortune-mill/scenes/world.gd test/run_all.ps1 examples/fortune-mill/docs/README.md
git commit -m "test(fortune-mill): FORTUNE_SMOKE 加自动化+离线回归 + 登记 test_fortune_offline 进 kit 门(P1)"
```

---

## 完成定义（P1 验收）

- [ ] `godot --headless --path . -s res://test/test_fortune_offline.gd` → `test_fortune_offline: ALL PASS`(墙钟差/封顶8h/回拨→0/零产率/无时间戳/边界)。
- [ ] `test/test_fortune_darts.gd` → `ALL PASS`(含 `auto_gold_rate`/`produce` 确定性断言 + P0 既有断言)。
- [ ] `powershell -File test/run_all.ps1` → `FAILS=0`(含新 `test_fortune_offline`)。
- [ ] `FORTUNE_SMOKE=1` → `[Fortune][SMOKE] PASS ... auto_rate>0 offline_earn>0`。
- [ ] 全程 headless-first(经济逻辑不挂树)、无裸 float 货币、`bus` 只广播脏标记、离线确定性期望值、封顶 8h、回拨按 0、只改 `examples/`+kit `test/`(不碰 addons/main)。
- [ ] 编辑器运行 `world.tscn`:买 Rattling Gunner 后 gold 自动增长;改系统时间后重进能看到离线横幅(手动确认,可选)。

## 分支收尾（不在本计划内)

P1 全部产物留在 `example/fortune-mill` 分支,**不并 main、不 push**(同 farm-sim;examples 示范游戏各留自己分支,main 只放 kit)。下一步 P2:刮刮乐 + 跨房协同(届时 KitModifiers/KitOffline 定型后由 kit cycle 移入 `addons/`)。
