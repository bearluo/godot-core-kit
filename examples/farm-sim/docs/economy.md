# 经济:商店 · 数值 · 任务 · 成就

## 商店与钱包 `systems/shop.gd`

kit 无货币子系统,游戏自建 `shop`(`Farm` 子节点):`gold` 钱包 + `buy(item, n)` / `sell(item, n)`,按 `item_def` 的 `buy_price`/`sell_price` 结算。起始金币 **500**。交易广播游戏自有命名空间事件 `shop:bought` / `shop:sold`(payload 含 `earn`/`item`/`qty`)——被任务/成就订阅。商店面板 `ui/shop_panel.gd`(`P` 键)。

物品定义 `defs/item_def.gd` + `data/items/*.tres`:`id` / `display_name` / `max_stack` / `category`(seed/produce/misc) / `buy_price` / `sell_price`。

## 数值曲线(四轴单调递增)

设计目标:**低门槛起步 → 逐级高投入高回报**,日均利润 / 种子价 / 生长天 / 卖价四轴全部递增,高投入 = 更高日均 + 更长回本周期。

| tier | 作物 | 生长天 | 每株产量 | 种子买价 | 产物卖价 | 毛利=量×卖−种 | **日均利润** |
|---|---|---|---|---|---|---|---|
| 1 | 白萝卜 turnip | 2 | 3 | 12 | 18 | 42 | **21.0** |
| 2 | 土豆 potato | 3 | 2 | 24 | 51 | 78 | **26.0** |
| 3 | 防风草 parsnip | 4 | 2 | 32 | 78 | 124 | **31.0** |
| 4 | 南瓜 pumpkin(秋限) | 5 | 2 | 45 | 115 | 185 | **37.0** |
| ★ | 星之果 star_fruit | 4 | 1 | 0(好感解锁赠) | 300 | 300 | **75.0** |

- **星之果**独立于买卖曲线:唯一途径是与商人好感达 100 解锁赠种(见 [world-and-npc.md](world-and-npc.md)),日均 75 为终局奖励。
- 相关常量:`ACTION_COST=8`、`WATER_UPGRADE_COST=200`、起始金币 500、起始种子 turnip/parsnip/potato ×10 + pumpkin ×5。
- 改价须知:数值与任务/成就的阈值断言耦合——改价前先核对 `Farm.run_smoke()` 里 `first_income`(累计 100 金币)等断言(教训见 git 历史)。

## 任务 `defs/quest_def.gd` + `systems/quest_log.gd`

`quest_log`(`Farm` 子节点)**一个订阅方同时消费 `clock:day_changed` + `shop:sold` 两来源**推进目标。任务类型:

| kind | 达标条件 | 示例(`data/quests/`) |
|---|---|---|
| `earn_gold` | 累计卖出收入 ≥ target | first_income(100 金币) |
| `sell_count` | 卖出某物品累计 ≥ target | turnip_tycoon(3 白萝卜) |
| `reach_day` | 到第 N 天 | survive_day5(第 5 天) |

达标广播 `quest:completed`。任务进度**随存档槽**保存(每档独立)。

## 成就 `defs/achievement_def.gd` + `systems/achievement_tracker.gd`

`tracker` 聚合 `shop:bought` + `quest:completed` + `weather:changed` **三来源**判里程碑(`data/achievements/`:all_quests / first_purchase / rain_dancer)。解锁广播 `achievement:unlocked`。

**核心边界(dogfood 重点)**:
- **任务 = 每档进度** → 存**存档槽**(`CoreKit.saves`),删档丢失。
- **成就 = 账号级** → 存 **`CoreKit.settings`**("achievements" 分区),删档不丢。

任务/成就面板 `ui/log_panel.gd`(`L` 键)。同为跨存档偏好走 Settings 分区的还有:语言(locale)、音量(audio)、键位(input)——见 [art-and-feel.md](art-and-feel.md) 与 [architecture.md](architecture.md)。
