# KitModifiers —— 数值修正器栈

> `class_name KitModifiers`(off-facade 类库) · `modifiers/kit_modifiers.gd` · `extends RefCounted`

## 职责

放置 / 增量(incremental / idle)游戏「产出聚合」的心脏。每个可被加成的量(伤害、产率、暴击率、全局乘数……)= 一个 **target**;每条升级 / 道具 / 跨来源协同 = 一条带 `source_id` 的修正,声明式注册到该 target 的栈。最终值按 `(base + Σ加法层) × Π乘法层` 求值。因为每条修正带来源、聚合可交换,故可**覆盖、可移除、可查询明细、顺序无关**——取代散落各处的 `total *= x`(顺序不可控、无法回滚、无法展示「产出由哪些来源构成」)。**off-facade 纯逻辑类**,不挂门面、不挂节点树,游戏各实体 / 各存档自建一台。

## 公开 API

```gdscript
func set_modifier(target: StringName, source_id: StringName, op: StringName, value: float) -> void
# 注册/覆盖一条修正。op:&"add"(加法层)/ &"mul"(乘法层);同 source_id 覆盖式。
# 累积效果(如升级 level)由调用方把 level 折进 value(如 pow(1+eff, level))。

func remove_source(target: StringName, source_id: StringName) -> void   # 撤下某来源
func value_for(target: StringName, base: float) -> float                # (base+Σadd)×Πmul,惰性缓存
func breakdown(target: StringName, base: float) -> Dictionary           # 明细:见下
func sources(target: StringName) -> Array                               # 该 target 的所有 source_id
func clear(target := &"") -> void                                       # 清一个 target;空参清全部

# breakdown 返回 { base, add, mul, result, sources:[{source_id, op, value}] }
#   —— result == value_for(target, base);sources 含未参与求值的保留 op(如 exp)。
```

## 依赖

零依赖(纯 GDScript + 引擎内建,不 `preload` 任何子系统、不挂门面)。不参与存档——调用方持权威态(升级等级、jackpot 次数等),读档后重放 `set_modifier` 即重建全部派生修正。

## 用法示例

```gdscript
var mods := KitModifiers.new()

# 升级:镖值 +50%/级(乘法层),买到 3 级
mods.set_modifier(&"gold_per_dart", &"golden_tips", &"mul", pow(1.5, 3))
# 手动/自动产出都经同一求值点取聚合值
var per_dart := mods.value_for(&"gold_per_dart", 1.0)   # base=1.0

# 跨来源协同:一条「全局乘数」target 被别处叠乘,所有读它的房间一次放大
mods.set_modifier(&"global_mul", &"lotto_jackpot", &"mul", pow(1.5, jackpot_count))
var out := base_output * mods.value_for(&"global_mul", 1.0)

# 读档重放:清残留 → 按存档等级重新 set_modifier
mods.clear(&"gold_per_dart")
for id in saved_levels:
    apply_upgrade(mods, id, saved_levels[id])
```

## 注意事项

- **聚合公式固定 `(base+Σadd)×Πmul`**:加法层先求和再被乘法层整体放大。要「先乘后加」请换 target 或改基数,别指望层内顺序(聚合可交换,顺序无关是特性)。
- **同 source_id 覆盖,不累加**:升级涨级请重算整条 value(把 level 折进去)再 `set_modifier` 同一 source_id;想多条并存就用不同 source_id。
- **指数层 exp 预留未实现**:`op==&"exp"` 会被 `set_modifier` 登记、出现在 `sources`/`breakdown`,但**不参与** `value_for` 求值(YAGNI,尚无消费方)。将来需要时在 `_ensure` 补一层即可。
- **脏标惰性重算**:`set/remove/clear` 置脏,`value_for/breakdown` 才重算并缓存;高频只读极廉价。不要在热循环里反复 `clear` 全量。
- **不参与存档、不防作弊**:它只算派生值。权威态与时间语义在别处(存档等级、`KitOffline` 的墙钟)。
