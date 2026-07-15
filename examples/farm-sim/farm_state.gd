extends Node
## Farm —— 农场游戏的持久状态 autoload(P3 引入)。承载**跨整场景切换保留**的全部状态与持久节点:
## 数据/背包/农田模型/钱包/任务/成就/天气 + HUD + UI 栈 + 全部面板。区域场景(农田/农舍/小镇)变薄,
## 只建 view+player+本地布景,读本单例。clock 本就是 CoreKit autoload,HUD 挂 CoreKit.layers 天然常驻。
##
## 惰性:_ready 什么都不做(demo/kit 测试不触发);农田场景首次 _ready 调 start() 才建全部(幂等)。
## model 与 view 剥离:use_tool_on(cell) 吃传入格(facing 由区域算),grid 变化经 grid_changed 信号通知 view 重绘。

signal grid_changed   ## 农田模型变更(耕种浇收/生长/读档)→ 区域 view 连此重绘

const FarmGrid = preload("res://examples/farm-sim/farm_grid.gd")
const HudScript = preload("res://examples/farm-sim/hud.gd")
const ShopScript = preload("res://examples/farm-sim/shop.gd")
const InventoryPanel = preload("res://examples/farm-sim/inventory_panel.gd")
const ShopPanel = preload("res://examples/farm-sim/shop_panel.gd")
const PauseMenu = preload("res://examples/farm-sim/pause_menu.gd")
const WeatherSystem = preload("res://examples/farm-sim/weather_system.gd")
const QuestLogScript = preload("res://examples/farm-sim/quest_log.gd")
const AchievementTracker = preload("res://examples/farm-sim/achievement_tracker.gd")
const LogPanel = preload("res://examples/farm-sim/log_panel.gd")
const SettingsPanel = preload("res://examples/farm-sim/settings_panel.gd")
const DialoguePanel = preload("res://examples/farm-sim/dialogue_panel.gd")
const I18nStrings = preload("res://examples/farm-sim/i18n_strings.gd")
const AudioBank = preload("res://examples/farm-sim/audio_bank.gd")
const Relationship = preload("res://examples/farm-sim/relationship.gd")

const GRID_W := 10
const GRID_H := 8
const ENERGY_MAX := 100
const ACTION_COST := 8            ## 每个工具动作耗的体力
const WATER_UPGRADE_COST := 200   ## 水壶升级(浇水 3×3)售价

# 区域(P3 多区域):场景路径 + 各区到达落点(世界坐标)。门/切换引用这些常量。
const AREA_FARM := "res://examples/farm-sim/world.tscn"
const AREA_HOUSE := "res://examples/farm-sim/house_area.tscn"
const AREA_TOWN := "res://examples/farm-sim/town_area.tscn"
const HOUSE_ENTRY := Vector2(96, 96)      ## 进农舍落点(农舍返回门右侧,避免立刻回触发)
const TOWN_ENTRY := Vector2(96, 128)      ## 进小镇落点
const FARM_FROM_HOUSE := Vector2(328, 60) ## 从农舍回农田落点(网格右侧外,农田→农舍门左侧)
const FARM_FROM_TOWN := Vector2(140, 264) ## 从小镇回农田落点(网格下方外,农田→小镇门上侧)

var started := false
var registry                       ## KitDataRegistry(crop/item/quest/achievement/npc)
var bag                            ## KitInventory
var grid                           ## FarmGrid(纯逻辑)
var shop                           ## shop.gd(钱包 + 买卖,Farm 子节点)
var weather                        ## WeatherSystem(Farm 子节点)
var quest_log                      ## QuestLog(Farm 子节点)
var tracker                        ## AchievementTracker(Farm 子节点)
var relationships: Dictionary = {} ## {npc_id:int} 好感度(P5)
var unlocked: Dictionary = {}      ## {npc_id:true} 好感解锁已发放(P6)
var current_area := "farm"         ## 当前区域名(各区 _ready 置)
var pending_spawn := Vector2.ZERO  ## 切区目标出生点(切前写,新区读;ZERO=用本区默认出生点)
var pending_facing := Vector2i.ZERO ## 切区目标朝向(跨区读档用;ZERO=不覆盖)

