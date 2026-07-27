extends Node
## world 表现层根(飞镖 + 刮刮乐 + 柏青哥 + 寿司 + 扭蛋 五房 + 元进度 NG+)+ FORTUNE_SMOKE headless 自测入口。
## UI 只读 FortuneMill 模型 + 发命令;订阅 bus 脏标记刷新,不持有权威数值。
## 柏青哥有真物理表现层(pachinko_board.gd,仅非 smoke 实例化);smoke 走 model 直算。

const SMOKE_MAX_STEPS := 500000
const DARTS_ROOM_SCENE := "res://examples/fortune-mill/scenes/darts_room.tscn"   ## 全屏墙房(飞镖真交互)入口
const PachinkoBoard := preload("res://examples/fortune-mill/scenes/pachinko_board.gd")
const FortuneArtBank := preload("res://examples/fortune-mill/gfx/art_bank.gd")
const FortuneFx := preload("res://examples/fortune-mill/gfx/fx.gd")
const FortuneSoundBank := preload("res://examples/fortune-mill/sfx/sound_bank.gd")
## i18n 标题 key → art_bank 房间调色板 key(图标 + 面板边框上色)。
const TITLE_TO_ROOM := {
	"fortune.room_darts": &"darts",
	"fortune.room_lotto": &"lotto",
	"fortune.room_pachinko": &"pachinko",
	"fortune.room_sushi": &"sushi",
	"fortune.room_gacha": &"gacha",
	"fortune.room_meta": &"meta",
	"fortune.room_ach": &"ach",
}

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
# 元进度 (NG+)
var _ng_label: Label
var _prestige_points_label: Label
var _lethal_label: Label
var _ascend_button: Button
var _lethal_button: Button
var _prestige_upgrade_buttons: Dictionary = {}
# 成就
var _ach_count_label: Label
var _ach_toast_label: Label
var _ach_list_label: Label
var _ach_recent: Array = []   # 最近解锁的 toast 文案(滚动展示)
# i18n(中英切换)
var _lang_button: Button
var _i18n_labels: Dictionary = {}   # key(String) -> Label(标题栏,随语言刷新)
var _i18n_buttons: Dictionary = {}  # key(String) -> Button(主操作按钮,随语言刷新)
# 手感/美术/音效(P5 5A/5B;仅可玩路径实例化)
var _art: FortuneArtBank
var _fx: FortuneFx
var _sfx: FortuneSoundBank

