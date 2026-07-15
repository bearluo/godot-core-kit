# farm-sim P3 · 生活模拟支柱(NPC + 多区域)实现计划

> **执行方式:** 主会话 inline 执行(executing-plans)。每 Task 独立可测,结尾一次 headless 断言 + 一个
> 编辑器 F5 检查点;做完 1-2 个停下让需求方 F5。步骤用 `- [ ]` 追踪。设计见
> `docs/superpowers/specs/2026-07-15-farm-sim-p3-life-sim-design.md`。

**Goal:** 把单场景农场扩成多区域世界(农田/农舍/小镇,`CoreKit.scenes`+`KitTransition` 切场景)+ 数据驱动
NPC(对话/送礼/好感度/好感解锁),持久状态上移到 `Farm` autoload。

**Architecture:** `Farm` autoload 持有全部跨场景状态与持久节点(model + quest_log/tracker/weather + HUD +
UI 栈 + 面板);区域场景变薄,只建 view + player + 本地布景 + 输入派发(路由到 Farm)。区域切换走整场景替换。

**Tech Stack:** Godot 4.7 GDScript;core-kit 门面(`clock/bus/scenes/layers/i18n/audio/settings/saves`)+ 类库
(`KitDataRegistry/KitInventory/KitUiStack/KitTransition/KitRebindList`)。

## Global Constraints(每 Task 隐含遵守)

- **分支纪律**:改动留 `example/farm-sim`,**不升版本、不合 main、push 留用户**。
- **不碰 kit 内部**;P3 若现 kit 缺口 → 记"反哺候选",分支分流剥到 main 单独 SDD,不在本计划改 kit。
- **不动旧 dogfood** game.gd/game.tscn(kit 回归)。
- **GDScript 坑**:RHS 来自无类型注入对象(Farm 里多为无类型 var)时用 `var x =`,**不用 `:=`**。
- **缩进 Tab**。
- **验收门**:每 Task 结尾 `powershell -File test\run_all.ps1` 仍 `FAILS=0`;`FARM_SMOKE=1` 跑 farm 场景打印
  `[Farm][SMOKE] PASS`;相关 headless 逻辑测 ALL PASS。
- **git**:每 Task 一 commit,message 结尾 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`,
  用 Bash heredoc `git commit -F - <<'EOF' … EOF`。

## `Farm` autoload API(Task 1 建立,后续任务扩展 —— 全局契约)

`examples/farm-sim/farm_state.gd`(extends Node,autoload 名 `Farm`)。**惰性**:`_ready` 只置 `started=false`;
`start()` 首次被农田场景调用才建全部。

```
# 生命周期
var started: bool
func start() -> void                       # 幂等:load 数据 + 建 grid/bag/shop/quest_log/tracker/weather
                                           #      + 配置 clock(7天/季)+ i18n install + 建 HUD/UI栈 + 订阅
func run_smoke() -> void                   # FARM_SMOKE=1 时农田场景 call_deferred 调;打印 [Farm][SMOKE] PASS

# 只读状态（供 HUD/面板/区域）
var registry, bag, grid, shop, quest_log, tracker, weather   # 无类型 var
var relationships: Dictionary              # {npc_id:int}（P5 用）
var unlocked: Dictionary                   # {npc_id:true}（P6 用）
func energy() -> int
func energy_max() -> int
func water_radius() -> int
func water_upgraded() -> bool
func selected_crop_name() -> String        # i18n 本地化
func selected_crop_plantable() -> bool
func weather_name() -> String

# 玩法动作（区域输入派发调用；纯 model 级，不依赖具体 player 节点）
func use_tool_on(cell: Vector2i) -> bool   # 按格状态派发 耕→种→浇→收；成功扣体力+播SFX+精疲自动睡
func sleep() -> void                       # advance_day + 回体力 + SFX
func cycle_seed() -> void
func buy_water_upgrade() -> bool

# UI（HUD + KitUiStack + 全部面板都归 Farm，挂 CoreKit.layers，跨区域常驻）
func toggle_ui(name: String) -> void       # inventory/shop/menu/log/settings/dialogue
func open_settings() -> void
func close_menu() -> void
func is_ui_open() -> bool
func route_action(action: String) -> void  # 面板开时把 move_up/down/farm_use 转给活动面板
func open_dialogue(npc) -> void            # P4：打开对话面板（npc = NPC 节点/定义）

