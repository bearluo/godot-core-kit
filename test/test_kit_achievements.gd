extends SceneTree
## KitAchievements 纯逻辑单测(kit 门):① evaluate 达阈值才解锁 ② 触发去重(已解锁不重触、
## 再求值无新解锁)③ 返回新解锁列表(def 表顺序)④ 平台 sink 每条只触发一次 ⑤ 手动 unlock 去重
## ⑥ 持久化恢复已解锁集合 ⑦ 与 KitStats 端到端(阈值判定读 get_value)。
## 运行:godot --headless --path . -s res://test/test_kit_achievements.gd


func _def(AchievementDefScript, id: StringName, key: StringName, thr: float):
	var a = AchievementDefScript.new()
	a.id = id; a.stat_key = key; a.threshold = thr
	return a


func _initialize() -> void:
	var KitAchievementsScript = load("res://addons/godot-core-kit/achievements/kit_achievements.gd")
	var AchievementDefScript = load("res://addons/godot-core-kit/achievements/achievement_def.gd")
	var KitStatsScript = load("res://addons/godot-core-kit/stats/kit_stats.gd")
	var failures := 0

	var defs: Array = [
		_def(AchievementDefScript, &"throw1", &"throws", 1.0),
		_def(AchievementDefScript, &"throw100", &"throws", 100.0),
		_def(AchievementDefScript, &"peak1k", &"peak", 1000.0),
	]
	var ach = KitAchievementsScript.new()
	ach.set_defs(defs)
	var stats = KitStatsScript.new()

	# 1. 全未达阈值 → 无解锁;total = def 数
	if not ach.evaluate(stats).is_empty() or ach.count() != 0:
		print("FAIL 1: 初始无统计不应解锁任何成就"); failures += 1
	if ach.total() != 3:
		print("FAIL 2: total 应为 def 数 3,实际 %d" % ach.total()); failures += 1

	# 2. throws=1 → 只解锁 throw1(阈值 1),throw100 未达
	stats.add(&"throws", 1.0)
	var n1 = ach.evaluate(stats)
	if n1.size() != 1 or n1[0] != &"throw1" or not ach.is_unlocked(&"throw1") or ach.is_unlocked(&"throw100"):
		print("FAIL 3: throws=1 应只解锁 throw1(新解锁 %s)" % [n1]); failures += 1

	# 3. 去重:同状态再求值无新解锁
	if not ach.evaluate(stats).is_empty():
		print("FAIL 4: 同状态再求值应无新解锁(去重)"); failures += 1

	# 4. throws 到 100 → 解锁 throw100(throw1 不重触)
	stats.set_value(&"throws", 100.0)
	var n2 = ach.evaluate(stats)
	if n2.size() != 1 or n2[0] != &"throw100" or ach.count() != 2:
		print("FAIL 5: throws=100 应只新解锁 throw100(新解锁 %s count %d)" % [n2, ach.count()]); failures += 1

	# 5. 平台 sink:每条新解锁触发一次(不重触)
	var fired: Array = []
	var ach2 = KitAchievementsScript.new()
	ach2.set_defs(defs)
	ach2.set_steam_sink(func(id): fired.append(id))
	var st2 = KitStatsScript.new(); st2.add(&"throws", 100.0); st2.record_max(&"peak", 2000.0)
	ach2.evaluate(st2)
	ach2.evaluate(st2)   # 再来一次不应重复触发
	if fired.size() != 3:
		print("FAIL 6: sink 应对 3 条各触发一次(实际 %d:%s)" % [fired.size(), fired]); failures += 1

	# 6. 手动 unlock 去重
	var ach3 = KitAchievementsScript.new(); ach3.set_defs(defs)
	if not ach3.unlock(&"throw1") or ach3.unlock(&"throw1"):
		print("FAIL 7: 手动 unlock 首次 true、再次 false(去重)"); failures += 1

	# 7. 持久化:已解锁集合往返
	var snap = ach.to_dict()   # ach 此时解锁 throw1 + throw100
	var ach4 = KitAchievementsScript.new(); ach4.set_defs(defs)
	ach4.from_dict(snap)
	if ach4.count() != 2 or not ach4.is_unlocked(&"throw1") or not ach4.is_unlocked(&"throw100"):
		print("FAIL 8: from_dict 应恢复 2 条已解锁"); failures += 1
	if not ach4.evaluate(stats).is_empty():
		print("FAIL 9: from_dict 恢复后已解锁项不应重触"); failures += 1

	# 8. 端到端:record_max 峰值达阈值 → 解锁 peak1k
	stats.record_max(&"peak", 1500.0)
	var n3 = ach.evaluate(stats)
	if n3.size() != 1 or n3[0] != &"peak1k" or ach.count() != 3:
		print("FAIL 10: peak=1500 应解锁 peak1k(新解锁 %s count %d)" % [n3, ach.count()]); failures += 1
	if ach.unlocked_ids().size() != 3:
		print("FAIL 11: unlocked_ids 应 3 条"); failures += 1

	if failures == 0:
		print("test_kit_achievements: ALL PASS")
		quit(0)
	else:
		print("test_kit_achievements: %d FAILURE(S)" % failures)
		quit(1)
