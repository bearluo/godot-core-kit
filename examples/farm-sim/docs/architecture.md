# 架构

## 两套并存的系统

`examples/farm-sim/` 里有两套代码,共用 `data/` 与 `systems/` 的部分逻辑:

1. **可玩游戏(主)** —— 有界面、键盘走动。入口 `scenes/world.tscn`,状态支柱 `systems/farm_state.gd`(`Farm` autoload)。本文档讲这套。
2. **旧 dogfood(`legacy/`)** —— 早期 17 段 headless 日志 demo(`legacy/game.gd`),逐段验证 kit 子系统。保留作历史记录,与新游戏并存不冲突。

## 支柱:`Farm` autoload

**问题**:`CoreKit.scenes.change_scene` 是**整场景替换、无栈**——切区时旧场景被 `free`。所以跨场景保留的状态(农田作物、金币、体力、好感度……)**不能待在会被切走的区域场景里**。

**方案**:游戏自己的单例 `Farm`(`systems/farm_state.gd`,`extends Node`,注册在 `project.godot` `[autoload]`)承载**全部跨区状态 + 常驻节点**:

- 数据 `registry` / 背包 `bag` / 农田模型 `grid` / 钱包 `shop` / 任务 `quest_log` / 成就 `tracker` / 天气 `weather` / 好感 `relationships` / 解锁 `unlocked`
- 事件订阅者(须常驻树,作 `Farm` 子节点)
- HUD(挂 `CoreKit.layers` 的 "hud" 层,天然跨场景常驻)+ `KitUiStack` UI 栈 + 全部面板
- 当前区 `current_area` / 落点 `pending_spawn` / 朝向 `pending_facing`

区域场景(`scenes/world`/`house_area`/`town_area`)因此变薄:只建 view + player + 本地布景,状态全读 `Farm`。

**惰性初始化**(守住 kit 回归门):`Farm._ready` 只置 `started=false`,什么都不建;`Farm.start()` 幂等,**只有农田场景首次 `_ready` 才调用**。于是 kit 的 demo / 测试加载工程时不会触发 `Farm.start()` → `run_all` 不被 example 污染。

## model / view 分离

核心逻辑与渲染严格分开,逻辑 headless 可测:

- `systems/farm_grid.gd` —— 纯农田模型(格子状态 / 作物生长 / 季节门 / 存档),不认贴图。
- `use_tool_on(cell)` —— model 级动作派发(吃传入格,facing 由区域算,不依赖具体 player 节点)。
- `grid_changed` 信号 —— 模型变更(耕种浇收 / 生长 / 读档)→ `scenes/farm_grid_view.gd` 连 `queue_redraw` 重绘。
- `fx_requested(kind, cell)` 信号 —— 动作成功 → 农田区爆粒子(见 [art-and-feel.md](art-and-feel.md))。

这条分离贯穿全局:所有渲染层(`*_view` / `player` / `npc`)都是薄壳,读模型画贴图;换真素材、甚至换 2.5D 视角都不动逻辑。

## CoreKit 子系统映射(dogfood 覆盖)

| 游戏功能 | 用到的 CoreKit 能力 |
|---|---|
| 日夜 / 季节 / 推进天 | `CoreKit.clock`(季节日历 + `clock:day_changed` 广播) |
| 背包 | `KitInventory`(off-facade,槽位制) |
| 内容数据(作物/物品/NPC/任务/成就) | `KitDataRegistry`(多类型 `.tres` 定义) |
| 存读档 | `CoreKit.saves`(`Farm.save_game/load_game` 收敛一处) |
| 作物生长状态(legacy) | `KitStateMachine`(每实体 Growing→Mature) |
| 面板导航 | `KitUiStack`(背包/商店/菜单/对话模态入栈) |
| HUD 常驻 | `CoreKit.layers`("hud" 层跨场景) |
| 区域切换 + 转场 | `CoreKit.scenes` + `KitTransition`(FADE / SLIDE + 缓动) |
| 事件链 | `CoreKit.bus`(`clock:` / `weather:` / `shop:` / `quest:` / `npc:` 命名空间) |
| 偏好(语言/音量/键位) | `CoreKit.settings`(分区,非存档槽) |
| 多语言 | `CoreKit.i18n`(内存 Translation) |
| 音频 | `CoreKit.audio`(音量 + 程序化 SFX/BGM) |
| 键位重绑定 | `CoreKit.input` + `KitRebindList`(设置面板) |

## 分支纪律

- farm-sim 代码全部留在 **`example/farm-sim` 分支**,**不合 main、不升 kit 版本、push 留给用户**。
- 只有 dogfood 中发现的 **kit 缺口**才剥出来走正常 kit SDD → 合 main → example rebase。
- 理由:`run_all` 首步 `--import` 扫全工程含 examples,半成品游戏的 parse error 会连累 kit 门,故隔离在分支;kit 主干保持干净版本化。

## 测试

| 层 | 文件 | 说明 |
|---|---|---|
| 纯逻辑(离线) | `test/test_farm_grid{,_save,_season}.gd`、`test_relationship.gd`、`test_art_bank.gd` | `SceneTree` + 运行时 `load`,不依赖 `CoreKit`;各自 ALL PASS |
| 端到端 | `Farm.run_smoke()`(env `FARM_SMOKE=1` 门控) | 走 `use_tool_on` model 级派发,覆盖 P0–P5 全链,打印 `[Farm][SMOKE] PASS` |

真实场景切换 / 手感 / 观感难 headless 验 → 编辑器手动 F5。**farm 测刻意不进 `run_all` 的 `$tests`**(那是 kit 回归门)。
