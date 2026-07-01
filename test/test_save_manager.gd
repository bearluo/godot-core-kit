extends SceneTree
## SaveManager headless 断言测试。
##
## 第一部分(必需、disk-free):sanitize/path/encode/decode 纯函数 ——
## 直接实例化脚本,不依赖 autoload、不碰磁盘。
## 第二部分(可选、清晰分区):save/load/has_slot/delete_slot/list_slots
## 的真实磁盘往返,使用一次性 slot 名,结束前清理,不污染上面的纯函数测试。
##
## 运行:godot --headless -s res://test/test_save_manager.gd
##
## 加载注:SaveManagerScript 故意延迟到 _initialize() 内部用 load() 取得,
## 不用类作用域 const X := preload(...)。原因:save_manager.gd 里引用了
## 全局 autoload 标识符 Log(仅用于版本不匹配警告);而 `-s` 入口脚本的
## 类作用域 preload 依赖在 Godot 完成 [autoload] 注册之前就会被编译,
## 此时 Log 尚不是可解析的标识符,会导致 save_manager.gd 编译失败(得到
## 一个损坏的脚本对象,.new() 静默失败/返回错误类型,测试形同虚设却仍
## 打印 ALL PASS)。延迟到 _initialize() 内部 load() 时,autoload 已注册
## 完毕,编译正常。实机验证见 docs/superpowers/plans 对应任务的执行记录。

var SaveManagerScript


## 数值容忍的深度相等:JSON 没有独立的 int 类型,GDScript 的
## JSON.parse_string 会把所有 JSON 数字解析为 float;而 Godot 的
## Dictionary/Array `==` 对容器内元素做严格类型比较(顶层标量 3 == 3.0
## 为 true,但 [3] == [3.0] 为 false)。因此存了 int 的字段磁盘/JSON 往返
## 一圈后,值不变但类型变成 float,若直接用 Dictionary `==` 断言会误报
## "往返不一致"——这不是 save_manager.gd 的 bug,是 JSON 规范决定的,
## _decode 里对 _version 字段特意 int(...) 转型比较也是同一原因。这里用
## 数值容忍的递归比较,同时仍能抓到真正的数据损坏(键缺失/嵌套结构不对/
## 字符串或布尔值不对/数组顺序或长度不对)。
func _values_equal(a, b) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	if (ta == TYPE_INT or ta == TYPE_FLOAT) and (tb == TYPE_INT or tb == TYPE_FLOAT):
		return a == b
	if ta != tb:
		return false
	if ta == TYPE_DICTIONARY:
		if a.size() != b.size():
			return false
		for key in a.keys():
			if not b.has(key) or not _values_equal(a[key], b[key]):
				return false
		return true
	if ta == TYPE_ARRAY:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _values_equal(a[i], b[i]):
				return false
		return true
	return a == b


func _initialize() -> void:
	SaveManagerScript = load("res://addons/godot-core-kit/save_manager.gd")

	var failures := 0
	failures += _test_pure_seams()
	failures += _test_disk_roundtrip()

	if failures == 0:
		print("test_save_manager: ALL PASS")
		quit(0)
	else:
		print("test_save_manager: %d FAILURE(S)" % failures)
		quit(1)


