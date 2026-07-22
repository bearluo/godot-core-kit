# Fortune Grinder（飞镖房真交互重构）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 fortune-mill 飞镖房（Room 1）竖切片重构为横版「命运转盘」投掷玩法——玩家只控方向+力度，扇形多镖扎进多难度奖区、扎上即出金币雨；升级看得见地改变玩法；电脑/Android 双端；单 AI 随机→升级练稳准。

**Architecture:** 严格 headless-first。纯 `RefCounted` 的 `FortuneWheelLayout`（静态、无状态、可无头测）承载转盘几何/结算数学；`DartsRoom` 持 `wheel_angle` + 调用 WheelLayout 做权威结算（`throw(aim,power)`、`produce`）；`FortuneMill` autoload 转发命令 + 存档迁移；view 层（`darts_input.gd` 输入适配 + world 场景 + `KitStateMachine` 投掷态机）只产 `(aim,power)`、只读 `wheel_angle` 渲染，不决定结算。

**Tech Stack:** Godot 4.7 mono GDScript（Tab 缩进）、godot-core-kit（`CoreKit.saves/.bus/.ticker/.settings/.audio`、`KitModifiers`、`KitDataRegistry`、`KitStateMachine`）、`Currency` 值类型、PowerShell `run_all.ps1` 门。

## Global Constraints

