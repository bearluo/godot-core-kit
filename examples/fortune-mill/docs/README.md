# fortune-mill 功能文档

P0 阶段只有飞镖房。目录:

- `defs/` —— 升级定义 Resource schema
- `systems/` —— 纯数据层(Currency/KitModifiers/DartsRoom/FortuneMill autoload)
- `scenes/` —— world 场景 + 表现层
- `gfx/` —— 表现层美术/手感(art_bank 程序化接缝 + fx 手感层,P5)
- `sfx/` —— 程序化音效(sound_bank 音效接缝,P5)
- `assets/` —— 真素材/音频投放口(drop-in;默认空,见 `assets/README.md`)
- `data/dart_upgrades/` —— 升级 .tres
- `test/test_fortune_*.gd` —— headless 断言(进 kit 门 run_all)

架构纪律:经济逻辑跑纯 RefCounted 数据层不挂节点树;UI 只读模型发命令;
bus 只广播 `fortune:*` 脏标记;货币全走 Currency;存档只存 Dictionary。

> **P0 存档语义**:仅在贿赂过关时落盘(`bribe_guard`→`save_game`);中途投镖/买升级不自动存、退出也不存。
> 自动存与离线结算(`KitOffline`)按 spec §5.7/§9 排到 P1。

## P1 自动化 + 离线

- **自动投**:买 `Rattling Gunner`(kind=automation → `throws_per_sec` 修正器)后,`ticker` 驱动
  `FortuneMill.tick(dt)` → `DartsRoom.produce(dt)` 按**确定性期望产率** `auto_gold_rate()` 持续产 gold
  (在线与离线同率,保证「离线 1h ≈ 在线 1h」;手动投仍走 RNG,自动投走期望值)。
- **离线结算**:`KitOffline.settle(last_seen, now, rate, cap=8h)`,墙钟差 × 产率,封顶 8 小时,
  时间回拨(`now<last`)按 0(防作弊)。`load_game` 时结算,回归横幅从 `FortuneMill.offline_report` 拉取。
- **自动存**:`ticker` 每 ~5s 周期自动存 + 窗口关闭(`WM_CLOSE_REQUEST`)退出存;存档新增 `last_seen` 时间戳。
- `KitOffline` 照 KitModifiers 先例在 `systems/` 内孵化,定型后随 kit cycle 移入 `addons/`。

## P2 刮刮乐 + 跨房协同

第 2 房 **刮刮乐 Lotto**(独立货币 money / 守卫 Gorgon):`do_scratch` → 加权中奖表
(`LottoRoom.PRIZE_MULT/WEIGHT`,多数小奖 + 稀有 JACKPOT)→ money;升级(卡值/多卡/自动刮/幸运符权重)
经共享 `KitModifiers` 聚合;攒够 1M money 贿赂 Gorgon 过关。5 货币互相独立不可兑换。

- **跨房协同(架构核心)**:JACKPOT 命中 → 往 **`global_mul`** target 叠一条永久乘法层
  (源 `lotto_jackpot`,值 `JACKPOT_MUL^count`)。每个房间产出都 `× value_for(&"global_mul", 1.0)`
  (飞镖 `throw`/`auto_gold_rate`、刮刮乐 `scratch`/`auto_money_rate`),故经**唯一求值点**
  一次 jackpot 放大**全房间**——飞镖房自动被放大,无需 JACKPOT 枚举各房 target。
  `_jackpot_count` 是权威态(存档),`from_dict` 重放这条 mul。新增房间只需在自己产出公式里读
  `global_mul` 即自动纳入协同,不改 JACKPOT。
- **KitModifiers 定型**:加 `breakdown(target, base)`(产出由哪些来源构成)/`sources(target)`;
  指数层 `exp` 保留不实现(YAGNI,spec §11 待定,未知 op 登记不求值)。形状经 P2 验证后
  走独立 kit cycle 反哺 `addons/godot-core-kit/modifiers/`。
- **自动化确定性**:`auto_money_rate()` 用中奖表期望值(含 jackpot 档 money 赔付期望),
  但**不**触发离散 jackpot(不叠 global_mul),同飞镖先例保「在线=离线」。
