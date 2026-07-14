# 农场经营 MVP 骨架(farm-sim)

用一条确定性剧情把多个子系统串起来做 **dogfood 验证**:载数据表 → 开店买种子 → 播种 → 逐日推进作物生长 → 收获 → 卖产物换钱 → **存档往返** → **背包 UI 面板入栈**。整段是**框架消费者视角**——只调 `CoreKit.*` 与两个 `class_name` 类库(`KitInventory`/`KitDataRegistry`),不碰 kit 内部,专门用来暴露多子系统协作时的缺口。

验证覆盖的子系统:

| 子系统 | 在本例中的角色 |
|---|---|
| `KitDataRegistry`(off-facade) | 一个 registry 存 **crop + item 两种类型**:作物表、物品表(含价格),`load_dir` 载入、`get_def` 查 |
| `KitInventory`(off-facade) | 玩家背包:买入/收获入库、播种/出售扣除;单格堆叠上限由 item 表驱动 |
| `CoreKit.clock` + `CoreKit.bus` | 逐日推进,每天广播 `clock:day_changed`,作物订阅后生长(跨子系统解耦) |
| `CoreKit.bus`(游戏侧命名空间) | 商店交易广播 **`shop:bought`/`shop:sold`**;游戏侧**既发布又订阅**,验证命名约定对游戏代码同样适用 |
| `CoreKit.saves` | 存档:`clock.to_dict()`+`bag.to_dict()`+金币 存槽,`load`+`from_dict` 复原(经 JSON 往返) |
| `KitUiStack`(off-facade) | 背包面板 `push` 进 UI 栈,面板内容反映背包 |

## 文件

