extends SceneTree
## DartsRoom(命运转盘模型)headless 断言。运行:godot --headless --path . -s res://test/test_fortune_darts.gd
const Currency := preload("res://examples/fortune-mill/systems/currency.gd")
const KitModifiers := preload("res://examples/fortune-mill/systems/kit_modifiers.gd")
const WL := preload("res://examples/fortune-mill/systems/wheel_layout.gd")
const DartsRoom := preload("res://examples/fortune-mill/systems/darts_room.gd")
const DartUpgradeDef := preload("res://examples/fortune-mill/defs/dart_upgrade_def.gd")
const KitDataRegistry := preload("res://addons/godot-core-kit/data/kit_data_registry.gd")


func _def(id, kind, target, op, eff, base, growth, maxl):
	var d = DartUpgradeDef.new()
	d.id = id; d.kind = kind; d.target = target; d.op = op
	d.effect_per_level = eff; d.base_cost = base; d.growth = growth; d.max_level = maxl
	return d


func _reg() -> Object:
	var reg = KitDataRegistry.new()
	reg.register(&"dart_upgrade", &"sharper_darts", _def(&"sharper_darts", &"value", &"gold_per_dart", &"add", 1.0, 10.0, 1.15, -1))
	reg.register(&"dart_upgrade", &"double_dart", _def(&"double_dart", &"multi", &"darts_per_throw", &"add", 1.0, 100.0, 2.5, 9))
	reg.register(&"dart_upgrade", &"widen_zone", _def(&"widen_zone", &"zone", &"win_zone", &"add", 6.0, 50.0, 1.8, 16))
	reg.register(&"dart_upgrade", &"hire_ai", _def(&"hire_ai", &"automation", &"throws_per_sec", &"add", 0.5, 500.0, 1.9, 25))
	return reg


func _room(reg) -> Array:
	var cur = Currency.new(0.0)
	var mods = KitModifiers.new()
	var room = DartsRoom.new(cur, mods, reg)
	room.seed_rng(12345)
	return [room, cur, mods]


## 用 landing 反推能命中 jackpot 的 (aim,power,wheel_angle):
## 令 aim=0.5(a_off=0)、power=SWEET(r=0)→ hit_angle=wheel_angle;设 wheel_angle=jackpot 中心。
func _aim_jackpot(room) -> void:
	room.wheel_angle = WL.jackpot_center()


