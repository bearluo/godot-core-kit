extends Resource
## 农场示例的物品定义(游戏侧数据 Resource)。与 crop_def 同存进一个 KitDataRegistry,
## 但归 "item" 类型——演示同一个 registry **承载多种类型**(crop + item 各一张表)。
## 物品的堆叠上限 max_stack 由数据表驱动:背包 add 时按此表取单格上限,而非硬编码。

@export var id: StringName = &""             ## 物品 id = registry 键
@export var display_name: String = ""        ## 展示名
@export var max_stack: int = 99             ## 背包单格堆叠上限(数据驱动)
@export var category: StringName = &"misc"   ## seed / produce / misc
