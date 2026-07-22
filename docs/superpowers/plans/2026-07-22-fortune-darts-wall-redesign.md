# 飞镖房「墙面 + 全屏进入房」重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans（本轮由主会话内联 TDD 执行，不派 subagent）。Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把飞镖房从「旋转命运转盘」换成「玩家控发射角→确定命中档的静态墙面」，并做成从世界进入的全屏房，经济/升级/贿赂/离线/存档/成就全不动（换皮不换核）。

**Architecture:** 模型层只改两处（`landing()` 的 `a_off` 铺满整圈 + `DartsRoom.update()` 冻结旋转）并把 `SEGMENTS` 重排成竖墙栈、加静态 `aim_for()`；新全屏场景 `darts_room.tscn`/`darts_room_view.gd` 读 `FortuneMill` 命令层渲染墙面/抛物线/落地收集并接真投掷；`world.gd` 飞镖列改为摘要 + 进入按钮，用 `CoreKit.scenes.change_scene`（FADE）进出。

**Tech Stack:** Godot 4.7 GDScript（Tab 缩进）、godot-core-kit（`CoreKit.scenes` / `KitStateMachine` / `KitModifiers` / `Currency`）、headless 断言测试 + `FORTUNE_SMOKE` 冒烟。

## Global Constraints

- 分支 `example/fortune-mill`：**永不并 main / 不 push**（留用户）。
- 只动 Room 1 飞镖房；其余 4 房、跨房协同、经济内核、51 成就、`dart_seg_*` 统计、升级 id、`SCHEMA_VERSION=4` 一律不动 → **无存档迁移**。
- headless-first / 数据表现分离 / 不用大数库（float + `Currency`）/ 在线=离线。
- `test/` 在**仓库根**（非 example 目录）；跑单测 `godot --headless --path . -s res://test/<x>.gd`。
- 验收门：`powershell -File test\run_all.ps1` → `=== SUMMARY FAILS=0 ===`（断言总数保持 **39**）。
- 提交署名（example 惯例）：`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`。
- `project.godot` 恒显 `M`（pre-commit 钩子剥 `godot_ai` 行）——正常，不必处理。

---

### Task 1: 模型换墙 —— SEGMENTS 重排 + landing 整圈 + 冻结旋转 + aim_for()

**Files:**
- Modify: `examples/fortune-mill/systems/wheel_layout.gd`（`SEGMENTS` 重排、`landing()`、新增 `aim_for()`）
- Modify: `examples/fortune-mill/systems/darts_room.gd:43-46`（`update()` 改 no-op）
- Test: `test/test_fortune_wheel.gd`（改 landing 断言、加 aim_for 往返）

**Interfaces:**
- Produces:
  - `FortuneWheelLayout.SEGMENTS`：8 档，顺序重排为竖墙栈（top→bottom：x20a/x2a/x100/jackpot/vermin/x5/x2b/x20b），各档 `name/span/mult/vermin` 值不变，`span` 和 ≡ 360。
  - `FortuneWheelLayout.landing(aim, power) -> {r: float, a_off: float}`：`a_off = clampf(aim,0,1) * 360.0`（铺满整圈）；`r = clampf(absf(power-POWER_SWEET)/POWER_SWEET, 0, 1)`（不变）。
  - `FortuneWheelLayout.aim_for(name: StringName) -> float`：返回 `_center_of(name)/360.0`，满足 `segment_at(aim_for(n)*360.0, 0.0)["name"] == n`。
  - `DartsRoom.update(dt)`：no-op（`wheel_angle` 恒 0，墙面静态）。
- Consumes: 无（叶子层）。

- [ ] **Step 1: 改测试 —— test_fortune_wheel FAIL7（landing 整圈）+ 新增 aim_for 往返**

把 `test/test_fortune_wheel.gd` 的 `# 7. landing ...` 块（45-52 行）替换为下面内容，并在其后（`# 8. fan_offsets` 之前）插入新块 `# 7d`：

