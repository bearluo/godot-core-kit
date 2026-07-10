class_name SaveSerializer
extends RefCounted
## 存档序列化策略抽象基类(off-facade 类库,不挂门面)。只负责 Dictionary <-> 字节的
## 转换;信封 {_version, data} 与版本校验由 SaveManager 负责,序列化器不感知其结构。
## 子类必须覆写全部三个方法。

## Dictionary -> 字节。子类必须覆写。
func encode(dict: Dictionary) -> PackedByteArray:
	push_error("SaveSerializer.encode 未覆写(抽象基类)")
	return PackedByteArray()

## 字节 -> Dictionary。格式解析失败(非法字节 / 根非字典)返回 {}(损坏契约)。子类必须覆写。
func decode(bytes: PackedByteArray) -> Dictionary:
	push_error("SaveSerializer.decode 未覆写(抽象基类)")
	return {}

## 该格式的文件扩展名(不含点,如 "json" / "bin")。子类必须覆写。
func extension() -> String:
	push_error("SaveSerializer.extension 未覆写(抽象基类)")
	return ""
