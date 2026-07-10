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
## 全局 autoload 标识符 CoreKit(仅用于版本不匹配警告);而 `-s` 入口脚本的
## 类作用域 preload 依赖在 Godot 完成 [autoload] 注册之前就会被编译,
## 此时 CoreKit 尚不是可解析的标识符,会导致 save_manager.gd 编译失败(得到
## 一个损坏的脚本对象,.new() 静默失败/返回错误类型,测试形同虚设却仍
## 打印 ALL PASS)。延迟到 _initialize() 内部 load() 时,autoload 已注册
## 完毕,编译正常。实机验证见 docs/superpowers/plans 对应任务的执行记录。

var SaveManagerScript
var SaveSerializerScript
var JsonSaveSerializerScript


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
	SaveManagerScript = load("res://addons/godot-core-kit/systems/save_manager.gd")
	SaveSerializerScript = load("res://addons/godot-core-kit/systems/save_serializer.gd")
	JsonSaveSerializerScript = load("res://addons/godot-core-kit/systems/json_save_serializer.gd")

	var failures := 0
	failures += _test_pure_seams()
	failures += _test_serializer()
	failures += _test_envelope_seam()
	failures += _test_serializer_swap()
	failures += _test_atomic_write()
	failures += _test_resource_guard()
	failures += _test_encode_error()
	failures += _test_disk_roundtrip()

	if failures == 0:
		print("test_save_manager: ALL PASS")
		quit(0)
	else:
		print("test_save_manager: %d FAILURE(S)" % failures)
		quit(1)


## ============================================================
## 第一部分:纯函数测试(disk-free,不依赖 autoload)——sanitize / slot_path。
## encode/decode 的直测已迁至 _test_serializer;信封校验迁至 _test_envelope_seam。
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

	# 4. _slot_path 默认(json serializer)为纯字符串拼接,不清洗
	if sm._slot_path("hero1") != "user://saves/hero1.json":
		print("FAIL _slot_path('hero1') 得到 '%s'" % sm._slot_path("hero1"))
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


## ============================================================
## T1: SaveSerializer 基类 + JsonSaveSerializer 直测(承接旧 _encode/_decode 段)。
## 序列化器信封无关:encode/decode 直接吞吐任意 Dictionary,不再包 {_version,data}。
## ============================================================
func _test_serializer() -> int:
	var failures := 0
	var json = JsonSaveSerializerScript.new()

	# 1. 任意纯数据 dict 往返一致(_values_equal 容忍 JSON int->float)
	var sample := {
		"level": 3,
		"hp": 87.5,
		"name": "hero",
		"alive": true,
		"inventory": ["sword", "shield", 42],
		"stats": {"str": 10, "dex": 7},
	}
	if not _values_equal(json.decode(json.encode(sample)), sample):
		print("FAIL JsonSaveSerializer 往返不一致,得到 %s" % [json.decode(json.encode(sample))])
		failures += 1

	# 2. 空 dict:encode 非空字节、decode 回空 dict(不再包信封)
	if json.encode({}).is_empty():
		print("FAIL JsonSaveSerializer.encode({}) 不应为空字节")
		failures += 1
	if json.decode(json.encode({})) != {}:
		print("FAIL JsonSaveSerializer.decode(encode({})) 应为 {}")
		failures += 1

	# 3. 非法字节 -> {}
	if json.decode("not valid json {{{".to_utf8_buffer()) != {}:
		print("FAIL JsonSaveSerializer.decode(非法字节) 应为 {}")
		failures += 1

	# 4. 合法 JSON 但根非字典 -> {}
	if json.decode("42".to_utf8_buffer()) != {}:
		print("FAIL JsonSaveSerializer.decode('42') 应为 {}")
		failures += 1

	# 5. extension
	if json.extension() != "json":
		print("FAIL JsonSaveSerializer.extension() 应为 'json',得到 '%s'" % json.extension())
		failures += 1

	# 6. 字节兼容:encode(信封) 逐字节 == 旧 store_string 路径的 UTF-8 字节(锁 back-compat)
	var env := {"_version": 1, "data": {"a": 1}}
	if json.encode(env) != JSON.stringify(env, "\t").to_utf8_buffer():
		print("FAIL JsonSaveSerializer.encode 应等价 JSON.stringify(env, tab).to_utf8_buffer()")
		failures += 1

	# 7. 抽象基类:未覆写返回空/默认(不崩溃)
	var base = SaveSerializerScript.new()
	if not base.encode({}).is_empty():
		print("FAIL SaveSerializer.encode 抽象基类应返回空字节")
		failures += 1
	if base.decode(PackedByteArray()) != {}:
		print("FAIL SaveSerializer.decode 抽象基类应返回 {}")
		failures += 1
	if base.extension() != "":
		print("FAIL SaveSerializer.extension 抽象基类应返回 ''")
		failures += 1

	return failures


