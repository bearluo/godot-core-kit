class_name AchievementDef
extends Resource
## 成就定义(.tres schema / 代码构建)。一条成就 = 一个统计阈值:
## 当 KitStats.get_value(stat_key) >= threshold 时解锁(KitAchievements 去重)。
## 统计源全走 KitStats,故任何成就都是「读某计数器到某值」的声明式条件——无需每条写触发代码。

@export var id: StringName
@export var title: String = ""
@export var desc: String = ""
## 判定读的统计键(KitStats 的 key)。
@export var stat_key: StringName
## 达此值即解锁(>=)。
@export var threshold: float = 1.0
## UI 分组用(bullseye / guard / milestone / meta …)。
@export var category: StringName = &"general"
## 隐藏成就(解锁前不剧透 desc);本作占位,UI 可据此打码。
@export var hidden: bool = false