- **离线双房**:`settle_offline` 各房各用自身产率单独结算,`offline_report` 改 per-room
  `{darts:{...}, lotto:{...}}`。
- 验收:`FORTUNE_SMOKE` 端到端 `PASS ... jackpots=1 darts_boost=1.50x gorgon=true`
  (jackpot 后飞镖率精确 ×1.5)。测试 `test_fortune_lotto`(含跨房加成证明 + jackpot 持久化)进 kit 门。

## P3 柏青哥 + 寿司(4 房可通关)

### 柏青哥 Pachinko(tickets / 守卫 Rimmington)

落球 → 加权落槽(`PachinkoRoom.SLOT_VALUES/SLOT_WEIGHTS`,plinko 式中间小值常见、边缘大值稀有)→ tickets;
升级(球值/多球/自动落球/骰子频率)经共享 `KitModifiers`;攒够 1M tickets 贿赂 Rimmington。

- **真物理 vs 数据分离**:经济权威在 `PachinkoRoom`(纯数据,`drop_ball()` 加权 RNG + `auto_ticket_rate()` 期望率,headless 可测)。
  真 RigidBody2D 落球是**表现层 juice**(`scenes/pachinko_board.gd`,仅非 smoke 实例化):球从 `CoreKit.pool` 取、
  碰钉子、落进底部 `Area2D` 槽 → 回调 `FortuneMill.pachinko_land(slot)` → `PachinkoRoom.award_slot`(权威入账);
  落槽 SFX 走 `CoreKit.audio`(程序化 tick);在场球数封顶 + 到底即回收;`_exit_tree` 清池免 RID 泄漏。
  手动落球走真物理;自动 / 离线 / headless smoke 走 model RNG。
- **DICE 临时全局乘数(跨房协同 · 临时型)**:落球累积 `_dice_meter`,攒够 `roll_dice` → 往 **`global_mul`**
  叠一条**临时** mul(源 `pachinko_dice`,`DICE_MUL`),`update(dt)`(`FortuneMill.tick` 每帧调)倒计时到 0
  自动 `remove_source`。与 JACKPOT 永久 mul **同 target 不同 source_id**,Πmul 乘性叠加,一起放大全房间。
  DICE 是 live buff,**不持久化**(存档不存,读档不恢复)。
- **离线三房**:`settle_offline` 各房各用自身产率单独结算,`offline_report={darts,lotto,pachinko}`。
- 验收:`FORTUNE_SMOKE PASS ... dice=true dice_boost=3.00x rimmington=true`(DICE 期间飞镖率精确 ×3=DICE_MUL)。
  测试 `test_fortune_pachinko`(含 DICE 施加/过期 + 与 jackpot 乘性叠加 + 跨房)进 kit 门。

### 寿司 Sushi(ribbons / 守卫 Hivemind)

选配方 → 等制作时长 → 出寿司得 ribbons;升级(ribbon 价值/制作速度/自动厨师)经共享 `KitModifiers`;
攒够 1M ribbons 贿赂 Hivemind。三处机制:

- **制作时长 + `KitInventory` 食材(dogfood)**:食材柜是真 `KitInventory`(`SushiRoom._pantry`)。
  `select_recipe` → `start_craft`(`_pantry.has/remove` 扣食材,够才开工)→ `update(dt)` 按 `craft_speed`
  聚合推进计时 → 到 `craft_time` 完成 `_award_sushi` 入账。手动制作是 live 态,**不持久化**(食材柜持久,
  进行中的 craft 读档从空灶起,同 DICE 精神)。
- **自动厨师(自动化/离线)**:`auto_ribbon_rate()` 用连续期望率(`chefs × 单份价值 / 有效制作时长 × global_mul`),
  **不**模拟离散制作/食材消耗,保「在线=离线」(同其余房 auto 先例)。`auto_chef` 基 0,买 Auto Chef 才 >0。