```gdscript
	# 7. landing 确定性 + 整圈映射:aim=0.5 → a_off=180(不再 0);甜点 power → r≈0
	var l_mid := WL.landing(0.5, WL.POWER_SWEET)
	if absf(float(l_mid["r"])) > 0.01:
		print("FAIL 7a: 甜点力度应 r≈0,实际 %s" % l_mid["r"]); failures += 1
	if absf(float(l_mid["a_off"]) - 180.0) > 0.01:
		print("FAIL 7b: aim=0.5 应 a_off≈180,实际 %s" % l_mid["a_off"]); failures += 1
	if absf(float(WL.landing(0.0, WL.POWER_SWEET)["a_off"])) > 0.01:
		print("FAIL 7c: aim=0 应 a_off≈0"); failures += 1
	if float(WL.landing(0.5, 1.0)["r"]) <= float(l_mid["r"]):
		print("FAIL 7d: 偏离甜点 r 应更大"); failures += 1

	# 7e. aim_for 往返:每档 aim_for(n) 都能确定命中该档
	for n in [&"jackpot", &"vermin", &"x100", &"x5", &"x20a"]:
		if WL.segment_at(WL.aim_for(n) * 360.0, 0.0)["name"] != n:
			print("FAIL 7e: aim_for(%s) 应命中 %s" % [n, n]); failures += 1
```

- [ ] **Step 2: 跑测试确认失败**

Run: `godot --headless --path . -s res://test/test_fortune_wheel.gd`
Expected: FAIL（`aim_for` 未定义 → 解析或运行错；或 landing a_off 还是旧值）。

- [ ] **Step 3: 实现 —— wheel_layout.gd 重排 SEGMENTS + 改 landing + 加 aim_for**

`SEGMENTS`（7-16 行）整块替换为竖墙栈顺序（值不变、和≡360）：

```gdscript
## 竖直墙面奖区(top→bottom)。宽度=难度:越窄倍率越高;含一块 vermin 没收段。
## 语义为「墙」而非转盘:aim(发射角)线性映射到本序列,不旋转。span 和 ≡ 360。
const SEGMENTS := [
	{"name": &"x20a",    "span": 40.0, "mult": 20.0,  "vermin": false},
	{"name": &"x2a",     "span": 72.0, "mult": 2.0,   "vermin": false},
	{"name": &"x100",    "span": 30.0, "mult": 100.0, "vermin": false},
	{"name": &"jackpot", "span": 18.0, "mult": 500.0, "vermin": false},
	{"name": &"vermin",  "span": 40.0, "mult": 0.0,   "vermin": true},
	{"name": &"x5",      "span": 58.0, "mult": 5.0,   "vermin": false},
	{"name": &"x2b",     "span": 62.0, "mult": 2.0,   "vermin": false},
	{"name": &"x20b",    "span": 40.0, "mult": 20.0,  "vermin": false},
]
```

`landing()`（78-81 行）的 `a_off` 改为铺满整圈：

```gdscript
## (aim,power) → 墙面落点 {r(离档心 0..1), a_off(发射角映射的墙面角 °)}。纯确定性,无 RNG。
## a_off 铺满整圈:aim 0..1 线性映射 0..360,配合冻结旋转 → 发射角唯一决定命中档。
static func landing(aim: float, power: float) -> Dictionary:
	var a_off := clampf(aim, 0.0, 1.0) * 360.0
	var r := clampf(absf(power - POWER_SWEET) / POWER_SWEET, 0.0, 1.0)
	return {"r": r, "a_off": a_off}
```

在 `landing()` 之后新增静态辅助：

```gdscript
## 能确定命中某档的 aim 值(该档中心角 / 360)。用于 smoke / 测试 / view 预览。
static func aim_for(name: StringName) -> float:
	return _center_of(name) / 360.0
```

- [ ] **Step 4: 冻结旋转 —— darts_room.gd update() 改 no-op**

`darts_room.gd:42-46` 的 `update()` 整块替换：

```gdscript
## 墙面静态,无旋转:update 为 no-op(保留供 autoload ticker 调用,wheel_angle 恒 0)。
## 命中档只由发射角(aim)决定,throw 里 wheel_angle 项恒为 0 → 落点确定。
func update(_dt: float) -> void:
	pass
```

- [ ] **Step 5: 跑 wheel 测试确认通过**

Run: `godot --headless --path . -s res://test/test_fortune_wheel.gd`
Expected: `test_fortune_wheel: ALL PASS`（FAIL1 和≡360 仍成立；FAIL2/3/4 用 jackpot_center/vermin_center 重算后仍成立；FAIL7/7e 新断言通过）。

