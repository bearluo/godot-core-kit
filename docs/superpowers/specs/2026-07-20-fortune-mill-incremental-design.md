# fortune-mill —— godot-core-kit 的 incremental 放置游戏示例（设计规格）

- 日期：2026-07-20
- 分支：`example/fortune-mill`（从 `main` 切出）
- 目录：`examples/fortune-mill/`
- 参照原作：Steam《财富磨坊 / Fortune Mill》(appid 4731620, Lavaflame2, 2026-06-02)
- 研究底稿：本仓库 deep-research 报告（106 agent / 23 源 / 25 断言对抗验证，12 确证 13 推翻）

---

## 1. 目标与定位

用一款**完整可玩的 incremental（增量/放置）游戏**，dogfood 验证 godot-core-kit，并反哺框架四个缺口子系统。

- **是什么**：房间闯关式放置游戏。玩家被 5 名守卫逐一拦路，每人索要各自房间专属货币 100 万；靠手动点击起步、买升级、解锁自动化攒够门槛过关；跨房间协同放大产出；通关后进 NG+。
- **不是什么**：不追求与原作逐值一致（公开资料不足）。飞镖房照抄已确证数值，其余 4 房 + 协同 + NG+ 规则按 incremental 通用骨架自行设计。
- **完成度**：5 房全做 + NG+ + 51 成就量级 + 程序化美术音效占位 + 中英双语。

### 1.1 复刻边界（来自研究结论，必须写清）

- **可照抄的一手数值**：仅飞镖房 17 档靶心倍率表（见 §5.1）、每房门槛 1M / NG+ 10M per room、5 房 5 货币 5 守卫映射。
- **自行设计（原作机制未获证，0-3 被推翻或从未证到）**：各小游戏产出公式、随机性、成本曲线、跨房协同的具体形态、NG+ 保留/重置项、离线机制。本 spec 中这些部分均标注为**【自定】**。
- 纠正：Lavaflame2 是 IdleOn/Idle Skilling 作者，非 Melvor Idle 作者；原作引擎无法从公开渠道确认——**不据此推断技术栈**。

### 1.2 锁定的关键决策

| 决策 | 结论 | 理由 |
|---|---|---|
| 分支起点 | 从 `main` 切干净分支 | main 上 kit 已 0.18.0，KitDataRegistry/KitInventory/GameClock 齐全；不带 farm-sim example 层 |
| 大数 | **不上大数库**，float + `Currency` 值类型抽象 | 本作量级 ~1e7，float64(1.8e308) 绰绰有余；大数库均为 GDExtension，断 Web 导出 / 绑 Godot 小版本 / 撞 Android 多架构 .so，与纯 GDScript 分发模型和已打通的 Android 出包链路冲突 |
| 架构风格 | 方案 A：headless-first 数据/表现分离 | 后台自动化天然成立、可 headless 自测、换大数只动数据层；与 farm-sim 已验证的 model/view 分离同路 |
| ECS | 不进场 | incremental 是「数值聚合依赖图」非「大量实体遍历」；GDScript 兑现不了 ECS 的内存局部性性能（要性能须 GDExtension，又撞 Web/Android 坑）；roadmap 既定「ECS 不自建暂缓」 |
| kit 反哺方式 | example 内长熟 → 定型后移入 addons | dogfood 纪律：游戏真需要才反哺 |

---

## 2. 架构（方案 A：headless-first 数据/表现分离）

### 2.1 分层原则

- **数据层**（`systems/`，纯 `RefCounted`/`Object`，**不挂节点树**）：所有经济逻辑。进程退出即停，但被 UI DISABLED 不停。
- **表现层**（`scenes/` + `ui/`，`Node`/`Control`）：只**读**模型 + 发命令，永不持有权威数值。
- **单向数据流**：UI 发命令 → 数据层改状态 → `bus` 广播脏标记 → UI 拉取重绘。UI 永不直接写模型字段。

### 2.2 核心运行时对象

```
FortuneMill (autoload, 状态支柱)
├─ Currency × 5          gold / money / tickets / ribbons / stuffing
├─ RoomModel × 5         darts / lotto / pachinko / sushi / gacha
│   ├─ upgrades: {id -> level}
│   ├─ automation: 已解锁的自动化产出率
│   └─ produce(dt) / on_manual_action()
├─ KitModifiers          全局修正器聚合器（跨房协同的唯一求值点）
├─ MetaProgress          ng_plus_level / achievements / stats
└─ tick(dt)              由 CoreKit.ticker 驱动
```

