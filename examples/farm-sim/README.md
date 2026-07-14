# 农场经营 MVP 骨架(farm-sim)

用一条确定性剧情把多个子系统串起来做 **dogfood 验证**:载数据表 → 开店买种子 → 播种 → 逐日推进作物生长 → 收获 → 卖产物换钱 → **存档往返** → **背包 UI 面板入栈** → **任务结算**。整段是**框架消费者视角**——只调 `CoreKit.*` 与两个 `class_name` 类库(`KitInventory`/`KitDataRegistry`),不碰 kit 内部,专门用来暴露多子系统协作时的缺口。

验证覆盖的子系统:

| 子系统 | 在本例中的角色 |
|---|---|
| `KitDataRegistry`(off-facade) | 一个 registry 存 **crop + item + quest 三种类型**:作物/物品(含价格)/任务表,`load_dir` 载入、`get_def` 查 |
| `KitInventory`(off-facade) | 玩家背包:买入/收获入库、播种/出售扣除;单格堆叠上限由 item 表驱动 |
| `CoreKit.clock` + `CoreKit.bus` | 逐日推进,每天广播 `clock:day_changed`,作物/任务订阅后各自反应(跨子系统解耦) |
| `CoreKit.bus`(游戏侧命名空间) | 商店广播 **`shop:bought`/`shop:sold`**、任务广播 **`quest:completed`**;游戏侧**既发布又订阅** |
| `CoreKit.bus`(多来源聚合) | 任务日志**一个订阅方汇聚 `clock:day_changed`+`shop:sold` 两个来源**推进目标 |
| `CoreKit.saves` | 存档:`clock`+`bag`+金币+任务进度 存槽,`load`+`from_dict` 复原(经 JSON 往返) |
| `KitUiStack`(off-facade) | 背包面板 `push` 进 UI 栈,面板内容反映背包 |
| `KitStateMachine`(off-facade) | 每株作物一台状态机建模生命周期 **Growing → Mature**(教科书用例) |

## 文件

| 文件 | 作用 |
|---|---|
| `crop_def.gd` + `data/crops/{turnip,parsnip}.tres` | 作物定义 `Resource`(id/天数/种子/产物/数量) |
| `item_def.gd` + `data/items/*.tres` | 物品定义 `Resource`(id/展示名/max_stack/类别/买价/卖价) |
| `quest_def.gd` + `data/quests/*.tres` | 任务定义 `Resource`(id/标题/条件类型/目标值/限定物品) |
| `crop.gd` | 一株已播种作物(Node)。内建 `KitStateMachine`(Growing→Mature),订阅 `clock:day_changed` 推进生长 |
| `farm.gd` | 农田 = 集成粘合层。持有注入的 registry+背包,负责 `plant`/`harvest_all` |
| `shop.gd` | 商店 + 钱包(游戏侧经济)。`buy`/`sell` 按 item 表价格,交易广播 `shop:*` 事件 |
| `quest_log.gd` | 任务日志。订阅 `clock:`+`shop:` 事件推进目标,达标广播 `quest:completed`,进度可存档 |
| `backpack_panel.gd` | 极简背包 UI 面板(Control):列出背包物品×总数,供 `KitUiStack.push` |
| `game.gd` / `game.tscn` | 驱动:10 段剧情串起全部验证。整条故事的入口 |

## 跑法

- **编辑器**:把 `game.tscn` 设为主场景运行,看输出面板。
- **Headless**:
  ```
  godot --headless --path . res://examples/farm-sim/game.tscn --quit-after 120
  ```
  (首次需先 `godot --headless --path . --import` 生成 `KitInventory`/`KitDataRegistry`/`KitUiStack` 的 `class_name` 缓存。)

## 预期输出

(以下略去每行的 `[时间][INFO]` 日志前缀)