## ============================================================
## T2: 信封校验接缝 _is_valid_envelope(承接旧 _decode 的 has/类型检查那段)。
## ============================================================
func _test_envelope_seam() -> int:
	var failures := 0
	var sm = SaveManagerScript.new()

	if not sm._is_valid_envelope({"_version": 1, "data": {}}):
		print("FAIL _is_valid_envelope 合法信封应为 true")
		failures += 1
	if sm._is_valid_envelope({}):
		print("FAIL _is_valid_envelope 缺键应为 false")
		failures += 1
	if sm._is_valid_envelope({"_version": 1}):
		print("FAIL _is_valid_envelope 缺 data 应为 false")
		failures += 1
	if sm._is_valid_envelope({"_version": {}, "data": {}}):
		print("FAIL _is_valid_envelope 非标量 _version 应为 false")
		failures += 1
	if sm._is_valid_envelope({"_version": 1, "data": "not a dict"}):
		print("FAIL _is_valid_envelope 非字典 data 应为 false")
		failures += 1

	sm.free()
	return failures


## ============================================================
## T2: 注入非默认 serializer(.bin)后 save/load 往返 + list_slots 只见当前扩展名。
## ============================================================
func _test_serializer_swap() -> int:
	var failures := 0
	var sm = SaveManagerScript.new()
	var slot := "__test_swap__"

	# 先用默认(json)存一个同名槽,稍后证明换到 .bin 后 list_slots 不再列它
	var json_path: String = sm._slot_path(slot)   # user://saves/<slot>.json
	if FileAccess.file_exists(json_path):
		DirAccess.remove_absolute(json_path)
	sm.save(slot, {"fmt": "json"})

	# 换到 .bin serializer
	var bin = load("res://test/bin_test_serializer.gd").new()
	sm.set_serializer(bin)

	# 换后 _slot_path 扩展名随之变化
	var bin_path: String = sm._slot_path(slot)
	if not bin_path.ends_with(".bin"):
		print("FAIL 换 serializer 后 _slot_path 应以 .bin 结尾,得到 '%s'" % bin_path)
		failures += 1

	# save->load 往返数据一致
	var payload := {"score": 7, "tag": "bin"}
	if not sm.save(slot, payload):
		print("FAIL 换 serializer 后 save 应为 true")
		failures += 1
	if not _values_equal(sm.load(slot), payload):
		print("FAIL 换 serializer 后 load 往返不一致,得到 %s" % [sm.load(slot)])
		failures += 1

	# list_slots 现按 .bin 过滤:含本槽(各 serializer 管自己扩展名)
	if not sm.list_slots().has(slot):
		print("FAIL 换 serializer 后 list_slots 应含 '%s'(.bin)" % slot)
		failures += 1

	# 换回默认 json:list_slots 又能看见 .json 槽(证明按扩展名隔离,而非删了文件)
	sm.set_serializer(JsonSaveSerializerScript.new())
	if not sm.list_slots().has(slot):
		print("FAIL 换回 json 后 list_slots 应重新含 '%s'(.json)" % slot)
		failures += 1

	# set_serializer(null) 被拒:_slot_path 仍是 .json
	sm.set_serializer(null)
	if not sm._slot_path(slot).ends_with(".json"):
		print("FAIL set_serializer(null) 应被拒,_slot_path 仍应 .json")
		failures += 1

	# 清理两个格式的文件
	if FileAccess.file_exists(json_path):
		DirAccess.remove_absolute(json_path)
	if FileAccess.file_exists(bin_path):
		DirAccess.remove_absolute(bin_path)
	sm.free()
	return failures