var _selected_crop: StringName = &"turnip"
var _crop_ids: Array = []
var _energy := ENERGY_MAX
var _water_radius := 0
var _ui_stack                      ## KitUiStack
var _active_ui := ""               ## 当前打开面板名(""=无)
var _dialogue_def                  ## 当前对话的 npc_def(open_dialogue 置;供 _open_ui/locale 重建)
var _player                        ## 当前区域的玩家(区域 _ready 经 bind_player 注入;开面板时锁其输入)
var _gifted_today: Dictionary = {} ## {npc_id:true} 当日已收礼(防刷,跨天清)
var _chatted_today: Dictionary = {} ## {npc_id:true} 当日已首聊(+好感一次,跨天清)


## 幂等启动:首次被农田场景调用才建全部持久状态。demo/kit 测试不调 → 不触发。
func start() -> void:
	if started:
		return
	started = true
	# i18n:装载中/英内存翻译;默认中文(尊重已持久化的 zh/en),locale 变化时重建活动面板
	I18nStrings.install()
	if not ["zh", "en"].has(CoreKit.i18n.get_locale()):
		CoreKit.i18n.set_locale("zh")
	CoreKit.i18n.locale_changed.connect(_on_locale_changed)
	# 数据 + 背包(起始给点种子)
	registry = KitDataRegistry.new()
	registry.load_dir(&"crop", "res://examples/farm-sim/data/crops")
	registry.load_dir(&"item", "res://examples/farm-sim/data/items")
	registry.load_dir(&"quest", "res://examples/farm-sim/data/quests")
	registry.load_dir(&"achievement", "res://examples/farm-sim/data/achievements")
	registry.load_dir(&"npc", "res://examples/farm-sim/data/npcs")   # 第 5 类型(P3)
	bag = KitInventory.new(20)
	bag.add(&"turnip_seed", 10, {}, 99)
	bag.add(&"parsnip_seed", 10, {}, 99)
	bag.add(&"potato_seed", 10, {}, 99)
	bag.add(&"pumpkin_seed", 5, {}, 99)
	_crop_ids = registry.ids(&"crop", true)
	CoreKit.clock.configure({"days_per_season": 7})   # 每季 7 天,四季一局内可达
	# 农田模型
	grid = FarmGrid.new()
	grid.setup(registry, bag, GRID_W, GRID_H)
	# 钱包 + 任务 + 成就 + 天气(都作 Farm 子节点常驻;须在买卖/推日/天气事件前入树)
	shop = ShopScript.new(); shop.name = "Shop"; shop.bind(registry, bag, 500); add_child(shop)
	quest_log = QuestLogScript.new(); quest_log.name = "QuestLog"; quest_log.bind(registry); add_child(quest_log)
	tracker = AchievementTracker.new(); tracker.name = "Achievements"; tracker.bind(registry); add_child(tracker)
	weather = WeatherSystem.new(); weather.name = "Weather"; add_child(weather)
	# HUD 挂 CoreKit.layers "hud"(跨场景常驻)
	CoreKit.layers.clear("hud")
	var hud = HudScript.new()
	hud.bind(CoreKit.clock, shop, self)   # self 供 energy/weather_name/selected_crop_* 等
	CoreKit.layers.mount(hud, "hud")
	# UI 栈挂 "window";关掉栈自带返回键,开关统一由 Farm 管
	CoreKit.layers.clear("window")
	_ui_stack = KitUiStack.new(); _ui_stack.cancel_action = &""
	CoreKit.layers.mount(_ui_stack, "window")
	# 事件链 clock:day_changed→weather:changed→生长;买卖音效
	CoreKit.bus.subscribe(weather.EV_CHANGED, _on_weather)
	CoreKit.bus.subscribe(shop.EV_BOUGHT, func(_p): _sfx(&"buy"))
	CoreKit.bus.subscribe(shop.EV_SOLD, func(_p): _sfx(&"sell"))
	CoreKit.bus.subscribe(CoreKit.clock.EV_DAY_CHANGED, _on_new_day)   # 跨天清送礼/聊天防刷
	CoreKit.audio.play_music(AudioBank.bgm(), 1.0)
	CoreKit.log.info("[Farm] 启动:持久状态就绪")


