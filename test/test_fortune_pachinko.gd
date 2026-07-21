extends SceneTree
## PachinkoRoom + DICE 临时全局乘数 headless 断言。运行:godot --headless --path . -s res://test/test_fortune_pachinko.gd
## 重点:DICE roll → global_mul 叠临时 mul,update(dt) 过期自动撤下;与 JACKPOT 永久 mul 同 target 乘性叠加;
## 经共享 KitModifiers 放大飞镖房(跨房)。
const Currency := preload("res://examples/fortune-mill/systems/currency.gd")
const KitModifiers := preload("res://examples/fortune-mill/systems/kit_modifiers.gd")
const PachinkoRoom := preload("res://examples/fortune-mill/systems/pachinko_room.gd")
const DartsRoom := preload("res://examples/fortune-mill/systems/darts_room.gd")
const PachinkoUpgradeDef := preload("res://examples/fortune-mill/defs/pachinko_upgrade_def.gd")
const KitDataRegistry := preload("res://addons/godot-core-kit/data/kit_data_registry.gd")


func _pdef(id: StringName, kind: StringName, target: StringName, op: StringName, eff: float, base: float, growth: float, maxl: int):
	var d = PachinkoUpgradeDef.new()
	d.id = id; d.kind = kind; d.target = target; d.op = op
	d.effect_per_level = eff; d.base_cost = base; d.growth = growth; d.max_level = maxl
	return d


func _reg():
	var reg = KitDataRegistry.new()
	reg.register(&"pachinko_upgrade", &"heavier", _pdef(&"heavier", &"value", &"tickets_per_ball", &"mul", 0.5, 20.0, 1.3, -1))
	reg.register(&"pachinko_upgrade", &"auto", _pdef(&"auto", &"automation", &"drops_per_sec", &"add", 0.5, 700.0, 1.9, 25))
	reg.register(&"pachinko_upgrade", &"dice", _pdef(&"dice", &"unlock", &"dice_frequency", &"add", 1.0, 500.0, 2.0, 10))
	return reg


func _room(reg) -> Array:
	var tickets = Currency.new(0.0)
	var mods = KitModifiers.new()
	var room = PachinkoRoom.new(tickets, mods, reg)
	room.seed_rng(777)
	return [room, tickets, mods]


## 落球直到骰子蓄满。
func _fill_dice(room) -> void:
	var guard := 0
	while not room.dice_ready() and guard < 10000:
		room.drop_ball()
		guard += 1


