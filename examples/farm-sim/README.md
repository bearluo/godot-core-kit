# 农场经营 MVP 骨架(farm-sim)

用一条确定性剧情把多个子系统串起来做 **dogfood 验证**:载数据表 → 发种子 → 播种 → 逐日推进作物生长 → 收获入背包 → **存档往返** → **背包 UI 面板入栈**。整段是**框架消费者视角**——只调 `CoreKit.*` 与两个 `class_name` 类库(`KitInventory`/`KitDataRegistry`),不碰 kit 内部,专门用来暴露多子系统协作时的缺口。

验证覆盖的子系统:

| 子系统 | 在本例中的角色 |
|---|---|
| `KitDataRegistry`(off-facade) | 一个 registry 存 **crop + item 两种类型**:`data/crops/` 作物表、`data/items/` 物品表,`load_dir` 载入、`get_def` 查 |
| `KitInventory`(off-facade) | 玩家背包:发种子、播种扣种子、收获入库;单格堆叠上限由 item 表驱动 |
| `CoreKit.clock` + `CoreKit.bus` | 逐日推进,每天广播 `clock:day_changed`,作物订阅后生长(跨子系统解耦) |
| `CoreKit.saves` | 存档:`clock.to_dict()`+`bag.to_dict()` 存槽,`load`+`from_dict` 复原(经 JSON 往返) |
| `KitUiStack`(off-facade) | 背包面板 `push` 进 UI 栈,面板内容反映背包 |

## 文件

