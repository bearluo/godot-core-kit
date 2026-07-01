@tool
extends EditorPlugin
## godot-core-kit 编辑器插件入口。
##
## 消费方在「项目设置 > 插件」里启用本插件时，自动把 CoreKit 注册为 autoload；
## 禁用时移除。带幂等判断，避免与开发工程 project.godot 中的预声明重复注册。

const AUTOLOAD_NAME := "CoreKit"
const AUTOLOAD_PATH := "res://addons/godot-core-kit/core_kit.gd"


func _enter_tree() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _exit_tree() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)