## ============================================================
## T2(补,回应 task-review Important):encode 返回空字节 → save_failed('encode_error')、
## 返回 false、不落盘。补齐新增 encode_error reason 的分支覆盖。
## ============================================================
func _test_encode_error() -> int:
	var failures := 0
	var sm = SaveManagerScript.new()
	var empty_ser = load("res://test/empty_encode_serializer.gd").new()
	sm.set_serializer(empty_ser)
	var slot := "__test_encode_error__"
	var path: String = sm._slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var captured := {"reason": ""}
	var on_fail := func(_s: String, reason: String) -> void: captured["reason"] = reason
	sm.save_failed.connect(on_fail)
	var ok: bool = sm.save(slot, {"a": 1})
	sm.save_failed.disconnect(on_fail)
	if ok:
		print("FAIL encode 空字节时 save 应返回 false")
		failures += 1
	if captured["reason"] != "encode_error":
		print("FAIL save_failed reason 应为 'encode_error',得到 '%s'" % captured["reason"])
		failures += 1
	if FileAccess.file_exists(path):
		print("FAIL encode_error 时不应落盘")
		failures += 1
	sm.free()
	return failures


## ============================================================
## T3: 原子写——成功不留 tmp;_atomic_replace 成功/覆盖两路径;rename 失败清理 + rename_error。
## rename 失败用"目标名被非空目录占位"确定性构造(已实测:rename 到目录失败,
## FileAccess.file_exists(目录)=false -> 回退分支不触发 -> _atomic_replace 返回 false)。
## ============================================================
func _test_atomic_write() -> int:
	var failures := 0
	var sm = SaveManagerScript.new()
	var slot := "__test_atomic__"
	var target: String = sm._slot_path(slot)
	var tmp := target + ".tmp"

	# 起点干净
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)

	# 成功路径:save 后 tmp 不残留、目标存在且可完整 load、list_slots 含本槽
	if not sm.save(slot, {"n": 1}):
		print("FAIL 原子写 save 应为 true")
		failures += 1
	if FileAccess.file_exists(tmp):
		print("FAIL save 成功后不应残留 tmp 文件")
		failures += 1
	if not FileAccess.file_exists(target):
		print("FAIL save 成功后目标文件应存在")
		failures += 1
	if not _values_equal(sm.load(slot), {"n": 1}):
		print("FAIL 原子写后 load 应完整")
		failures += 1
	if not sm.list_slots().has(slot):
		print("FAIL 原子写后 list_slots 应含 '%s'" % slot)
		failures += 1
	DirAccess.remove_absolute(target)

	# _atomic_replace 直测——目标不存在 -> true、tmp 消失、目标为源内容
	var a_src: String = SaveManagerScript.SAVE_DIR + "/__ar_src__.tmp"
	var a_dst: String = SaveManagerScript.SAVE_DIR + "/__ar_dst__.dat"
	DirAccess.make_dir_recursive_absolute(SaveManagerScript.SAVE_DIR)
	var wf := FileAccess.open(a_src, FileAccess.WRITE)
	wf.store_string("NEW")
	wf.close()
	if not sm._atomic_replace(a_src, a_dst):
		print("FAIL _atomic_replace 目标不存在应为 true")
		failures += 1
	if FileAccess.file_exists(a_src) or not FileAccess.file_exists(a_dst):
		print("FAIL _atomic_replace 后 tmp 应消失、目标应存在")
		failures += 1

	# _atomic_replace 覆盖——目标已存在(旧)-> true 且内容为新
	var wf2 := FileAccess.open(a_src, FileAccess.WRITE)
	wf2.store_string("NEWER")
	wf2.close()
	if not sm._atomic_replace(a_src, a_dst):
		print("FAIL _atomic_replace 覆盖应为 true")
		failures += 1
	var rf := FileAccess.open(a_dst, FileAccess.READ)
	var got := rf.get_as_text()
	rf.close()
	if got != "NEWER":
		print("FAIL _atomic_replace 覆盖后内容应为 'NEWER',得到 '%s'" % got)
		failures += 1
	DirAccess.remove_absolute(a_dst)

	# rename 失败:目标名被非空目录占位 -> save_failed('rename_error')、false、tmp 清理
	var slot2 := "__test_rename_fail__"
	var target2: String = sm._slot_path(slot2)   # user://saves/<slot2>.json
	var tmp2 := target2 + ".tmp"
	DirAccess.make_dir_recursive_absolute(target2)          # 用目标名建目录
	var inner := FileAccess.open(target2 + "/inner.txt", FileAccess.WRITE)
	inner.store_string("x")                                  # 让目录非空
	inner.close()
	var captured := {"reason": ""}
	var on_fail := func(_s: String, reason: String) -> void: captured["reason"] = reason
	sm.save_failed.connect(on_fail)
	var ok2: bool = sm.save(slot2, {"n": 2})
	sm.save_failed.disconnect(on_fail)
	if ok2:
		print("FAIL 目标被目录占位时 save 应返回 false")
		failures += 1
	if captured["reason"] != "rename_error":
		print("FAIL save_failed reason 应为 'rename_error',得到 '%s'" % captured["reason"])
		failures += 1
	if FileAccess.file_exists(tmp2):
		print("FAIL rename 失败后应清理 tmp")
		failures += 1
	# 清理占位目录
	if FileAccess.file_exists(target2 + "/inner.txt"):
		DirAccess.remove_absolute(target2 + "/inner.txt")
	DirAccess.remove_absolute(target2)
	sm.free()
	return failures


