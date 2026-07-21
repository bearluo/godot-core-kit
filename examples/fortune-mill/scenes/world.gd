extends Node
## 飞镖房表现层根 + FORTUNE_SMOKE headless 自测入口。
## UI 只读 FortuneMill 模型 + 发命令;订阅 bus 脏标记刷新,不持有权威数值。

const SMOKE_MAX_STEPS := 500000

var _gold_label: Label
var _status_label: Label
var _bribe_button: Button
var _upgrade_buttons: Dictionary = {}   # StringName(id) -> Button
var _rate_label: Label
var _offline_label: Label


func _ready() -> void:
	if OS.get_environment("FORTUNE_SMOKE") == "1":
		_run_smoke()
		return
	_build_ui()
	CoreKit.bus.subscribe("fortune:currency_changed", _on_dirty)
	CoreKit.bus.subscribe("fortune:upgrade_purchased", _on_dirty)
	CoreKit.bus.subscribe("fortune:room_cleared", _on_cleared)
	_refresh()
	_maybe_show_offline()


## --- FORTUNE_SMOKE:自动玩闭环,验证 $1 → 100 万 → 贿赂过关 ---

func _run_smoke() -> void:
	var fm = FortuneMill   # autoload;不用 := 以免静态类型退化为 Node
	var steps := 0
	# clean-room:autoload 的 _ready 可能已 load_game 载入历史存档(含通关态),
	# smoke 作为回归 gate 必须从全新态起步,否则载入通关档会 steps=0 直接假 PASS。
	fm.currency.set_amount(1.0)
	fm.darts.from_dict({})   # 重置 levels/cleared/bullseye_unlock + 清 modifier 残留
	CoreKit.saves.delete_slot(fm.SAVE_SLOT)
	while not fm.can_bribe() and steps < SMOKE_MAX_STEPS:
		fm.do_throw()
		if steps % 20 == 0:
			_smoke_buy_round(fm)
		steps += 1
	var ok: bool = fm.can_bribe() and fm.bribe_guard()
	# --- P1 回归:自动化产出 + 离线结算(过关后 gold 充裕,可买自动投) ---
	fm.buy_dart_upgrade(&"rattling_gunner")            # 确保 ≥1 级(已满级则 no-op,产率仍 >0)
	var rate: float = fm.darts.auto_gold_rate()
	var before_auto: float = fm.currency.get_amount()
	fm.tick(1.0)                                       # 模拟 1 秒自动产出
	var auto_ok: bool = rate > 0.0 and fm.currency.get_amount() > before_auto
	var t_now: float = Time.get_unix_time_from_system()
	var g_before: float = fm.currency.get_amount()
	var rep: Dictionary = fm.settle_offline(t_now - 3600.0, t_now)   # 模拟关游戏 1 小时
	var offline_ok: bool = float(rep.get("earned", 0.0)) > 0.0 and fm.currency.get_amount() > g_before
	var gold_str := Currency.format(fm.currency.get_amount())
	CoreKit.saves.delete_slot(fm.SAVE_SLOT)   # smoke 自清理,不留存档污染后续运行
	if ok and auto_ok and offline_ok:
		print("[Fortune][SMOKE] PASS gold=%s steps=%d cleared=%s auto_rate=%.2f offline_earn=%.0f" % [gold_str, steps, fm.darts.is_cleared(), rate, float(rep.get("earned", 0.0))])
		get_tree().quit(0)
	else:
		print("[Fortune][SMOKE] FAIL gold=%s steps=%d ok=%s auto_ok=%s offline_ok=%s" % [gold_str, steps, ok, auto_ok, offline_ok])
		get_tree().quit(1)


## 每轮把每条买得起的升级各买一级(均衡成长,推动数值爬升)。
func _smoke_buy_round(fm) -> void:
	for id in fm.registry.ids(&"dart_upgrade", true):
		fm.buy_dart_upgrade(id)


## --- 可玩 UI(代码构建,P0 无美术) ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2(16, 16)
	layer.add_child(root)

	_gold_label = Label.new()
	root.add_child(_gold_label)

	_status_label = Label.new()
	root.add_child(_status_label)

	_rate_label = Label.new()
	root.add_child(_rate_label)

	var throw_btn := Button.new()
	throw_btn.text = "投镖 (Throw)"
	throw_btn.pressed.connect(func(): FortuneMill.do_throw())
	root.add_child(throw_btn)

	root.add_child(HSeparator.new())
	var up_title := Label.new()
	up_title.text = "— 升级 —"
	root.add_child(up_title)

	for id in FortuneMill.registry.ids(&"dart_upgrade", true):
		var btn := Button.new()
		btn.pressed.connect(func(): FortuneMill.buy_dart_upgrade(id))
		root.add_child(btn)
		_upgrade_buttons[id] = btn

	root.add_child(HSeparator.new())
	_bribe_button = Button.new()
	_bribe_button.text = "贿赂 Verminous (需 1M gold)"
	_bribe_button.pressed.connect(func(): FortuneMill.bribe_guard())
	root.add_child(_bribe_button)

	_offline_label = Label.new()
	_offline_label.visible = false
	root.add_child(_offline_label)


func _on_dirty(_payload) -> void:
	_refresh()


func _on_cleared(_payload) -> void:
	_status_label.text = "★ 已贿赂 Verminous,飞镖房通关! ★"


func _refresh() -> void:
	if _gold_label == null:
		return
	_gold_label.text = "Gold: %s" % Currency.format(FortuneMill.currency.get_amount())
	if _rate_label != null:
		_rate_label.text = "自动: %s gold/s" % Currency.format(FortuneMill.darts.auto_gold_rate())
	for id in _upgrade_buttons:
		var def = FortuneMill.registry.get_def(&"dart_upgrade", id)
		var lvl := FortuneMill.darts.level_of(id)
		var cost := FortuneMill.darts.cost_of(id)
		var btn: Button = _upgrade_buttons[id]
		btn.text = "%s  Lv.%d  (%s gold)" % [def.title, lvl, Currency.format(cost)]
		btn.disabled = not FortuneMill.currency.can_afford(cost)
	_bribe_button.disabled = not FortuneMill.can_bribe()


## 从模型拉取最近离线结算,earned>0 才显示回归横幅(不靠事件,避免错过首帧)。
func _maybe_show_offline() -> void:
	if _offline_label == null:
		return
	var rep: Dictionary = FortuneMill.offline_report
	if rep.is_empty() or float(rep.get("earned", 0.0)) <= 0.0:
		return
	var mins := int(float(rep.get("elapsed", 0.0)) / 60.0)
	var capped := " (已封顶)" if bool(rep.get("capped", false)) else ""
	_offline_label.visible = true
	_offline_label.text = "欢迎回来!离线 %d 分钟%s,自动攒了 %s gold" % [mins, capped, Currency.format(float(rep.get("earned", 0.0)))]
