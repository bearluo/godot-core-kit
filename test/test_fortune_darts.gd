extends SceneTree
## DartsRoom headless 断言。运行:godot --headless --path . -s res://test/test_fortune_darts.gd
const Currency := preload("res://examples/fortune-mill/systems/currency.gd")
const KitModifiers := preload("res://examples/fortune-mill/systems/kit_modifiers.gd")
const DartsRoom := preload("res://examples/fortune-mill/systems/darts_room.gd")
const DartUpgradeDef := preload("res://examples/fortune-mill/defs/dart_upgrade_def.gd")
const KitDataRegistry := preload("res://addons/godot-core-kit/data/kit_data_registry.gd")


func _make_room(reg) -> Array:
	var cur = Currency.new(0.0)
	var mods = KitModifiers.new()
	var room = DartsRoom.new(cur, mods, reg)
	room.seed_rng(12345)
	return [room, cur, mods]


func _def(id: StringName, kind: StringName, target: StringName, op: StringName, eff: float, base: float, growth: float, maxl: int):
	var d = DartUpgradeDef.new()
	d.id = id; d.kind = kind; d.target = target; d.op = op
	d.effect_per_level = eff; d.base_cost = base; d.growth = growth; d.max_level = maxl
	return d


func _initialize() -> void:
	var failures := 0

	# 注册两条升级:一条 add 值,一条 unlock
	var reg = KitDataRegistry.new()
	reg.register(&"dart_upgrade", &"sharper", _def(&"sharper", &"value", &"gold_per_dart", &"add", 1.0, 10.0, 1.15, -1))
	reg.register(&"dart_upgrade", &"unlock", _def(&"unlock", &"unlock", &"gold_per_dart", &"add", 1.0, 50.0, 1.8, 16))

	# 1. 靶心表 17 档 + 首尾值
	if DartsRoom.BULLSEYE.size() != 17 or DartsRoom.BULLSEYE[0] != 1.5 or DartsRoom.BULLSEYE[16] != 2500.0:
		print("FAIL 1: 靶心表应 17 档 1.5..2500"); failures += 1

	# 2. throw 产 gold > 0 且入账
	var t = _make_room(reg)
	var room = t[0]; var cur = t[1]
	var r = room.throw()
	if r["gold"] <= 0.0 or cur.get_amount() != r["gold"]:
		print("FAIL 2: throw 应产正 gold 并入账"); failures += 1

	# 3. 初始仅 1 档(未解锁)时命中倍率恒为 tier1=1.5
	var t3 = _make_room(reg)
	var room3 = t3[0]; var cur3 = t3[1]
	room3.throw()
	# 单镖 base=1.0 × 1.5 = 1.5(无值升级)
	if absf(cur3.get_amount() - 1.5) > 0.0001:
		print("FAIL 3: 初始单镖应 1.0×1.5=1.5,实际 %s" % cur3.get_amount()); failures += 1

	# 4. cost_of:level0 = base_cost
	var t4 = _make_room(reg)
	var room4 = t4[0]
	if absf(room4.cost_of(&"sharper") - 10.0) > 0.0001:
		print("FAIL 4: level0 成本应 base 10"); failures += 1

	# 5. buy_upgrade:钱不够 → false
	if room4.buy_upgrade(&"sharper"):
		print("FAIL 5: 没钱应买不了"); failures += 1

	# 6. 给钱 → 买 sharper → level1 + modifier 生效(gold_per_dart base+1)
	var t6 = _make_room(reg)
	var room6 = t6[0]; var cur6 = t6[1]; var mods6 = t6[2]
	cur6.add(100.0)
	if not room6.buy_upgrade(&"sharper") or room6.level_of(&"sharper") != 1:
		print("FAIL 6a: 买 sharper 应成功 level1"); failures += 1
	# gold_per_dart base=DART_BASE=1.0,加 +1 → value_for=2.0
	if absf(mods6.value_for(&"gold_per_dart", DartsRoom.DART_BASE) - 2.0) > 0.0001:
		print("FAIL 6b: sharper 后 gold_per_dart 应 2.0"); failures += 1
	# 扣款:100 - 10 = 90
	if absf(cur6.get_amount() - 90.0) > 0.0001:
		print("FAIL 6c: 扣款后应 90"); failures += 1

	# 7. 第二级成本 = 10 × 1.15 = 11.5
	if absf(room6.cost_of(&"sharper") - 11.5) > 0.0001:
		print("FAIL 7: level1 成本应 11.5,实际 %s" % room6.cost_of(&"sharper")); failures += 1

	# 8. unlock 升级抬高解锁档数
	var t8 = _make_room(reg)
	var room8 = t8[0]; var cur8 = t8[1]
	cur8.add(1000.0)
	room8.buy_upgrade(&"unlock")
	if room8.max_tier() != 2:  # 初始 1 + 解锁 1
		print("FAIL 8: unlock 一级后 max_tier 应 2,实际 %d" % room8.max_tier()); failures += 1

	# 9. can_bribe / bribe
	var t9 = _make_room(reg)
	var room9 = t9[0]; var cur9 = t9[1]
	if room9.can_bribe() or room9.bribe():
		print("FAIL 9a: 未达门槛不能贿赂"); failures += 1
	cur9.set_amount(DartsRoom.BRIBE_COST)
	if not room9.can_bribe() or not room9.bribe() or not room9.is_cleared():
		print("FAIL 9b: 达门槛应能贿赂并 cleared"); failures += 1

	# 10. to_dict/from_dict 往返:levels + cleared + modifier 重建
	var t10 = _make_room(reg)
	var room10 = t10[0]; var cur10 = t10[1]
	cur10.add(100.0)
	room10.buy_upgrade(&"sharper")
	var snap = room10.to_dict()
	var t10b = _make_room(reg)
	var room10b = t10b[0]; var mods10b = t10b[2]
	room10b.from_dict(snap)
	if room10b.level_of(&"sharper") != 1:
		print("FAIL 10a: from_dict 应恢复 level1"); failures += 1
	if absf(mods10b.value_for(&"gold_per_dart", DartsRoom.DART_BASE) - 2.0) > 0.0001:
		print("FAIL 10b: from_dict 应重建 modifier(gold_per_dart=2.0)"); failures += 1

	# 11. top>1 时加权命中恒落在 [1, max_tier],不越界(历史 Android 越界读教训)
	var t11 = _make_room(reg)
	var room11 = t11[0]; var cur11 = t11[1]
	cur11.add(100000.0)
	room11.buy_upgrade(&"unlock")   # _bullseye_unlock 1 -> max_tier 2
	room11.buy_upgrade(&"unlock")   # _bullseye_unlock 2 -> max_tier 3
	var top11 = room11.max_tier()
	if top11 < 2:
		print("FAIL 11a: 前置 max_tier 应 >=2,实际 %d" % top11); failures += 1
	for _n in 300:
		var tier = room11._roll_tier()
		if tier < 1 or tier > top11 or tier - 1 >= DartsRoom.BULLSEYE.size():
			print("FAIL 11b: _roll_tier 越界 tier=%d (max %d)" % [tier, top11]); failures += 1
			break

	# 12. from_dict 完整重算:复用同一实例加载不含某升级的旧存档,应清除其残留 modifier
	var t12 = _make_room(reg)
	var room12 = t12[0]; var cur12 = t12[1]; var mods12 = t12[2]
	cur12.add(100.0)
	room12.buy_upgrade(&"sharper")   # sharper level1 -> gold_per_dart +1 -> 2.0
	if absf(mods12.value_for(&"gold_per_dart", DartsRoom.DART_BASE) - 2.0) > 0.0001:
		print("FAIL 12a: 前置 sharper 后应 2.0"); failures += 1
	room12.from_dict({"levels": {}, "cleared": false})   # 加载空快照(复用同一 room/mods)
	if room12.level_of(&"sharper") != 0:
		print("FAIL 12b: from_dict 空存档后 sharper 应 0 级"); failures += 1
	if absf(mods12.value_for(&"gold_per_dart", DartsRoom.DART_BASE) - DartsRoom.DART_BASE) > 0.0001:
		print("FAIL 12c: from_dict 应清残留,gold_per_dart 回 base %s,实际 %s" % [DartsRoom.DART_BASE, mods12.value_for(&"gold_per_dart", DartsRoom.DART_BASE)]); failures += 1

	# 13. auto_gold_rate:无自动投升级(throws_per_sec 基值 0)→ 0;produce 不加 gold
	var t13 = _make_room(reg)
	var room13 = t13[0]; var cur13 = t13[1]
	if absf(room13.auto_gold_rate()) > 0.0001:
		print("FAIL 13a: 无自动化产率应 0,实际 %s" % room13.auto_gold_rate()); failures += 1
	var g13 = cur13.get_amount()
	room13.produce(5.0)
	if absf(cur13.get_amount() - g13) > 0.0001:
		print("FAIL 13b: 无自动化 produce 不应加 gold"); failures += 1

	# 14. auto_gold_rate 确定性公式:注入 throws_per_sec=2。top=1 → E[bullseye]=1.5;
	#     darts=1;per_dart=DART_BASE=1.0 → rate=2×1×1×1.5=3.0(确定性,无 RNG)
	var t14 = _make_room(reg)
	var room14 = t14[0]; var cur14 = t14[1]; var mods14 = t14[2]
	mods14.set_modifier(&"throws_per_sec", &"test_auto", &"add", 2.0)
	if absf(room14.auto_gold_rate() - 3.0) > 0.0001:
		print("FAIL 14a: rate 应 2×1×1×1.5=3.0,实际 %s" % room14.auto_gold_rate()); failures += 1
	var made14 = room14.produce(4.0)   # 3×4=12
	if absf(made14 - 12.0) > 0.0001:
		print("FAIL 14b: produce(4s) 应 12,实际 %s" % made14); failures += 1
	if absf(cur14.get_amount() - 12.0) > 0.0001:
		print("FAIL 14c: produce 应入账 12,实际 %s" % cur14.get_amount()); failures += 1
	if absf(room14.produce(0.0)) > 0.0001:
		print("FAIL 14d: produce(0) 应 0"); failures += 1

	# 15. 买 Rattling Gunner 自动投升级 → throws_per_sec 抬到 >0,rate 随之 >0
	var reg15 = KitDataRegistry.new()
	reg15.register(&"dart_upgrade", &"rattling", _def(&"rattling", &"automation", &"throws_per_sec", &"add", 0.5, 500.0, 1.9, 25))
	var t15 = _make_room(reg15)
	var room15 = t15[0]; var cur15 = t15[1]
	cur15.add(1000.0)
	if not room15.buy_upgrade(&"rattling") or room15.level_of(&"rattling") != 1:
		print("FAIL 15a: 买 rattling 应成功 level1"); failures += 1
	# L1: throws_per_sec +0.5;top=1,per_dart=1,darts=1 → rate=0.5×1×1×1.5=0.75
	if absf(room15.auto_gold_rate() - 0.75) > 0.0001:
		print("FAIL 15b: rattling L1 rate 应 0.75,实际 %s" % room15.auto_gold_rate()); failures += 1

	if failures == 0:
		print("test_fortune_darts: ALL PASS")
		quit(0)
	else:
		print("test_fortune_darts: %d FAILURE(S)" % failures)
		quit(1)
