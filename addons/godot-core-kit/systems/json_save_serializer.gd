class_name JsonSaveSerializer
extends SaveSerializer
## 默认 JSON 序列化器。与旧 _encode/_decode 逐字节兼容:缩进 "\t"、UTF-8、扩展名 "json"。

func encode(dict: Dictionary) -> PackedByteArray:
	return JSON.stringify(dict, "\t").to_utf8_buffer()

func decode(bytes: PackedByteArray) -> Dictionary:
	var parsed = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func extension() -> String:
	return "json"
