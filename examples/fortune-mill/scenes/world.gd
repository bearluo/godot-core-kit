extends Node
## world 表现层根(飞镖 + 刮刮乐 + 柏青哥 + 寿司 + 扭蛋 五房)+ FORTUNE_SMOKE headless 自测入口。
## UI 只读 FortuneMill 模型 + 发命令;订阅 bus 脏标记刷新,不持有权威数值。
## 柏青哥有真物理表现层(pachinko_board.gd,仅非 smoke 实例化);smoke 走 model 直算。

const SMOKE_MAX_STEPS := 500000
const PachinkoBoard := preload("res://examples/fortune-mill/scenes/pachinko_board.gd")

# 飞镖房
var _gold_label: Label
var _status_label: Label
var _bribe_button: Button
var _dart_upgrade_buttons: Dictionary = {}
var _rate_label: Label
var _offline_label: Label
# 刮刮乐房
var _money_label: Label
var _lotto_rate_label: Label
var _jackpot_label: Label
var _scratch_status: Label
var _lotto_upgrade_buttons: Dictionary = {}
var _gorgon_button: Button
# 柏青哥房
var _tickets_label: Label
var _pachinko_rate_label: Label
var _pachinko_status: Label
var _dice_label: Label
var _dice_button: Button
var _pachinko_upgrade_buttons: Dictionary = {}
var _rimmington_button: Button
var _pachinko_board: Node2D
# 寿司房
var _ribbons_label: Label
var _sushi_rate_label: Label
var _sushi_status: Label
var _craft_label: Label
var _sushi_recipe_buttons: Dictionary = {}
var _sushi_upgrade_buttons: Dictionary = {}
var _hivemind_button: Button
# 扭蛋房
var _stuffing_label: Label
var _gacha_rate_label: Label
var _gacha_status: Label
var _collection_label: Label
var _gacha_upgrade_buttons: Dictionary = {}
var _executor_button: Button


func _ready() -> void:
	if OS.get_environment("FORTUNE_SMOKE") == "1":
		_run_smoke()
		return
	_build_ui()
	CoreKit.bus.subscribe("fortune:currency_changed", _on_dirty)
	CoreKit.bus.subscribe("fortune:money_changed", _on_dirty)
	CoreKit.bus.subscribe("fortune:tickets_changed", _on_dirty)
	CoreKit.bus.subscribe("fortune:ribbons_changed", _on_dirty)
	CoreKit.bus.subscribe("fortune:stuffing_changed", _on_dirty)
	CoreKit.bus.subscribe("fortune:upgrade_purchased", _on_dirty)
	CoreKit.bus.subscribe("fortune:jackpot_hit", _on_jackpot)
	CoreKit.bus.subscribe("fortune:dice_rolled", _on_dirty)
	CoreKit.bus.subscribe("fortune:recipe_unlocked", _on_dirty)
	CoreKit.bus.subscribe("fortune:item_pulled", _on_dirty)
	CoreKit.bus.subscribe("fortune:room_cleared", _on_cleared)
	_refresh()
	_maybe_show_offline()


## --- FORTUNE_SMOKE:飞镖过关 + 刮刮乐 JACKPOT 跨房 + 柏青哥 DICE 跨房 + 三守卫过关 ---

