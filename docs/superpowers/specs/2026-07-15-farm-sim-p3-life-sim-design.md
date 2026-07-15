# farm-sim P3 · 生活模拟支柱(NPC + 多区域)设计

> 状态:架构与范围已获需求方口头认可(2026-07-15)。本文为 P3 正式 spec;实现计划见
> `docs/superpowers/plans/2026-07-15-farm-sim-p3-life-sim.md`。承接 P0-P2(vertical slice + 内容层,
> 分支 `example/farm-sim` @245164d),继续建在 core-kit 上,全程占位美术。

## 1. 目标

把单场景的农场扩成**多区域世界 + 有社交的 NPC**:玩家在 农田/农舍/小镇 间走动切场景,小镇有能对话、
收礼、有好感度、好感解锁奖励的 NPC。同时 dogfood 之前一直没覆盖的 `CoreKit.scenes`(场景切换)+
`KitTransition`(转场缓动)两个子系统。

## 2. 关键架构决策:持久状态上移到 `Farm` autoload

`CoreKit.scenes.change_scene` 是**整场景替换**(无场景栈,替换即 free 旧场景)。因此跨场景要保留的状态
**不能待在被切走的区域场景里**。引入游戏自己的单例 autoload **`Farm`**(`examples/farm-sim/farm_state.gd`,
extends Node,注册到 `project.godot` `[autoload]`),承载全部跨场景持久状态:

