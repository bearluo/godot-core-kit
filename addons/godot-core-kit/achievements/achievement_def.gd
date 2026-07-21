class_name AchievementDef
extends Resource
## 成就定义(off-facade 数据 schema,`.tres` 可编 / 代码可建)。一条成就 = 一个统计阈值:
## 当被判定的统计源 `get_value(stat_key) >= threshold` 时解锁。声明式——任何成就都是
## 「读某计数器到某值」,无需为每条写触发代码。被 [[kit-achievements]] 的 evaluate 消费。
##
## KitAchievements 只鸭子类型读 id / stat_key / threshold 三个字段,故本类是「推荐 schema」而非
## 强制:游戏可子类化补自定义字段(图标、分组、隐藏标记等),或提供任何带这三字段的对象。

@export var id: StringName
@export var title: String = ""
@export var desc: String = ""
## 判定读的统计键(KitStats 的 key)。
@export var stat_key: StringName
## 达此值即解锁(>=)。
@export var threshold: float = 1.0
## UI 分组用(自定义分类:milestone / combat / meta …)。
@export var category: StringName = &"general"
## 隐藏成就(解锁前不剧透 desc);UI 可据此打码。
@export var hidden: bool = false