func _run_smoke() -> void:
	var fm = FortuneMill   # autoload;不用 := 以免静态类型退化为 Node
	var steps := 0
	# clean-room:从全新态起步(autoload 可能已 load 历史存档)。三房都重置。
	fm.currency.set_amount(1.0)
	fm.money.set_amount(0.0)
	fm.tickets.set_amount(0.0)
	fm.ribbons.set_amount(0.0)
	fm.stuffing.set_amount(0.0)
	fm.darts.from_dict({})
	fm.lotto.from_dict({})
	fm.pachinko.from_dict({})
	fm.sushi.from_dict({})
	fm.gacha.from_dict({})
	CoreKit.saves.delete_slot(fm.SAVE_SLOT)

	# --- P0:飞镖房手动爬到 1M 贿赂 Verminous ---
	while not fm.can_bribe() and steps < SMOKE_MAX_STEPS:
		fm.do_throw()
		if steps % 20 == 0:
			_smoke_buy_round(fm)
		steps += 1
	var ok: bool = fm.can_bribe() and fm.bribe_guard()

	# --- P1:飞镖自动产出 + 离线结算 ---
	fm.buy_dart_upgrade(&"rattling_gunner")
	var rate: float = fm.darts.auto_gold_rate()
	var before_auto: float = fm.currency.get_amount()
	fm.tick(1.0)
	var auto_ok: bool = rate > 0.0 and fm.currency.get_amount() > before_auto
	var t_now: float = Time.get_unix_time_from_system()
	var g_before: float = fm.currency.get_amount()
	var rep: Dictionary = fm.settle_offline(t_now - 3600.0, t_now)
	var p1_earn: float = float((rep.get("darts", {}) as Dictionary).get("earned", 0.0))
	var offline_ok: bool = p1_earn > 0.0 and fm.currency.get_amount() > g_before

	# --- P2:刮刮乐 JACKPOT 跨房 + Gorgon 过关 ---
	fm.lotto.seed_rng(4242)
	var darts_rate_pre: float = fm.darts.auto_gold_rate()
	var lsteps := 0
	while fm.lotto.jackpot_count() < 1 and lsteps < SMOKE_MAX_STEPS:
		fm.do_scratch()
		lsteps += 1
	var jackpots: int = fm.lotto.jackpot_count()
	var darts_rate_post: float = fm.darts.auto_gold_rate()
	var crossroom_ok: bool = jackpots >= 1 and darts_rate_post > darts_rate_pre
	fm.money.add(1000.0)
	fm.buy_lotto_upgrade(&"auto_scratcher")
	var skip := 0
	while not fm.can_bribe_gorgon() and skip < 200000:
		fm.tick(3600.0)
		skip += 1
	var gorgon_ok: bool = fm.can_bribe_gorgon() and fm.bribe_gorgon() and fm.lotto.is_cleared()

	# --- P3:柏青哥落球 + DICE 跨房 + Rimmington 过关 ---
	fm.pachinko.seed_rng(555)
	var pach_drop: Dictionary = fm.drop_ball()
	var pach_drop_ok: bool = float(pach_drop.get("tickets", 0.0)) > 0.0
	var darts_pre_dice: float = fm.darts.auto_gold_rate()
	var dg := 0
	while not fm.can_roll_dice() and dg < 200000:
		fm.drop_ball()
		dg += 1
	var dice_rolled: bool = fm.roll_dice()
	var darts_post_dice: float = fm.darts.auto_gold_rate()
	var dice_cross_ok: bool = dice_rolled and darts_post_dice > darts_pre_dice
	fm.tickets.add(1000.0)
	fm.buy_pachinko_upgrade(&"auto_dropper")
	var pskip := 0
	while not fm.can_bribe_rimmington() and pskip < 200000:
		fm.tick(3600.0)   # tick 内 pachinko.update(dt) 会让 DICE 过期(符合预期)
		pskip += 1
	var rimmington_ok: bool = fm.can_bribe_rimmington() and fm.bribe_rimmington() and fm.pachinko.is_cleared()
	var t3: float = Time.get_unix_time_from_system()
	var rep3: Dictionary = fm.settle_offline(t3 - 3600.0, t3)
	var off3_ok: bool = float((rep3.get("pachinko", {}) as Dictionary).get("earned", 0.0)) > 0.0

	# --- P3:寿司制作(dogfood KitInventory)+ 解锁式开关跨房 + Hivemind 过关 ---
	fm.restock_sushi(&"rice", 20)
	fm.select_sushi_recipe(&"cucumber_roll")
	var rib_before_craft: float = fm.ribbons.get_amount()
	var rice_before: int = fm.sushi.ingredient_count(&"rice")
	var craft_started: bool = fm.start_craft()
	fm.tick(10.0)   # 推进 ≥ craft_time,tick 内 sushi.update 完成一份寿司
	var craft_ok: bool = craft_started and fm.ribbons.get_amount() > rib_before_craft and fm.sushi.ingredient_count(&"rice") < rice_before
	# 解锁式开关协同:解锁 dragon_roll → 飞镖投速 ×2(飞镖此时已有自动投,throws_per_sec>0)
	var darts_pre_switch: float = fm.darts.auto_gold_rate()
	fm.ribbons.add(6000.0)
	var recipe_unlocked: bool = fm.unlock_sushi_recipe(&"dragon_roll")
	var darts_post_switch: float = fm.darts.auto_gold_rate()
	var switch_cross_ok: bool = recipe_unlocked and darts_pre_switch > 0.0 and absf(darts_post_switch - darts_pre_switch * 2.0) < 0.01
	# 自动厨师爬到 1M ribbons 贿赂 Hivemind
	fm.select_sushi_recipe(&"dragon_roll")
	fm.ribbons.add(2000.0)
	fm.buy_sushi_upgrade(&"auto_chef")
	var sskip := 0
	while not fm.can_bribe_hivemind() and sskip < 200000:
		fm.tick(3600.0)
		sskip += 1
	var hivemind_ok: bool = fm.can_bribe_hivemind() and fm.bribe_hivemind() and fm.sushi.is_cleared()
	var t4: float = Time.get_unix_time_from_system()
	var rep4: Dictionary = fm.settle_offline(t4 - 3600.0, t4)
	var off4_ok: bool = float((rep4.get("sushi", {}) as Dictionary).get("earned", 0.0)) > 0.0

	# --- P4:扭蛋抽卡(dogfood KitInventory 收藏柜)+ 被动收集协同跨房 + Executor 过关 ---
	fm.gacha.seed_rng(999)
	var stuffing_before_pull: float = fm.stuffing.get_amount()
	var pull_r: Dictionary = fm.do_pull()   # 手动抽卡命令:收集道具 + 产 stuffing
	var pull_ok: bool = float(pull_r.get("stuffing", 0.0)) > 0.0 and fm.stuffing.get_amount() > stuffing_before_pull and fm.gacha.owned(pull_r.get("item", &"")) >= 1
	# 被动收集协同:收集 5 个 dream_daruma(global_mul ×(1.1)^5)→ 飞镖率同步放大(飞镖此时已有自动投)
	var darts_pre_gacha: float = fm.darts.auto_gold_rate()
	fm.gacha.grant_item(&"dream_daruma", 5)
	var darts_post_gacha: float = fm.darts.auto_gold_rate()
	var gacha_cross_ok: bool = darts_pre_gacha > 0.0 and absf(darts_post_gacha - darts_pre_gacha * pow(1.1, 5)) < 0.01
	# 自动抽卡爬到 1M stuffing 贿赂 Executor
	fm.stuffing.add(2000.0)
	fm.buy_gacha_upgrade(&"auto_gacha")
	var gskip := 0
	while not fm.can_bribe_executor() and gskip < 200000:
		fm.tick(3600.0)
		gskip += 1
	var executor_ok: bool = fm.can_bribe_executor() and fm.bribe_executor() and fm.gacha.is_cleared()
	var t5: float = Time.get_unix_time_from_system()
	var rep5: Dictionary = fm.settle_offline(t5 - 3600.0, t5)
	var off5_ok: bool = float((rep5.get("gacha", {}) as Dictionary).get("earned", 0.0)) > 0.0

	var gacha_boost := (darts_post_gacha / darts_pre_gacha) if darts_pre_gacha > 0.0 else 0.0
	var switch_boost := (darts_post_switch / darts_pre_switch) if darts_pre_switch > 0.0 else 0.0
	var dice_boost := (darts_post_dice / darts_pre_dice) if darts_pre_dice > 0.0 else 0.0
	var boost := (darts_rate_post / darts_rate_pre) if darts_rate_pre > 0.0 else 0.0
	CoreKit.saves.delete_slot(fm.SAVE_SLOT)
	var p012 := ok and auto_ok and offline_ok and crossroom_ok and gorgon_ok
	var p3 := pach_drop_ok and dice_cross_ok and rimmington_ok and off3_ok
	var p3s := craft_ok and switch_cross_ok and hivemind_ok and off4_ok
	var p4 := pull_ok and gacha_cross_ok and executor_ok and off5_ok
	if p012 and p3 and p3s and p4:
		print("[Fortune][SMOKE] PASS steps=%d jackpots=%d darts_boost=%.2fx gorgon=%s dice=%s dice_boost=%.2fx rimmington=%s craft=%s switch_boost=%.2fx hivemind=%s gacha_boost=%.2fx executor=%s stuffing=%s ribbons=%s" % [steps, jackpots, boost, fm.lotto.is_cleared(), dice_rolled, dice_boost, fm.pachinko.is_cleared(), craft_ok, switch_boost, fm.sushi.is_cleared(), gacha_boost, fm.gacha.is_cleared(), Currency.format(fm.stuffing.get_amount()), Currency.format(fm.ribbons.get_amount())])
		get_tree().quit(0)
	else:
		print("[Fortune][SMOKE] FAIL p0=%s auto=%s offline=%s cross=%s gorgon=%s | drop=%s dice_cross=%s rimmington=%s off3=%s | craft=%s switch=%s(%.2f→%.2f) hivemind=%s off4=%s | pull=%s gacha_cross=%s(%.2f→%.2f) executor=%s off5=%s" % [ok, auto_ok, offline_ok, crossroom_ok, gorgon_ok, pach_drop_ok, dice_cross_ok, rimmington_ok, off3_ok, craft_ok, switch_cross_ok, darts_pre_switch, darts_post_switch, hivemind_ok, off4_ok, pull_ok, gacha_cross_ok, darts_pre_gacha, darts_post_gacha, executor_ok, off5_ok])
		get_tree().quit(1)


