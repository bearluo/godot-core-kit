extends SceneTree
## KitOffline 纯数学单测:墙钟差 × 产率、封顶 8h、时间回拨按 0、零产率、无上次时间戳。

const KitOfflineScript = preload("res://examples/fortune-mill/systems/kit_offline.gd")


func _initialize() -> void:
	var day := 86400.0
	var base := 1_000_000.0   # 任意墙钟基准秒

	# 1) 正常结算:1 小时 × 10 gold/s = 36000
	var r := KitOfflineScript.settle(base, base + 3600.0, 10.0)
	assert(is_equal_approx(r.earned, 36000.0), "1h×10/s=36000, got %f" % r.earned)
	assert(is_equal_approx(r.elapsed, 3600.0), "elapsed=3600")
	assert(r.capped == false, "1h 不封顶")
	assert(r.rolled_back == false, "正常不回拨")

	# 2) 封顶 8 小时:过 10 小时只计 8 小时
	var r2 := KitOfflineScript.settle(base, base + 10.0 * 3600.0, 10.0)
	assert(is_equal_approx(r2.elapsed, 28800.0), "封顶 8h=28800, got %f" % r2.elapsed)
	assert(is_equal_approx(r2.earned, 288000.0), "8h×10/s=288000, got %f" % r2.earned)
	assert(r2.capped == true, "超 8h 应 capped")

	# 3) 恰好 8 小时边界:不算 capped(<= cap)
	var r3 := KitOfflineScript.settle(base, base + 28800.0, 1.0)
	assert(is_equal_approx(r3.elapsed, 28800.0), "边界 elapsed=28800")
	assert(r3.capped == false, "恰好 8h 不算超")

	# 4) 时间回拨:now < last → earned 0 + rolled_back
	var r4 := KitOfflineScript.settle(base, base - 500.0, 10.0)
	assert(is_equal_approx(r4.earned, 0.0), "回拨 earned=0, got %f" % r4.earned)
	assert(r4.rolled_back == true, "回拨应标记")
	assert(r4.capped == false, "回拨非封顶")

	# 5) 零/负产率:无自动化 → earned 0(但 elapsed 照算)
	var r5 := KitOfflineScript.settle(base, base + 3600.0, 0.0)
	assert(is_equal_approx(r5.earned, 0.0), "零产率 earned=0")
	assert(is_equal_approx(r5.elapsed, 3600.0), "零产率 elapsed 照算")

	# 6) 无上次时间戳(last_seen<=0):首次运行,earned 0、不回拨
	var r6 := KitOfflineScript.settle(0.0, base, 10.0)
	assert(is_equal_approx(r6.earned, 0.0), "无时间戳 earned=0")
	assert(r6.rolled_back == false, "无时间戳非回拨")

	# 7) now == last(无时间流逝):earned 0、不回拨
	var r7 := KitOfflineScript.settle(base, base, 10.0)
	assert(is_equal_approx(r7.earned, 0.0), "now==last earned=0")
	assert(r7.rolled_back == false, "now==last 非回拨")

	# 8) 自定义封顶(day 天上限)覆盖默认 8h
	var r8 := KitOfflineScript.settle(base, base + 10.0 * 3600.0, 1.0, day)
	assert(is_equal_approx(r8.elapsed, 36000.0), "自定义 cap=day 时 10h 全计, got %f" % r8.elapsed)

	print("test_fortune_offline: ALL PASS")
	quit(0)