- **headless-first**：经济逻辑纯 `RefCounted`、不挂节点树；UI 只读模型发命令；`CoreKit.bus` 只广播 `fortune:*` 脏标记、不做数值求值。
- **数据/表现分离**：model 权威、可无头测；view 仅表现 + 输入；view 读 `model.wheel_angle` 渲染、`throw` 把 `(aim,power)` 交回 model。
- **不用大数库**：float + `Currency`，禁 GDExtension/big-number。
- **在线 = 离线不变量**：AI/离线同用 `auto_gold_rate()` 期望值；手动 `throw` 走真 `(aim,power)+wheel_angle`。
- **跨平台 model 一致**：双端只在输入适配层不同，下游 model/经济/存档/结算完全相同。
- **不出现裸 float 货币运算**：全走 `Currency`。
- 修正走**共享** `KitModifiers`（与其余 4 房同一实例，唯一求值点）。
- **example 只在 `example/fortune-mill` 分支**：永不并 main、永不 push（除非用户指示）。提交署名 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`。
- **Tab 缩进**（本仓库硬约定）；`.gd` 改动后 `godot --headless --path . --import` 生成/更新 `.gd.uid` 一并提交；`.tres` 无 `.uid`。
- **门**：`powershell -File test\run_all.ps1` 必须以 `=== SUMMARY FAILS=0 ===` 收尾。
- 依据 spec：`docs/superpowers/specs/2026-07-22-fortune-grinder-real-interaction-design.md`（commit `eccd077`）。
- godot 只在 PowerShell PATH；跑 smoke 用 `$env:FORTUNE_SMOKE='1'`。

## 文件结构

| 文件 | 责任 | 动作 |
|---|---|---|
| `examples/fortune-mill/systems/wheel_layout.gd` | 转盘几何 + 结算数学（静态、纯、无头可测） | **新建** |
| `examples/fortune-mill/systems/darts_room.gd` | 飞镖房 model：`wheel_angle`/`throw(aim,power)`/扇形多镖/`produce`/升级/存档 | **重写** |
| `examples/fortune-mill/data/dart_upgrades/*.tres` | 6 升级数据（重命名/重定 2+1 条） | **改** |
| `examples/fortune-mill/defs/dart_upgrade_def.gd` | schema：`kind` 注释扩 value/aid/multi/zone/automation | **改（注释）** |
| `examples/fortune-mill/systems/fortune_state.gd` | `do_throw(aim,power)`、tick `update`、`_track_throw`、schema v3→v4 迁移 | **改** |
| `examples/fortune-mill/scenes/darts_input.gd` | 输入适配：Desktop/Touch → `(aim,power)`（纯映射可测） | **新建** |
| `examples/fortune-mill/scenes/world.gd` | 飞镖房横版视图 + `KitStateMachine` 态机 + 转盘/弧线/金币雨 + smoke 扩 | **改** |
| `test/test_fortune_wheel.gd` | WheelLayout 断言 | **新建** |
| `test/test_fortune_darts.gd` | DartsRoom 断言（重写为转盘模型） | **重写** |
| `test/test_fortune_input.gd` | darts_input 纯映射断言 | **新建** |
| `test/run_all.ps1` | `$tests` 加 2 条、头注释 37→39 | **改** |
| `examples/fortune-mill/docs/README.md`、`assets/README.md` | 文档 | **改** |

> 净测试数：37 → **39**（+`test_fortune_wheel` +`test_fortune_input`；`test_fortune_darts` 重写不增计数）。

---

## Task 1: FortuneWheelLayout（纯几何/结算数学 + 测试）

**Files:**
- Create: `examples/fortune-mill/systems/wheel_layout.gd`
- Create: `test/test_fortune_wheel.gd`

**Interfaces:**
- Produces（全部 `static`，无状态，`class_name FortuneWheelLayout`）：
  - `const SEGMENTS: Array`（各 `{name:StringName, span:float, mult:float, vermin:bool}`，span 合计 360）
  - `const AIM_ARC := 120.0`、`const POWER_SWEET := 0.6`、`const FAN_STEP := 14.0`、`const AI_RADIAL := 1.5`
  - `segment_at(angle_deg: float, win_bonus: float) -> Dictionary` → `{name, mult, vermin}`
  - `expected_mult(ai_skill: float) -> float`
  - `radial_bonus(r: float) -> float`
  - `landing(aim: float, power: float) -> Dictionary` → `{r, a_off}`
  - `fan_offsets(n: int) -> Array`（长度 n 的角偏移，居中对称）

- [ ] **Step 1: 写失败测试 `test/test_fortune_wheel.gd`**

```gdscript
extends SceneTree
## FortuneWheelLayout 纯几何/结算断言。运行:godot --headless --path . -s res://test/test_fortune_wheel.gd
const WL := preload("res://examples/fortune-mill/systems/wheel_layout.gd")

func _initialize() -> void:
	var failures := 0

	# 1. SEGMENTS 覆盖 360、含 jackpot 与 vermin
	var total := 0.0
	var has_jack := false; var has_vermin := false
	for s in WL.SEGMENTS:
		total += float(s["span"])
		if s["name"] == &"jackpot": has_jack = true
		if bool(s.get("vermin", false)): has_vermin = true
	if absf(total - 360.0) > 0.01 or not has_jack or not has_vermin:
		print("FAIL 1: SEGMENTS 应覆盖 360 且含 jackpot+vermin,实际 total=%s" % total); failures += 1

	# 2. jackpot 中心 win_bonus=0 时命中 jackpot
	var jc := WL.jackpot_center()
	if WL.segment_at(jc, 0.0)["name"] != &"jackpot":
		print("FAIL 2: jackpot 中心应命中 jackpot"); failures += 1

	# 3. 扩大中奖区:jackpot 边缘外一点,win_bonus=0 非 jackpot,win_bonus 大 → 变 jackpot
	var edge := jc + WL.jackpot_half_base() + 8.0
	var was_jack := WL.segment_at(edge, 0.0)["name"] == &"jackpot"
	var now_jack := WL.segment_at(edge, 40.0)["name"] == &"jackpot"
	if was_jack or not now_jack:
		print("FAIL 3: win_bonus 应加宽 jackpot 命中带"); failures += 1

	# 4. vermin 段 mult=0
	var vseg := WL.segment_at(WL.vermin_center(), 0.0)
	if not bool(vseg["vermin"]) or float(vseg["mult"]) != 0.0:
		print("FAIL 4: vermin 段应 mult=0"); failures += 1

	# 5. expected_mult 随 ai_skill 单调升(0 最低,1 最高)
	var e0 := WL.expected_mult(0.0); var e1 := WL.expected_mult(1.0); var eh := WL.expected_mult(0.5)
	if not (e1 > eh and eh > e0 and e0 > 0.0):
		print("FAIL 5: expected_mult 应随 ai_skill 单调升,e0=%s eh=%s e1=%s" % [e0, eh, e1]); failures += 1

	# 6. radial_bonus:盘心(r=0)>边缘(r=1),且单调
	if not (WL.radial_bonus(0.0) > WL.radial_bonus(0.5) and WL.radial_bonus(0.5) > WL.radial_bonus(1.0)):
		print("FAIL 6: radial_bonus 应随 r 单调降"); failures += 1

	# 7. landing 确定性 + 甜点 power=POWER_SWEET → r≈0(最靠盘心)
	var l_sweet := WL.landing(0.5, WL.POWER_SWEET)
	if absf(float(l_sweet["r"])) > 0.01:
		print("FAIL 7a: 甜点力度应 r≈0,实际 %s" % l_sweet["r"]); failures += 1
	if absf(float(l_sweet["a_off"])) > 0.01:   # aim=0.5 → 居中 a_off≈0
		print("FAIL 7b: aim=0.5 应 a_off≈0,实际 %s" % l_sweet["a_off"]); failures += 1
	var l_bad := WL.landing(0.5, 1.0)
	if float(l_bad["r"]) <= float(l_sweet["r"]):
		print("FAIL 7c: 偏离甜点 r 应更大"); failures += 1

	# 8. fan_offsets:居中对称,和≈0,长度对
	var fan := WL.fan_offsets(3)
	if fan.size() != 3 or absf(float(fan[0]) + float(fan[2])) > 0.01 or absf(float(fan[1])) > 0.01:
		print("FAIL 8: fan_offsets(3) 应对称居中,实际 %s" % str(fan)); failures += 1
	if WL.fan_offsets(1).size() != 1 or absf(float(WL.fan_offsets(1)[0])) > 0.01:
		print("FAIL 8b: fan_offsets(1) 应 [0]"); failures += 1

	if failures == 0:
		print("test_fortune_wheel: ALL PASS"); quit(0)
	else:
		print("test_fortune_wheel: %d FAILURE(S)" % failures); quit(1)
```

- [ ] **Step 2: 运行确认失败**

Run: `godot --headless --path . -s res://test/test_fortune_wheel.gd`
Expected: 解析错误 / `WL` 预加载失败（文件不存在）。

- [ ] **Step 3: 实现 `examples/fortune-mill/systems/wheel_layout.gd`**

```gdscript
class_name FortuneWheelLayout
extends RefCounted
## 命运转盘的几何 + 结算数学。全静态、无状态、纯 float 运算 → headless 可测。
## model(DartsRoom)与 view 都调此;view 只用来渲染,权威结算在 DartsRoom.throw 里经此计算。

## 扇区(顺时针,从 0° 起铺满 360°)。宽度=难度:越窄倍率越高;含一块 vermin 没收段。
const SEGMENTS := [
	{"name": &"jackpot", "span": 18.0, "mult": 500.0, "vermin": false},
	{"name": &"x2a",     "span": 72.0, "mult": 2.0,   "vermin": false},
	{"name": &"x20a",    "span": 40.0, "mult": 20.0,  "vermin": false},
	{"name": &"x5",      "span": 58.0, "mult": 5.0,   "vermin": false},
	{"name": &"vermin",  "span": 40.0, "mult": 0.0,   "vermin": true},
	{"name": &"x100",    "span": 30.0, "mult": 100.0, "vermin": false},
	{"name": &"x2b",     "span": 62.0, "mult": 2.0,   "vermin": false},
	{"name": &"x20b",    "span": 40.0, "mult": 20.0,  "vermin": false},
]

const AIM_ARC := 120.0      ## aim 0..1 映射到 ±AIM_ARC/2 的盘面角偏移
const POWER_SWEET := 0.6    ## 力度甜点(落盘心);偏离 → 落点外移
const FAN_STEP := 14.0      ## 扇形多镖每支相邻角距(°)
const AI_RADIAL := 1.5      ## AI/离线期望的平均径向加成(手动走真 radial_bonus)


## jackpot 段中心角(°)。
static func jackpot_center() -> float:
	return _center_of(&"jackpot")


static func vermin_center() -> float:
	return _center_of(&"vermin")


## jackpot 基础半宽(°)。
static func jackpot_half_base() -> float:
	return _span_of(&"jackpot") * 0.5


## 命中角落在哪个奖区。win_bonus(°)加宽 jackpot 命中带(以中心对称扩)。
## 语义:先判「加宽后的 jackpot 带」,否则回落基础扇区。
static func segment_at(angle_deg: float, win_bonus: float) -> Dictionary:
	var a := fposmod(angle_deg, 360.0)
	var jc := jackpot_center()
	var half := jackpot_half_base() + maxf(0.0, win_bonus) * 0.5
	if _arc_dist(a, jc) <= half:
		return {"name": &"jackpot", "mult": 500.0, "vermin": false}
	var acc := 0.0
	for s in SEGMENTS:
		var a0 := acc; var a1 := acc + float(s["span"])
		if a >= a0 and a < a1:
			return {"name": s["name"], "mult": float(s["mult"]), "vermin": bool(s.get("vermin", false))}
		acc = a1
	# 边界兜底(a==360 之类)
	var last: Dictionary = SEGMENTS[SEGMENTS.size() - 1]
	return {"name": last["name"], "mult": float(last["mult"]), "vermin": bool(last.get("vermin", false))}


## AI/离线的期望倍率(含平均径向)。ai_skill 0=近均匀(含 vermin 拖累),1=偏向高奖、避 vermin。
static func expected_mult(ai_skill: float) -> float:
	var s := clampf(ai_skill, 0.0, 1.0)
	# 均匀期望(按 span 加权,vermin=0 计入)
	var uniform := 0.0
	var top := 0.0
	for seg in SEGMENTS:
		uniform += (float(seg["span"]) / 360.0) * float(seg["mult"])
		top = maxf(top, float(seg["mult"]))
	# 高目标:偏向但不满命中 jackpot(用 x100 量级更稳,避免离散暴涨)
	var high := 100.0
	var e_seg: float = lerpf(uniform, high, s)
	return e_seg * AI_RADIAL


## 径向精度加成:盘心 2.0 → 边缘 1.0(r 归一化 0..1)。
static func radial_bonus(r: float) -> float:
	return lerpf(2.0, 1.0, clampf(r, 0.0, 1.0))


## (aim,power) → 盘面落点 {r(离盘心 0..1), a_off(盘面角偏移 °)}。纯确定性,无 RNG。
static func landing(aim: float, power: float) -> Dictionary:
	var a_off := (clampf(aim, 0.0, 1.0) - 0.5) * AIM_ARC
	var r := clampf(absf(power - POWER_SWEET) / POWER_SWEET, 0.0, 1.0)
	return {"r": r, "a_off": a_off}


## n 支扇形多镖的角偏移(居中对称,和为 0)。
static func fan_offsets(n: int) -> Array:
	var out: Array = []
	var cnt := maxi(1, n)
	var start := -FAN_STEP * (float(cnt) - 1.0) * 0.5
	for i in cnt:
		out.append(start + FAN_STEP * float(i))
	return out


static func _center_of(name: StringName) -> float:
	var acc := 0.0
	for s in SEGMENTS:
		if s["name"] == name:
			return acc + float(s["span"]) * 0.5
		acc += float(s["span"])
	return 0.0


static func _span_of(name: StringName) -> float:
	for s in SEGMENTS:
		if s["name"] == name:
			return float(s["span"])
	return 0.0


## 两角在圆周上的最短角距(°)。
static func _arc_dist(a: float, b: float) -> float:
	var d := absf(fposmod(a - b, 360.0))
	return minf(d, 360.0 - d)
```

- [ ] **Step 4: 运行确认通过**

Run: `godot --headless --path . -s res://test/test_fortune_wheel.gd`
Expected: `test_fortune_wheel: ALL PASS`

- [ ] **Step 5: import 生成 uid + 提交**

```bash
godot --headless --path . --import
git add examples/fortune-mill/systems/wheel_layout.gd examples/fortune-mill/systems/wheel_layout.gd.uid test/test_fortune_wheel.gd test/test_fortune_wheel.gd.uid
git commit -m "$(printf 'feat(fortune-mill): FortuneWheelLayout 转盘几何/结算数学(纯静态,headless 可测)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 2: DartsRoom 重构（throw(aim,power) + 扇形多镖 + AI 期望 + 6 升级）+ 数据 + 测试

**Files:**
- Modify: `examples/fortune-mill/systems/darts_room.gd`（整体重写结算部分）
- Modify: `examples/fortune-mill/data/dart_upgrades/`（重命名 `bullseye_training.tres`→`widen_zone.tres`、`rattling_gunner.tres`→`hire_ai.tres`；重定 `steady_hand.tres`）
- Modify: `examples/fortune-mill/defs/dart_upgrade_def.gd`（`kind` 注释）
- Modify: `test/test_fortune_darts.gd`（重写为转盘模型）

**Interfaces:**
- Consumes: `FortuneWheelLayout`（Task 1 全部 static）、`Currency`、`KitModifiers`、`KitDataRegistry`。
- Produces（`DartsRoom`）：`const DART_BASE := 1.0`、`const BRIBE_COST := 1_000_000.0`、`const WHEEL_SPEED := 45.0`；`var wheel_angle: float`；`throw(aim: float, power: float) -> Dictionary`（`{gold, darts, hits:[{seg,mult,r,gold,vermin}]}`）；`update(dt)`；`auto_gold_rate()`；`produce(dt)`；`buy_upgrade(id)`；`cost_of(id)`；`level_of(id)`；`bribe_threshold()`/`can_bribe()`/`bribe()`/`is_cleared()`；`to_dict()`/`from_dict(d)`；`seed_rng(s)`。**移除**：`BULLSEYE`/`max_tier`/`_roll_tier`/`_expected_bullseye`/`_bullseye_unlock`。

- [ ] **Step 1: 重写数据 .tres（先删旧 + 建新，保 import 有效）**

`bullseye_training.tres` → 重命名内容为 `widen_zone.tres`：

```bash
git mv examples/fortune-mill/data/dart_upgrades/bullseye_training.tres examples/fortune-mill/data/dart_upgrades/widen_zone.tres
git mv examples/fortune-mill/data/dart_upgrades/rattling_gunner.tres examples/fortune-mill/data/dart_upgrades/hire_ai.tres
```

写 `examples/fortune-mill/data/dart_upgrades/widen_zone.tres`：

```
[gd_resource type="Resource" script_class="DartUpgradeDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://examples/fortune-mill/defs/dart_upgrade_def.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"widen_zone"
title = "Widen Jackpot"
kind = &"zone"
target = &"win_zone"
op = &"add"
effect_per_level = 6.0
base_cost = 50.0
growth = 1.8
max_level = 16
```

写 `examples/fortune-mill/data/dart_upgrades/hire_ai.tres`：

```
[gd_resource type="Resource" script_class="DartUpgradeDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://examples/fortune-mill/defs/dart_upgrade_def.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"hire_ai"
title = "Hire AI Grinder"
kind = &"automation"
target = &"throws_per_sec"
op = &"add"
effect_per_level = 0.5
base_cost = 500.0
growth = 1.9
max_level = 25
```

改写 `examples/fortune-mill/data/dart_upgrades/steady_hand.tres`（重定为操作辅助）：

```
[gd_resource type="Resource" script_class="DartUpgradeDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://examples/fortune-mill/defs/dart_upgrade_def.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"steady_hand"
title = "Steady Hand"
kind = &"aid"
target = &"aim_steady"
op = &"add"
effect_per_level = 1.0
base_cost = 40.0
growth = 1.25
max_level = 8
```

`sharper_darts.tres`、`golden_tips.tres`、`double_dart.tres` **不改**。

- [ ] **Step 2: 更新 `defs/dart_upgrade_def.gd` 的 kind 注释**

把第 8 行注释改为：

```gdscript
## 分类(UI 分组 + DartsRoom 特判):value(镖值) / aid(操作辅助 aim_steady) / multi(扇形多镖) / zone(扩大中奖区 win_zone) / automation(雇 AI:throws_per_sec+ai_skill)
```
把第 10-11 行 target 注释改为：
```gdscript
## modifier target:gold_per_dart / darts_per_throw / aim_steady / win_zone；automation 特判驱动 throws_per_sec + ai_skill
```

- [ ] **Step 3: 写失败测试 `test/test_fortune_darts.gd`（整体重写）**

```gdscript
extends SceneTree
## DartsRoom(命运转盘模型)headless 断言。运行:godot --headless --path . -s res://test/test_fortune_darts.gd
const Currency := preload("res://examples/fortune-mill/systems/currency.gd")
const KitModifiers := preload("res://examples/fortune-mill/systems/kit_modifiers.gd")
const WL := preload("res://examples/fortune-mill/systems/wheel_layout.gd")
const DartsRoom := preload("res://examples/fortune-mill/systems/darts_room.gd")
const DartUpgradeDef := preload("res://examples/fortune-mill/defs/dart_upgrade_def.gd")
const KitDataRegistry := preload("res://addons/godot-core-kit/data/kit_data_registry.gd")


func _def(id, kind, target, op, eff, base, growth, maxl):
	var d = DartUpgradeDef.new()
	d.id = id; d.kind = kind; d.target = target; d.op = op
	d.effect_per_level = eff; d.base_cost = base; d.growth = growth; d.max_level = maxl
	return d


func _reg() -> Object:
	var reg = KitDataRegistry.new()
	reg.register(&"dart_upgrade", &"sharper_darts", _def(&"sharper_darts", &"value", &"gold_per_dart", &"add", 1.0, 10.0, 1.15, -1))
	reg.register(&"dart_upgrade", &"double_dart", _def(&"double_dart", &"multi", &"darts_per_throw", &"add", 1.0, 100.0, 2.5, 9))
	reg.register(&"dart_upgrade", &"widen_zone", _def(&"widen_zone", &"zone", &"win_zone", &"add", 6.0, 50.0, 1.8, 16))
	reg.register(&"dart_upgrade", &"hire_ai", _def(&"hire_ai", &"automation", &"throws_per_sec", &"add", 0.5, 500.0, 1.9, 25))
	return reg


func _room(reg) -> Array:
	var cur = Currency.new(0.0)
	var mods = KitModifiers.new()
	var room = DartsRoom.new(cur, mods, reg)
	room.seed_rng(12345)
	return [room, cur, mods]


## 用 landing 反推能命中 jackpot 的 (aim,power,wheel_angle):
## 令 aim=0.5(a_off=0)、power=SWEET(r=0)→ hit_angle=wheel_angle;设 wheel_angle=jackpot 中心。
func _aim_jackpot(room) -> void:
	room.wheel_angle = WL.jackpot_center()


func _initialize() -> void:
	var failures := 0

	# 1. throw(甜点+对准 jackpot) → 单镖 gold = base(1.0)×500×radial(2.0)×gmul(1.0) = 1000
	var t = _room(_reg()); var room = t[0]; var cur = t[1]
	_aim_jackpot(room)
	var r = room.throw(0.5, WL.POWER_SWEET)
	if absf(float(r["gold"]) - 1000.0) > 0.01 or absf(cur.get_amount() - float(r["gold"])) > 0.01:
		print("FAIL 1: jackpot 甜点单镖应 1000 并入账,实际 %s" % r["gold"]); failures += 1
	if r["hits"].size() != 1 or r["hits"][0]["seg"] != &"jackpot":
		print("FAIL 1b: hits 应 1 支且命中 jackpot"); failures += 1

	# 2. throw 命中 vermin → payout 0
	var t2 = _room(_reg()); var room2 = t2[0]; var cur2 = t2[1]
	room2.wheel_angle = WL.vermin_center()
	var r2 = room2.throw(0.5, WL.POWER_SWEET)
	if absf(float(r2["gold"])) > 0.01:
		print("FAIL 2: vermin 应 payout 0,实际 %s" % r2["gold"]); failures += 1

	# 3. radial:同 jackpot,偏离甜点(power=1.0,r=1,radial=1.0)→ 500,小于甜点 1000
	var t3 = _room(_reg()); var room3 = t3[0]
	_aim_jackpot(room3)
	var r3 = room3.throw(0.5, 1.0)
	if absf(float(r3["gold"]) - 500.0) > 0.01:
		print("FAIL 3: jackpot 边缘力度应 500(radial 1.0),实际 %s" % r3["gold"]); failures += 1

	# 4. 扇形多镖:买 double_dart 一级 → darts_per_throw=2;throw 返 2 个 hits,各自结算
	var t4 = _room(_reg()); var room4 = t4[0]; var cur4 = t4[1]
	cur4.add(1000.0)
	room4.buy_upgrade(&"double_dart")
	_aim_jackpot(room4)
	var r4 = room4.throw(0.5, WL.POWER_SWEET)
	if r4["hits"].size() != 2:
		print("FAIL 4: double_dart 后应 2 支,实际 %d" % r4["hits"].size()); failures += 1

	# 5. widen_zone:jackpot 带外一点,未升级非 jackpot、升级后变 jackpot → payout 升
	var t5 = _room(_reg()); var room5 = t5[0]; var cur5 = t5[1]; var mods5 = t5[2]
	# 令 hit_angle 落在 jackpot 中心 + 基础半宽 + 8°(基础带外)
	room5.wheel_angle = WL.jackpot_center() + WL.jackpot_half_base() + 8.0
	var before = room5.throw(0.5, WL.POWER_SWEET)   # 非 jackpot
	cur5.add(100000.0)
	for _i in 3: room5.buy_upgrade(&"widen_zone")   # win_zone +18°
	var after = room5.throw(0.5, WL.POWER_SWEET)    # 现应命中 jackpot
	if after["hits"][0]["seg"] != &"jackpot" or float(after["gold"]) <= float(before["gold"]):
		print("FAIL 5: widen_zone 应把该落点变 jackpot 且 payout 升"); failures += 1

	# 6. auto_gold_rate:无 hire_ai → 0;produce 不加
	var t6 = _room(_reg()); var room6 = t6[0]; var cur6 = t6[1]
	if absf(room6.auto_gold_rate()) > 0.0001:
		print("FAIL 6: 无自动化产率应 0"); failures += 1
	var g6 = cur6.get_amount(); room6.produce(5.0)
	if absf(cur6.get_amount() - g6) > 0.0001:
		print("FAIL 6b: 无自动化 produce 不加 gold"); failures += 1

	# 7. hire_ai:买一级 → throws_per_sec>0 且 auto_gold_rate>0;produce 入账
	var t7 = _room(_reg()); var room7 = t7[0]; var cur7 = t7[1]; var mods7 = t7[2]
	cur7.add(1000.0)
	if not room7.buy_upgrade(&"hire_ai") or room7.level_of(&"hire_ai") != 1:
		print("FAIL 7a: 买 hire_ai 应成功 level1"); failures += 1
	if room7.auto_gold_rate() <= 0.0:
		print("FAIL 7b: hire_ai 后产率应 >0"); failures += 1
	var made = room7.produce(2.0)
	if made <= 0.0 or absf(cur7.get_amount() - made) > 0.0001:
		print("FAIL 7c: produce 应入账"); failures += 1

	# 8. AI 稳准:ai_skill 越高 auto_gold_rate 越高(在线=离线同一 rate)
	var t8 = _room(_reg()); var room8 = t8[0]; var mods8 = t8[2]
	mods8.set_modifier(&"throws_per_sec", &"x", &"add", 1.0)
	mods8.set_modifier(&"ai_skill", &"y", &"add", 0.0)
	var rate_lo = room8.auto_gold_rate()
	mods8.set_modifier(&"ai_skill", &"y", &"add", 1.0)
	var rate_hi = room8.auto_gold_rate()
	if not (rate_hi > rate_lo and rate_lo > 0.0):
		print("FAIL 8: ai_skill 高应产率更高,lo=%s hi=%s" % [rate_lo, rate_hi]); failures += 1

	# 9. cost_of / buy 扣款 / 买不起
	var t9 = _room(_reg()); var room9 = t9[0]; var cur9 = t9[1]
	if absf(room9.cost_of(&"sharper_darts") - 10.0) > 0.0001 or room9.buy_upgrade(&"sharper_darts"):
		print("FAIL 9: level0 成本 10 且没钱买不了"); failures += 1
	cur9.add(100.0); room9.buy_upgrade(&"sharper_darts")
	if absf(cur9.get_amount() - 90.0) > 0.0001 or room9.level_of(&"sharper_darts") != 1:
		print("FAIL 9b: 买后扣款 90 + level1"); failures += 1

	# 10. bribe:未达门槛不能;达门槛(1M)可 + cleared
	var t10 = _room(_reg()); var room10 = t10[0]; var cur10 = t10[1]
	if room10.can_bribe() or room10.bribe():
		print("FAIL 10a: 未达门槛不能贿赂"); failures += 1
	cur10.set_amount(DartsRoom.BRIBE_COST)
	if not room10.can_bribe() or not room10.bribe() or not room10.is_cleared():
		print("FAIL 10b: 达门槛应贿赂 + cleared"); failures += 1

	# 11. to_dict/from_dict 往返 + 完整重算(空存档清残留 modifier)
	var t11 = _room(_reg()); var room11 = t11[0]; var cur11 = t11[1]; var mods11 = t11[2]
	cur11.add(1000.0); room11.buy_upgrade(&"sharper_darts")
	if absf(mods11.value_for(&"gold_per_dart", DartsRoom.DART_BASE) - 2.0) > 0.0001:
		print("FAIL 11a: sharper 后 gold_per_dart 2.0"); failures += 1
	var snap = room11.to_dict()
	var t11b = _room(_reg()); var room11b = t11b[0]; var mods11b = t11b[2]
	room11b.from_dict(snap)
	if room11b.level_of(&"sharper_darts") != 1 or absf(mods11b.value_for(&"gold_per_dart", DartsRoom.DART_BASE) - 2.0) > 0.0001:
		print("FAIL 11b: from_dict 应恢复 level + modifier"); failures += 1
	room11.from_dict({"levels": {}, "cleared": false})   # 复用同实例加载空档
	if room11.level_of(&"sharper_darts") != 0 or absf(mods11.value_for(&"gold_per_dart", DartsRoom.DART_BASE) - DartsRoom.DART_BASE) > 0.0001:
		print("FAIL 11c: 空存档应清残留 modifier"); failures += 1

	# 12. hire_ai from_dict 清残留:买后 ai_skill/throws_per_sec >0,空档后回 0
	var t12 = _room(_reg()); var room12 = t12[0]; var cur12 = t12[1]; var mods12 = t12[2]
	cur12.add(1000.0); room12.buy_upgrade(&"hire_ai")
	room12.from_dict({"levels": {}, "cleared": false})
	if absf(mods12.value_for(&"throws_per_sec", 0.0)) > 0.0001 or absf(mods12.value_for(&"ai_skill", 0.0)) > 0.0001:
		print("FAIL 12: hire_ai 空档应清 throws_per_sec + ai_skill"); failures += 1

	if failures == 0:
		print("test_fortune_darts: ALL PASS"); quit(0)
	else:
		print("test_fortune_darts: %d FAILURE(S)" % failures); quit(1)
```

- [ ] **Step 4: 运行确认失败**

Run: `godot --headless --path . -s res://test/test_fortune_darts.gd`
Expected: 断言失败 / 解析错误（DartsRoom 仍是旧靶心模型、无 `throw(aim,power)`/`wheel_angle`）。

- [ ] **Step 5: 重写 `examples/fortune-mill/systems/darts_room.gd`**

```gdscript
class_name DartsRoom
extends RefCounted
## 飞镖房 model(命运转盘,纯数据,不挂节点树)。手动 throw(aim,power) → 扇形多镖各自扎盘 →
## 按扇区倍率×径向加成产 gold;升级经共享 KitModifiers;自动投(AI)走期望值保在线=离线;
## 攒够 BRIBE_COST 贿赂守卫 Verminous 过关。转盘几何/结算数学在 FortuneWheelLayout(纯静态)。

const DART_BASE := 1.0             ## 单镖基础 gold(未加成)
const BRIBE_COST := 1_000_000.0    ## 贿赂 Verminous 门槛
const WHEEL_SPEED := 45.0          ## 转盘角速度(°/秒);model 自持相位,view 只读渲染

var wheel_angle: float = 0.0       ## 当前转盘相位(°);update(dt) 推进,throw 读它定命中扇区
var _currency: Currency
var _modifiers: KitModifiers
var _registry: KitDataRegistry
var _levels: Dictionary = {}       # StringName(id) -> int(level)
var _cleared: bool = false
var _rng := RandomNumberGenerator.new()


func _init(currency: Currency, modifiers: KitModifiers, registry: KitDataRegistry) -> void:
	_currency = currency
	_modifiers = modifiers
	_registry = registry
	_rng.randomize()


func seed_rng(s: int) -> void:
	_rng.seed = s


func level_of(id: StringName) -> int:
	return int(_levels.get(id, 0))


func cost_of(id: StringName) -> float:
	var def = _registry.get_def(&"dart_upgrade", id)
	if def == null:
		return INF
	return float(def.base_cost) * pow(float(def.growth), level_of(id))


## 推进转盘相位(由 autoload ticker 每拍调,与 produce 同拍)。
func update(dt: float) -> void:
	if dt <= 0.0:
		return
	wheel_angle = fposmod(wheel_angle + WHEEL_SPEED * dt, 360.0)


## 手动投:方向 aim(0..1) + 力度 power(0..1)。扇形多镖各以不同角偏移扎盘,各自结算。
## 返回 {gold, darts, hits:[{seg,mult,r,gold,vermin}]}。
func throw(aim: float, power: float) -> Dictionary:
	var darts := maxi(1, int(_modifiers.value_for(&"darts_per_throw", 1.0)))
	var per_dart := _modifiers.value_for(&"gold_per_dart", DART_BASE)
	var win_bonus := _modifiers.value_for(&"win_zone", 0.0)
	var gmul := _modifiers.value_for(&"global_mul", 1.0)
	var land := FortuneWheelLayout.landing(aim, power)
	var r := float(land["r"])
	var rb := FortuneWheelLayout.radial_bonus(r)
	var fans := FortuneWheelLayout.fan_offsets(darts)
	var total := 0.0
	var hits: Array = []
	for i in darts:
		var hit_angle: float = wheel_angle + float(land["a_off"]) + float(fans[i])
		var seg := FortuneWheelLayout.segment_at(hit_angle, win_bonus)
		var pay: float = per_dart * float(seg["mult"]) * rb * gmul
		total += pay
		hits.append({"seg": seg["name"], "mult": float(seg["mult"]), "r": r, "gold": pay, "vermin": bool(seg["vermin"])})
	_currency.add(total)
	return {"gold": total, "darts": darts, "hits": hits}


## 自动产出期望 gold/秒(确定性):throws/s × 多镖 × 单镖聚合值 × AI 期望倍率(含平均径向) × global_mul。
## throws_per_sec 基值 0,买 hire_ai 才 >0;在线 produce 与离线结算同用此率(在线=离线)。
func auto_gold_rate() -> float:
	var tps := _modifiers.value_for(&"throws_per_sec", 0.0)
	if tps <= 0.0:
		return 0.0
	var darts := maxi(1, int(_modifiers.value_for(&"darts_per_throw", 1.0)))
	var per_dart := _modifiers.value_for(&"gold_per_dart", DART_BASE)
	var ai_skill := _modifiers.value_for(&"ai_skill", 0.0)
	var gmul := _modifiers.value_for(&"global_mul", 1.0)
	return tps * float(darts) * per_dart * FortuneWheelLayout.expected_mult(ai_skill) * gmul


func produce(dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	var g := auto_gold_rate() * dt
	if g <= 0.0:
		return 0.0
	_currency.add(g)
	return g


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


## 把某升级在 level 的效果落到 modifier。automation(hire_ai)特判:一条驱动 throws_per_sec + ai_skill。
func _apply_upgrade(def, level: int) -> void:
	if def.kind == &"automation":
		# cadence:每级 +effect;ai_skill:L1=0(随机)逐级升到 ~1(稳准)
		_modifiers.set_modifier(&"throws_per_sec", def.id, &"add", float(def.effect_per_level) * level)
		_modifiers.set_modifier(&"ai_skill", def.id, &"add", clampf(float(level - 1) * 0.12, 0.0, 1.0))
		return
	var v := 0.0
	if def.op == &"add":
		v = float(def.effect_per_level) * level
	else:  # mul:每级 ×(1+effect)
		v = pow(1.0 + float(def.effect_per_level), level)
	_modifiers.set_modifier(def.target, def.id, def.op, v)


func bribe_threshold() -> float:
	return BRIBE_COST * _modifiers.value_for(&"bribe_cost_mul", 1.0)


func can_bribe() -> bool:
	return _currency.get_amount() >= bribe_threshold()


func bribe() -> bool:
	if not can_bribe():
		return false
	_cleared = true
	return true


func is_cleared() -> bool:
	return _cleared


## 只存权威状态(levels/cleared);modifier 是派生值,from_dict 重算。
func to_dict() -> Dictionary:
	var lv := {}
	for id in _levels:
		lv[String(id)] = int(_levels[id])
	return {"levels": lv, "cleared": _cleared}


func from_dict(d: Dictionary) -> void:
	# 先摘除本 room 此前已施加的所有 modifier(派生态从零重算,不叠加残留)
	for old_id in _levels:
		_clear_upgrade_modifiers(old_id)
	_levels.clear()
	_cleared = bool(d.get("cleared", false))
	var lv: Dictionary = d.get("levels", {})
	for k in lv:
		var id := StringName(k)
		var level := int(lv[k])
		_levels[id] = level
		var def = _registry.get_def(&"dart_upgrade", id)
		if def != null:
			_apply_upgrade(def, level)


## 摘除某升级施加的 modifier 源(automation 占两个 target)。
func _clear_upgrade_modifiers(id: StringName) -> void:
	var def = _registry.get_def(&"dart_upgrade", id)
	if def == null:
		return
	if def.kind == &"automation":
		_modifiers.remove_source(&"throws_per_sec", id)
		_modifiers.remove_source(&"ai_skill", id)
	else:
		_modifiers.remove_source(def.target, id)
```

- [ ] **Step 6: 运行确认通过**

Run: `godot --headless --path . -s res://test/test_fortune_darts.gd`
Expected: `test_fortune_darts: ALL PASS`

- [ ] **Step 7: import + 提交**

```bash
godot --headless --path . --import
git add examples/fortune-mill/systems/darts_room.gd examples/fortune-mill/systems/darts_room.gd.uid examples/fortune-mill/defs/dart_upgrade_def.gd examples/fortune-mill/data/dart_upgrades/ test/test_fortune_darts.gd
git commit -m "$(printf 'feat(fortune-mill): DartsRoom 重构命运转盘——throw(aim,power)+扇形多镖+AI 期望+6 升级\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 3: FortuneMill 装配 + 统计/成就适配 + 存档迁移 v3→v4

**Files:**
- Modify: `examples/fortune-mill/systems/fortune_state.gd`
- Modify: `examples/fortune-mill/systems/achievement_catalog.gd`（darts 靶心档成就 → 转盘奖区）
- Modify: `test/test_fortune_migration.gd`（加 v3→v4 用例）
- Modify（按需，读文件后对齐）: `test/test_fortune_stats.gd`、`test/test_fortune_achievements.gd`

**Interfaces:**
- Consumes: 新 `DartsRoom.throw(aim,power)`/`update(dt)`（Task 2）。
- Produces: `FortuneMill.do_throw(aim: float, power: float) -> Dictionary`；`tick` 内 `darts.update(dt)`；`_track_throw` 读 `r.hits`；`SCHEMA_VERSION := 4`；迁移 v3→v4 映射旧 darts 升级 id + 统计键。

- [ ] **Step 1: 改 `fortune_state.gd`——命令签名 + tick + 统计**

`SCHEMA_VERSION` 3 → 4（第 7 行）。

`do_throw`（第 143-147 行）改为：
```gdscript
func do_throw(aim: float, power: float) -> Dictionary:
	var r := darts.throw(aim, power)
	CoreKit.bus.publish("fortune:currency_changed", currency.get_amount())
	_track_throw(r)
	return r
```

`tick(dt)`（第 98-99 行附近）在 `darts.produce(dt)` 前加转盘推进：
```gdscript
func tick(dt: float) -> void:
	darts.update(dt)   # 命运转盘相位推进(view 只读渲染;结算读它)
	var g := darts.produce(dt)
```

`_track_throw`（第 131-138 行）改为读 `hits`、按奖区计数：
```gdscript
## 记一次投镖统计:累计投镖数、累计/单次最大产出、各命中奖区计数。
func _track_throw(r: Dictionary) -> void:
	var gold := float(r.get("gold", 0.0))
	var hits: Array = r.get("hits", [])
	stats.add(&"dart_throws", float(hits.size()))
	stats.add(&"total_gold", gold)
	stats.record_max(&"max_payout", gold)
	for h in hits:
		stats.add(StringName("dart_seg_%s" % String(h.get("seg", &"none"))), 1.0)
	_evaluate_achievements()
```

- [ ] **Step 2: 改 `achievement_catalog.gd`——靶心档成就 → 转盘奖区**

先读 `examples/fortune-mill/systems/achievement_catalog.gd` 找到 darts 靶心档相关条目（stat_key 形如 `dart_tier_N`）。把它们替换为转盘奖区成就，stat_key 用 `dart_seg_<name>`：
- `dart_seg_jackpot`（首命中 JACKPOT，阈值 1）
- `dart_seg_x100`（阈值 1）
- `dart_seg_x20a` / `dart_seg_x20b` 合并意义（可只保 `dart_seg_x100` + jackpot + 一条 `dart_seg_vermin`「运气不好」）
- 保留与档位无关的：`dart_throws` 里程碑、`total_gold` 里程碑、`guard_darts`。

**规则**：逐条把 `dart_tier_%d` 键改为对应 `dart_seg_*` 键，条目数尽量保持不变（1:1 或合并后补充「manual jackpot」「x20 命中」等等值条目）；若净条目数变化，更新 `achievement_catalog.gd` 里的总数/注释与 spec 文档「51」处。改完读 `test/test_fortune_achievements.gd`：若它硬断言某 `dart_tier_*` 成就解锁，改成对应 `dart_seg_*`；`test/test_fortune_stats.gd` 同理（若断言 `dart_tier_*` 累加，改 `dart_seg_*`）。

- [ ] **Step 3: 改 `fortune_state.gd`——迁移 v3→v4（`_build_migrator`）**

在 `_build_migrator`（第 536-552 行）末尾、`return m` 前加 v3→v4：
```gdscript
	# v3→v4:飞镖房重构命运转盘——升级 id 改名(bullseye_training→widen_zone、rattling_gunner→hire_ai)
	# + 统计键 dart_tier_* → dart_seg_*(旧靶心档统计废弃,不再映射,新档从 0 计)。
	m.register(3, func(d: Dictionary) -> Dictionary:
		var darts_d = d.get("darts", {})
		if darts_d is Dictionary and darts_d.has("levels"):
			var lv: Dictionary = darts_d["levels"]
			if lv.has("bullseye_training"):
				lv["widen_zone"] = lv["bullseye_training"]; lv.erase("bullseye_training")
			if lv.has("rattling_gunner"):
				lv["hire_ai"] = lv["rattling_gunner"]; lv.erase("rattling_gunner")
			darts_d["levels"] = lv
			d["darts"] = darts_d
		var st = d.get("stats", {})
		if st is Dictionary:
			for k in st.keys():
				if String(k).begins_with("dart_tier_"):
					st.erase(k)   # 旧靶心档统计废弃
			d["stats"] = st
		return d)
```

- [ ] **Step 4: 加迁移测试 `test/test_fortune_migration.gd`（v3→v4 用例）**

读现有 `test/test_fortune_migration.gd` 的结构，仿其风格加一个 case：构造 `{"schema_version":3, "darts":{"levels":{"bullseye_training":2,"rattling_gunner":3}}, "stats":{"dart_tier_5":9}}`，跑 `_migrator.migrate`（或它构造 SaveMigrator 的方式），断言 `ok==true`、结果 `darts.levels.widen_zone==2`、`hire_ai==3`、无 `bullseye_training`/`rattling_gunner`、`stats` 无 `dart_tier_5`。

> 注：`test_fortune_migration.gd` 直接测 `SaveMigrator`；若它硬编码「目标版本=3」，改为 4，并确保它注册了 v1/v2/v3 三步（或复用 `FortuneMill._build_migrator` 的等价链）。

- [ ] **Step 5: 跑受影响的 4 个测试确认全过**

```bash
godot --headless --path . -s res://test/test_fortune_migration.gd
godot --headless --path . -s res://test/test_fortune_stats.gd
godot --headless --path . -s res://test/test_fortune_achievements.gd
godot --headless --path . -s res://test/test_fortune_darts.gd
```
Expected: 每个都 `... ALL PASS`。

- [ ] **Step 6: import + 提交**

```bash
godot --headless --path . --import
git add examples/fortune-mill/systems/fortune_state.gd examples/fortune-mill/systems/fortune_state.gd.uid examples/fortune-mill/systems/achievement_catalog.gd examples/fortune-mill/systems/achievement_catalog.gd.uid test/test_fortune_migration.gd test/test_fortune_stats.gd test/test_fortune_achievements.gd
git commit -m "$(printf 'feat(fortune-mill): FortuneMill 装配转盘 throw(aim,power)+update tick+统计/成就适配+迁移 v3→v4\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 4: 双端输入适配（darts_input.gd + 纯映射测试）

**Files:**
- Create: `examples/fortune-mill/scenes/darts_input.gd`
- Create: `test/test_fortune_input.gd`

**Interfaces:**
- Produces（`class_name FortuneDartsInput extends Node`）：
  - static `desktop_aim(mouse_y: float, view_h: float) -> float`（0..1）
  - static `desktop_power(hold_seconds: float, sweet: float) -> float`（0..1，摆动三角波）
  - static `touch_aim(drag: Vector2) -> float`、static `touch_power(drag: Vector2, max_len: float) -> float`
  - `signal thrown(aim: float, power: float)`；`signal aim_changed(aim)`；`signal power_changed(power)`
  - `set_mode(mode: StringName)`（`&"desktop"`/`&"touch"`）、`current_mode() -> StringName`、`func detect_mode() -> StringName`（`OS.has_feature("mobile")` 或触屏 → touch，否则 desktop；`CoreKit.settings` 覆盖）
- 纯 static 数学（`desktop_*`/`touch_*`）→ 可无头测；节点部分读 `InputEvent` 在 view。

- [ ] **Step 1: 写失败测试 `test/test_fortune_input.gd`**

```gdscript
extends SceneTree
## FortuneDartsInput 纯输入映射断言(不含节点/事件)。运行:-s res://test/test_fortune_input.gd
const DI := preload("res://examples/fortune-mill/scenes/darts_input.gd")

func _initialize() -> void:
	var failures := 0

	# 1. desktop_aim:鼠标顶端→0、底端→1、中间→0.5
	if absf(DI.desktop_aim(0.0, 600.0) - 0.0) > 0.001 or absf(DI.desktop_aim(600.0, 600.0) - 1.0) > 0.001 or absf(DI.desktop_aim(300.0, 600.0) - 0.5) > 0.001:
		print("FAIL 1: desktop_aim 边界/中点"); failures += 1

	# 2. desktop_power:三角摆动在 [0,1],甜点附近达峰
	var p := DI.desktop_power(0.0, 0.6)
	if p < 0.0 or p > 1.0:
		print("FAIL 2: desktop_power 应在 [0,1]"); failures += 1

	# 3. touch:向左上拖 → 反方向(右下)=方向;拖越长 power 越大
	var short := DI.touch_power(Vector2(-40, 0), 200.0)
	var long := DI.touch_power(Vector2(-160, 0), 200.0)
	if not (long > short and long <= 1.0 and short >= 0.0):
		print("FAIL 3: touch_power 应随拖长单调升且封顶 1"); failures += 1

	# 4. touch_aim:纯水平拖 aim≈0.5(无纵向分量);向下拖 aim 增
	var a_mid := DI.touch_aim(Vector2(-100, 0))
	var a_dn := DI.touch_aim(Vector2(-100, 80))
	if absf(a_mid - 0.5) > 0.05 or not (a_dn > a_mid):
		print("FAIL 4: touch_aim 纵向映射"); failures += 1

	if failures == 0:
		print("test_fortune_input: ALL PASS"); quit(0)
	else:
		print("test_fortune_input: %d FAILURE(S)" % failures); quit(1)
```

- [ ] **Step 2: 运行确认失败** — `godot --headless --path . -s res://test/test_fortune_input.gd`（文件不存在）。

- [ ] **Step 3: 实现 `examples/fortune-mill/scenes/darts_input.gd`**

```gdscript
class_name FortuneDartsInput
extends Node
## 双端输入适配:把「鼠标瞄准+蓄力」/「触屏拉弓」都归结为 (aim,power) 一对量,发 thrown 信号。
## 纯映射数学是 static(可无头测);节点部分读 InputEvent 供 view 用。model/经济与本层解耦。

signal thrown(aim: float, power: float)
signal aim_changed(aim: float)
signal power_changed(power: float)

const POWER_SWEET := 0.6     ## 与 FortuneWheelLayout.POWER_SWEET 对齐
const POWER_PERIOD := 1.2    ## 力度摆动周期(秒)
const DRAG_MAX := 240.0      ## 触屏拉弓最大有效拖距(px)

var _mode: StringName = &"desktop"
var _charging: bool = false
var _hold: float = 0.0
var _aim: float = 0.5


# --- 纯映射(static,可测) ---

static func desktop_aim(mouse_y: float, view_h: float) -> float:
	if view_h <= 0.0:
		return 0.5
	return clampf(mouse_y / view_h, 0.0, 1.0)


## 蓄力三角摆动:hold 秒 → [0,1] 往返(逼玩家把握时机)。
static func desktop_power(hold_seconds: float, _sweet: float) -> float:
	var phase := fposmod(hold_seconds / POWER_PERIOD, 1.0)
	return 1.0 - absf(phase * 2.0 - 1.0)   # 0→1→0 三角波


## 触屏:拖向量的纵向分量 → aim(0..1);中点 0.5。
static func touch_aim(drag: Vector2) -> float:
	return clampf(0.5 + drag.y / (DRAG_MAX * 2.0), 0.0, 1.0)


## 触屏:拖长 → power(0..1),封顶。
static func touch_power(drag: Vector2, max_len: float) -> float:
	if max_len <= 0.0:
		return 0.0
	return clampf(drag.length() / max_len, 0.0, 1.0)


# --- 节点侧(view 用) ---

func detect_mode() -> StringName:
	# 设置覆盖优先;否则平台判定
	var forced := CoreKit.settings.get_value("darts_input", "")
	if forced == "desktop" or forced == "touch":
		return StringName(forced)
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		return &"touch"
	return &"desktop"


func set_mode(mode: StringName) -> void:
	_mode = mode


func current_mode() -> StringName:
	return _mode


func _ready() -> void:
	_mode = detect_mode()


func _process(delta: float) -> void:
	if _mode == &"desktop" and _charging:
		_hold += delta
		power_changed.emit(desktop_power(_hold, POWER_SWEET))


## desktop:按下开始蓄力、松开投掷;aim 由 view 每帧用鼠标 y 调 set_aim。
## touch:view 用 drag 向量算 aim/power,松手调 fire。(具体事件在 view 的 FSM 里接,见 Task 5)
func set_aim(aim: float) -> void:
	_aim = clampf(aim, 0.0, 1.0)
	aim_changed.emit(_aim)


func begin_charge() -> void:
	_charging = true
	_hold = 0.0


func release() -> void:
	if not _charging:
		return
	_charging = false
	thrown.emit(_aim, desktop_power(_hold, POWER_SWEET))


## touch 一次性投掷(view 从 drag 算好 aim/power 直接投)。
func fire(aim: float, power: float) -> void:
	thrown.emit(clampf(aim, 0.0, 1.0), clampf(power, 0.0, 1.0))
```

- [ ] **Step 4: 运行确认通过** — `test_fortune_input: ALL PASS`。

- [ ] **Step 5: import + 提交**

```bash
godot --headless --path . --import
git add examples/fortune-mill/scenes/darts_input.gd examples/fortune-mill/scenes/darts_input.gd.uid test/test_fortune_input.gd test/test_fortune_input.gd.uid
git commit -m "$(printf 'feat(fortune-mill): 双端输入适配 FortuneDartsInput(桌面瞄准+蓄力 / 触屏拉弓 → aim,power)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 5: 飞镖房横版视图 + KitStateMachine 投掷态机（world 场景）

**Files:**
- Modify: `examples/fortune-mill/scenes/world.gd`（飞镖房面板重构为横版转盘视图 + 投掷态机）

**Interfaces:**
- Consumes: `FortuneMill.do_throw(aim,power)`（Task 3）、`FortuneMill.darts.wheel_angle`、`FortuneDartsInput`（Task 4）、`FortuneArtBank`/`FortuneFx`/`FortuneSoundBank`（现有 gfx/sfx）、`KitStateMachine`/`KitState`。
- 本任务只在**非 smoke 路径**（`_build_ui` 内）生效；smoke 路径不受影响。

> 说明：本任务是纯表现/输入接线，无头无法断言像素；验收＝`--import` 解析干净 + 非 smoke world 启动 90 帧无 `ERROR:` + 现有 smoke 仍绿。渲染/Tween 细节在引擎内迭代打磨；下列给出必须落地的**结构与关键逻辑**。

- [ ] **Step 1: 在 world 飞镖房面板搭横版视图节点**（`_build_ui` 内，替换原飞镖 Throw 按钮那段）
  - 一个 `Node2D` 容器：左侧磨工占位、右侧转盘 `Node2D`（画 `FortuneWheelLayout.SEGMENTS` 扇区，`rotation_degrees = FortuneMill.darts.wheel_angle`，`_process` 里每帧同步）、金色中奖带随 `win_zone` 宽度画。
  - `var _darts_input := FortuneDartsInput.new(); add_child(_darts_input)`；连 `thrown` → `_on_dart_thrown`。
  - 力度条 `ProgressBar`/自绘，连 `_darts_input.power_changed`；aim 指示连 `aim_changed`。

- [ ] **Step 2: KitStateMachine 投掷态机**（dogfood；4 态子节点）
  - 建 `KitStateMachine` 子节点，挂 4 个 `KitState` 子节点，节点名即态名：`Idle` / `Aim` / `Charge` / `Resolve`。
  - 桌面：`Idle` 里 `handle_input` 按下左键 → `_darts_input.begin_charge()` + `transition_to("Charge")`；`Charge.update` 用鼠标 y 调 `_darts_input.set_aim(...)`，松开 → `_darts_input.release()` + `transition_to("Resolve")`。
  - 触屏：`Idle` 接 `InputEventScreenTouch`/`Drag` 累计 drag 向量 → `transition_to("Aim")`（显示预测弧线），松手 → `_darts_input.fire(FortuneDartsInput.touch_aim(drag), FortuneDartsInput.touch_power(drag, FortuneDartsInput.DRAG_MAX))` → `Resolve`。
  - `Resolve.enter`：播飞镖弧线 Tween + 落定 → 回 `Idle`。
  - 态机与输入模式：`_darts_input.current_mode()` 决定接哪套事件。

- [ ] **Step 3: `_on_dart_thrown(aim, power)` → 命令 model + 表现**

```gdscript
func _on_dart_thrown(aim: float, power: float) -> void:
	var r: Dictionary = FortuneMill.do_throw(aim, power)
	for h in r.get("hits", []):
		var pos: Vector2 = _wheel_hit_pos(h)   # 由 seg/r 反算盘面屏幕坐标
		_fx.popup("+%s" % Currency.format_short(float(h["gold"])), pos, _hit_color(h))
		if h["seg"] == &"jackpot":
			_fx.flash(Color(1, 0.85, 0.3))
		_play_sfx(&"throw", -6.0, randf_range(0.94, 1.06))
	# 金币雨即时:非 vermin 的命中迸金币(见 fx)
```
（`_play_sfx`/`_fx`/`Currency.format_short` 沿用现有；`_wheel_hit_pos`/`_hit_color` 本任务新增小工具。）

- [ ] **Step 4: 转盘旋转同步 + AI 磨工占位**
  - `_process(dt)`：`_wheel_node.rotation_degrees = FortuneMill.darts.wheel_angle`。
  - 若 `FortuneMill.darts.level_of(&"hire_ai") > 0`：显示 AI 磨工节点 + 按 `throws_per_sec` 间隔播一个「AI 投掷」表现（纯 juice，产出已由 `produce` 结算，不重复入账）。

- [ ] **Step 5: 验收（无头解析 + 启动干净 + smoke 未破）**

```bash
godot --headless --path . --import
# 非 smoke 启动 world 若干帧,断言 stderr 无 ERROR(需显示环境;CI 无显示时跳过此步,靠 import + smoke)
FORTUNE_SMOKE=1 godot --headless --path . res://examples/fortune-mill/scenes/world.tscn --quit-after 90
```
Expected: import exit=0；smoke 仍打印既有 `FORTUNE_SMOKE ... PASS`（本任务不碰 smoke 断言，Task 6 才扩）。

- [ ] **Step 6: 提交**

```bash
godot --headless --path . --import
git add examples/fortune-mill/scenes/world.gd examples/fortune-mill/scenes/world.gd.uid
git commit -m "$(printf 'feat(fortune-mill): 飞镖房横版转盘视图 + KitStateMachine 投掷态机 + 双端接线\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 6: FORTUNE_SMOKE 扩 + run_all + docs（收尾门）

**Files:**
- Modify: `examples/fortune-mill/scenes/world.gd`（smoke 块加转盘断言）
- Modify: `test/run_all.ps1`
- Modify: `examples/fortune-mill/docs/README.md`、`examples/fortune-mill/assets/README.md`

**Interfaces:**
- Consumes: 全部前置任务。smoke 在 `_build_ui` **前**返回,只测 model。

- [ ] **Step 1: world 的 FORTUNE_SMOKE 块加转盘断言**

在现有 smoke 块（`_ready` 里 `if FORTUNE_SMOKE` 段）加：确定性构造命中——
```gdscript
	# 命运转盘:对准 jackpot 甜点 → 单镖 base×500×radial2 = 1000;vermin → 0;AI 期望 >0
	FortuneMill.darts.wheel_angle = FortuneWheelLayout.jackpot_center()
	var wr := FortuneMill.do_throw(0.5, FortuneWheelLayout.POWER_SWEET)
	var wheel_ok := absf(float(wr["gold"]) - 1000.0) < 0.01 and wr["hits"][0]["seg"] == &"jackpot"
	FortuneMill.darts.wheel_angle = FortuneWheelLayout.vermin_center()
	var vermin_ok := absf(float(FortuneMill.do_throw(0.5, FortuneWheelLayout.POWER_SWEET)["gold"])) < 0.01
```
把 `wheel_ok and vermin_ok` 并进 smoke 总门（现有 `if p012 and ... :` 那行加 `and wheel_ok and vermin_ok`），PASS 行 append ` | wheel=jackpot%.0f/vermin0`（`float(wr["gold"])`）、FAIL 行 append `| wheel=%s vermin=%s`。

- [ ] **Step 2: 跑 smoke 确认 PASS**

```bash
FORTUNE_SMOKE=1 godot --headless --path . res://examples/fortune-mill/scenes/world.tscn --quit-after 120
```
Expected: `FORTUNE_SMOKE ... PASS ... | wheel=jackpot1000/vermin0`

- [ ] **Step 3: run_all.ps1 加 2 测 + 头注释**
  - 头注释（第 1 行）`37 个断言测试` → `39 个断言测试`。
  - `$tests` 数组：在 `'test_fortune_darts'` 后加 `'test_fortune_wheel'`；数组末尾（`test_fortune_offline` 后）加 `'test_fortune_input'`。

- [ ] **Step 4: 跑全量门**

```bash
powershell -File test\run_all.ps1
```
Expected: 结尾 `=== SUMMARY FAILS=0 ===`（39 测全 OK + demo/world smoke 干净）。

- [ ] **Step 5: docs**
  - `examples/fortune-mill/docs/README.md`：把飞镖房一节改写为「命运转盘真交互」（转盘/多难度奖区/径向精度/扎上即金币雨/双端操作/单 AI 随机→稳准/6 升级/KitStateMachine）。
  - `examples/fortune-mill/assets/README.md`：art/sfx key 若新增（wheel/coin/dart_stick）补 drop-in 表。

- [ ] **Step 6: 提交**

```bash
git add examples/fortune-mill/scenes/world.gd examples/fortune-mill/scenes/world.gd.uid test/run_all.ps1 examples/fortune-mill/docs/README.md examples/fortune-mill/assets/README.md
git commit -m "$(printf 'feat(fortune-mill): FORTUNE_SMOKE 扩转盘断言 + run_all 37→39 + docs(命运转盘)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Self-Review（对照 spec）

- **spec 覆盖**：①转盘 model=T1+T2；②双端输入=T4+T5；③throw(aim,power)+扇形多镖=T2；④单 AI 随机→稳准/期望值=T2；⑤6 升级线=T2(数据)+T2(_apply_upgrade);⑥数据表现分离=T1/T2 纯 model + T5 view;⑦迁移=T3;⑧KitStateMachine dogfood=T5;⑨测试=T1/T2/T4 + smoke T6;⑩范围=仅 Room 1;⑪验收=T6 门。全覆盖。
- **无占位符**：model/测试代码完整；T5 view 明确标注「引擎内迭代」并给出结构+关键逻辑（渲染细节属表现打磨，非算法）。T3 成就/统计适配需读现有文件对齐（已给规则 + 迁移完整代码 + 判据）。
- **类型/命名一致**：`throw(aim,power)` 返 `{gold,darts,hits}`；`FortuneWheelLayout` 静态方法名（`segment_at`/`expected_mult`/`radial_bonus`/`landing`/`fan_offsets`/`jackpot_center`/`vermin_center`/`jackpot_half_base`）在 T1 定义、T2/T6 引用一致；modifier target（`gold_per_dart`/`darts_per_throw`/`win_zone`/`aim_steady`/`throws_per_sec`/`ai_skill`）跨任务一致。
- **已知集成点/风险**：darts 靶心档成就→转盘奖区（T3 需读 `achievement_catalog.gd` 对齐总数与两个测试）；`aim_steady` 本切片主要作用 view 手感（放宽甜点/减晃动），model 结算不依赖它（不破 headless 断言）。`world.gd` smoke 块具体行号以实际为准（在 `_build_ui` 前那段）。