- [ ] **Step 6: Commit**

```bash
git add examples/fortune-mill/systems/wheel_layout.gd examples/fortune-mill/systems/darts_room.gd test/test_fortune_wheel.gd
git commit -m "feat(fortune-mill): 飞镖房换墙——SEGMENTS 重排竖栈+landing 整圈+aim_for+冻结旋转(T1/换皮不换核)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: test_fortune_darts aim 化 + 冻结断言

**Files:**
- Test: `test/test_fortune_darts.gd`（把设 `wheel_angle` 的命中改为 `aim_for` 驱动；加 update no-op 断言）

**Interfaces:**
- Consumes: Task 1 的 `WL.aim_for(name)`、`WL.landing`（a_off=aim*360）、`DartsRoom.update()` no-op。
- Produces: 无（测试）。

- [ ] **Step 1: 改测试 —— 用 aim_for 反推命中，去掉 wheel_angle**

在 `test/test_fortune_darts.gd` 做以下替换（其余断言不动）：

`_aim_jackpot`（37-38 行）删除该 helper（不再设 wheel_angle）。FAIL1 块（46-47 行）：

```gdscript
	var r = room.throw(WL.aim_for(&"jackpot"), WL.POWER_SWEET)
```

FAIL2 块（55-56 行）：

```gdscript
	var r2 = room2.throw(WL.aim_for(&"vermin"), WL.POWER_SWEET)
```
（删除其上一行 `room2.wheel_angle = WL.vermin_center()`）

FAIL3 块（62-63 行）：删除 `_aim_jackpot(room3)`，改：

```gdscript
	var r3 = room3.throw(WL.aim_for(&"jackpot"), 0.0)
```

FAIL4 块（71-72 行）：删除 `_aim_jackpot(room4)`，改：

```gdscript
	var r4 = room4.throw(WL.aim_for(&"jackpot"), WL.POWER_SWEET)
```

FAIL5 块（79-83 行）：把设 `wheel_angle` 改为 aim（jackpot 带外低侧一点，未升级命中 x100、升级后变 jackpot）：

```gdscript
	# 令落点在 jackpot 中心 - 基础半宽 - 8°(基础带外,x100 侧)
	var edge_aim := (WL.jackpot_center() - WL.jackpot_half_base() - 8.0) / 360.0
	var before = room5.throw(edge_aim, WL.POWER_SWEET)   # 非 jackpot(x100)
	cur5.add(100000.0)
	for _i in 3: room5.buy_upgrade(&"widen_zone")   # win_zone +18°
	var after = room5.throw(edge_aim, WL.POWER_SWEET)    # 现应命中 jackpot
```

在 FAIL1 块之前（`_initialize` 起始 `var failures := 0` 之后）新增冻结断言：

```gdscript
	# 0. 冻结旋转:update 为 no-op,wheel_angle 恒 0
	var t0 = _room(_reg()); var room0 = t0[0]
	room0.update(1.0)
	if absf(room0.wheel_angle) > 0.0001:
		print("FAIL 0: update 应 no-op,wheel_angle 恒 0,实际 %s" % room0.wheel_angle); failures += 1
```

- [ ] **Step 2: 跑测试确认通过**

Run: `godot --headless --path . -s res://test/test_fortune_darts.gd`
Expected: `test_fortune_darts: ALL PASS`（12+1 断言全绿；jackpot 甜点单镖=1000、vermin=0、widen 生效、冻结成立）。

- [ ] **Step 3: Commit**

