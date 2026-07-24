extends SceneTree
## SushiRoom(制作时长 + KitInventory 食材 + 解锁式开关协同)headless 断言。
## 运行:godot --headless --path . -s res://test/test_fortune_sushi.gd
## 重点:① 手动 craft 消耗食材 + 计时完成入账 ② craft_speed/ribbons_per_sushi 升级 ③ 自动厨师期望率
## ④ 解锁高级配方 → 往别房 throws_per_sec 注册永久开关(规则开关型协同)⑤ 经共享 KitModifiers 放大飞镖(跨房)⑥ 持久化。
const Currency := preload("res://examples/fortune-mill/systems/currency.gd")
const KitModifiers := preload("res://addons/godot-core-kit/modifiers/kit_modifiers.gd")
const SushiRoom := preload("res://examples/fortune-mill/systems/sushi_room.gd")
const DartsRoom := preload("res://examples/fortune-mill/systems/darts_room.gd")
const SushiRecipeDef := preload("res://examples/fortune-mill/defs/sushi_recipe_def.gd")
const SushiUpgradeDef := preload("res://examples/fortune-mill/defs/sushi_upgrade_def.gd")
const KitDataRegistry := preload("res://addons/godot-core-kit/data/kit_data_registry.gd")


func _rdef(id: StringName, ct: float, rv: float, ing: StringName, ic: int, deflt: bool, ucost: float, st: StringName, sop: StringName, sv: float):
	var d = SushiRecipeDef.new()
	d.id = id; d.craft_time = ct; d.ribbon_value = rv; d.ingredient = ing; d.ingredient_count = ic
	d.unlocked_by_default = deflt; d.unlock_cost = ucost
	d.switch_target = st; d.switch_op = sop; d.switch_value = sv
	return d


func _udef(id: StringName, kind: StringName, target: StringName, op: StringName, eff: float, base: float, growth: float, maxl: int):
	var d = SushiUpgradeDef.new()
	d.id = id; d.kind = kind; d.target = target; d.op = op
	d.effect_per_level = eff; d.base_cost = base; d.growth = growth; d.max_level = maxl
	return d


func _reg():
	var reg = KitDataRegistry.new()
	reg.register(&"sushi_recipe", &"cucumber_roll", _rdef(&"cucumber_roll", 3.0, 5.0, &"rice", 2, true, 0.0, &"", &"mul", 1.0))
	reg.register(&"sushi_recipe", &"dragon_roll", _rdef(&"dragon_roll", 12.0, 70.0, &"eel", 3, false, 5000.0, &"throws_per_sec", &"mul", 2.0))
	reg.register(&"sushi_upgrade", &"sharper_knife", _udef(&"sharper_knife", &"value", &"ribbons_per_sushi", &"mul", 0.4, 30.0, 1.35, -1))
	reg.register(&"sushi_upgrade", &"faster_hands", _udef(&"faster_hands", &"speed", &"craft_speed", &"mul", 0.5, 60.0, 1.4, -1))
	reg.register(&"sushi_upgrade", &"auto_chef", _udef(&"auto_chef", &"automation", &"auto_chef", &"add", 1.0, 900.0, 1.8, 30))
	return reg


func _room(reg) -> Array:
	var ribbons = Currency.new(0.0)
	var mods = KitModifiers.new()
	var room = SushiRoom.new(ribbons, mods, reg)
	return [room, ribbons, mods]


