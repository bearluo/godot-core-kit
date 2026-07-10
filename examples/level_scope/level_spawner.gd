extends Node
## 一个关卡专属服务示例(Node 型)。关卡用 provide_child 收养它 → 归关卡管生命周期,
## 关卡 free 时作为子节点连带回收,无需手动清理。
## 若换成 provide("spawner", LevelSpawnerScript.new())(ref-only),则容器只丢引用、
## 不释放这个 Node,得由你自己负责它的生命周期。


func spawn_wave(count: int) -> void:
	CoreKit.log.info("[LevelSpawner] spawning wave of %d" % count)
