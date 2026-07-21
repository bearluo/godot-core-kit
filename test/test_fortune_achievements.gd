extends SceneTree
## KitAchievements(成就引擎:阈值判定 + 去重 + Steam 抽象层)+ AchievementCatalog(51 条目录)headless 断言。
## 运行:godot --headless --path . -s res://test/test_fortune_achievements.gd
## 重点:① evaluate 达阈值才解锁 ② 触发去重(已解锁不重触、再求值无新解锁)③ 返回「新解锁」列表
## ④ Steam sink 每条只触发一次 ⑤ 手动 unlock 去重 ⑥ 持久化恢复已解锁集合 ⑦ 目录 51 条 + 阈值正确。
const KitStats := preload("res://examples/fortune-mill/systems/kit_stats.gd")
const KitAchievements := preload("res://examples/fortune-mill/systems/kit_achievements.gd")
const AchievementCatalog := preload("res://examples/fortune-mill/systems/achievement_catalog.gd")
const AchievementDef := preload("res://examples/fortune-mill/defs/achievement_def.gd")
const KitDataRegistry := preload("res://addons/godot-core-kit/data/kit_data_registry.gd")


func _def(id: StringName, key: StringName, thr: float) -> AchievementDef:
	var a = AchievementDef.new()
	a.id = id; a.stat_key = key; a.threshold = thr
	return a


func _initialize() -> void:
	var failures := 0

	# --- 引擎:阈值判定 + 去重 + 新解锁列表 ---
	var defs: Array = [
		_def(&"throw1", &"throws", 1.0),
		_def(&"throw100", &"throws", 100.0),
		_def(&"peak1k", &"peak", 1000.0),
	]
	var ach = KitAchievements.new()
	ach.set_defs(defs)
	var stats = KitStats.new()

	# 1. 全未达阈值 → 无解锁
	if not ach.evaluate(stats).is_empty() or ach.count() != 0:
		print("FAIL 1: 初始无统计不应解锁任何成就"); failures += 1
	if ach.total() != 3:
		print("FAIL 2: total 应为 def 数 3,实际 %d" % ach.total()); failures += 1

	# 2. throws=1 → 只解锁 throw1(阈值 1),throw100 未达
	stats.add(&"throws", 1.0)
	var n1 := ach.evaluate(stats)
	if n1.size() != 1 or n1[0] != &"throw1" or not ach.is_unlocked(&"throw1") or ach.is_unlocked(&"throw100"):
		print("FAIL 3: throws=1 应只解锁 throw1(新解锁 %s)" % [n1]); failures += 1

	# 3. 去重:同状态再求值无新解锁
	if not ach.evaluate(stats).is_empty():
		print("FAIL 4: 同状态再求值应无新解锁(去重)"); failures += 1

	# 4. throws 到 100 → 解锁 throw100(throw1 不重触)
	stats.set_value(&"throws", 100.0)
	var n2 := ach.evaluate(stats)
	if n2.size() != 1 or n2[0] != &"throw100" or ach.count() != 2:
		print("FAIL 5: throws=100 应只新解锁 throw100(新解锁 %s count %d)" % [n2, ach.count()]); failures += 1

	# 5. Steam sink:每条新解锁触发一次(不重触)
	var fired: Array = []
	var ach2 = KitAchievements.new()
	ach2.set_defs(defs)
	ach2.set_steam_sink(func(id): fired.append(id))
	var st2 = KitStats.new(); st2.add(&"throws", 100.0); st2.record_max(&"peak", 2000.0)
	ach2.evaluate(st2)
	ach2.evaluate(st2)   # 再来一次不应重复触发
	if fired.size() != 3:
		print("FAIL 6: Steam sink 应对 3 条各触发一次(实际 %d:%s)" % [fired.size(), fired]); failures += 1

	# 6. 手动 unlock 去重
	var ach3 = KitAchievements.new(); ach3.set_defs(defs)
	if not ach3.unlock(&"throw1") or ach3.unlock(&"throw1"):
		print("FAIL 7: 手动 unlock 首次 true、再次 false(去重)"); failures += 1

	# 7. 持久化:已解锁集合往返
	var snap = ach.to_dict()   # ach 此时解锁 throw1 + throw100
	var ach4 = KitAchievements.new(); ach4.set_defs(defs)
	ach4.from_dict(snap)
	if ach4.count() != 2 or not ach4.is_unlocked(&"throw1") or not ach4.is_unlocked(&"throw100"):
		print("FAIL 8: from_dict 应恢复 2 条已解锁"); failures += 1
	# 恢复后已解锁的不再触发新解锁(即便阈值仍满足)
	if not ach4.evaluate(stats).is_empty():
		print("FAIL 9: from_dict 恢复后已解锁项不应重触"); failures += 1

	# --- 目录:AchievementCatalog 建 51 条,阈值/键正确 ---
	var reg = KitDataRegistry.new()
	var n := AchievementCatalog.build(reg)
	if n != 51 or reg.count(&"achievement") != 51:
		print("FAIL 10: 目录应建 51 条,实际 build=%d count=%d" % [n, reg.count(&"achievement")]); failures += 1
	# 抽查几条关键成就的键与阈值
	var g = reg.get_def(&"achievement", &"guard_darts")
	if g == null or g.stat_key != &"guard_darts" or absf(g.threshold - 1.0) > 0.0001:
		print("FAIL 11: guard_darts 定义错"); failures += 1
	var t17 = reg.get_def(&"achievement", &"dart_tier_17")
	if t17 == null or t17.stat_key != &"dart_tier_17":
		print("FAIL 12: dart_tier_17 定义错"); failures += 1
	var gm = reg.get_def(&"achievement", &"gold_1e5")
	if gm == null or gm.stat_key != &"total_gold" or absf(gm.threshold - 100_000.0) > 0.5:
		print("FAIL 13: gold_1e5 阈值应 100k"); failures += 1

	# 8. 目录 + 引擎端到端:喂 5 守卫统计 → 恰好解锁 5 条 guard_* 成就
	var full = KitAchievements.new()
	full.set_defs(reg.all(&"achievement"))
	var fs = KitStats.new()
	for room in [&"darts", &"lotto", &"pachinko", &"sushi", &"gacha"]:
		fs.add(StringName("guard_%s" % room), 1.0)
	var newly := full.evaluate(fs)
	if newly.size() != 5:
		print("FAIL 14: 喂 5 守卫应恰解锁 5 条(实际 %d:%s)" % [newly.size(), newly]); failures += 1
	if not (full.is_unlocked(&"guard_darts") and full.is_unlocked(&"guard_gacha")):
		print("FAIL 15: guard 成就应解锁"); failures += 1

	if failures == 0:
		print("test_fortune_achievements: ALL PASS")
		quit(0)
	else:
		print("test_fortune_achievements: %d FAILURE(S)" % failures)
		quit(1)
