extends SceneTree
## Prestige(NG+ 元进度:门槛缩放 + prestige 加成 + Lethal Mode)headless 断言。
## 运行:godot --headless --path . -s res://test/test_fortune_prestige.gd
## 重点:① 门槛缩放经共享 bribe_cost_mul(各房 bribe_threshold 读它)② ascend 门槛 ×10 + 发点
## ③ NG+ 专属升级只在 ng≥1 可买,花 prestige 点,施加跨周目存活的 global_mul/gold_per_dart 加成
## ④ prestige 加成经共享 modifiers,跨房间重置(darts.from_dict)存活 ⑤ Lethal Mode 撤加成 + 门槛回 1M
## + 计时 + 最佳时间取 min + 期间禁买 ⑥ 持久化(ng_level/points/levels/best + modifier 重放)。
const Currency := preload("res://examples/fortune-mill/systems/currency.gd")
const KitModifiers := preload("res://examples/fortune-mill/systems/kit_modifiers.gd")
const Prestige := preload("res://examples/fortune-mill/systems/prestige.gd")
const DartsRoom := preload("res://examples/fortune-mill/systems/darts_room.gd")
const PrestigeUpgradeDef := preload("res://examples/fortune-mill/defs/prestige_upgrade_def.gd")
const KitDataRegistry := preload("res://addons/godot-core-kit/data/kit_data_registry.gd")

const M1 := 1_000_000.0
const M10 := 10_000_000.0
const M100 := 100_000_000.0


func _pdef(id: StringName, target: StringName, op: StringName, eff: float, base: float, growth: float, maxl: int):
	var d = PrestigeUpgradeDef.new()
	d.id = id; d.target = target; d.op = op
	d.effect_per_level = eff; d.base_cost = base; d.growth = growth; d.max_level = maxl
	return d


func _reg():
	var reg = KitDataRegistry.new()
	reg.register(&"prestige_upgrade", &"eternal_fortune", _pdef(&"eternal_fortune", &"global_mul", &"mul", 0.5, 1.0, 2.0, -1))
	reg.register(&"prestige_upgrade", &"golden_hands", _pdef(&"golden_hands", &"gold_per_dart", &"add", 5.0, 1.0, 3.0, -1))
	reg.register(&"prestige_upgrade", &"swift_start", _pdef(&"swift_start", &"throws_per_sec", &"add", 0.5, 2.0, 2.5, 10))
	return reg


func _setup(reg) -> Array:
	var mods = KitModifiers.new()
	var prestige = Prestige.new(mods, reg)
	var darts = DartsRoom.new(Currency.new(0.0), mods, reg)   # 只借它读 bribe_threshold
	return [prestige, mods, darts]