- **产出结算**跑在 `RoomModel.produce(dt)`，与节点树无关。
- **栈顶房间** tick 4Hz；**后台房间**走 `ticker` 预算队列低频摊平（实现「Full Automation across the game」）。
- **UI 数字刷新**降到 10Hz，值变化才 `set_text`（见 §7 风险）。

### 2.3 货币抽象

- `Currency`：值类型（`RefCounted` 或 `class_name`），字段内部 float。提供 `add/sub/can_afford/format(style)`。
- **P0 就封接口**，全代码库不出现裸 float 货币运算。日后换 Decimal 只替换 `Currency` 内部实现。
- 格式化 `style ∈ {plain, kMBT, scientific}`，`settings` 存偏好。

---

## 3. 子系统映射（14 门面 + off-facade → 游戏系统）

| 游戏用途 | 子系统 | 用法要点 |
|---|---|---|
| 经济心跳 + UI 节流 | `ticker` | 房间 produce 1~4Hz；UI 刷新 10Hz；后台房间预算队列 |
| 秒级自动存 + 原子写 | `saves` | 放置游戏必须秒级自动存；SaveSerializer 扩展点日后序列化 Decimal |
| 升级/房间/生物/成就定义 | `KitDataRegistry` | 全做 `.tres`，`load_dir` 扫 `data/`；`ids(sorted)` 稳定商店排序 |
| 房间导航 | `KitUiStack` | 房间屏 = `KitUiScreen`；被盖屏 DISABLED（**仅停表现层，数据层照跑**） |
| 事件 | `bus` | `room:cleared` / `upgrade:purchased` / `currency:changed` / `jackpot:hit`。**只广播脏标记，绝不做数值求值** |
| 柏青哥落球 + 命中 SFX | `pool` + `audio` | 落球 `RigidBody2D` 走 pool；高频命中 SFX 走 audio SFX 池 |
| 数值作弊验证 | `console` | 注册 `give <cur> <n>` / `goto_room <n>` / `set_ngplus <n>`（否则每次验证 NG+ 要玩十几小时） |
| 记号法/自动购买偏好 | `settings` | 数字记号法、自动购买开关、离线弹窗开关 |
| HUD/弹窗/toast 分层 | `layers` | HUD / 商店弹窗 / 成就 toast / 离线弹窗分层 |
| 小游戏局部状态 | `KitStateMachine` | 飞镖 idle→aiming→throwing→settling；柏青哥 loading→dropping→scoring |
| 房间级服务隔离 | `KitContext` | 每房是独立经济体，room-scoped 注入避免全局单例互污（可选，视复杂度） |
| 扭蛋道具/寿司食材容器 | `KitInventory` | 槽位/堆叠/合并现成 |
| 中英双语 | `i18n` | 运行时切语言 + 字体回退 + 缺翻译告警 |

**优先级低/不用**：`input`（桌面为主，重绑定需求弱）、`res`（资源少）、`scenes`/`KitTransition`（房间做 UI 屏则用不上）、`clock`（**不做经济结算**——它是可暂停可加速的游戏内日历，进程退出不推进、无防作弊语义；离线结算另用 KitOffline）。

---

## 4. kit 反哺清单（example 内长熟 → 定型后移入 addons/）

| 反哺项 | 目录去向 | 规模 | 反哺窗口 | 为什么 kit/Godot 不够 |
|---|---|---|---|---|
| **KitModifiers** 数值修正器栈 | `addons/.../systems/` 或新 `modifiers/` | 300~500 行 | P0 雏形 → **P2 定型** | incremental 的心脏：加法/乘法/指数分层 + 每条带 `source_id` + 脏标驱动重算 + 可查询「产出由哪些来源构成」。kit 无等价物；否则退化成散落各处的 `total *= x`，顺序不可控、无法回滚、无法展示明细 |
| **KitOffline** 离线结算 | `addons/.../systems/` | 200~300 行 | **P1** | 墙钟差(`Time.get_unix_time_from_system`) + 封顶 + 时间回拨/前拨作弊检测 + 跨升级边界分段积分 + 回归弹窗数据包。clock 和 Godot 内置都不覆盖 |
| **KitStats + KitAchievements** | `addons/.../systems/` | ~300 行 | **P4** | 51 成就 + 统计计数器 + 触发去重 + toast + 日后 Steam 抽象层。kit 无 |
| **SaveManager migration** 版本迁移链 | `save_manager.gd` 增量 | ~150 行 | **P4** | 现有仅 SaveSerializer + 原子写，无 v1→v2→v3 顺序迁移；长期运营放置游戏一次数值改版就报废老存档 |
| 节流数值 Label + 滚动动画 | `addons/.../ui/` | 小 | 视情况 | GDScript 字符串格式化开销显著，百来个 Label 每帧 set_text 吃满帧预算。kit 无 UI 数值组件 |
| 数字格式化（k/M/B/T 或 AA） | 小工具 | 百行内 | 小工具 | 从 ChronoDK 纯 GDScript 版摘出或自研；**不引入大数库** |
| 解锁条件求值 | 复用 `console/console_evaluator.gd` | 半自研 | 视情况 | **不从零造 DSL**：Godot 内置 `Expression` 够用，console 已在用同一机制，抽出包一层缓存 + 事件驱动重评 |

