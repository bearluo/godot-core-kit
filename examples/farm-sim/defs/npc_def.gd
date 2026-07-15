extends Resource
## NPC 定义(游戏侧数据 Resource,P3)。存进 KitDataRegistry 的 "npc" 类型(registry 第 5 类型),
## 由 load_dir 从 data/npcs/ 批量载入 .tres。数据驱动:加 NPC = 加一份 .tres,无需改代码。
##
## schedule:轻量日程,[{after_hour:int, area:StringName, x:int, y:int}, ...]。按当前 hour 取
## **最后一个 after_hour <= hour** 的项决定该 NPC 此刻在哪个区、站哪格(假定按 after_hour 升序)。
## 不做寻路移动动画(占位:换站位)。gift_*/unlock_* 供 P5 送礼好感 / P6 好感解锁。

@export var id: StringName = &""             ## NPC id = DataRegistry 的键
@export var display_name: String = ""        ## 展示名(头顶 Label)
@export var home_area: StringName = &"town"  ## 常驻区域(town/house/farm)
@export var schedule: Array = []             ## 轻量日程 [{after_hour, area, x, y}]
@export var dialogue: Array = []             ## 闲聊台词(String);对话轮流推进
@export var gift_loved: Array = []           ## 爱的物品 id(送礼 +大)
@export var gift_liked: Array = []           ## 喜欢(+小)
@export var gift_disliked: Array = []        ## 讨厌(-)
@export var unlock_at: int = 0               ## 好感阈值(点数);达到发 unlock_item
@export var unlock_item: StringName = &""    ## 达阈值发放的物品(如特殊种子);空=无解锁
