# farm-sim P0 · 视觉切片 实现计划

> **For agentic workers:** 逐 task 实现;每 task 收尾跑验收(headless smoke + 逻辑断言 +
> 编辑器手动手感检查),绿了再提交。步骤用 `- [ ]` 追踪。
> 设计 spec：`docs/superpowers/specs/2026-07-14-farm-sim-game-design.md`

**Goal（P0 done）：** 把现有 headless 循环变成看得见能玩的——能走小人、对着面前格子耕/种/浇、作物逐日生长、成熟收进背包、HUD 显示日期/金币/体力。全程占位美术。

**Architecture：** 逻辑与表现分离。`FarmGrid`（纯逻辑、headless 可测）持有格子状态 + 已种作物，经注入的 `KitInventory`/`KitDataRegistry` 做种植/收获；一层薄 `_draw` 占位渲染。`Player`(CharacterBody2D) 走动 + 朝向,工具作用于"面前那一格"。`HUD`(CanvasLayer 经 `CoreKit.layers`) 显示状态。逐日推进复用 `CoreKit.clock`。

**Tech Stack：** Godot 4.7 GDScript;core-kit 门面 + `KitInventory`/`KitDataRegistry`;占位渲染用 `_draw()` 彩色格(P5 再换 `TileMapLayer`+真 tileset)。

## Global Constraints

- 游戏代码全部在 `examples/farm-sim/`,留 `example/farm-sim` 分支,**不合 main、不升 kit 版本**。
- **不破坏现有 dogfood**:`game.gd`/`game.tscn` 及 crop.gd/farm.gd 等保持可跑(它们是 kit 回归);P0 新增游戏世界用**新文件**,复用数据(crop_def/item_def/.tres)与门面,不改动 dogfood 脚本逻辑。
- Tab 缩进;`extends`,游戏侧脚本**不加 class_name**(除非要被 .tscn 引用则用 ext_resource 路径,同现有 crop.tscn)。
- 验收硬指标:`powershell -File test\run_all.ps1` 仍 `=== SUMMARY FAILS=0 ===`(import 扫全工程含 examples,兜 parse error);world 场景 headless 跑 exit=0 且 stderr 无 `ERROR:`/`SCRIPT ERROR:`。
- headless 跑法:`godot --headless --path . res://examples/farm-sim/<scene>.tscn --quit-after 120`;新增 .tscn/.tres 后先 `godot --headless --path . --import`。godot exe:`D:\Program Files\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe`。
- 逻辑测试文件 `test/test_*.gd` 沿用现有约定(`extends SceneTree`,`_initialize()`,运行时 `load()` 不顶层 preload,`failures` 计数,ALL PASS + `quit(0/1)`);**不进 run_all**(那是 kit 门),游戏逻辑测单独手动跑,但要能过。

---

### Task 1：输入动作 + world 场景骨架

**Files:**
- Modify: `project.godot`（新增 `[input]` 段:`move_up/down/left/right`、`farm_use`、`farm_next_day`）
- Create: `examples/farm-sim/world.gd`、`examples/farm-sim/world.tscn`

**Interfaces:**
- Produces: `world.gd`(extends Node2D,P0 世界根,后续 task 往里挂 FarmGrid/Player/HUD)

- [ ] **Step 1**：给 `project.godot` 加 `[input]` 段,定义 6 个动作。键位:WASD 移动、`J`/空格 = `farm_use`、`N` = `farm_next_day`。用 `physical_keycode`(布局无关)。可先在 Godot 编辑器 Project Settings→Input Map 里加再存,或手写 `[input]` 段(格式见现有引擎序列化;不确定就编辑器加)。
- [ ] **Step 2**：写 `world.gd`:
```gdscript
extends Node2D
## 农场游戏世界根(P0 视觉切片)。持有农田网格 + 玩家 + HUD;复用 core-kit 数据/门面。
## 后续 task 在 _ready 里构建 FarmGrid/Player/HUD 并注入 registry/bag/shop。

func _ready() -> void:
	CoreKit.log.info("[World] 农场世界启动")
```
- [ ] **Step 3**：建 `world.tscn`:根 `World`(Node2D)挂 `world.gd`。暂空。
- [ ] **Step 4** 验收:`--import` 后 `godot --headless --path . res://examples/farm-sim/world.tscn --quit-after 30`,见 `[World] 农场世界启动`,exit=0,无 ERROR。

