class_name SushiRecipeDef
extends Resource
## 寿司配方定义(.tres schema)。一条配方 = 一道可制作的寿司:制作时长 + 食材消耗 + ribbon 产出,
## 外加(可选)解锁式开关协同——高级配方解锁时往**别房** target 注册一条永久 modifier(SUSHI 规则开关型)。

@export var id: StringName
@export var title: String = ""
## 制作时长(秒);实际时长 = craft_time / craft_speed 聚合(制作速度升级缩短)。
@export var craft_time: float = 3.0
## 单份寿司基础 ribbons(× ribbons_per_sushi 聚合 × global_mul)。
@export var ribbon_value: float = 5.0
## 消耗食材 id(空 = 无需食材);start_craft 从食材柜 KitInventory 扣 ingredient_count 个。
@export var ingredient: StringName = &""
@export var ingredient_count: int = 0
## 开局即解锁(基础配方);其余需 unlock_recipe 花 ribbons 解锁。
@export var unlocked_by_default: bool = false
@export var unlock_cost: float = 0.0

## 解锁式开关协同(SUSHI 型;三类协同里唯一「规则开关」):switch_target 非空 → 本配方解锁时
## 往该 target 注册一条永久 modifier(源 sushi_<id>),如 throws_per_sec ×2「飞镖自动投速翻倍」。
@export var switch_target: StringName = &""
@export var switch_op: StringName = &"mul"
@export var switch_value: float = 1.0
