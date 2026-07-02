@tool
extends EditorPlugin
## godot-core-kit 编辑器插件入口。
## v0.4.0 起只注册一个 autoload:CoreKit(门面),全部子系统由它内部构造,
## 初始化顺序完全内控。从 0.3.x 升级的工程需手动移除旧的 Log/EventBus/
## SceneManager/ObjectPool/SaveManager 五项 autoload 注册(见 README 迁移一节)。

const AUTOLOAD_NAME := "CoreKit"
const AUTOLOAD_PATH := "res://addons/godot-core-kit/core_kit.gd"


func _enter_tree() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _exit_tree() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)
