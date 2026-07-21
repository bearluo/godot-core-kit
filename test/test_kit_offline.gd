extends SceneTree
## KitOffline 纯数学单测(kit 门):墙钟差 × 产率、封顶 8h、时间回拨按 0、
## 零/负产率、无上次时间戳、无流逝、自定义封顶。运行:
## godot --headless --path . -s res://test/test_kit_offline.gd

const KitOfflineScript = preload("res://addons/godot-core-kit/offline/kit_offline.gd")


func _initialize() -> void:
	var day := 86400.0
	var base := 1_000_000.0   # 任意墙钟基准秒
	var failures := 0

	# 1) 正常结算:1 小时 × 10 gold/s = 36000
	var r := KitOfflineScript.settle(base, base + 3600.0, 10.0)
	if not is_equal_approx(r.earned, 36000.0) or not is_equal_approx(r.elapsed, 3600.0) or r.capped or r.rolled_back:
		print("FAIL 1: 1h×10/s 应 earned=36000 elapsed=3600 未封顶未回拨,实际 %s" % r); failures += 1

	# 2) 封顶 8 小时:过 10 小时只计 8 小时
	var r2 := KitOfflineScript.settle(base, base + 10.0 * 3600.0, 10.0)
	if not is_equal_approx(r2.elapsed, 28800.0) or not is_equal_approx(r2.earned, 288000.0) or not r2.capped:
		print("FAIL 2: 10h 应封顶 elapsed=28800 earned=288000 capped=true,实际 %s" % r2); failures += 1

	# 3) 恰好 8 小时边界:不算 capped(<= cap)
	var r3 := KitOfflineScript.settle(base, base + 28800.0, 1.0)
	if not is_equal_approx(r3.elapsed, 28800.0) or r3.capped:
		print("FAIL 3: 恰好 8h 应 elapsed=28800 capped=false,实际 %s" % r3); failures += 1

	# 4) 时间回拨:now < last → earned 0 + rolled_back
	var r4 := KitOfflineScript.settle(base, base - 500.0, 10.0)
	if not is_equal_approx(r4.earned, 0.0) or not r4.rolled_back or r4.capped:
		print("FAIL 4: 回拨应 earned=0 rolled_back=true capped=false,实际 %s" % r4); failures += 1

	# 5) 零产率:earned 0,elapsed 照算
	var r5 := KitOfflineScript.settle(base, base + 3600.0, 0.0)
	if not is_equal_approx(r5.earned, 0.0) or not is_equal_approx(r5.elapsed, 3600.0):
		print("FAIL 5: 零产率应 earned=0 elapsed=3600,实际 %s" % r5); failures += 1

	# 6) 负产率:防御,earned 0
	var r6 := KitOfflineScript.settle(base, base + 3600.0, -5.0)
	if not is_equal_approx(r6.earned, 0.0):
		print("FAIL 6: 负产率应 earned=0,实际 %s" % r6); failures += 1

	# 7) 无上次时间戳(last_seen<=0):首次运行,earned 0、不回拨
	var r7 := KitOfflineScript.settle(0.0, base, 10.0)
	if not is_equal_approx(r7.earned, 0.0) or r7.rolled_back:
		print("FAIL 7: 无时间戳应 earned=0 rolled_back=false,实际 %s" % r7); failures += 1

	# 8) now == last(无时间流逝):earned 0、不回拨
	var r8 := KitOfflineScript.settle(base, base, 10.0)
	if not is_equal_approx(r8.earned, 0.0) or r8.rolled_back:
		print("FAIL 8: now==last 应 earned=0 rolled_back=false,实际 %s" % r8); failures += 1

	# 9) 自定义封顶(day 天上限)覆盖默认 8h
	var r9 := KitOfflineScript.settle(base, base + 10.0 * 3600.0, 1.0, day)
	if not is_equal_approx(r9.elapsed, 36000.0):
		print("FAIL 9: 自定义 cap=day 时 10h 全计 elapsed=36000,实际 %s" % r9); failures += 1

	if failures == 0:
		print("test_kit_offline: ALL PASS")
		quit(0)
	else:
		print("test_kit_offline: %d FAILURE(S)" % failures)
		quit(1)
