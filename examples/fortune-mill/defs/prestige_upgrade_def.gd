class_name PrestigeUpgradeDef
extends Resource
## NG+ 专属升级定义(.tres schema)。只在 NG+(ng_level ≥ 1)可买,花 prestige 点,
## 往某 modifier target 叠一条**跨周目存活**的永久加成(prestige 味)——经共享 KitModifiers
## 求值,故一次施加即放大所有房间;NG+ 重置(_reset_rooms)只清各房自身源,不动 prestige_<id> 源。
##
## 与房间升级 def 同构:add(每级 +effect×level) / mul(每级 ×(1+effect)^level),
## 成本几何曲线 base_cost × growth^level,单位是 prestige 点(非房间货币)。

@export var id: StringName
@export var title: String = ""
## modifier target:global_mul(放大全房) / gold_per_dart / throws_per_sec / ... 任意房共读的 target。
@export var target: StringName = &"global_mul"
## 修正算子:add(每级 +effect×level) / mul(每级 ×(1+effect)^level)
@export var op: StringName = &"mul"
@export var effect_per_level: float = 0.5
## 成本以 prestige 点计(ascend 累积),几何增长。
@export var base_cost: float = 1.0
@export var growth: float = 2.0
@export var max_level: int = -1
