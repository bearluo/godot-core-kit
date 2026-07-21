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