```
[Farm] 载入 2 作物 + 4 物品 + 3 任务,registry 类型: [crop, item, quest]
[Shop] 开局金币 200
[Shop] 买入 防风草种子 x3 花 60,余额 140
[Shop] 买入 白萝卜种子 x3 花 30,余额 110
[Farm] 播种 白萝卜 (消耗 1 白萝卜种子)
[Farm] 播种 防风草 (消耗 1 防风草种子)
[Clock] 开局 y1 spring d1 06:00
[Crop:白萝卜] 第 2 天 生长 1/2
[Crop:防风草] 第 2 天 生长 1/4
[Crop:白萝卜] 第 3 天 生长 2/2
[Crop:白萝卜] 状态 Growing→Mature 已成熟
[Crop:防风草] 第 3 天 生长 2/4
[Crop:防风草] 第 4 天 生长 3/4
[Quest] 完成:坚持务农:撑到第 5 天
[Crop:防风草] 第 5 天 生长 4/4
[Crop:防风草] 状态 Growing→Mature 已成熟
[Farm] 收获 白萝卜 x3 → 背包(单格上限 99)
[Farm] 收获 防风草 x2 → 背包(单格上限 1)
[Quest] 完成:首笔收入:累计赚到 100 金币
[Quest] 完成:萝卜大户:卖出 3 个白萝卜
[Shop] 卖出 白萝卜 x3 得 105,余额 215
[Shop] 结算:金币 215,累计收入 105
[Save] 已存档 'farm_demo' @ y1 spring d5 06:00 gold=215 完成任务=3
[Save] 读档前(已变化): y1 spring d10 06:00 gold=0 完成任务=0
[Save] 读档后(已复原): y1 spring d5 06:00 gold=215 完成任务=3
[UI] 背包面板入栈,depth=1
[UI]   防风草 x2
[UI]   防风草种子 x2
[UI]   白萝卜种子 x2
[Quest] 结算(3/3 完成):
[Quest]   ✓ 105/100 首笔收入:累计赚到 100 金币
[Quest]   ✓ 5/5 坚持务农:撑到第 5 天
[Quest]   ✓ 3/3 萝卜大户:卖出 3 个白萝卜
```

逐段对应验证点:
1. `载入 2 作物 + 4 物品 + 3 任务 … [crop, item, quest]` —— 一个 `KitDataRegistry` **同时承载三种类型**,`load_dir` 分别扫三个子目录。
2. `[Shop] 买种子` —— 开局 200 金币,`shop.buy` 按 item 表 `buy_price` 扣钱入包,广播 `shop:bought`;价格数据驱动。
3. `[Crop:*] 生长 / 状态 Growing→Mature` —— `advance_day()` 经 bus 广播 `clock:day_changed`,作物**只认事件**地长一格;到 grow_days 由内建 `KitStateMachine` 转到 Mature 态(`state_changed` 信号打出转移行),`is_ready()` 即查该态。
4. `[Quest] 完成:坚持务农`(第 5 天)—— 任务日志订阅 `clock:day_changed`,`reach_day` 目标在 d5 达标。
5. `[Quest] 完成:首笔收入 / 萝卜大户`(卖出时)—— 任务日志**同时**订阅 `shop:sold`,`earn_gold`(累计 105≥100)与 `sell_count`(卖 3 白萝卜≥3)达标 → 证明 **bus 作多来源事件聚合器**(一个订阅方汇聚 clock:+shop: 两来源)。
6. `[Save] 存 → 变 → 复原` —— `clock+bag+金币+任务进度` 存进 `CoreKit.saves`,推进 5 天+清空钱包+遗忘任务后 `load`+`from_dict` 完整复原(d5/gold=215/完成任务=3),证明 **saves 接入 + to_dict/from_dict 扛得住 JSON int→float 往返**。
7. `[UI] 背包面板` —— `KitUiStack.push` 一个反映背包内容的 Control 面板,`depth=1`。
8. `[Quest] 结算 3/3` —— 三条目标各由不同来源事件在整局中聚合达成。

## 要点

