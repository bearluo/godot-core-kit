extends RefCounted
## test fixture:供 evaluator 测试绑定的上下文对象(带属性 + 方法)。

var hp: int = 100
var tag: String = "hero"


func greet(who: String) -> String:
	return "hi " + who