## 区域场景 _ready 注入本区玩家(用于开面板时锁输入)。
func bind_player(player) -> void:
	_player = player


## 当前区域玩家(门/交互判定用;切换间隙可能为旧节点,调用方自行容错)。
func current_player():
	return _player


# --- 区域切换(P3 多区域)---

## 切到目标区:写 pending_spawn(新区 _ready 读)+ change_scene(可带转场)。HUD/UI 栈挂
## CoreKit.layers、Farm 状态在本单例,均不随场景替换丢失,故切区后农田/背包/金币照旧。
func go_to(area_path: String, spawn: Vector2, transition) -> void:
	pending_spawn = spawn
	await CoreKit.scenes.change_scene(area_path, transition)


# --- NPC 出现 + 日程(P3)---

## 按当前 hour,该区此刻在场的 NPC:返回 [{def, cell}]。区域场景据此实例化 NPC 摆到 cell。
func npcs_in_area(area: String, hour: int) -> Array:
	var result: Array = []
	if registry == null:
		return result
	for nid in registry.ids(&"npc"):
		var def = registry.get_def(&"npc", nid)
		if def == null:
			continue
		var slot := _npc_slot(def, hour)
		if slot.is_empty():
			continue
		if String(slot.get("area", "")) == area:
			result.append({"def": def, "cell": Vector2i(int(slot.get("x", 0)), int(slot.get("y", 0)))})
	return result


## 从 schedule 选当前时段项:最后一个 after_hour <= hour 的项(假定 schedule 按 after_hour 升序)。
## 空 schedule → {}。
func _npc_slot(def, hour: int) -> Dictionary:
	var sched: Array = def.schedule
	var chosen: Dictionary = {}
	for item in sched:
		if int(item.get("after_hour", 0)) <= hour:
			chosen = item
	return chosen


# --- 送礼 + 好感度 + 解锁(P5/P6)---

func friendship(npc_id: StringName) -> int:
	return int(relationships.get(npc_id, 0))


func friendship_level(npc_id: StringName) -> int:
	return Relationship.level_of(friendship(npc_id))


## 背包中可送礼的物品(produce 类且持有 >0):[{id, name, count}]。对话面板据此列送礼清单。
func giftable_items() -> Array:
	var result: Array = []
	if registry == null:
		return result
	for iid in registry.ids(&"item"):
		var idef = registry.get_def_or(&"item", iid, null)
		if idef == null or idef.category != &"produce":
			continue
		var c = bag.count(iid)   # bag 无类型,不用 :=
		if c > 0:
			result.append({"id": iid, "name": idef.display_name, "count": c})
	return result


## 当日首聊 +好感(防刷:一天一次)。
func chat_with(npc_id: StringName) -> void:
	if _chatted_today.has(npc_id):
		return
	_chatted_today[npc_id] = true
	relationships[npc_id] = friendship(npc_id) + Relationship.GIFT_NEUTRAL
	CoreKit.bus.publish("npc:friendship_changed",
		{"npc_id": String(npc_id), "points": friendship(npc_id), "level": friendship_level(npc_id)})
	_check_unlock(npc_id)