- **解锁式开关协同(SUSHI 型 · 三类协同唯一「规则开关」)**:高级配方(`SushiRecipeDef.switch_target`
  非空,如 `dragon_roll`)解锁 → 往**别房** target 注册一条**永久** modifier(源 `sushi_<id>`),
  如 `throws_per_sec ×2`「飞镖自动投速翻倍」。经共享 `KitModifiers` 唯一求值点即时生效于别房;
  `_unlocked` 是权威态(存档),`from_dict` 重放开关。与 JACKPOT/DICE 不同:SUSHI 改的是**规则**
  (给一个 add-型 target 挂 mul 开关),落在各房自己的产率 target 上、不走 `global_mul`。

三类协同对照:**JACKPOT** 永久 `mul` on `global_mul`(放大全房);**DICE** 临时 `mul` on `global_mul`
(限时放大全房);**SUSHI** 永久 `mul` on 别房专属 target(规则开关,如投速)。四房共享一个 `KitModifiers`
求值点,互不枚举。

- **离线四房**:`settle_offline` 各房各用自身产率单独结算,`offline_report={darts,lotto,pachinko,sushi}`。
- 验收:`FORTUNE_SMOKE PASS ... craft=true switch_boost=2.00x hivemind=true`(解锁 dragon 后飞镖率精确 ×2)。
  测试 `test_fortune_sushi`(含 craft 消耗食材+计时完成 / 升级 / auto 率 / 解锁开关跨房 ×2 / 持久化)进 kit 门。达成 P3「4 房可通关」。

## P4 扭蛋 + NG+ + 成就 + migration + i18n(分阶段)

P4 是大阶段,照 P3 分阶段:**4A 扭蛋(本节)→ 4B NG+/NG++ + Lethal Mode → 4C 51 成就 + KitStats → 4D SaveManager migration + i18n 中英**。

### 4A 扭蛋 Gacha(stuffing / 守卫 Executor)——补齐第 4/最后一类协同

投币抽扭蛋 → 按稀有度加权得道具(进 `KitInventory` 收藏柜)+ stuffing;升级(单抽价值/自动抽速/
自动抽卡机/稀有度权重)经共享 `KitModifiers`;攒够 1M stuffing 贿赂 Executor。三处机制:

- **手动抽卡 + `KitInventory` 收藏柜(dogfood 第 2 处)**:`pull()` 加权 RNG 抽一个道具 →
  `grant_item` 收进收藏柜(`GachaRoom._vault`)+ 挂被动协同 + 产 stuffing。`grant_item(id,n)` 是
  pull 与测试共用的确定性入口(道具是收集向,收集 = 加被动 modifier)。
- **自动抽卡(自动化/离线)**:`auto_stuffing_rate()` 用连续期望率(pullers × PULL_BASE_RATE ×
  pull_speed × 期望单抽 × global_mul),**不**收集离散道具(保「在线=离线」,同其余房 auto 先例)。
  `auto_puller` 基 0,买 Auto Gacha 才 >0。
- **被动收集协同(GACHA 型,第 4/最后一类协同——唯一「收集向」)**:持有道具 → 往各房 target 挂一条
  **永久** modifier(源 `gacha_<id>`),持有 n 份:`add=value×n` / `mul=(1+value)^n`,越集越强。经共享
  `KitModifiers` 唯一求值点即时生效于别房(可指向别房产率如 `gold_per_dart`,或 `global_mul` 放大全房)。
  收藏柜 `_vault` 是权威态(存档),`from_dict` 按持有数重放被动层。

四类协同至此齐活:**JACKPOT** 永久 `mul` on `global_mul`(放大全房);**DICE** 临时 `mul` on
`global_mul`(限时放大全房);**SUSHI** 永久 `mul` on 别房专属 target(规则开关);**GACHA** 永久
`add`/`mul` on 各房 target(收集向,越集越强)。五房共享一个 `KitModifiers` 求值点,互不枚举。

