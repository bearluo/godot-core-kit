extends Node2D
## 农场游戏世界根(P0 视觉切片)。构建并接线农田网格 + 玩家 + 高亮 + HUD,复用 core-kit 的
## 数据(KitDataRegistry/KitInventory)与门面(clock/bus/layers);工具作用于玩家面前那一格。
##
## 逻辑与表现分离:FarmGrid 管状态、FarmGridView 画占位美术;世界这里只做"接线 + 输入派发"。
## 操作:WASD 走动;J(farm_use)对面前格 耕→种→浇→收;N(farm_next_day)推进一天让作物生长。

const FarmGrid = preload("res://examples/farm-sim/farm_grid.gd")
const FarmGridView = preload("res://examples/farm-sim/farm_grid_view.gd")
const PlayerScript = preload("res://examples/farm-sim/player.gd")
const TargetHighlight = preload("res://examples/farm-sim/target_highlight.gd")
const HudScript = preload("res://examples/farm-sim/hud.gd")
const ShopScript = preload("res://examples/farm-sim/shop.gd")
const InventoryPanel = preload("res://examples/farm-sim/inventory_panel.gd")
const ShopPanel = preload("res://examples/farm-sim/shop_panel.gd")
const PauseMenu = preload("res://examples/farm-sim/pause_menu.gd")
const WeatherSystem = preload("res://examples/farm-sim/weather_system.gd")
const WeatherView = preload("res://examples/farm-sim/weather_view.gd")
const QuestLogScript = preload("res://examples/farm-sim/quest_log.gd")
const AchievementTracker = preload("res://examples/farm-sim/achievement_tracker.gd")
const LogPanel = preload("res://examples/farm-sim/log_panel.gd")
const SettingsPanel = preload("res://examples/farm-sim/settings_panel.gd")
const I18nStrings = preload("res://examples/farm-sim/i18n_strings.gd")
const AudioBank = preload("res://examples/farm-sim/audio_bank.gd")

const GRID_W := 10
const GRID_H := 8
const ENERGY_MAX := 100
const ACTION_COST := 8   ## 每个工具动作耗的体力
const WATER_UPGRADE_COST := 200   ## 水壶升级(浇水 3×3)售价

var _registry
var _bag
var _grid
var _view
var _player
var _shop
var _weather                                   ## WeatherSystem(每天掷晴/雨,广播 weather:changed)
var _quest_log                                 ## QuestLog(任务进度,随存档)
var _tracker                                   ## AchievementTracker(账号级成就,存 settings)
var _selected_crop: StringName = &"turnip"   ## 当前选中种子(cycle_seed 切换)
var _crop_ids: Array = []                      ## 可选作物 id(字母序)
var _energy := ENERGY_MAX                      ## 当前体力(工具动作扣,睡觉回满)
var _water_radius := 0                          ## 浇水半径(0=单格;水壶升级后 1=3×3),随存档
var _ui_stack                                  ## KitUiStack(背包/商店/菜单)
var _active_ui := ""                            ## 当前打开的面板名(""=无)


func energy() -> int:
	return _energy


func energy_max() -> int:
	return ENERGY_MAX


