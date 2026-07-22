# Fortune Grinder —— 飞镖房「真交互」重构 设计文档 (spec)

> 分支：`example/fortune-mill`（示范游戏，**永不并 main / 永不 push 除非用户指示**）。
> 承接：`docs/superpowers/specs/2026-07-20-fortune-mill-incremental-design.md`（原 incremental 设计）。
> 本文只重构 **Room 1（飞镖房）** 这一个竖切片；其余 4 房不动。

## 背景与目标

现有飞镖房是「点按钮 → 加权 RNG 命中 17 档靶心 → 产 gold」，是纯 incremental，**没有具体的操作玩法**（用户反馈：房间只是按钮点击）。

**目标**：把飞镖房**竖切片彻底重构**为「有真实操作核心」的横版投掷玩法——**命运转盘 (Fortune Grinder)**。玩家只控**方向 + 力度**，把飞镖抛进旋转的转盘，命中不同难度奖区、**扎上即出金币雨**。升级**看得见地改变玩法**；支持**电脑端 + Android 双操作**；自动投做成一个 **AI 磨工**。

**核心认知（不可动摇）**：这仍是 incremental，**核心是金币经济复利循环**（产金 → 买升级 → 复利 → 跨房协同 → 贿赂过关 → 转生 NG+）。真交互是这条循环的**引擎点火与油门**，绝不是独立的手速小游戏。

## 全局约束（每个任务隐含继承）

- **headless-first**：经济逻辑跑纯 `RefCounted` model，不挂节点树；UI 只读模型发命令；`bus` 只广播脏标记、不做数值求值。
- **数据/表现分离**：model 权威、可无头测；view 仅表现 + 输入。
- **不用大数库**：float + `Currency` 值类型，不引入 GDExtension/big-number。
- **在线 = 离线不变量**：自动化与离线结算同用期望值率。
- **跨平台 model 一致**：双端只在**输入适配层**不同，model / 经济 / 存档 / 结算完全相同。
- **不出现裸 float 货币运算**：全走 `Currency`。
- 修正走共享 `KitModifiers`（唯一求值点，与其余 4 房同一实例）。
- 验收沿用「从初始爬到攒够门槛贿赂守卫 **Verminous** 过关」+ `FORTUNE_SMOKE=1` headless 端到端 PASS。

## 玩法愿景

横版侧视：左侧磨工站台、右侧**命运转盘**（持续旋转），中间飞镖走抛物线。方向+力度决定落点，转盘旋转决定命中哪个奖区（时机），扎中即刻迸金币。花金币买的升级在屏幕上**看得见地**改变这台机器（加宽金区、扇形多镖、雇 AI……）。

## 一、命运转盘 model

- 盘面 = 一圈**扇区**，每扇区一个奖区，**宽度 = 难度**：越窄越难命中、倍率越高。默认布局（示例数值，实现时可调，写进 `WheelLayout`）：

  | 扇区 | 角宽(°) | 倍率 |
  |---|---|---|
  | JACKPOT | 18 | ×500 |
  | ×100 | 30 | ×100 |
  | ×20 (×2 段) | 40 各 | ×20 |
  | ×5 | 58 | ×5 |
  | ×2 (×2 段) | 62 / 72 | ×2 |
  | 劫匪 Vermin | 40 | ×0（没收，本切片先做 0，负收益延后） |

  角宽合计 360。
- **径向精度加成 `radial_bonus(r)`**：落点离盘心越近基础倍率越高（连续曲线，例 `1.0 → 2.0`，r 为归一化半径 0=盘心）。这一层让「瞄得准」有意义，独立于扇区。
- **旋转**：model 拥有 `wheel_angle: float`，按固定角速度 `WHEEL_SPEED`（设计常数）在 `update(dt)` 推进（由 autoload ticker 驱动，与 `produce` 同拍）。view 只读 `wheel_angle` 渲染。玩家松手的实时时刻 → 读 model 当前 `wheel_angle` = 时机技巧来源。
- **双轴技巧**：方向+力度（落点/精度）× 松手时机（哪个扇区转到落点）。

## 二、输入抽象与双端操作

玩家最终只产出一对**归一化输入 `(aim, power)`**，`aim∈[0,1]`（纵向/发射角映射）、`power∈[0,1]`：

- `(aim, power) → 确定性抛物线落点`：纯公式，无需真物理引擎——`launch_angle = f(aim)`、`speed = f(power)`、重力常数 `G` → 落在转盘平面的 `(r, a_off)`（离盘心半径 + 相对盘面角偏移）。可无头复算。
- **两个输入适配器**（view 层，平台自适应 + 设置可手动覆盖）：
  - **Desktop（鼠标）**：鼠标位置 → `aim`；按住左键蓄力（力度条摆动，甜点区宽度/晃动受 `aim_steady` 影响）→ `power`；松开 → fire。可选键盘 `↑↓` + 空格。
  - **Android（触屏·拉弓/弹弓）**：drag 向量 → **反方向 = aim 角、长度 = power**；松手 → fire；实时预测弧线辅助。
  - 平台判定：`OS.has_feature("mobile")` / 触屏检测；**dogfood `CoreKit.settings`** 存手动覆盖。
