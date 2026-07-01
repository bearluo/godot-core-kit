extends Node
## ObjectPool 测试专用 fixture:探测 _pool_reset() 的调用次数与时机。
## 挂到一个 trivial 场景的根节点上,由 test_object_pool.gd 用于验证:
## prewarm 阶段不触发 _pool_reset();release() 归还时恰好触发一次。

var reset_calls := 0


func _pool_reset() -> void:
	reset_calls += 1
