extends Resource
## 成就定义(游戏侧数据 Resource)。存进 KitDataRegistry 的 "achievement" 类型——把 registry
## 扩到第 4 种类型。成就是账号级里程碑:解锁进 CoreKit.settings(不进存档槽),条件靠订阅
## 游戏事件驱动(见 achievement_tracker.gd)。与"任务"对照:任务=每档进度、进存档;成就=账号解锁、进 settings。

@export var id: StringName = &""
@export var title: String = ""
## 条件类型:first_purchase(首次 shop:bought) / all_quests(完成任务数≥target) / rain_dancer(遇到雨天)
@export var kind: StringName = &"first_purchase"
@export var target: int = 1   ## 仅 all_quests 用:需完成的任务数