- **跨平台一致**：适配器只产 `(aim, power)`；下游 model / 经济 / 存档 / 结算跨平台完全相同。

## 三、投掷结算（model 权威，纯函数 + model 自有 wheel_angle）

命令：`DartsRoom.throw(aim: float, power: float) -> Dictionary`（手动）。

- **单镖**：`(aim, power) → (r, a_off)`；实际命中盘面角 `hit_angle = wrap(wheel_angle + a_off)`；`seg = WheelLayout.segment_at(hit_angle, win_zone)` → `segment_mult`；`radial_bonus(r)`。
- **扇形多镖（Double Dart Lv N）**：以 `aim` 为中心，`darts_per_throw` 支镖按固定角偏移 `±spread` **扇形展开**，每支各自 `(r_i, a_off_i)` → 各自扎盘结算（都读同一 `wheel_angle`）。多镖 = 在旋转盘面上**铺宽覆盖**。
- 每镖 `payout = gold_per_dart × segment_mult × radial_bonus × global_mul`；Vermin 段 `payout = 0`。总和 `currency.add(total)`。
- 返回 `{gold, darts, hits:[{seg, mult, r}...]}`（供统计/成就/表现层金币雨）。
- **稳手 `aim_steady`**：主要作用在 view 手感（放宽力度甜点区、减小蓄力晃动）；model 端读入以**收窄 (aim,power)→landing 的随机抖动**（可选，默认 0 抖动时该项无副作用）。
- **扎上即出金币雨**：`throw()` 即时结算并返回；view 收到即在各落点迸金币，**不等指针**。

## 四、自动投 / AI（唯一 1 个 AI）

一条升级「**雇 AI 磨工**」（已合并原「AI 稳准」）：

- `L1`（买下）= 雇佣**唯一 1 个** AI，**随机瞄准盘面**投（命中全靠概率）。
- `L2+`（升同一条）= **练稳准**：`ai_skill` 从 0→1，随机波动逐级收窄、分布偏向高奖扇区。
- **不能加人手**（全局仅 1 个 AI）。
- cadence：`throws_per_sec` 底座（AI 投掷间隔）。
- **在线 = 离线**：AI 与离线结算都走**期望值**——
  `auto_gold_rate() = throws_per_sec × darts_per_throw × gold_per_dart × E[segment_mult × radial_bonus | ai_skill] × global_mul`，
  其中 `E[...]` 按 `ai_skill` 加权（`ai_skill=0` 近均匀分布 → 高 skill 偏高奖区、避开 Vermin）。`produce(dt) = auto_gold_rate() × dt`。手动走真 `(aim,power)+wheel_angle`（有起伏），AI/离线走期望（平滑）。
- 手动仍高技巧高回报，AI 是可升级的**被动底薪**，两者并存——解决「自动化淘汰手动」。

## 五、升级线（6 条）

| # | id | title | kind | target | op | effect/级 | base_cost | growth | max | 来源 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `sharper_darts` | Sharper Darts | value | `gold_per_dart` | add | 1.0 | 10 | 1.15 | -1 | ✅ 沿用 |
| 2 | `golden_tips` | Golden Tips | value | `gold_per_dart` | mul | 0.5 | 25 | 1.3 | -1 | ✅ 沿用 |
| 3 | `steady_hand` | Steady Hand（稳手） | aid | `aim_steady` | add | 每级放宽甜点/减晃动 | 40 | 1.25 | 8 | 🔶 重定（原镖值×） |
| 4 | `double_dart` | Double Dart（扇形多镖） | multi | `darts_per_throw` | add | 1.0 | 100 | 2.5 | 9 | 🔶 沿用+扇形语义 |
| 5 | `widen_zone` | Widen Jackpot（扩大中奖区域） | zone | `win_zone` | add | 每级加宽金色高奖扇区 x° | 50 | 1.8 | 16 | 🔴 换机制（原 `bullseye_training` 位） |
| 6 | `hire_ai` | Hire AI Grinder（雇 AI 磨工） | automation | `throws_per_sec` + `ai_skill` | 见下 | L1 起投；升级提 ai_skill | 500 | 1.9 | 25 | 🔶 改+合并（原 `rattling_gunner` + 原稳准） |

- `hire_ai` 一条驱动两个 target：在 `DartsRoom._apply_upgrade` 特判——`throws_per_sec` 设一个基础投掷率（L1 起 >0），`ai_skill = f(level)`（0→接近 1）。
- **modifier target 汇总**：`gold_per_dart`、`darts_per_throw`、`throws_per_sec`、`aim_steady`(新)、`win_zone`(新)、`ai_skill`(新)；共享 `global_mul`、`bribe_cost_mul`（不变）。
- `DartUpgradeDef` schema 扩展 `kind` 取值：`value / aid / multi / zone / automation`。

