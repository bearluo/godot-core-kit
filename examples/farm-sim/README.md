# 农场经营 MVP 骨架(farm-sim)

用一条确定性剧情把多个子系统串起来做 **dogfood 验证**:载数据表 → 开店买种子 → 播种 → 逐日推进(天气影响)作物生长 → 收获 → 卖产物换钱 → **存档往返** → **背包 UI 面板入栈** → **任务结算** → **对象池复用第二茬** → **成就结算** → **温室作用域服务** → **多语言本地化** → **帧调度环境 tick**。整段是**框架消费者视角**——只调 `CoreKit.*` 与三个 `class_name` 类库(`KitInventory`/`KitDataRegistry`/`KitContext`),不碰 kit 内部,专门用来暴露多子系统协作时的缺口。

验证覆盖的子系统:

| 子系统 | 在本例中的角色 |
|---|---|
| `KitDataRegistry`(off-facade) | 一个 registry 存 **crop + item + quest + achievement 四种类型**:作物/物品(含价格)/任务/成就表,`load_dir` 载入、`get_def` 查 |
| `KitInventory`(off-facade) | 玩家背包:买入/收获入库、播种/出售扣除;单格堆叠上限由 item 表驱动 |
| `CoreKit.clock` + `CoreKit.bus` | 逐日推进,每天广播 `clock:day_changed`,天气/任务订阅后各自反应(跨子系统解耦) |
| `CoreKit.bus`(游戏侧命名空间) | 游戏自有 **4 个命名空间**:`shop:`、`quest:`、`weather:`、`achievement:`;游戏侧**既发布又订阅** |
| `CoreKit.bus`(多来源聚合) | 任务日志汇聚 `clock:`+`shop:` 两来源;成就追踪器汇聚 `shop:`+`quest:`+`weather:` 三来源(不同组合、各判各的) |
| `CoreKit.bus`(事件链/管道) | **`clock:day_changed` →(天气系统丰富为)→ `weather:changed` → 作物生长**,每级只认上一级事件、无直接引用 |
| `CoreKit.saves` | 存档:`clock`+`bag`+金币+任务进度 存槽,`load`+`from_dict` 复原(经 JSON 往返) |
| `CoreKit.settings`(账号级) | **成就解锁存 settings 而非存档槽**——账号级、跨存档、删档不丢;对照任务的每档进度,dogfood "settings ≠ saves" 边界 |
| `KitUiStack`(off-facade) | 背包面板 `push` 进 UI 栈,面板内容反映背包 |
| `KitStateMachine`(off-facade) | 每株作物一台状态机建模生命周期 **Growing → Mature**(教科书用例) |
| `CoreKit.pool`(对象池) | 作物实例**池化复用**:收获归还、播种借出,两茬共用 2 个实例、零重复 `instantiate` |
| `KitContext`(off-facade DI) | **温室作用域服务容器**:全局 `CoreKit.provide` + 作用域 `provide`(shadow 全局 registry)+ `provide_child`(随作用域释放的 climate)+ 层级回退(温室内/外同一 `resolve` 取到不同服务) |
| `CoreKit.i18n`(本地化) | 运行时切 zh/en/ja,同一 key(`FARM_WELCOME`/`CROP_turnip`…)出不同译文;翻译**内存现建现加**(`add_translation`,免 .po 导入),`locale_changed` 广播,缺 key 回退原样;locale 持久化走 Settings(非存档) |
| `CoreKit.ticker`(帧调度) | **按渲染帧**跑持续逻辑(对照按天广播的 clock):`every_n` 洒水器每 3 帧错峰脉冲;`queue_task` 把 12 块地巡查按 `budget_msec` 预算分帧消化,`queue_drained` 收尾 |

## 文件

