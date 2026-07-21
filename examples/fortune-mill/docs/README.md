# fortune-mill 功能文档

P0 阶段只有飞镖房。目录:

- `defs/` —— 升级定义 Resource schema
- `systems/` —— 纯数据层(Currency/KitModifiers/DartsRoom/FortuneMill autoload)
- `scenes/` —— world 场景 + 表现层
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