## OTA:扭蛋房内容包的 manifest 地址(改成你的 CDN/服务器)。本地测试用 python -m http.server。
const GACHA_MANIFEST_URL := "http://localhost:8080/manifest.json"
var _ota_status: Label        # 扭蛋房占位处的 OTA 状态标签(仅缺包时建)
var _ota_restart_btn: Button  # 下载完成后显现:重启以应用更新


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
	CoreKit.bus.subscribe("fortune:ascended", _on_ascended)
	CoreKit.bus.subscribe("fortune:prestige_bought", _on_dirty)
	CoreKit.bus.subscribe("fortune:lethal_started", _on_dirty)
	CoreKit.bus.subscribe("fortune:lethal_ended", _on_dirty)
	CoreKit.bus.subscribe("fortune:lethal_finished", _on_lethal_finished)
	CoreKit.bus.subscribe("fortune:room_cleared", _on_cleared)
	CoreKit.bus.subscribe("fortune:achievement_unlocked", _on_achievement_unlocked)
	CoreKit.i18n.locale_changed.connect(_on_locale_changed)   # 切语言 → 刷新 i18n 文案
	# OTA:扭蛋房内容包更新流程(check→download→重启屏障)。仅缺包时占位 UI 触发 check。
	CoreKit.updater.update_available.connect(_on_ota_available)
	CoreKit.updater.up_to_date.connect(func() -> void: _ota_set("已是最新(未发现扭蛋房内容包)"))
	CoreKit.updater.check_failed.connect(func(r: String) -> void: _ota_set("检查失败: %s" % r))
	CoreKit.updater.downloaded.connect(func(id: String) -> void: _ota_set("已下载 %s ✓" % id))
	CoreKit.updater.download_failed.connect(func(id: String, r: String) -> void: _ota_set("下载失败 %s: %s" % [id, r]))
	CoreKit.updater.ready_to_apply.connect(_on_ota_ready)
	_refresh()
	_maybe_show_offline()
	_maybe_web_auto_ota()


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
	fm.prestige.from_dict({})
	fm.stats.from_dict({})           # 统计清零(成就阈值从新档起判)
	fm.achievements.from_dict({})    # 已解锁成就清空
	CoreKit.saves.delete_slot(fm.SAVE_SLOT)

	# --- 墙面定点验证(趁未升级:单镖 base×500×radial2=1000;vermin→0;两投顺带喂 jackpot/vermin 统计)---
	var wr: Dictionary = fm.do_throw(FortuneWheelLayout.aim_for(&"jackpot"), FortuneWheelLayout.POWER_SWEET)
	var wheel_ok: bool = absf(float(wr["gold"]) - 1000.0) < 0.01 and wr["hits"][0]["seg"] == &"jackpot"
	var vermin_ok: bool = absf(float(fm.do_throw(FortuneWheelLayout.aim_for(&"vermin"), FortuneWheelLayout.POWER_SWEET)["gold"])) < 0.01

	# --- P0:飞镖房手动爬到 1M 贿赂 Verminous(墙面:aim 对准当前布局档的 jackpot 甜点确定性投)---
	# 注:买 widen_zone 会换奖励区布局档、移动头奖中心,故每轮按当前档重算 jackpot 瞄准
	while not fm.can_bribe() and steps < SMOKE_MAX_STEPS:
		var lay: Array = FortuneWheelLayout.layout_for(fm.darts.level_of(&"widen_zone"))
		fm.do_throw(FortuneWheelLayout.aim_for(&"jackpot", lay), FortuneWheelLayout.POWER_SWEET)
		if steps % 20 == 0:
			_smoke_buy_round(fm)
		steps += 1
	var ok: bool = fm.can_bribe() and fm.bribe_guard()

	# --- P1:飞镖自动产出 + 离线结算 ---
	fm.buy_dart_upgrade(&"hire_ai")
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

	# --- P4 4B:NG+ 元进度(ascend 门槛 ×10 + prestige 永久加成 + Lethal Mode 计时)---
	# 此刻 5 房均已 cleared → 可 ascend。ascend 前记 stuffing/ribbons 供 PASS 行展示。
	var stuffing_final: float = fm.stuffing.get_amount()
	var ribbons_final: float = fm.ribbons.get_amount()
	var run_complete_pre: bool = fm.is_run_complete()
	var thr_pre: float = fm.darts.bribe_threshold()          # ng0 → 1M
	var asc: Dictionary = fm.ascend()
	var ng_level: int = int(asc.get("ng_level", 0))
	var thr_post: float = fm.darts.bribe_threshold()         # ng1 → 10M
	var ng_ok: bool = run_complete_pre and ng_level == 1 and absf(thr_post - thr_pre * 10.0) < 1.0
	# ascend 重置:5 房货币归零 + 守卫重新拦路
	var reset_ok: bool = fm.currency.get_amount() <= 1.0 and fm.money.get_amount() == 0.0 and not fm.darts.is_cleared() and not fm.gacha.is_cleared()
	# prestige 专属升级(NG+ 才能买):ascend 发 1 点 → 买 eternal_fortune → 永久 global_mul ×1.5
	var gmul_pre: float = fm.modifiers.value_for(&"global_mul", 1.0)
	var prestige_bought: bool = fm.buy_prestige_upgrade(&"eternal_fortune")
	var gmul_post: float = fm.modifiers.value_for(&"global_mul", 1.0)
	var prestige_ok: bool = prestige_bought and absf(gmul_post - gmul_pre * 1.5) < 0.01
	var prestige_gmul := (gmul_post / gmul_pre) if gmul_pre > 0.0 else 0.0
	# Lethal Mode:开速通 → 无 NG+ 加成(global_mul 回落 + 门槛回 1M)+ 计时;注资通 5 房 → 记最佳时间 + 恢复加成
	var lethal_started: bool = fm.start_lethal()
	var gmul_in_lethal: float = fm.modifiers.value_for(&"global_mul", 1.0)
	var thr_in_lethal: float = fm.darts.bribe_threshold()
	fm.prestige.tick_lethal(8.0)
	var lethal_enter_ok: bool = lethal_started and gmul_in_lethal < gmul_post and absf(thr_in_lethal - 1_000_000.0) < 1.0 and fm.prestige.lethal_elapsed() > 0.0
	fm.currency.add(1_000_000.0); fm.bribe_guard()
	fm.money.add(1_000_000.0); fm.bribe_gorgon()
	fm.tickets.add(1_000_000.0); fm.bribe_rimmington()
	fm.ribbons.add(1_000_000.0); fm.bribe_hivemind()
	fm.stuffing.add(1_000_000.0); fm.bribe_executor()        # 第 5 房触发 _check_lethal_finish 记时
	var lethal_best: float = fm.prestige.lethal_best()
	var gmul_after_lethal: float = fm.modifiers.value_for(&"global_mul", 1.0)
	var lethal_ok: bool = lethal_enter_ok and not fm.prestige.lethal_active() and absf(lethal_best - 8.0) < 0.01 and absf(gmul_after_lethal - gmul_post) < 0.01

	# --- P4 4C:51 成就 + KitStats 统计(玩到此处应解锁大量成就;验去重与阈值判定)---
	var ach = fm.achievements
	var must_unlock := [&"guard_darts", &"guard_lotto", &"guard_pachinko", &"guard_sushi", &"guard_gacha",
		&"ng_1", &"seg_jackpot_1", &"throws_100", &"gold_1e5", &"payout_1e2",
		&"jackpot_1", &"pull_1", &"craft_1", &"drop_1", &"dice_1", &"scratch_1", &"recipe_1", &"prestige_1", &"lethal_1"]
	var ach_all := true
	for aid in must_unlock:
		if not ach.is_unlocked(aid):
			ach_all = false
	var ach_count: int = ach.count()
	var ach_total: int = ach.total()
	var ach_dedup: bool = ach.evaluate(fm.stats).is_empty()   # 去重:同状态再求值应无新解锁
	var stat_throws: float = fm.stats.get_value(&"dart_throws", 0.0)
	var ach_ok: bool = ach_all and ach_total == 51 and ach_count >= 25 and ach_dedup and stat_throws >= 100.0

	# --- P4 4D:存档版本迁移链(v1→v2→v3)+ i18n 中英(运行时切换 + 缺翻译回退)---
	# 迁移:造一条 v1 老档(键 "gold" + stats.throws)→ 逐级升到 v3(currency + stats.dart_throws)
	var v1_save := {"schema_version": 1, "gold": 12345.0, "stats": {"throws": 42.0}}
	var mig: Dictionary = fm._migrator.migrate(v1_save)
	var mig_chain_ok: bool = mig.ok and int(mig.to) == 4 and mig.data.has("currency") and not mig.data.has("gold") \
		and absf(float(mig.data["currency"]) - 12345.0) < 0.01 \
		and (mig.data["stats"] as Dictionary).has("dart_throws") and not (mig.data["stats"] as Dictionary).has("throws")
	# 无版本章的历史档默认 v1 并迁到 v3;未来版本安全失败(保底新档)
	var mig_unversioned: Dictionary = fm._migrator.migrate({"gold": 1.0})
	var mig_future: Dictionary = fm._migrator.migrate({"schema_version": 999})
	var migration_ok: bool = mig_chain_ok and mig_unversioned.ok and int(mig_unversioned.from) == 1 \
		and (not mig_future.ok) and str(mig_future.reason) == "future"
	# i18n:_ready 已注册 en/zh 目录;运行时切语言同 key 文案不同,缺翻译回退原 key
	CoreKit.i18n.set_locale("en")
	var i18n_en: String = CoreKit.i18n.t(&"fortune.throw")
	CoreKit.i18n.set_locale("zh")
	var i18n_zh: String = CoreKit.i18n.t(&"fortune.throw")
	var i18n_missing: String = CoreKit.i18n.t(&"fortune.__nonexistent__")
	var i18n_ok: bool = i18n_en == "Throw" and i18n_zh == "投镖" and i18n_missing == "fortune.__nonexistent__"

	# --- P5 5A:程序化美术接缝(headless 生成 + 房间辨识 + 无真素材走程序化兜底)---
	var ab = FortuneArtBank.new()
	var art_tex = ab.texture_for(&"darts", 32)
	var art_darts = art_tex.get_image().get_pixel(16, 16) if art_tex != null else Color.BLACK
	var art_sushi = ab.texture_for(&"sushi", 32).get_image().get_pixel(16, 16)
	var art_ok: bool = art_tex != null and art_tex.get_width() == 32 and not art_darts.is_equal_approx(art_sushi) and ab.source_for(&"darts") == "procedural"

	# --- P5 5B:程序化音效接缝(headless 合成 + voice 可辨识 + 无真音频走程序化兜底)---
	var sb = FortuneSoundBank.new()
	var s_throw = sb.stream_for(&"throw")
	var s_jackpot = sb.stream_for(&"jackpot")
	var sfx_ok: bool = s_throw != null and s_throw is AudioStream and s_throw.get_length() > 0.0 and s_jackpot.get_length() > s_throw.get_length() and sb.source_for(&"throw") == "procedural"

	var gacha_boost := (darts_post_gacha / darts_pre_gacha) if darts_pre_gacha > 0.0 else 0.0
	var switch_boost := (darts_post_switch / darts_pre_switch) if darts_pre_switch > 0.0 else 0.0
	var dice_boost := (darts_post_dice / darts_pre_dice) if darts_pre_dice > 0.0 else 0.0
	var boost := (darts_rate_post / darts_rate_pre) if darts_rate_pre > 0.0 else 0.0
	CoreKit.saves.delete_slot(fm.SAVE_SLOT)
	var p012 := ok and auto_ok and offline_ok and crossroom_ok and gorgon_ok
	var p3 := pach_drop_ok and dice_cross_ok and rimmington_ok and off3_ok
	var p3s := craft_ok and switch_cross_ok and hivemind_ok and off4_ok
	var p4 := pull_ok and gacha_cross_ok and executor_ok and off5_ok
	var p4b := ng_ok and reset_ok and prestige_ok and lethal_ok
	var p4c := ach_ok
	var p4d := migration_ok and i18n_ok
	var p5a := art_ok
	var p5b := sfx_ok
	if p012 and p3 and p3s and p4 and p4b and p4c and p4d and p5a and p5b and wheel_ok and vermin_ok:
		print("[Fortune][SMOKE] PASS steps=%d jackpots=%d darts_boost=%.2fx gorgon=%s dice_boost=%.2fx rimmington=%s craft=%s switch_boost=%.2fx hivemind=%s gacha_boost=%.2fx executor=%s | ng=%d thr=%s prestige_gmul=%.2fx lethal_best=%.1fs | achievements=%d/%d throws=%d | migration=v%d→v%d i18n=%s/%s | art=%dx%d/%s sfx=%.2fs/%s | wall=jackpot%.0f/vermin0 | stuffing=%s ribbons=%s" % [steps, jackpots, boost, fm.lotto.is_cleared(), dice_boost, fm.pachinko.is_cleared(), craft_ok, switch_boost, fm.sushi.is_cleared(), gacha_boost, fm.gacha.is_cleared(), ng_level, Currency.format(thr_post), prestige_gmul, lethal_best, ach_count, ach_total, int(stat_throws), int(mig.from), int(mig.to), i18n_en, i18n_zh, art_tex.get_width(), art_tex.get_height(), ab.source_for(&"darts"), s_throw.get_length(), sb.source_for(&"throw"), float(wr["gold"]), Currency.format(stuffing_final), Currency.format(ribbons_final)])
		get_tree().quit(0)
	else:
		print("[Fortune][SMOKE] FAIL p0=%s auto=%s offline=%s cross=%s gorgon=%s | drop=%s dice_cross=%s rimmington=%s off3=%s | craft=%s switch=%s hivemind=%s off4=%s | pull=%s gacha_cross=%s executor=%s off5=%s | ng=%s reset=%s prestige=%s(%.2f→%.2f) lethal=%s(enter=%s best=%.1f) | ach=%s(all=%s count=%d/%d dedup=%s throws=%d) | migration=%s i18n=%s(en=%s zh=%s missing=%s) | p5a=%s p5b=%s | wheel=%s vermin=%s" % [ok, auto_ok, offline_ok, crossroom_ok, gorgon_ok, pach_drop_ok, dice_cross_ok, rimmington_ok, off3_ok, craft_ok, switch_cross_ok, hivemind_ok, off4_ok, pull_ok, gacha_cross_ok, executor_ok, off5_ok, ng_ok, reset_ok, prestige_ok, gmul_pre, gmul_post, lethal_ok, lethal_enter_ok, lethal_best, ach_ok, ach_all, ach_count, ach_total, ach_dedup, int(stat_throws), migration_ok, i18n_ok, i18n_en, i18n_zh, i18n_missing, art_ok, sfx_ok, wheel_ok, vermin_ok])
		get_tree().quit(1)