---

### Task 2：FarmGrid 网格模型（纯逻辑,headless 可测）

**Files:**
- Create: `examples/farm-sim/farm_grid.gd`
- Create: `test/test_farm_grid.gd`

**Interfaces:**
- Consumes: 注入的 `KitDataRegistry`(crop/item 定义)、`KitInventory`(背包)
- Produces:`FarmGrid`——`bind(registry, bag)`;格子状态 `EMPTY/TILLED/WATERED`;`till(cell)`/`plant(cell, crop_id)`/`water(cell)`/`harvest(cell)` 返回 bool;`tile_state(cell)`、`crop_stage(cell)`、`crop_mature(cell)`;`advance_day()`(推进所有作物一格);`cell_valid(cell)`;`size()`。cell 为 `Vector2i`。

- [ ] **Step 1**：写 `farm_grid.gd`。要点:
  - `enum State { EMPTY, TILLED, WATERED }`;`_state: Dictionary`(Vector2i→State)、`_crop: Dictionary`(Vector2i→{id, stage, days})。
  - `bind(registry, bag)` 注入。`till`:格空且未耕 → TILLED。`plant(cell, crop_id)`:格 TILLED/WATERED 且无作物 且 `bag.count(seed_item)>=1` → 扣种子 + 记 `_crop[cell]={id,stage:0}`。`water`:格 TILLED → WATERED(有作物也可浇)。`harvest(cell)`:该格作物 mature → `bag.add(harvest_item, amount, {}, max_stack)` + 清作物 + 格回 TILLED。
  - `advance_day()`:遍历 `_crop`,未成熟的 `stage+=1`(浇过水额外 +1 可留到 P2,P0 先固定 +1)。
  - `crop_mature(cell)`:`stage >= def.grow_days`。查定义走 `registry.get_def(&"crop", id)`(无类型对象,别用 `:=`)。
- [ ] **Step 2**：写 `test/test_farm_grid.gd`(extends SceneTree)。运行时 `load` FarmGrid/KitInventory/KitDataRegistry;载入 crops/items 数据;断言:
  - till 空格 → TILLED;非空格 till 返回 false
  - 背包有种子时 plant 成功且扣 1 种子;无种子 plant 返回 false
  - 未耕格 plant 返回 false
  - plant 后 advance_day×grow_days → crop_mature 为 true;harvest 入背包正确数量、格回 TILLED
- [ ] **Step 3** 验收:`godot --headless --path . -s res://test/test_farm_grid.gd` 打印 `ALL PASS`、exit=0。

---

### Task 3：FarmGrid 占位渲染（_draw 彩色格）

**Files:**
- Create: `examples/farm-sim/farm_grid_view.gd`(extends Node2D)
- Modify: `world.tscn`(挂 FarmGrid 视图节点)、`world.gd`(构建网格)

- [ ] **Step 1**：`farm_grid_view.gd`:`bind(grid)` 持有 FarmGrid;`_draw()` 遍历所有格,按状态填色(EMPTY 草绿 / TILLED 棕 / WATERED 深棕);有作物则在格中心画一个按 `stage/grow_days` 比例变大变色(未熟浅绿→成熟金黄)的小方块;`queue_redraw()` 在状态变化时调。常量 `CELL := 32`(像素);cell↔世界:`world = Vector2(cell) * CELL`。
- [ ] **Step 2**：`world.gd._ready` 里:`KitDataRegistry.new()` 载 crops/items;`KitInventory.new(20)` 塞几个起始种子;`FarmGrid.new().bind(registry,bag)` 建 10×8 网格;`FarmGridView` bind grid 加进树。
- [ ] **Step 3** 验收:编辑器打开 world.tscn 运行,**肉眼看到**一片草绿格子(手动手感检查);headless 跑无 ERROR。

