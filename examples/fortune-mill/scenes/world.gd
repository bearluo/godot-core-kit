extends Node
## world 表现层根(飞镖房 + 刮刮乐房)+ FORTUNE_SMOKE headless 自测入口。
## UI 只读 FortuneMill 模型 + 发命令;订阅 bus 脏标记刷新,不持有权威数值。

const SMOKE_MAX_STEPS := 500000

# 飞镖房
var _gold_label: Label
var _status_label: Label
var _bribe_button: Button
var _dart_upgrade_buttons: Dictionary = {}   # StringName(id) -> Button
var _rate_label: Label
var _offline_label: Label
# 刮刮乐房
var _money_label: Label
var _lotto_rate_label: Label
var _jackpot_label: Label
var _scratch_status: Label
var _lotto_upgrade_buttons: Dictionary = {}
var _gorgon_button: Button


func _ready() -> void:
	if OS.get_environment("FORTUNE_SMOKE") == "1":
		_run_smoke()
		return
	_build_ui()
	CoreKit.bus.subscribe("fortune:currency_changed", _on_dirty)
	CoreKit.bus.subscribe("fortune:money_changed", _on_dirty)
	CoreKit.bus.subscribe("fortune:upgrade_purchased", _on_dirty)
	CoreKit.bus.subscribe("fortune:jackpot_hit", _on_jackpot)
	CoreKit.bus.subscribe("fortune:room_cleared", _on_cleared)
	_refresh()
	_maybe_show_offline()


## --- FORTUNE_SMOKE:自动玩闭环,验证飞镖 $1→100 万过关 + 刮刮乐闭环 + JACKPOT 跨房加成 + Gorgon 过关 ---

func _run_smoke() -> void:
	var fm = FortuneMill   # autoload;不用 := 以免静态类型退化为 Node
	var steps := 0
	# clean-room:autoload 的 _ready 可能已 load_game 载入历史存档(含通关/jackpot 态),
	# smoke 作为回归 gate 必须从全新态起步,故双房都重置。
	fm.currency.set_amount(1.0)
	fm.money.set_amount(0.0)
	fm.darts.from_dict({})   # 重置 levels/cleared/bullseye_unlock + 清 modifier 残留
	fm.lotto.from_dict({})   # 重置 levels/jackpot/cleared + 清 global_mul 残留
	CoreKit.saves.delete_slot(fm.SAVE_SLOT)

	# --- P0:飞镖房手动爬到 1M 贿赂 Verminous ---
	while not fm.can_bribe() and steps < SMOKE_MAX_STEPS:
		fm.do_throw()
		if steps % 20 == 0:
			_smoke_buy_round(fm)
		steps += 1
	var ok: bool = fm.can_bribe() and fm.bribe_guard()

	# --- P1:飞镖自动产出 + 离线结算(过关后 gold 充裕,可买自动投) ---
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

	# --- P2:刮刮乐闭环 + JACKPOT 跨房协同 + Gorgon 过关 ---
	fm.lotto.seed_rng(4242)
	var darts_rate_pre: float = fm.darts.auto_gold_rate()   # jackpot 前飞镖率(global_mul=1)
	var lsteps := 0
	while fm.lotto.jackpot_count() < 1 and lsteps < SMOKE_MAX_STEPS:
		fm.do_scratch()
		lsteps += 1
	var jackpots: int = fm.lotto.jackpot_count()
	var darts_rate_post: float = fm.darts.auto_gold_rate()  # jackpot 后被 global_mul 放大
	var crossroom_ok: bool = jackpots >= 1 and darts_rate_post > darts_rate_pre
	# 买自动刮 + 时移攒够 1M money 贿赂 Gorgon
	fm.money.add(1000.0)
	fm.buy_lotto_upgrade(&"auto_scratcher")
	var skip := 0
	while not fm.can_bribe_gorgon() and skip < 200000:
		fm.tick(3600.0)   # 每步模拟 1h 自动产出
		skip += 1
	var gorgon_ok: bool = fm.can_bribe_gorgon() and fm.bribe_gorgon() and fm.lotto.is_cleared()
	# 双房离线结算(5 货币独立,各房各结)
	var t2: float = Time.get_unix_time_from_system()
	var rep2: Dictionary = fm.settle_offline(t2 - 3600.0, t2)
	var off2_g: float = float((rep2.get("darts", {}) as Dictionary).get("earned", 0.0))
	var off2_m: float = float((rep2.get("lotto", {}) as Dictionary).get("earned", 0.0))
	var offline2_ok: bool = off2_g > 0.0 and off2_m > 0.0

	var gold_str := Currency.format(fm.currency.get_amount())
	var boost := (darts_rate_post / darts_rate_pre) if darts_rate_pre > 0.0 else 0.0
	CoreKit.saves.delete_slot(fm.SAVE_SLOT)   # smoke 自清理,不留存档污染后续运行
	if ok and auto_ok and offline_ok and crossroom_ok and gorgon_ok and offline2_ok:
		print("[Fortune][SMOKE] PASS gold=%s steps=%d auto_rate=%.2f offline_earn=%.0f jackpots=%d darts_boost=%.2fx gorgon=%s money=%s" % [gold_str, steps, rate, p1_earn, jackpots, boost, fm.lotto.is_cleared(), Currency.format(fm.money.get_amount())])
		get_tree().quit(0)
	else:
		print("[Fortune][SMOKE] FAIL ok=%s auto=%s offline=%s crossroom=%s(pre=%.2f post=%.2f) gorgon=%s offline2=%s" % [ok, auto_ok, offline_ok, crossroom_ok, darts_rate_pre, darts_rate_post, gorgon_ok, offline2_ok])
		get_tree().quit(1)


## 每轮把每条买得起的飞镖升级各买一级(均衡成长,推动数值爬升)。
func _smoke_buy_round(fm) -> void:
	for id in fm.registry.ids(&"dart_upgrade", true):
		fm.buy_dart_upgrade(id)


## --- 可玩 UI(代码构建,P0/P2 无美术;两列:飞镖房 | 刮刮乐房) ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var cols := HBoxContainer.new()
	cols.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	cols.position = Vector2(16, 16)
	cols.add_theme_constant_override("separation", 48)
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


func _on_dirty(_payload) -> void:
	_refresh()


func _on_jackpot(_count) -> void:
	_refresh()


func _on_cleared(room) -> void:
	if str(room) == "lotto":
		if _scratch_status != null:
			_scratch_status.text = "★ 已贿赂 Gorgon,刮刮乐房通关! ★"
	else:
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


## 从模型拉取最近离线结算(per-room),任一房 earned>0 才显示回归横幅(不靠事件,避免错过首帧)。
func _maybe_show_offline() -> void:
	if _offline_label == null:
		return
	var rep: Dictionary = FortuneMill.offline_report
	if rep.is_empty():
		return
	var g := float((rep.get("darts", {}) as Dictionary).get("earned", 0.0))
	var m := float((rep.get("lotto", {}) as Dictionary).get("earned", 0.0))
	var parts: Array = []
	if g > 0.0:
		parts.append("飞镖 %s gold" % Currency.format(g))
	if m > 0.0:
		parts.append("刮刮乐 %s money" % Currency.format(m))
	if parts.is_empty():
		return
	var mins := int(float((rep.get("darts", {}) as Dictionary).get("elapsed", 0.0)) / 60.0)
	_offline_label.visible = true
	_offline_label.text = "欢迎回来!离线 %d 分钟,自动攒了:%s" % [mins, ", ".join(parts)]
