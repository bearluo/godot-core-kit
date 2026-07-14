# farm-sim 游戏化设计 spec（headless dogfood → 成熟农场经营游戏）

> 日期：2026-07-14 · 分支：`example/farm-sim` · 建在 `godot-core-kit` 之上
> 状态：设计已获需求方口头认可，本文为正式 spec；P0 实现计划见
> `docs/superpowers/plans/2026-07-14-farm-sim-p0-vertical-slice.md`

## 1. 背景与目标

`examples/farm-sim/` 目前是一条 17 段确定性剧情的 **headless dogfood 验证床**（`game.gd` 纯日志、无界面、无交互）。需求方要把它变成一款**真正能玩、有界面的成熟农场经营游戏**，方向三定：

- **完整游戏路线图**（先规划分期，不只做一个切片）
- **程序化占位美术**起步（后期换真像素素材）
- **键盘走动小人**（星露谷式），非鼠标点格子

继续建在 core-kit 上——既做游戏、又持续吃自研框架的狗粮。

## 2. 调研综述（2026-07-14 web 调研）

**品类内核（五大系统相互咬合）**：农场 sim 的"好玩"不在单个系统，而在五个系统**互相咬合**成一个让人"再玩一天"的每日循环——`网格种田 · 日夜/季节钟 · 背包/体力 · 经济(money sink) · NPC 人际`。业界共识：**miss the connections and you have five disconnected toys**。核心循环必须先打磨到"上瘾"再扩内容（ConcernedApe 先把 vertical slice 做爽才铺开）。

**体量现实锚点**：Stardew Valley = **单人 4.5 年、每天 10+ 小时**。这是**尺度锚点、不是目标**。solo/小团队务必：先 vertical slice、狠砍范围、每阶段独立可玩。

**vertical slice 定义**（调研共识）：一块 ~10×10 农田、3 种不同生长期/价格的作物、单季一个日夜循环、基础背包（种子/锄/浇水壶）、一个商店 NPC、体力约束。

**Godot 4 技术范式**：`TileMapLayer`（4.3+ 新节点，旧 `TileMap` 已弃用）做网格；`CharacterBody2D` + `Input.get_vector` + `move_and_slide` 做角色；"面前那一格"= 坐标 + 朝向偏移，工具作用于该格；`Camera2D` 跟随；`Control` + `CanvasLayer` 做 HUD/菜单；作物数据驱动、Y-sort 排深度。

**美术策略**：占位程序美术起步、逻辑与表现严格分离便于后期整包替换；真素材首选 **Sprout Lands**（Cup Nooble，免费可商用、不可转售），备选 Cute Fantasy / itch.io / OpenGameArt 的 CC0 包。

来源：summerengine《make a game like Stardew》、kokutech 设计分析、Stardew Valley / Eric Barone 维基、Medium《MVP vs vertical slice》、Sprout Lands（cupnooble.itch.io）。

## 3. 设计愿景与原则

**愿景**：俯视 2D、键盘走动、程序占位美术的星露谷式农场经营；核心是一个咬合紧密、让人"再玩一天"的每日循环。

**设计原则**（scoping 时必须守住）：

1. **核心循环优先**：先把"耕→种→浇→长→收→卖→再买种"打磨到爽，再谈任何扩展。
2. **系统要咬合，不做孤岛**：每加一个系统都要接回核心循环（如天气→生长、好感→解锁配方）。
3. **每阶段独立可玩**：任一阶段结束都能上手玩、能验收，不留半成品。
4. **狠砍范围**：深水区支柱（采矿/钓鱼/战斗/制作/节日）默认后置、可选，老实标注每个都是数周量级。
5. **逻辑与表现分离**：格子状态/作物数据/经济都不依赖具体贴图；占位美术是一层薄 renderer，换真素材不动逻辑。
6. **复用 core-kit，缺口走分支分流**：能用门面/类库就用；dogfood 中暴露的 kit 缺口剥到 main 走 SDD，游戏代码留分支。
7. **平衡是调参不是编码**：作物价/生长期/工具价/初始体力留成数据（`KitDataRegistry`/常量），好调。

