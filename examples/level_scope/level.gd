extends KitContext
## 关卡根 = 一台 KitContext,作用域 = 这一关的整棵子树。
## 演示:关卡专属服务的注册,以及"关卡卸载即作用域回收"的树驱动生命周期。
##
## 结构说明:KitContext 继承自 Node,所以这里的关卡根是普通 Node。
## 若你的关卡根要用 Node2D(带变换),就别让根 extends KitContext,改为在
## Node2D 根下挂一个 KitContext 子节点、并把关卡内的游戏内容 parent 到它下面——
## 解析同样沿 get_parent() 向上命中那台 KitContext,效果一致。

const EnemyScript := preload("res://examples/level_scope/enemy.gd")
const LevelSpawnerScript := preload("res://examples/level_scope/level_spawner.gd")

## 关卡难度。驱动方在 instantiate 后、add_child 前赋值;_ready 里注册进作用域并 shadow 全局。
@export var difficulty: String = "normal"


func _ready() -> void:
	# 注册关卡专属服务。必须在 spawn 实体之前——实体的 _ready 早于父节点,
	# 若先 spawn 再注册,实体解析时服务还不在,会 miss。
	provide_child("spawner", LevelSpawnerScript.new())               # Node 服务:随本关 free 连带回收
	provide("config", {"difficulty": difficulty, "wave_count": 3})   # 纯数据:只存引用
	provide("difficulty", difficulty)                                # 在本关子树内 shadow 全局 difficulty
	CoreKit.log.info("[%s] scoped services registered (difficulty=%s)" % [name, difficulty])

	# 代码 spawn 一个实体到本关子树内(必须是 KitContext 的后代才能向上解析到本关)。
	var enemy := EnemyScript.new()
	enemy.name = "Enemy1"
	add_child(enemy)