## 每轮把每条买得起的飞镖升级各买一级。
func _smoke_buy_round(fm) -> void:
	for id in fm.registry.ids(&"dart_upgrade", true):
		fm.buy_dart_upgrade(id)


## --- 可玩 UI(代码构建;三列:飞镖 | 刮刮乐 | 柏青哥 + 右侧物理板) ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var cols := HBoxContainer.new()
	cols.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	cols.position = Vector2(16, 16)
	cols.add_theme_constant_override("separation", 40)
	layer.add_child(cols)

	# 飞镖房列
	var dcol := VBoxContainer.new()
	cols.add_child(dcol)
	_add_title(dcol, "▛ 飞镖房 (gold / Verminous)")
	_gold_label = Label.new(); dcol.add_child(_gold_label)
	_status_label = Label.new(); dcol.add_child(_status_label)
	_rate_label = Label.new(); dcol.add_child(_rate_label)
	var throw_btn := Button.new(); throw_btn.text = "投镖 (Throw)"
	throw_btn.pressed.connect(func() -> void: FortuneMill.do_throw())
	dcol.add_child(throw_btn)
	dcol.add_child(HSeparator.new())
	for id in FortuneMill.registry.ids(&"dart_upgrade", true):
		var btn := Button.new()
		btn.pressed.connect(func() -> void: FortuneMill.buy_dart_upgrade(id))
		dcol.add_child(btn)
		_dart_upgrade_buttons[id] = btn
	dcol.add_child(HSeparator.new())
	_bribe_button = Button.new(); _bribe_button.text = "贿赂 Verminous (需 1M gold)"
	_bribe_button.pressed.connect(func() -> void: FortuneMill.bribe_guard())
	dcol.add_child(_bribe_button)
	_offline_label = Label.new(); _offline_label.visible = false
	dcol.add_child(_offline_label)

	# 刮刮乐房列
	var lcol := VBoxContainer.new()
	cols.add_child(lcol)
	_add_title(lcol, "▟ 刮刮乐房 (money / Gorgon)")
	_money_label = Label.new(); lcol.add_child(_money_label)
	_scratch_status = Label.new(); lcol.add_child(_scratch_status)
	_lotto_rate_label = Label.new(); lcol.add_child(_lotto_rate_label)
	_jackpot_label = Label.new(); lcol.add_child(_jackpot_label)
	var scratch_btn := Button.new(); scratch_btn.text = "刮卡 (Scratch)"
	scratch_btn.pressed.connect(_on_scratch_pressed)
	lcol.add_child(scratch_btn)
	lcol.add_child(HSeparator.new())
	for id in FortuneMill.registry.ids(&"lotto_upgrade", true):
		var btn := Button.new()
		btn.pressed.connect(func() -> void: FortuneMill.buy_lotto_upgrade(id))
		lcol.add_child(btn)
		_lotto_upgrade_buttons[id] = btn
	lcol.add_child(HSeparator.new())
	_gorgon_button = Button.new(); _gorgon_button.text = "贿赂 Gorgon (需 1M money)"
	_gorgon_button.pressed.connect(func() -> void: FortuneMill.bribe_gorgon())
	lcol.add_child(_gorgon_button)

	# 柏青哥房列
	var pcol := VBoxContainer.new()
	cols.add_child(pcol)
	_add_title(pcol, "▙ 柏青哥房 (tickets / Rimmington)")
	_tickets_label = Label.new(); pcol.add_child(_tickets_label)
	_pachinko_status = Label.new(); pcol.add_child(_pachinko_status)
	_pachinko_rate_label = Label.new(); pcol.add_child(_pachinko_rate_label)
	_dice_label = Label.new(); pcol.add_child(_dice_label)
	var drop_btn := Button.new(); drop_btn.text = "落球 (Drop)"
	drop_btn.pressed.connect(_on_drop_pressed)
	pcol.add_child(drop_btn)
	_dice_button = Button.new(); _dice_button.text = "掷骰 (Roll Dice)"
	_dice_button.pressed.connect(func() -> void: FortuneMill.roll_dice())
	pcol.add_child(_dice_button)
	pcol.add_child(HSeparator.new())
	for id in FortuneMill.registry.ids(&"pachinko_upgrade", true):
		var btn := Button.new()
		btn.pressed.connect(func() -> void: FortuneMill.buy_pachinko_upgrade(id))
		pcol.add_child(btn)
		_pachinko_upgrade_buttons[id] = btn
	pcol.add_child(HSeparator.new())
	_rimmington_button = Button.new(); _rimmington_button.text = "贿赂 Rimmington (需 1M tickets)"
	_rimmington_button.pressed.connect(func() -> void: FortuneMill.bribe_rimmington())
	pcol.add_child(_rimmington_button)

	# 寿司房列
	var scol := VBoxContainer.new()
	cols.add_child(scol)
	_add_title(scol, "▜ 寿司房 (ribbons / Hivemind)")
	_ribbons_label = Label.new(); scol.add_child(_ribbons_label)
	_sushi_status = Label.new(); scol.add_child(_sushi_status)
	_sushi_rate_label = Label.new(); scol.add_child(_sushi_rate_label)
	_craft_label = Label.new(); scol.add_child(_craft_label)
	var restock_btn := Button.new(); restock_btn.text = "备料 (Restock ×10)"
	restock_btn.pressed.connect(func() -> void: FortuneMill.restock_sushi_all(10))
	scol.add_child(restock_btn)
	var craft_btn := Button.new(); craft_btn.text = "开始制作 (Craft)"
	craft_btn.pressed.connect(func() -> void: FortuneMill.start_craft())
	scol.add_child(craft_btn)
	scol.add_child(HSeparator.new())
	# 配方(选中已解锁 / 花 ribbons 解锁)
	for id in FortuneMill.registry.ids(&"sushi_recipe", true):
		var btn := Button.new()
		btn.pressed.connect(func() -> void: _on_recipe_pressed(id))
		scol.add_child(btn)
		_sushi_recipe_buttons[id] = btn
	scol.add_child(HSeparator.new())
	for id in FortuneMill.registry.ids(&"sushi_upgrade", true):
		var btn := Button.new()
		btn.pressed.connect(func() -> void: FortuneMill.buy_sushi_upgrade(id))
		scol.add_child(btn)
		_sushi_upgrade_buttons[id] = btn
	scol.add_child(HSeparator.new())
	_hivemind_button = Button.new(); _hivemind_button.text = "贿赂 Hivemind (需 1M ribbons)"
	_hivemind_button.pressed.connect(func() -> void: FortuneMill.bribe_hivemind())
	scol.add_child(_hivemind_button)

	# 扭蛋房列
	var gcol := VBoxContainer.new()
	cols.add_child(gcol)
	_add_title(gcol, "▛ 扭蛋房 (stuffing / Executor)")
	_stuffing_label = Label.new(); gcol.add_child(_stuffing_label)
	_gacha_status = Label.new(); gcol.add_child(_gacha_status)
	_gacha_rate_label = Label.new(); gcol.add_child(_gacha_rate_label)
	_collection_label = Label.new(); gcol.add_child(_collection_label)
	var pull_btn := Button.new(); pull_btn.text = "抽扭蛋 (Pull)"
	pull_btn.pressed.connect(_on_pull_pressed)
	gcol.add_child(pull_btn)
	gcol.add_child(HSeparator.new())
	for id in FortuneMill.registry.ids(&"gacha_upgrade", true):
		var btn := Button.new()
		btn.pressed.connect(func() -> void: FortuneMill.buy_gacha_upgrade(id))
		gcol.add_child(btn)
		_gacha_upgrade_buttons[id] = btn
	gcol.add_child(HSeparator.new())
	_executor_button = Button.new(); _executor_button.text = "贿赂 Executor (需 1M stuffing)"
	_executor_button.pressed.connect(func() -> void: FortuneMill.bribe_executor())
	gcol.add_child(_executor_button)

	# 柏青哥物理板(真 RigidBody2D 落球;juice)
	_pachinko_board = PachinkoBoard.new()
	add_child(_pachinko_board)