## 每轮把每条买得起的飞镖升级各买一级。
func _smoke_buy_round(fm) -> void:
	for id in fm.registry.ids(&"dart_upgrade", true):
		fm.buy_dart_upgrade(id)


## --- 可玩 UI(代码构建;三列:飞镖 | 刮刮乐 | 柏青哥 + 右侧物理板) ---

func _build_ui() -> void:
	_art = FortuneArtBank.new()
	var layer := CanvasLayer.new()
	add_child(layer)
	# 赌场毛毡背景(铺满,置于所有 UI 之下,不拦鼠标)
	var felt := ColorRect.new()
	felt.color = Color("0e3b2e")
	felt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(felt)
	# i18n:托管赌场皮肤 Theme(按钮/标签样式)+ zh CJK 系统字体回退;切语言即换 theme.default_font
	var theme := _build_theme()
	CoreKit.i18n.bind_theme(theme)   # 当前 locale 若已注册字体则立即应用一次
	var root := VBoxContainer.new()
	root.theme = theme               # 主题下发全部子控件 → 字体 + 皮肤随 locale 切换
	root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2(16, 16)
	layer.add_child(root)
	# 语言切换按钮(中/英)
	_lang_button = Button.new()
	_lang_button.text = CoreKit.i18n.t("fortune.lang")
	_lang_button.pressed.connect(_on_lang_pressed)
	root.add_child(_lang_button)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	root.add_child(cols)

	# 飞镖房列(墙房入口:摘要 + 进入按钮 → FADE 进全屏墙房 darts_room.tscn;真瞄准/蓄力/投掷都在墙房内)
	var dcol := _room_panel(cols, "fortune.room_darts")
	_add_title(dcol, "fortune.room_darts")
	_gold_label = Label.new(); dcol.add_child(_gold_label)
	_status_label = Label.new(); dcol.add_child(_status_label)
	_rate_label = Label.new(); dcol.add_child(_rate_label)
	# 进入全屏墙房:真瞄准/蓄力/投掷都在墙房里,hub 只留摘要 + 升级 + 贿赂
	var enter_btn := Button.new()
	enter_btn.text = CoreKit.i18n.t("fortune.enter_darts")
	enter_btn.pressed.connect(_on_enter_darts)
	_i18n_buttons["fortune.enter_darts"] = enter_btn
	dcol.add_child(enter_btn)
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
	var lcol := _room_panel(cols, "fortune.room_lotto")
	_add_title(lcol, "fortune.room_lotto")
	_money_label = Label.new(); lcol.add_child(_money_label)
	_scratch_status = Label.new(); lcol.add_child(_scratch_status)
	_lotto_rate_label = Label.new(); lcol.add_child(_lotto_rate_label)
	_jackpot_label = Label.new(); lcol.add_child(_jackpot_label)
	lcol.add_child(_i18n_button("fortune.scratch", _on_scratch_pressed))
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
	var pcol := _room_panel(cols, "fortune.room_pachinko")
	_add_title(pcol, "fortune.room_pachinko")
	_tickets_label = Label.new(); pcol.add_child(_tickets_label)
	_pachinko_status = Label.new(); pcol.add_child(_pachinko_status)
	_pachinko_rate_label = Label.new(); pcol.add_child(_pachinko_rate_label)
	_dice_label = Label.new(); pcol.add_child(_dice_label)
	pcol.add_child(_i18n_button("fortune.drop", _on_drop_pressed))
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
	var scol := _room_panel(cols, "fortune.room_sushi")
	_add_title(scol, "fortune.room_sushi")
	_ribbons_label = Label.new(); scol.add_child(_ribbons_label)
	_sushi_status = Label.new(); scol.add_child(_sushi_status)
	_sushi_rate_label = Label.new(); scol.add_child(_sushi_rate_label)
	_craft_label = Label.new(); scol.add_child(_craft_label)
	var restock_btn := Button.new(); restock_btn.text = "备料 (Restock ×10)"
	restock_btn.pressed.connect(func() -> void: FortuneMill.restock_sushi_all(10))
	scol.add_child(restock_btn)
	scol.add_child(_i18n_button("fortune.craft", func() -> void: FortuneMill.start_craft()))
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

	# 扭蛋房列(可下载内容包 OTA:未下载则占位,下载 + 重启后出现)
	var gcol := _room_panel(cols, "fortune.room_gacha")
	_add_title(gcol, "fortune.room_gacha")
	if FortuneMill.has_gacha():
		_stuffing_label = Label.new(); gcol.add_child(_stuffing_label)
		_gacha_status = Label.new(); gcol.add_child(_gacha_status)
		_gacha_rate_label = Label.new(); gcol.add_child(_gacha_rate_label)
		_collection_label = Label.new(); gcol.add_child(_collection_label)
		gcol.add_child(_i18n_button("fortune.pull", _on_pull_pressed))
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
	else:
		var lock := Label.new()
		lock.text = "🔒 扭蛋房未安装"
		gcol.add_child(lock)
		var dl := Button.new()
		dl.text = "检查 / 下载扭蛋房 (OTA)"
		dl.pressed.connect(_on_ota_check)
		gcol.add_child(dl)
		_ota_status = Label.new()
		_ota_status.text = "内容包待下载"
		gcol.add_child(_ota_status)
		_ota_restart_btn = Button.new()
		_ota_restart_btn.text = "▶ 重启以应用更新"
		_ota_restart_btn.visible = false
		_ota_restart_btn.pressed.connect(func() -> void: CoreKit.updater.restart_to_apply())
		gcol.add_child(_ota_restart_btn)

	# 元进度列 (NG+)
	var ncol := _room_panel(cols, "fortune.room_meta")
	_add_title(ncol, "fortune.room_meta")
	_ng_label = Label.new(); ncol.add_child(_ng_label)
	_prestige_points_label = Label.new(); ncol.add_child(_prestige_points_label)
	_lethal_label = Label.new(); ncol.add_child(_lethal_label)
	ncol.add_child(HSeparator.new())
	_ascend_button = _i18n_button("fortune.ascend", func() -> void: FortuneMill.ascend())
	ncol.add_child(_ascend_button)
	ncol.add_child(HSeparator.new())
	for id in FortuneMill.prestige.upgrade_ids():
		var btn := Button.new()
		btn.pressed.connect(func() -> void: FortuneMill.buy_prestige_upgrade(id))
		ncol.add_child(btn)
		_prestige_upgrade_buttons[id] = btn
	ncol.add_child(HSeparator.new())
	_lethal_button = Button.new()
	_lethal_button.pressed.connect(_on_lethal_pressed)
	ncol.add_child(_lethal_button)

	# 成就列(51 条:计数 + 最近解锁 toast + 明细速览)
	var acol := _room_panel(cols, "fortune.room_ach")
	_add_title(acol, "fortune.room_ach")
	_ach_count_label = Label.new(); acol.add_child(_ach_count_label)
	_ach_toast_label = Label.new(); acol.add_child(_ach_toast_label)
	acol.add_child(HSeparator.new())
	_ach_list_label = Label.new(); _ach_list_label.text = "最近解锁:"; acol.add_child(_ach_list_label)

	# 柏青哥物理板(真 RigidBody2D 落球;juice)
	_pachinko_board = PachinkoBoard.new()
	add_child(_pachinko_board)

	# 手感层(浮字冒泡 / 全屏闪光 / 按钮脉冲)
	_fx = FortuneFx.new()
	add_child(_fx)

	# 音效库(程序化 SFX;经 CoreKit.audio 轮转池播放)
	_sfx = FortuneSoundBank.new()


