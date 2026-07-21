extends Node
## FortuneMill —— 状态支柱 autoload(唯一挂树的游戏级节点)。装配纯数据层、
## 暴露命令方法、接线存档与 bus。经济逻辑在 darts(DartsRoom)里,本节点只转发 + 广播脏标记。
## autoload 顺序必须在 CoreKit 之后(依赖 CoreKit.saves/.bus/.log/.ticker)。

const SAVE_SLOT := "fortune"
const UPGRADES_DIR := "res://examples/fortune-mill/data/dart_upgrades"
const LOTTO_DIR := "res://examples/fortune-mill/data/lotto_cards"
const PACHINKO_DIR := "res://examples/fortune-mill/data/pachinko_balls"
const SUSHI_RECIPES_DIR := "res://examples/fortune-mill/data/sushi_recipes"
const SUSHI_UPGRADES_DIR := "res://examples/fortune-mill/data/sushi_upgrades"
const OFFLINE_CAP_SECONDS := 28800.0   # 封顶 8 小时(spec §5.7)
const TICK_EVERY_N := 15               # ~4Hz @60fps 的自动产出结算
const AUTOSAVE_EVERY_N := 300          # ~5s @60fps 的周期自动存

var currency: Currency    # gold(飞镖房)
var money: Currency       # money(刮刮乐房);5 货币互相独立不可兑换
var tickets: Currency     # tickets(柏青哥房)
var ribbons: Currency     # ribbons(寿司房)
var modifiers: KitModifiers   # 全房间共享:跨房协同的唯一求值点(global_mul 等)
var registry: KitDataRegistry
var darts: DartsRoom
var lotto: LottoRoom
var pachinko: PachinkoRoom
var sushi: SushiRoom

## 最近一次离线结算数据包(空=无);UI 首帧拉取展示回归横幅。
var offline_report: Dictionary = {}

var _tick_handle: int = -1
var _autosave_handle: int = -1
var _last_tick_ms: int = 0


func _ready() -> void:
	currency = Currency.new(1.0)          # 开局 $1 gold(spec §5.1)
	money = Currency.new(0.0)             # 刮刮乐房从 0 money 起步(免费刮卡)
	tickets = Currency.new(0.0)           # 柏青哥房从 0 tickets 起步(免费落球)
	ribbons = Currency.new(0.0)           # 寿司房从 0 ribbons 起步(基础配方免费制作)
	modifiers = KitModifiers.new()
	registry = KitDataRegistry.new()
	var n := registry.load_dir(&"dart_upgrade", UPGRADES_DIR)
	var nl := registry.load_dir(&"lotto_upgrade", LOTTO_DIR)
	var np := registry.load_dir(&"pachinko_upgrade", PACHINKO_DIR)
	var nr := registry.load_dir(&"sushi_recipe", SUSHI_RECIPES_DIR)
	var ns := registry.load_dir(&"sushi_upgrade", SUSHI_UPGRADES_DIR)
	darts = DartsRoom.new(currency, modifiers, registry)
	lotto = LottoRoom.new(money, modifiers, registry)       # 共享 modifiers → 跨房协同
	pachinko = PachinkoRoom.new(tickets, modifiers, registry)
	sushi = SushiRoom.new(ribbons, modifiers, registry)     # 解锁高级配方 → 往别房注册永久开关
	if CoreKit.saves.has_slot(SAVE_SLOT):
		load_game()                       # 内部做离线结算
	_last_tick_ms = Time.get_ticks_msec()
	_tick_handle = CoreKit.ticker.every_n(_on_tick, TICK_EVERY_N)
	_autosave_handle = CoreKit.ticker.every_n(save_game, AUTOSAVE_EVERY_N)
	CoreKit.log.info("[Fortune] ready: %d dart + %d lotto + %d pachinko + %d recipe + %d sushi upgrades" % [n, nl, np, nr, ns])


## --- ticker 驱动的自动产出(降频 tick,真实 dt 自算) ---

func _on_tick() -> void:
	var now := Time.get_ticks_msec()
	var dt := float(now - _last_tick_ms) / 1000.0
	_last_tick_ms = now
	if dt > 0.0:
		tick(dt)