- **消费者视角、零 kit 侵入**:整例不 `preload` 任何子系统脚本,`registry`/`bag` 全由驱动方 `bind(...)` 注入——这正是"用 core-kit 做游戏"的推荐姿势。
- **跨子系统靠 bus 解耦**:作物/任务都不持有时钟或商店引用,只订阅事件名常量(命名约定 `namespace:event`,见 [`event-bus.md`](../../addons/godot-core-kit/docs/core/event-bus.md))。
- **游戏可定义自己的 bus 命名空间**:`shop:`(shop.gd)、`quest:`(quest_log.gd)与 kit 的 `clock:` 三者并存互不干扰——命名约定不止约束 kit,游戏侧照办即可解耦自己的系统。
- **bus 是多来源聚合器**:`quest_log` 一个订阅方同时消费 `clock:day_changed` 与 `shop:sold`,把不同系统的事件汇成任务进度——这是"没有引用关系的广播"最典型的用法。
- **每实体状态机用 `KitStateMachine`**:`crop.gd` 在代码里建一台状态机(`Growing`/`Mature` 用内部类作 KitState,免加文件),相位切换交给 `transition_to`、`is_ready()` 查 `current_state.name`。构造有次序要求:**所有 KitState 子节点 add_child、`initial_state` 设好、`state_changed` 连好,都要在 `add_child(machine)`(入树触发机器 `_ready`)之前完成**。生长计数留在 crop、相位交给 FSM 是常见分工(FSM 建模离散相位/行为,计时器留实体)。
- **持久化边界**:`shop.gold` / 任务进度是游戏侧状态(kit 无货币/任务子系统),随存档 `to_dict/from_dict` 一起走——展示"什么归 kit、什么归游戏"。
- **Node 监听者主动清理**:`Crop`/`QuestLog` 在 `_exit_tree` 调 `CoreKit.bus.unsubscribe_all(self)`,不留悬空订阅。
- **dogfood 记到的四条坑,其中三条已反哺进 kit(v0.18.0)**——这正是"在 examples 里做游戏验证框架"的产出闭环:
  1. **`StringName` 数组的原生 `.sort()` 按指针地址排、非字典序**(Godot 行为)。→ **已修**:`KitDataRegistry.ids/types` 加 `sorted` 参数(`ids(&"crop", true)` 即字母序);本例已改用(见 `game.gd` / `quest_log._ready`)。
  2. **`KitInventory` 没有"列出全部物品"的聚合方法**,背包 UI 只能手动遍历 `capacity()`×`slot(i)`。→ **已修**:新增 `KitInventory.totals() -> {id:总数}`;本例已改用(见 `backpack_panel._aggregate`)。
  3. **`StringName` 作 Dictionary 键经存档(JSON)会退化为 `String`**:自定义 `to_dict/from_dict` 若用 StringName 键存 dict,`from_dict` 必须把键归一回 StringName(见 `quest_log.from_dict`),否则后续用 StringName 索引会 miss。→ 这是**游戏侧惯例**,不是 kit 缺陷(kit 各子系统 `from_dict` 已规避,如 KitInventory 存 `String(id)`、读 `StringName(id)`),照做即可。
  4. **`KitStateMachine` 没有"当前态判定"便利方法**,查当前态要 `sm.current_state != null and String(sm.current_state.name) == "X"`。→ **已修**:新增 `state_name() -> String` / `is_in(query) -> bool`(null 安全);本例已改用(见 `crop.is_ready`)。
  > 修复流程遵分支分流规矩:三条 kit 改进剥出来走 kit 正常 SDD → run_all 绿 → **ff-merge 进 main(0.17.0→0.18.0)**,再把本分支 rebase 到新 main、改用新 API。示例本身仍留在 `example/farm-sim` 不合 main。
- **无类型返回值 + `:=` 会 parse error**:`var n := registry.load_dir(...)` 因 `registry` 无类型、编译期推不出返回类型而报错,退回普通 `var n = ...`。
- **这是骨架不是成品**:没有网格地块、工具体力、动物 NPC、对话——那些是"游戏本体",不属于 kit。本例只验证这些地基能不能顺畅拼在一起。
- 子系统完整 API 见 [`game-clock.md`](../../addons/godot-core-kit/docs/systems/game-clock.md) / [`kit-inventory.md`](../../addons/godot-core-kit/docs/inventory/kit-inventory.md) / [`kit-data-registry.md`](../../addons/godot-core-kit/docs/data/kit-data-registry.md) / [`save-manager.md`](../../addons/godot-core-kit/docs/systems/save-manager.md) / [`ui-stack.md`](../../addons/godot-core-kit/docs/ui/ui-stack.md) / [`state-machine.md`](../../addons/godot-core-kit/docs/state-machine.md)。