## 标题栏:房间图标(art_bank)+ 文案(走 i18n key,注册进 _i18n_labels 供切语言时刷新)。
func _add_title(col: VBoxContainer, key: String) -> void:
	var row := HBoxContainer.new()
	var room: StringName = TITLE_TO_ROOM.get(key, &"")
	var icon := TextureRect.new()
	icon.texture = _art.texture_for(room, 24)
	icon.custom_minimum_size = Vector2(24, 24)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var l := Label.new()
	l.text = CoreKit.i18n.t(key)
	row.add_child(l)
	col.add_child(row)
	_i18n_labels[key] = l


## 赌场皮肤 Theme:深底金字按钮(normal/hover/pressed/disabled 分级)+ 浅色标签 + zh 字体回退。
func _build_theme() -> Theme:
	var theme := Theme.new()
	var zh_font := SystemFont.new()   # 零素材,SystemFont 走 OS 字体族
	zh_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "PingFang SC", "sans-serif"])
	CoreKit.i18n.register_locale_font("zh", zh_font)
	theme.set_stylebox("normal", "Button", _flat(Color("1c2a24"), Color("caa24a"), 1))
	theme.set_stylebox("hover", "Button", _flat(Color("26382f"), Color("e6c260"), 1))
	theme.set_stylebox("pressed", "Button", _flat(Color("13201a"), Color("caa24a"), 1))
	theme.set_stylebox("disabled", "Button", _flat(Color("161d1a"), Color("3a463f"), 1))
	theme.set_color("font_color", "Button", Color("f0e0b0"))
	theme.set_color("font_hover_color", "Button", Color("fff0c0"))
	theme.set_color("font_pressed_color", "Button", Color("caa24a"))
	theme.set_color("font_disabled_color", "Button", Color("6a726b"))
	theme.set_color("font_color", "Label", Color("e8e8e0"))
	return theme