func _ready() -> void:
	CoreKit.log.info("[World] 农场世界启动")
	# i18n:装载中/英内存翻译;默认中文(尊重已持久化的 zh/en 选择),locale 变化时重建活动面板
	I18nStrings.install()
	if not ["zh", "en"].has(CoreKit.i18n.get_locale()):
		CoreKit.i18n.set_locale("zh")
	CoreKit.i18n.locale_changed.connect(_on_locale_changed)
	# 数据 + 背包(起始给点种子)
	_registry = KitDataRegistry.new()
	_registry.load_dir(&"crop", "res://examples/farm-sim/data/crops")
	_registry.load_dir(&"item", "res://examples/farm-sim/data/items")
	_registry.load_dir(&"quest", "res://examples/farm-sim/data/quests")
	_registry.load_dir(&"achievement", "res://examples/farm-sim/data/achievements")
	_bag = KitInventory.new(20)
	_bag.add(&"turnip_seed", 10, {}, 99)
	_bag.add(&"parsnip_seed", 10, {}, 99)
	_bag.add(&"potato_seed", 10, {}, 99)
	_bag.add(&"pumpkin_seed", 5, {}, 99)
	_crop_ids = _registry.ids(&"crop", true)   # 可选作物字母序:[parsnip, potato, pumpkin, turnip]

	# 时钟:每季 7 天(默认 28),让四季在一局内可达 → 季节轮替、季节限定作物有意义
	CoreKit.clock.configure({"days_per_season": 7})

	# 农田网格 + 占位渲染
	_grid = FarmGrid.new()
	_grid.setup(_registry, _bag, GRID_W, GRID_H)
	_view = FarmGridView.new()
	_view.bind(_grid)
	add_child(_view)

	# 玩家(置于网格中央)+ 面前格高亮
	_player = PlayerScript.new()
	_player.setup(_grid)
	_player.position = _grid.cell_to_world(Vector2i(GRID_W / 2, GRID_H / 2)) + Vector2(16, 16)
	add_child(_player)
	var hl = TargetHighlight.new()
	hl.bind(_player, _grid)
	add_child(hl)

	# 钱包(复用 shop.gd,P1 接买卖 UI)
	_shop = ShopScript.new()
	_shop.bind(_registry, _bag, 500)
	add_child(_shop)

	# 任务日志 + 成就追踪(复用 dogfood 组件):须在买卖/天气/推日事件前入树(其 _ready 订阅这些事件)。
	# 任务=每档进度(随存档 to_dict/from_dict);成就=账号级里程碑(存 CoreKit.settings,不进存档)。
	_quest_log = QuestLogScript.new()
	_quest_log.name = "QuestLog"
	_quest_log.bind(_registry)
	add_child(_quest_log)
	_tracker = AchievementTracker.new()
	_tracker.name = "Achievements"
	_tracker.bind(_registry)
	add_child(_tracker)

	# 天气系统(复用 weather_system.gd):每天订阅 clock:day_changed,掷晴/雨,广播 weather:changed。
	# 须在任何 advance_day 之前入树(其 _ready 订阅时钟)。
	_weather = WeatherSystem.new()
	_weather.name = "Weather"
	add_child(_weather)
	# 雨天视觉覆盖:挂 layer=1 的 CanvasLayer(农田之上、HUD 之下),按屏幕坐标画雨幕
	var weather_layer := CanvasLayer.new()
	weather_layer.layer = 1
	add_child(weather_layer)
	var weather_view = WeatherView.new()
	weather_view.bind(_weather)
	weather_layer.add_child(weather_view)

	# HUD 挂 CoreKit.layers 的 hud 层(先 clear 防编辑器内重入重复挂)
	CoreKit.layers.clear("hud")
	var hud = HudScript.new()
	hud.bind(CoreKit.clock, _shop, self)   # self 作体力源(energy()/energy_max())
	CoreKit.layers.mount(hud, "hud")

	# UI 栈(背包/商店/菜单)挂 window 层;关掉栈自带返回键,开关统一由 world 管
	CoreKit.layers.clear("window")
	_ui_stack = KitUiStack.new()
	_ui_stack.cancel_action = &""
	CoreKit.layers.mount(_ui_stack, "window")

	# 逐日推进走事件链 clock:day_changed →(weather 掷天气)→ weather:changed → 本世界长作物。
	# 订阅天气(而非直接订时钟),保证"先定当天天气、再据加成生长"的顺序(与 dogfood crop.gd 同构)。
	CoreKit.bus.subscribe(_weather.EV_CHANGED, _on_weather)
	# 买卖音效:订阅商店事件点播(shop_panel 触发交易 → 事件 → 这里出声)
	CoreKit.bus.subscribe(_shop.EV_BOUGHT, func(_p): _sfx(&"buy"))
	CoreKit.bus.subscribe(_shop.EV_SOLD, func(_p): _sfx(&"sell"))
	CoreKit.audio.play_music(AudioBank.bgm(), 1.0)   # 程序化 BGM 循环
	CoreKit.log.info("[World] 就绪:WASD 走动,J 用工具(耕/种/浇/收),N 进下一天")

	if OS.get_environment("FARM_SMOKE") == "1":
		call_deferred("_run_smoke")   # headless 端到端自测(env 门控,不影响正常运行/F5)