---

### Task 4：玩家角色移动 + 朝向 + 相机

**Files:**
- Create: `examples/farm-sim/player.gd`(extends CharacterBody2D)、`examples/farm-sim/player.tscn`
- Modify: `world.tscn`/`world.gd`(挂 Player)

**Interfaces:**
- Produces:`Player`——`facing: Vector2i`(4 向,默认下);`tile_pos() -> Vector2i`(玩家所在格);`facing_cell() -> Vector2i`(= tile_pos + facing)。`CELL` 与 view 一致(共用常量或各自 const 一致值)。

- [ ] **Step 1**：`player.tscn`:根 `Player`(CharacterBody2D)+ 占位视觉(一个 `Polygon2D`/`ColorRect` 身体 + 一个小三角 `Polygon2D` 表朝向)+ `CollisionShape2D` + `Camera2D`(挂玩家下,`enabled`)。
- [ ] **Step 2**：`player.gd`:`_physics_process`:`var dir := Input.get_vector("move_left","move_right","move_up","move_down")`;`velocity = dir * SPEED`;`move_and_slide()`;若 `dir` 非零,把朝向量化成 4 向存 `facing`(取绝对值大的轴),转朝向三角。`tile_pos()`=`Vector2i((global_position/CELL).floor())`;`facing_cell()`=`tile_pos()+facing`。
- [ ] **Step 3**：world 里把 Player 加进树,给个初始位置在网格内。
- [ ] **Step 4** 验收:编辑器运行,WASD 走动、相机跟随、朝向三角随移动转向(手动手感检查);headless 无 ERROR。

---

### Task 5：面前格高亮 + 面前格计算断言

**Files:**
- Create: `examples/farm-sim/target_highlight.gd`(extends Node2D)
- Create: `test/test_facing_cell.gd`
- Modify: `world.tscn`/`world.gd`

- [ ] **Step 1**：`target_highlight.gd`:`bind(player, grid)`;`_process` 里取 `player.facing_cell()`,若在网格内则 `_draw` 一个描边方块高亮该格(`queue_redraw` 当目标变)。
- [ ] **Step 2**：`test/test_facing_cell.gd`:纯算面前格——给定 tile_pos + facing(上下左右)断言 facing_cell 正确(把计算逻辑做成可脱离节点的静态/纯函数以便测,或直接测一个轻量实例)。
- [ ] **Step 3** 验收:test 打印 ALL PASS;编辑器里高亮方块随小人朝向移动到面前格(手动)。

---

### Task 6：工具作用于面前格（耕/种/浇/收 派发）

**Files:**
- Modify: `player.gd`（`farm_use` 输入 → 派发)或 `world.gd`(集中派发)
- Create: `test/test_farm_actions.gd`

- [ ] **Step 1**：在 world(或 player)接 `Input.is_action_just_pressed("farm_use")`(放 `_unhandled_input` 或 `_process`):取 `player.facing_cell()`,按 `grid.tile_state` + 有无作物 派发:
  - EMPTY → `grid.till(cell)`
  - TILLED/WATERED 且无作物 → `grid.plant(cell, _selected_seed)`(P0 固定选一种种子)
  - 有作物且未浇 → `grid.water(cell)`;成熟 → `grid.harvest(cell)`
  - 每次派发后 `view.queue_redraw()`、`CoreKit.log.info` 一行反馈。
- [ ] **Step 2**：`test/test_farm_actions.gd`:脚本化一串"面前格 = 某格"下连续 use 的效果:till→plant(扣种子)→water→(advance 到熟)→harvest,断言每步 grid 状态/背包正确。
- [ ] **Step 3** 验收:test ALL PASS;编辑器手动:走到格前按 use,依次耕→种→浇,格子变色、日志有反馈(手感检查)。

---

### Task 7：逐日推进 + 生长可见