```bash
git add test/test_fortune_darts.gd
git commit -m "test(fortune-mill): darts 测试 aim 化(aim_for 反推命中)+冻结旋转断言(T2)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: world.gd _run_smoke aim 化 + 冒烟标记 wall=

**Files:**
- Modify: `examples/fortune-mill/scenes/world.gd`（`_run_smoke` 内 136-148 行 + PASS 打印的 `wheel=` 标记）

**Interfaces:**
- Consumes: Task 1 的 `FortuneWheelLayout.aim_for(name)`。
- Produces: 冒烟 PASS 行含 `wall=jackpot1000/vermin0`。

- [ ] **Step 1: 改冒烟 —— 命运转盘定点验证段（136-140 行）aim 化**

`world.gd:136-140` 替换为：

```gdscript
	# --- 墙面定点验证(趁未升级:单镖 base×500×radial2=1000;vermin→0;两投顺带喂 jackpot/vermin 统计)---
	var wr: Dictionary = fm.do_throw(FortuneWheelLayout.aim_for(&"jackpot"), FortuneWheelLayout.POWER_SWEET)
	var wheel_ok: bool = absf(float(wr["gold"]) - 1000.0) < 0.01 and wr["hits"][0]["seg"] == &"jackpot"
	var vermin_ok: bool = absf(float(fm.do_throw(FortuneWheelLayout.aim_for(&"vermin"), FortuneWheelLayout.POWER_SWEET)["gold"])) < 0.01
```

- [ ] **Step 2: 改 P0 爬 1M 段（142-148 行）—— 去 wheel_angle，aim 对准 jackpot**

`world.gd:142-148` 替换为：

```gdscript
	# --- P0:飞镖房手动爬到 1M 贿赂 Verminous(墙面:aim 对准 jackpot 甜点确定性投)---
	var jackpot_aim: float = FortuneWheelLayout.aim_for(&"jackpot")
	while not fm.can_bribe() and steps < SMOKE_MAX_STEPS:
		fm.do_throw(jackpot_aim, FortuneWheelLayout.POWER_SWEET)
		if steps % 20 == 0:
			_smoke_buy_round(fm)
		steps += 1
	var ok: bool = fm.can_bribe() and fm.bribe_guard()
```

- [ ] **Step 3: 改 PASS 打印标记 wheel= → wall=**

Run 先定位：`grep -n 'wheel=' examples/fortune-mill/scenes/world.gd`
把 PASS 打印里 `wheel=jackpot1000/vermin0`（用 `wheel_ok`/`vermin_ok` 组装的那段字符串）改为 `wall=jackpot1000/vermin0`（保留 `wheel_ok`/`vermin_ok` 变量名与 348 行的判定不变，仅改可见标记文案）。

- [ ] **Step 4: 跑冒烟确认 PASS**

Run: `$env:FORTUNE_SMOKE='1'; godot --headless --path . res://examples/fortune-mill/scenes/world.tscn --quit-after 30; Remove-Item Env:FORTUNE_SMOKE`
Expected: 输出含 `PASS` 且含 `wall=jackpot1000/vermin0`（stderr 无 ERROR/SCRIPT ERROR）。

- [ ] **Step 5: 跑全量门确认 39 FAILS=0**

Run: `powershell -File test\run_all.ps1`
Expected: `=== SUMMARY FAILS=0 ===`（39 测 + demo 冒烟干净）。

- [ ] **Step 6: Commit**

```bash
git add examples/fortune-mill/scenes/world.gd
git commit -m "test(fortune-mill): FORTUNE_SMOKE aim 化+标记 wall=jackpot1000/vermin0,run_all 39 FAILS=0(T3)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: 全屏墙房场景 darts_room.tscn + darts_room_view.gd（读真 model）

**Files:**
- Create: `examples/fortune-mill/scenes/darts_room_view.gd`（`Control`，全屏墙房）
- Create: `examples/fortune-mill/scenes/darts_room.tscn`（root Control「DartsRoom」1152×648，挂脚本）
- Reference（移植视觉内核）: `examples/fortune-mill/scenes/proto_boss_stage.gd`（抛物线/落地间隔收集/手感/墙面绘制原型）
- Reference（迁入投掷）: `examples/fortune-mill/scenes/world.gd:1091-1117`（`_ThrowState`）、`world.gd:634-724`（FSM/输入/aim 喂食）

**Interfaces:**
- Consumes:
  - `FortuneMill.do_throw(aim, power) -> {gold, darts, hits:[{seg,mult,r,gold,vermin}]}`
  - `FortuneMill.buy_dart_upgrade(id)`、`FortuneMill.bribe_guard()`、`FortuneMill.can_bribe()`
  - `FortuneMill.darts.level_of(id)`、`.cost_of(id)`、`.auto_gold_rate()`、`FortuneMill.currency`
  - `FortuneMill.registry.ids(&"dart_upgrade", true)`、`.get_def(&"dart_upgrade", id)`
  - `FortuneWheelLayout.SEGMENTS`（8 档，按序）；`FortuneDartsInput`；`KitStateMachine`
- Produces:
  - `darts_room_view.gd` 方法 `band_rect_for(seg_name: StringName) -> Rect2`：按 `SEGMENTS` 的 span 比例把墙面竖切成 8 带，返回该档屏幕矩形（供飞镖扎点/金币迸射用）。
  - 场景路径常量供 Task 5 引用：`res://examples/fortune-mill/scenes/darts_room.tscn`。

