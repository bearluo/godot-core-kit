extends Node
## godot-core-kit 运行时全局入口（骨架示例）。
##
## 以 autoload "CoreKit" 注册，游戏项目里可直接使用，例如 `CoreKit.VERSION`、
## `CoreKit.info("...")`。后续的通用基础子系统（日志、事件总线、场景管理、
## 对象池、存档等）都从这里挂接。

const VERSION := "0.1.0"


func _ready() -> void:
	info("v%s ready" % VERSION)


## 骨架占位方法：统一日志出口。后续会替换为正式的 Logger 子系统。
func info(message: String) -> void:
	print("[CoreKit] %s" % message)
