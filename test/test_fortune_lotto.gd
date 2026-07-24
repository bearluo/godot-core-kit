extends SceneTree
## LottoRoom + 跨房协同 headless 断言。运行:godot --headless --path . -s res://test/test_fortune_lotto.gd
## 重点:JACKPOT → global_mul 永久乘法层 → 经共享 KitModifiers 放大飞镖房(跨房协同证明)。
const Currency := preload("res://examples/fortune-mill/systems/currency.gd")
const KitModifiers := preload("res://addons/godot-core-kit/modifiers/kit_modifiers.gd")
const LottoRoom := preload("res://examples/fortune-mill/systems/lotto_room.gd")
const DartsRoom := preload("res://examples/fortune-mill/systems/darts_room.gd")
const LottoUpgradeDef := preload("res://examples/fortune-mill/defs/lotto_upgrade_def.gd")
const KitDataRegistry := preload("res://addons/godot-core-kit/data/kit_data_registry.gd")


func _ldef(id: StringName, kind: StringName, target: StringName, op: StringName, eff: float, base: float, growth: float, maxl: int):
	var d = LottoUpgradeDef.new()
	d.id = id; d.kind = kind; d.target = target; d.op = op
	d.effect_per_level = eff; d.base_cost = base; d.growth = growth; d.max_level = maxl
	return d


func _reg():
	var reg = KitDataRegistry.new()
	reg.register(&"lotto_upgrade", &"bigger", _ldef(&"bigger", &"value", &"money_per_card", &"mul", 0.5, 15.0, 1.3, -1))
	reg.register(&"lotto_upgrade", &"auto", _ldef(&"auto", &"automation", &"scratches_per_sec", &"add", 0.5, 600.0, 1.9, 25))
	reg.register(&"lotto_upgrade", &"charm", _ldef(&"charm", &"unlock", &"jackpot_weight", &"add", 1.0, 400.0, 2.0, 10))
	return reg


func _room(reg) -> Array:
	var money = Currency.new(0.0)
	var mods = KitModifiers.new()
	var room = LottoRoom.new(money, mods, reg)
	room.seed_rng(777)
	return [room, money, mods]


## 循环刮至首次命中 jackpot(有界),返回是否命中。
func _scratch_to_jackpot(room, cap: int) -> bool:
	for _n in cap:
		if room.scratch()["jackpot"]:
			return true
	return false