func _initialize() -> void:
	var failures := 0
	var reg = _reg()

	# 1. 手动 craft:补货 → 扣食材开工 → 计时完成入账
	var t1 = _room(reg); var r1 = t1[0]; var rb1 = t1[1]
	r1.restock(&"rice", 10)
	if r1.ingredient_count(&"rice") != 10:
		print("FAIL 1a: 补货后 rice 应 10,实际 %d" % r1.ingredient_count(&"rice")); failures += 1
	if not r1.start_craft() or r1.ingredient_count(&"rice") != 8 or not r1.is_crafting():
		print("FAIL 1b: start_craft 应扣 2 rice 并开工(rice=%d crafting=%s)" % [r1.ingredient_count(&"rice"), r1.is_crafting()]); failures += 1
	var e1a = r1.update(1.0)   # progress 1 < 3,未完成
	if e1a != 0.0 or not r1.is_crafting():
		print("FAIL 1c: 未到制作时长不应完成"); failures += 1
	var e1b = r1.update(2.5)   # progress 3.5 >= 3,完成 award 5
	if e1b <= 0.0 or r1.is_crafting() or absf(rb1.get_amount() - e1b) > 0.0001:
		print("FAIL 1d: 到时应出寿司入账(earned=%s ribbons=%s)" % [e1b, rb1.get_amount()]); failures += 1

	# 2. 食材不足不能开工
	var t2 = _room(reg); var r2 = t2[0]
	if r2.start_craft():
		print("FAIL 2: 无食材不应能开工"); failures += 1

	# 3. faster_hands(craft_speed mul)缩短有效制作时长
	var t3 = _room(reg); var r3 = t3[0]; var rb3 = t3[1]
	var ct_before = r3.craft_time_of(&"cucumber_roll")
	rb3.add(1000.0)
	r3.buy_upgrade(&"faster_hands")
	if not (r3.craft_time_of(&"cucumber_roll") < ct_before):
		print("FAIL 3: faster_hands 后有效制作时长应缩短(%s→%s)" % [ct_before, r3.craft_time_of(&"cucumber_roll")]); failures += 1

	# 4. sharper_knife(ribbons_per_sushi mul)抬高单份产出
	var t4 = _room(reg); var r4 = t4[0]; var rb4 = t4[1]
	r4.restock(&"rice", 10)
	r4.start_craft(); var base_award = r4.update(100.0)
	rb4.add(1000.0)
	r4.buy_upgrade(&"sharper_knife")
	r4.restock(&"rice", 10)
	r4.start_craft(); var up_award = r4.update(100.0)
	if not (up_award > base_award):
		print("FAIL 4: sharper_knife 后单份产出应提高(%s→%s)" % [base_award, up_award]); failures += 1

	# 5. 自动厨师:无 chef 率 0;买 auto_chef → 率 >0 且 produce 入账
	var t5 = _room(reg); var r5 = t5[0]; var rb5 = t5[1]
	if absf(r5.auto_ribbon_rate()) > 0.0001:
		print("FAIL 5a: 无自动厨师产率应 0"); failures += 1
	rb5.add(2000.0)
	r5.buy_upgrade(&"auto_chef")
	if r5.auto_ribbon_rate() <= 0.0:
		print("FAIL 5b: 买 auto_chef 后产率应 >0"); failures += 1
	var before5 = rb5.get_amount()
	r5.produce(1.0)
	if rb5.get_amount() <= before5:
		print("FAIL 5c: produce 应加 ribbons"); failures += 1

	# 6. auto_ribbon_rate 确定性(两次相同)
	if absf(r5.auto_ribbon_rate() - r5.auto_ribbon_rate()) > 0.0001:
		print("FAIL 6: auto_ribbon_rate 应确定性一致"); failures += 1

	# 7. 解锁式开关:买不起 dragon → false;够 ribbons 解锁 → throws_per_sec 挂 ×2 开关
	var t7 = _room(reg); var r7 = t7[0]; var rb7 = t7[1]; var m7 = t7[2]
	m7.set_modifier(&"throws_per_sec", &"base", &"add", 3.0)   # 造一个基值,好观测 ×2 开关
	if r7.is_unlocked(&"dragon_roll") or r7.can_unlock(&"dragon_roll") or r7.unlock_recipe(&"dragon_roll"):
		print("FAIL 7a: 0 ribbons 不应能解锁 dragon"); failures += 1
	var tps_before = m7.value_for(&"throws_per_sec", 0.0)
	rb7.add(6000.0)
	if not r7.can_unlock(&"dragon_roll") or not r7.unlock_recipe(&"dragon_roll") or not r7.is_unlocked(&"dragon_roll"):
		print("FAIL 7b: 够 ribbons 应能解锁 dragon"); failures += 1
	if absf(m7.value_for(&"throws_per_sec", 0.0) - tps_before * 2.0) > 0.0001:
		print("FAIL 7c: 解锁 dragon 应把 throws_per_sec ×2(%s→%s)" % [tps_before, m7.value_for(&"throws_per_sec", 0.0)]); failures += 1

	# 8. 跨房协同:同一 modifiers 喂 DartsRoom,解锁 dragon 后飞镖 auto 率 ×2(规则开关)
	var reg8 = _reg()
	var rb8 = Currency.new(0.0); var gold8 = Currency.new(0.0); var m8 = KitModifiers.new()
	var sushi8 = SushiRoom.new(rb8, m8, reg8)
	var darts8 = DartsRoom.new(gold8, m8, reg8); darts8.seed_rng(11)
	m8.set_modifier(&"throws_per_sec", &"tauto", &"add", 2.0)
	var darts_before := darts8.auto_gold_rate()
	rb8.add(6000.0)
	sushi8.unlock_recipe(&"dragon_roll")
	var darts_after := darts8.auto_gold_rate()
	if darts_before <= 0.0 or absf(darts_after - darts_before * 2.0) > 0.01:
		print("FAIL 8: 跨房——解锁 dragon 后飞镖率应 ×2(%s→%s)" % [darts_before, darts_after]); failures += 1

	# 9. bribe Hivemind:未达门槛不能,达 1M 门槛能
	var t9 = _room(reg); var r9 = t9[0]; var rb9 = t9[1]
	if r9.can_bribe() or r9.bribe():
		print("FAIL 9a: 未达门槛不能贿赂"); failures += 1
	rb9.set_amount(SushiRoom.BRIBE_COST)
	if not r9.can_bribe() or not r9.bribe() or not r9.is_cleared():
		print("FAIL 9b: 达门槛应能贿赂并 cleared"); failures += 1

	# 10. 持久化:买升级 + 解锁 dragon(开关)+ 进行中制作(live),to_dict → 新 room from_dict:
	#     升级/解锁/开关重建;进行中制作不持久;食材柜持久(craft 已扣)
	var t10 = _room(reg); var r10 = t10[0]; var rb10 = t10[1]
	rb10.add(7000.0)
	r10.buy_upgrade(&"sharper_knife")
	r10.unlock_recipe(&"dragon_roll")
	r10.restock(&"rice", 5)
	r10.start_craft()   # 造一个 live craft(消耗 2 rice → 剩 3)
	var snap10 = r10.to_dict()
	var m10b = KitModifiers.new()
	m10b.set_modifier(&"throws_per_sec", &"base", &"add", 1.0)
	var r10b = SushiRoom.new(Currency.new(0.0), m10b, reg)
	r10b.from_dict(snap10)
	if r10b.level_of(&"sharper_knife") != 1:
		print("FAIL 10a: from_dict 应恢复 sharper_knife level1"); failures += 1
	if not r10b.is_unlocked(&"dragon_roll"):
		print("FAIL 10b: from_dict 应恢复 dragon 解锁"); failures += 1
	if absf(m10b.value_for(&"throws_per_sec", 0.0) - 2.0) > 0.0001:
		print("FAIL 10c: from_dict 应重放 dragon 跨房开关(×2 → 2.0),实际 %s" % m10b.value_for(&"throws_per_sec", 0.0)); failures += 1
	if r10b.is_crafting():
		print("FAIL 10d: 进行中制作是 live 态,不应持久化"); failures += 1
	if r10b.ingredient_count(&"rice") != 3:
		print("FAIL 10e: 食材柜应持久化(craft 扣 2 后剩 3),实际 %d" % r10b.ingredient_count(&"rice")); failures += 1

	if failures == 0:
		print("test_fortune_sushi: ALL PASS")
		quit(0)
	else:
		print("test_fortune_sushi: %d FAILURE(S)" % failures)
		quit(1)