## 六、数据 / 表现分离 · headless 边界

- **model（纯 `RefCounted`，可无头测）**：`DartsRoom` 持 `wheel_angle`、`WheelLayout`（扇区布局 + `segment_at` + `win_zone` 加宽）、各 modifier；方法 `throw(aim,power)`、`update(dt)`（推进 wheel_angle）、`produce(dt)`（AI 期望值）、`auto_gold_rate()`、`buy_upgrade`、`bribe_threshold/can_bribe/bribe`、`to_dict/from_dict`。
- **view（仅非 smoke 路径实例化）**：输入适配器（Desktop / Touch）、渲染转盘/飞镖弧线/金币雨、**`KitStateMachine`** 投掷态机（`IDLE → AIM/CHARGE → RELEASE → RESOLVE → IDLE`）、fx/sfx。view 读 `model.wheel_angle` 渲染，`throw` 把 `(aim,power)` 交回 model 结算（**view 不决定落哪个奖区**）。
- `bus` 只广播 `fortune:*` 脏标记。

## 七、向后兼容 / 存档迁移

升级 id 有增改（新 `widen_zone`；语义变的 `steady_hand`/`hire_ai`），旧存档带 `bullseye_training`/`rattling_gunner` 等级 + 17 档 tier 状态无法直接映射。

- **采用**：`SCHEMA_VERSION` bump + 一版迁移（走 example 的 `CoreKit.saves` 迁移链 / kit v0.22 migration）——`bullseye_training → widen_zone`、`rattling_gunner → hire_ai`，丢弃 tier 状态；迁移缺步/失败 → **该房重置为默认**（调用方保底），不污染其余 4 房。

## 八、kit dogfood（本切片新增演示的能力）

- 实时输入（鼠标 / 触屏 drag）、**平台自适应输入 + `CoreKit.settings` 手动切换**。
- **`KitStateMachine`**（fortune-mill 首次 dogfood）跑投掷态机。
- `_process` / `update(dt)` 驱动转盘旋转 + 力度摆动 + 飞镖弧线。
- `CoreKit.pool` 复用飞镖节点（可选）。
- fx/sfx 接缝（已有 `gfx/art_bank` / `sfx/sound_bank`）扩投掷 / 落盘 / 金币雨 / jackpot。

## 九、测试点

- **headless**（新 `test/test_fortune_darts_wheel.gd`，seed rng + 显式 set `wheel_angle`）：
  1. 构造 `(aim,power,wheel_angle)` 使落点在 JACKPOT 段 → 得最高 `segment_mult`。
  2. 落 Vermin 段 → `payout = 0`。
  3. 同段、`r` 更小（更靠盘心）→ payout 更高（radial_bonus 单调）。
  4. 扇形多镖 `N`：`throw` 返 N 个 hits、各自结算、总和正确。
  5. `widen_zone` 升级后：同一 `(aim,power,wheel_angle)` 从非金段变金段 → payout 升。
  6. AI 期望：`ai_skill=0`（近均匀）vs 高（偏高奖）→ `auto_gold_rate` 单调升；`produce(dt)` 与在线期望一致（**在线=离线**）。
  7. `to_dict/from_dict` 往返 + 迁移映射。
  8. 全程 `Currency`，无裸 float 货币运算。
- **FORTUNE_SMOKE 扩**（`_build_ui` 前返回，只测 model）：构造若干确定性 `throw` 断言 gold 累积 + 一次 JACKPOT 命中 + AI 期望产出；PASS 行加 `wheel=…/dual-input` 字样。
- **门**：example `run_all`（当前 37 测）+ 新测 → **38**，以 `=== SUMMARY FAILS=0 ===` 收尾（import → 各测 ALL PASS → demo/world smoke stderr 干净）。

## 十、范围边界（YAGNI）

- **IN**：§1–§9 全部——model 重构 + 双端输入适配 + 转盘/飞镖/金币雨表现 + `KitStateMachine` 态机 + 6 升级 + 存档迁移 + 测试 + smoke + docs。
- **OUT**：其余 4 房；AI 加人手；wheel 速度作升级轴；连击 / 排行榜；手柄输入。
- **延后（可选）**：Vermin 段负收益（先做 ×0）；`aim_steady` 对 model 抖动的作用（先只作用 view 手感）。

## 十一、验收

- example `run_all` 以 `=== SUMMARY FAILS=0 ===` 收尾（38 测 + smoke PASS + 非 smoke world 90 帧干净、stderr 无 `ERROR:`）。
- 能从初始爬到攒够门槛贿赂 **Verminous** 过关（门槛沿用 `1_000_000 × bribe_cost_mul`）。
- 电脑端鼠标、Android 触屏两套输入都能玩，且产出同一套 model 结算。
