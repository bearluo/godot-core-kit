extends SceneTree
## Currency headless 断言。运行:godot --headless --path . -s res://test/test_fortune_currency.gd
const Currency := preload("res://examples/fortune-mill/systems/currency.gd")


func _initialize() -> void:
	var failures := 0

	# 1. 构造 + get_amount
	var c = Currency.new(100.0)
	if c.get_amount() != 100.0:
		print("FAIL 1: get_amount 应 100"); failures += 1

	# 2. add
	c.add(50.0)
	if c.get_amount() != 150.0:
		print("FAIL 2: add 后应 150"); failures += 1

	# 3. can_afford
	if not c.can_afford(150.0) or c.can_afford(150.01):
		print("FAIL 3: can_afford 边界错"); failures += 1

	# 4. spend 够 → 扣款返 true
	if not c.spend(30.0) or c.get_amount() != 120.0:
		print("FAIL 4: spend 够应扣到 120"); failures += 1

	# 5. spend 不够 → 不扣返 false
	if c.spend(1000.0) or c.get_amount() != 120.0:
		print("FAIL 5: spend 不够应不扣且返 false"); failures += 1

	# 6. set_amount
	c.set_amount(1_000_000.0)
	if c.get_amount() != 1_000_000.0:
		print("FAIL 6: set_amount 错"); failures += 1

	# 7. format kMBT
	if Currency.format(0.0) != "0":
		print("FAIL 7a: format(0) 应 '0',实际 '%s'" % Currency.format(0.0)); failures += 1
	if Currency.format(999.0) != "999":
		print("FAIL 7b: format(999) 应 '999',实际 '%s'" % Currency.format(999.0)); failures += 1
	if Currency.format(1500.0) != "1.50K":
		print("FAIL 7c: format(1500) 应 '1.50K',实际 '%s'" % Currency.format(1500.0)); failures += 1
	if Currency.format(2_500_000.0) != "2.50M":
		print("FAIL 7d: format(2.5e6) 应 '2.50M',实际 '%s'" % Currency.format(2_500_000.0)); failures += 1
	if Currency.format(1_000_000_000.0) != "1.00B":
		print("FAIL 7e: format(1e9) 应 '1.00B',实际 '%s'" % Currency.format(1_000_000_000.0)); failures += 1

	# 8. format plain
	if Currency.format(1500.0, "plain") != "1500":
		print("FAIL 8: format plain 应 '1500',实际 '%s'" % Currency.format(1500.0, "plain")); failures += 1

	if failures == 0:
		print("test_fortune_currency: ALL PASS")
		quit(0)
	else:
		print("test_fortune_currency: %d FAILURE(S)" % failures)
		quit(1)
