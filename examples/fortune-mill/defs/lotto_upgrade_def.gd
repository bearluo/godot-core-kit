class_name LottoUpgradeDef
extends Resource
## 刮刮乐房升级定义(.tres schema)。镜像 DartUpgradeDef:一条升级 = 对某 modifier
## target 的一层贡献,或(kind==unlock)提升 JACKPOT 权重档。成本几何曲线 base_cost × growth^level。

@export var id: StringName
@export var title: String = ""
## 分类(UI 分组 + LottoRoom 特判):value(卡值) / multi(多卡) / automation(自动刮) / unlock(JACKPOT 权重)
@export var kind: StringName = &"value"
## modifier target(kind==unlock 时忽略):money_per_card / cards_per_scratch / scratches_per_sec
@export var target: StringName = &"money_per_card"
## 修正算子:add(每级 +effect×level) / mul(每级 ×(1+effect)^level)
@export var op: StringName = &"add"
@export var effect_per_level: float = 1.0
@export var base_cost: float = 10.0
@export var growth: float = 1.3
@export var max_level: int = -1
