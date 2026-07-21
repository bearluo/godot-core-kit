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