# 区域切换（P2 计划 Task2）
var current_area: String
var pending_spawn: Vector2                  # 目标出生点（切换前写，新区读）
func go_to(area_path: String, spawn: Vector2, transition) -> void   # 写 pending_spawn + change_scene

# 存读档（收敛到一处）
func save_game() -> void
func load_game() -> bool
func i18n_cycle_locale() -> void            # 供 settings 面板

# 好感度（P5/P6）
func gift_to(npc_id: StringName, item_id: StringName) -> Dictionary  # {reaction:String, delta:int, unlocked:bool}
func chat_with(npc_id: StringName) -> void                          # 当日首聊 +好感
func friendship(npc_id: StringName) -> int
func friendship_level(npc_id: StringName) -> int
```

## 文件结构(P3 新增/修改)

| 文件 | 责任 | Task |
|---|---|---|
| `examples/farm-sim/farm_state.gd` | **`Farm` autoload**:全部持久状态 + 玩法/UI/存档 API | 1 |
| `project.godot` | +`[autoload] Farm`;+`interact` 输入动作(town 交互;或复用 farm_use) | 1,2 |
| `examples/farm-sim/world.gd` | 农田场景变薄:view+player+highlight+weather_view+输入派发→Farm | 1 |
| `examples/farm-sim/{hud,pause_menu,shop_panel,settings_panel,inventory_panel,log_panel}.gd` | bind 目标从 world 改 Farm | 1 |
| `examples/farm-sim/area_base.gd` | 区域基类:玩家生成/移动、面板路由、区域切换、出生点 | 2 |
| `examples/farm-sim/{house_area,town_area}.tscn/.gd` | 农舍/小镇场景 | 2 |
| `examples/farm-sim/door.gd` | 边界/门触发区(Area2D),走进切场景 | 2 |
| `examples/farm-sim/npc_def.gd` + `data/npcs/*.tres` | NPC 定义(registry 第 5 类型) | 3 |
| `examples/farm-sim/npc.gd` | NPC 占位节点(色块+名,按日程站位,可交互) | 3 |
| `examples/farm-sim/dialogue_panel.gd` | 对话 + 聊天/送礼/离开选项 | 4,5 |
| `examples/farm-sim/relationship.gd` | 好感度纯逻辑(加减/等级/解锁判定),供 Farm + 测试 | 5,6 |
| `test/test_relationship.gd` | 好感度 headless 逻辑测 | 5 |

---

### Task 1: 持久化重构 → `Farm` autoload(P0-P2 迁移,玩法零变化)

**目标**:把 world.gd 里全部 model + 持久节点 + UI + 存档 + smoke 搬进 `Farm` autoload,world.gd 变薄成"农田场景"
(view+player+输入派发)。**P0-P2 玩法与 F5 手感必须完全不变**,这是纯重构。

**Files:** Create `farm_state.gd`;Modify `world.gd`、`project.godot`(autoload)、六个 UI 脚本(bind 目标)。

- [ ] **Step 1:** 建 `farm_state.gd`(extends Node)。把 world.gd `_ready` 里**建 model 的部分**搬进 `Farm.start()`:
  load registry(crop/item/quest/achievement 四类)、建 bag+起始种子、`crop_ids`、`clock.configure({days_per_season:7})`、
  `I18nStrings.install()`+默认 locale+连 locale_changed、建 grid(FarmGrid)、shop、quest_log、tracker、weather(add_child 到
  Farm)、订阅 `weather:changed`→`_on_weather`、订阅 shop 买卖→SFX、播 BGM。`start()` 用 `if started: return` 幂等守卫。
  `_ready()` 里**只** `started = false`(惰性,demo/测试不触发)。

- [ ] **Step 2:** 把 world.gd 的 model 级方法搬到 Farm 并按上面 API 命名:`use_tool_on(cell)`(原 `_use_tool` 去掉
  `_player.facing_cell()`,改吃传入 cell;facing 由区域算)、`sleep`、`cycle_seed`、`selected_crop_name/plantable`、
  `energy/energy_max`、`water_radius/water_upgraded/buy_water_upgrade`、`_water_area`、`weather_name`、`_on_weather`、
  `_sfx`、`i18n_cycle_locale`(原 cycle_locale)、`save_game/load_game`(存档新增 `current_area`;player 位置改由区域在切换/存档时写入 Farm)。

- [ ] **Step 3:** UI 归 Farm:把 HUD 创建、`KitUiStack` 创建/挂载、`_open_ui/_close_ui/_toggle_ui/close_menu/open_settings/
  _rebuild_active_ui/_on_locale_changed`、`is_ui_open()`、`route_action(action)`(原 world `_unhandled_input` 里"面板开时转发
  给 top.handle_action"的那段)搬到 Farm。HUD `bind(CoreKit.clock, shop, self)`(self=Farm)。面板在 Farm 的 `_open_ui` 里建。

- [ ] **Step 4:** 六个 UI 脚本 bind 目标从 world 改 Farm(纯改传入对象,方法名不变——Farm 提供同名 save_game/load_game/
  open_settings/close_menu/buy_water_upgrade/water_upgraded/WATER_UPGRADE_COST/cycle_locale→i18n_cycle_locale/energy/
  energy_max/selected_crop_name/selected_crop_plantable/weather_name)。`settings_panel` 的 `cycle_locale` 调用改
  `Farm.i18n_cycle_locale`;`shop_panel`/`pause_menu` bind 传 Farm。

- [ ] **Step 5:** world.gd 变薄成农田场景:`_ready` → `Farm.start()`;建 `_view`(FarmGridView.bind(Farm.grid))、`_player`
  (spawn 到网格中央)、`_highlight`、`_weather_view`(CanvasLayer);`_unhandled_input`:面板开 → `Farm.route_action`;否则
  toggle 键 → `Farm.toggle_ui`;farm_use(J)→ `if Farm.use_tool_on(_player.facing_cell()): _view.queue_redraw()`;
  farm_next_day(N)→`Farm.sleep()`;cycle_seed(Q)→`Farm.cycle_seed()`。玩家 `input_locked` 由 Farm 开关面板时设(Farm 持
  当前 player 引用:区域 `_ready` 里 `Farm.bind_player(_player)`)。存档时 world 把 `_player.global_position/facing` 写进 Farm。

- [ ] **Step 6:** `project.godot` `[autoload]` 段加 `Farm="*res://examples/farm-sim/farm_state.gd"`(在 CoreKit 之后)。

- [ ] **Step 7:** smoke 搬到 `Farm.run_smoke()`:不再依赖真实 player,直接 `use_tool_on(cell)` 系列 + sleep + 升级 +
  存读档 + 五面板 + i18n + 音频断言(原逻辑照搬,`_player.facing_cell()` 换成显式 cell,player 位置往返改测 Farm 里存的
  位置字段或跳过)。打印 `[Farm][SMOKE] PASS`。world.gd `_ready` 里 `if OS.get_environment("FARM_SMOKE")=="1": call_deferred` 调
  `Farm.run_smoke`(经 Farm)。

- [ ] **Step 8:** import + `FARM_SMOKE=1` 跑 world.tscn → `[Farm][SMOKE] PASS`;`run_all` FAILS=0(**验 Farm autoload 惰性
  未污染 demo**);编辑器 F5 手动确认 P0-P2 全部照旧(走动/耕种浇收/天气/季节/体力/背包商店菜单/存读档/L/设置/音效)。

- [ ] **Step 9:** commit `refactor(farm-sim P3): 持久状态上移 Farm autoload（P0-P2 迁移，玩法零变化）`。

---

### Task 2: 多区域 + 场景切换(农舍/小镇 + 转场)

**Files:** Create `area_base.gd`、`house_area.tscn/.gd`、`town_area.tscn/.gd`、`door.gd`;Modify `world.gd`(改 extends
`area_base`)、`farm_state.gd`(`go_to`/`pending_spawn`/`current_area` + 存档带区域)、`project.godot`(`interact` 动作可选)。

**Interfaces:**
- Produces: `AreaBase`(玩家生成/移动/面板路由/`_go_to(area_path, spawn, transition)`);`Farm.go_to`;`Door`(Area2D,
  `setup(target_area_path, target_spawn, transition)`,body_entered→Farm.go_to)。

- [ ] **Step 1:** 写 `area_base.gd`(extends Node2D):`@export var area_name: String`;`_ready`:`Farm.start()`;建 player
  于 `Farm.pending_spawn`(无则区域默认出生点),`Farm.bind_player(player)`,`Farm.current_area = area_name`;
  `_unhandled_input`:面板开→`Farm.route_action`;toggle 键→`Farm.toggle_ui`;移动交给 player。工具/交互留给子类
  `_on_use()` 虚方法(农田=用工具,小镇/农舍=交互身边 NPC/物件)。`_go_to(path, spawn, t)` → 存 player 位置到 Farm →
  `Farm.go_to(path, spawn, t)`。

- [ ] **Step 2:** `farm_state.gd` 加区域切换:`var current_area`、`var pending_spawn`;`func go_to(path, spawn, t)`:
  `pending_spawn = spawn`;`await CoreKit.scenes.change_scene(path, t)`。存档 to_dict 加 `current_area`;load 后需切到该区
  (读档若跨区,`go_to` 到存档区)。

- [ ] **Step 3:** world.gd 改 `extends` `area_base.gd`,`area_name="farm"`;farm 专属(grid view/weather_view/highlight/
  `_on_use`=用工具)留在 world.gd。

- [ ] **Step 4:** 写 `door.gd`(Area2D + CollisionShape2D + 占位色块提示):`setup(target_path, target_spawn, transition)`;
  `body_entered(body)`:若是 player → `get_parent()._go_to(...)`(或直接 `Farm.go_to`)。农田放两个门(→农舍 FADE、→小镇 SLIDE)。

- [ ] **Step 5:** 写 `house_area.tscn/.gd`(extends area_base,area_name="house"):占位地板 + 一张床(Area2D,交互→
  `Farm.sleep()` + 可存档)+ 一个门回农田。`town_area.tscn/.gd`(area_name="town"):占位地面 + 商店牌子(交互→
  `Farm.toggle_ui("shop")`)+ 门回农田。各区玩家默认出生点设在门口内侧。

- [ ] **Step 6:** smoke 加区域往返:`Farm.go_to` 无法在纯 headless 无场景树轻易验(change_scene 要真实 tree)——改为在
  smoke 里断言 `Farm` 的区域状态字段(pending_spawn/current_area 读写)+ 农田状态在"模拟切走再切回"(不真 change_scene,
  只重建 view 读同一 Farm.grid)后不丢。真实转场留 F5。

- [ ] **Step 7:** import + FARM_SMOKE PASS + run_all FAILS=0;**F5**:农田走到门 → 转场(FADE/SLIDE)→ 农舍/小镇;农舍睡觉、
  小镇开商店;回农田,已种作物/背包/金币都在。

- [ ] **Step 8:** commit `feat(farm-sim P3): 多区域世界 + 场景切换转场（农田/农舍/小镇，CoreKit.scenes+KitTransition）`。

---

### Task 3: NPC 数据 + 出现 + 日程

**Files:** Create `npc_def.gd`、`data/npcs/*.tres`(1-2 个 NPC)、`npc.gd`;Modify `farm_state.gd`(load npc 类型 +
`npcs_in_area(area, hour)`)、`town_area.gd`(实例化本区 NPC)。

**Interfaces:**
- Produces: `NpcDef`(见 spec §4 字段);`NPC` 节点(`setup(def)`,占位色块+名 Label,`tile_pos()`);
  `Farm.npcs_in_area(area, hour) -> Array`(按 schedule 取当前在该区的 NPC def + 站位)。

- [ ] **Step 1:** 写 `npc_def.gd`(extends Resource):id/display_name/home_area/schedule(Array of Dict)/dialogue(Array)/
  gift_loved/gift_liked/gift_disliked(Array)/unlock_at(int)/unlock_item(StringName)。

- [ ] **Step 2:** 建 1-2 个 NPC .tres(如 `merchant.tres`:home_area=town,dialogue 几句,gift_loved=[turnip],
  unlock_at=100,unlock_item=star_seed;可选 `granny.tres` home_area=house)。schedule 起步:单项 `[{after_hour:0,
  area:town, x:.., y:..}]`(全天在镇);想演示日程可加 `{after_hour:18, area:house,...}`。

- [ ] **Step 3:** `farm_state.gd`:`start()` 里 `registry.load_dir(&"npc", ".../data/npcs")`(registry 第 5 类型);
  `func npcs_in_area(area, hour) -> Array`:遍历 npc defs,按 schedule 选当前时段项,area 匹配则收 `{def, cell}`。

- [ ] **Step 4:** 写 `npc.gd`(extends Node2D 或 CharacterBody2D 静态):`setup(def)`;`_draw` 占位色块 + 头顶
  `Label`(display_name);`tile_pos()`(格坐标,供相邻判定)。

- [ ] **Step 5:** `town_area.gd`(及 house)`_ready`:`for e in Farm.npcs_in_area(area_name, CoreKit.clock.hour()): 实例化 NPC
  摆到 e.cell`。存 `_npcs` 供交互查最近。

- [ ] **Step 6:** import + FARM_SMOKE PASS(加 `npcs_in_area` 断言:镇上至少 1 个 NPC def)+ run_all FAILS=0;**F5**:进小镇
  看到 NPC 色块 + 名字站在指定位置。

- [ ] **Step 7:** commit `feat(farm-sim P3): NPC 数据驱动定义 + 占位出现 + 轻量日程（registry 第5类型）`。

---

### Task 4: 对话系统

**Files:** Create `dialogue_panel.gd`;Modify `area_base.gd`/`town_area.gd`(`_on_use` 找最近 NPC → `Farm.open_dialogue`)、
`farm_state.gd`(`open_dialogue` + dialogue 面板接入 UI 栈)。

- [ ] **Step 1:** 写 `dialogue_panel.gd`(Control,KitUiStack):`bind(npc_def, farm)`;显示 NPC 名 + 当前台词 + 选项
  `[聊天]/[送礼:<选中物品>]/[离开]`(↑↓ 选,J 确认);`handle_action`:move→移光标,farm_use→执行选项。**本 Task 先只做
  [聊天](出下一句台词轮换)与 [离开]**(送礼选项占位/禁用,Task5 接)。文案走 i18n key。

- [ ] **Step 2:** `farm_state.gd`:`open_dialogue(npc_def)`:建 dialogue_panel、bind、push 到 UI 栈(`_active_ui="dialogue"`,
  锁 player)。`route_action` 已通用转发。

- [ ] **Step 3:** 交互键:小镇/农舍 `_on_use()`:找与 player 相邻(facing_cell 或距离≤1格)的 `_npcs` 最近者 → `Farm.open_dialogue(def)`。
  农田 `_on_use` 仍是用工具。若需独立交互键而非复用 J,加 `interact` 输入动作;否则复用 farm_use(J)按区域语义分派(推荐复用)。

- [ ] **Step 4:** import + FARM_SMOKE PASS(dialogue 面板 build/push/pop 无错)+ run_all FAILS=0;**F5**:小镇走到 NPC 前按 J →
  对话框出台词,聊天出下一句,离开关闭。

- [ ] **Step 5:** commit `feat(farm-sim P3): NPC 对话面板 + 相邻交互（KitUiStack）`。

---

### Task 5: 送礼 + 好感度

**Files:** Create `relationship.gd`、`test/test_relationship.gd`;Modify `farm_state.gd`(relationships + gift/chat/friendship
API + 存档)、`dialogue_panel.gd`(启用 [送礼])、`hud.gd`(可选:显示当前选中的"手持物品")。

**Interfaces:**
- Produces: `Relationship`(纯逻辑:`gift_delta(def, item)->int` 按 loved/liked/disliked 判;`level_of(points)->int` 分档);
  `Farm.gift_to(npc_id, item_id)->{reaction,delta,unlocked}`、`chat_with`、`friendship`、`friendship_level`;
  bus `npc:gift_given`/`npc:friendship_changed`(命名空间 npc:)。

- [ ] **Step 1:** 写 `relationship.gd`(extends RefCounted,静态/实例纯逻辑):`static func gift_delta(npc_def, item_id) -> int`
  (loved→+50、liked→+20、disliked→−30、其余→+5);`static func level_of(points) -> int`(points/100)。零依赖,可 headless 测。

- [ ] **Step 2:** `farm_state.gd`:`var relationships := {}`;`gift_to(npc_id, item_id)`:查 def→`Relationship.gift_delta`→
  `relationships[npc_id] += delta`、扣背包 1 个该物品、广播 `npc:gift_given`+`npc:friendship_changed`、返回 `{reaction,delta}`
  (reaction 按 delta 正负取 i18n 文案);当日对同一 NPC 只接一次礼(记 `_gifted_today` set,`clock:day_changed` 清空)。
  `chat_with(npc_id)`:当日首聊 +5、记 `_chatted_today`。`friendship/friendship_level` getter。relationships 随存档
  to_dict/from_dict(StringName 键归一)。

- [ ] **Step 3:** `dialogue_panel.gd` 启用 [送礼:<选中物品>]:选中 → `Farm.gift_to(npc_id, held_item)`,出 reaction 台词 +
  刷新。"选中物品"起步复用一个背包物品指针(HUD 已有 selected_crop 是种子;送礼更想送产物——引入 `Farm.held_item` +
  循环选择,或对话里列可送物品选。**最简**:送"当前选中种子对应的产物"或让对话面板列背包可送项选一个。计划取:对话面板内
  列背包非种子物品(produce)让玩家 ↑↓ 选一个送)。

- [ ] **Step 4:** 写 `test/test_relationship.gd`:gift_delta 各偏好档、level_of 分档、送礼累加 + 扣物、当日防刷、存档往返
  (relationships to_dict→JSON→from_dict 键归一)。加进按需单跑(不进 run_all $tests)。

- [ ] **Step 5:** import + test_relationship ALL PASS + FARM_SMOKE PASS(送礼加好感 + 存读档复原 relationships)+ run_all
  FAILS=0;**F5**:小镇送 NPC 喜欢的物品 → 好感涨、出反应台词;存读档好感保留;当天重复送被挡。

- [ ] **Step 6:** commit `feat(farm-sim P3): 送礼 + 好感度（relationship 纯逻辑 + npc: 事件 + 随存档 + 当日防刷）`。

---

### Task 6: 好感解锁

**Files:** Modify `farm_state.gd`(unlock 判定 + 发放 + 存档)、新增解锁作物数据 `data/crops/star_fruit.tres` +
`data/items/star_seed.tres`+`star_fruit.tres`。

- [ ] **Step 1:** 建解锁作物:`star_fruit.tres`(高价值,如 grow_days=4、sell 高)、`star_seed.tres`(seed,buy_price=0
  不可买)、`star_fruit.tres`(produce,sell 高)。作为好感奖励专属。

- [ ] **Step 2:** `farm_state.gd`:`gift_to`/`chat_with` 后 `_check_unlock(npc_id)`:好感 ≥ def.unlock_at 且
  `not unlocked.has(npc_id)` 且 def.unlock_item 非空 → `bag.add(unlock_item,1)` + `unlocked[npc_id]=true` + 广播
  `npc:unlocked{npc_id,item}`(幂等)。`unlocked` 随存档 to_dict/from_dict。`gift_to` 返回值加 `unlocked:bool`。

- [ ] **Step 3:** dialogue_panel 解锁时出一句"给你星之种子"提示(读 `npc:unlocked` 或 gift_to 返回)。

- [ ] **Step 4:** import + FARM_SMOKE PASS(送礼刷到阈值 → unlock 发放种子 + 幂等再送不重发 + unlocked 存读档)+ run_all
  FAILS=0;**F5**:反复送礼把某 NPC 好感刷过阈值 → 收到星之种子(背包 I 可见),能种、能收、能卖;存读档解锁不丢、不重发。

- [ ] **Step 5:** commit `feat(farm-sim P3): 好感解锁奖励（阈值发放特殊种子，幂等 + 随存档）`。

---

### 收尾(全部 Task 后)

- [ ] `world.gd`/`farm_state.gd` 顶部 docstring 更新(多区域 + NPC + 操作)。
- [ ] spec `2026-07-14-farm-sim-game-design.md` 的 **P3 checklist** 逐项勾 `[x]` + 标题 ✅。
- [ ] 更新 memory `farm-sim-trio-plan.md` / `MEMORY.md`:记 P3 完成 + Farm autoload 架构。
- [ ] F5 总验收:三区走动切场景、农田状态跨区留存、NPC 对话/送礼/好感/解锁、存读档全量。
- [ ] 提示需求方在 `example/farm-sim` 自行 push。

## Self-Review 记录

- **Spec 覆盖**:spec §2 Farm autoload→Task1;§3 多区域→Task2;§4 NPC→Task3;§5 对话/送礼/好感→Task4/5;§6 解锁→Task6;
  §7 测试(test_relationship + FARM_SMOKE 迁移)贯穿。无遗漏。
- **类型一致**:Farm API(start/use_tool_on/sleep/cycle_seed/buy_water_upgrade/toggle_ui/route_action/go_to/gift_to/
  chat_with/friendship/save_game/load_game/i18n_cycle_locale)在各 Task 引用一致;`Relationship.gift_delta/level_of`、
  `NpcDef` 字段、`Farm.npcs_in_area` 一致。
- **风险点**:Task1 是最大重构——策略是"纯搬迁 + 玩法零变化",靠 FARM_SMOKE 迁移后仍 PASS + F5 回归守护;autoload 惰性
  保证 run_all 不受污染。Task2 真实场景切换难 headless 验,靠 F5;smoke 只验 Farm 区域状态字段与农田状态留存。
- **注意**:`use_tool_on` 去掉了对 `_player` 的依赖(cell 由区域传入),这是把 model 从 view 剥离的关键;player 位置/朝向
  存档由区域场景写入 Farm。送礼"选中物品"落到对话面板内列 produce 选择(Task5 Step3),避免与 HUD 种子选择语义打架。
