extends SceneTree
## KitModifiers headless 断言。运行:godot --headless --path . -s res://test/test_fortune_modifiers.gd
const KitModifiers := preload("res://examples/fortune-mill/systems/kit_modifiers.gd")


func _initialize() -> void:
	var failures := 0
	var m = KitModifiers.new()

	# 1. 空栈 → 返回 base
	if m.value_for(&"gold", 10.0) != 10.0:
		print("FAIL 1: 空栈应返 base 10"); failures += 1

	# 2. 单 add
	m.set_modifier(&"gold", &"a", &"add", 5.0)
	if m.value_for(&"gold", 10.0) != 15.0:
		print("FAIL 2: (10+5) 应 15"); failures += 1

	# 3. 加 mul → (10+5)*2 = 30
	m.set_modifier(&"gold", &"b", &"mul", 2.0)
	if m.value_for(&"gold", 10.0) != 30.0:
		print("FAIL 3: (10+5)*2 应 30"); failures += 1

	# 4. 多 mul 叠乘 → (10+5)*2*1.5 = 45
	m.set_modifier(&"gold", &"c", &"mul", 1.5)
	if m.value_for(&"gold", 10.0) != 45.0:
		print("FAIL 4: (10+5)*2*1.5 应 45"); failures += 1

	# 5. 同 source 覆盖 → a 改 8 → (10+8)*3 = 54
	m.set_modifier(&"gold", &"a", &"add", 8.0)
	if m.value_for(&"gold", 10.0) != 54.0:
		print("FAIL 5: 覆盖后 (10+8)*3 应 54"); failures += 1

	# 6. remove_source(c) → (10+8)*2 = 36
	m.remove_source(&"gold", &"c")
	if m.value_for(&"gold", 10.0) != 36.0:
		print("FAIL 6: 移除 c 后 (10+8)*2 应 36"); failures += 1

	# 7. target 隔离:另一 target 不受影响
	if m.value_for(&"speed", 1.0) != 1.0:
		print("FAIL 7: 未设修正的 target 应返 base"); failures += 1

	# 8. 缓存一致:连续两次 value_for 相同(无副作用)
	var v1 = m.value_for(&"gold", 10.0)
	var v2 = m.value_for(&"gold", 10.0)
	if v1 != v2:
		print("FAIL 8: 连续 value_for 应一致"); failures += 1

	# --- 定型(P2):明细查询 breakdown / sources + exp 保留 ---
	# 此刻 gold: a=add 8, b=mul 2 → (10+8)*2 = 36

	# 10. breakdown 明细:base/add/mul/result 与 value_for 一致,sources 列出各源
	var bd: Dictionary = m.breakdown(&"gold", 10.0)
	if bd.get("base") != 10.0 or bd.get("add") != 8.0 or bd.get("mul") != 2.0:
		print("FAIL 10: breakdown base/add/mul 应 10/8/2,实际 %s" % bd); failures += 1
	if not is_equal_approx(float(bd.get("result", 0.0)), m.value_for(&"gold", 10.0)):
		print("FAIL 10: breakdown.result 应等于 value_for,实际 %s" % bd); failures += 1
	if (bd.get("sources", []) as Array).size() != 2:
		print("FAIL 10: breakdown.sources 应含 2 条,实际 %s" % bd.get("sources")); failures += 1

	# 11. sources(target) 返回该 target 的所有 source_id
	var srcs: Array = m.sources(&"gold")
	if srcs.size() != 2 or not srcs.has(&"a") or not srcs.has(&"b"):
		print("FAIL 11: sources 应为 [a,b],实际 %s" % [srcs]); failures += 1

	# 12. exp 保留(未知 op):不参与求值(被忽略),但仍登记进 sources
	m.set_modifier(&"gold", &"e", &"exp", 3.0)
	if m.value_for(&"gold", 10.0) != 36.0:
		print("FAIL 12: exp 保留应被忽略,value_for 仍 36,实际 %s" % m.value_for(&"gold", 10.0)); failures += 1
	if m.sources(&"gold").size() != 3:
		print("FAIL 12: exp 登记后 sources 应 3 条"); failures += 1

	# 13. clear(target)
	m.clear(&"gold")
	if m.value_for(&"gold", 10.0) != 10.0:
		print("FAIL 13: clear 后应返 base"); failures += 1
	if not m.sources(&"gold").is_empty():
		print("FAIL 13: clear 后 sources 应空"); failures += 1

	if failures == 0:
		print("test_fortune_modifiers: ALL PASS")
		quit(0)
	else:
		print("test_fortune_modifiers: %d FAILURE(S)" % failures)
		quit(1)