func _initialize() -> void:
	var failures := 0
	var reg = _reg()

	# 1. 槽表常量 + drop_ball 产 tickets 入账
	if PachinkoRoom.SLOT_VALUES.size() != PachinkoRoom.SLOT_WEIGHTS.size():
		print("FAIL 1: 槽值/权重表长度应一致"); failures += 1
	var t1 = _room(reg); var r1 = t1[0]; var tk1 = t1[1]
	var d1 = r1.drop_ball()
	if d1["tickets"] <= 0.0 or absf(tk1.get_amount() - d1["tickets"]) > 0.0001:
		print("FAIL 1b: drop_ball 应产正 tickets 并入账,实际 %s" % d1); failures += 1

	# 2. heavier_balls(mul tickets_per_ball)后自动率提高
	var t2 = _room(reg); var r2 = t2[0]; var tk2 = t2[1]; var m2 = t2[2]
	m2.set_modifier(&"drops_per_sec", &"tauto", &"add", 1.0)
	var rate_before = r2.auto_ticket_rate()
	tk2.add(100.0)
	r2.buy_upgrade(&"heavier")
	if r2.auto_ticket_rate() <= rate_before:
		print("FAIL 2: 买 heavier 后 auto 率应提高"); failures += 1

	# 3. 无自动化 → auto 率 0;produce 不加 tickets
	var t3 = _room(reg); var r3 = t3[0]; var tk3 = t3[1]
	if absf(r3.auto_ticket_rate()) > 0.0001:
		print("FAIL 3a: 无自动化产率应 0"); failures += 1
	var b3 = tk3.get_amount()
	r3.produce(5.0)
	if absf(tk3.get_amount() - b3) > 0.0001:
		print("FAIL 3b: 无自动化 produce 不应加 tickets"); failures += 1

	# 4. DICE:初始未蓄满不能掷;蓄满掷骰 → global_mul ×DICE_MUL 且 active
	var t4 = _room(reg); var r4 = t4[0]; var m4 = t4[2]
	if r4.dice_ready() or r4.roll_dice():
		print("FAIL 4a: 初始未蓄满不应能掷骰"); failures += 1
	_fill_dice(r4)
	if not r4.dice_ready() or not r4.roll_dice() or not r4.dice_active():
		print("FAIL 4b: 蓄满应能掷骰并激活"); failures += 1
	if absf(m4.value_for(&"global_mul", 1.0) - PachinkoRoom.DICE_MUL) > 0.0001:
		print("FAIL 4c: 掷骰后 global_mul 应 =DICE_MUL,实际 %s" % m4.value_for(&"global_mul", 1.0)); failures += 1

	# 5. DICE 过期:update 过 DICE_DURATION → global_mul 回落 1、不再 active
	r4.update(PachinkoRoom.DICE_DURATION + 1.0)
	if r4.dice_active() or absf(m4.value_for(&"global_mul", 1.0) - 1.0) > 0.0001:
		print("FAIL 5: DICE 过期后 global_mul 应回 1,实际 %s active=%s" % [m4.value_for(&"global_mul", 1.0), r4.dice_active()]); failures += 1

	# 6. DICE 与 JACKPOT 乘性叠加(同 global_mul 两源)
	var t6 = _room(reg); var r6 = t6[0]; var m6 = t6[2]
	m6.set_modifier(&"global_mul", &"lotto_jackpot", &"mul", 1.5)   # 模拟一次永久 jackpot
	_fill_dice(r6)
	r6.roll_dice()
	if absf(m6.value_for(&"global_mul", 1.0) - 1.5 * PachinkoRoom.DICE_MUL) > 0.0001:
		print("FAIL 6: DICE×JACKPOT 应 1.5×%s,实际 %s" % [PachinkoRoom.DICE_MUL, m6.value_for(&"global_mul", 1.0)]); failures += 1

	# 7. 跨房协同:同一 modifiers 喂 DartsRoom,DICE 期间飞镖 auto 率 ×DICE_MUL
	var t7reg = _reg()
	var tickets7 = Currency.new(0.0); var gold7 = Currency.new(0.0); var mods7 = KitModifiers.new()
	var pach7 = PachinkoRoom.new(tickets7, mods7, t7reg); pach7.seed_rng(2024)
	var darts7 = DartsRoom.new(gold7, mods7, t7reg); darts7.seed_rng(99)
	mods7.set_modifier(&"throws_per_sec", &"tauto", &"add", 3.0)
	var darts_before = darts7.auto_gold_rate()
	_fill_dice(pach7)
	pach7.roll_dice()
	var darts_after = darts7.auto_gold_rate()
	if darts_before <= 0.0 or absf(darts_after - darts_before * PachinkoRoom.DICE_MUL) > 0.01:
		print("FAIL 7: 跨房——DICE 期间飞镖率应 ×%s(%s→%s)" % [PachinkoRoom.DICE_MUL, darts_before, darts_after]); failures += 1

	# 8. auto_ticket_rate 确定性(两次相同)
	var t8 = _room(reg); var r8 = t8[0]; var m8 = t8[2]
	m8.set_modifier(&"drops_per_sec", &"tauto", &"add", 2.0)
	if absf(r8.auto_ticket_rate() - r8.auto_ticket_rate()) > 0.0001:
		print("FAIL 8: auto_ticket_rate 应确定性一致"); failures += 1

	# 9. bribe Rimmington:未达门槛不能,达 1M 门槛能
	var t9 = _room(reg); var r9 = t9[0]; var tk9 = t9[1]
	if r9.can_bribe() or r9.bribe():
		print("FAIL 9a: 未达门槛不能贿赂"); failures += 1
	tk9.set_amount(PachinkoRoom.BRIBE_COST)
	if not r9.can_bribe() or not r9.bribe() or not r9.is_cleared():
		print("FAIL 9b: 达门槛应能贿赂并 cleared"); failures += 1

	# 10. 持久化:买 heavier + 掷骰(临时 buff),to_dict → 新 room(全新 mods)from_dict:
	#     level 重建、DICE 临时 buff **不**恢复(fresh mods 上 global_mul 仍 1)
	var t10 = _room(reg); var r10 = t10[0]; var tk10 = t10[1]
	tk10.add(100.0)
	r10.buy_upgrade(&"heavier")
	_fill_dice(r10); r10.roll_dice()   # 造一个 live buff
	var snap10 = r10.to_dict()
	var mods10b = KitModifiers.new()
	var r10b = PachinkoRoom.new(Currency.new(0.0), mods10b, reg)
	r10b.from_dict(snap10)
	if r10b.level_of(&"heavier") != 1:
		print("FAIL 10a: from_dict 应恢复 heavier level1"); failures += 1
	if absf(mods10b.value_for(&"tickets_per_ball", PachinkoRoom.BALL_BASE) - 1.5) > 0.0001:
		print("FAIL 10b: from_dict 应重建 tickets_per_ball(×1.5)"); failures += 1
	if r10b.dice_active() or absf(mods10b.value_for(&"global_mul", 1.0) - 1.0) > 0.0001:
		print("FAIL 10c: DICE 临时 buff 不应持久化,fresh mods global_mul 应 1"); failures += 1

	if failures == 0:
		print("test_fortune_pachinko: ALL PASS")
		quit(0)
	else:
		print("test_fortune_pachinko: %d FAILURE(S)" % failures)
		quit(1)