func tick(dt: float) -> void:
	var g := darts.produce(dt)
	if g > 0.0:
		CoreKit.bus.publish("fortune:currency_changed", currency.get_amount())
	var m := lotto.produce(dt)
	if m > 0.0:
		CoreKit.bus.publish("fortune:money_changed", money.get_amount())
	pachinko.update(dt)   # DICE 倒计时(无产出也要推进过期)
	var t := pachinko.produce(dt)
	if t > 0.0:
		CoreKit.bus.publish("fortune:tickets_changed", tickets.get_amount())
	var sc := sushi.update(dt)   # 手动制作计时完成产出(进行中的 craft)
	var sp := sushi.produce(dt)  # 自动厨师连续产出
	if sc > 0.0 or sp > 0.0:
		CoreKit.bus.publish("fortune:ribbons_changed", ribbons.get_amount())


## --- 命令(表现层唯一入口) ---

func do_throw() -> Dictionary:
	var r := darts.throw()
	CoreKit.bus.publish("fortune:currency_changed", currency.get_amount())
	return r


func buy_dart_upgrade(id: StringName) -> bool:
	if darts.buy_upgrade(id):
		CoreKit.bus.publish("fortune:upgrade_purchased", String(id))
		CoreKit.bus.publish("fortune:currency_changed", currency.get_amount())
		return true
	return false


func bribe_guard() -> bool:
	if darts.bribe():
		CoreKit.bus.publish("fortune:room_cleared", "darts")
		save_game()
		return true
	return false


func can_bribe() -> bool:
	return darts.can_bribe()


## --- 刮刮乐房命令 ---

func do_scratch() -> Dictionary:
	var r := lotto.scratch()
	CoreKit.bus.publish("fortune:money_changed", money.get_amount())
	if r.get("jackpot", false):
		CoreKit.bus.publish("fortune:jackpot_hit", lotto.jackpot_count())
		# JACKPOT 抬 global_mul → 飞镖显示产率也变,刷飞镖 HUD
		CoreKit.bus.publish("fortune:currency_changed", currency.get_amount())
	return r


func buy_lotto_upgrade(id: StringName) -> bool:
	if lotto.buy_upgrade(id):
		CoreKit.bus.publish("fortune:upgrade_purchased", String(id))
		CoreKit.bus.publish("fortune:money_changed", money.get_amount())
		return true
	return false


func bribe_gorgon() -> bool:
	if lotto.bribe():
		CoreKit.bus.publish("fortune:room_cleared", "lotto")
		save_game()
		return true
	return false


func can_bribe_gorgon() -> bool:
	return lotto.can_bribe()


## --- 柏青哥房命令 ---

func drop_ball() -> Dictionary:
	var r := pachinko.drop_ball()
	CoreKit.bus.publish("fortune:tickets_changed", tickets.get_amount())
	return r


## 物理球落进槽 slot 的回调(手动落球走真物理表现层时用;走权威 award_slot 入账)。
func pachinko_land(slot: int) -> float:
	var t := pachinko.award_slot(slot)
	CoreKit.bus.publish("fortune:tickets_changed", tickets.get_amount())
	return t


func roll_dice() -> bool:
	if pachinko.roll_dice():
		CoreKit.bus.publish("fortune:dice_rolled", pachinko.dice_seconds_left())
		# DICE 抬 global_mul → 各房显示产率都变,刷全 HUD
		CoreKit.bus.publish("fortune:currency_changed", currency.get_amount())
		CoreKit.bus.publish("fortune:money_changed", money.get_amount())
		return true
	return false


func can_roll_dice() -> bool:
	return pachinko.dice_ready()


func buy_pachinko_upgrade(id: StringName) -> bool:
	if pachinko.buy_upgrade(id):
		CoreKit.bus.publish("fortune:upgrade_purchased", String(id))
		CoreKit.bus.publish("fortune:tickets_changed", tickets.get_amount())
		return true
	return false


func bribe_rimmington() -> bool:
	if pachinko.bribe():
		CoreKit.bus.publish("fortune:room_cleared", "pachinko")
		save_game()
		return true
	return false


func can_bribe_rimmington() -> bool:
	return pachinko.can_bribe()


## --- 寿司房命令 ---

func select_sushi_recipe(id: StringName) -> bool:
	return sushi.select_recipe(id)


## 解锁配方(带 switch 的高级配方 → 注册跨房永久开关,改别房规则)。
func unlock_sushi_recipe(id: StringName) -> bool:
	if sushi.unlock_recipe(id):
		CoreKit.bus.publish("fortune:recipe_unlocked", String(id))
		CoreKit.bus.publish("fortune:ribbons_changed", ribbons.get_amount())
		# 规则开关可能改别房产率(如飞镖投速),刷全 HUD
		CoreKit.bus.publish("fortune:currency_changed", currency.get_amount())
		return true
	return false