## ============================================================
## 第一部分:纯函数测试(disk-free,不依赖 autoload)
## ============================================================
func _test_pure_seams() -> int:
	var failures := 0
	var sm = SaveManagerScript.new()  # 变量名避开内置 load() 函数关联联想

	# 1. 合法输入原样通过
	if sm._sanitize_slot_name("hero1") != "hero1":
		print("FAIL _sanitize_slot_name('hero1') 应原样返回,得到 '%s'" % sm._sanitize_slot_name("hero1"))
		failures += 1

	# 2. 路径穿越字符被清洗掉,结果只含白名单字符
	var traversal: String = sm._sanitize_slot_name("../../etc/passwd")
	var re_whitelist := RegEx.new()
	re_whitelist.compile("^[A-Za-z0-9_-]+$")
	if traversal.contains("/") or traversal.contains("\\") or traversal.contains("..") or re_whitelist.search(traversal) == null:
		print("FAIL _sanitize_slot_name 路径穿越未清洗干净,得到 '%s'" % traversal)
		failures += 1

	# 3. 空/纯空白输入被拒绝为 "",不回退默认值
	if sm._sanitize_slot_name("") != "":
		print("FAIL _sanitize_slot_name('') 应为 ''")
		failures += 1
	if sm._sanitize_slot_name("   ") != "":
		print("FAIL _sanitize_slot_name('   ') 应为 ''")
		failures += 1

	# 4. _slot_path 是纯字符串拼接,不清洗
	if sm._slot_path("hero1") != "user://saves/hero1.json":
		print("FAIL _slot_path('hero1') 得到 '%s'" % sm._slot_path("hero1"))
		failures += 1

	# 5. 往返:嵌套 dict/array/int/float/string/bool
	var sample := {
		"level": 3,
		"hp": 87.5,
		"name": "hero",
		"alive": true,
		"inventory": ["sword", "shield", 42],
		"stats": {"str": 10, "dex": 7},
	}
	var round_tripped: Dictionary = sm._decode(sm._encode(sample))
	if not _values_equal(round_tripped.get("data"), sample):
		print("FAIL 往返不一致,得到 %s" % [round_tripped.get("data")])
		failures += 1

	# 6. 编码空 dict 后解码,信封非空({} 语义与损坏 sentinel 不冲突)
	var empty_envelope: Dictionary = sm._decode(sm._encode({}))
	if empty_envelope.is_empty():
		print("FAIL _decode(_encode({})) 不应为空信封")
		failures += 1
	if not empty_envelope.has("_version") or not empty_envelope.has("data"):
		print("FAIL _decode(_encode({})) 信封应含 _version 与 data 键")
		failures += 1
	if empty_envelope.get("data") != {}:
		print("FAIL _decode(_encode({})).data 应为 {}")
		failures += 1

	# 7. 非法 JSON 不崩溃,返回 {}
	if sm._decode("not valid json {{{") != {}:
		print("FAIL _decode 对非法 JSON 应返回 {}")
		failures += 1

	# 8. 合法 JSON 但根不是 Dictionary
	if sm._decode("42") != {}:
		print("FAIL _decode('42') 应返回 {}")
		failures += 1

	# 9. 合法 JSON object 但缺少信封键
	if sm._decode("{}") != {}:
		print("FAIL _decode('{}') 应返回 {}(缺少 _version/data)")
		failures += 1

	# 10. data 字段类型不对
	if sm._decode('{"_version":1,"data":"not a dict"}') != {}:
		print("FAIL _decode 对非 Dictionary 的 data 字段应返回 {}")
		failures += 1

	# 11. _encode 输出本身是合法 JSON
	var encoded: String = sm._encode({"a": 1})
	var parsed = JSON.parse_string(encoded)
	if typeof(parsed) != TYPE_DICTIONARY:
		print("FAIL _encode 输出不是合法 JSON: '%s'" % encoded)
		failures += 1

	sm.free()
	return failures


## ============================================================
## 第二部分(可选、磁盘往返,清晰分区,用完清理):save/load/has_slot/
## delete_slot/list_slots 真实走 FileAccess/DirAccess I/O。
## 使用一次性 slot 名,结束前清理,不污染上面的纯函数测试,也不在真实
## 存档目录里留下垃圾文件。
## ============================================================
func _test_disk_roundtrip() -> int:
	var failures := 0
	var sm = SaveManagerScript.new()
	var slot := "__test_save_manager__"
	var path: String = sm._slot_path(slot)

	# 保证起点干净(万一上次异常退出留下文件)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	# save -> has_slot -> load -> list_slots
	var payload := {"score": 42, "name": "tester"}
	if not sm.save(slot, payload):
		print("FAIL save() 应返回 true")
		failures += 1
	if not sm.has_slot(slot):
		print("FAIL has_slot() 保存后应为 true")
		failures += 1
	var loaded_data: Dictionary = sm.load(slot)
	if not _values_equal(loaded_data, payload):
		print("FAIL load() 应返回保存时写入的数据,得到 %s" % [loaded_data])
		failures += 1
	if not sm.list_slots().has(slot):
		print("FAIL list_slots() 应包含 '%s'" % slot)
		failures += 1

	# delete_slot -> 清理后应消失
	if not sm.delete_slot(slot):
		print("FAIL delete_slot() 应返回 true")
		failures += 1
	if sm.has_slot(slot):
		print("FAIL delete_slot() 后 has_slot() 应为 false")
		failures += 1

	# 损坏文件 -> load_failed(reason="corrupt")
	var captured := {"reason": ""}  # 用 Dictionary 当可变"盒子",绕开 lambda 捕获局部量的坑
	var on_load_failed := func(_slot: String, reason: String) -> void:
		captured["reason"] = reason
	sm.load_failed.connect(on_load_failed)
	DirAccess.make_dir_recursive_absolute(SaveManagerScript.SAVE_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not valid json {{{")
	f.close()
	var corrupt_result: Dictionary = sm.load(slot)
	if corrupt_result != {}:
		print("FAIL load() 对损坏文件应返回 {}")
		failures += 1
	if captured["reason"] != "corrupt":
		print("FAIL load_failed reason 应为 'corrupt',得到 '%s'" % captured["reason"])
		failures += 1

	# 清理
	DirAccess.remove_absolute(path)
	sm.free()
	return failures