- [ ] **Step 1: 建脚本骨架 —— 全屏墙房 + 读 model 刷新**

`script_create` `darts_room_view.gd`：`extends Control`。核心成员/方法（先只做「能显示 + 能投出真 gold + 升级/贿赂/返回」，视觉后步细化）：

```gdscript
extends Control
## 飞镖墙房(全屏进入式)。读 FortuneMill 命令层:玩家控发射角(aim)+蓄力(power) →
## do_throw → 飞镖抛物线扎进 model 判定的档 → 金币落地间隔收集;升级/贿赂真扣真过关。
## 换皮不换核:结算/经济全在 FortuneMill/DartsRoom,本类只做输入+表现。

const WORLD_SCENE := "res://examples/fortune-mill/scenes/world.tscn"

var _stage: Control                     # 自绘墙面/飞镖/金币的画布
var _gold_label: Label
var _rate_label: Label
var _bribe_button: Button
var _upgrade_buttons: Dictionary = {}   # id -> Button
var _darts_input                        # FortuneDartsInput
var _throw_fsm                          # KitStateMachine
var _power_bar: ProgressBar

func _ready() -> void:
	_build_ui()
	_build_throw_fsm()
	_darts_input = FortuneDartsInput.new(); add_child(_darts_input)
	_apply_input_mode()
	_darts_input.thrown.connect(_on_dart_thrown)
	_darts_input.power_changed.connect(func(p): if _power_bar: _power_bar.value = p)
	CoreKit.bus.subscribe("fortune:currency_changed", _on_dirty)
	CoreKit.bus.subscribe("fortune:upgrade_purchased", _on_dirty)
	CoreKit.bus.subscribe("fortune:room_cleared", _on_dirty)
	_refresh()

func _on_dirty(_p = null) -> void:
	_refresh()

## 命令 model + 表现:每支镖扎进其 seg 对应的墙带,金币按真 hit.gold 迸射落地。
func _on_dart_thrown(aim: float, power: float) -> void:
	if _throw_fsm != null: _throw_fsm.transition_to("Resolve")
	var r: Dictionary = FortuneMill.do_throw(aim, power)
	for h in r.get("hits", []):
		var rect := band_rect_for(h.get("seg", &""))
		_stage.spawn_dart_and_coins(rect.get_center(), float(h.get("gold", 0.0)), bool(h.get("vermin", false)))
	_refresh()

## 按 SEGMENTS 的 span 比例把墙面竖切成 8 带,返回该档在 _stage 内的矩形。
func band_rect_for(seg_name: StringName) -> Rect2:
	var wall := _stage.wall_rect()
	var acc := 0.0
	for s in FortuneWheelLayout.SEGMENTS:
		var frac := float(s["span"]) / 360.0
		if s["name"] == seg_name:
			return Rect2(wall.position.x, wall.position.y + acc * wall.size.y, wall.size.x, frac * wall.size.y)
		acc += frac
	return wall

func _refresh() -> void:
	_gold_label.text = "Gold: %s" % Currency.format(FortuneMill.currency.get_amount())
	_rate_label.text = "自动: %s gold/s" % Currency.format(FortuneMill.darts.auto_gold_rate())
	for id in _upgrade_buttons:
		var def = FortuneMill.registry.get_def(&"dart_upgrade", id)
		var cost := FortuneMill.darts.cost_of(id)
		var btn: Button = _upgrade_buttons[id]
		btn.text = "%s  Lv.%d  (%s)" % [def.title, FortuneMill.darts.level_of(id), Currency.format(cost)]
		btn.disabled = not FortuneMill.currency.can_afford(cost)
	_bribe_button.disabled = not FortuneMill.can_bribe()
```

