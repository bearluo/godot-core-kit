extends SceneTree
## SaveMigrator(存档版本迁移链)headless 断言。
## 运行:godot --headless --path . -s res://test/test_fortune_migration.gd
## 重点:① 完整链 v1→v3 ② 缺版本章默认 v1 ③ 当前版本原样 ④ 未来版本安全失败
##       ⑤ 缺中间步失败 missing:N ⑥ 迁移返回非字典失败 error:N ⑦ version_of 读版本章。
const SaveMigrator := preload("res://examples/fortune-mill/systems/save_migrator.gd")


func _initialize() -> void:
	var failures := 0

	# 三步链:v1→v2 加键 a、v2→v3 加键 b
	var m = SaveMigrator.new(3)
	m.register(1, func(d: Dictionary) -> Dictionary:
		d["a"] = 1
		return d)
	m.register(2, func(d: Dictionary) -> Dictionary:
		d["b"] = 2
		return d)

	# 1. 完整链 v1→v3(两步都跑,补盖版本章)
	var r1 = m.migrate({"schema_version": 1})
	if not (r1.ok and int(r1.from) == 1 and int(r1.to) == 3 and int(r1.data.get("a", 0)) == 1 and int(r1.data.get("b", 0)) == 2 and int(r1.data.get("schema_version", 0)) == 3):
		print("FAIL 1: v1→v3 链应完整,得到 %s" % [r1]); failures += 1

	# 2. 缺版本章默认 v1 并迁到 v3
	var r2 = m.migrate({})
	if not (r2.ok and int(r2.from) == 1 and int(r2.to) == 3):
		print("FAIL 2: 缺版本章应默认 v1 迁到 v3,得到 %s" % [r2]); failures += 1

	# 3. 已是当前版本 → 原样(不重复跑迁移,不注入 a/b)
	var r3 = m.migrate({"schema_version": 3, "x": 9})
	if not (r3.ok and int(r3.from) == 3 and int(r3.to) == 3 and not r3.data.has("a") and int(r3.data.get("x", 0)) == 9):
		print("FAIL 3: 当前版本应原样,得到 %s" % [r3]); failures += 1

	# 4. 未来版本 → 失败 reason=future(保底新档语义)
	var r4 = m.migrate({"schema_version": 99})
	if not ((not r4.ok) and str(r4.reason) == "future"):
		print("FAIL 4: 未来版本应失败 future,得到 %s" % [r4]); failures += 1

	# 5. 缺中间步(2→3 未注册)→ 失败 missing:2
	var m2 = SaveMigrator.new(3)
	m2.register(1, func(d: Dictionary) -> Dictionary:
		return d)
	var r5 = m2.migrate({"schema_version": 1})
	if not ((not r5.ok) and str(r5.reason) == "missing:2"):
		print("FAIL 5: 缺 2→3 步应失败 missing:2,得到 %s" % [r5]); failures += 1

	# 6. 迁移函数返回非字典 → 失败 error:N
	var m3 = SaveMigrator.new(2)
	m3.register(1, func(_d: Dictionary):
		return 42)
	var r6 = m3.migrate({"schema_version": 1})
	if not ((not r6.ok) and str(r6.reason) == "error:1"):
		print("FAIL 6: 迁移返回非字典应失败 error:1,得到 %s" % [r6]); failures += 1

	# 7. version_of:缺 → 1、有 → 读出
	if m.version_of({}) != 1 or m.version_of({"schema_version": 5}) != 5:
		print("FAIL 7: version_of 判定错"); failures += 1

	# 8. Fortune v3→v4:飞镖房重构命运转盘——升级 id 改名 + 旧靶心档统计清除
	#    (等价链:复刻 FortuneMill._build_migrator 的 v3→v4 步,验证该数据变换)
	var m4 = SaveMigrator.new(4)
	m4.register(3, func(d: Dictionary) -> Dictionary:
		var darts_d = d.get("darts", {})
		if darts_d is Dictionary and darts_d.has("levels"):
			var lv: Dictionary = darts_d["levels"]
			if lv.has("bullseye_training"):
				lv["widen_zone"] = lv["bullseye_training"]; lv.erase("bullseye_training")
			if lv.has("rattling_gunner"):
				lv["hire_ai"] = lv["rattling_gunner"]; lv.erase("rattling_gunner")
			darts_d["levels"] = lv
			d["darts"] = darts_d
		var st = d.get("stats", {})
		if st is Dictionary:
			for k in st.keys():
				if String(k).begins_with("dart_tier_"):
					st.erase(k)
			d["stats"] = st
		return d)
	var r7 = m4.migrate({"schema_version": 3, "darts": {"levels": {"bullseye_training": 2, "rattling_gunner": 3}}, "stats": {"dart_tier_5": 9, "dart_throws": 100}})
	var lv7: Dictionary = r7.data.get("darts", {}).get("levels", {})
	var st7: Dictionary = r7.data.get("stats", {})
	if not (r7.ok and int(r7.to) == 4 and int(lv7.get("widen_zone", 0)) == 2 and int(lv7.get("hire_ai", 0)) == 3 \
			and not lv7.has("bullseye_training") and not lv7.has("rattling_gunner") \
			and not st7.has("dart_tier_5") and int(st7.get("dart_throws", 0)) == 100):
		print("FAIL 8: v3→v4 应改名升级 id + 清 dart_tier_*,得到 %s" % [r7]); failures += 1

	if failures == 0:
		print("test_fortune_migration: ALL PASS")
		quit(0)
	else:
		print("test_fortune_migration: %d FAILURE(S)" % failures)
		quit(1)
