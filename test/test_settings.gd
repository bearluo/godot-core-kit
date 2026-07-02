extends SceneTree
## Settings headless 断言测试(直接实例化脚本,不依赖门面接线)。
## 运行:godot --headless --path . -s res://test/test_settings.gd
##
## 加载注:settings.gd 运行期引用全局 autoload 标识符 CoreKit(落盘失败时
## CoreKit.log.error),故不在类作用域 preload,延迟到 _initialize() 内 load()
## (此时 autoload 已注册)。settings_path 接缝重定向到一次性测试文件,
## 不碰真实 user://settings.json(那是 CoreKit 门面实例在用的真文件)。

var SettingsScript

const TEST_PATH := "user://__test_settings__.json"


func _make():
	var s = SettingsScript.new()
	s.settings_path = TEST_PATH
	return s


func _initialize() -> void:
	SettingsScript = load("res://addons/godot-core-kit/settings.gd")
	var failures := 0

	# 起点干净(上次异常退出可能残留)
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)

	var s = _make()

	# 1. 未设值返回 default
	if s.get_value("audio", "music") != null:
		print("FAIL 1: 未设值应返回 null")
		failures += 1
	if s.get_value("audio", "music", 0.5) != 0.5:
		print("FAIL 1: 未设值应返回显式 default")
		failures += 1

	# 2. set → get 往返(标量与容器)
	s.set_value("audio", "music", 0.8)
	if s.get_value("audio", "music") != 0.8:
		print("FAIL 2: float 往返失败")
		failures += 1
	s.set_value("gfx", "fullscreen", true)
	if s.get_value("gfx", "fullscreen") != true:
		print("FAIL 2: bool 往返失败")
		failures += 1
	s.set_value("meta", "tag", "hero")
	if s.get_value("meta", "tag") != "hero":
		print("FAIL 2: String 往返失败")
		failures += 1

	# 3. 信号:同值不广播;新值广播一次且参数正确
	var calls := []
	s.value_changed.connect(func(section: String, key: String, value) -> void:
		calls.append([section, key, value]))
	s.set_value("audio", "music", 0.8)  # 同值
	if calls.size() != 0:
		print("FAIL 3: 同值 set 不应广播,收到 %d 次" % calls.size())
		failures += 1
	s.set_value("audio", "music", 0.3)
	if calls.size() != 1 or calls[0] != ["audio", "music", 0.3]:
		print("FAIL 3: 新值 set 应广播一次且参数正确,收到 %s" % [calls])
		failures += 1

	# 4. has_value / erase_value / erase_section 语义与空操作安全
	if not s.has_value("audio", "music"):
		print("FAIL 4: has_value 应为 true")
		failures += 1
	s.erase_value("audio", "music")
	if s.has_value("audio", "music"):
		print("FAIL 4: erase_value 后 has_value 应为 false")
		failures += 1
	if calls.size() != 2 or calls[1] != ["audio", "music", null]:
		print("FAIL 4: erase_value 应广播 value=null")
		failures += 1
	s.erase_value("audio", "music")   # 再删:空操作,不广播
	s.erase_section("no_such_section")  # 空操作
	if calls.size() != 2:
		print("FAIL 4: 空操作不应广播")
		failures += 1
	s.erase_section("gfx")
	if s.has_value("gfx", "fullscreen"):
		print("FAIL 4: erase_section 后键应消失")
		failures += 1

	# 5. _decode 损坏输入;_decode(_encode(x)) 往返
	if s._decode("not valid json {{{") != {}:
		print("FAIL 5: 非法 JSON 应返回 {}")
		failures += 1
	if s._decode("42") != {}:
		print("FAIL 5: 根非 Dictionary 应返回 {}")
		failures += 1
	var round_tripped: Dictionary = s._decode(s._encode({"a": {"b": "c"}}))
	if round_tripped.get("a", {}).get("b") != "c":
		print("FAIL 5: _encode/_decode 往返失败,得到 %s" % [round_tripped])
		failures += 1
	# 非 Dictionary 的 section 值在 _decode 时被丢弃
	var dropped: Dictionary = s._decode('{"good": {"k": 1}, "bad": 5}')
	if dropped.has("bad") or not dropped.has("good"):
		print("FAIL 5: 非 Dictionary section 应被丢弃,得到 %s" % [dropped])
		failures += 1

	# 6. 磁盘往返:重建实例读盘一致(注:JSON 往返 int 会变 float,
	#    顶层标量 == 比较 42 == 42.0 为 true,断言仍成立)
	s.set_value("save", "score", 42)
	var s2 = _make()
	s2._load_from_disk()
	if s2.get_value("save", "score") != 42:
		print("FAIL 6: 磁盘往返失败,得到 %s" % [s2.get_value("save", "score")])
		failures += 1
	if s2.get_value("meta", "tag") != "hero":
		print("FAIL 6: 磁盘往返丢键")
		failures += 1
	s2.free()

	# 7. 坏文件降级:预写非法 JSON → 空配置且可正常覆盖写
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string("corrupted[[[")
	f.close()
	var s3 = _make()
	s3._load_from_disk()
	if s3.get_value("meta", "tag") != null:
		print("FAIL 7: 坏文件应降级为空配置")
		failures += 1
	s3.set_value("meta", "tag", "again")
	var s4 = _make()
	s4._load_from_disk()
	if s4.get_value("meta", "tag") != "again":
		print("FAIL 7: 坏文件被 set 覆盖后应可正常读回")
		failures += 1
	s3.free()
	s4.free()

	# 8. 容器值:get 返回深拷贝 + read-modify-write 必须写透(回归 aliasing 静默丢数据)
	var s8 = _make()
	s8.set_value("binds", "keys", {"jump": "space", "fire": "ctrl"})
	# get 返回独立副本:改它不应回写 _data
	var got: Dictionary = s8.get_value("binds", "keys")
	got["jump"] = "w"
	if s8.get_value("binds", "keys")["jump"] != "space":
		print("FAIL 8: get_value 应返回深拷贝,改动不应污染内部 _data")
		failures += 1
	# read-modify-write:改副本再 set 回,必须真的写透并广播
	var calls8 := []
	s8.value_changed.connect(func(section: String, key: String, v) -> void: calls8.append(key))
	var rmw: Dictionary = s8.get_value("binds", "keys")
	rmw["jump"] = "w"
	s8.set_value("binds", "keys", rmw)
	if calls8.size() != 1:
		print("FAIL 8: read-modify-write 的 set_value 应写透并广播一次,实际 %d" % calls8.size())
		failures += 1
	# 真正落盘:新实例读盘应看到修改后的值
	var s8b = _make()
	s8b._load_from_disk()
	if s8b.get_value("binds", "keys")["jump"] != "w":
		print("FAIL 8: read-modify-write 应真正落盘,磁盘读回 jump 应为 'w'")
		failures += 1
	# 内容相同的容器 set 回:不应重复广播/写盘
	var same: Dictionary = s8.get_value("binds", "keys")
	s8.set_value("binds", "keys", same)
	if calls8.size() != 1:
		print("FAIL 8: 内容未变的容器 set 不应再广播,实际 %d" % calls8.size())
		failures += 1
	s8.free()
	s8b.free()

	# 清理
	s.free()
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)

	if failures == 0:
		print("test_settings: ALL PASS")
		quit(0)
	else:
		print("test_settings: %d FAILURE(S)" % failures)
		quit(1)