---

## 5. 玩法内容设计

### 5.0 通用循环（每房一致）

`手动点击产出 → 买升级 → 解锁自动化 → 攒够 100 万专属货币 → 贿赂守卫过关 → 解锁下一房`

- 5 货币互相独立，不可兑换（原作坐实五货币并行）。
- 守卫难度递减漏斗（研究实证解锁率 95%→53%）：后期房间门槛感更强，用成本曲线陡度体现。

### 5.1 Room 1 · 飞镖（gold / 守卫 Verminous）——照抄

- **手动**：投镖，命中靶心按稀有度倍率产 gold；镖基础值 × 靶心倍率 = 单次产出。
- **靶心 17 档倍率表（一手确证，直接抄）**：

  | 档 | 名 | 倍率 | | 档 | 名 | 倍率 |
  |---|---|---|---|---|---|---|
  | 1 | red | 1.5x | | 10 | Violet | 80x |
  | 2 | purple | 2x | | 11 | Luscious | 125x |
  | 3 | blue | 3x | | 12 | Gilded | 200x |
  | 4 | yellow | 5x | | 13 | Void | 300x |
  | 5 | green | 8x | | 14 | Emerald | 500x |
  | 6 | orange royal | 12x | | 15 | Onyx | 800x |
  | 7 | pinnacle | 20x | | 16 | Sapphire | 1200x |
  | 8 | Cloud Nine | 30x | | 17 | Supernova | 2500x（封顶）|
  | 9 | Starfire | 50x | | | | |

- **升级**：镖值 +%（乘数）、靶心档位逐级解锁（解锁，每档对应一成就）、`Rattling Gunner` 自动投（自动化）、双镖/多镖（速度）。
- **爬升结构**：靶心档位 × 百分比乘数 × 自动化/多镖，三层相乘，飞镖房约 5~6 个数量级（$1 gold → 每投 $250k → 攒 1M 贿赂 Verminous）。

### 5.2 Room 2 · 刮刮乐 Lotto（money / 守卫 Gorgon）——【自定】

- **手动**：买刮刮卡 → 刮开 → 按中奖表得 money。
- **随机性**：加权中奖表（多数小奖 + 稀有 JACKPOT）。**JACKPOT 命中 → 全房间永久乘法层加成（累积不重置，除 NG+）**——这是第一个跨房协同产出点，P2 用它逼定 KitModifiers 形状。
- **升级**：卡面价值（乘数）、刮卡速度（速度）、自动刮卡（自动化）、JACKPOT 概率/权重（解锁式）。

### 5.3 Room 3 · 柏青哥 Pachinko（tickets / 守卫 Rimmington）——【自定】

- **手动**：落球，`RigidBody2D` 碰钉子随机落进底部槽位，槽值 × 落球数 = tickets。**全作唯一需要真物理**；落球实例走 `pool`；碰撞 SFX 走 audio SFX 池。
- **骰子 bonus**：攒够 tickets/触发条件掷骰 → **全房间限时乘数 buff**（DICE，临时乘法层，持续 N 秒或 N 次产出）。骰子挂在本房内，**不是独立房间**（研究确证）。
- **升级**：球价值（乘数）、同时球数（速度/并行）、自动落球（自动化）、骰子频率（解锁式）。
- **性能注意**：自动化模式下大量球同时在场——限制在场球数上限 + pool 复用 + 到底即回收。

### 5.4 Room 4 · 寿司 Sushi（ribbons / 守卫 Hivemind）——【自定】

- **手动**：选配方 → 等制作时长 → 出寿司得 ribbons。配方/食材容器用 `KitInventory`。
- **协同**：特定高级寿司 → **解锁式 modifier（改变玩法开关）**，如「飞镖自动投速翻倍」「刮刮乐必出小奖」。SUSHI 是三类协同里唯一的「规则开关」型。
- **升级**：配方解锁（解锁）、制作速度（速度）、自动厨师（自动化）、ribbon 价值（乘数）。

### 5.5 Room 5 · 扭蛋 Gacha（stuffing / 守卫 Executor）——【自定】