- **离线五房**:`settle_offline` 各房各用自身产率单独结算,`offline_report={darts,lotto,pachinko,sushi,gacha}`。
- 验收:`FORTUNE_SMOKE PASS ... gacha_boost=1.61x executor=true stuffing=1.07M`(收集 5 个 dream_daruma
  后飞镖率精确 ×(1.1)^5=1.61)。测试 `test_fortune_gacha`(含 pull 收集+产出 / add·mul 被动层堆叠 /
  价值升级 / 自动率 / 稀有度权重抬期望 / 收集跨房放大飞镖 ×4 / 持久化收藏柜+被动层)进 kit 门。达成 P4「5 房可通关」。

### 4B NG+ 元进度 + Lethal Mode(`systems/prestige.gd`)

通关 5 房 → `ascend` 进下一周目。**门槛缩放走共享 `KitModifiers` 的新 target `bribe_cost_mul`**——各房
`bribe_threshold() = 1M × value_for(bribe_cost_mul, 1.0)`,prestige 在其上挂唯一门槛源 `ng_threshold`(mul)
= `10^ng_level`;ng0 → ×1.0(完全向后兼容,各房 `can_bribe` 现读它)。契合「5 房共享一个求值点」的架构,
门槛是派生值不入存档。三处机制:

- **ascend(进周目)**:确认 5 房通关 → `Prestige.ascend`(发 `ng_level+1` 点 + 门槛 ×10)→ `_reset_rooms`
  重置 5 房(货币归零/升级清空/守卫重新拦路,含 `lotto.from_dict({})` 清掉 JACKPOT 永久 global_mul——
  spec「累积不重置,除 NG+」)。**保留**:成就/统计(4C 做)、prestige 升级、**部分稀有扭蛋道具**(epic 稀有度,
  重置后按持有数重新收集,被动层随之重建)。
- **NG+ 专属升级线(prestige 味)**:`data/prestige_upgrades/*.tres`(Eternal Fortune=global_mul、Golden
  Hands=gold_per_dart、Swift Start=throws_per_sec),**只在 ng≥1 可买**,花 prestige 点,往 def.target 挂
  **跨周目存活**的源 `prestige_<id>`——`_reset_rooms` 只清各房自身源、不动 prestige 源,故加成穿越重置。
- **Lethal Mode(可选速通)**:`start_lethal` → **无 NG+ 加成**(撤 prestige 源 + 门槛回 1M)+ 计时;5 房全
  通关时 `_check_lethal_finish`→`finish_lethal` 记最佳秒数(取 min)、退出即恢复加成与门槛;期间禁买 prestige。

**顺带修一个 `GachaRoom.from_dict` 潜在 bug**:空档(`from_dict({})`)未清收藏柜 `_vault`,导致 NG+/Lethal 重置时
「快照 epic → 重置 → 重新 grant」在旧库存上**叠加**(dream_daruma 6→12→…global_mul 暴涨)。改为 from_dict 先重建
空柜再按存档载入(空档 = 完全重置)。

验收:`FORTUNE_SMOKE PASS ... ng=1 thr=10.00M prestige_gmul=1.50x lethal_best=8.0s`(ascend 门槛 ×10、prestige
永久 global_mul ×1.5、Lethal 撤加成+门槛回 1M+计时+跑完记时)。测试 `test_fortune_prestige`(门槛缩放 / ascend
×10+发点 / NG+ 专属升级 add·mul 加成 / 加成跨房间重置存活 / Lethal 撤加成+门槛回 1M+最佳取 min+期间禁买 /
持久化 ng_level·points·levels·best + modifier 重放)进 kit 门。

### 4C 51 成就 + KitStats(`systems/kit_stats.gd` + `systems/kit_achievements.gd`)

51 条成就 + 统计计数器,两个 off-facade 类库孵化于本 example(拟反哺 kit,同 KitOffline/KitModifiers 先例)。
**数据驱动阈值判定**:每条成就 = `{stat_key, threshold}`,当 `KitStats.get_value(stat_key) >= threshold` 即解锁——
无需每条写触发代码。三层:

- **`KitStats`(计数器持久化)**:`add`(累加:累计投镖数、抽卡/落球/刮卡次数)、`record_max`(峰值:最高单次收益、
  最高周目 ng_level)、`set_value`(权威快照:jackpot 累计次数)。读走 `get_value`(阈值判定唯一入口)。纯数据,存档。
