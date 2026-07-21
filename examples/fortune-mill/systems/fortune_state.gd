extends Node
## FortuneMill —— 状态支柱 autoload(唯一挂树的游戏级节点)。装配纯数据层、
## 暴露命令方法、接线存档与 bus。经济逻辑在 darts(DartsRoom)里,本节点只转发 + 广播脏标记。
## autoload 顺序必须在 CoreKit 之后(依赖 CoreKit.saves/.bus/.log/.ticker)。

const SAVE_SLOT := "fortune"
const UPGRADES_DIR := "res://examples/fortune-mill/data/dart_upgrades"
const OFFLINE_CAP_SECONDS := 28800.0   # 封顶 8 小时(spec §5.7)
const TICK_EVERY_N := 15               # ~4Hz @60fps 的自动产出结算
const AUTOSAVE_EVERY_N := 300          # ~5s @60fps 的周期自动存

var currency: Currency
var modifiers: KitModifiers
var registry: KitDataRegistry
var darts: DartsRoom

## 最近一次离线结算数据包(空=无);UI 首帧拉取展示回归横幅。
var offline_report: Dictionary = {}

var _tick_handle: int = -1
var _autosave_handle: int = -1
var _last_tick_ms: int = 0


func _ready() -> void:
	currency = Currency.new(1.0)          # 开局 $1 gold(spec §5.1)
	modifiers = KitModifiers.new()
	registry = KitDataRegistry.new()
	var n := registry.load_dir(&"dart_upgrade", UPGRADES_DIR)
	darts = DartsRoom.new(currency, modifiers, registry)
	if CoreKit.saves.has_slot(SAVE_SLOT):
		load_game()                       # 内部做离线结算
	_last_tick_ms = Time.get_ticks_msec()
	_tick_handle = CoreKit.ticker.every_n(_on_tick, TICK_EVERY_N)
	_autosave_handle = CoreKit.ticker.every_n(save_game, AUTOSAVE_EVERY_N)
	CoreKit.log.info("[Fortune] ready: %d upgrades, gold=%s" % [n, Currency.format(currency.get_amount())])


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


## --- 离线结算(load 时按墙钟差补收益;可注入 now 供 smoke 确定性验证) ---

func settle_offline(last_seen: float, now: float) -> Dictionary:
	var rep := KitOffline.settle(last_seen, now, darts.auto_gold_rate(), OFFLINE_CAP_SECONDS)
	offline_report = rep
	if rep.earned > 0.0:
		currency.add(rep.earned)
		CoreKit.bus.publish("fortune:currency_changed", currency.get_amount())
		CoreKit.bus.publish("fortune:offline_settled", rep)
	return rep


## --- 存档(只存 Dictionary,SaveManager 拒 Object;含 last_seen 时间戳) ---

func to_dict() -> Dictionary:
	return {
		"currency": currency.get_amount(),
		"darts": darts.to_dict(),
		"last_seen": Time.get_unix_time_from_system(),
	}


func from_dict(d: Dictionary) -> void:
	currency.set_amount(float(d.get("currency", 1.0)))
	darts.from_dict(d.get("darts", {}))


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