## ============================================================
## T4: 资源引用安全守卫 _has_unserializable + save 拒 Object/Callable/嵌套。
## Resource.new() 为 TYPE_OBJECT;func():pass 为 TYPE_CALLABLE。
## ============================================================
func _test_resource_guard() -> int:
	var failures := 0
	var sm = SaveManagerScript.new()

	# 纯函数:纯数据 false;含 Object/Callable/嵌套 true
	if sm._has_unserializable({"a": 1, "b": ["x", 2, {"c": true}]}):
		print("FAIL _has_unserializable 纯数据应为 false")
		failures += 1
	if not sm._has_unserializable({"res": Resource.new()}):
		print("FAIL _has_unserializable 含 Resource 应为 true")
		failures += 1
	if not sm._has_unserializable({"bag": [Resource.new()]}):
		print("FAIL _has_unserializable 嵌套 Array 中 Resource 应为 true")
		failures += 1
	if not sm._has_unserializable({"cb": func() -> void: pass}):
		print("FAIL _has_unserializable 含 Callable 应为 true")
		failures += 1

	# save 拒:命中守卫 -> false、save_failed('unserializable')、不落盘
	var slot := "__test_guard__"
	var path: String = sm._slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var captured := {"reason": ""}
	var on_fail := func(_s: String, reason: String) -> void: captured["reason"] = reason
	sm.save_failed.connect(on_fail)
	var ok: bool = sm.save(slot, {"res": Resource.new()})
	sm.save_failed.disconnect(on_fail)
	if ok:
		print("FAIL 含 Resource 的 save 应返回 false")
		failures += 1
	if captured["reason"] != "unserializable":
		print("FAIL save_failed reason 应为 'unserializable',得到 '%s'" % captured["reason"])
		failures += 1
	if FileAccess.file_exists(path):
		print("FAIL 守卫命中时不应落盘")
		failures += 1

	sm.free()
	return failures
