@tool
extends EditorPlugin
## godot-core-kit 编辑器插件入口。
##
## 消费方启用本插件时,按 AUTOLOADS 顺序注册全部 autoload:Log 最先(最底层、
## 零依赖),其后的 EventBus/SceneManager/ObjectPool/SaveManager 各自独立、可引用
## Log,CoreKit 最后。顺序决定初始化顺序,凡引用 Log 的单例都排在 Log 之后。
## 每项带 has_setting 幂等判断,避免与开发工程 project.godot 预声明重复注册。
## 禁用时逆序移除。
##
## 顺序不变式仅对"全新启用"成立:若消费方已部分注册了后续 autoload 而没有 Log
## (如就地跨版本升级),再启用本插件会把 Log 追加到它们之后而破坏顺序。全新安装
## 与本开发工程(project.godot 已按同序预声明全部 autoload)不受影响。

const AUTOLOADS := [
	["Log", "res://addons/godot-core-kit/log.gd"],
	["EventBus", "res://addons/godot-core-kit/event_bus.gd"],
	["SceneManager", "res://addons/godot-core-kit/scene_manager.gd"],
	["ObjectPool", "res://addons/godot-core-kit/object_pool.gd"],
	["SaveManager", "res://addons/godot-core-kit/save_manager.gd"],
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
