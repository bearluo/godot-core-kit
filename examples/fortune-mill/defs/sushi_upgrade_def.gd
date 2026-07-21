class_name SushiUpgradeDef
extends Resource
## 寿司房升级定义(.tres schema)。镜像其余房升级 def:一条升级 = 对某 modifier target 的一层贡献。
## 成本几何曲线 base_cost × growth^level。配方解锁不走升级(是 unlock_recipe 独立动作),故本 def 无 unlock kind。

@export var id: StringName
@export var title: String = ""
## 分类(UI 分组):value(ribbon 价值) / speed(制作速度) / automation(自动厨师)
@export var kind: StringName = &"value"
## modifier target:ribbons_per_sushi(单份价值) / craft_speed(制作提速) / auto_chef(自动厨师数)
@export var target: StringName = &"ribbons_per_sushi"
## 修正算子:add(每级 +effect×level) / mul(每级 ×(1+effect)^level)
@export var op: StringName = &"mul"
@export var effect_per_level: float = 0.4
@export var base_cost: float = 30.0
@export var growth: float = 1.35
@export var max_level: int = -1
