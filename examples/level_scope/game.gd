extends Node
## 关卡作用域示例的驱动(模拟真实游戏里管理关卡的 Main/Game 节点)。
## 把整条故事串起来:全局默认 → 加载关卡(在作用域内 shadow) → 实体解析+回退 →
## 卸载关卡 → 作用域及其 provide_child 服务自动回收。
##
## 跑法:把 game.tscn 设为主场景运行,或 headless:
##   godot --headless --path . res://examples/level_scope/game.tscn --quit-after 120

const LevelScene := preload("res://examples/level_scope/level.tscn")


func _ready() -> void:
	# 1. 注册一个全局默认(整局可见)。关卡会在自己作用域内 shadow 它。
	CoreKit.provide("difficulty", "global-default")
	CoreKit.log.info("[Game] global difficulty = %s" % CoreKit.service("difficulty"))

	# 2. 加载第 1 关(难度 hard)。add_child 触发 level._ready:注册作用域服务 + spawn 实体。
	var level := LevelScene.instantiate()
	level.name = "Level1"
	level.difficulty = "hard"
	add_child(level)

	# 3. 关卡外解析仍拿全局默认——证明 shadow 只在关卡子树内生效,不污染全局。
	CoreKit.log.info("[Game] outside level, global difficulty still = %s" % CoreKit.service("difficulty"))

	# 4. 卸载关卡 → 作用域 + provide_child 的服务随之回收(树驱动,无需手动清理)。
	var spawner = level.service("spawner")
	CoreKit.log.info("[Game] before unload: spawner valid = %s" % is_instance_valid(spawner))
	level.free()  # 真实代码里通常用 queue_free();此处 free() 便于同帧确定性地看回收结果
	CoreKit.log.info("[Game] after unload:  spawner valid = %s (作用域已随关卡回收)" % is_instance_valid(spawner))