## 4. 关键洞察：非视觉系统 70~80% 已建好 ✅

farm sim 五大核心系统 + 周边，**dogfood 15 档几乎全建过并验证过**。真正缺的是**表现层 + 交互层**：

| 星露谷系统 | core-kit 现成件 | 状态 |
|---|---|---|
| 种田（生长/阶段） | `KitStateMachine`(crop.gd) + `CoreKit.clock` + weather_system | ✅ 已有 |
| 日夜/季节钟 | `CoreKit.clock`（年/季/日/时，带季节） | ✅ 已有 |
| 背包 | `KitInventory`（槽位/堆叠） | ✅ 已有 |
| 经济/商店 | shop.gd（买卖/钱包/`shop:` 事件） | ✅ 已有 |
| 数据表（作物/物品/…） | `KitDataRegistry`（多类型） | ✅ 已有 |
| 存档 | `CoreKit.saves` + to_dict/from_dict | ✅ 已有 |
| 任务/成就 | quest_log / achievement_tracker | ✅ 已有 |
| 多语言/键位/音频/转场/HUD 层/对象池 | `i18n`/`input`/`audio`/`scenes`+`transition`/`layers`/`pool` | ✅ 门面就位 |
| **网格地块（耕/浇/种在格子上）** | — | ❌ **新建** |
| **玩家角色（走动/朝向/工具作用于面前格）** | — | ❌ **新建** |
| **可见 UI（HUD/背包/商店/对话框）** | `Control` + `KitUiStack` + `CoreKit.layers` | ❌ **新建（有地基）** |
| **体力 + 睡觉进下一天** | — | ❌ 新建（很小） |
| **NPC/好感度** | `KitDataRegistry`+`bus`+`saves` 可承载 | ❌ 后期支柱 |

**结论：不是从零做游戏，而是给一套已验证的系统补表现层与交互层。**

## 5. 技术架构（Godot 4）

**场景结构**（P0 起）：

```
World (Node2D)                      # 游戏世界根（新主场景）
├─ FarmLand (TileMapLayer/自建网格)  # 地表 + 格子状态(未耕/已耕/已浇/已种)
│  └─ Crops (Node2D)                # 已种作物实例挂这（复用 crop.gd 的生长逻辑）
├─ Player (CharacterBody2D)         # 键盘走动 + 4 向朝向 + 工具作用于面前格
│  └─ Camera2D                      # 跟随
├─ TargetHighlight (Node2D)         # 面前格高亮
└─ HUD (CanvasLayer, 经 CoreKit.layers) # 日期/金币/体力；弹窗菜单走 KitUiStack
```

**逻辑/表现分离**：核心逻辑放**可 headless 测**的类（格子网格模型、面前格计算、种植/收获经 `KitInventory`），视觉是薄 renderer。`headless` smoke + 逻辑断言测确定性，手感在编辑器手动验。

**关键实现点**：
- **网格**：`FarmTile` 状态 `EMPTY→TILLED→WATERED`，种了则挂一个 crop（沿用 `crop.gd` 的 `KitStateMachine` 生长）。格坐标 ↔ 世界坐标转换封装在网格模型里。
- **角色**：`CharacterBody2D`；输入动作 `move_up/down/left/right`（project.godot 新增）+ `farm_use`（工具）/`farm_interact`；朝向存一个 `facing: Vector2i`；面前格 = `player_tile + facing`。
- **工具**：作用于面前格，按格子状态派发（空地→耕；已耕→种/浇；成熟→收）。P0 单工具多态即可，P2 再拆锄/壶/工具升级。
- **UI**：HUD 走 `CoreKit.layers` 具名层；背包/商店/对话弹窗走 `KitUiStack` 入出栈。

## 6. 分阶段路线图（每阶段独立可玩 + done 判据 checklist）

> P0+P1 = vertical slice。P2 起铺内容。P4 深水区可选。每阶段各自出详细实现计划再开写。

