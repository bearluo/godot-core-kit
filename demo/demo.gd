extends Node
## 冒烟测试场景：证明 CoreKit autoload 已就绪且可调用。
## 用 Godot 4 打开工程直接运行即可，应在输出看到 CoreKit 的日志。

func _ready() -> void:
	CoreKit.info("demo scene loaded — core-kit is wired up correctly")