## headless 自测:把玩家摆到朝向固定格,走真实 _use_tool 派发路径 耕→种→浇→(逐日到熟)→收,
## 并断言逐日推进经 bus→_on_day→grid.advance_day 生效。gated by FARM_SMOKE=1。
func _run_smoke() -> void:
	var c := Vector2i(1, 1)
	_player.position = _grid.cell_to_world(c + Vector2i(-1, 0)) + Vector2(16, 16)
	_player.facing = Vector2i(1, 0)
	var ok = _player.facing_cell() == c   # _player 无类型,不用 :=
	# 选种切换:作物≥3,循环一整圈回到起点
	var seed_start := _selected_crop
	for i in range(_crop_ids.size()):
		_cycle_seed()
	ok = ok and _crop_ids.size() >= 4 and _selected_crop == seed_start
	_use_tool()   # 空 → 耕
	ok = ok and _grid.tile_state(c) == FarmGrid.State.TILLED
	_use_tool()   # 已耕 → 种
	ok = ok and _grid.has_crop(c)
	_use_tool()   # 已种(已耕)→ 浇
	ok = ok and _grid.tile_state(c) == FarmGrid.State.WATERED
	var def = _registry.get_def(&"crop", _selected_crop)
	for i in range(int(def.grow_days)):
		CoreKit.clock.advance_day()   # 经 bus → _on_day → grid.advance_day
	ok = ok and _grid.crop_mature(c)
	_use_tool()   # 成熟 → 收
	ok = ok and not _grid.has_crop(c) and _bag.count(def.harvest_item) >= int(def.harvest_amount)
	ok = ok and _energy == ENERGY_MAX - 4 * ACTION_COST   # 耕/种/浇/收 4 次各扣体力
	_sleep()
	ok = ok and _energy == ENERGY_MAX                      # 睡觉回满
	# 工具升级 + 区域浇水:给够金币买升级 → 半径 1(幂等);耕出以 (5,5) 为心的 3×3,_water_area 浇 9 格
	_shop.gold = 1000
	ok = ok and buy_water_upgrade() and _water_radius == 1
	ok = ok and not buy_water_upgrade()                     # 已升级再买失败(幂等)
	var center := Vector2i(5, 5)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			_grid.till(center + Vector2i(dx, dy))
	_water_area(center)
	var watered := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if _grid.tile_state(center + Vector2i(dx, dy)) == FarmGrid.State.WATERED:
				watered += 1
	ok = ok and watered == 9                                # 3×3 全浇
	# 任务/成就:买种子解锁 first_purchase 成就(账号级);卖 3 白萝卜完成 first_income+turnip_tycoon 两任务
	_shop.buy(&"turnip_seed", 1)
	ok = ok and _tracker.unlocked_count() >= 1              # shop:bought → first_purchase 解锁
	_shop.sell(&"turnip", _bag.count(&"turnip"))            # 卖光 turnip → shop:sold 推进任务
	ok = ok and _quest_log.done_count() >= 2                # first_income(赚100)+turnip_tycoon(卖3)
	var quests_done = _quest_log.done_count()   # _quest_log 无类型,不用 :=
	# 存读档往返:存 → 改(金币/体力/地块/水壶半径/任务)→ 读 → 全量复原
	var gold_at_save = _shop.gold   # _shop 无类型,不用 :=
	var pos_at_save = _player.global_position   # _player 无类型,不用 :=
	save_game()
	_grid.till(Vector2i(7, 7)); _shop.gold = 123; _energy = 10; _water_radius = 0
	_player.global_position = pos_at_save + Vector2(200, 200)   # 移开小人,验证读档拉回
	_quest_log.forget_all()                                 # 清任务进度,验证读档复原
	var loaded := load_game()
	ok = ok and loaded and _shop.gold == gold_at_save and _energy == ENERGY_MAX
	ok = ok and _player.global_position == pos_at_save      # 读档复原小人位置
	ok = ok and _water_radius == 1                          # 读档复原水壶升级
	ok = ok and _quest_log.done_count() == quests_done      # 读档复原任务进度
	ok = ok and _grid.tile_state(Vector2i(7, 7)) == FarmGrid.State.EMPTY   # 读档回滚了 till
	CoreKit.saves.delete_slot("farm")                       # 清存档槽,保证可重复跑
	# i18n:切语言后同 key 出不同文案(不假设起始语言)
	var loc0 = CoreKit.i18n.get_locale()
	var save0 = CoreKit.i18n.t("MENU_SAVE")
	cycle_locale()
	ok = ok and CoreKit.i18n.get_locale() != loc0 and CoreKit.i18n.t("MENU_SAVE") != save0
	cycle_locale()
	ok = ok and CoreKit.i18n.get_locale() == loc0           # 切回起始语言
	# 音频:程序化流非空;音量写读往返
	ok = ok and AudioBank.sfx(&"till") != null and AudioBank.bgm() != null
	CoreKit.audio.set_volume("music", 0.5)
	ok = ok and absf(CoreKit.audio.get_volume("music") - 0.5) < 0.01
	# UI 面板冒烟:五个面板各开各关一次,验证 build/push/pop 不报错(含 settings 的 KitRebindList)
	for uiname in ["inventory", "shop", "menu", "log", "settings"]:
		_open_ui(uiname)
		ok = ok and _active_ui == uiname and _ui_stack.depth() == 1
		_close_ui()
		ok = ok and _active_ui == "" and _ui_stack.is_empty()
	CoreKit.log.info("[World][SMOKE] %s(体力回满=%s,存读档=%s,任务=%d/%d,成就=%d/%d,语言=%s)" % [
		"PASS" if ok else "FAIL", _energy == ENERGY_MAX, loaded,
		_quest_log.done_count(), _quest_log.quest_count(),
		_tracker.unlocked_count(), _tracker.total(), CoreKit.i18n.get_locale()])
	_tracker.reset_all()                                    # 清 settings 成就分区,保证可重复跑
	CoreKit.settings.erase_section("locale")                # 复位语言/音量/键位持久化,保证可重复跑
	CoreKit.settings.erase_section("audio")
	CoreKit.settings.erase_section("input")
	get_tree().quit(0 if ok else 1)


