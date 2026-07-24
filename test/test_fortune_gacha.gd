extends SceneTree
## GachaRoom(手动抽卡 + KitInventory 收藏柜 + 被动收集协同)headless 断言。
## 运行:godot --headless --path . -s res://test/test_fortune_gacha.gd
## 重点:① 手动 pull 收集道具 + 产 stuffing ② grant_item 按持有数堆叠被动层(add/mul)
## ③ stuffing_per_pull 价值升级 ④ 自动抽卡期望率 ⑤ 稀有度权重升级抬高期望
## ⑥ 被动收集协同经共享 KitModifiers 放大别房(飞镖,第 4 类协同)⑦ 持久化(收藏柜 + 被动层重放)。
const Currency := preload("res://examples/fortune-mill/systems/currency.gd")
const KitModifiers := preload("res://addons/godot-core-kit/modifiers/kit_modifiers.gd")
const GachaRoom := preload("res://examples/fortune-mill/systems/gacha_room.gd")
const DartsRoom := preload("res://examples/fortune-mill/systems/darts_room.gd")
const GachaItemDef := preload("res://examples/fortune-mill/defs/gacha_item_def.gd")
const GachaUpgradeDef := preload("res://examples/fortune-mill/defs/gacha_upgrade_def.gd")
const KitDataRegistry := preload("res://addons/godot-core-kit/data/kit_data_registry.gd")


func _idef(id: StringName, rarity: StringName, weight: float, sval: float, target: StringName, op: StringName, vpc: float):
	var d = GachaItemDef.new()
	d.id = id; d.rarity = rarity; d.weight = weight; d.stuffing_value = sval
	d.target = target; d.op = op; d.value_per_copy = vpc
	return d


func _udef(id: StringName, kind: StringName, target: StringName, op: StringName, eff: float, base: float, growth: float, maxl: int):
	var d = GachaUpgradeDef.new()
	d.id = id; d.kind = kind; d.target = target; d.op = op
	d.effect_per_level = eff; d.base_cost = base; d.growth = growth; d.max_level = maxl
	return d


func _reg():
	var reg = KitDataRegistry.new()
	reg.register(&"gacha_item", &"lucky_cat", _idef(&"lucky_cat", &"common", 60.0, 2.0, &"global_mul", &"mul", 0.02))
	reg.register(&"gacha_item", &"golden_dart", _idef(&"golden_dart", &"rare", 10.0, 12.0, &"gold_per_dart", &"add", 1.0))
	reg.register(&"gacha_item", &"dream_daruma", _idef(&"dream_daruma", &"epic", 2.0, 60.0, &"global_mul", &"mul", 0.1))
	reg.register(&"gacha_upgrade", &"bigger_capsules", _udef(&"bigger_capsules", &"value", &"stuffing_per_pull", &"mul", 0.5, 30.0, 1.4, -1))
	reg.register(&"gacha_upgrade", &"faster_crank", _udef(&"faster_crank", &"speed", &"pull_speed", &"mul", 0.4, 60.0, 1.4, -1))
	reg.register(&"gacha_upgrade", &"auto_gacha", _udef(&"auto_gacha", &"automation", &"auto_puller", &"add", 1.0, 900.0, 1.8, 30))
	reg.register(&"gacha_upgrade", &"rare_fortune", _udef(&"rare_fortune", &"unlock", &"stuffing_per_pull", &"mul", 1.0, 500.0, 2.0, 10))
	return reg


func _room(reg) -> Array:
	var stuffing = Currency.new(0.0)
	var mods = KitModifiers.new()
	var room = GachaRoom.new(stuffing, mods, reg)
	return [room, stuffing, mods]


