class_name GachaItemDef
extends Resource
## 扭蛋道具定义(.tres schema)。一条道具 = 一个可抽取的收藏品:稀有度 + 抽取权重 + stuffing 产出,
## 外加**被动收集协同**(GACHA 型,第 4 类协同)——持有本道具即往某 target 挂一条被动 add/mul。

@export var id: StringName
@export var title: String = ""
## 稀有度(UI 分组 + 权重):common / rare / epic。非 common 者权重随稀有度权重升级抬高。
@export var rarity: StringName = &"common"
## 基础抽取权重(加权 RNG);rare/epic 实际权重 = weight ×(1 + 0.5 × 稀有度档)。
@export var weight: float = 10.0
## 抽到本道具产出的基础 stuffing(× stuffing_per_pull 聚合 × global_mul)。
@export var stuffing_value: float = 2.0

## 被动收集协同(GACHA 型;三类之外的第 4 类,唯一「收集向」):持有本道具 → 往 target 挂一条
## 被动 modifier(源 gacha_<id>)。持有 n 份:add=value×n / mul=(1+value)^n。越集越强,永久(除 NG+)。
## target 可指向别房产率(如 gold_per_dart)或 global_mul(放大全房)。
@export var target: StringName = &"global_mul"
@export var op: StringName = &"mul"
@export var value_per_copy: float = 0.02
