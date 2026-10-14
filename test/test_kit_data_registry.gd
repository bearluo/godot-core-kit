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

	# 10. ids/types 排序变体(String 字典序,不受 StringName 指针序影响)
	var rs = Reg.new()
	rs.register(&"zeta", &"b", 1)
	rs.register(&"alpha", &"c", 1)
	rs.register(&"alpha", &"a", 1)
	if rs.ids(&"alpha", true) != [&"a", &"c"]:
		print("FAIL 10: ids sorted 应 [a, c],实际 %s" % str(rs.ids(&"alpha", true))); failures += 1
	if rs.types(true) != [&"alpha", &"zeta"]:
		print("FAIL 10: types sorted 应 [alpha, zeta],实际 %s" % str(rs.types(true))); failures += 1
	if rs.ids(&"alpha").size() != 2:
		print("FAIL 10: ids 默认应含 2 项"); failures += 1

	# 11. register_records 正常一批:返回条数;存只读副本;改原字典不影响登记值
	var rr = Reg.new()
	var src := [{"id": "turnip", "price": 10}, {"id": "potato", "price": 5}]
	if rr.register_records(&"crop", src) != 2:
		print("FAIL 11: 应登记 2 条"); failures += 1
	var tv = rr.get_def(&"crop", &"turnip")
	if tv != {"id": "turnip", "price": 10} or not (tv as Dictionary).is_read_only():
		print("FAIL 11: 登记值应等于原记录且只读,实际 %s" % str(tv)); failures += 1
	src[0]["price"] = 999
	if rr.get_def(&"crop", &"turnip")["price"] != 10:
		print("FAIL 11: 改调用方原字典不应影响登记值"); failures += 1
	if rr.get_def(&"crop", &"turnip").price != 10:
		print("FAIL 11: 字典定义应支持点号读取"); failures += 1

	# 12. 跳过:非字典 / 缺 id / id 为空 / id 为 null;只计成功
	var bad := [{"id": "ok"}, 42, {"price": 1}, {"id": ""}, {"id": null}]
	if rr.register_records(&"bad", bad) != 1 or rr.count(&"bad") != 1:
		print("FAIL 12: 坏记录应跳过,只计 1 条成功"); failures += 1

	# 13. 数字 id 转 StringName;自定义 id_key;StringName 键
	rr.register_records(&"num", [{"id": 101, "n": 1}])
	if not rr.has_def(&"num", &"101"):
		print("FAIL 13: 数字 id 101 应能用 &\"101\" 查到"); failures += 1
	rr.register_records(&"sku", [{"code": "A1"}, {&"code": "B2"}], &"code")
	if not rr.has_def(&"sku", &"A1") or not rr.has_def(&"sku", &"B2"):
		print("FAIL 13: 自定义 id_key(含 StringName 键)应生效"); failures += 1

	# 14. factory:返回 Resource 存它;返回 null 跳过
	var mk := func(rec: Dictionary):
		if rec.get("skip", false):
			return null
		var dd = Def.new(); dd.max_stack = rec["max"]; return dd
	var nf: int = rr.register_records(&"fac", [{"id": "a", "max": 7}, {"id": "b", "skip": true}], &"id", mk)
	var fa = rr.get_def_or(&"fac", &"a")
	if nf != 1 or not (fa is Resource) or fa.max_stack != 7 or rr.has_def(&"fac", &"b"):
		print("FAIL 14: factory 结果应原样存、null 跳过,n=%d" % nf); failures += 1

	# 15. 重复 id:后者覆盖(与 register 一致),两条都算成功
	if rr.register_records(&"dup", [{"id": "x", "v": 1}, {"id": "x", "v": 2}]) != 2 \
			or rr.count(&"dup") != 1 or rr.get_def(&"dup", &"x")["v"] != 2:
		print("FAIL 15: 重复 id 应覆盖为后者"); failures += 1

	# 16. records 不是 Array(如 JSON 解析失败的 null)→ 告警返回 0
	if rr.register_records(&"j", null) != 0 or rr.register_records(&"j", {"id": "x"}) != 0:
		print("FAIL 16: 非 Array 输入应返回 0"); failures += 1

	if failures == 0:
		print("test_kit_data_registry: ALL PASS")
		quit(0)
	else:
		print("test_kit_data_registry: %d FAILURE(S)" % failures)
		quit(1)
