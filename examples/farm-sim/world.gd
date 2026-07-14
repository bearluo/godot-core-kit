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

const GRID_W := 10
const GRID_H := 8
const ENERGY_MAX := 100
const ACTION_COST := 8   ## 每个工具动作耗的体力

var _registry
var _bag
var _grid
var _view
var _player
var _shop
var _selected_crop: StringName = &"turnip"   ## 当前选中种子(cycle_seed 切换)
var _crop_ids: Array = []                      ## 可选作物 id(字母序)
var _energy := ENERGY_MAX                      ## 当前体力(工具动作扣,睡觉回满)
var _ui_stack                                  ## KitUiStack(背包/商店/菜单)
var _active_ui := ""                            ## 当前打开的面板名(""=无)


func energy() -> int:
	return _energy


func energy_max() -> int:
	return ENERGY_MAX


func _ready() -> void:
	CoreKit.log.info("[World] 农场世界启动")
	# 数据 + 背包(起始给点种子)
	_registry = KitDataRegistry.new()
	_registry.load_dir(&"crop", "res://examples/farm-sim/data/crops")
	_registry.load_dir(&"item", "res://examples/farm-sim/data/items")
	_bag = KitInventory.new(20)
	_bag.add(&"turnip_seed", 10, {}, 99)
	_bag.add(&"parsnip_seed", 10, {}, 99)
	_bag.add(&"potato_seed", 10, {}, 99)
	_crop_ids = _registry.ids(&"crop", true)   # 可选作物字母序:[parsnip, potato, turnip]

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

	# 逐日推进:接时钟广播,作物生长 + 重绘
	CoreKit.bus.subscribe(CoreKit.clock.EV_DAY_CHANGED, _on_day)
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
	ok = ok and _crop_ids.size() >= 3 and _selected_crop == seed_start
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
	# 存读档往返:存 → 改(金币/体力/地块)→ 读 → 全量复原
	var gold_at_save = _shop.gold   # _shop 无类型,不用 :=
	save_game()
	_grid.till(Vector2i(7, 7)); _shop.gold = 123; _energy = 10
	var loaded := load_game()
	ok = ok and loaded and _shop.gold == gold_at_save and _energy == ENERGY_MAX
	ok = ok and _grid.tile_state(Vector2i(7, 7)) == FarmGrid.State.EMPTY   # 读档回滚了 till
	CoreKit.saves.delete_slot("farm")                       # 清存档槽,保证可重复跑
	# UI 面板冒烟:三个面板各开各关一次,验证 build/push/pop 不报错(手感/布局仍需 F5)
	for uiname in ["inventory", "shop", "menu"]:
		_open_ui(uiname)
		ok = ok and _active_ui == uiname and _ui_stack.depth() == 1
		_close_ui()
		ok = ok and _active_ui == "" and _ui_stack.is_empty()
	CoreKit.log.info("[World][SMOKE] %s(背包 %s=%d,体力回满=%s,存读档=%s)" % [
		"PASS" if ok else "FAIL", def.harvest_item, _bag.count(def.harvest_item),
		_energy == ENERGY_MAX, loaded])
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
			panel.bind(_shop, _registry, _bag)
		"menu":
			panel = PauseMenu.new()
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


## 存档:地块 + 背包 + 金币 + 时钟 + 体力 全量存进 CoreKit.saves。
func save_game() -> void:
	CoreKit.saves.save("farm", {
		"grid": _grid.to_dict(), "bag": _bag.to_dict(),
		"gold": _shop.gold, "clock": CoreKit.clock.to_dict(), "energy": _energy})
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
	_view.queue_redraw()
	CoreKit.log.info("[World] 已读档")
	return true


## 对玩家面前那一格用工具:按状态派发 耕→种→浇→收。成功一次扣体力,精疲则自动睡。
func _use_tool() -> void:
	var c: Vector2i = _player.facing_cell()
	if not _grid.cell_valid(c):
		return
	if _energy <= 0:
		CoreKit.log.info("[World] 精疲力尽,按 N 睡觉")
		return
	var did := false
	if _grid.has_crop(c):
		if _grid.crop_mature(c):
			did = _grid.harvest(c)
			if did: CoreKit.log.info("[World] 收获 @ %s" % c)
		else:
			did = _grid.water(c)
			if did: CoreKit.log.info("[World] 浇水 @ %s" % c)
	elif _grid.tile_state(c) == FarmGrid.State.EMPTY:
		did = _grid.till(c)
		if did: CoreKit.log.info("[World] 耕地 @ %s" % c)
	else:
		did = _grid.plant(c, _selected_crop)
		if did:
			CoreKit.log.info("[World] 播种 %s @ %s" % [_selected_crop, c])
		else:
			did = _grid.water(c)
			if did: CoreKit.log.info("[World] 浇水 @ %s" % c)
	if did:
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


## 当前选中种子的展示名(供 HUD)。
func selected_crop_name() -> String:
	var def = _registry.get_def_or(&"crop", _selected_crop, null)
	return def.display_name if def != null else String(_selected_crop)


## 睡觉:推进一天(作物生长)+ 体力回满。
func _sleep() -> void:
	CoreKit.clock.advance_day()
	_energy = ENERGY_MAX
	CoreKit.log.info("[World] 睡了一觉,体力回满")


func _on_day(_snap: Dictionary) -> void:
	_grid.advance_day()
	_view.queue_redraw()
	CoreKit.log.info("[World] 新的一天,作物生长")
