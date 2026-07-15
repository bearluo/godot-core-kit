extends Node
## 温室气候 = 一个【作用域 Node 服务】。由温室的 KitContext 经 provide_child("climate", self)
## 收养——生命周期归容器:温室 free 时本节点连带释放(见 _exit_tree 日志),这正是 provide_child
## 相对 provide(只存引用、不管生命周期)的区别。
##
## dogfood 点:KitContext.provide_child 的 Node 型作用域服务 + 随容器释放的生命周期。

var growth_bonus := 2   ## 温室恒温:作物额外生长加成(仅温室作用域内的作物能 resolve 到)


func _exit_tree() -> void:
	CoreKit.log.info("[Greenhouse] Climate 服务随温室作用域释放(provide_child 生命周期)")