- **`KitAchievements`(成就引擎)**:持有 def 表 + 已解锁集合;`evaluate(stats)` 扫全部 def,解锁「已达阈值且未解锁」者,
  **返回本次新解锁 id 列表**(供 UI 弹 toast),已解锁的**绝不重触**(去重的核心)。**Steam 抽象层**:`set_steam_sink`
  注入平台回调(如 `Steam.setAchievement`),新解锁时触发一次;默认空(kit 无引擎绑定)。存档只存已解锁 id 集合。
- **51 条目录(`systems/achievement_catalog.gd`)**:代码构建 `AchievementDef` → 注册进 `KitDataRegistry` 的
  `&"achievement"` 类(系统化故代码生成而非 51 个 .tres;真要覆盖/新增往 `data/achievements/` 丢同 id 的 .tres
  经 `load_dir` 覆盖,drop-in 零改代码)。覆盖:**17 转盘奖区命中(jackpot/×100/×20/×5/×2/vermin)+ 5 守卫贿赂 +
  累计/单次产出里程碑 + 投镖数 + NG+/Lethal + 各房首次动作**。

## 飞镖房重构:命运转盘真交互(Fortune Grinder)

把飞镖房从「点按钮→加权命中靶心档」重构为**横版「命运转盘」真交互**:玩家只控**方向 aim + 力度 power**,
扇形多镖各自扎盘、扎上即出金币雨;升级**看得见地改变玩法**;电脑/Android 双端;单 AI 随机→升级练稳准。
仍是 incremental——真交互只是金币复利循环的**引擎点火与油门**,不是独立手速小游戏。范围仅 Room 1。

- **转盘几何/结算(`systems/wheel_layout.gd`,`class_name FortuneWheelLayout`,纯静态无状态)**:`SEGMENTS`
  8 扇区铺满 360°(宽度=难度:越窄倍率越高,含一块 `vermin` ×0 没收段);`segment_at(angle, win_bonus)`
  判命中扇区(`win_bonus` 加宽 jackpot 命中带);`landing(aim, power)` → 落点 `{r, a_off}`(力度甜点
  `POWER_SWEET` 落盘心 r=0,偏离外移);`radial_bonus(r)` 盘心 2.0→边缘 1.0;`fan_offsets(n)` 扇形多镖角偏移;
  `expected_mult(ai_skill)` AI/离线期望倍率。全 float、无 RNG → headless 可测(`test_fortune_wheel`)。
- **model(`systems/darts_room.gd`)**:`throw(aim, power)` 纯函数 + model 自持 `wheel_angle`(`update(dt)` 以
  `WHEEL_SPEED` 推进,view 只读渲染);扇形多镖各以 `fan_offsets` 不同角度扎盘,单镖 = `gold_per_dart × 扇区倍率
  × radial_bonus × global_mul`。jackpot 甜点单镖 = `1×500×2 = 1000`。`auto_gold_rate()` 走 `expected_mult(ai_skill)`
  期望值,保**在线=离线**。