- [ ] **Step 2: 建 UI + 返回按钮 + 迁入 FSM/输入（移植 world.gd）**

在 `darts_room_view.gd` 补 `_build_ui()`（HUD：金币/自动/力度条/Throw 按钮/升级按钮循环 `for id in FortuneMill.registry.ids(&"dart_upgrade", true)` 接 `buy_dart_upgrade`/贿赂按钮接 `bribe_guard`/**返回按钮**）、`_build_throw_fsm()`、`_apply_input_mode()`、桌面 `_on_throw_down/_on_throw_up`、`_process`（桌面蓄力中 `set_aim(desktop_aim(mouse_y,vh))`）、`_resolve_then_idle()`——从 `world.gd:624-724` 原样迁入（把 `_wheel_view` 相关删掉，aim 喂食保留）。内嵌 `_ThrowState`（从 `world.gd:1091-1117` 原样迁入）。返回按钮：

```gdscript
	var back := Button.new(); back.text = "← 返回世界"
	back.pressed.connect(func() -> void:
		await CoreKit.scenes.change_scene(WORLD_SCENE, {"transition": CoreKit.scenes.Transition.FADE}))
	# 放到 HUD 顶部
```

- [ ] **Step 3: Stage 画布 —— 墙面 8 带 + 抛物线飞镖 + 落地间隔收集（移植原型）**

给 `_stage` 挂一个内部/独立自绘 `Control`，移植 `proto_boss_stage.gd` 的：`_draw_bg`、墙面绘制（把原型 6 `ZONES` 换成读 `FortuneWheelLayout.SEGMENTS` 的 8 带，颜色用 world.gd `_wheel_palette()` 那套 seg→Color）、`_draw_guard`、`_draw_thrower`、抛物线 `_process`（`GRAV`/`_launch_vel`）、金币三态 `burst→rest→seek` + `COLLECT_INTERVAL` **只收 rest**、`_draw_power_bar`。**关键改动 vs 原型**：不再随机决定扎点/金币，改由 `spawn_dart_and_coins(pos, gold, vermin)` 接口——`pos` 来自 `band_rect_for(seg).get_center()`、金币颗数按 `gold` 映射。新增 `wall_rect() -> Rect2` 返回墙面矩形（供 `band_rect_for`）。`_stage` 提供：

```gdscript
func wall_rect() -> Rect2: ...                                   # 墙面在 stage 内的矩形
func spawn_dart_and_coins(target: Vector2, gold: float, vermin: bool) -> void: ...  # 抛物线飞镖→扎 target→金币迸射落地
```

- [ ] **Step 4: 建场景 + 挂脚本 + 保存**

`scene_manage(op=create)` root `Control` 名 `DartsRoom`，`offset_right=1152 offset_bottom=648`；`script_attach` `darts_room_view.gd`；`scene_save` 到 `res://examples/fortune-mill/scenes/darts_room.tscn`。

- [ ] **Step 5: 实时编辑器 run 验证（截图）**

先 `project_manage(op=stop)`，再 `project_run(mode=custom, scene=res://examples/fortune-mill/scenes/darts_room.tscn)`，`editor_screenshot(source=game)`：
- 看到墙面 8 带 + 投掷者 + 守卫铁门 + HUD 金币/升级/贿赂/返回。
- 按住 Throw 蓄力→松手→飞镖走抛物线扎进某带→金币迸射落地→间隔飞向计数器；金币计数随真 gold 增长。
- 点升级按钮金币减少、Lv 增；金币刷到 1M 时贿赂按钮可用、点击过关（`fortune:room_cleared`）。
- 空中金币不被间隔收集卷走（只收落地的）。
截图逐轮微调墙栈配色/纵深/手感（视觉在编辑器内迭代）。

- [ ] **Step 6: Commit**

```bash
git add examples/fortune-mill/scenes/darts_room_view.gd examples/fortune-mill/scenes/darts_room_view.gd.uid examples/fortune-mill/scenes/darts_room.tscn
git commit -m "feat(fortune-mill): 全屏墙房 darts_room——读真 model 抛物线投掷+落地间隔收集+升级/贿赂/返回(T4)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: world.gd 飞镖列改摘要+进入按钮 + 场景进出 + docs

**Files:**
- Modify: `examples/fortune-mill/scenes/world.gd`（飞镖列 `_build_ui` 392-433、`_refresh` 905-915、`_process` 714-724、删除迁走的飞镖专属代码）
- Modify: `examples/fortune-mill/docs/`（飞镖房功能文档：命运转盘 → 墙面 + 全屏房；grep 旧「转盘」）

**Interfaces:**
- Consumes: Task 4 的 `res://examples/fortune-mill/scenes/darts_room.tscn`；`CoreKit.scenes.change_scene(target, {"transition": ...})`。
- Produces: `world.tscn` 飞镖列 = 金币/自动摘要 + `进入飞镖房` 按钮（切场景 FADE）。

- [ ] **Step 1: 飞镖列改摘要 + 进入按钮**

`world.gd:_build_ui` 飞镖列块（392-433）：保留 `_gold_label`/`_rate_label`/`_status_label` 三行摘要；删除 `_WheelView` 实例化、`_power_bar`、`_darts_input`、`_build_throw_fsm()`、Throw 按钮、升级按钮循环、`_bribe_button`；改为加一个进入按钮：

```gdscript
	var enter := Button.new()
	enter.text = "进入飞镖房 ▶"
	enter.pressed.connect(func() -> void:
		await CoreKit.scenes.change_scene(
			"res://examples/fortune-mill/scenes/darts_room.tscn",
			{"transition": CoreKit.scenes.Transition.FADE}))
	dcol.add_child(enter)
	_status_label.text = "把飞镖房搬进全屏——点上方进入"
```

- [ ] **Step 2: 精简 _refresh 飞镖块 + _process + 删除迁走的函数/成员**

- `_refresh`（905-915）：保留 `_gold_label`/`_rate_label`；删除升级按钮循环与 `_bribe_button.disabled`；改 `_status_label` 为过关态摘要：

```gdscript
	_gold_label.text = "Gold: %s" % Currency.format(FortuneMill.currency.get_amount())
	_rate_label.text = "自动: %s gold/s" % Currency.format(FortuneMill.darts.auto_gold_rate())
	_status_label.text = "✅ 已贿赂 Verminous" if FortuneMill.darts.is_cleared() else "把飞镖房搬进全屏——点上方进入"
```

- `_process`（714-724）：删除整个函数体（飞镖 wheel view/aim 喂食已迁走；其余房不用 _process）——保留空 `_process` 或直接删除函数。
- 删除迁走的飞镖专属：`_build_throw_fsm`、`_on_throw_down/_on_throw_up`、`_on_power_changed`、`_on_dart_thrown`、`_resolve_then_idle`、`_wheel_hit_pos`、`_hit_color`、`_wheel_palette`、`_apply_input_mode`，内部类 `_WheelView`、`_ThrowState`，成员 `_wheel_view`/`_power_bar`/`_darts_input`/`_throw_fsm`/`_dart_upgrade_buttons`/`_bribe_button`。**保留** `_fx`/`_sfx`/`_pop_at`/`_pulse_button`/`_play_sfx`/`_pulse_button`（其余房用）。逐个 `grep` 确认无残留引用再删。

- [ ] **Step 3: run_all 门 —— 39 FAILS=0（冒烟不受 UI 改动影响）**

Run: `powershell -File test\run_all.ps1`
Expected: `=== SUMMARY FAILS=0 ===`（`_run_smoke` 在 `_ready` 提前 return、不进 `_build_ui`，故 UI 精简不影响冒烟；demo stderr 干净）。

- [ ] **Step 4: 实时编辑器 run 端到端（截图）**

`project_manage(op=stop)` → `project_run(mode=custom, scene=res://examples/fortune-mill/scenes/world.tscn)` → 截图：
- 飞镖列只剩金币/自动摘要 + `进入飞镖房 ▶`。
- 点进入 → FADE 淡入全屏墙房 → 投掷/升级/贿赂 → 点返回 → FADE 淡出回世界。
- 回世界后其余 4 房（刮刮乐/柏青哥/寿司/扭蛋 + 元进度/成就列）状态无损、无重复订阅报错（观察 `logs_read` 无 `ERROR:`）。

- [ ] **Step 5: docs 更新**

`grep -rl '转盘' examples/fortune-mill/docs/` 逐篇把飞镖房「命运转盘」表述改为「墙面 + 全屏进入房」，补一句进出经 `CoreKit.scenes.change_scene` FADE、状态靠 `FortuneMill` autoload 存活。

- [ ] **Step 6: Commit**

```bash
git add examples/fortune-mill/scenes/world.gd examples/fortune-mill/docs
git commit -m "feat(fortune-mill): world 飞镖列改摘要+进入全屏墙房(CoreKit.scenes FADE 进出)+docs(T5)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6（可选）: steady_hand/aim_steady → view 抛物线散布

**Files:**
- Modify: `examples/fortune-mill/scenes/darts_room_view.gd`（读 `aim_steady` 收紧散布，纯表现）

**Interfaces:**
- Consumes: `FortuneMill.modifiers.value_for(&"aim_steady", 0.0)`（steady_hand 升级写入，模型结算不读=不破坏确定性）。
- Produces: 无。

- [ ] **Step 1: 抛物线落点散布随 aim_steady 收紧**

在 `spawn_dart_and_coins` 里，飞镖扎点在 `target` 基础上加一个视觉抖动 `offset`，其幅度随 `aim_steady` 递减（仅表现，`target` 仍来自权威 `band_rect_for(seg)`——扎带不变，只微抖带内位置）：

```gdscript
	var steady := FortuneMill.modifiers.value_for(&"aim_steady", 0.0)
	var jitter := maxf(0.0, 14.0 - steady * 3.0)   # steady 越高抖动越小
	var visual := target + Vector2(randf_range(-jitter, jitter), randf_range(-jitter, jitter))
```

- [ ] **Step 2: 实时编辑器 run 验证**

run 世界→进飞镖房→买 steady_hand 若干级→观察飞镖扎点抖动明显收紧（金额/命中档不变，确定性保持）。

- [ ] **Step 3: Commit**

```bash
git add examples/fortune-mill/scenes/darts_room_view.gd
git commit -m "feat(fortune-mill): steady_hand 接线——aim_steady 收紧墙房飞镖散布(纯表现,T6)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage：**
- 模型两处改（landing 整圈 + 冻结旋转）→ Task 1 ✓
- SEGMENTS 重排竖墙栈 + aim_for() → Task 1 ✓
- 8 档保留 / 无迁移 → Task 1（值不变，SCHEMA 不动）✓
- 全屏墙房 darts_room.tscn/view（抛物线+落地间隔收集+真 do_throw/升级/贿赂）→ Task 4 ✓
- 进入式场景切换 CoreKit.scenes FADE 进出 → Task 4（返回）+ Task 5（进入）✓
- world 飞镖列改摘要+进入按钮、迁走 _WheelView/FSM/输入 → Task 5 ✓
- 测试改 test_fortune_wheel/test_fortune_darts/_run_smoke landing/旋转断言 → Task 1/2/3 ✓
- run_all 保持 39 FAILS=0 → Task 3 Step5 + Task 5 Step3 ✓
- steady_hand/aim_steady view 接线 → Task 6（可选）✓
- docs → Task 5 Step5 ✓

**Placeholder scan：** 无 TBD/TODO；TDD 任务（1-3）给出完整代码与命令；视觉移植任务（4）以既有原型 `proto_boss_stage.gd` 为移植源 + 明确 model 契约接口（`band_rect_for`/`spawn_dart_and_coins`/`do_throw`），非占位。

**Type consistency：** `aim_for(name)->float`、`landing->{r,a_off}`、`band_rect_for(StringName)->Rect2`、`wall_rect()->Rect2`、`spawn_dart_and_coins(Vector2,float,bool)`、`change_scene(target,{"transition":...})` 跨任务一致；seg 名（jackpot/vermin/x100/x5/x20a/x20b/x2a/x2b）全程一致。

**风险点（Task 5 Step4 须验）：** 切回 `world.tscn` 重跑 `_ready` 重新 `CoreKit.bus.subscribe`，旧 world 节点 `queue_free` 后其订阅回调失效——farm-sim 场景切换已在用 bus 视为先例，以 run + `logs_read` 无 `ERROR:` 验证无重复订阅/脏引用；若发现重复订阅，在 world `_ready` 订阅前先 `unsubscribe` 或改用 `_exit_tree` 退订。