func _add_title(col: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	col.add_child(l)


func _on_scratch_pressed() -> void:
	var r: Dictionary = FortuneMill.do_scratch()
	if _scratch_status == null:
		return
	var earned := Currency.format(float(r.get("money", 0.0)))
	if r.get("jackpot", false):
		_scratch_status.text = "★ JACKPOT! +%s money ★" % earned
	else:
		_scratch_status.text = "刮出 +%s money" % earned


## 落球:走物理板(真物理落槽回调 pachinko_land);多球数取自 modifier。
func _on_drop_pressed() -> void:
	var balls := maxi(1, int(FortuneMill.modifiers.value_for(&"balls_per_drop", 1.0)))
	if _pachinko_board != null:
		_pachinko_board.drop(balls)
	else:
		FortuneMill.drop_ball()


## 配方按钮:已解锁 → 选中它;未解锁 → 花 ribbons 解锁(解锁高级配方触发跨房规则开关)。
func _on_recipe_pressed(id: StringName) -> void:
	if FortuneMill.sushi.is_unlocked(id):
		FortuneMill.select_sushi_recipe(id)
	else:
		FortuneMill.unlock_sushi_recipe(id)
	_refresh()


## 抽扭蛋:走命令 do_pull(收集道具 + 产 stuffing);状态栏报本次抽到的道具与稀有度。
func _on_pull_pressed() -> void:
	var r: Dictionary = FortuneMill.do_pull()
	if _gacha_status == null:
		return
	var st := Currency.format(float(r.get("stuffing", 0.0)))
	_gacha_status.text = "抽到 [%s] %s (+%s stuffing, 持有 %d)" % [str(r.get("rarity", &"")), str(r.get("item", &"")), st, int(r.get("owned", 0))]


func _on_dirty(_payload) -> void:
	_refresh()


func _on_jackpot(_count) -> void:
	_refresh()


func _on_cleared(room) -> void:
	match str(room):
		"lotto":
			if _scratch_status != null:
				_scratch_status.text = "★ 已贿赂 Gorgon,刮刮乐房通关! ★"
		"pachinko":
			if _pachinko_status != null:
				_pachinko_status.text = "★ 已贿赂 Rimmington,柏青哥房通关! ★"
		"sushi":
			if _sushi_status != null:
				_sushi_status.text = "★ 已贿赂 Hivemind,寿司房通关! ★"
		"gacha":
			if _gacha_status != null:
				_gacha_status.text = "★ 已贿赂 Executor,扭蛋房通关! ★"
		_:
			if _status_label != null:
				_status_label.text = "★ 已贿赂 Verminous,飞镖房通关! ★"


func _refresh() -> void:
	if _gold_label == null:
		return
	# 飞镖房
	_gold_label.text = "Gold: %s" % Currency.format(FortuneMill.currency.get_amount())
	_rate_label.text = "自动: %s gold/s" % Currency.format(FortuneMill.darts.auto_gold_rate())
	for id in _dart_upgrade_buttons:
		var def = FortuneMill.registry.get_def(&"dart_upgrade", id)
		var lvl := FortuneMill.darts.level_of(id)
		var cost := FortuneMill.darts.cost_of(id)
		var btn: Button = _dart_upgrade_buttons[id]
		btn.text = "%s  Lv.%d  (%s gold)" % [def.title, lvl, Currency.format(cost)]
		btn.disabled = not FortuneMill.currency.can_afford(cost)
	_bribe_button.disabled = not FortuneMill.can_bribe()
	# 刮刮乐房
	_money_label.text = "Money: %s" % Currency.format(FortuneMill.money.get_amount())
	_lotto_rate_label.text = "自动: %s money/s" % Currency.format(FortuneMill.lotto.auto_money_rate())
	var gmul := FortuneMill.modifiers.value_for(&"global_mul", 1.0)
	_jackpot_label.text = "JACKPOT ×%d  →  全房间产出 ×%.2f" % [FortuneMill.lotto.jackpot_count(), gmul]
	for id in _lotto_upgrade_buttons:
		var ldef = FortuneMill.registry.get_def(&"lotto_upgrade", id)
		var llvl := FortuneMill.lotto.level_of(id)
		var lcost := FortuneMill.lotto.cost_of(id)
		var lbtn: Button = _lotto_upgrade_buttons[id]
		lbtn.text = "%s  Lv.%d  (%s money)" % [ldef.title, llvl, Currency.format(lcost)]
		lbtn.disabled = not FortuneMill.money.can_afford(lcost)
	_gorgon_button.disabled = not FortuneMill.can_bribe_gorgon()
	# 柏青哥房
	_tickets_label.text = "Tickets: %s" % Currency.format(FortuneMill.tickets.get_amount())
	_pachinko_rate_label.text = "自动: %s tk/s" % Currency.format(FortuneMill.pachinko.auto_ticket_rate())
	var dm := FortuneMill.pachinko.dice_meter()
	var dt := FortuneMill.pachinko.dice_threshold()
	if FortuneMill.pachinko.dice_active():
		_dice_label.text = "🎲 DICE 生效!全房 ×%.1f (剩 %.0fs)" % [PachinkoRoom.DICE_MUL, FortuneMill.pachinko.dice_seconds_left()]
	else:
		_dice_label.text = "骰子蓄力: %.0f / %.0f" % [dm, dt]
	_dice_button.disabled = not FortuneMill.can_roll_dice()
	for id in _pachinko_upgrade_buttons:
		var pdef = FortuneMill.registry.get_def(&"pachinko_upgrade", id)
		var plvl := FortuneMill.pachinko.level_of(id)
		var pcost := FortuneMill.pachinko.cost_of(id)
		var pbtn: Button = _pachinko_upgrade_buttons[id]
		pbtn.text = "%s  Lv.%d  (%s tk)" % [pdef.title, plvl, Currency.format(pcost)]
		pbtn.disabled = not FortuneMill.tickets.can_afford(pcost)
	_rimmington_button.disabled = not FortuneMill.can_bribe_rimmington()
	# 寿司房
	_ribbons_label.text = "Ribbons: %s" % Currency.format(FortuneMill.ribbons.get_amount())
	_sushi_rate_label.text = "自动: %s rb/s" % Currency.format(FortuneMill.sushi.auto_ribbon_rate())
	if FortuneMill.sushi.is_crafting():
		var tgt := FortuneMill.sushi.craft_target()
		var prog := FortuneMill.sushi.craft_progress()
		_craft_label.text = "制作中 %s: %.0f%%" % [FortuneMill.sushi.active_recipe(), 100.0 * prog / maxf(0.001, tgt)]
	else:
		_craft_label.text = "当前配方: %s" % FortuneMill.sushi.active_recipe()
	for id in _sushi_recipe_buttons:
		var rdef = FortuneMill.registry.get_def(&"sushi_recipe", id)
		var rbtn: Button = _sushi_recipe_buttons[id]
		if FortuneMill.sushi.is_unlocked(id):
			var sel := "▶ " if FortuneMill.sushi.active_recipe() == id else ""
			rbtn.text = "%s%s (%.0fs, 库存 %d)" % [sel, rdef.title, rdef.craft_time, FortuneMill.sushi.ingredient_count(rdef.ingredient)]
			rbtn.disabled = false
		else:
			rbtn.text = "🔒 %s (解锁 %s rb)" % [rdef.title, Currency.format(FortuneMill.sushi.unlock_cost(id))]
			rbtn.disabled = not FortuneMill.sushi.can_unlock(id)
	for id in _sushi_upgrade_buttons:
		var sdef = FortuneMill.registry.get_def(&"sushi_upgrade", id)
		var slvl := FortuneMill.sushi.level_of(id)
		var scost := FortuneMill.sushi.cost_of(id)
		var sbtn: Button = _sushi_upgrade_buttons[id]
		sbtn.text = "%s  Lv.%d  (%s rb)" % [sdef.title, slvl, Currency.format(scost)]
		sbtn.disabled = not FortuneMill.ribbons.can_afford(scost)
	_hivemind_button.disabled = not FortuneMill.can_bribe_hivemind()
	# 扭蛋房
	_stuffing_label.text = "Stuffing: %s" % Currency.format(FortuneMill.stuffing.get_amount())
	_gacha_rate_label.text = "自动: %s st/s" % Currency.format(FortuneMill.gacha.auto_stuffing_rate())
	var coll: Array = []
	for iid in FortuneMill.gacha.item_ids():
		var n := FortuneMill.gacha.owned(iid)
		if n > 0:
			coll.append("%s×%d" % [str(iid), n])
	_collection_label.text = "收藏: %s" % (", ".join(coll) if not coll.is_empty() else "(空)")
	for id in _gacha_upgrade_buttons:
		var gdef = FortuneMill.registry.get_def(&"gacha_upgrade", id)
		var glvl := FortuneMill.gacha.level_of(id)
		var gcost := FortuneMill.gacha.cost_of(id)
		var gbtn: Button = _gacha_upgrade_buttons[id]
		gbtn.text = "%s  Lv.%d  (%s st)" % [gdef.title, glvl, Currency.format(gcost)]
		gbtn.disabled = not FortuneMill.stuffing.can_afford(gcost)
	_executor_button.disabled = not FortuneMill.can_bribe_executor()


## 从模型拉取最近离线结算(per-room),任一房 earned>0 才显示回归横幅。
func _maybe_show_offline() -> void:
	if _offline_label == null:
		return
	var rep: Dictionary = FortuneMill.offline_report
	if rep.is_empty():
		return
	var parts: Array = []
	var g := float((rep.get("darts", {}) as Dictionary).get("earned", 0.0))
	var m := float((rep.get("lotto", {}) as Dictionary).get("earned", 0.0))
	var tk := float((rep.get("pachinko", {}) as Dictionary).get("earned", 0.0))
	var rb := float((rep.get("sushi", {}) as Dictionary).get("earned", 0.0))
	var st := float((rep.get("gacha", {}) as Dictionary).get("earned", 0.0))
	if g > 0.0:
		parts.append("飞镖 %s gold" % Currency.format(g))
	if m > 0.0:
		parts.append("刮刮乐 %s money" % Currency.format(m))
	if tk > 0.0:
		parts.append("柏青哥 %s tk" % Currency.format(tk))
	if rb > 0.0:
		parts.append("寿司 %s rb" % Currency.format(rb))
	if st > 0.0:
		parts.append("扭蛋 %s st" % Currency.format(st))
	if parts.is_empty():
		return
	var mins := int(float((rep.get("darts", {}) as Dictionary).get("elapsed", 0.0)) / 60.0)
	_offline_label.visible = true
	_offline_label.text = "欢迎回来!离线 %d 分钟,自动攒了:%s" % [mins, ", ".join(parts)]