## 圆角描边 StyleBoxFlat 工厂(赌场皮肤共用)。
func _flat(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	return sb


## 房间列:PanelContainer(强调色边框 + 深底)包一层 VBox,返回内层 VBox 供填充。
func _room_panel(parent: HBoxContainer, title_key: String) -> VBoxContainer:
	var room: StringName = TITLE_TO_ROOM.get(title_key, &"")
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat(Color("13251d"), _art.color_for(room), 2))
	parent.add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	return col


## 进入全屏墙房:FADE 切到 darts_room.tscn(真瞄准/蓄力/投掷都在墙房里;墙房返回再 FADE 回 world)。
func _on_enter_darts() -> void:
	CoreKit.scenes.change_scene(DARTS_ROOM_SCENE, {"transition": CoreKit.scenes.Transition.FADE})


## 在锚点控件右侧冒一条浮字(纯表现;fx 未就绪/控件未入树时静默跳过)。
func _pop_at(anchor: Control, text: String, color: Color) -> void:
	if _fx == null or anchor == null or not anchor.is_inside_tree():
		return
	_fx.popup(text, anchor.global_position + Vector2(anchor.size.x + 6.0, -4.0), color)


## 主操作按钮按下脉冲(纯表现)。
func _pulse_button(key: String) -> void:
	if _fx != null and _i18n_buttons.has(key):
		_fx.pulse(_i18n_buttons[key])


