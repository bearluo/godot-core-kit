# 农场经营 MVP 骨架(farm-sim)

用一条确定性剧情把三个"农场向"子系统串起来 dogfood 验证:**时钟推进一天 → 作物长一格 → 成熟收获入背包**。整段是**框架消费者视角**——只调 `CoreKit.*` 与两个 `class_name` 类库(`KitInventory`/`KitDataRegistry`),不碰 kit 内部,专门用来暴露三者协作时的缺口。

验证的三个子系统:

| 子系统 | 在本例中的角色 |
|---|---|
| `KitDataRegistry`(off-facade) | 从 `data/*.tres` 用 `load_dir` 载入作物定义表,按 id `get_def` 查 |
| `KitInventory`(off-facade) | 玩家背包:发种子、播种扣种子、收获入库(`add`/`remove`/`count`) |
| `CoreKit.clock` + `CoreKit.bus` | 逐日推进,每天广播 `clock:day_changed`,作物订阅后生长(跨子系统解耦) |

## 文件

| 文件 | 作用 |
|---|---|
| `crop_def.gd` | 作物定义 `Resource`(游戏侧数据结构:id/天数/种子/产物/数量) |
| `data/turnip.tres` / `data/parsnip.tres` | 两份作物定义 `.tres`,供 `load_dir` 扫描载入 |
| `crop.gd` | 一株已播种作物(Node)。订阅 `CoreKit.clock.EV_DAY_CHANGED`,每天长 1 格 |
| `farm.gd` | 农田 = 集成粘合层。持有注入的 registry+背包,负责 `plant`/`harvest_all` |
| `game.gd` / `game.tscn` | 驱动:载表 → 发种 → 播种 → 推进 4 天 → 收获 → 结算。整条故事的入口 |

## 跑法

- **编辑器**:把 `game.tscn` 设为主场景运行,看输出面板。
- **Headless**:
  ```
  godot --headless --path . res://examples/farm-sim/game.tscn --quit-after 120
  ```
  (首次需先 `godot --headless --path . --import` 生成 `KitInventory`/`KitDataRegistry` 的 `class_name` 缓存。)

## 预期输出

(以下略去每行的 `[时间][INFO]` 日志前缀)

```
[Farm] 载入 2 种作物: parsnip, turnip
[Bag] 初始种子: turnip_seed=3 parsnip_seed=3
[Farm] 播种 turnip (消耗 1 turnip_seed)
[Farm] 播种 parsnip (消耗 1 parsnip_seed)
[Bag] 播种后种子: turnip_seed=2 parsnip_seed=2
[Clock] 开局 y1 spring d1 06:00
[Crop:turnip] 第 2 天 生长 1/2
[Crop:parsnip] 第 2 天 生长 1/4
[Crop:turnip] 第 3 天 生长 2/2  已成熟
[Crop:parsnip] 第 3 天 生长 2/4
[Crop:parsnip] 第 4 天 生长 3/4
[Crop:parsnip] 第 5 天 生长 4/4  已成熟
[Farm] 收获 turnip x3 → 背包
[Farm] 收获 parsnip x2 → 背包
[Bag] 最终库存: turnip=3 parsnip=2 turnip_seed=2 parsnip_seed=2
[Clock] 结束 y1 spring d5 06:00
```

逐段对应验证点:
1. `载入 2 种作物` —— `KitDataRegistry.load_dir` 扫 `data/` 把两份 `.tres` 按 `id` 属性存进 `"crop"` 类型。
2. `播种…消耗种子` —— `plant` 查 `get_def` 拿定义、`KitInventory.remove` 扣 1 个种子、spawn 一株 `Crop`。
3. `[Crop:*] 第 N 天 生长 x/y` —— 每次 `CoreKit.clock.advance_day()` 经 `CoreKit.bus` 广播 `clock:day_changed`,作物**只认事件、不认时钟**地长一格(turnip 2 天熟、parsnip 4 天熟)。
4. `收获 … → 背包` —— 成熟作物把产物 `KitInventory.add` 进背包,自身 `free()`。
5. `最终库存` —— 背包同时留着 turnip×3 / parsnip×2 产物与各 2 个剩余种子,证明堆叠与增减都对。

## 要点

- **消费者视角、零 kit 侵入**:整例不 `preload` 任何子系统脚本,`registry`/`bag` 全由驱动方 `farm.bind(...)` 注入——这正是"用 core-kit 做游戏"的推荐姿势。
- **跨子系统靠 bus 解耦**:作物不持有时钟引用,只订阅事件名常量 `CoreKit.clock.EV_DAY_CHANGED`(命名约定 `namespace:event`,见 [`event-bus.md`](../../addons/godot-core-kit/docs/core/event-bus.md))。换任何东西驱动"过一天"都不用改作物。
- **payload = 快照**:`clock:*` 事件的 payload 是 `clock.snapshot()` 的 `Dictionary`(`year/season_index/season_name/day/hour/minute`),作物直接读 `snap["day"]`。
- **Node 监听者主动清理**:`Crop._exit_tree` 调 `CoreKit.bus.unsubscribe_all(self)`,收获 `free` 时不留悬空订阅(自动剔除之外的显式保险)。
- **这是骨架不是成品**:没有网格地块、工具体力、动物 NPC、存档——那些是"游戏本体",不属于 kit。本例只验证三块地基能不能顺畅拼在一起。
- 三个子系统完整 API 见 [`game-clock.md`](../../addons/godot-core-kit/docs/systems/game-clock.md) / [`kit-inventory.md`](../../addons/godot-core-kit/docs/inventory/kit-inventory.md) / [`kit-data-registry.md`](../../addons/godot-core-kit/docs/data/kit-data-registry.md)。
