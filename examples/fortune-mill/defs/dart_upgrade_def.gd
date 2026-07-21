class_name DartUpgradeDef
extends Resource
## 飞镖房升级定义(.tres 用的 schema)。一条升级 = 对某 modifier target 的一层贡献,
## 或(kind==unlock)解锁靶心档位数。成本几何曲线 base_cost × growth^level。

@export var id: StringName
@export var title: String = ""
## 分类(UI 分组 + DartsRoom 特判):value(产出) / unlock(解锁靶心档) / multi(多镖)
@export var kind: StringName = &"value"
## modifier target(kind==unlock 时忽略):gold_per_dart / darts_per_throw
@export var target: StringName = &"gold_per_dart"
## 修正算子:add(每级 +effect×level) / mul(每级 ×(1+effect)^level)
@export var op: StringName = &"add"
@export var effect_per_level: float = 1.0
@export var base_cost: float = 10.0
@export var growth: float = 1.15
@export var max_level: int = -1