## 送物品给 NPC:按偏好加减好感,扣背包 1 个,当日对同一 NPC 只接一次礼。返回
## {reaction, delta, unlocked}。reaction:none(无效)/already(当日已送)/loved/liked/neutral/disliked。
func gift_to(npc_id: StringName, item_id: StringName) -> Dictionary:
	var def = registry.get_def_or(&"npc", npc_id, null)
	if def == null or bag.count(item_id) < 1:
		return {"reaction": "none", "delta": 0, "unlocked": false}
	if _gifted_today.has(npc_id):
		return {"reaction": "already", "delta": 0, "unlocked": false}
	_gifted_today[npc_id] = true
	var delta := Relationship.gift_delta(def, item_id)
	bag.remove(item_id, 1)
	relationships[npc_id] = friendship(npc_id) + delta
	CoreKit.bus.publish("npc:gift_given", {"npc_id": String(npc_id), "item": String(item_id), "delta": delta})
	CoreKit.bus.publish("npc:friendship_changed",
		{"npc_id": String(npc_id), "points": friendship(npc_id), "level": friendship_level(npc_id)})
	var did_unlock := _check_unlock(npc_id)
	return {"reaction": Relationship.reaction_of(delta), "delta": delta, "unlocked": did_unlock}


## 好感达 def.unlock_at 且未发放且 unlock_item 非空 → 发物品入背包 + 记 unlocked + 广播 npc:unlocked。
## 幂等(unlocked 记录后不再发)。返回本次是否发放。
func _check_unlock(npc_id: StringName) -> bool:
	var def = registry.get_def_or(&"npc", npc_id, null)
	if def == null or unlocked.has(npc_id):
		return false
	if String(def.unlock_item) == "" or friendship(npc_id) < int(def.unlock_at):
		return false
	bag.add(def.unlock_item, 1, {}, 99)
	unlocked[npc_id] = true
	CoreKit.bus.publish("npc:unlocked", {"npc_id": String(npc_id), "item": String(def.unlock_item)})
	CoreKit.log.info("[Farm] 好感解锁:%s 赠 %s" % [def.display_name, def.unlock_item])
	return true


## 跨天:清送礼/聊天防刷记录。
func _on_new_day(_payload) -> void:
	_gifted_today.clear()
	_chatted_today.clear()


## 区域名 → 场景路径。
func _area_path(area: String) -> String:
	match area:
		"house":
			return AREA_HOUSE
		"town":
			return AREA_TOWN
		_:
			return AREA_FARM


## 淡入淡出转场(农田↔农舍用)。
func fade() -> KitTransition:
	var t := KitTransition.new()
	t.type = KitTransition.Type.FADE
	t.duration = 0.3
	return t


## 滑动转场(农田↔小镇用;dir = KitTransition.Dir.*)。
func slide(dir: int) -> KitTransition:
	var t := KitTransition.new()
	t.type = KitTransition.Type.SLIDE
	t.direction = dir
	t.duration = 0.35
	return t


func _exit_tree() -> void:
	CoreKit.bus.unsubscribe_all(self)


# --- 只读状态(供 HUD/面板/区域)---
func energy() -> int: return _energy
func energy_max() -> int: return ENERGY_MAX
func water_radius() -> int: return _water_radius
func water_upgraded() -> bool: return _water_radius > 0
func is_ui_open() -> bool: return _active_ui != ""


func selected_crop_name() -> String:
	return I18nStrings.crop_name(registry, _selected_crop)


func selected_crop_plantable() -> bool:
	return grid.crop_plantable(_selected_crop, StringName(CoreKit.clock.season_name()))


func weather_name() -> String:
	if weather == null:
		return ""
	var k = weather.current_kind()   # weather 无类型,不用 :=
	if k == &"":
		k = &"sunny"
	return CoreKit.i18n.t("WEATHER_" + String(k))


# --- 玩法动作(区域输入派发调用;model 级,不依赖具体 player 节点)---

