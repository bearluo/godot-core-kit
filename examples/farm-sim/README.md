# farm-sim —— godot-core-kit 的农场经营示例

一款俯视、键盘走动的**星露谷式农场经营游戏**,建在 [godot-core-kit](../../addons/godot-core-kit/) 上,用真实玩法 dogfood 验证框架各子系统。种田 → 卖钱 → 升级/解锁 → 多区域探索 → 与 NPC 交往,一个"再玩一天"的每日循环。

## 快速开始

- **编辑器里玩**:运行工程(主场景 `scenes/world.tscn`)。`WASD` 走 · `J` 用工具/交互 · `N` 睡觉 · `Q` 切种子 · `I` 背包 · `P` 商店 · `L` 任务成就 · `Esc` 菜单 · 走门切区。
- **headless 自测**:`FARM_SMOKE=1 godot --headless --path . res://examples/farm-sim/scenes/world.tscn` → `[Farm][SMOKE] PASS`。
- 首次跑先 `godot --headless --path . --import` 生成 `class_name` 缓存与 `.uid`。

## 功能文档(`docs/`)

| 文档 | 内容 |
|---|---|
| [docs/README.md](docs/README.md) | 索引 + 目录结构 + 怎么跑 |
| [docs/architecture.md](docs/architecture.md) | `Farm` autoload 支柱、model/view 分离、CoreKit 子系统映射、分支纪律、测试 |
| [docs/farming.md](docs/farming.md) | 种田循环:网格 / 作物 / 工具 / 体力 / 季节 / 天气 / 水壶升级 |
| [docs/economy.md](docs/economy.md) | 经济:商店 / 数值曲线表 / 任务 / 成就 |
| [docs/world-and-npc.md](docs/world-and-npc.md) | 多区域世界 + NPC 社交(日程 / 对话 / 送礼 / 好感 / 解锁) |
| [docs/art-and-feel.md](docs/art-and-feel.md) | 美术接缝 / 程序化贴图 / 走路动画 / 粒子 / 手感 / 音效 / 真素材 drop-in |

## 目录结构

```
farm-sim/
├─ docs/      功能文档(本表)
├─ defs/      数据定义脚本 *_def.gd(给 .tres 用的 Resource schema)
├─ systems/   非视觉逻辑(farm_state autoload / farm_grid / shop / quest_log /
│             achievement_tracker / weather_system / relationship)
├─ scenes/    场景根+区域+实体+view(world/house/town + area_base/player/npc/
│             door/farm_grid_view/target_highlight/weather_view)
├─ ui/        hud + 面板(inventory/shop/pause/log/settings/dialogue)
├─ gfx/       程序化美术/音频/粒子/i18n(art_bank/audio_bank/fx/i18n_strings)
├─ data/      内容 .tres(crops/items/npcs/quests/achievements/greenhouse_crops)
├─ assets/    真素材放置处(空;PNG 丢入即覆盖程序化贴图)
└─ legacy/    旧 dogfood 17 段 headless demo(见 legacy/README.md)
```

## 约定

- 全部代码留 **`example/farm-sim` 分支**,不合 main、不升 kit 版本、push 留用户;只有 kit 缺口才剥到 main 走 SDD。详见 [docs/architecture.md](docs/architecture.md)。
- farm 测试独立单跑,**不进** kit 的 `test/run_all.ps1` 门。
