extends Node
## godot-core-kit 运行时全局入口(骨架示例)。
##
## 以 autoload "CoreKit" 注册。日志统一走 Log 单例(在 CoreKit 之前初始化)。
## 后续通用基础子系统(事件总线、场景管理、对象池、存档等)都从这里挂接。

const VERSION := "0.2.0"


func _ready() -> void:
	Log.info("CoreKit v%s ready" % VERSION)