## 对给定格用工具:按格状态派发 耕→种→浇→收。成功扣体力 + 播 SFX + 精疲自动睡 + 发 grid_changed。返回是否生效。
func use_tool_on(cell: Vector2i) -> bool:
	if not grid.cell_valid(cell):
		return false
	if _energy <= 0:
		CoreKit.log.info("[Farm] 精疲力尽,睡觉恢复")
		return false
	var did := false
	var sfx_name: StringName = &""
	if grid.has_crop(cell):
		if grid.crop_mature(cell):
			did = grid.harvest(cell)
			if did:
				CoreKit.log.info("[Farm] 收获 @ %s" % cell); sfx_name = &"harvest"
		else:
			did = _water_area(cell)
			if did:
				CoreKit.log.info("[Farm] 浇水 @ %s" % cell); sfx_name = &"water"
	elif grid.tile_state(cell) == FarmGrid.State.EMPTY:
		did = grid.till(cell)
		if did:
			CoreKit.log.info("[Farm] 耕地 @ %s" % cell); sfx_name = &"till"
	else:
		var season := StringName(CoreKit.clock.season_name())
		did = grid.plant(cell, _selected_crop, season)
		if did:
			CoreKit.log.info("[Farm] 播种 %s @ %s" % [_selected_crop, cell]); sfx_name = &"plant"
		elif not grid.crop_plantable(_selected_crop, season):
			CoreKit.log.info("[Farm] %s 不在当季(%s)可种" % [selected_crop_name(), CoreKit.clock.season_name()])
		else:
			did = _water_area(cell)
			if did:
				CoreKit.log.info("[Farm] 浇水 @ %s" % cell); sfx_name = &"water"
	if did:
		if sfx_name != &"":
			_sfx(sfx_name)
		_energy = maxi(0, _energy - ACTION_COST)
		grid_changed.emit()
		if _energy == 0:
			CoreKit.log.info("[Farm] 累倒了……")
			sleep()
	return did


## 以 center 为心浇 (2r+1)² 范围;FarmGrid.water 只对 TILLED 生效,天然跳过非法格。
func _water_area(center: Vector2i) -> bool:
	var any := false
	for dy in range(-_water_radius, _water_radius + 1):
		for dx in range(-_water_radius, _water_radius + 1):
			var cc := center + Vector2i(dx, dy)
			if grid.cell_valid(cc) and grid.water(cc):
				any = true
	return any


## 睡觉:推进一天(经天气链生长)+ 体力回满。
func sleep() -> void:
	CoreKit.clock.advance_day()
	_energy = ENERGY_MAX
	_sfx(&"day")
	CoreKit.log.info("[Farm] 睡了一觉,体力回满")


func cycle_seed() -> void:
	if _crop_ids.is_empty():
		return
	var i := _crop_ids.find(_selected_crop)
	_selected_crop = _crop_ids[(i + 1) % _crop_ids.size()]
	CoreKit.log.info("[Farm] 选中种子:%s" % selected_crop_name())


## 买水壶升级(3×3 浇水):钱够且未升级 → 扣钱、半径置 1。已升级或钱不足返回 false。
func buy_water_upgrade() -> bool:
	if _water_radius > 0 or shop.gold < WATER_UPGRADE_COST:
		return false
	shop.gold -= WATER_UPGRADE_COST
	_water_radius = 1
	CoreKit.log.info("[Farm] 水壶升级:浇水范围 3×3")
	return true


## weather:changed(嵌套在 clock:day_changed 内广播)→ 据当天生长加成长作物。
func _on_weather(payload: Dictionary) -> void:
	var bonus := int(payload.get("growth_bonus", 0))
	grid.advance_day(bonus)
	grid_changed.emit()
	if payload.get("kind", &"") == &"rainy":
		_sfx(&"rain")
	if bonus > 0:
		CoreKit.log.info("[Farm] 雨天,作物加速生长 +%d" % bonus)


func _sfx(name: StringName) -> void:
	CoreKit.audio.play_sfx(AudioBank.sfx(name))


## 切换中/英(设置面板 J 调用)。
func cycle_locale() -> void:
	CoreKit.i18n.set_locale("en" if CoreKit.i18n.get_locale() == "zh" else "zh")


# --- UI(HUD + KitUiStack + 全部面板都归 Farm,挂 CoreKit.layers,跨区域常驻)---

func toggle_ui(name: String) -> void:
	if _active_ui == name:
		_close_ui()
	else:
		_close_ui()
		_open_ui(name)


