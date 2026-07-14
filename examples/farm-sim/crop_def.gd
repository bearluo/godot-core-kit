extends Resource
## 农场示例的作物定义(游戏侧自定义数据 Resource)。
## 存进 KitDataRegistry 的 "crop" 类型,由 load_dir 从 data/ 目录批量载入 .tres。
## 说明:这是"游戏侧"的数据结构,不属于 kit;KitDataRegistry 只负责把它按 id 存取——
## 本示例验证"从 Resource 载入配置表"这条链路(load_dir → get_def)。

@export var id: StringName = &""            ## 作物 id = DataRegistry 的键(load_dir 默认取此属性)
@export var display_name: String = ""       ## 展示名
@export var grow_days: int = 3              ## 成熟所需天数(每收到一次 clock:day_changed 长 1)
@export var seed_item: StringName = &""     ## 播种消耗的种子物品 id
@export var harvest_item: StringName = &""  ## 成熟收获的产物物品 id
@export var harvest_amount: int = 1         ## 每株收获数量
