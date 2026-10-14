# KitAchievements —— 成就引擎

> `class_name KitAchievements`(off-facade 类库) · `achievements/kit_achievements.gd` · `extends RefCounted`
> 配套 schema：`class_name AchievementDef` · `achievements/achievement_def.gd` · `extends Resource`

## 职责

数据驱动的成就系统三件事：**阈值判定 + 触发去重 + 平台抽象层**。持有成就定义表（每条 = `AchievementDef{id, stat_key, threshold}`）+ 已解锁集合。核心 `evaluate(stats)` 扫全部 def，凡「未解锁」且 `stats.get_value(stat_key) >= threshold` → 解锁，返回本次**新解锁 id 列表**（供上层弹 toast）；已解锁的**绝不重触**——取代散落各处「解锁前先查有没有解锁过」的样板。任何成就都是「读某统计键到某值」的声明式条件，无需为每条写触发代码。统计源见 [KitStats](../stats/kit-stats.md)。**off-facade 纯逻辑类**，不挂门面、不挂节点树、不碰事件总线。

## 公开 API

```gdscript
# KitAchievements
func set_defs(defs: Array) -> void            # 装入 def 表(通常 KitDataRegistry.all(&"achievement") 或代码构建)
func set_steam_sink(sink: Callable) -> void   # 平台抽象层:新解锁时 sink.call(id) 一次(默认空)
func evaluate(stats) -> Array                 # 扫 def 解锁达阈值者,返回新解锁 id 列表(def 表顺序)
func unlock(id: StringName) -> bool           # 手动解锁一条(去重:新解锁 true / 已解锁 false)
func is_unlocked(id: StringName) -> bool
func count() -> int                           # 已解锁数
func total() -> int                           # def 表条数
func unlocked_ids() -> Array
func to_dict() -> Dictionary                  # 只存已解锁 id 集合 {"unlocked":[...]}
func from_dict(d: Dictionary) -> void

# AchievementDef(@export:id / title / desc / stat_key / threshold / category / hidden)
```

`evaluate` 的 `stats` 与 def 均**鸭子类型**：`stats` 只需 `get_value(key, default)`（通常 KitStats）；def 只需 `id` / `stat_key` / `threshold` 三字段——`AchievementDef` 是推荐 schema，游戏可子类化补字段或提供任何带这三字段的对象。

## 依赖

零依赖（纯 GDScript + 引擎内建，不 `preload` 任何子系统、不挂门面、不绑定任何平台 SDK）。存档只存已解锁 id 集合——def 表是只读数据、统计另存，派生态（哪些达阈值）由 `evaluate` 重算。平台成就（Steam / Google Play Games）经 `set_steam_sink` 注入回调，kit 本身不引入平台依赖。

## 用法示例

```gdscript
var stats := KitStats.new()
var ach := KitAchievements.new()
ach.set_defs(registry.all(&"achievement"))   # AchievementDef 列表
# 上线时挂平台层(可选):
# ach.set_steam_sink(func(id): Steam.setAchievement(String(id)))

# 命令入口:喂完统计即求值,广播新解锁供 UI 弹 toast
func on_action():
    stats.add(&"throws", 1)
    for id in ach.evaluate(stats):
        bus.publish("achievement:unlocked", id)

# 存档
save["achievements"] = ach.to_dict()
ach.from_dict(save.get("achievements", {}))
ach.evaluate(stats)   # 读档后自愈:补发本版新增/存档漏判的成就(不再重触已解锁)
```

### 接 GodotSteam(仅桌面 Steam 版)

[GodotSteam](https://codeberg.org/godotsteam/godotsteam) 是 GDExtension,只能用在桌面构建,Web 和微信小游戏用不了,所以只在有 `Steam` 单例时挂 sink。成就 id 要和 Steamworks 后台的 API 名一致。API 名以 [godotsteam.com](https://godotsteam.com) 文档为准:

```gdscript
func _ready() -> void:
    if Engine.has_singleton("Steam"):
        var steam := Engine.get_singleton("Steam")
        steam.steamInitEx()
        ach.set_steam_sink(func(id: StringName) -> void:
            steam.setAchievement(String(id))
            steam.storeStats())          # 上传后 Steam 才弹解锁提示

func _process(_delta: float) -> void:
    if Engine.has_singleton("Steam"):
        Engine.get_singleton("Steam").run_callbacks()
```

## 注意事项

- **去重是核心契约**：已解锁 id 永不再触发 sink、永不出现在 `evaluate` 的返回列表。据此可安全地在每次统计变更后无脑 `evaluate`。
- **`evaluate` 幂等**：同一 `stats` 反复调用只有首次跨阈值那次返回新解锁；适合高频调用（扫 def 表是线性、廉价）。
- **读档后调一次 `evaluate`**：能自愈——补发「本版新增的成就」或「统计已达标但存档漏记」的解锁；因去重不会重复弹旧 toast（若不想弹，丢弃返回值即可）。
- **不做时间/数值语义**：它只判定「统计 ≥ 阈值」。计数在 [KitStats](../stats/kit-stats.md)、离线在 [KitOffline](../offline/kit-offline.md)、产出聚合在 [KitModifiers](../modifiers/kit-modifiers.md)。
- **平台回调是同步一次性**：`sink` 在新解锁的 `evaluate`/`unlock` 内被调用一次；若平台 SDK 异步，请在 sink 内自行排队，勿阻塞。