func _exit_tree() -> void:
	CoreKit.bus.unsubscribe_all(self)


func _unhandled_input(event: InputEvent) -> void:
	# 菜单开关(任何时候可用)
	if event.is_action_pressed("toggle_inventory"):
		_toggle_ui("inventory"); return
	if event.is_action_pressed("toggle_shop"):
		_toggle_ui("shop"); return
	if event.is_action_pressed("toggle_menu"):
		_toggle_ui("menu"); return
	if event.is_action_pressed("toggle_log"):
		_toggle_ui("log"); return
	# 菜单开着:把 导航/确认 路由给活动面板,其余吞掉(不误触农场操作)
	if _active_ui != "":
		for a in ["move_up", "move_down", "farm_use"]:
			if event.is_action_pressed(a):
				var top = _ui_stack.top()
				if top != null and top.has_method("handle_action"):
					top.handle_action(a)
				return
		return
	# 无菜单:正常农场操作
	if event.is_action_pressed("farm_use"):
		_use_tool()
	elif event.is_action_pressed("farm_next_day"):
		_sleep()
	elif event.is_action_pressed("cycle_seed"):
		_cycle_seed()


## 切换面板:同名再按=关;开着别的=先关再开。
func _toggle_ui(name: String) -> void:
	if _active_ui == name:
		_close_ui()
	else:
		_close_ui()
		_open_ui(name)


