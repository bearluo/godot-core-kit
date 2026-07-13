extends SceneTree
## GameClock headless 断言。不入树、直接 .new() 实例化(手动调 _process 保确定性,
## 避免真实帧干扰);bus 断言用运行时 load 的 EventBus 实例。
## 运行:godot --headless --path . -s res://test/test_game_clock.gd

var ClockScript
var BusScript


func _initialize() -> void:
	ClockScript = load("res://addons/godot-core-kit/systems/game_clock.gd")
	BusScript = load("res://addons/godot-core-kit/core/event_bus.gd")
	var failures := 0

	# 1. 初始状态
	var c = ClockScript.new()
	if c.year() != 1 or c.season_index() != 0 or c.season_name() != "spring" or c.day() != 1 or c.hour() != 6 or c.minute() != 0:
		print("FAIL 1: 初始应 y1 spring d1 06:00,实际 y%d s%d d%d %02d:%02d" % [c.year(), c.season_index(), c.day(), c.hour(), c.minute()]); failures += 1
	if c.paused or c.time_scale != 0.0:
		print("FAIL 1: 初始应 time_scale=0 未暂停"); failures += 1

	# 2. 分->时级联
	c.advance_minutes(30)
	if c.hour() != 6 or c.minute() != 30:
		print("FAIL 2: advance 30 应 06:30"); failures += 1
	c.advance_minutes(40)
	if c.hour() != 7 or c.minute() != 10:
		print("FAIL 2: 再 advance 40 应 07:10"); failures += 1

	# 3. 跨天
	var c3 = ClockScript.new()
	c3.advance_day()
	if c3.day() != 2 or c3.hour() != 6 or c3.minute() != 0:
		print("FAIL 3: advance_day 应到 d2 06:00"); failures += 1

	# 4. 跨季(2 天季长)
	var c4 = ClockScript.new()
	c4.configure({"days_per_season": 2})
	c4.advance_day()
	c4.advance_day()
	if c4.season_index() != 1 or c4.day() != 1:
		print("FAIL 4: 2 天季长 advance 2 天应到 season1 d1,实际 s%d d%d" % [c4.season_index(), c4.day()]); failures += 1

	# 5. 跨年(1 天季长 2 季)
	var c5 = ClockScript.new()
	c5.configure({"days_per_season": 1, "seasons": ["a", "b"]})
	c5.advance_day()
	c5.advance_day()
	if c5.year() != 2:
		print("FAIL 5: 1 天季长 2 季 advance 2 天应到 year2,实际 %d" % c5.year()); failures += 1

	# 6. sleep_to_next_day
	var c6 = ClockScript.new()
	c6.set_datetime(1, 0, 1, 14, 0)
	c6.sleep_to_next_day()
	if c6.day() != 2 or c6.hour() != 6 or c6.minute() != 0:
		print("FAIL 6: sleep 应到 d2 06:00,实际 d%d %02d:%02d" % [c6.day(), c6.hour(), c6.minute()]); failures += 1

	# 7. 原生 signal 计数
	var c7 = ClockScript.new()
	var sig := {"days": 0, "last": []}
	c7.day_changed.connect(func(d, s, y): sig["days"] += 1; sig["last"] = [d, s, y])
	c7.advance_day(); c7.advance_day(); c7.advance_day()
	if sig["days"] != 3:
		print("FAIL 7: day_changed 应发 3 次,实际 %d" % sig["days"]); failures += 1
	if sig["last"] != [4, 0, 1]:
		print("FAIL 7: 末次参数应 (4,0,1),实际 %s" % str(sig["last"])); failures += 1

	# 8. bus 绑定广播
	var c8 = ClockScript.new()
	var bus = BusScript.new()
	c8.bind_bus(bus)
	var got := {"payload": null}
	bus.subscribe(c8.EV_DAY_CHANGED, func(p): got["payload"] = p)
	c8.advance_day()
	if not (got["payload"] is Dictionary) or int(got["payload"].get("day", -1)) != 2 or not got["payload"].has("season_name"):
		print("FAIL 8: bus clock:day_changed 应收到含 day/season_name 的快照,实际 %s" % str(got["payload"])); failures += 1
	bus.free()

	# 9. bus 未绑定降级
	var c9 = ClockScript.new()
	c9.advance_day()
	if c9.day() != 2:
		print("FAIL 9: 未绑定 bus 仍应正常推进"); failures += 1

	# 10. _process 走时
	var c10 = ClockScript.new()
	c10.time_scale = 60.0
	c10._process(1.0)
	if c10.hour() != 7 or c10.minute() != 0:
		print("FAIL 10: time_scale 60 _process(1.0) 应到 07:00,实际 %02d:%02d" % [c10.hour(), c10.minute()]); failures += 1
	c10.paused = true
	c10._process(1.0)
	if c10.hour() != 7:
		print("FAIL 10: paused 后 _process 不应推进"); failures += 1
	c10.paused = false
	c10.time_scale = 0.0
	c10._process(1.0)
	if c10.hour() != 7:
		print("FAIL 10: time_scale 0 不应推进"); failures += 1

	# 11. to_dict/from_dict 往返
	var c11 = ClockScript.new()
	c11.configure({"days_per_season": 10, "seasons": ["x", "y", "z"], "wake_hour": 8})
	c11.advance_minutes(3 * 60 + 15)
	c11.time_scale = 30.0
	var d11 = c11.to_dict()
	var c11b = ClockScript.new()
	c11b.from_dict(d11)
	if c11b.snapshot() != c11.snapshot():
		print("FAIL 11: from_dict 后 snapshot 应一致"); failures += 1
	if c11b.days_per_season() != 10 or c11b.seasons() != ["x", "y", "z"] or c11b.time_scale != 30.0:
		print("FAIL 11: from_dict 应恢复配置与 time_scale"); failures += 1

	# 12. set_datetime 夹取
	var c12 = ClockScript.new()
	c12.set_datetime(1, 99, 999, 99, 99)
	if c12.season_index() > 3 or c12.day() > 28 or c12.hour() > 23 or c12.minute() > 59:
		print("FAIL 12: set_datetime 应夹取到合法上界,实际 s%d d%d %02d:%02d" % [c12.season_index(), c12.day(), c12.hour(), c12.minute()]); failures += 1

	c.free(); c3.free(); c4.free(); c5.free(); c6.free(); c7.free(); c8.free(); c9.free(); c10.free(); c11.free(); c11b.free(); c12.free()

	if failures == 0:
		print("test_game_clock: ALL PASS")
		quit(0)
	else:
		print("test_game_clock: %d FAILURE(S)" % failures)
		quit(1)
