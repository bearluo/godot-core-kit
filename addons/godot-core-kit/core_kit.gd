extends Node
## godot-core-kit 运行时全局入口(骨架示例)。
##
## 以 autoload "CoreKit" 注册。日志统一走 Log 单例(在 CoreKit 之前初始化)。
## 各通用基础子系统(EventBus / SceneManager / ObjectPool / SaveManager)均为
## 各自独立的 autoload、互不依赖,不从 CoreKit 挂接;CoreKit 仅作运行时入口与版本标识。

const VERSION := "0.3.0"


func _ready() -> void:
	Log.info("CoreKit v%s ready" % VERSION)