## 播一条程序化 SFX(经 CoreKit.audio 轮转池;pitch 抖动加活力,纯表现)。
func _play_sfx(key: StringName, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	if _sfx == null:
		return
	CoreKit.audio.play_sfx(_sfx.stream_for(key), volume_db, pitch)


## 主操作按钮:文案走 i18n key,注册进 _i18n_buttons 供切语言时刷新。
func _i18n_button(key: String, on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = CoreKit.i18n.t(key)
	btn.pressed.connect(on_press)
	_i18n_buttons[key] = btn
	return btn


## 语言切换按钮:中↔英切换(经 kit LocaleManager;持久化 + 换字体由其托管)。
func _on_lang_pressed() -> void:
	var next := "en" if CoreKit.i18n.get_locale() == "zh" else "zh"
	CoreKit.i18n.set_locale(next)


## locale_changed 回调:重刷所有 i18n 文案(标题/按钮/语言键)+ 全 HUD。
func _on_locale_changed(_locale) -> void:
	_apply_locale_texts()
	_refresh()


func _apply_locale_texts() -> void:
	for key in _i18n_labels:
		(_i18n_labels[key] as Label).text = CoreKit.i18n.t(key)
	for key in _i18n_buttons:
		(_i18n_buttons[key] as Button).text = CoreKit.i18n.t(key)
	if _lang_button != null:
		_lang_button.text = CoreKit.i18n.t("fortune.lang")


func _on_scratch_pressed() -> void:
	var r: Dictionary = FortuneMill.do_scratch()
	var money_won := float(r.get("money", 0.0))
	if money_won > 0.0:
		_pop_at(_money_label, "+%s" % Currency.format(money_won), _art.color_for(&"lotto"))
	_pulse_button("fortune.scratch")
	_play_sfx(&"scratch", -7.0, randf_range(0.97, 1.05))
	if _scratch_status == null:
		return
	var earned := Currency.format(money_won)
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
	_play_sfx(&"drop", -9.0, randf_range(0.9, 1.12))   # 落球发射音(落槽 tick 由物理板负责)


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
	var st_won := float(r.get("stuffing", 0.0))
	if st_won > 0.0:
		_pop_at(_stuffing_label, "+%s" % Currency.format(st_won), _art.color_for(&"gacha"))
	_pulse_button("fortune.pull")
	_play_sfx(&"pull", -7.0, randf_range(0.97, 1.05))
	if _gacha_status == null:
		return
	var st := Currency.format(st_won)
	_gacha_status.text = "抽到 [%s] %s (+%s stuffing, 持有 %d)" % [str(r.get("rarity", &"")), str(r.get("item", &"")), st, int(r.get("owned", 0))]


## --- OTA:扭蛋房内容包更新(check → download → 重启屏障;含 GDScript 逻辑必须重启) ---

func _on_ota_check() -> void:
	_ota_set("检查更新中…")
	CoreKit.updater.check(GACHA_MANIFEST_URL)


func _on_ota_available(plan: Dictionary) -> void:
	_ota_set("发现扭蛋房内容包,下载中…")
	CoreKit.updater.download(plan)


func _on_ota_ready() -> void:
	# 下载校验落盘完成;扭蛋房含 GDScript 逻辑 → 必须重启进程才生效(研究 §4b)。
	# Web 上 restart_to_apply() 返 false,重启屏障 = 由外部 reload 页面(见 _maybe_web_auto_ota)。
	if OS.has_feature("web"):
		print("[WEBOTA] ready-to-apply")
	_ota_set("下载完成 ✓ 重启后扭蛋房出现")
	if _ota_restart_btn != null:
		_ota_restart_btn.visible = true


func _ota_set(msg: String) -> void:
	if _ota_status != null:
		_ota_status.text = msg


## Web headless 自驱 OTA(仿 FORTUNE_SMOKE 的自测入口):URL 带 ?autoota=1 时自动跑
## check→download,外部驱动脚本收到 [WEBOTA] ready-to-apply 后 reload 页面(web 上
## restart_to_apply() 返 false,重启屏障 = reload)。同源取 manifest,规避硬编码 localhost:8080。
func _maybe_web_auto_ota() -> void:
	if not OS.has_feature("web"):
		return
	var search := str(JavaScriptBridge.eval("location.search", true))
	if search.find("autoota=1") == -1:
		return
	if FortuneMill.has_gacha():
		print("[WEBOTA] boot has_gacha=true gacha-online")   # reload 后:包已在 _init 挂载
		return
	# kit 0.24.1 起 HttpPackTransport 在 web 自动走 store_buffer 落盘,直接用默认传输即可。
	var origin := str(JavaScriptBridge.eval("location.origin", true))
	print("[WEBOTA] boot has_gacha=false auto-check manifest=%s/manifest.json" % origin)
	CoreKit.updater.check(origin + "/manifest.json")


## Lethal 按钮:进行中 → 放弃;否则开一局速通。
func _on_lethal_pressed() -> void:
	if FortuneMill.prestige.lethal_active():
		FortuneMill.abort_lethal()
	else:
		FortuneMill.start_lethal()
	_refresh()


func _on_ascended(info) -> void:
	if _ng_label != null:
		_ng_label.text = "★ 进入 NG+%d!5 房重置,门槛 ×10 ★" % int((info as Dictionary).get("ng_level", 0))
	_refresh()


func _on_lethal_finished(t) -> void:
	if _lethal_label != null:
		_lethal_label.text = "🏁 Lethal 通关!用时 %.1fs" % float(t)
	_refresh()


## 成就解锁 toast:查 def 标题 → 顶出一条,保留最近 6 条滚动。
func _on_achievement_unlocked(id) -> void:
	var def = FortuneMill.registry.get_def(&"achievement", id)
	var title: String = def.title if def != null else String(id)
	if _ach_toast_label != null:
		_ach_toast_label.text = "🎉 解锁:%s" % title
	_ach_recent.push_front("· %s" % title)
	if _ach_recent.size() > 6:
		_ach_recent.resize(6)
	if _ach_list_label != null:
		_ach_list_label.text = "最近解锁:\n%s" % "\n".join(_ach_recent)
	if _ach_count_label != null:
		_ach_count_label.text = "已解锁: %d / %d" % [FortuneMill.achievements.count(), FortuneMill.achievements.total()]


func _on_dirty(_payload) -> void:
	_refresh()


func _on_jackpot(_count) -> void:
	if _fx != null:
		_fx.flash(Color(0.95, 0.78, 0.25, 0.45))   # 金色 JACKPOT 闪
	_play_sfx(&"jackpot", -4.0)                     # 上行琶音 fanfare
	_refresh()


func _on_cleared(room) -> void:
	if _fx != null and _art != null:
		var room_key: StringName = &"darts"
		match str(room):
			"lotto": room_key = &"lotto"
			"pachinko": room_key = &"pachinko"
			"sushi": room_key = &"sushi"
			"gacha": room_key = &"gacha"
		var c: Color = _art.color_for(room_key)
		_fx.flash(Color(c.r, c.g, c.b, 0.4))   # 房间强调色过关庆祝闪
	_play_sfx(&"clear", -3.0)                  # 过关 fanfare
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
	# 扭蛋房(可下载内容包;缺包时列为占位,跳过刷新)
	if FortuneMill.has_gacha():
		_stuffing_label.text = "Stuffing: %s" % Currency.format(FortuneMill.stuffing.get_amount())
		_gacha_rate_label.text = "自动: %s st/s" % Currency.format(FortuneMill.gacha.auto_stuffing_rate())
		var coll: Array = []
		for iid in FortuneMill.gacha.item_ids():
			var n: int = FortuneMill.gacha.owned(iid)
			if n > 0:
				coll.append("%s×%d" % [str(iid), n])
		_collection_label.text = "收藏: %s" % (", ".join(coll) if not coll.is_empty() else "(空)")
		for id in _gacha_upgrade_buttons:
			var gdef = FortuneMill.registry.get_def(&"gacha_upgrade", id)
			var glvl: int = FortuneMill.gacha.level_of(id)
			var gcost: float = FortuneMill.gacha.cost_of(id)
			var gbtn: Button = _gacha_upgrade_buttons[id]
			gbtn.text = "%s  Lv.%d  (%s st)" % [gdef.title, glvl, Currency.format(gcost)]
			gbtn.disabled = not FortuneMill.stuffing.can_afford(gcost)
		_executor_button.disabled = not FortuneMill.can_bribe_executor()
	# 元进度 (NG+)
	_ng_label.text = "周目: NG+%d   门槛 ×%.0f" % [FortuneMill.prestige.ng_level(), FortuneMill.prestige.threshold_factor()]
	_prestige_points_label.text = "Prestige 点: %s" % Currency.format(FortuneMill.prestige.points())
	if FortuneMill.prestige.lethal_active():
		_lethal_label.text = "☠ LETHAL %.1fs (无 NG+ 加成)" % FortuneMill.prestige.lethal_elapsed()
		_lethal_button.text = "放弃 Lethal (Abort)"
	else:
		var best := FortuneMill.prestige.lethal_best()
		_lethal_label.text = "Lethal 最佳: %s" % (("%.1fs" % best) if best >= 0.0 else "—")
		_lethal_button.text = "开始 Lethal 速通"
	_ascend_button.disabled = not FortuneMill.can_ascend()
	for id in _prestige_upgrade_buttons:
		var predef = FortuneMill.registry.get_def(&"prestige_upgrade", id)
		var prlvl := FortuneMill.prestige.level_of(id)
		var prcost := FortuneMill.prestige.cost_of(id)
		var prbtn: Button = _prestige_upgrade_buttons[id]
		prbtn.text = "%s  Lv.%d  (%s pts)" % [predef.title, prlvl, Currency.format(prcost)]
		prbtn.disabled = not FortuneMill.prestige.can_buy(id)
	# 成就
	if _ach_count_label != null:
		_ach_count_label.text = "已解锁: %d / %d" % [FortuneMill.achievements.count(), FortuneMill.achievements.total()]


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


## --- 内部类:(无;转盘/投掷态机随墙面重构迁入 darts_room_view.gd,hub 不再内联真交互) ---
