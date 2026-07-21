class_name PachinkoUpgradeDef
extends Resource
## 柏青哥房升级定义(.tres schema)。镜像 LottoUpgradeDef:一条升级 = 对某 modifier target
## 的一层贡献,或(kind==unlock)提升骰子频率档。成本几何曲线 base_cost × growth^level。

@export var id: StringName
@export var title: String = ""
## 分类(UI 分组 + PachinkoRoom 特判):value(球值) / multi(多球) / automation(自动落球) / unlock(骰子频率)
@export var kind: StringName = &"value"
## modifier target(kind==unlock 时忽略):tickets_per_ball / balls_per_drop / drops_per_sec
@export var target: StringName = &"tickets_per_ball"
## 修正算子:add(每级 +effect×level) / mul(每级 ×(1+effect)^level)
@export var op: StringName = &"add"
@export var effect_per_level: float = 1.0
@export var base_cost: float = 10.0
@export var growth: float = 1.3
@export var max_level: int = -1
