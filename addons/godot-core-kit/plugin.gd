@tool
extends EditorPlugin
## godot-core-kit 编辑器插件入口。
##
## 消费方启用本插件时,按顺序注册 autoload:先 Log(最底层、零依赖),
## 再 CoreKit(依赖 Log)。顺序决定初始化顺序,CoreKit._ready() 会用到 Log。
## 每项带 has_setting 幂等判断,避免与开发工程 project.godot 预声明重复注册。
## 禁用时逆序移除。
##
## 顺序不变式仅对"全新启用"成立:若消费方已单独注册了 CoreKit 而没有 Log
## (如 0.1.0 就地升级到 0.2.0),再启用本插件会把 Log 追加到 CoreKit 之后而
## 破坏顺序。全新安装与本开发工程(两者都预声明了两个 autoload)不受影响。

const AUTOLOADS := [
	["Log", "res://addons/godot-core-kit/log.gd"],
	["CoreKit", "res://addons/godot-core-kit/core_kit.gd"],
]


func _enter_tree() -> void:
	for entry in AUTOLOADS:
		var autoload_name: String = entry[0]
		var autoload_path: String = entry[1]
		if not ProjectSettings.has_setting("autoload/" + autoload_name):
			add_autoload_singleton(autoload_name, autoload_path)


func _exit_tree() -> void:
	for i in range(AUTOLOADS.size() - 1, -1, -1):
		var autoload_name: String = AUTOLOADS[i][0]
		if ProjectSettings.has_setting("autoload/" + autoload_name):
			remove_autoload_singleton(autoload_name)
