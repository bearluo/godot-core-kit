extends SceneTree
## FortuneWheelLayout 纯几何/结算断言。运行:godot --headless --path . -s res://test/test_fortune_wheel.gd
const WL := preload("res://examples/fortune-mill/systems/wheel_layout.gd")

func _initialize() -> void:
	var failures := 0

	# 1. SEGMENTS 覆盖 360、含 jackpot 与 vermin
	var total := 0.0
	var has_jack := false; var has_vermin := false
	for s in WL.SEGMENTS:
		total += float(s["span"])
		if s["name"] == &"jackpot": has_jack = true
		if bool(s.get("vermin", false)): has_vermin = true
	if absf(total - 360.0) > 0.01 or not has_jack or not has_vermin:
		print("FAIL 1: SEGMENTS 应覆盖 360 且含 jackpot+vermin,实际 total=%s" % total); failures += 1

	# 2. jackpot 中心 win_bonus=0 时命中 jackpot
	var jc := WL.jackpot_center()
	if WL.segment_at(jc, 0.0)["name"] != &"jackpot":
		print("FAIL 2: jackpot 中心应命中 jackpot"); failures += 1

	# 3. 扩大中奖区:jackpot 边缘外一点,win_bonus=0 非 jackpot,win_bonus 大 → 变 jackpot
	var edge := jc + WL.jackpot_half_base() + 8.0
	var was_jack: bool = WL.segment_at(edge, 0.0)["name"] == &"jackpot"
	var now_jack: bool = WL.segment_at(edge, 40.0)["name"] == &"jackpot"
	if was_jack or not now_jack:
		print("FAIL 3: win_bonus 应加宽 jackpot 命中带"); failures += 1

	# 4. vermin 段 mult=0
	var vseg := WL.segment_at(WL.vermin_center(), 0.0)
	if not bool(vseg["vermin"]) or float(vseg["mult"]) != 0.0:
		print("FAIL 4: vermin 段应 mult=0"); failures += 1

	# 5. expected_mult 随 ai_skill 单调升(0 最低,1 最高)
	var e0 := WL.expected_mult(0.0); var e1 := WL.expected_mult(1.0); var eh := WL.expected_mult(0.5)
	if not (e1 > eh and eh > e0 and e0 > 0.0):
		print("FAIL 5: expected_mult 应随 ai_skill 单调升,e0=%s eh=%s e1=%s" % [e0, eh, e1]); failures += 1

	# 6. radial_bonus:盘心(r=0)>边缘(r=1),且单调
	if not (WL.radial_bonus(0.0) > WL.radial_bonus(0.5) and WL.radial_bonus(0.5) > WL.radial_bonus(1.0)):
		print("FAIL 6: radial_bonus 应随 r 单调降"); failures += 1

	# 7. landing 确定性 + 整圈映射:aim=0.5 → a_off=180(不再 0);甜点 power → r≈0
	var l_mid := WL.landing(0.5, WL.POWER_SWEET)
	if absf(float(l_mid["r"])) > 0.01:
		print("FAIL 7a: 甜点力度应 r≈0,实际 %s" % l_mid["r"]); failures += 1
	if absf(float(l_mid["a_off"]) - 180.0) > 0.01:
		print("FAIL 7b: aim=0.5 应 a_off≈180,实际 %s" % l_mid["a_off"]); failures += 1
	if absf(float(WL.landing(0.0, WL.POWER_SWEET)["a_off"])) > 0.01:
		print("FAIL 7c: aim=0 应 a_off≈0"); failures += 1
	if float(WL.landing(0.5, 1.0)["r"]) <= float(l_mid["r"]):
		print("FAIL 7d: 偏离甜点 r 应更大"); failures += 1

	# 7e. aim_for 往返:每档 aim_for(n) 都能确定命中该档
	for n in [&"jackpot", &"vermin", &"x100", &"x5", &"x20a"]:
		if WL.segment_at(WL.aim_for(n) * 360.0, 0.0)["name"] != n:
			print("FAIL 7e: aim_for(%s) 应命中 %s" % [n, n]); failures += 1

	# 8. fan_offsets:居中对称,和≈0,长度对
	var fan := WL.fan_offsets(3)
	if fan.size() != 3 or absf(float(fan[0]) + float(fan[2])) > 0.01 or absf(float(fan[1])) > 0.01:
		print("FAIL 8: fan_offsets(3) 应对称居中,实际 %s" % str(fan)); failures += 1
	if WL.fan_offsets(1).size() != 1 or absf(float(WL.fan_offsets(1)[0])) > 0.01:
		print("FAIL 8b: fan_offsets(1) 应 [0]"); failures += 1

	if failures == 0:
		print("test_fortune_wheel: ALL PASS"); quit(0)
	else:
		print("test_fortune_wheel: %d FAILURE(S)" % failures); quit(1)
