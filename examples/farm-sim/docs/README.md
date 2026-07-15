# farm-sim 功能文档

`examples/farm-sim/` 是 **godot-core-kit** 的 dogfood 示例:一款俯视、键盘走动的星露谷式农场经营游戏,用来在真实玩法里验证框架各子系统。本目录是它的功能/架构文档。

> 想了解 **kit 本身**的 API,看 `addons/godot-core-kit/docs/`;这里只讲 **farm-sim 游戏**怎么搭、各功能在哪。

## 怎么跑

| 目的 | 命令(仓库根执行) |
|---|---|
| 编辑器里玩 | 直接运行工程(main_scene = `scenes/world.tscn`) |
| headless 端到端自测 | `FARM_SMOKE=1 godot --headless --path . res://examples/farm-sim/scenes/world.tscn` → 打印 `[Farm][SMOKE] PASS` |
| 纯逻辑测(离线) | `godot --headless --path . -s res://test/test_farm_grid.gd`(还有 `test_farm_grid_save`/`test_farm_season`/`test_relationship`/`test_art_bank`) |
| 旧 dogfood(17 段日志 demo) | `godot --headless --path . res://examples/farm-sim/legacy/game.tscn --quit-after 200` |

> farm 的测试**不进 kit 的 `test/run_all.ps1` 门**(那是 kit 回归门);farm 测独立单跑。`run_all` 仍 `FAILS=0` 不受 example 影响。

## 操作(编辑器内游玩)

`WASD` 走动 · `J` 用工具(耕→种→浇→收 / 与身边 NPC 对话 / 床睡觉 / 商店牌开店) · `N` 睡觉推进一天 · `Q` 切种子 · `I` 背包 · `P` 商店 · `L` 任务/成就 · `Esc` 菜单(存读档 / 设置)。走进区域边缘的门切换农田 / 农舍 / 小镇。

## 目录结构

| 目录 | 职责 |
|---|---|
| `defs/` | 数据定义脚本(`*_def.gd`,给 `.tres` 用的 Godot Resource schema) |
| `systems/` | 非视觉逻辑,多数 headless 可测(`farm_state` autoload / `farm_grid` 模型 / `shop` / `quest_log` / `achievement_tracker` / `weather_system` / `relationship`) |
| `scenes/` | 场景根 + 区域 + 场景内实体/渲染(`world`/`house_area`/`town_area` + `.tscn` / `area_base` / `player` / `npc` / `door` / `farm_grid_view` / `target_highlight` / `weather_view`) |
| `ui/` | HUD + 面板(`hud` / `inventory_panel` / `shop_panel` / `pause_menu` / `log_panel` / `settings_panel` / `dialogue_panel`) |
| `gfx/` | 程序化美术/音频/粒子/本地化(`art_bank` / `audio_bank` / `fx` / `i18n_strings`) |
| `data/` | 内容数据(`.tres`:crops / items / npcs / quests / achievements / greenhouse_crops) |
| `assets/` | 真素材放置处(空着;PNG 丢进来即覆盖程序化贴图,见 [art-and-feel.md](art-and-feel.md)) |
| `legacy/` | 旧 dogfood 17 段 headless demo(`game` / `farm` / `climate` / `backpack_panel` / `crop`),与新游戏并存作历史记录 |

## 文档索引

- [architecture.md](architecture.md) —— 架构:Farm autoload 支柱、model/view 分离、CoreKit 子系统映射、分支纪律、测试
- [farming.md](farming.md) —— 种田循环:网格 / 作物 / 工具 / 体力 / 季节 / 天气 / 水壶升级
- [economy.md](economy.md) —— 经济:商店 / 数值曲线表 / 任务 / 成就
- [world-and-npc.md](world-and-npc.md) —— 多区域世界 + NPC 社交(日程 / 对话 / 送礼 / 好感 / 解锁)
- [art-and-feel.md](art-and-feel.md) —— 美术接缝 / 程序化贴图 / 走路动画 / 粒子 / 手感 / 音效 / 真素材 drop-in