| 文件 | 作用 |
|---|---|
| `crop_def.gd` + `data/crops/{turnip,parsnip}.tres` | 作物定义 `Resource`(id/天数/种子/产物/数量) |
| `item_def.gd` + `data/items/*.tres` | 物品定义 `Resource`(id/展示名/max_stack/类别/买价/卖价) |
| `quest_def.gd` + `data/quests/*.tres` | 任务定义 `Resource`(id/标题/条件类型/目标值/限定物品) |
| `achievement_def.gd` + `data/achievements/*.tres` | 成就定义 `Resource`(id/标题/条件类型/目标值),registry 第 4 类型 |
| `climate.gd` + `data/greenhouse_crops/*.tres` | 温室作用域服务:`climate`(provide_child 的 Node 服务)+ 温室专属作物 `golden_turnip`(只在温室 registry) |
| `crop.gd` + `crop.tscn` | 一株已播种作物(Node)。内建 `KitStateMachine`(Growing→Mature),订阅 `weather:changed` 推进生长(雨天 +1);**可被 `CoreKit.pool` 复用**(订阅移到 `_enter_tree`、实现 `_pool_reset`) |
| `weather_system.gd` | 天气系统。订阅 `clock:day_changed`,固定种子 RNG 掷晴/雨,广播 `weather:changed`(带 growth_bonus) |
| `farm.gd` | 农田 = 集成粘合层。持有注入的 registry+背包,负责 `plant`/`harvest_all`(经对象池借还作物) |
| `shop.gd` | 商店 + 钱包(游戏侧经济)。`buy`/`sell` 按 item 表价格,交易广播 `shop:*` 事件 |
| `quest_log.gd` | 任务日志。订阅 `clock:`+`shop:` 事件推进目标,达标广播 `quest:completed`,进度可存档(每档) |
| `achievement_tracker.gd` | 成就追踪器。订阅 `shop:`+`quest:`+`weather:` 解锁里程碑,解锁写 `CoreKit.settings`(账号级、非存档) |
| `backpack_panel.gd` | 极简背包 UI 面板(Control):列出背包物品×总数,供 `KitUiStack.push` |
| `game.gd` / `game.tscn` | 驱动:15 段剧情串起全部验证。整条故事的入口 |

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
[Farm] 载入 2 作物 + 4 物品 + 3 任务 + 3 成就,registry 类型: [achievement, crop, item, quest]
[Shop] 开局金币 200
[Achieve] 解锁:初次采购:第一次在商店买东西
[Shop] 买入 防风草种子 x3 花 60,余额 140
[Shop] 买入 白萝卜种子 x3 花 30,余额 110
[Farm] 播种 白萝卜 (消耗 1 白萝卜种子)
[Farm] 播种 防风草 (消耗 1 防风草种子)
[Clock] 开局 y1 spring d1 06:00
[Weather] 第 2 天 下雨(作物生长 +1)
[Achieve] 解锁:雨中人:经历一个雨天
[Crop:白萝卜] 第 2 天 生长 2/2(雨+1)
[Crop:白萝卜] 状态 Growing→Mature 已成熟
[Crop:防风草] 第 2 天 生长 2/4(雨+1)
[Weather] 第 3 天 晴天(作物生长 +0)
[Crop:防风草] 第 3 天 生长 3/4
[Weather] 第 4 天 下雨(作物生长 +1)
[Crop:防风草] 第 4 天 生长 4/4(雨+1)
[Crop:防风草] 状态 Growing→Mature 已成熟
[Quest] 完成:坚持务农:撑到第 5 天
[Weather] 第 5 天 晴天(作物生长 +0)
[Farm] 收获 白萝卜 x3 → 背包(单格上限 99)
[Farm] 收获 防风草 x2 → 背包(单格上限 1)
[Quest] 完成:首笔收入:累计赚到 100 金币
[Achieve] 解锁:全能农夫:完成全部 3 个任务
[Quest] 完成:萝卜大户:卖出 3 个白萝卜
[Shop] 卖出 白萝卜 x3 得 105,余额 215
[Shop] 结算:金币 215,累计收入 105
[Save] 已存档 'farm_demo' @ y1 spring d5 06:00 gold=215 完成任务=3
[Weather] 第 7 天 下雨(作物生长 +1)
[Weather] 第 8 天 晴天(作物生长 +0)
[Save] 读档前(已变化): y1 spring d10 06:00 gold=0 完成任务=0
[Achieve] 存档清空了任务进度,但成就仍解锁 3/3(存 settings 非存档槽,不受删档影响)
[Save] 读档后(已复原): y1 spring d5 06:00 gold=215 完成任务=3
[UI] 背包面板入栈,depth=1
[UI]   防风草 x2
[UI]   防风草种子 x2
[UI]   白萝卜种子 x2
[Quest] 结算(3/3 完成):
[Quest]   ✓ 105/100 首笔收入:累计赚到 100 金币
[Quest]   ✓ 5/5 坚持务农:撑到第 5 天
[Quest]   ✓ 3/3 萝卜大户:卖出 3 个白萝卜
[Pool] 第一茬收获后:空闲=2 在用=0 总实例=2
[Farm] 播种 白萝卜 (消耗 1 白萝卜种子)
[Farm] 播种 防风草 (消耗 1 防风草种子)
[Pool] 第二茬播种后:空闲=0 在用=2 总实例=2(复用未新建)
[Crop:白萝卜] 第 6 天 生长 1/2
[Crop:防风草] 第 6 天 生长 1/4
[Crop:白萝卜] 第 7 天 生长 2/2
[Crop:白萝卜] 状态 Growing→Mature 已成熟
[Crop:防风草] 第 7 天 生长 2/4
[Weather] 第 8 天 下雨(作物生长 +1)
[Crop:防风草] 第 8 天 生长 4/4(雨+1)
[Crop:防风草] 状态 Growing→Mature 已成熟
[Weather] 第 9 天 晴天(作物生长 +0)
[Farm] 收获 白萝卜 x3 → 背包(单格上限 99)
[Farm] 收获 防风草 x2 → 背包(单格上限 1)
[Pool] 第二茬收获完,累计只 instantiate 过 2 个 Crop(两茬共用)
[Achieve] 结算(3/3 解锁,账号级存 settings):
[Achieve]   ★ 全能农夫:完成全部 3 个任务
[Achieve]   ★ 初次采购:第一次在商店买东西
[Achieve]   ★ 雨中人:经历一个雨天
[Context] 温室内 resolve:registry 有 golden_turnip=true,climate 生长+2
[Context] 温室外 resolve:registry 有 golden_turnip=false(回退全局,看不到温室专属)
[Greenhouse] Climate 服务随温室作用域释放(provide_child 生命周期)
[i18n] 已加载语言: [en, ja, zh]
[i18n] locale_changed → zh
[i18n] [zh] 欢迎来到农场! | turnip=白萝卜 | parsnip=防风草
[i18n] locale_changed → en
[i18n] [en] Welcome to the farm! | turnip=Turnip | parsnip=Parsnip
[i18n] locale_changed → ja
[i18n] [ja] 農場へようこそ! | turnip=カブ | parsnip=パースニップ
[i18n] 缺失 key 回退:has=false t()=CROP_golden
[Ticker] 洒水器 every_n(3):9 帧内脉冲 3 次(错峰降频)
[Ticker] 入队 12 块地巡查,待办=12
[Ticker] 巡查完成:12 块,queue_drained=true
```
> 天气由固定种子 RNG 决定,序列可复现(晴/雨影响作物当天生长几格)。注意存档只回滚时钟,
> 不回滚天气 RNG,所以读档后重玩的第 6~9 天天气与存档前的不同——天气是瞬态、不入档。
>
> `[Achieve] 解锁:全能农夫` 打印在 `[Quest] 完成:萝卜大户` **之前**看似奇怪:因为 quest_log 是
> 先 `publish quest:completed` 再 log 自己的"完成"行,成就在第 3 个任务的 publish 里就解锁并打印了,
> 早于该任务自己的完成行——时序正确,非乱序。

逐段对应验证点:
1. `载入 … + 3 成就 … [achievement, crop, item, quest]` —— 一个 `KitDataRegistry` **同时承载四种类型**,`load_dir` 分别扫四个子目录。
2. `[Shop] 买种子` —— 开局 200 金币,`shop.buy` 按 item 表 `buy_price` 扣钱入包,广播 `shop:bought`;价格数据驱动。
3. `[Weather] 掷天气 → [Crop:*] 生长 / 状态 Growing→Mature` —— `advance_day()` 广播 `clock:day_changed`,天气系统据此掷晴/雨、丰富为 `weather:changed`(带 growth_bonus),作物**只认 `weather:changed`** 地长 1(+雨天 bonus)格 → **bus 事件链 clock→weather→crop**;到 grow_days 由内建 `KitStateMachine` 转到 Mature(`state_changed` 打出转移行),`is_ready()` 查该态。雨天把 2 天的白萝卜一天催熟(见 `第 2 天 生长 2/2(雨+1)`)。
4. `[Quest] 完成:坚持务农`(第 5 天)—— 任务日志订阅 `clock:day_changed`,`reach_day` 目标在 d5 达标。
5. `[Quest] 完成:首笔收入 / 萝卜大户`(卖出时)—— 任务日志**同时**订阅 `shop:sold`,`earn_gold`(累计 105≥100)与 `sell_count`(卖 3 白萝卜≥3)达标 → 证明 **bus 作多来源事件聚合器**(一个订阅方汇聚 clock:+shop: 两来源)。
6. `[Save] 存 → 变 → 复原` —— `clock+bag+金币+任务进度` 存进 `CoreKit.saves`,推进 5 天+清空钱包+遗忘任务后 `load`+`from_dict` 完整复原(d5/gold=215/完成任务=3),证明 **saves 接入 + to_dict/from_dict 扛得住 JSON int→float 往返**。
7. `[UI] 背包面板` —— `KitUiStack.push` 一个反映背包内容的 Control 面板,`depth=1`。
8. `[Quest] 结算 3/3` —— 三条目标各由不同来源事件在整局中聚合达成。
9. `[Pool] 复用` —— 第一茬收获后 2 个 Crop 实例归还池(空闲=2);第二茬播种直接借出复用(总实例仍=2、`instantiate` 零次),生长/成熟一切如常 → 证明 **`CoreKit.pool` 复用有状态节点**,省掉反复实例化。
10. `[Weather] 晴/雨` —— 天气系统订阅 `clock:day_changed`、按固定种子掷天气、广播 `weather:changed`;这是 clock→weather→crop **事件链**的中间一环,也是游戏自有命名空间之一。天气瞬态、不入档(读档只回滚时钟)。
11. `[Achieve] 解锁 / 结算` —— 成就追踪器汇聚 `shop:bought`(初次采购)+`weather:changed` 雨天(雨中人)+ 第 3 个 `quest:completed`(全能农夫)三来源解锁;解锁写 **`CoreKit.settings`**。关键对照:`[Save] 读档前` 那步把**任务进度清空**(每档状态),但同一行紧跟的 `[Achieve] 仍解锁 3/3` 证明**成就不受删档/复原影响**——它在 settings 不在存档槽,dogfood **"settings ≠ saves"** 的边界。
12. `[Context] 温室内/外 resolve` —— **`KitContext` 层级服务容器**(off-facade DI,对照前面全程手动 `bind` 注入):registry 注册为全局服务(`CoreKit.provide`);温室是一个 `KitContext` 作用域,`provide` 一份 **shadow 全局**的专属 registry(含温室限定作物 `golden_turnip`)、`provide_child` 一个 climate 服务。温室内的节点 `resolve("registry")` 命中温室作用域(`golden_turnip=true`),温室外的节点同一份 `resolve` 回退到全局根(`golden_turnip=false`)——**同一份 resolve 代码、因所在子树不同拿到不同服务**。温室 `free()` 时 `provide_child` 的 climate 连带释放(`[Greenhouse] Climate 释放`),证 **provide_child 生命周期归容器**。
13. `[i18n] 切 zh/en/ja` —— **`CoreKit.i18n` 本地化**:3 份翻译**内存现建现加**(`Translation.new`+`add_message`→`add_translation`,免 .po 编辑器导入);`set_locale` 逐一切换,同一 key `FARM_WELCOME`/`CROP_turnip`/`CROP_parsnip` 出不同译文,每次切换广播 `locale_changed`。缺 key(`CROP_golden`)`has_translation=false`、`t()` 原样返回 key(debug 下去重告警帮发现漏翻)。locale 是跨存档偏好 → `set_locale` 自动持久化到 Settings 的 `"locale"` 分区(**不进存档槽**),收尾 `erase_section` 复位。
14. `[Ticker] 洒水器 / 巡查` —— **`CoreKit.ticker` 帧调度**(按渲染帧,和按天广播的 clock 对照):① `every_n(cb, 3)` 洒水器每 3 帧脉冲一次,9 帧内 3 次(不同 handle 靠 `(_frame+handle)%n` 自动错峰,上百实体不挤同帧);② `queue_task` 把 12 块地巡查一次性入队(`待办=12`),把 `budget_msec` 调到 0.1ms 强制**分帧消化**(每帧至少 1 个不饿死),全部跑完后 `queue_drained` 广播 → `巡查完成:12 块, drained=true`。脉冲数/巡查数由固定 await 帧数决定,确定性可复现(跑两遍一致)。

## 要点

- **消费者视角、零 kit 侵入**:整例不 `preload` 任何子系统脚本,`registry`/`bag` 全由驱动方 `bind(...)` 注入——这正是"用 core-kit 做游戏"的推荐姿势。
- **跨子系统靠 bus 解耦**:作物/任务都不持有时钟或商店引用,只订阅事件名常量(命名约定 `namespace:event`,见 [`event-bus.md`](../../addons/godot-core-kit/docs/core/event-bus.md))。
- **游戏可定义自己的 bus 命名空间**:游戏自有 `shop:`(shop.gd)、`quest:`(quest_log.gd)、`weather:`(weather_system.gd)、`achievement:`(achievement_tracker.gd)四个命名空间,与 kit 的 `clock:` 并存互不干扰——命名约定不止约束 kit,游戏侧照办即可解耦自己的系统。
- **bus 是多来源聚合器**:`quest_log` 汇聚 `clock:day_changed`+`shop:sold` 两来源;`achievement_tracker` 汇聚 `shop:bought`+`quest:completed`+`weather:changed` 三来源(**不同的组合、各判各的里程碑**)——一个订阅方把多个无引用关系系统的广播汇成自己的进度,是"没有引用关系的广播"最典型的用法。
- **bus 也能串成事件链/管道**:`clock:day_changed` →(天气系统在处理器里丰富为)→ `weather:changed` → 作物据 `growth_bonus` 生长。每级只认上一级事件、彼此不 `preload`(crop 认 weather、weather 认 clock)。**嵌套 publish**(在一个事件的处理器里 publish 另一个事件)靠 EventBus 的快照派发(重入安全)成立——见 [`event-bus.md`](../../addons/godot-core-kit/docs/core/event-bus.md) 的"派发期间 subscribe/unsubscribe 只影响下一次 publish"。天气是瞬态状态(不入档),读档只回滚时钟、天气 RNG 继续走。
- **每实体状态机用 `KitStateMachine`**:`crop.gd` 在代码里建一台状态机(`Growing`/`Mature` 用内部类作 KitState,免加文件),相位切换交给 `transition_to`、`is_ready()` 查 `current_state.name`。构造有次序要求:**所有 KitState 子节点 add_child、`initial_state` 设好、`state_changed` 连好,都要在 `add_child(machine)`(入树触发机器 `_ready`)之前完成**。生长计数留在 crop、相位交给 FSM 是常见分工(FSM 建模离散相位/行为,计时器留实体)。
- **持久化边界(什么归 kit、什么归游戏)**:`shop.gold` / 任务进度是游戏侧状态(kit 无货币/任务子系统),随存档 `to_dict/from_dict` 一起走。
- **`settings` ≠ `saves`(什么进存档、什么进偏好)**:**任务**是每【存档槽】的进度 → 进 `CoreKit.saves`,删档即失;**成就**是【账号级】里程碑 → `achievement_tracker` 解锁写 `CoreKit.settings`("achievements" 分区),跨存档、删档不丢。demo 在 `[Save] 读档前` 那步把任务清空,同一行紧跟 `[Achieve] 仍解锁 3/3` 就是这条边界的现场证明。收尾用 `settings.erase_section("achievements")` 复位以保证可重复跑(仿 `saves.delete_slot`)。判定选择:音量/键位/语言/成就这类"跨存档、装完游戏该一直记住"的进 settings,当前局面/进度进 saves。
- **Node 监听者主动清理**:`Crop`/`QuestLog` 在 `_exit_tree` 调 `CoreKit.bus.unsubscribe_all(self)`,不留悬空订阅。
- **对象池复用有状态节点(`CoreKit.pool`)**:作物是高频 spawn/despawn 的实体,`farm.plant` 用 `pool.acquire`、`harvest_all` 用 `pool.release`,两茬共用 2 个实例。池化有状态 Node 的三条铁律(见 `crop.gd`):① `_ready` 一生只跑一次(即使被反复摘挂树也不重跑)→ 只放"建一次"的 FSM 搭建;② 订阅/退订必须放 `_enter_tree`/`_exit_tree`(每次进出树都跑),否则复用后收不到事件;③ 实现约定钩子 `_pool_reset()`,归还时清本轮状态(`_stage=0`、FSM 拨回 `Growing`),下次复用从头开始。**池按 `PackedScene` 复用**,故作物需配一个 `crop.tscn`(裸 Node + 挂 `crop.gd`)。
  - **`pool.release()` 用 `call_deferred` 摘父节点**(躲物理碰撞回调里同步改树的 "flushing queries" 报错),所以归还的节点**在本帧内仍挂树、仍订阅**。本 demo 同步推进时钟,收获后 `await get_tree().process_frame` 让延迟摘除落定、作物真正离树退订,之后 `advance_day` 才不会再喂到已归还实例(否则它们会继续长)。真实游戏每帧有天然帧边界,通常无需手动 await——这是"把整局压进一个 `_ready` 同步跑"的 demo 才凸显的注意点。
  - **收尾 `pool.clear("crop")`**:池持有的空闲实例是游离节点(不在树上),退出时不被 SceneTree 回收,不清会报 `resources still in use`——仿 `saves.delete_slot` 一样收尾释放。
- **本地化用 `CoreKit.i18n`(不是散落各处的 `tr()`)**:单点托管——`set_locale` 一处切、`t(key)` 处处取、`locale_changed` 一个信号驱动 UI 刷新。翻译资源除了 `.po`/`.csv` 编辑器导入外,**还能内存现建现加**(`Translation.new`+`add_message`→`i18n.add_translation`),适合运行时/热更/测试(本例即用此法免导入)。两条边界:①缺 key 时 `t()` 原样返回 key 且 debug 去重告警,是**发现漏翻**的抓手,别把它当报错;②**locale 是跨存档偏好 → 进 Settings 不进存档槽**(与成就同理,`set_locale` 自动落 `"locale"` 分区),切勿存进 SaveManager。展示名要本地化就把 `.tres` 里的中文字面量换成 key、用 `i18n.t(key)` 取(本例用独立 key 演示,未改数据表的 `display_name`)。
- **帧驱动 `CoreKit.ticker` vs 天驱动 `clock`(选对节奏)**:两种"随时间跑逻辑"的通道各司其职——**离散、语义化、低频**的用 `clock:day_changed` 事件(作物生长、任务、天气);**连续、高频、每帧**的持续逻辑用 `ticker`。`every_n(cb, n)` 把高频回调降频到每 n 帧、不同 handle 自动错峰(上百实体的低频 AI 不挤同帧,靠 `(_frame+handle)%n`);`queue_task`+`budget_msec` 把批量一次性任务(批量生成/巡查/烘焙)按每帧预算分摊到多帧、`queue_drained` 收尾,避免卡单帧。二者都只吃渲染帧(`_process`),要物理帧节奏自己写 `_physics_process`。回调宿主 `free()` 后 `every_n` 自动剪除,一次性队列里失效 Callable 直接跳过。**热路径别每帧 resolve/分配**,该降频的降频、该分帧的分帧。
- **手动 `bind` 注入 vs `KitContext` 服务容器**:本例前 12 段全程用手动 `bind(registry, ...)` 注入依赖(消费者视角最直白);第 13 段 `KitContext` 展示 DI 容器怎么把这套接线做成**按 key 解析 + 层级回退**——`CoreKit.provide/service` 是整局全局作用域,`KitContext` 节点是关卡/实体级作用域,`resolve` 沿祖先链向上、树顶兜底全局根。独特价值在**作用域 + shadow + 生命周期**:温室 `provide("registry", 专属)` 在子树内 shadow 全局同名 key,`provide_child("climate", node)` 让 Node 服务随容器 `free` 连带释放(对照 `provide` 只存引用不管生命周期)。心智与 per-entity `KitStateMachine` 一致:每个作用域一个容器。热路径别每帧 `resolve`,在 `_ready` pull 一次存成员。(本例未演示的 `subscribe`〔化解"后代 `_ready` 早于祖先"的时序坑〕/ `provide_factory`〔SINGLETON/TRANSIENT scope〕见 [`kit-context.md`](../../addons/godot-core-kit/docs/di/kit-context.md)。)
- **dogfood 记到的四条坑,其中三条已反哺进 kit(v0.18.0)**——这正是"在 examples 里做游戏验证框架"的产出闭环:
  1. **`StringName` 数组的原生 `.sort()` 按指针地址排、非字典序**(Godot 行为)。→ **已修**:`KitDataRegistry.ids/types` 加 `sorted` 参数(`ids(&"crop", true)` 即字母序);本例已改用(见 `game.gd` / `quest_log._ready`)。
  2. **`KitInventory` 没有"列出全部物品"的聚合方法**,背包 UI 只能手动遍历 `capacity()`×`slot(i)`。→ **已修**:新增 `KitInventory.totals() -> {id:总数}`;本例已改用(见 `backpack_panel._aggregate`)。
  3. **`StringName` 作 Dictionary 键经存档(JSON)会退化为 `String`**:自定义 `to_dict/from_dict` 若用 StringName 键存 dict,`from_dict` 必须把键归一回 StringName(见 `quest_log.from_dict`),否则后续用 StringName 索引会 miss。→ 这是**游戏侧惯例**,不是 kit 缺陷(kit 各子系统 `from_dict` 已规避,如 KitInventory 存 `String(id)`、读 `StringName(id)`),照做即可。
  4. **`KitStateMachine` 没有"当前态判定"便利方法**,查当前态要 `sm.current_state != null and String(sm.current_state.name) == "X"`。→ **已修**:新增 `state_name() -> String` / `is_in(query) -> bool`(null 安全);本例已改用(见 `crop.is_ready`)。
  > 修复流程遵分支分流规矩:三条 kit 改进剥出来走 kit 正常 SDD → run_all 绿 → **ff-merge 进 main(0.17.0→0.18.0)**,再把本分支 rebase 到新 main、改用新 API。示例本身仍留在 `example/farm-sim` 不合 main。
  >
  > **增量 8~13(对象池 / 天气 / 成就 / KitContext / i18n / 帧调度)未再暴露新的 kit 缺口**——`CoreKit.pool` / `CoreKit.bus`(嵌套 publish)/ `CoreKit.settings` / `KitContext` / `CoreKit.i18n` / `CoreKit.ticker` 的现有 API 都够用,只重踩了一次已知的 GDScript `:=` 坑(下条)。这本身是正向信号:kit 表面已能顺滑支撑这些常见玩法系统。
- **无类型对象的返回值/属性 + `:=` 会 parse error**:`var n := registry.load_dir(...)`、`var shown := def.grow_days`——只要右侧取自无类型变量(`registry`/`def` 都是无类型注入的),编译期推不出类型就报 `Cannot infer the type`,退回普通 `var x = ...` 即可。**这条本增量又踩了一次**(crop 天气重构里 `var shown := ...`),是 GDScript 与"消费者视角注入(不写类型)"结合下的高频坑,不是 kit 缺陷。
- **这是骨架不是成品**:没有网格地块、工具体力、动物 NPC、对话——那些是"游戏本体",不属于 kit。本例只验证这些地基能不能顺畅拼在一起。
- 子系统完整 API 见 [`game-clock.md`](../../addons/godot-core-kit/docs/systems/game-clock.md) / [`kit-inventory.md`](../../addons/godot-core-kit/docs/inventory/kit-inventory.md) / [`kit-data-registry.md`](../../addons/godot-core-kit/docs/data/kit-data-registry.md) / [`save-manager.md`](../../addons/godot-core-kit/docs/systems/save-manager.md) / [`settings.md`](../../addons/godot-core-kit/docs/core/settings.md) / [`ui-stack.md`](../../addons/godot-core-kit/docs/ui/ui-stack.md) / [`state-machine.md`](../../addons/godot-core-kit/docs/state-machine.md) / [`object-pool.md`](../../addons/godot-core-kit/docs/systems/object-pool.md) / [`kit-context.md`](../../addons/godot-core-kit/docs/di/kit-context.md) / [`i18n.md`](../../addons/godot-core-kit/docs/systems/i18n.md) / [`frame-scheduler.md`](../../addons/godot-core-kit/docs/systems/frame-scheduler.md)。
