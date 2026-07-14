class_name KitDataRegistry
extends RefCounted
## KitDataRegistry —— 定义数据表(off-facade 类库,游戏 new 并持有,通常
## CoreKit.provide("data", reg) 挂全局服务)。按 type 分组:type(StringName) ->
## { id(StringName) -> def(Resource,游戏自定义子类) }。定义 = 游戏自定义 Resource
## 子类的 .tres(Inspector 可编、类型安全)。register 显式登记;load_dir 扫目录批量。
## 只读目录,不参与存档。零依赖(仅引擎 DirAccess/ResourceLoader)。
##
## 命名:查询用 get_def/has_def(避开引擎原生 Object.get 冲突)。
##
## 用法:
##   var reg := KitDataRegistry.new()
##   reg.load_dir(&"crop", "res://data/crops")      # 扫 *.tres,id 取 def.id 或文件名
##   reg.register(&"item", &"wood", wood_def)
##   var c = reg.get_def(&"crop", &"turnip")
##   CoreKit.provide("data", reg)                    # 挂全局服务(可选)

var _store: Dictionary = {}   # StringName(type) -> Dictionary( StringName(id) -> Variant(def) )


## 显式登记一条定义。已存在同 (type,id) → push_warning 覆盖。
func register(type: StringName, id: StringName, def: Variant) -> void:
	if not _store.has(type):
		_store[type] = {}
	var bucket: Dictionary = _store[type]
	if bucket.has(id):
		push_warning("KitDataRegistry: 覆盖已存在定义 [%s/%s]" % [type, id])
	bucket[id] = def


## 扫 dir_path 下 *.tres / *.res 逐个 load 并按 type 登记。id 取 def 的 id_property 属性
## (存在且非空则用),否则文件名 stem。返回成功登记数。目录打不开 → push_warning + 0。
## 导出坑:导出包里 .tres 可能呈现为 "xxx.tres.remap",自动剥 .remap 再 load。
func load_dir(type: StringName, dir_path: String, id_property: StringName = &"id") -> int:
	var da := DirAccess.open(dir_path)
	if da == null:
		push_warning("KitDataRegistry.load_dir: 无法打开目录 '%s'" % dir_path)
		return 0
	var loaded := 0
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if not da.current_is_dir():
			var fname := entry
			if fname.ends_with(".remap"):
				fname = fname.trim_suffix(".remap")     # 导出包:剥 .remap
			if fname.ends_with(".tres") or fname.ends_with(".res"):
				var res = ResourceLoader.load(dir_path.path_join(fname))
				if res != null:
					register(type, _derive_id(res, fname, id_property), res)
					loaded += 1
				else:
					push_warning("KitDataRegistry.load_dir: 加载失败 '%s'" % fname)
		entry = da.get_next()
	da.list_dir_end()
	return loaded


## 取 (type,id) 定义;缺 → push_warning + null。
func get_def(type: StringName, id: StringName) -> Variant:
	if _store.has(type) and (_store[type] as Dictionary).has(id):
		return _store[type][id]
	push_warning("KitDataRegistry.get_def: 未登记 [%s/%s]" % [type, id])
	return null


## 取 (type,id) 定义;缺 → 返回 fallback,不报错。
func get_def_or(type: StringName, id: StringName, fallback: Variant = null) -> Variant:
	if _store.has(type) and (_store[type] as Dictionary).has(id):
		return _store[type][id]
	return fallback


func has_def(type: StringName, id: StringName) -> bool:
	return _store.has(type) and (_store[type] as Dictionary).has(id)


## 某 type 的全部定义(顺序为插入序);未知 type → []。
func all(type: StringName) -> Array:
	return (_store[type] as Dictionary).values() if _store.has(type) else []


## 某 type 的全部 id(默认插入序)。sorted=true 时按【字符串字典序】返回——StringName
## 数组的原生 sort() 按指针地址排、非字典序,列 UI/日志需稳定字母序时用它。
func ids(type: StringName, sorted := false) -> Array:
	var result: Array = (_store[type] as Dictionary).keys() if _store.has(type) else []
	if sorted:
		result.sort_custom(func(a, b): return String(a) < String(b))
	return result


## 全部已注册 type(默认插入序)。sorted=true 时按字符串字典序(理由同 ids())。
func types(sorted := false) -> Array:
	var result: Array = _store.keys()
	if sorted:
		result.sort_custom(func(a, b): return String(a) < String(b))
	return result


func count(type: StringName) -> int:
	return (_store[type] as Dictionary).size() if _store.has(type) else 0


## 清空某 type(空 type → 清空全部)。
func clear(type: StringName = &"") -> void:
	if String(type).is_empty():
		_store.clear()
	else:
		_store.erase(type)


## 取 def 的 id:res 有 id_property 属性且非空 → StringName(该值);否则文件名 stem。
## 用引擎原生 Object.get(故本类查询方法叫 get_def,不占用 get)。
func _derive_id(res: Variant, fname: String, id_property: StringName) -> StringName:
	if res is Object:
		var v = (res as Object).get(id_property)
		if v != null and String(v) != "":
			return StringName(v)
	return StringName(fname.get_file().get_basename())
