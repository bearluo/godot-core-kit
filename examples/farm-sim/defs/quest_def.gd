extends Resource
## 任务定义(游戏侧数据 Resource)。存进 KitDataRegistry 的 "quest" 类型——把 registry
## 扩到第 3 种类型。任务条件靠订阅游戏事件驱动(见 quest_log.gd),纯数据驱动目标。

@export var id: StringName = &""
@export var title: String = ""
## 条件类型:earn_gold(累计收入≥target) / sell_count(累计卖出 item≥target) / reach_day(day≥target)
@export var kind: StringName = &"earn_gold"
@export var target: int = 1
@export var item: StringName = &""   ## 仅 sell_count 用:限定物品 id(空 = 任意)
