extends Node
## 冒烟测试场景:证明 Log 与 CoreKit autoload 已就绪且可调用。
## 用 Godot 4 打开工程直接运行即可,应在输出看到 Log 的彩色分级日志。

func _ready() -> void:
	Log.info("demo scene loaded — core-kit is wired up correctly")
