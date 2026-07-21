# KitStats —— 统计计数器存储

> `class_name KitStats`(off-facade 类库) · `stats/kit_stats.gd` · `extends RefCounted`

## 职责

放置 / 成就 / 数值向游戏的「玩家生涯计数」心脏。把散落各处的 `player.kills += 1`、`if x > best: best = x` 收拢成一个 **key → 数值** 的表,配三种语义化写法(累加 / 单调取大 / 直接置),读一律走 `get_value`,读档只需一个 `to_dict`/`from_dict`。常与 [KitAchievements](../achievements/kit-achievements.md) 搭配——成就把「解锁条件」声明成「某统计键 >= 阈值」,由 KitStats 提供被判定的数。**off-facade 纯逻辑类**,不挂门面、不挂节点树,游戏各存档 / 各档案自建一台。

## 公开 API

```gdscript
func add(key: StringName, amount := 1.0) -> float      # 累加,返回新值(里程碑计数)
func record_max(key: StringName, value: float) -> float # 单调取大,返回当前值(峰值;默认基线 0,仅非负)
func set_value(key: StringName, value: float) -> void   # 直接置(权威快照,不累加)
func get_value(key: StringName, default := 0.0) -> float # 读(阈值/展示唯一入口)
func has(key: StringName) -> bool
func keys() -> Array
func clear() -> void
func to_dict() -> Dictionary       # key String 化、值 float
func from_dict(d: Dictionary) -> void   # 覆盖式(先清旧值)
```

## 依赖

零依赖(纯 GDScript + 引擎内建,不 `preload` 任何子系统、不挂门面)。参与存档:调用方在存档时收 `to_dict()`、读档时 `from_dict()`——它持权威的生涯计数,故 NG+/重开等「保留统计」的语义由调用方决定是否重置。

## 用法示例

```gdscript
var stats := KitStats.new()

# 命令入口集中喂食(model 层保持纯粹不依赖 stats)
stats.add(&"throws", darts_thrown)          # 累计投镖数
stats.add(&"total_gold", gold_earned)       # 累计产出里程碑
stats.record_max(&"max_payout", gold_this)  # 最高单次收益
stats.set_value(&"jackpots", jackpot_count) # 权威计数镜像进来

# 读:成就阈值判定 / HUD 展示
if stats.get_value(&"total_gold") >= 1_000_000.0:
    ...

# 存档
save["stats"] = stats.to_dict()
stats.from_dict(save.get("stats", {}))
```

## 注意事项

- **`record_max` 默认基线 0**:仅适用非负峰值。要跟踪可能为负的极值(如最低血量),先 `set_value` 一个合适基线,或换用 `add`/`set_value` 组合自行判断。
- **`from_dict` 覆盖式**:先清空再载入,`from_dict({})` = 完全重置(不残留旧键)。
- **喂食集中在命令入口**:推荐由「唯一命令入口层」喂 stats(而非各 model 内部),让业务 model 保持纯粹、不反向依赖统计;读则任意处 `get_value`。
- **不做时间语义、不防作弊**:它只是计数容器。时间 / 离线补偿在 [KitOffline](../offline/kit-offline.md),派生数值聚合在 [KitModifiers](../modifiers/kit-modifiers.md)。