func _initialize() -> void:
	var failures := 0
	var reg = _reg()

	# 1. 首周目:ng_level 0、points 0、门槛 = 基础 1M(bribe_cost_mul ×1.0)
	var t1 = _setup(reg); var p1 = t1[0]; var d1 = t1[2]
	if p1.ng_level() != 0 or absf(p1.points()) > 0.0001:
		print("FAIL 1a: 首周目应 ng0 points0(ng=%d pts=%s)" % [p1.ng_level(), p1.points()]); failures += 1
	if absf(d1.bribe_threshold() - M1) > 1.0:
		print("FAIL 1b: ng0 门槛应 1M,实际 %s" % d1.bribe_threshold()); failures += 1

	# 2. NG+ 专属:ng0 时买 prestige 升级应失败(can_buy false)
	if p1.can_buy(&"eternal_fortune") or p1.buy_upgrade(&"eternal_fortune"):
		print("FAIL 2: ng0 不应能买 NG+ 专属升级"); failures += 1

	# 3. ascend:ng→1、reward 1、points 1、门槛 ×10 → 10M
	var t3 = _setup(reg); var p3 = t3[0]; var m3 = t3[1]; var d3 = t3[2]
	var info3 = p3.ascend()
	if int(info3.get("ng_level", 0)) != 1 or absf(float(info3.get("reward", 0.0)) - 1.0) > 0.0001 or absf(p3.points() - 1.0) > 0.0001:
		print("FAIL 3a: ascend 应 ng1 reward1 points1(%s)" % info3); failures += 1
	if absf(d3.bribe_threshold() - M10) > 1.0:
		print("FAIL 3b: ascend 后门槛应 10M,实际 %s" % d3.bribe_threshold()); failures += 1

	# 4. ascend 后买 eternal_fortune(cost 1 ≤ points 1)→ 花光点 + global_mul ×1.5
	if not p3.buy_upgrade(&"eternal_fortune"):
		print("FAIL 4a: ng1 有点应能买 eternal_fortune"); failures += 1
	if absf(p3.points()) > 0.0001:
		print("FAIL 4b: 买后 points 应花光,实际 %s" % p3.points()); failures += 1
	if absf(m3.value_for(&"global_mul", 1.0) - 1.5) > 0.0001:
		print("FAIL 4c: eternal_fortune Lv1 应 global_mul→1.5,实际 %s" % m3.value_for(&"global_mul", 1.0)); failures += 1

	# 5. 点不够(0 < cost 2.0)再买失败
	if p3.buy_upgrade(&"eternal_fortune"):
		print("FAIL 5: 点不够不应能再买"); failures += 1

	# 6. prestige 加成跨房间重置存活:重置 darts(from_dict {})后 global_mul 仍 1.5、门槛仍 10M
	d3.from_dict({})
	if absf(m3.value_for(&"global_mul", 1.0) - 1.5) > 0.0001:
		print("FAIL 6a: 重置 darts 后 prestige global_mul 应存活(1.5),实际 %s" % m3.value_for(&"global_mul", 1.0)); failures += 1
	if absf(d3.bribe_threshold() - M10) > 1.0:
		print("FAIL 6b: 重置 darts 后门槛仍应 10M(prestige 拥有),实际 %s" % d3.bribe_threshold()); failures += 1

	# 7. 二周目 + eternal_fortune Lv2:ng→2、points→2、门槛 100M;买 Lv2(cost 2 ≤ 2)→ global_mul (1.5)^2=2.25
	p3.ascend()
	if p3.ng_level() != 2 or absf(p3.points() - 2.0) > 0.0001:
		print("FAIL 7a: 二周目应 ng2 points2(ng=%d pts=%s)" % [p3.ng_level(), p3.points()]); failures += 1
	if absf(d3.bribe_threshold() - M100) > 1.0:
		print("FAIL 7b: 二周目门槛应 100M,实际 %s" % d3.bribe_threshold()); failures += 1
	if not p3.buy_upgrade(&"eternal_fortune") or p3.level_of(&"eternal_fortune") != 2:
		print("FAIL 7c: 应能买 eternal_fortune 到 Lv2"); failures += 1
	if absf(m3.value_for(&"global_mul", 1.0) - pow(1.5, 2)) > 0.0001:
		print("FAIL 7d: eternal_fortune Lv2 应 global_mul→2.25,实际 %s" % m3.value_for(&"global_mul", 1.0)); failures += 1

	# 8. add 算子升级(golden_hands):ascend 一次买它 → gold_per_dart add 5(base 1 → 6)
	var t8 = _setup(reg); var p8 = t8[0]; var m8 = t8[1]
	p8.ascend()
	if not p8.buy_upgrade(&"golden_hands"):
		print("FAIL 8a: 应能买 golden_hands"); failures += 1
	if absf(m8.value_for(&"gold_per_dart", 1.0) - 6.0) > 0.0001:
		print("FAIL 8b: golden_hands Lv1 应 gold_per_dart→6.0,实际 %s" % m8.value_for(&"gold_per_dart", 1.0)); failures += 1

	# 9. Lethal Mode:开局撤 prestige 加成(global_mul→1.0)+ 门槛回 1M + 计时;finish 恢复加成与门槛、记最佳
	var t9 = _setup(reg); var p9 = t9[0]; var m9 = t9[1]; var d9 = t9[2]
	p9.ascend(); p9.buy_upgrade(&"eternal_fortune")   # global_mul 1.5、门槛 10M
	if not p9.start_lethal() or not p9.lethal_active():
		print("FAIL 9a: start_lethal 应进入 Lethal"); failures += 1
	if absf(m9.value_for(&"global_mul", 1.0) - 1.0) > 0.0001:
		print("FAIL 9b: Lethal 应撤 prestige 加成(global_mul→1.0),实际 %s" % m9.value_for(&"global_mul", 1.0)); failures += 1
	if absf(d9.bribe_threshold() - M1) > 1.0:
		print("FAIL 9c: Lethal 门槛应回 1M,实际 %s" % d9.bribe_threshold()); failures += 1
	p9.tick_lethal(10.0)
	if absf(p9.lethal_elapsed() - 10.0) > 0.0001:
		print("FAIL 9d: Lethal 计时应累加到 10,实际 %s" % p9.lethal_elapsed()); failures += 1
	var ft9 = p9.finish_lethal()
	if absf(ft9 - 10.0) > 0.0001 or absf(p9.lethal_best() - 10.0) > 0.0001 or p9.lethal_active():
		print("FAIL 9e: finish 应记最佳10 + 退出 Lethal(t=%s best=%s active=%s)" % [ft9, p9.lethal_best(), p9.lethal_active()]); failures += 1
	if absf(m9.value_for(&"global_mul", 1.0) - 1.5) > 0.0001:
		print("FAIL 9f: finish 后应恢复 prestige 加成(1.5),实际 %s" % m9.value_for(&"global_mul", 1.0)); failures += 1
	if absf(d9.bribe_threshold() - M10) > 1.0:
		print("FAIL 9g: finish 后门槛应恢复 10M,实际 %s" % d9.bribe_threshold()); failures += 1

	# 10. 最佳时间取 min;Lethal 期间禁买 prestige 升级
	p9.start_lethal(); p9.tick_lethal(5.0); p9.finish_lethal()
	if absf(p9.lethal_best() - 5.0) > 0.0001:
		print("FAIL 10a: 更快一局应更新最佳(5),实际 %s" % p9.lethal_best()); failures += 1
	p9.start_lethal(); p9.tick_lethal(20.0); p9.finish_lethal()
	if absf(p9.lethal_best() - 5.0) > 0.0001:
		print("FAIL 10b: 更慢一局不应改最佳(仍5),实际 %s" % p9.lethal_best()); failures += 1
	p9.ascend()   # 攒点,隔离出「Lethal 期间禁买」这个原因
	p9.start_lethal()
	if p9.can_buy(&"eternal_fortune") or p9.buy_upgrade(&"eternal_fortune"):
		print("FAIL 10c: Lethal 期间不应能买 prestige 升级"); failures += 1
	p9.abort_lethal()

	# 11. 持久化:ascend×2 + 买 eternal + golden + 跑一局 Lethal,to_dict → 新 Prestige from_dict 全重建
	var t11 = _setup(reg); var p11 = t11[0]
	p11.ascend(); p11.ascend()                 # ng2、points 1+2=3
	p11.buy_upgrade(&"eternal_fortune")        # points 2、global_mul 1.5
	p11.buy_upgrade(&"golden_hands")           # points 1、gold_per_dart 6
	p11.start_lethal(); p11.tick_lethal(7.0); p11.finish_lethal()   # best 7
	var snap = p11.to_dict()
	var m11b = KitModifiers.new()
	var d11b = DartsRoom.new(Currency.new(0.0), m11b, reg)
	var p11b = Prestige.new(m11b, reg)
	p11b.from_dict(snap)
	if p11b.ng_level() != 2 or absf(p11b.points() - 1.0) > 0.0001:
		print("FAIL 11a: from_dict 应恢复 ng2 points1(ng=%d pts=%s)" % [p11b.ng_level(), p11b.points()]); failures += 1
	if p11b.level_of(&"eternal_fortune") != 1 or p11b.level_of(&"golden_hands") != 1:
		print("FAIL 11b: from_dict 应恢复升级等级"); failures += 1
	if absf(p11b.lethal_best() - 7.0) > 0.0001:
		print("FAIL 11c: from_dict 应恢复最佳时间 7,实际 %s" % p11b.lethal_best()); failures += 1
	if absf(m11b.value_for(&"global_mul", 1.0) - 1.5) > 0.0001:
		print("FAIL 11d: from_dict 应重放 eternal global_mul(1.5),实际 %s" % m11b.value_for(&"global_mul", 1.0)); failures += 1
	if absf(m11b.value_for(&"gold_per_dart", 1.0) - 6.0) > 0.0001:
		print("FAIL 11e: from_dict 应重放 golden gold_per_dart(6.0),实际 %s" % m11b.value_for(&"gold_per_dart", 1.0)); failures += 1
	if absf(d11b.bribe_threshold() - M100) > 1.0:
		print("FAIL 11f: from_dict 应重放门槛因子(100M),实际 %s" % d11b.bribe_threshold()); failures += 1

	if failures == 0:
		print("test_fortune_prestige: ALL PASS")
		quit(0)
	else:
		print("test_fortune_prestige: %d FAILURE(S)" % failures)
		quit(1)
