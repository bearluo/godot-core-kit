extends SceneTree
## KitDataRegistry headless 断言。RefCounted,直接 load().new()。register/查询用任意
## Variant def(免造 .tres);load_dir 用运行时 ResourceSaver 造临时 .tres 到 user://。
## 运行:godot --headless --path . -s res://test/test_kit_data_registry.gd

var Reg
var Def


func _initialize() -> void:
	Reg = load("res://addons/godot-core-kit/data/kit_data_registry.gd")
	Def = load("res://test/fixtures/test_data_def.gd")
	var failures := 0

	var r = Reg.new()

	# 1. register + get_def
	r.register(&"item", &"wood", {"n": 1})
	if r.get_def(&"item", &"wood") != {"n": 1}:
		print("FAIL 1: register/get_def 失败"); failures += 1

	# 2. has_def
	if not r.has_def(&"item", &"wood") or r.has_def(&"item", &"gold") or r.has_def(&"crop", &"x"):
		print("FAIL 2: has_def 判定错"); failures += 1

	# 3. 缺失 get_def -> null(push_warning)
	if r.get_def(&"item", &"gold") != null:
		print("FAIL 3: 缺失 get_def 应 null"); failures += 1

	# 4. get_def_or fallback
	if r.get_def_or(&"item", &"gold", 42) != 42:
		print("FAIL 4: get_def_or 应返回 fallback"); failures += 1

	# 5. 覆盖(push_warning)
	r.register(&"item", &"wood", {"n": 2})
	if r.get_def(&"item", &"wood") != {"n": 2}:
		print("FAIL 5: register 覆盖应更新值"); failures += 1

	# 6. all/ids/count/types
	r.register(&"item", &"stone", {"n": 3})
	if r.count(&"item") != 2 or r.ids(&"item").size() != 2 or r.all(&"item").size() != 2 or not (&"item" in r.types()):
		print("FAIL 6: all/ids/count/types 错"); failures += 1
	if not (&"wood" in r.ids(&"item")) or not (&"stone" in r.ids(&"item")):
		print("FAIL 6: ids 应含 wood/stone"); failures += 1

	# 7. clear(type) / clear()
	r.register(&"crop", &"turnip", {"g": 4})
	r.clear(&"item")
	if r.count(&"item") != 0 or r.count(&"crop") != 1:
		print("FAIL 7: clear(item) 应只清 item"); failures += 1
	r.clear()
	if r.types().size() != 0:
		print("FAIL 7: clear() 应清全部"); failures += 1

	# 8. load_dir 载入(造临时 .tres:turnip 带属性 id / potato 取文件名)
	var dir := "user://test_registry"
	DirAccess.make_dir_recursive_absolute(dir)
	var d1 = Def.new(); d1.id = &"turnip"; d1.max_stack = 99
	ResourceSaver.save(d1, dir + "/turnip.tres")
	var d2 = Def.new()  # 不设 id -> 取文件名 potato
	ResourceSaver.save(d2, dir + "/potato.tres")
	var r2 = Reg.new()
	var loaded = r2.load_dir(&"crop", dir)
	if loaded != 2 or not r2.has_def(&"crop", &"turnip") or not r2.has_def(&"crop", &"potato"):
		print("FAIL 8: load_dir 应载入 2 条,实际 %d" % loaded); failures += 1
	var cd = r2.get_def(&"crop", &"turnip")
	if cd == null or cd.max_stack != 99:
		print("FAIL 8: load_dir 载入的 def.max_stack 应 99"); failures += 1
	DirAccess.remove_absolute(dir + "/turnip.tres")
	DirAccess.remove_absolute(dir + "/potato.tres")
	DirAccess.remove_absolute(dir)

	# 9. load_dir 坏路径
	if Reg.new().load_dir(&"x", "res://__nope__") != 0:
		print("FAIL 9: 坏路径 load_dir 应返 0"); failures += 1

	if failures == 0:
		print("test_kit_data_registry: ALL PASS")
		quit(0)
	else:
		print("test_kit_data_registry: %d FAILURE(S)" % failures)
		quit(1)