func _initialize() -> void:
	var failures := 0

	# 1. throw(甜点+对准 jackpot) → 单镖 gold = base(1.0)×500×radial(2.0)×gmul(1.0) = 1000
	var t = _room(_reg()); var room = t[0]; var cur = t[1]
	_aim_jackpot(room)
	var r = room.throw(0.5, WL.POWER_SWEET)
	if absf(float(r["gold"]) - 1000.0) > 0.01 or absf(cur.get_amount() - float(r["gold"])) > 0.01:
		print("FAIL 1: jackpot 甜点单镖应 1000 并入账,实际 %s" % r["gold"]); failures += 1
	if r["hits"].size() != 1 or r["hits"][0]["seg"] != &"jackpot":
		print("FAIL 1b: hits 应 1 支且命中 jackpot"); failures += 1

	# 2. throw 命中 vermin → payout 0
	var t2 = _room(_reg()); var room2 = t2[0]; var cur2 = t2[1]
	room2.wheel_angle = WL.vermin_center()
	var r2 = room2.throw(0.5, WL.POWER_SWEET)
	if absf(float(r2["gold"])) > 0.01:
		print("FAIL 2: vermin 应 payout 0,实际 %s" % r2["gold"]); failures += 1

	# 3. radial:同 jackpot,力度=0(松手即投,r=|0-SWEET|/SWEET=1,radial=1.0)→ 500,小于甜点 1000
	var t3 = _room(_reg()); var room3 = t3[0]
	_aim_jackpot(room3)
	var r3 = room3.throw(0.5, 0.0)
	if absf(float(r3["gold"]) - 500.0) > 0.01:
		print("FAIL 3: jackpot 边缘力度应 500(radial 1.0),实际 %s" % r3["gold"]); failures += 1

	# 4. 扇形多镖:买 double_dart 一级 → darts_per_throw=2;throw 返 2 个 hits,各自结算
	var t4 = _room(_reg()); var room4 = t4[0]; var cur4 = t4[1]
	cur4.add(1000.0)
	room4.buy_upgrade(&"double_dart")
	_aim_jackpot(room4)
	var r4 = room4.throw(0.5, WL.POWER_SWEET)
	if r4["hits"].size() != 2:
		print("FAIL 4: double_dart 后应 2 支,实际 %d" % r4["hits"].size()); failures += 1

	# 5. widen_zone:jackpot 带外一点,未升级非 jackpot、升级后变 jackpot → payout 升
	var t5 = _room(_reg()); var room5 = t5[0]; var cur5 = t5[1]; var mods5 = t5[2]
	# 令 hit_angle 落在 jackpot 中心 + 基础半宽 + 8°(基础带外)
	room5.wheel_angle = WL.jackpot_center() + WL.jackpot_half_base() + 8.0
	var before = room5.throw(0.5, WL.POWER_SWEET)   # 非 jackpot
	cur5.add(100000.0)
	for _i in 3: room5.buy_upgrade(&"widen_zone")   # win_zone +18°
	var after = room5.throw(0.5, WL.POWER_SWEET)    # 现应命中 jackpot
	if after["hits"][0]["seg"] != &"jackpot" or float(after["gold"]) <= float(before["gold"]):
		print("FAIL 5: widen_zone 应把该落点变 jackpot 且 payout 升"); failures += 1

	# 6. auto_gold_rate:无 hire_ai → 0;produce 不加
	var t6 = _room(_reg()); var room6 = t6[0]; var cur6 = t6[1]
	if absf(room6.auto_gold_rate()) > 0.0001:
		print("FAIL 6: 无自动化产率应 0"); failures += 1
	var g6 = cur6.get_amount(); room6.produce(5.0)
	if absf(cur6.get_amount() - g6) > 0.0001:
		print("FAIL 6b: 无自动化 produce 不加 gold"); failures += 1

	# 7. hire_ai:买一级 → throws_per_sec>0 且 auto_gold_rate>0;produce 入账
	var t7 = _room(_reg()); var room7 = t7[0]; var cur7 = t7[1]; var mods7 = t7[2]
	cur7.add(1000.0)
	if not room7.buy_upgrade(&"hire_ai") or room7.level_of(&"hire_ai") != 1:
		print("FAIL 7a: 买 hire_ai 应成功 level1"); failures += 1
	if room7.auto_gold_rate() <= 0.0:
		print("FAIL 7b: hire_ai 后产率应 >0"); failures += 1
	var before7 = cur7.get_amount()
	var made = room7.produce(2.0)
	if made <= 0.0 or absf(cur7.get_amount() - (before7 + made)) > 0.0001:
		print("FAIL 7c: produce 应入账"); failures += 1

	# 8. AI 稳准:ai_skill 越高 auto_gold_rate 越高(在线=离线同一 rate)
	var t8 = _room(_reg()); var room8 = t8[0]; var mods8 = t8[2]
	mods8.set_modifier(&"throws_per_sec", &"x", &"add", 1.0)
	mods8.set_modifier(&"ai_skill", &"y", &"add", 0.0)
	var rate_lo = room8.auto_gold_rate()
	mods8.set_modifier(&"ai_skill", &"y", &"add", 1.0)
	var rate_hi = room8.auto_gold_rate()
	if not (rate_hi > rate_lo and rate_lo > 0.0):
		print("FAIL 8: ai_skill 高应产率更高,lo=%s hi=%s" % [rate_lo, rate_hi]); failures += 1

	# 9. cost_of / buy 扣款 / 买不起
	var t9 = _room(_reg()); var room9 = t9[0]; var cur9 = t9[1]
	if absf(room9.cost_of(&"sharper_darts") - 10.0) > 0.0001 or room9.buy_upgrade(&"sharper_darts"):
		print("FAIL 9: level0 成本 10 且没钱买不了"); failures += 1
	cur9.add(100.0); room9.buy_upgrade(&"sharper_darts")
	if absf(cur9.get_amount() - 90.0) > 0.0001 or room9.level_of(&"sharper_darts") != 1:
		print("FAIL 9b: 买后扣款 90 + level1"); failures += 1

	# 10. bribe:未达门槛不能;达门槛(1M)可 + cleared
	var t10 = _room(_reg()); var room10 = t10[0]; var cur10 = t10[1]
	if room10.can_bribe() or room10.bribe():
		print("FAIL 10a: 未达门槛不能贿赂"); failures += 1
	cur10.set_amount(DartsRoom.BRIBE_COST)
	if not room10.can_bribe() or not room10.bribe() or not room10.is_cleared():
		print("FAIL 10b: 达门槛应贿赂 + cleared"); failures += 1

	# 11. to_dict/from_dict 往返 + 完整重算(空存档清残留 modifier)
	var t11 = _room(_reg()); var room11 = t11[0]; var cur11 = t11[1]; var mods11 = t11[2]
	cur11.add(1000.0); room11.buy_upgrade(&"sharper_darts")
	if absf(mods11.value_for(&"gold_per_dart", DartsRoom.DART_BASE) - 2.0) > 0.0001:
		print("FAIL 11a: sharper 后 gold_per_dart 2.0"); failures += 1
	var snap = room11.to_dict()
	var t11b = _room(_reg()); var room11b = t11b[0]; var mods11b = t11b[2]
	room11b.from_dict(snap)
	if room11b.level_of(&"sharper_darts") != 1 or absf(mods11b.value_for(&"gold_per_dart", DartsRoom.DART_BASE) - 2.0) > 0.0001:
		print("FAIL 11b: from_dict 应恢复 level + modifier"); failures += 1
	room11.from_dict({"levels": {}, "cleared": false})   # 复用同实例加载空档
	if room11.level_of(&"sharper_darts") != 0 or absf(mods11.value_for(&"gold_per_dart", DartsRoom.DART_BASE) - DartsRoom.DART_BASE) > 0.0001:
		print("FAIL 11c: 空存档应清残留 modifier"); failures += 1

	# 12. hire_ai from_dict 清残留:买后 ai_skill/throws_per_sec >0,空档后回 0
	var t12 = _room(_reg()); var room12 = t12[0]; var cur12 = t12[1]; var mods12 = t12[2]
	cur12.add(1000.0); room12.buy_upgrade(&"hire_ai")
	room12.from_dict({"levels": {}, "cleared": false})
	if absf(mods12.value_for(&"throws_per_sec", 0.0)) > 0.0001 or absf(mods12.value_for(&"ai_skill", 0.0)) > 0.0001:
		print("FAIL 12: hire_ai 空档应清 throws_per_sec + ai_skill"); failures += 1

	if failures == 0:
		print("test_fortune_darts: ALL PASS"); quit(0)
	else:
		print("test_fortune_darts: %d FAILURE(S)" % failures); quit(1)
