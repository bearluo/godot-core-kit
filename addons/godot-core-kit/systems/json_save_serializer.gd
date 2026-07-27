class_name JsonSaveSerializer
extends SaveSerializer
## 默认 JSON 序列化器。与旧 _encode/_decode 逐字节兼容:缩进 "\t"、UTF-8、扩展名 "json"。

func encode(dict: Dictionary) -> PackedByteArray:
	return JSON.stringify(dict, "\t").to_utf8_buffer()

func decode(bytes: PackedByteArray) -> Dictionary:
	# 空/空白字节视为「无存档」直接返回 {}:静态 JSON.parse_string 对空串会
	# push_error(微信小游戏把引擎打印渲染成红色 console.error);实例式 parse 对
	# 畸形输入也只返回错误码、不刷引擎级 ERROR。见 pack_updater._parse_json 同源纪律。
	var text := bytes.get_string_from_utf8()
	if text.strip_edges().is_empty():
		return {}
	var j := JSON.new()
	if j.parse(text) != OK:
		return {}
	var parsed = j.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func extension() -> String:
	return "json"
