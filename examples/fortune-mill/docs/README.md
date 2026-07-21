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
