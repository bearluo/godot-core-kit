# 多区域世界 + NPC 社交

## 多区域

三个区域场景,`J`/走门切换,全部继承 `scenes/area_base.gd`:

| 区域 | 场景 | 内容 |
|---|---|---|
| 农田 | `scenes/world.tscn`(主) | 10×8 网格 + 天气 + 通往农舍/小镇的门 |
| 农舍 | `scenes/house_area.tscn` | 床(睡觉)+ 回农田门;傍晚奶奶在此 |
| 小镇 | `scenes/town_area.tscn` | 商店牌(开店)+ 回农田门;NPC 白天在此 |

### `area_base.gd` 基类

子类只覆盖 5 个虚方法:`_area_name()` / `_default_spawn()` / `_build_area()` / `_after_player()` / `_on_use()`。基类统一:调 `Farm.start()`、设 `Farm.current_area`、在 `pending_spawn` 造 player、绑定、摆放本区 NPC、路由输入(面板开关 / `farm_use` / 睡觉 / 切种子)。

### 门 `scenes/door.gd`

玩家是无碰撞体的占位角色,故门不用 `Area2D` 物理,而是**位置轮询**:`_process` 每帧读 `Farm.current_player()` 位置,进入门矩形 → `Farm.go_to(path, spawn, transition)`。触发一次即锁,切场景后随旧场景释放。

### 切换 = 整场景替换 + 转场

`Farm.go_to` = 写 `pending_spawn` + `await CoreKit.scenes.change_scene(path, transition)`。农田↔农舍用 **FADE**、农田↔小镇用 **SLIDE**(dogfood 两种 `KitTransition`,带 `TRANS_CUBIC` 缓动)。农田状态全在 `Farm.grid`,切区不丢。跨区读档用**延迟导航**(`call_deferred("_resume_saved_area")`)避免在菜单面板 `_activate` 内自由旧节点。

## NPC(数据驱动)

`defs/npc_def.gd` + `data/npcs/*.tres`(商人阿福、奶奶),进 `KitDataRegistry` 作第 5 类型。字段:`id` / `display_name` / `home_area` / `schedule` / `dialogue` / `gift_loved`·`gift_liked`·`gift_disliked` / `unlock_at` / `unlock_item`。

**日程**:`schedule = [{after_hour, area, x, y}]`,按 `hour` 取最后满足项决定站位(轻量,不做寻路)。`Farm.npcs_in_area(area, hour)` + `area_base._spawn_area_npcs` 各区 `_ready` 自动摆放。例:奶奶白天在镇、`after_hour:18` 回农舍。

> 正常游玩钟点恒 6:00,故两 NPC 白天都在镇;傍晚日程由 smoke 用不同 hour 验证。

## 对话 / 送礼 / 好感 / 解锁

相邻按 `J` → `Farm.open_dialogue(def)` 开对话面板 `ui/dialogue_panel.gd`(`KitUiStack` 模态,小状态机 menu / gift 子菜单):

- **聊天**:轮换台词,当日首次 +5 好感。
- **送礼**:列背包 produce 选送,`Farm.gift_to(npc, item)` 按喜好加减好感,当日防刷(订阅 `clock:day_changed` 跨天清)。
- 广播 `npc:` 命名空间事件(`gift_given` / `friendship_changed` / `unlocked`)。

### 好感数值 `systems/relationship.gd`

纯逻辑、零依赖、headless 可测(`test/test_relationship.gd`):

| 常量 | 值 |
|---|---|
| 送爱物 `GIFT_LOVED` | +50 |
| 送喜欢 `GIFT_LIKED` | +20 |
| 送普通 `GIFT_NEUTRAL` | +5 |
| 送讨厌 `GIFT_DISLIKED` | −30 |
| 每级点数 `POINTS_PER_LEVEL` | 100 |

`gift_delta(npc_def, item)` / `level_of(points)` / `reaction_of(delta)`。

### 解锁

好感达 `unlock_at`(商人 100)→ `Farm._check_unlock` 幂等发放 `unlock_item`(**星之种子** star_seed,专属高价值作物 star_fruit,见 [economy.md](economy.md))。`relationships` / `unlocked` 随存档(StringName 键归一)。