func _open_ui(name: String) -> void:
	var panel
	match name:
		"inventory":
			panel = InventoryPanel.new(); panel.bind(bag, registry)
		"shop":
			panel = ShopPanel.new(); panel.bind(shop, registry, bag, self)
		"menu":
			panel = PauseMenu.new(); panel.bind(self)
		"log":
			panel = LogPanel.new(); panel.bind(quest_log, tracker)
		"settings":
			panel = SettingsPanel.new(); panel.bind(self)
		"dialogue":
			if _dialogue_def == null:
				return
			panel = DialoguePanel.new(); panel.bind(_dialogue_def, self)
		_:
			return
	_ui_stack.push(panel, {"hide_below": false, "dim": Color(0, 0, 0, 0.45)})
	_active_ui = name
	if _player != null:
		_player.input_locked = true


func _close_ui() -> void:
	if _active_ui == "":
		return
	_ui_stack.pop()
	_active_ui = ""
	if _player != null:
		_player.input_locked = false


func close_menu() -> void:
	_close_ui()


func open_settings() -> void:
	_close_ui()
	_open_ui("settings")


## 打开与 def 的对话面板(区域 _on_use 找到相邻 NPC 时调用)。走 UI 栈、锁玩家;locale 切换经
## _dialogue_def 重建。
func open_dialogue(def) -> void:
	if def == null:
		return
	_close_ui()
	_dialogue_def = def
	_open_ui("dialogue")


## 面板开时,区域把 move_up/down/farm_use 转来,派发给活动面板。
func route_action(action: String) -> void:
	var top = _ui_stack.top()
	if top != null and top.has_method("handle_action"):
		top.handle_action(action)


func _on_locale_changed(_loc: String) -> void:
	call_deferred("_rebuild_active_ui")


func _rebuild_active_ui() -> void:
	if _active_ui == "":
		return
	var name := _active_ui
	_close_ui()
	_open_ui(name)


# --- 存读档(收敛到一处:grid/bag/gold/clock/energy/water/quests/relationships/unlocked/area/player)---

func save_game() -> void:
	var d := {
		"grid": grid.to_dict(), "bag": bag.to_dict(),
		"gold": shop.gold, "clock": CoreKit.clock.to_dict(), "energy": _energy,
		"water_radius": _water_radius, "quests": quest_log.to_dict(),
		"relationships": relationships.duplicate(), "unlocked": unlocked.keys(),
		"area": current_area}
	if _player != null:
		d["player"] = {
			"x": _player.global_position.x, "y": _player.global_position.y,
			"fx": _player.facing.x, "fy": _player.facing.y}
	CoreKit.saves.save("farm", d)
	CoreKit.log.info("[Farm] 已存档")


func load_game() -> bool:
	var d = CoreKit.saves.load("farm")
	if d == null or (d is Dictionary and d.is_empty()):
		CoreKit.log.info("[Farm] 无存档")
		return false
	grid.from_dict(d["grid"])
	bag.from_dict(d["bag"])
	shop.gold = int(d["gold"])
	CoreKit.clock.from_dict(d["clock"])
	_energy = int(d["energy"])
	_water_radius = int(d.get("water_radius", 0))
	quest_log.from_dict(d.get("quests", {}))
	relationships = {}
	var rel: Dictionary = d.get("relationships", {})
	for k in rel:
		relationships[StringName(k)] = int(rel[k])
	unlocked = {}
	for uid in d.get("unlocked", []):
		unlocked[StringName(uid)] = true
	var here := current_area
	var saved_area := str(d.get("area", "farm"))
	var pp: Dictionary = d.get("player", {})
	var target_pos := Vector2.ZERO
	var target_facing := Vector2i(0, 1)
	if pp.has("x"):
		target_pos = Vector2(float(pp["x"]), float(pp["y"]))
		target_facing = Vector2i(int(pp.get("fx", 0)), int(pp.get("fy", 1)))
	current_area = saved_area
	grid_changed.emit()
	if saved_area != here:
		# 跨区读档:延迟一帧(等调用方 _activate 收尾)再关面板 + 切到存档区,玩家落存档点
		call_deferred("_resume_saved_area", saved_area, target_pos, target_facing)
	elif _player != null and pp.has("x"):
		# 同区读档:直接复位当前玩家(Task1 手感不变)
		_player.global_position = target_pos
		_player.facing = target_facing
		_player.queue_redraw()
	CoreKit.log.info("[Farm] 已读档")
	return true