func _initialize() -> void:
	var failures := 0
	var reg = _reg()

	# 1. 中奖表常量:5 档,末档为 JACKPOT 200x,JACKPOT_MUL=1.5
	if LottoRoom.PRIZE_MULT.size() != 5 or LottoRoom.JACKPOT_TIER != 4 or LottoRoom.PRIZE_MULT[4] != 200.0:
		print("FAIL 1: 中奖表应 5 档、末档 jackpot 200x"); failures += 1
	if absf(LottoRoom.JACKPOT_MUL - 1.5) > 0.0001:
		print("FAIL 1b: JACKPOT_MUL 应 1.5"); failures += 1

	# 2. scratch 产 money > 0 且入账
	var t2 = _room(reg); var r2 = t2[0]; var m2 = t2[1]
	var s2 = r2.scratch()
	if s2["money"] <= 0.0 or absf(m2.get_amount() - s2["money"]) > 0.0001:
		print("FAIL 2: scratch 应产正 money 并入账,实际 %s" % s2); failures += 1

	# 3. bigger_prizes(mul money_per_card)后自动率提高
	var t3 = _room(reg); var r3 = t3[0]; var money3 = t3[1]; var mods3 = t3[2]
	mods3.set_modifier(&"scratches_per_sec", &"tauto", &"add", 1.0)
	var rate_before = r3.auto_money_rate()
	money3.add(100.0)
	r3.buy_upgrade(&"bigger")
	if r3.auto_money_rate() <= rate_before:
		print("FAIL 3: 买 bigger 后 auto 率应提高"); failures += 1

	# 4. 无自动化(scratches_per_sec 基 0)→ auto 率 0;produce 不加 money
	var t4 = _room(reg); var r4 = t4[0]; var money4 = t4[1]
	if absf(r4.auto_money_rate()) > 0.0001:
		print("FAIL 4a: 无自动化产率应 0"); failures += 1
	var b4 = money4.get_amount()
	r4.produce(5.0)
	if absf(money4.get_amount() - b4) > 0.0001:
		print("FAIL 4b: 无自动化 produce 不应加 money"); failures += 1

	# 5. auto_money_rate 确定性(两次相同)
	var t5 = _room(reg); var r5 = t5[0]; var mods5 = t5[2]
	mods5.set_modifier(&"scratches_per_sec", &"tauto", &"add", 2.0)
	if absf(r5.auto_money_rate() - r5.auto_money_rate()) > 0.0001:
		print("FAIL 5: auto_money_rate 应确定性一致"); failures += 1

	# 6. JACKPOT:循环刮至命中 → _jackpot_count≥1 且 global_mul = 1.5^count
	var t6 = _room(reg); var r6 = t6[0]; var mods6 = t6[2]
	if not _scratch_to_jackpot(r6, 50000) or r6.jackpot_count() < 1:
		print("FAIL 6a: 循环刮应命中 jackpot"); failures += 1
	var gmul6 = mods6.value_for(&"global_mul", 1.0)
	if gmul6 <= 1.0 or absf(gmul6 - pow(LottoRoom.JACKPOT_MUL, r6.jackpot_count())) > 0.0001:
		print("FAIL 6b: global_mul 应 1.5^count,实际 %s (count %d)" % [gmul6, r6.jackpot_count()]); failures += 1

	# 7. 跨房协同:同一 modifiers 喂 DartsRoom,jackpot 后飞镖 auto 率 ×1.5^count
	var t7reg = _reg()
	var gold7 = Currency.new(0.0); var money7 = Currency.new(0.0); var mods7 = KitModifiers.new()
	var lotto7 = LottoRoom.new(money7, mods7, t7reg); lotto7.seed_rng(2024)
	var darts7 = DartsRoom.new(gold7, mods7, t7reg); darts7.seed_rng(99)
	mods7.set_modifier(&"throws_per_sec", &"tauto", &"add", 3.0)
	var darts_before = darts7.auto_gold_rate()
	var hit7 = _scratch_to_jackpot(lotto7, 50000)
	var darts_after = darts7.auto_gold_rate()
	var factor7 = pow(LottoRoom.JACKPOT_MUL, lotto7.jackpot_count())
	if not hit7 or darts_before <= 0.0:
		print("FAIL 7a: 前置飞镖率>0 且命中 jackpot"); failures += 1
	elif absf(darts_after - darts_before * factor7) > 0.01:
		print("FAIL 7b: 跨房——飞镖率应 ×%s(%s→%s)" % [factor7, darts_before, darts_after]); failures += 1

	# 8. jackpot 持久化:to_dict → 新 room(全新 modifiers)from_dict → count + global_mul 重放
	var snap8 = r6.to_dict()
	var count8 = r6.jackpot_count()
	var mods8b = KitModifiers.new()
	var r8b = LottoRoom.new(Currency.new(0.0), mods8b, reg)
	r8b.from_dict(snap8)
	if r8b.jackpot_count() != count8:
		print("FAIL 8a: from_dict 应恢复 jackpot_count"); failures += 1
	if absf(mods8b.value_for(&"global_mul", 1.0) - pow(LottoRoom.JACKPOT_MUL, count8)) > 0.0001:
		print("FAIL 8b: from_dict 应重放 global_mul"); failures += 1

	# 9. from_dict 清残留:复用同一 room 加载空存档 → global_mul 回 1、money_per_card 回 base
	var t9 = _room(reg); var r9 = t9[0]; var money9 = t9[1]; var mods9 = t9[2]
	money9.add(100.0)
	r9.buy_upgrade(&"bigger")
	_scratch_to_jackpot(r9, 50000)
	r9.from_dict({"levels": {}, "cleared": false, "jackpots": 0})
	if absf(mods9.value_for(&"global_mul", 1.0) - 1.0) > 0.0001:
		print("FAIL 9a: from_dict 空档后 global_mul 应回 1,实际 %s" % mods9.value_for(&"global_mul", 1.0)); failures += 1
	if absf(mods9.value_for(&"money_per_card", LottoRoom.CARD_BASE) - LottoRoom.CARD_BASE) > 0.0001:
		print("FAIL 9b: from_dict 应清 money_per_card 残留"); failures += 1

	# 10. bribe Gorgon:未达门槛不能,达 1M 门槛能
	var t10 = _room(reg); var r10 = t10[0]; var money10 = t10[1]
	if r10.can_bribe() or r10.bribe():
		print("FAIL 10a: 未达门槛不能贿赂"); failures += 1
	money10.set_amount(LottoRoom.BRIBE_COST)
	if not r10.can_bribe() or not r10.bribe() or not r10.is_cleared():
		print("FAIL 10b: 达门槛应能贿赂并 cleared"); failures += 1

	if failures == 0:
		print("test_fortune_lotto: ALL PASS")
		quit(0)
	else:
		print("test_fortune_lotto: %d FAILURE(S)" % failures)
		quit(1)
