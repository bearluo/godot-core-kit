extends SceneTree
## KitStats(统计计数器持久化)headless 断言。
## 运行:godot --headless --path . -s res://test/test_fortune_stats.gd
## 重点:① add 累加 ② record_max 单调取大 ③ set_value 直接置 ④ get_value 默认值
## ⑤ has/keys/clear ⑥ to_dict/from_dict 往返一致(key String 化、值 float)。
const KitStats := preload("res://examples/fortune-mill/systems/kit_stats.gd")


func _initialize() -> void:
	var failures := 0
	var s = KitStats.new()

	# 1. add 累加(默认 +1;显式 amount)
	if absf(s.add(&"throws") - 1.0) > 0.0001 or absf(s.add(&"throws", 4.0) - 5.0) > 0.0001:
		print("FAIL 1: add 应累加到 5,实际 %s" % s.get_value(&"throws")); failures += 1

	# 2. record_max 单调取大(小值不覆盖大值)
	s.record_max(&"peak", 100.0)
	s.record_max(&"peak", 30.0)
	if absf(s.get_value(&"peak") - 100.0) > 0.0001:
		print("FAIL 2a: 更小值不应覆盖峰值(应 100),实际 %s" % s.get_value(&"peak")); failures += 1
	s.record_max(&"peak", 250.0)
	if absf(s.get_value(&"peak") - 250.0) > 0.0001:
		print("FAIL 2b: 更大值应更新峰值(应 250),实际 %s" % s.get_value(&"peak")); failures += 1

	# 3. set_value 直接置(不累加)
	s.set_value(&"jackpots", 7.0)
	s.set_value(&"jackpots", 3.0)
	if absf(s.get_value(&"jackpots") - 3.0) > 0.0001:
		print("FAIL 3: set_value 应直接置为 3,实际 %s" % s.get_value(&"jackpots")); failures += 1

	# 4. get_value 默认值(缺 key)
	if absf(s.get_value(&"missing", -1.0) - (-1.0)) > 0.0001:
		print("FAIL 4: 缺 key 应返回默认 -1,实际 %s" % s.get_value(&"missing", -1.0)); failures += 1

	# 5. has / keys
	if not s.has(&"throws") or s.has(&"missing"):
		print("FAIL 5a: has 判定错"); failures += 1
	if s.keys().size() != 3:
		print("FAIL 5b: keys 应 3 个(throws/peak/jackpots),实际 %d" % s.keys().size()); failures += 1

	# 6. to_dict / from_dict 往返
	var snap = s.to_dict()
	if not (snap.has("throws") and snap.has("peak") and snap.has("jackpots")):
		print("FAIL 6a: to_dict 键应 String 化齐全(%s)" % snap); failures += 1
	var s2 = KitStats.new()
	s2.from_dict(snap)
	if absf(s2.get_value(&"throws") - 5.0) > 0.0001 or absf(s2.get_value(&"peak") - 250.0) > 0.0001 or absf(s2.get_value(&"jackpots") - 3.0) > 0.0001:
		print("FAIL 6b: from_dict 应完整恢复(throws5/peak250/jackpots3)"); failures += 1

	# 7. from_dict 覆盖式(先清旧值)
	s2.add(&"extra", 9.0)
	s2.from_dict(snap)
	if s2.has(&"extra"):
		print("FAIL 7: from_dict 应先清旧值(extra 不应残留)"); failures += 1

	# 8. clear
	s.clear()
	if s.keys().size() != 0 or s.has(&"throws"):
		print("FAIL 8: clear 后应空"); failures += 1

	if failures == 0:
		print("test_fortune_stats: ALL PASS")
		quit(0)
	else:
		print("test_fortune_stats: %d FAILURE(S)" % failures)
		quit(1)