| 文件 | 作用 |
|---|---|
| `crop_def.gd` + `data/crops/{turnip,parsnip}.tres` | 作物定义 `Resource`(id/天数/种子/产物/数量) |
| `item_def.gd` + `data/items/*.tres` | 物品定义 `Resource`(id/展示名/max_stack/类别);种子 + 产物各 2 份 |
| `crop.gd` | 一株已播种作物(Node)。订阅 `CoreKit.clock.EV_DAY_CHANGED`,每天长 1 格 |
| `farm.gd` | 农田 = 集成粘合层。持有注入的 registry+背包,负责 `plant`/`harvest_all` |
| `backpack_panel.gd` | 极简背包 UI 面板(Control):列出背包物品×总数,供 `KitUiStack.push` |
| `game.gd` / `game.tscn` | 驱动:8 段剧情串起全部验证。整条故事的入口 |

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
[Farm] 载入 2 作物 + 4 物品,registry 类型: [crop, item]
[Bag] 初始种子: turnip_seed=3 parsnip_seed=3
[Farm] 播种 白萝卜 (消耗 1 白萝卜种子)
[Farm] 播种 防风草 (消耗 1 防风草种子)
[Bag] 播种后种子: turnip_seed=2 parsnip_seed=2
[Clock] 开局 y1 spring d1 06:00
[Crop:白萝卜] 第 2 天 生长 1/2
[Crop:防风草] 第 2 天 生长 1/4
[Crop:白萝卜] 第 3 天 生长 2/2  已成熟
[Crop:防风草] 第 3 天 生长 2/4
[Crop:防风草] 第 4 天 生长 3/4
[Crop:防风草] 第 5 天 生长 4/4  已成熟
[Farm] 收获 白萝卜 x3 → 背包(单格上限 99)
[Farm] 收获 防风草 x2 → 背包(单格上限 1)
[Bag] 收获后: turnip=3 parsnip=2,已用格数=5
[Save] 已存档 'farm_demo' @ y1 spring d5 06:00 turnip=3
[Save] 读档前(已变化): y1 spring d10 06:00 turnip=13
[Save] 读档后(已复原): y1 spring d5 06:00 turnip=3
[UI] 背包面板入栈,depth=1
[UI]   防风草 x2
[UI]   防风草种子 x2
[UI]   白萝卜 x3
[UI]   白萝卜种子 x2
```

逐段对应验证点:
1. `载入 2 作物 + 4 物品 … [crop, item]` —— 一个 `KitDataRegistry` **同时承载两种类型**,`load_dir` 分别扫 `data/crops`、`data/items`。
2. `播种 … 消耗种子` —— `plant` 查 `crop` 定义拿 `seed_item`、`KitInventory.remove` 扣种子;展示名来自 `item` 表(跨表查询)。
3. `[Crop:*] 第 N 天 生长 x/y` —— 每次 `CoreKit.clock.advance_day()` 经 `CoreKit.bus` 广播 `clock:day_changed`,作物**只认事件、不认时钟**地长一格。
4. `收获 … 单格上限 N` / `已用格数=5` —— 上限取自 `item` 表:防风草 `max_stack=1`,收 2 株 → 占 2 格,证明**数据驱动堆叠**生效。
5. `[Save] 存 → 变 → 复原` —— `clock+bag` `to_dict` 存进 `CoreKit.saves`,推进 5 天+加 10 白萝卜后 `load`+`from_dict` 完整复原到存档点(d5/turnip=3),证明 **saves 接入 + to_dict/from_dict 扛得住 JSON int→float 往返**。
6. `[UI] 背包面板` —— `KitUiStack.push` 一个反映背包内容的 Control 面板,`depth=1`,内容与背包一致。

## 要点

- **消费者视角、零 kit 侵入**:整例不 `preload` 任何子系统脚本,`registry`/`bag` 全由驱动方 `farm.bind(...)` 注入——这正是"用 core-kit 做游戏"的推荐姿势。
- **跨子系统靠 bus 解耦**:作物不持有时钟引用,只订阅事件名常量 `CoreKit.clock.EV_DAY_CHANGED`(命名约定 `namespace:event`,见 [`event-bus.md`](../../addons/godot-core-kit/docs/core/event-bus.md))。换任何东西驱动"过一天"都不用改作物。
- **payload = 快照**:`clock:*` 事件的 payload 是 `clock.snapshot()` 的 `Dictionary`(`year/season_index/season_name/day/hour/minute`),作物直接读 `snap["day"]`。
- **Node 监听者主动清理**:`Crop._exit_tree` 调 `CoreKit.bus.unsubscribe_all(self)`,收获 `free` 时不留悬空订阅。
- **dogfood 记到的两条坑**(留作后续可选的 kit 改进,均属"发现即价值"):
  1. **`StringName` 数组的原生 `.sort()` 按指针地址排、非字典序**(Godot 行为)。想按字母序列出 `registry.ids()/types()` 或背包物品,必须 `sort_custom(func(x,y): return String(x) < String(y))`(见 `game.gd._sorted` / `backpack_panel._aggregate`)。kit 侧可考虑让 `ids()/types()` 提供 String 有序变体或在文档警示。
  2. **`KitInventory` 没有"列出全部物品"的聚合方法**:背包 UI 想按 id 汇总只能手动遍历 `capacity()`×`slot(i)`(见 `backpack_panel._aggregate`)。kit 侧可考虑补 `totals() -> Dictionary` / `entries()` 便利方法。
  > 按分支分流规矩,这两条若要修,应剥出来走 kit 正常 SDD → run_all 绿 → ff-merge 进 main(升版),再把本分支 rebase 上去;示例本身留在 `example/farm-sim` 不合 main。
- **无类型返回值 + `:=` 会 parse error**:`var n := registry.load_dir(...)` 因 `registry` 无类型、编译期推不出返回类型而报错,退回普通 `var n = ...`。
- **这是骨架不是成品**:没有网格地块、工具体力、动物 NPC、经济/任务——那些是"游戏本体",不属于 kit。本例只验证这些地基能不能顺畅拼在一起。
- 子系统完整 API 见 [`game-clock.md`](../../addons/godot-core-kit/docs/systems/game-clock.md) / [`kit-inventory.md`](../../addons/godot-core-kit/docs/inventory/kit-inventory.md) / [`kit-data-registry.md`](../../addons/godot-core-kit/docs/data/kit-data-registry.md) / [`save-manager.md`](../../addons/godot-core-kit/docs/systems/save-manager.md) / [`ui-stack.md`](../../addons/godot-core-kit/docs/ui/ui-stack.md)。