## 跨区读档收尾(deferred):关面板 → 切到存档区,玩家落存档点/朝向。
func _resume_saved_area(area: String, pos: Vector2, facing: Vector2i) -> void:
	_close_ui()
	pending_facing = facing
	go_to(_area_path(area), pos, fade())


## headless 端到端自测(farm 场景 _ready 在 FARM_SMOKE=1 时 call_deferred 调)。用 use_tool_on(cell) 走 model 级
## 派发(不依赖真实 player),覆盖 P0-P2 全链路。打印 [Farm][SMOKE] PASS。
func run_smoke() -> void:
	var c := Vector2i(1, 1)
	var ok := true
	var seed_start := _selected_crop
	for i in range(_crop_ids.size()):
		cycle_seed()
	ok = ok and _crop_ids.size() >= 4 and _selected_crop == seed_start
	ok = ok and use_tool_on(c) and grid.tile_state(c) == FarmGrid.State.TILLED   # 空→耕
	ok = ok and use_tool_on(c) and grid.has_crop(c)                              # →种
	ok = ok and use_tool_on(c) and grid.tile_state(c) == FarmGrid.State.WATERED  # →浇
	var def = registry.get_def(&"crop", _selected_crop)
	for i in range(int(def.grow_days)):
		CoreKit.clock.advance_day()
	ok = ok and grid.crop_mature(c)
	ok = ok and use_tool_on(c) and not grid.has_crop(c) and bag.count(def.harvest_item) >= int(def.harvest_amount)  # 收
	ok = ok and _energy == ENERGY_MAX - 4 * ACTION_COST
	sleep()
	ok = ok and _energy == ENERGY_MAX
	# 工具升级 + 3×3 区域浇水
	shop.gold = 1000
	ok = ok and buy_water_upgrade() and _water_radius == 1
	ok = ok and not buy_water_upgrade()
	var center := Vector2i(5, 5)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			grid.till(center + Vector2i(dx, dy))
	_water_area(center)
	var watered := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if grid.tile_state(center + Vector2i(dx, dy)) == FarmGrid.State.WATERED:
				watered += 1
	ok = ok and watered == 9
	# 任务/成就
	shop.buy(&"turnip_seed", 1)
	ok = ok and tracker.unlocked_count() >= 1
	shop.sell(&"turnip", bag.count(&"turnip"))
	ok = ok and quest_log.done_count() >= 2
	var quests_done = quest_log.done_count()   # 无类型,不用 :=
	# 存读档往返(headless 无 player,跳位置断言)
	var gold_at_save = shop.gold
	save_game()
	grid.till(Vector2i(7, 7)); shop.gold = 123; _energy = 10; _water_radius = 0
	quest_log.forget_all()
	var loaded := load_game()
	ok = ok and loaded and shop.gold == gold_at_save and _energy == ENERGY_MAX
	ok = ok and _water_radius == 1
	ok = ok and quest_log.done_count() == quests_done
	ok = ok and grid.tile_state(Vector2i(7, 7)) == FarmGrid.State.EMPTY
	CoreKit.saves.delete_slot("farm")
	# i18n
	var loc0 = CoreKit.i18n.get_locale()
	var save0 = CoreKit.i18n.t("MENU_SAVE")
	cycle_locale()
	ok = ok and CoreKit.i18n.get_locale() != loc0 and CoreKit.i18n.t("MENU_SAVE") != save0
	cycle_locale()
	ok = ok and CoreKit.i18n.get_locale() == loc0
	# 音频
	ok = ok and AudioBank.sfx(&"till") != null and AudioBank.bgm() != null
	CoreKit.audio.set_volume("music", 0.5)
	ok = ok and absf(CoreKit.audio.get_volume("music") - 0.5) < 0.01
	# 五面板 build/push/pop
	for uiname in ["inventory", "shop", "menu", "log", "settings"]:
		_open_ui(uiname)
		ok = ok and _active_ui == uiname and _ui_stack.depth() == 1
		_close_ui()
		ok = ok and _active_ui == "" and _ui_stack.is_empty()
	# 区域切换状态字段读写(真实 change_scene 需场景树,留 F5)+ 农田状态跨"模拟切区"不丢
	var area0 = current_area
	pending_spawn = HOUSE_ENTRY
	current_area = "house"
	ok = ok and pending_spawn == HOUSE_ENTRY and current_area == "house"
	grid.till(Vector2i(3, 3))                       # 在"农舍"时改农田模型
	var st33 = grid.tile_state(Vector2i(3, 3))
	current_area = area0                             # 模拟切回农田(只逻辑,不真换场景)
	pending_spawn = Vector2.ZERO
	ok = ok and grid.tile_state(Vector2i(3, 3)) == st33 and st33 == FarmGrid.State.TILLED
	# NPC 出现 + 日程:白天小镇有 NPC;傍晚(hour>=18)奶奶按日程移到农舍
	ok = ok and npcs_in_area("town", 6).size() >= 2      # 商人 + 奶奶(白天在镇)
	ok = ok and npcs_in_area("house", 6).is_empty()      # 白天农舍无人
	ok = ok and npcs_in_area("house", 20).size() == 1    # 傍晚奶奶在农舍
	ok = ok and npcs_in_area("town", 20).size() == 1     # 傍晚镇上只剩商人
	# 对话面板 build/push/pop(商人 def)+ 聊天不崩
	var mdef = registry.get_def(&"npc", &"merchant")
	open_dialogue(mdef)
	ok = ok and _active_ui == "dialogue" and _ui_stack.depth() == 1
	route_action("farm_use")   # 聊天:出下一句台词
	route_action("move_down")  # 光标移到送礼
	close_menu()
	ok = ok and _active_ui == "" and _ui_stack.is_empty()
	# 送礼 + 好感度 + 解锁(商人爱萝卜,unlock_at=100 → 送两次触发星之种子)
	bag.add(&"turnip", 5, {}, 99)
	var f0 = friendship(&"merchant")
	var g1 = gift_to(&"merchant", &"turnip")
	ok = ok and g1.reaction == "loved" and friendship(&"merchant") == f0 + Relationship.GIFT_LOVED
	var g2 = gift_to(&"merchant", &"turnip")                 # 当日防刷
	ok = ok and g2.reaction == "already" and friendship(&"merchant") == f0 + Relationship.GIFT_LOVED
	CoreKit.clock.advance_day()                              # 翻天清防刷
	var g3 = gift_to(&"merchant", &"turnip")                 # 再 +50 → 100 触发解锁
	ok = ok and g3.unlocked and unlocked.has(&"merchant") and bag.count(&"star_seed") >= 1
	CoreKit.clock.advance_day()
	var star_before = bag.count(&"star_seed")
	gift_to(&"merchant", &"turnip")                          # 幂等:不重发
	ok = ok and bag.count(&"star_seed") == star_before
	# 好感/解锁随存读档
	var fm = friendship(&"merchant")
	save_game()
	relationships.clear(); unlocked.clear()
	load_game()
	ok = ok and friendship(&"merchant") == fm and unlocked.has(&"merchant")
	CoreKit.saves.delete_slot("farm")
	CoreKit.log.info("[Farm][SMOKE] %s(体力回满=%s,存读档=%s,任务=%d/%d,成就=%d/%d,语言=%s)" % [
		"PASS" if ok else "FAIL", _energy == ENERGY_MAX, loaded,
		quest_log.done_count(), quest_log.quest_count(),
		tracker.unlocked_count(), tracker.total(), CoreKit.i18n.get_locale()])
	tracker.reset_all()
	CoreKit.settings.erase_section("locale")
	CoreKit.settings.erase_section("audio")
	CoreKit.settings.erase_section("input")
	get_tree().quit(0 if ok else 1)