- **手动**：投币抽扭蛋 → 按稀有度得道具 + stuffing。道具进 `KitInventory`。
- **协同**：**道具给各房间被动加/乘法层**（收集向）。稀有度权重可升级。
- **升级**：抽卡速度（速度）、稀有度权重（解锁式）、自动抽卡（自动化）、stuffing 价值（乘数）。
- **注意**：研究提到社区反馈「高 NG+ 轮次 Gacha 仓储成本增长快过收益」——平衡时留意抽卡成本曲线不要压过道具收益。

### 5.6 跨房间协同（KitModifiers 的形状，【自定】）

三层聚合，全局唯一求值点：

```
产出_房间i = base_i(加法层求和) × ∏(乘法层) [ × 指数层(预留) ]
```

- 每条升级、每个协同来源 = 一条 `Modifier{ target, op ∈ {add, mul, exp}, value, source_id }`，声明式注册到目标房间的栈。
- **JACKPOT**（刮刮乐）→ 永久 `mul`，跨轮累积。
- **DICE**（柏青哥）→ 临时 `mul`，限时/限次自动移除。
- **SUSHI**（寿司）→ 解锁式开关（改规则，不一定是数值）。
- **GACHA 道具**（扭蛋）→ 被动 `add`/`mul`。
- `bus` 广播 `modifier:dirty(target)`，聚合器按需重算并缓存；UI 读缓存。**协同不走 bus 累加**（避免顺序依赖/重复累加）。

### 5.7 自动化 + 离线（【自定】）

- 买到自动化升级后，`RoomModel.produce(dt)` 在数据层持续跑（`ticker` 驱动），与 UI 是否可见无关。
- **KitOffline**：登录时 `Time.get_unix_time_from_system()` 差值 × 各房自动化产出率，**封顶 8 小时**；系统时间回拨/前拨检测（回拨则不结算或按 0 计）；回归弹窗展示各房离线收益数据包。

### 5.8 NG+ 元进度（保留/重置规则，【自定】——公开资料只确证「门槛 ×10 + 升级更贵 + 有 NG+ 专属升级」）

- **重置**：5 房货币归零、房间升级等级归零、守卫重新拦路、门槛 1M → 10M（NG++ 继续 ×10 或叠加缩放）。
- **保留**：成就、统计、NG+ 专属升级、记号法偏好、部分稀有扭蛋道具。
- **NG+ 专属升级线**：只在 NG+ 可买，提供跨轮永久加成（prestige 味）。
- **Lethal Mode**（可选速通模式）：P4 做计时 + 无 NG+ 加成的限制模式。

### 5.9 成就 + 统计（【自定】，51 条量级）

- 覆盖：17 档靶心首次命中、5 守卫贿赂、NG+/NG++ 完成、累计产出/单次最大产出里程碑、各自动化解锁等。
- `KitStats` 计数器持久化（累计投镖数、最高单次收益、各档靶心首命中）+ `KitAchievements` 触发去重 + toast。预留 Steam achievements 抽象层。

### 5.10 美术 / 音频（占位先行，真素材零改代码替换）

- `art_bank` 程序化像素贴图（照 farm-sim P5 已验证的 drop-in 模式重写，适配原作 Pixel Graphics 标签风格）。
- `audio_bank` 程序化音效（飞镖命中、刮卡、落球碰撞、抽卡等）。
- `assets/` 空目录；真 PNG/wav 丢入即覆盖程序化贴图，**不改代码**。
- 工作量预警（研究粗估）：120+ 升级图标（~40h）、15 生物立绘、5~6 房间背景、60+ SFX——占位跑通全流程后置替换。

---

## 6. 数据流与错误处理

- **命令流**：UI 点击 → `FortuneMill` 命令方法（buy_upgrade / do_manual_action / bribe_guard）→ 校验（can_afford / 门槛）→ 改模型 → `bus` 脏标记 → UI 重绘。
- **产出流**：`ticker` → `FortuneMill.tick(dt)` → 各 `RoomModel.produce(dt)` → 累加货币 → 脏标记。
- **存档**：`saves` 秒级自动存 + 退出存；只存**权威状态**（货币、升级等级、NG+ 层、成就、统计、时间戳），**不存派生值**（modifier 结果重算不持久化）。
- **错误处理**：
  - 买不起/未满门槛：命令返回 false，UI 提示，不改状态。
  - 存档损坏/版本不符：migration 链尝试迁移；失败则告警 + 保底新档（不静默覆盖）。
  - 离线时间回拨：检测到则按 0 结算，日志告警。
  - 缺翻译：i18n 缺翻译告警（已有）。