func _open_ui(name: String) -> void:
	var panel
	match name:
		"inventory":
			panel = InventoryPanel.new()
			panel.bind(_bag, _registry)
		"shop":
			panel = ShopPanel.new()
			panel.bind(_shop, _registry, _bag, self)
		"menu":
			panel = PauseMenu.new()
			panel.bind(self)
		"log":
			panel = LogPanel.new()
			panel.bind(_quest_log, _tracker)
		"settings":
			panel = SettingsPanel.new()
			panel.bind(self)
		_:
			return
	_ui_stack.push(panel, {"hide_below": false, "dim": Color(0, 0, 0, 0.45)})  # 模态浮层:压暗背景、挡输入
	_active_ui = name
	_player.input_locked = true


func _close_ui() -> void:
	if _active_ui == "":
		return
	_ui_stack.pop()
	_active_ui = ""
	_player.input_locked = false


## 供菜单"继续"调用。
func close_menu() -> void:
	_close_ui()


## 切换中/英(设置面板 J 调用);set_locale 会广播 locale_changed → _rebuild_active_ui。
func cycle_locale() -> void:
	CoreKit.i18n.set_locale("en" if CoreKit.i18n.get_locale() == "zh" else "zh")


## 暂停菜单"设置"入口:关菜单再开设置(避免栈叠)。
func open_settings() -> void:
	_close_ui()
	_open_ui("settings")


func _on_locale_changed(_loc: String) -> void:
	call_deferred("_rebuild_active_ui")   # 延迟重建,避开在旧面板 handle_action 内 free 它


## 语言变化后重建当前活动面板,使其标签用新语言(HUD 每帧读 t() 天然实时)。
func _rebuild_active_ui() -> void:
	if _active_ui == "":
		return
	var name := _active_ui
	_close_ui()
	_open_ui(name)


func _sfx(name: StringName) -> void:
	CoreKit.audio.play_sfx(AudioBank.sfx(name))


## 存档:地块 + 背包 + 金币 + 时钟 + 体力 全量存进 CoreKit.saves。
func save_game() -> void:
	CoreKit.saves.save("farm", {
		"grid": _grid.to_dict(), "bag": _bag.to_dict(),
		"gold": _shop.gold, "clock": CoreKit.clock.to_dict(), "energy": _energy,
		"water_radius": _water_radius, "quests": _quest_log.to_dict(),
		"player": {
			"x": _player.global_position.x, "y": _player.global_position.y,
			"fx": _player.facing.x, "fy": _player.facing.y}})
	CoreKit.log.info("[World] 已存档")


## 读档:全量还原(无存档返回 false)。
func load_game() -> bool:
	var d = CoreKit.saves.load("farm")
	if d == null or (d is Dictionary and d.is_empty()):
		CoreKit.log.info("[World] 无存档")
		return false
	_grid.from_dict(d["grid"])
	_bag.from_dict(d["bag"])
	_shop.gold = int(d["gold"])
	CoreKit.clock.from_dict(d["clock"])
	_energy = int(d["energy"])
	_water_radius = int(d.get("water_radius", 0))
	_quest_log.from_dict(d.get("quests", {}))
	var pp: Dictionary = d.get("player", {})   # 小人位置 + 朝向(旧存档无此键则不动)
	if pp.has("x"):
		_player.global_position = Vector2(float(pp["x"]), float(pp["y"]))
		_player.facing = Vector2i(int(pp.get("fx", _player.facing.x)), int(pp.get("fy", _player.facing.y)))
		_player.queue_redraw()
	_view.queue_redraw()
	CoreKit.log.info("[World] 已读档")
	return true


func water_radius() -> int:
	return _water_radius


func water_upgraded() -> bool:
	return _water_radius > 0


## 买水壶升级(3×3 浇水):钱够且未升级 → 扣钱、半径置 1。已升级或钱不足返回 false。
func buy_water_upgrade() -> bool:
	if _water_radius > 0 or _shop.gold < WATER_UPGRADE_COST:
		return false
	_shop.gold -= WATER_UPGRADE_COST
	_water_radius = 1
	CoreKit.log.info("[World] 水壶升级:浇水范围 3×3")
	return true