func _initialize() -> void:
	var failures := 0
	var reg = _reg()

	# 1. 手动 pull:抽一次 → 收集道具 + 产 stuffing
	var t1 = _room(reg); var r1 = t1[0]; var st1 = t1[1]
	r1.seed_rng(7)
	var pr = r1.pull()
	if float(pr["stuffing"]) <= 0.0 or String(pr["item"]).is_empty() or int(pr["owned"]) < 1:
		print("FAIL 1a: pull 应产 stuffing 并收集道具(%s)" % pr); failures += 1
	if st1.get_amount() <= 0.0 or r1.owned(pr["item"]) != int(pr["owned"]):
		print("FAIL 1b: 收藏柜应记录持有数(stuffing=%s)" % st1.get_amount()); failures += 1

	# 2. grant_item 堆叠 add 被动层:持 3 golden_dart → gold_per_dart add=3(base 1 → 4)
	var t2 = _room(reg); var r2 = t2[0]; var m2 = t2[2]
	r2.grant_item(&"golden_dart", 3)
	if r2.owned(&"golden_dart") != 3:
		print("FAIL 2a: 持有数应 3,实际 %d" % r2.owned(&"golden_dart")); failures += 1
	if absf(m2.value_for(&"gold_per_dart", 1.0) - 4.0) > 0.0001:
		print("FAIL 2b: 3 份 golden_dart 应 gold_per_dart→4.0,实际 %s" % m2.value_for(&"gold_per_dart", 1.0)); failures += 1

	# 3. grant_item 堆叠 mul 被动层:持 5 lucky_cat → global_mul=(1.02)^5
	var t3 = _room(reg); var r3 = t3[0]; var m3 = t3[2]
	r3.grant_item(&"lucky_cat", 5)
	if absf(m3.value_for(&"global_mul", 1.0) - pow(1.02, 5)) > 0.0001:
		print("FAIL 3: 5 份 lucky_cat 应 global_mul→%s,实际 %s" % [pow(1.02, 5), m3.value_for(&"global_mul", 1.0)]); failures += 1

	# 4. bigger_capsules(stuffing_per_pull mul 0.5)价值升级 → 单抽价值聚合 ×1.5
	var t4 = _room(reg); var r4 = t4[0]; var st4 = t4[1]; var m4 = t4[2]
	st4.add(100.0)
	r4.buy_upgrade(&"bigger_capsules")
	if absf(m4.value_for(&"stuffing_per_pull", 1.0) - 1.5) > 0.0001:
		print("FAIL 4: bigger_capsules 后 stuffing_per_pull 应 1.5,实际 %s" % m4.value_for(&"stuffing_per_pull", 1.0)); failures += 1

	# 5. 自动抽卡:无 puller 率 0;买 auto_gacha → 率 >0 且 produce 入账
	var t5 = _room(reg); var r5 = t5[0]; var st5 = t5[1]
	if absf(r5.auto_stuffing_rate()) > 0.0001:
		print("FAIL 5a: 无自动抽卡机产率应 0"); failures += 1
	st5.add(2000.0)
	r5.buy_upgrade(&"auto_gacha")
	if r5.auto_stuffing_rate() <= 0.0:
		print("FAIL 5b: 买 auto_gacha 后产率应 >0"); failures += 1
	var before5 = st5.get_amount()
	r5.produce(1.0)
	if st5.get_amount() <= before5:
		print("FAIL 5c: produce 应加 stuffing"); failures += 1

	# 6. auto_stuffing_rate 确定性(两次相同)
	if absf(r5.auto_stuffing_rate() - r5.auto_stuffing_rate()) > 0.0001:
		print("FAIL 6: auto_stuffing_rate 应确定性一致"); failures += 1

	# 7. rare_fortune(unlock 稀有度权重)抬高期望 → 自动率上升(rare/epic 单抽价值更高)
	var t7 = _room(reg); var r7 = t7[0]; var st7 = t7[1]
	st7.add(3000.0)
	r7.buy_upgrade(&"auto_gacha")
	var rate_before7 = r7.auto_stuffing_rate()
	r7.buy_upgrade(&"rare_fortune")
	if r7.rarity_level() != 1:
		print("FAIL 7a: rare_fortune 后 rarity_level 应 1,实际 %d" % r7.rarity_level()); failures += 1
	if not (r7.auto_stuffing_rate() > rate_before7):
		print("FAIL 7b: 稀有度权重升级应抬高期望产率(%s→%s)" % [rate_before7, r7.auto_stuffing_rate()]); failures += 1

	# 8. 被动收集协同(跨房):同一 modifiers 喂 DartsRoom,收集 golden_dart 后飞镖 auto 率 ×4
	var reg8 = _reg()
	var st8 = Currency.new(0.0); var gold8 = Currency.new(0.0); var m8 = KitModifiers.new()
	var gacha8 = GachaRoom.new(st8, m8, reg8)
	var darts8 = DartsRoom.new(gold8, m8, reg8); darts8.seed_rng(11)
	m8.set_modifier(&"throws_per_sec", &"tauto", &"add", 2.0)   # 造飞镖自动投,好观测
	var darts_before := darts8.auto_gold_rate()
	gacha8.grant_item(&"golden_dart", 3)   # gold_per_dart 1→4
	var darts_after := darts8.auto_gold_rate()
	if darts_before <= 0.0 or absf(darts_after - darts_before * 4.0) > 0.01:
		print("FAIL 8: 跨房——收集 3 golden_dart 后飞镖率应 ×4(%s→%s)" % [darts_before, darts_after]); failures += 1

	# 9. bribe Executor:未达门槛不能,达 1M 门槛能
	var t9 = _room(reg); var r9 = t9[0]; var st9 = t9[1]
	if r9.can_bribe() or r9.bribe():
		print("FAIL 9a: 未达门槛不能贿赂"); failures += 1
	st9.set_amount(GachaRoom.BRIBE_COST)
	if not r9.can_bribe() or not r9.bribe() or not r9.is_cleared():
		print("FAIL 9b: 达门槛应能贿赂并 cleared"); failures += 1

	# 10. 持久化:买升级 + 稀有度档 + 收集道具,to_dict → 新 room from_dict:
	#     升级/rarity_level/收藏柜/被动层全重建
	var t10 = _room(reg); var r10 = t10[0]; var st10 = t10[1]
	st10.add(4000.0)
	r10.buy_upgrade(&"bigger_capsules")
	r10.buy_upgrade(&"rare_fortune")
	r10.grant_item(&"golden_dart", 2)   # gold_per_dart 1→3
	r10.grant_item(&"lucky_cat", 4)     # global_mul (1.02)^4
	var snap10 = r10.to_dict()
	var m10b = KitModifiers.new()
	var r10b = GachaRoom.new(Currency.new(0.0), m10b, reg)
	r10b.from_dict(snap10)
	if r10b.level_of(&"bigger_capsules") != 1:
		print("FAIL 10a: from_dict 应恢复 bigger_capsules level1"); failures += 1
	if r10b.rarity_level() != 1:
		print("FAIL 10b: from_dict 应恢复 rarity_level 1,实际 %d" % r10b.rarity_level()); failures += 1
	if r10b.owned(&"golden_dart") != 2 or r10b.owned(&"lucky_cat") != 4:
		print("FAIL 10c: from_dict 应恢复收藏柜(golden=%d cat=%d)" % [r10b.owned(&"golden_dart"), r10b.owned(&"lucky_cat")]); failures += 1
	if absf(m10b.value_for(&"gold_per_dart", 1.0) - 3.0) > 0.0001:
		print("FAIL 10d: from_dict 应重放 golden_dart 被动层(→3.0),实际 %s" % m10b.value_for(&"gold_per_dart", 1.0)); failures += 1
	if absf(m10b.value_for(&"global_mul", 1.0) - pow(1.02, 4)) > 0.0001:
		print("FAIL 10e: from_dict 应重放 lucky_cat 被动层(→%s),实际 %s" % [pow(1.02, 4), m10b.value_for(&"global_mul", 1.0)]); failures += 1

	if failures == 0:
		print("test_fortune_gacha: ALL PASS")
		quit(0)
	else:
		print("test_fortune_gacha: %d FAILURE(S)" % failures)
		quit(1)
