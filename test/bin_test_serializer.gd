extends "res://addons/godot-core-kit/systems/save_serializer.gd"
## 测试专用:二进制序列化器,证明 SaveManager 的 serializer 可替换、扩展名随之切换。
## var_to_bytes 保留 int 类型(不像 JSON 会 int->float),allow_objects 默认 false。

func encode(dict: Dictionary) -> PackedByteArray:
	return var_to_bytes(dict)

func decode(bytes: PackedByteArray) -> Dictionary:
	var v = bytes_to_var(bytes)
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	return v

func extension() -> String:
	return "bin"