func restock_sushi(id: StringName, amount: int) -> int:
	return sushi.restock(id, amount)


func restock_sushi_all(amount: int) -> void:
	sushi.restock_all(amount)


## 开始制作选中配方(消耗食材,起制作时长计时;完成由 tick 内 sushi.update 结算)。
func start_craft() -> bool:
	return sushi.start_craft()


func buy_sushi_upgrade(id: StringName) -> bool:
	if sushi.buy_upgrade(id):
		CoreKit.bus.publish("fortune:upgrade_purchased", String(id))
		CoreKit.bus.publish("fortune:ribbons_changed", ribbons.get_amount())
		return true
	return false


func bribe_hivemind() -> bool:
	if sushi.bribe():
		CoreKit.bus.publish("fortune:room_cleared", "sushi")
		save_game()
		return true
	return false


func can_bribe_hivemind() -> bool:
	return sushi.can_bribe()


## --- 离线结算(load 时按墙钟差补各房收益;可注入 now 供 smoke 确定性验证) ---
## 5 货币独立 → 每房各用自身产率单独结算。返回 per-room 数据包。

func settle_offline(last_seen: float, now: float) -> Dictionary:
	var rep_g := KitOffline.settle(last_seen, now, darts.auto_gold_rate(), OFFLINE_CAP_SECONDS)
	var rep_m := KitOffline.settle(last_seen, now, lotto.auto_money_rate(), OFFLINE_CAP_SECONDS)
	var rep_t := KitOffline.settle(last_seen, now, pachinko.auto_ticket_rate(), OFFLINE_CAP_SECONDS)
	var rep_r := KitOffline.settle(last_seen, now, sushi.auto_ribbon_rate(), OFFLINE_CAP_SECONDS)
	offline_report = {"darts": rep_g, "lotto": rep_m, "pachinko": rep_t, "sushi": rep_r}
	if rep_g.earned > 0.0:
		currency.add(rep_g.earned)
		CoreKit.bus.publish("fortune:currency_changed", currency.get_amount())
	if rep_m.earned > 0.0:
		money.add(rep_m.earned)
		CoreKit.bus.publish("fortune:money_changed", money.get_amount())
	if rep_t.earned > 0.0:
		tickets.add(rep_t.earned)
		CoreKit.bus.publish("fortune:tickets_changed", tickets.get_amount())
	if rep_r.earned > 0.0:
		ribbons.add(rep_r.earned)
		CoreKit.bus.publish("fortune:ribbons_changed", ribbons.get_amount())
	if rep_g.earned > 0.0 or rep_m.earned > 0.0 or rep_t.earned > 0.0 or rep_r.earned > 0.0:
		CoreKit.bus.publish("fortune:offline_settled", offline_report)
	return offline_report


## --- 存档(只存 Dictionary,SaveManager 拒 Object;含 last_seen 时间戳) ---

func to_dict() -> Dictionary:
	return {
		"currency": currency.get_amount(),
		"money": money.get_amount(),
		"tickets": tickets.get_amount(),
		"ribbons": ribbons.get_amount(),
		"darts": darts.to_dict(),
		"lotto": lotto.to_dict(),
		"pachinko": pachinko.to_dict(),
		"sushi": sushi.to_dict(),
		"last_seen": Time.get_unix_time_from_system(),
	}


func from_dict(d: Dictionary) -> void:
	currency.set_amount(float(d.get("currency", 1.0)))
	money.set_amount(float(d.get("money", 0.0)))
	tickets.set_amount(float(d.get("tickets", 0.0)))
	ribbons.set_amount(float(d.get("ribbons", 0.0)))
	darts.from_dict(d.get("darts", {}))
	lotto.from_dict(d.get("lotto", {}))
	pachinko.from_dict(d.get("pachinko", {}))
	sushi.from_dict(d.get("sushi", {}))


func save_game() -> void:
	CoreKit.saves.save(SAVE_SLOT, to_dict())


func load_game() -> void:
	var d := CoreKit.saves.load(SAVE_SLOT)
	from_dict(d)
	settle_offline(float(d.get("last_seen", 0.0)), Time.get_unix_time_from_system())


## 窗口关闭时存一次(退出存)。只挂 WM_CLOSE_REQUEST——不挂 EXIT_TREE,
## 避免 headless smoke 退出时重建被清理的存档位、污染下次运行。周期自动存兜底菜单退出。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
