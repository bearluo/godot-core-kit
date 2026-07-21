class_name GachaUpgradeDef
extends Resource
## 扭蛋房升级定义(.tres schema)。镜像其余房升级 def:一条升级 = 对某 modifier target 的一层贡献,
## 或 unlock 类(改稀有度权重档)。成本几何曲线 base_cost × growth^level。

@export var id: StringName
@export var title: String = ""
## 分类(UI 分组):value(stuffing 价值) / speed(自动抽速) / automation(自动抽卡机) / unlock(稀有度权重)
@export var kind: StringName = &"value"
## modifier target:stuffing_per_pull(单抽价值) / pull_speed(自动抽速) / auto_puller(自动抽卡机数)。
## unlock 类不用 target(改 _rarity_level,抬高 rare/epic 权重)。
@export var target: StringName = &"stuffing_per_pull"
## 修正算子:add(每级 +effect×level) / mul(每级 ×(1+effect)^level)
@export var op: StringName = &"mul"
@export var effect_per_level: float = 0.5
@export var base_cost: float = 30.0
@export var growth: float = 1.4
@export var max_level: int = -1