| 状态 | 类型 | 说明 |
|---|---|---|
| `registry` | KitDataRegistry | crop/item/quest/achievement/**npc** 定义 |
| `bag` | KitInventory | 背包 |
| `grid` | FarmGrid | 农田模型(纯逻辑,RefCounted) |
| `shop` | shop.gd(Node,Farm 的子节点) | 钱包 gold + 买卖 |
| `energy` / `water_radius` / `selected_crop` / `crop_ids` | 值 | |
| `quest_log` / `tracker` / `weather` | Node(Farm 子节点) | 事件订阅者,必须常驻在树 |
| `relationships` | Dictionary {npc_id:int} | **P3 新增**:好感度点数 |
| `unlocked` | Dictionary {npc_id:true} | **P3 新增**:已发放的好感解锁 |
| `current_area` / `spawns` | String / Dictionary | 当前区域 + 各区玩家出生/离开位置 |

- **惰性启动**:`Farm.start()` 幂等,首次被农田场景调用时才 load 数据、建 grid/bag/shop/quest_log/tracker/
  weather 并订阅。**demo.tscn / kit 测试不触发**(autoload 的 `_ready` 只置位,不做重活)→ run_all 不受影响。
- **clock 本就是 CoreKit autoload**,天然持久,不入 Farm。
- **HUD 在 `CoreKit.layers` 的 "hud" 层**,天然跨场景常驻,不随区域切换重建。
- **存读档收敛到 `Farm.save_game()/load_game()`**:一处存全部(grid/bag/gold/energy/water/quests/
  relationships/unlocked/clock/current_area/player 位置)。

**代价与守护**:这是从"单场景全包"到"持久 autoload + 多薄场景"的重构,对 P0-P2 有回归风险。守护:
①`FARM_SMOKE` 端到端自测迁到 Farm 上、保持 PASS;②`run_all` FAILS=0;③玩法零变化(P0-P2 F5 手感不变)。
低风险非重构替代(持久根挂可换子场景)被否——那样不 dogfood `CoreKit.scenes`,失去覆盖价值。

## 3. 多区域世界

三个区域场景(均薄:读 `Farm` 状态,只建 view + 本地布景 + 出生点):

| 区域 | 场景 | 内容 |
|---|---|---|
| 农田 farm | `farm_area.tscn`(由 world.tscn 演变) | 农田网格 + 种植(J 用工具)+ 天气视觉 + 通往农舍/小镇的边界 |
| 农舍 house | `house_area.tscn` | 床(交互 → 睡觉推进天 + 回体力)+ 存档点 + 通往农田的门 |
| 小镇 town | `town_area.tscn` | 商店入口(交互 → 商店面板)+ NPC + 通往农田的门 |

- **区域基类** `area_base.gd`(extends Node2D):共享玩家生成、输入派发(WASD 走动、面板 I/P/L/Esc 全区可用)、
  区域切换。农田专属(grid view + 工具 J)在 farm_area 覆盖;小镇/农舍的 J = 与身边 NPC/物件交互。
- **切换**:边界/门是 `Area2D` 触发区(或位置判定),走进 → `_go_to(area, spawn, transition)`:把目标出生点写进
  `Farm.pending_spawn`,`await CoreKit.scenes.change_scene(area_path, KitTransition)`;新区 `_ready` 读 `Farm.pending_spawn`
  把玩家摆到位。门用 FADE、开阔边界用 SLIDE(dogfood 两种转场)。
- **农田状态跨区保留**:去农舍睡一觉回来,已种作物/浇水/生长进度都在(全在 Farm.grid)。

## 4. NPC(数据驱动)

`npc_def.gd`(Resource,进 registry "npc" 类型 → registry 扩到第 5 类型):

```
id: StringName            # npc id
display_name: String
home_area: StringName      # 常驻区域(town/house/farm)
schedule: Array            # 轻量日程 [{after_hour:int, area:StringName, x:int, y:int}],按当前 hour 取最后满足项
dialogue: Array            # 闲聊行(String);每次对话轮流/随日推进
gift_loved: Array          # 爱的物品 id(送礼 +大)
gift_liked: Array          # 喜欢(+小)
gift_disliked: Array       # 讨厌(-)
unlock_at: int             # 好感阈值(点数)
unlock_item: StringName    # 达阈值发放的物品(如特殊种子);空=无
```

- **出现/日程**:NPC 节点(占位:色块 + 头顶名字 Label)在其**当前时段所在区**渲染;进某区时,该区场景问 Farm/registry
  "现在哪些 NPC 在本区",实例化站到 schedule 指定格。轻量:schedule 按 `hour` 选站位/区,不做寻路移动动画(占位)。
- **交互**:玩家走到 NPC 相邻格,J(交互)→ 打开**对话面板**。

## 5. 对话 + 送礼 + 好感度

- **对话面板** `dialogue_panel.gd`(Control,走 KitUiStack,模态锁玩家):顶部 NPC 名 + 一行台词;下方选项
  **[聊天] / [送礼:<当前选中物品>] / [离开]**(↑↓ 选,J 确认)。聊天 → 出下一句台词 + 当日首次聊天 +1 好感。
- **送礼**:选"送礼" → 把背包里**当前选中物品**(复用 HUD 的 selected;或扩一个"手持物品"概念)给 NPC →
  按偏好加减好感(爱 +big / 喜欢 +small / 讨厌 −),扣该物品 1 个,出对应反应台词;广播 `npc:gift_given`。
  一天对同一 NPC 只接一次礼(防刷)。
- **好感度**:`Farm.relationships[npc_id]` 累计点数;好感等级 = 点数分档(如每 100 一级)。广播
  `npc:friendship_changed{npc_id, points, level}`。命名空间 `npc:`(游戏第 5 个自有命名空间)。
- **持久化**:relationships 随存档 to_dict/from_dict(StringName 键经 JSON 归一,见既有 quest_log 坑)。

## 6. 好感解锁

好感点数达 `unlock_at` 且尚未发放 → 把 `unlock_item`(如"星之种子"特殊作物种子)加进背包 + 记 `Farm.unlocked[npc_id]=true`
(幂等,只发一次)+ 广播 `npc:unlocked{npc_id, item}`。`unlocked` 随存档。解锁的作物是一株高价值作物,给种田循环
一个"社交 → 农业"的正反馈。

## 7. 测试策略

- **headless 逻辑测**:新 `test/test_relationship.gd`(纯逻辑:好感加减/偏好判定/等级分档/解锁阈值幂等/存档往返)。
  NPC 定义载入 + schedule 取项也可测。沿用"运行时 load、不依赖 CoreKit、直接 new"套路。
- **FARM_SMOKE 迁到 Farm**:自测搬到 `Farm`(或农田场景驱动 Farm),覆盖 P0-P2 全部 + P3:区域切换往返(农田→农舍→
  农田,农田状态不丢)、NPC 出现、对话面板 build/push/pop、送礼加好感、解锁发放、好感存读档。仍 env 门控、打印
  `[Farm][SMOKE] PASS`。
- **run_all**:farm 测试独立于 kit 门(不进 `$tests`);Farm autoload 惰性、demo/kit 测试无副作用 → run_all 仍 FAILS=0。

## 8. 分支与工作流

全部改动留 `example/farm-sim` 分支,**不升版本、不合 main、push 留用户**。P3 若暴露 kit 缺口(如
`CoreKit.scenes` 需要"场景栈/记住返回点"、transition 需要新类型),记进"反哺候选",按分支分流剥到 main 单独 SDD,
不在 P3 计划里改 kit。旧 dogfood game.gd/game.tscn 保留作 kit 回归。

## 9. 范围与非目标(YAGNI)

- **做**:3 区世界 + 场景切换转场、1-2 个 NPC(数据驱动可扩)、对话/送礼/好感/解锁、持久化。
- **不做(后置)**:NPC 寻路移动动画(schedule 只换站位)、多句分支剧情树、婚恋/日程事件、节日、
  多存档槽 UI、真实美术(P5)。NPC 数量起步 1-2 个,数据驱动加更多是纯加 .tres。

## 10. 开放/待定(不阻塞开写)

- 好感等级的具体阈值/送礼点数 → 占位值,后续平衡。
- schedule 时段划分粒度(2-3 段即可)→ 实现时定。
- "当前选中物品"送礼是否复用 HUD 的 selected_crop 语义,还是引入独立"手持物品" → 计划 Task 里定(倾向复用背包里
  一个可循环选中的物品指针,轻量)。