| 文件 | 作用 |
|---|---|
| `crop_def.gd` + `data/crops/{turnip,parsnip}.tres` | 作物定义 `Resource`(id/天数/种子/产物/数量) |
| `item_def.gd` + `data/items/*.tres` | 物品定义 `Resource`(id/展示名/max_stack/类别/买价/卖价);种子 + 产物各 2 份 |
| `crop.gd` | 一株已播种作物(Node)。订阅 `CoreKit.clock.EV_DAY_CHANGED`,每天长 1 格 |
| `farm.gd` | 农田 = 集成粘合层。持有注入的 registry+背包,负责 `plant`/`harvest_all` |
| `shop.gd` | 商店 + 钱包(游戏侧经济)。`buy`/`sell` 按 item 表价格,交易广播 `shop:*` 事件 |
| `backpack_panel.gd` | 极简背包 UI 面板(Control):列出背包物品×总数,供 `KitUiStack.push` |
| `game.gd` / `game.tscn` | 驱动:9 段剧情串起全部验证。整条故事的入口 |

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
[Shop] 开局金币 200
[Shop] 买入 防风草种子 x3 花 60,余额 140
[Shop] 买入 白萝卜种子 x3 花 30,余额 110
[Farm] 播种 白萝卜 (消耗 1 白萝卜种子)
[Farm] 播种 防风草 (消耗 1 防风草种子)
[Clock] 开局 y1 spring d1 06:00
[Crop:白萝卜] 第 2 天 生长 1/2
[Crop:防风草] 第 2 天 生长 1/4
[Crop:白萝卜] 第 3 天 生长 2/2  已成熟
[Crop:防风草] 第 3 天 生长 2/4
[Crop:防风草] 第 4 天 生长 3/4
[Crop:防风草] 第 5 天 生长 4/4  已成熟
[Farm] 收获 白萝卜 x3 → 背包(单格上限 99)
[Farm] 收获 防风草 x2 → 背包(单格上限 1)
[Shop] 卖出 白萝卜 x3 得 105,余额 215
[Shop] 结算:金币 215,累计收入 105
[Save] 已存档 'farm_demo' @ y1 spring d5 06:00 gold=215
[Save] 读档前(已变化): y1 spring d10 06:00 gold=0
[Save] 读档后(已复原): y1 spring d5 06:00 gold=215
[UI] 背包面板入栈,depth=1
[UI]   防风草 x2
[UI]   防风草种子 x2
[UI]   白萝卜种子 x2
```

逐段对应验证点:
1. `载入 2 作物 + 4 物品 … [crop, item]` —— 一个 `KitDataRegistry` **同时承载两种类型**,`load_dir` 分别扫 `data/crops`、`data/items`。
2. `[Shop] 买种子` —— 开局 200 金币,`shop.buy` 按 item 表 `buy_price` 扣钱入包,广播 `shop:bought`;价格数据驱动。
3. `[Crop:*] 第 N 天 生长 x/y` —— 每次 `CoreKit.clock.advance_day()` 经 `CoreKit.bus` 广播 `clock:day_changed`,作物**只认事件、不认时钟**地长一格。
4. `收获 … 单格上限 N` —— 上限取自 item 表:防风草 `max_stack=1`,收 2 株 → 占 2 格(UI 里仍聚合成"防风草 x2"),证明**数据驱动堆叠**。
5. `[Shop] 卖 … 累计收入 105` —— `shop.sell` 按 `sell_price` 入账、广播 `shop:sold`;`game.gd` **订阅了自家的 `shop:sold`** 累计总收入,证明 bus 命名约定 `namespace:event` 在**游戏侧作为发布方+订阅方**同样成立(`shop:` 是游戏自有命名空间)。
6. `[Save] 存 → 变 → 复原` —— `clock+bag+金币` 存进 `CoreKit.saves`,推进 5 天+清空钱包后 `load`+`from_dict` 完整复原到存档点(d5/gold=215),证明 **saves 接入 + to_dict/from_dict 扛得住 JSON int→float 往返**。
7. `[UI] 背包面板` —— `KitUiStack.push` 一个反映背包内容的 Control 面板(白萝卜已卖出,留防风草+种子),`depth=1`。

## 要点

- **消费者视角、零 kit 侵入**:整例不 `preload` 任何子系统脚本,`registry`/`bag` 全由驱动方 `bind(...)` 注入——这正是"用 core-kit 做游戏"的推荐姿势。
- **跨子系统靠 bus 解耦**:作物不持有时钟引用,只订阅事件名常量 `CoreKit.clock.EV_DAY_CHANGED`(命名约定 `namespace:event`,见 [`event-bus.md`](../../addons/godot-core-kit/docs/core/event-bus.md))。换任何东西驱动"过一天"都不用改作物。
- **游戏可定义自己的 bus 命名空间**:`shop.gd` 用 `shop:bought`/`shop:sold` 常量发布,与 kit 的 `clock:` 并存互不干扰——命名约定不止约束 kit,游戏侧照办即可解耦自己的系统。
- **payload = 快照/结构**:`clock:*` payload 是 `clock.snapshot()`;`shop:*` payload 是 `{item,qty,cost/earn,gold}` 单 Dictionary(遵约定"单 Variant payload")。
- **Node 监听者主动清理**:`Crop._exit_tree` 调 `CoreKit.bus.unsubscribe_all(self)`,收获 `free` 时不留悬空订阅。
- **钱包是游戏侧状态**:kit 无货币子系统,`shop.gold` 是游戏自有 int,随存档 `to_dict/from_dict` 一起走——展示"什么归 kit、什么归游戏"的边界。
- **dogfood 记到的两条坑**(留作后续可选的 kit 改进,均属"发现即价值"):
  1. **`StringName` 数组的原生 `.sort()` 按指针地址排、非字典序**(Godot 行为)。想按字母序列出 `registry.ids()/types()` 或背包物品,必须 `sort_custom(func(x,y): return String(x) < String(y))`(见 `game.gd._sorted` / `backpack_panel._aggregate`)。kit 侧可考虑让 `ids()/types()` 提供 String 有序变体或在文档警示。
  2. **`KitInventory` 没有"列出全部物品"的聚合方法**:背包 UI 想按 id 汇总只能手动遍历 `capacity()`×`slot(i)`(见 `backpack_panel._aggregate`)。kit 侧可考虑补 `totals() -> Dictionary` / `entries()` 便利方法。
  > 按分支分流规矩,这两条若要修,应剥出来走 kit 正常 SDD → run_all 绿 → ff-merge 进 main(升版),再把本分支 rebase 上去;示例本身留在 `example/farm-sim` 不合 main。
- **无类型返回值 + `:=` 会 parse error**:`var n := registry.load_dir(...)` 因 `registry` 无类型、编译期推不出返回类型而报错,退回普通 `var n = ...`。
- **这是骨架不是成品**:没有网格地块、工具体力、动物 NPC、任务/对话——那些是"游戏本体",不属于 kit。本例只验证这些地基能不能顺畅拼在一起。
- 子系统完整 API 见 [`game-clock.md`](../../addons/godot-core-kit/docs/systems/game-clock.md) / [`kit-inventory.md`](../../addons/godot-core-kit/docs/inventory/kit-inventory.md) / [`kit-data-registry.md`](../../addons/godot-core-kit/docs/data/kit-data-registry.md) / [`save-manager.md`](../../addons/godot-core-kit/docs/systems/save-manager.md) / [`ui-stack.md`](../../addons/godot-core-kit/docs/ui/ui-stack.md)。