## 以 center 为心浇 (2r+1)² 范围;FarmGrid.water 只对 TILLED 生效,天然跳过非法格。返回是否有格被浇。
func _water_area(center: Vector2i) -> bool:
	var any := false
	for dy in range(-_water_radius, _water_radius + 1):
		for dx in range(-_water_radius, _water_radius + 1):
			var cc := center + Vector2i(dx, dy)
			if _grid.cell_valid(cc) and _grid.water(cc):
				any = true
	return any


## 对玩家面前那一格用工具:按状态派发 耕→种→浇→收。成功一次扣体力,精疲则自动睡。
func _use_tool() -> void:
	var c: Vector2i = _player.facing_cell()
	if not _grid.cell_valid(c):
		return
	if _energy <= 0:
		CoreKit.log.info("[World] 精疲力尽,按 N 睡觉")
		return
	var did := false
	var sfx_name: StringName = &""
	if _grid.has_crop(c):
		if _grid.crop_mature(c):
			did = _grid.harvest(c)
			if did:
				CoreKit.log.info("[World] 收获 @ %s" % c)
				sfx_name = &"harvest"
		else:
			did = _water_area(c)
			if did:
				CoreKit.log.info("[World] 浇水 @ %s" % c)
				sfx_name = &"water"
	elif _grid.tile_state(c) == FarmGrid.State.EMPTY:
		did = _grid.till(c)
		if did:
			CoreKit.log.info("[World] 耕地 @ %s" % c)
			sfx_name = &"till"
	else:
		var season := StringName(CoreKit.clock.season_name())
		did = _grid.plant(c, _selected_crop, season)
		if did:
			CoreKit.log.info("[World] 播种 %s @ %s" % [_selected_crop, c])
			sfx_name = &"plant"
		elif not _grid.crop_plantable(_selected_crop, season):
			CoreKit.log.info("[World] %s 不在当季(%s)可种" % [selected_crop_name(), CoreKit.clock.season_name()])
		else:
			did = _water_area(c)
			if did:
				CoreKit.log.info("[World] 浇水 @ %s" % c)
				sfx_name = &"water"
	if did:
		if sfx_name != &"":
			_sfx(sfx_name)
		_energy = maxi(0, _energy - ACTION_COST)
		_view.queue_redraw()
		if _energy == 0:
			CoreKit.log.info("[World] 累倒了……")
			_sleep()


## 循环切换选中的种子(cycle_seed)。
func _cycle_seed() -> void:
	if _crop_ids.is_empty():
		return
	var i := _crop_ids.find(_selected_crop)
	_selected_crop = _crop_ids[(i + 1) % _crop_ids.size()]
	CoreKit.log.info("[World] 选中种子:%s" % selected_crop_name())


## 当前选中种子的展示名(供 HUD;经 i18n 本地化,缺 key 回退 .tres 原文)。
func selected_crop_name() -> String:
	return I18nStrings.crop_name(_registry, _selected_crop)


## 当前选中种子在当季能否种(供 HUD 标注 [非当季])。
func selected_crop_plantable() -> bool:
	return _grid.crop_plantable(_selected_crop, StringName(CoreKit.clock.season_name()))


## 睡觉:推进一天(作物生长)+ 体力回满。
func _sleep() -> void:
	CoreKit.clock.advance_day()
	_energy = ENERGY_MAX
	_sfx(&"day")
	CoreKit.log.info("[World] 睡了一觉,体力回满")


## weather:changed(嵌套在 clock:day_changed 内广播)→ 据当天生长加成长作物。
func _on_weather(payload: Dictionary) -> void:
	var bonus := int(payload.get("growth_bonus", 0))
	_grid.advance_day(bonus)
	_view.queue_redraw()
	if payload.get("kind", &"") == &"rainy":
		_sfx(&"rain")
	if bonus > 0:
		CoreKit.log.info("[World] 雨天,作物加速生长 +%d" % bonus)


## 当前天气展示名(供 HUD;经 i18n 本地化)。
func weather_name() -> String:
	if _weather == null:
		return ""
	var k = _weather.current_kind()   # _weather 无类型,不用 :=
	if k == &"":
		k = &"sunny"
	return CoreKit.i18n.t("WEATHER_" + String(k))