**Files:**
- Modify: `world.gd`
- Create: `test/test_grow_cycle.gd`

- [ ] **Step 1**：world 接 `farm_next_day` 输入 → `CoreKit.clock.advance_day()`;订阅 `CoreKit.clock.EV_DAY_CHANGED` → `grid.advance_day()` + `view.queue_redraw()`。作物 stage 增长在 view 上体现(方块变大变色)。
- [ ] **Step 2**：`test/test_grow_cycle.gd`:plant 一株 → 循环 `clock.advance_day()`(经 bus 触发 grid.advance_day)→ 到 grow_days 断言 mature、可 harvest。(需实例化 grid 并手动接 bus,或直接调 grid.advance_day 验证增长——测逻辑即可。)
- [ ] **Step 3** 验收:test ALL PASS;编辑器手动:种下后按 N 推进几天,看作物方块逐渐长大变金黄,成熟后 use 收获入背包。

---

### Task 8：HUD（日期 / 金币 / 体力占位）

**Files:**
- Create: `examples/farm-sim/hud.gd`(extends Control)
- Modify: `world.gd`(经 CoreKit.layers 挂 HUD)

- [ ] **Step 1**：`hud.gd`:三个 `Label`(日期/金币/体力)。`bind(clock, shop)`;`_process` 或订阅刷新:日期 `y%d %s d%d`(clock)、金币(shop.gold)、体力(P0 固定占位如 `100/100`,不消耗)。
- [ ] **Step 2**：world 经 `CoreKit.layers` 拿/建一个具名 HUD 层(CanvasLayer),把 HUD Control 加进去(fallback:直接 new 一个 CanvasLayer 加 HUD,若 layers API 需要特定用法则查 `docs/systems/layer-manager.md`)。给 world 一个 shop 钱包(复用 shop.gd 或先放个金币变量)。
- [ ] **Step 3** 验收:编辑器运行,左上角显示 日期/金币/体力,按 N 推进天数时日期跟着变(手动);headless 无 ERROR。

---

### Task 9：整合 + smoke test + 主场景

**Files:**
- Modify: `world.gd`(完整接线)、`project.godot`(主场景设为 world.tscn)
- Create: `test/test_world_smoke.gd`

- [ ] **Step 1**：`world.gd` 完整接线:载数据 → 建 bag(起始种子)+ 钱包 → FarmGrid + View + Player + TargetHighlight + HUD,依赖注入齐全,初始给玩家和网格合理位置。
- [ ] **Step 2**：`test/test_world_smoke.gd`(extends SceneTree):`load` world 相关脚本或直接实例化 FarmGrid,脚本化跑一遍完整循环(till→plant→water→advance N 天→harvest),断言无异常 + 终态正确;或用 headless 加载 world.tscn 跑若干帧确认无报错。
- [ ] **Step 3**：`project.godot` 把 `run/main_scene` 设为 `res://examples/farm-sim/world.tscn`(F5 即玩游戏;不影响 run_all——它按显式路径跑 kit demo/测试)。
- [ ] **Step 4** 验收(P0 门):
  - `godot --headless --path . -s res://test/test_world_smoke.gd` → ALL PASS
  - `godot --headless --path . res://examples/farm-sim/world.tscn --quit-after 120` → exit=0、无 ERROR
  - `powershell -File test\run_all.ps1` → `=== SUMMARY FAILS=0 ===`(确认游戏化没连累 kit 门)
  - 编辑器 F5:走小人、耕/种/浇、推进天数、作物长大、收获入背包、HUD 更新——**完整可玩一轮**(手动验收)

---

## P0 完成后

- 更新 spec 里 P0 的 checklist 勾选;提交(游戏代码留分支)。
- 若过程中暴露 kit 缺口(如某门面 API 用着别扭):记下来,按分支分流规矩剥到 main 走 kit SDD,不在此分支改 kit。
- 进入 P1:出 `docs/superpowers/plans/...-p1-*.md`(背包/商店 UI、体力+睡觉、多作物、存读档 UI)。
