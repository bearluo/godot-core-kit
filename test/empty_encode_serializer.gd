extends "res://addons/godot-core-kit/systems/save_serializer.gd"
## 测试专用:encode 恒返回空 PackedByteArray,用于触发 SaveManager 的 encode_error 分支。

func encode(_dict: Dictionary) -> PackedByteArray:
	return PackedByteArray()

func decode(_bytes: PackedByteArray) -> Dictionary:
	return {}

func extension() -> String:
	return "dat"