- **6 升级线(看得见地改玩法)**:`sharper_darts`(镖值 add)/`golden_tips`(镖值 mul)/`double_dart`(扇形多镖
  `darts_per_throw`)/`steady_hand`(操作辅助 `aim_steady`)/**`widen_zone`**(加宽 jackpot 命中带 `win_zone`,
  换掉旧 bullseye 解锁)/**`hire_ai`**(雇唯一 1 个 AI:一条驱动 `throws_per_sec` + `ai_skill`,L1 随机瞄准→逐级
  练稳准,自动底薪与手动高技巧并存)。
- **双端输入(`scenes/darts_input.gd`,`FortuneDartsInput`)**:玩家只产 `(aim, power)`;桌面=鼠标 y 定 aim +
  按住蓄力(三角摆动 power)、松开投掷;Android=拉弓(反向=aim、拖长=power)。纯映射 static 可测
  (`test_fortune_input`);跨平台 model/经济/存档完全相同,仅输入层不同。`CoreKit.settings` 的模式覆盖由 view 施加,
  适配器本身不依赖 settings 子系统(保持无头可测)。
- **view + 投掷态机(`scenes/world.gd`)**:自绘 `_WheelView`(Control)读 `model.wheel_angle` 旋转、按 `win_zone`
  画加宽金弧;**首个 fortune-mill dogfood `KitStateMachine`** 投掷态机(桌面 Idle→Charge→Resolve、触屏 Idle→Aim→Resolve)。
- **存档迁移 v3→v4**:升级 id 改名(`bullseye_training`→`widen_zone`、`rattling_gunner`→`hire_ai`)+ 废弃旧
  `dart_tier_*` 统计;成就统计键从 `dart_tier_N` 改为 `dart_seg_<扇区>`(见成就目录)。
- 验收:`test_fortune_wheel` + `test_fortune_input` + 重写的 `test_fortune_darts` 进 kit 门(run_all 37→**39**);
  `FORTUNE_SMOKE` 扩转盘断言 `wheel=jackpot1000/vermin0`。

**统计喂食集中在 `fortune_state` 命令入口**(房间 model 保持纯粹不依赖 stats):`do_throw`→投镖数/累计产出/单次峰值/
各命中档位(`darts.throw` 现返回 `tiers`);`do_scratch`/`drop_ball`/`roll_dice`/`start_craft`/`do_pull`/贿赂/`ascend`/
`buy_prestige_upgrade`/`_check_lethal_finish` 各喂对应键,喂完即 `_evaluate_achievements` 求值广播新解锁。
`_reset_rooms`(NG+/Lethal)**不动 stats/achievements**(spec §185 保留成就/统计)。加载后 `evaluate` 一次自愈补发。

验收:`FORTUNE_SMOKE PASS ... achievements=32/51 throws=657`(全流程解锁 32 条:5 守卫 + NG+ + 各房首次动作 +
产出里程碑,去重再求值无新解锁)。测试 `test_fortune_stats`(add/record_max/set/get/持久化)、`test_fortune_achievements`
(阈值判定 / 去重 / 新解锁列表 / Steam sink 每条一次 / 持久化 / 目录 51 条端到端)进 kit 门。

### 4D 存档版本迁移 + i18n 中英

两个 example-local 孵化类:

- **`systems/save_migrator.gd`(`SaveMigrator`,拟反哺)**:存档 `data` 自带 `schema_version` 版本章,
  `register(from, fn)` 注册 v(n)→v(n+1) 迁移函数,`migrate(data)` 按序跑链。缺失版本章视为 v1(兼容历史老档);
  缺步 / 非字典 / 未来版本 → `ok=false`,由 `load_game` 保底新档(不静默覆盖老档)。`fortune_state`
  `SCHEMA_VERSION=3` + 两步真实历史键改名(`gold`→`currency`、stats.`throws`→`dart_throws`)。
  **机制已反哺进 kit `SaveManager` 信封 `_version`**(v0.22.0):游戏侧改用
  `CoreKit.saves.set_data_version`/`register_migration` 后即可删本类(见仓库根记忆的 P4 收尾清单)。
- **`systems/locale_catalog.gd`(`LocaleCatalog`,游戏专有不反哺)**:代码建 en/zh `Translation` 经
  `CoreKit.i18n`(kit LocaleManager)注册;world 托管 `Theme` + zh CJK `SystemFont` 字体回退(零素材,走 OS 字体族)
  + 语言切换按钮 + 7 列标题/6 主操作按钮走 `t()` → `locale_changed` 重刷。缺翻译告警由 kit `t()` 负责。

验收:`FORTUNE_SMOKE PASS ... migration=v1→v3 i18n=Throw/投镖`。测试 `test_fortune_migration`(迁移链 / 缺版本章默认 v1 /
未来版本安全失败)、`test_fortune_i18n`(注册两语言 / 运行时切换文案不同 / 缺翻译回退 / 字体回退)进 kit 门。

## P5 抛光(真素材 drop-in / 手感)

### 5A 程序化美术接缝 + 赌场皮肤 + fx 手感(`gfx/`)

incremental 原本是纯灰底标签+按钮,5A 给可玩路径加视觉与手感(headless smoke 不受影响——smoke 在 `_build_ui` 前返回):

- **`gfx/art_bank.gd`(`FortuneArtBank`,「美术接缝」)**:UI 图标统一经 `texture_for(key)` 取。
  **先真素材后程序化**——查 `ResourceLoader.exists(assets/<key>.png)`,命中 `load` 真素材,缺失才按房间调色板
  确定性生成 `ImageTexture`(径向渐变筹码)兜底,结果缓存。仓库默认零素材全走程序化;把 png 丢进 `assets/`
  (文件名 = key)即**零改代码顶替**(见 `assets/README.md`)。纯 `Image` 运算 headless 可测,故进 kit 门。
- **赌场皮肤 `Theme`**:毛毡绿背景 + 深底金字按钮(normal/hover/pressed/disabled 分级)+ 七房各按
  art_bank 强调色描边的 `PanelContainer` + 标题栏 art_bank 图标。皮肤 theme 复用 i18n 的 `bind_theme`
  通道(切语言仍换 `default_font`,皮肤样式共存不冲突)。
- **`gfx/fx.gd`(`FortuneFx`,手感层)**:浮字冒泡 `popup`(投镖/刮卡/抽卡的货币增量上浮渐隐)+ 全屏闪光
  `flash`(JACKPOT 金闪 / 过关房间色庆祝)+ 按钮按下脉冲 `pulse`。全走 `Tween` 播完自清理,纯表现不持权威数值。
  增量由命令前后差算(不依赖 model 返回),故不需改数据层。

验收:`FORTUNE_SMOKE PASS ... art=32x32/procedural`(headless 生成 + 房间辨识 + 无真素材走程序化兜底)。
测试 `test_fortune_art_bank`(每房 key 出图/尺寸 / 缓存同实例 / 房间中心色不同 / asset_path 接缝 / 无素材=procedural /
未登记 key 兜底)进 kit 门。fx/皮肤为纯表现,由非 smoke world 90 帧无报错兜底。

### 5B 程序化音效接缝(`sfx/`)

5A 给了视觉/手感,5B 补听觉——结构完全平行 art_bank,更深 dogfood `CoreKit.audio`(AudioManager):

- **`sfx/sound_bank.gd`(`FortuneSoundBank`,音效接缝)**:动作 SFX 统一经 `stream_for(key)` 取。
  **先真音频后程序化**——查 `assets/<key>.wav` 再 `.ogg`,命中 `load` 真音频,缺失才按 key 的 voice 参数
  (基频/时长/波形 blip·noise·arp/扫频)确定性合成 16-bit 单声道 `AudioStreamWAV` 兜底(快起短衰包络),
  结果缓存。仓库默认零音频全走程序化;把 `wav`/`ogg` 丢进 `assets/`(文件名=key)即**零改代码顶替**。
  纯样本运算 headless 可测(dummy 音频驱动),故进 kit 门。
- **播放**:6 类动作(投镖 `throw` / 刮卡 `scratch` / 抽卡 `pull` / 落球发射 `drop` / JACKPOT `jackpot` /
  过关 `clear`)在 world 命令处经 `CoreKit.audio.play_sfx(stream, volume_db, pitch)`(AudioManager 轮转池)播放,
  连续动作带 `pitch` 抖动加活力。柏青哥落槽 tick 仍由物理板 `pachinko_board` 负责(发射音与落槽音分工)。

验收:`FORTUNE_SMOKE PASS ... sfx=0.10s/procedural`(headless 合成 + voice 可辨识 jackpot>throw + 无真音频走程序化)。
测试 `test_fortune_sound_bank`(每 key 合成/时长>0 / 缓存同实例 / voice 时长不同 / asset_path wav·ogg 接缝 /
无音频=procedural / 未登记兜底)进 kit 门(飞镖房转盘重构后共 39 测)。播放为纯表现,由非 smoke world 90 帧无报错兜底。
