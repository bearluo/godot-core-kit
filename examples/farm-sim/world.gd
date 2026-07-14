extends Node2D
## 农场游戏世界根(P0 视觉切片)。持有农田网格 + 玩家 + HUD;复用 core-kit 的数据(KitDataRegistry/
## KitInventory)与门面(clock/layers/…)。逻辑与表现分离:FarmGrid 管状态、薄 renderer 画占位美术。
##
## 后续 task 在 _ready 里构建 FarmGrid/FarmGridView/Player/TargetHighlight/HUD 并注入依赖。

func _ready() -> void:
	CoreKit.log.info("[World] 农场世界启动")