### P0 · 视觉切片（把现有 headless 循环变成看得见能玩的）
- [ ] 能看到农田网格 + 占位地表
- [ ] 键盘走小人（4 向移动 + 朝向），`Camera2D` 跟随
- [ ] 面前格高亮
- [ ] 对面前格 **耕→种→浇** 生效，格子视觉变化
- [ ] 作物按天生长（复用 crop.gd + `CoreKit.clock`），阶段可见；成熟可收入背包（`KitInventory`）
- [ ] "下一天"键推进 `clock.advance_day()`，作物长一格
- [ ] HUD 显示 日期 / 金币 / 体力（体力此阶段可占位不消耗）
- [ ] 全程占位美术；headless smoke 跑通无报错 + 编辑器手动可玩

### P1 · 核心循环成型（vertical slice 收口）
- [ ] 背包界面（`KitUiStack` 入栈，展示物品×数量）
- [ ] 商店界面（买种子/卖收成，接 shop.gd）
- [ ] **体力系统**：动作耗体力，体力耗尽/主动睡觉 → 进下一天
- [ ] 多作物（≥3 种不同生长期/价格）
- [ ] 菜单 存档/读档（`CoreKit.saves`：地块/背包/金币/时钟全量往返）
- [ ] 一个完整"日循环"闭环可反复玩

### P2 · 内容与深度
- [ ] 四季轮替 + 季节限定作物（`CoreKit.clock` 季节）
- [ ] 天气可见效果（weather_system 接渲染，雨天视觉 + 免浇水/生长加成）
- [ ] 工具升级（如浇水 3×3）
- [ ] 任务/成就进 UI（quest_log / achievement_tracker 面板）
- [ ] 语言切换（`CoreKit.i18n`，作物/UI 文案 key 化）
- [ ] 基础音效 + BGM（`CoreKit.audio`）+ 键位重绑定 UI（`CoreKit.input`）

### P3 · 生活模拟支柱
- [ ] NPC（日程/对话框/送礼/好感度；NPC 定义进 `KitDataRegistry`）
- [ ] 好感度解锁（配方/剧情），随存档
- [ ] 多区域世界（农舍/小镇），走到边界切场景（`CoreKit.scenes` + `transition`）

### P4 · 扩展支柱（可选深水区，按口味挑，每个数周量级）
- [ ] 采矿 / 钓鱼 / 采集 / 制作加工 / 节日 —— 立项前单独评估

### P5 · 美术替换 + 打磨
- [ ] 占位美术换真像素素材（Sprout Lands 等），只换 renderer 层
- [ ] 数值平衡（作物价/生长期/工具价/体力曲线）
- [ ] 手感抛光（动画/音效/转场/粒子）

## 7. 美术策略（占位 → 真素材）

- **现在**：地块=彩色 tile（未耕/已耕/已浇/成熟不同色）、作物=按阶段变色/变形的简单图形、角色=方块+朝向指示、UI=Godot 内置控件。渲染集中在薄 renderer 脚本。
- **P5**：换真像素包（首选 Sprout Lands，免费可商用不可转售；备选 Cute Fantasy / CC0 包）。**逻辑不动、只换 renderer + tileset**。素材放 `examples/farm-sim/art/`，license 随包留档。

## 8. 分支与工作流

- 游戏代码全部留 `example/farm-sim` 分支，**不合 main、不升 kit 版本**。
- dogfood 中若暴露 kit 缺口：剥到 main 走 kit 正常 SDD（run_all 绿 → ff-merge，minor 升版）→ 例子 rebase 到新 main。
- 现有 headless `game.gd` 剧情**保留**（改造为可选 demo 模式或独立入口），作为 kit 回归与"系统仍能拼在一起"的证明,不被游戏化破坏。
- 每阶段：出详细 plan → 逐 task 实现 → headless smoke + 手动验收 → 提交。push 留给需求方。

## 9. 开放/待定（不阻塞 P0）

- 世界结构：P0~P2 单屏农场，P3 才多区域（默认，可推翻）。
- 深水区做多少：P3 立住后按兴趣定。
- 落地位置：暂留 `examples/farm-sim/`；成熟后可抽独立目录/仓库。
- 视角细节（正交俯视 vs 2.5D 斜俯视）、格子尺寸、一天时长：P0 定占位值，P5 调优。