---

## 7. 风险与对策

| 风险 | 对策 |
|---|---|
| **UI 节点规模**（120+ 升级卡片，Control 破千，布局重算瓶颈）| 虚拟列表（只实例可视项）+ `pool` 复用卡片 + `ticker` 预算队列分帧刷新 |
| **每帧数值刷新**（GDScript 字符串格式化开销）| 禁止 `_process` 无条件 set_text；10Hz 节流 + 值变化才写 + 缓存格式化结果 |
| **float 精度** | 本作量级非问题；真风险是不做货币抽象 → 用 `Currency` 值类型封住 |
| **存档膨胀** | 几十~几百 KB 可接受；不存派生值 |
| **后台房间停摆**（KitUiStack DISABLED vs Full Automation）| 产出逻辑脱离节点树跑数据层；DISABLED 只停表现层 |
| **移动端**（柏青哥物理 + 大量 Label 在低端安卓吃紧）| 限在场球数；Label 节流；已打通 Android 出包链路，**不引入 GDExtension 大数库**（撞多架构 .so 坑 #73334/#82727）|
| **Web 导出** | 纯 GDScript 全程可导 Web；**不引入 GDExtension** 是决定性理由 |
| **美术/音频工作量被低估** | art_bank 程序化占位先行，真素材后置替换 |

---

## 8. 测试策略

- **kit 反哺子系统单测**（`test/` 下，进 kit 门 `run_all.ps1`）：`test_kit_modifiers.gd`（加/乘/指数分层 + source_id 移除 + 脏标重算）、`test_kit_offline.gd`（墙钟差 + 封顶 + 回拨检测 + 分段积分）、`test_kit_stats.gd` / achievements。
- **example 端到端 smoke**（独立于 kit 门，照 farm-sim `FARM_SMOKE` 约定）：`FORTUNE_SMOKE=1 godot --headless` → 无窗口跑通「飞镖 $1 → 攒 1M → 贿赂 Verminous → 进第 2 房」→ 打印 `[Fortune][SMOKE] PASS`。
- **数值验证**：`console` 作弊命令跳关验证 NG+ 10M/房与后期数值，不必真玩十几小时。
- example 测试与 kit 门测试分开（farm-sim 已确立此约定）。

---

## 9. 阶段路线（工作量为量级参考，无外部来源支撑）

| 阶段 | 内容 | 量级 | 反哺窗口 | 验收 |
|---|---|---|---|---|
| **P0** | 飞镖竖切片：`Currency` + `KitModifiers` 雏形 + 手动投 + 17 档靶心（抄）+ 5~10 升级走 KitDataRegistry + saves + 格式化 | 1~2 周 | — | **$1 gold → 100 万 → 贿赂 Verminous**；FORTUNE_SMOKE PASS |
| **P1** | 自动化（ticker 降频）+ 离线（KitOffline + 回归弹窗）| 0.5~1 周 | **KitOffline** | 关游戏 1 小时回来有离线收益 |
| **P2** | 刮刮乐 + 跨房协同（**架构关键点**：JACKPOT 逼定 modifier 形状，错了后 3 房返工）| 1~2 周 | **KitModifiers 定型反哺** | 刮刮乐 JACKPOT 给飞镖房加成生效 |
| **P3** | 柏青哥（RigidBody2D + pool + 骰子）+ 寿司（配方 + 解锁式协同）| 2~3 周 | — | 4 房可通关 |
| **P4** | 扭蛋 + NG+/NG++ + 51 成就（KitStats）+ SaveManager migration + i18n 中英 + Lethal Mode 计时 | 1~2 周 | **KitStats + migration** | NG+ 完整循环 + 成就触发 |
| **P5** | 数值平衡（成本/产出曲线）+ 手感 + 音效层次 + 真素材 drop-in 通道验证 | — | — | 5 房节奏顺畅 |

**P0 选飞镖打头**：唯一有完整一手数值、不用猜、无物理依赖，验收标准可量化。
**P2 是全项目最关键一步**：刮刮乐本身比飞镖简单，价值在于第一次逼出跨房间 modifier 的正确形状。

---

## 10. 未决问题（不阻塞 P0，实现中定）

- 各房成本曲线的 base/growth 具体取值——P5 平衡阶段调，P0 先让飞镖房能爬到 1M 即可。
- 协同的指数层是否真需要（预留但 P2 前不实现）。
- `KitContext` 房间级隔离是否值得——若全局单例够清晰可省，视 P2 复杂度定。
- NG+ 保留稀有道具的具体范围——P4 定。
- Lethal Mode 的具体奖励规则——P4 定。
