extends Control
## 商店面板(P1 占位 UI):列可买种子(buy_price)与可卖产物(sell_price),↑↓ 选行、J 买/卖(卖为
## 卖光该产物)。交易走 shop.buy/sell(已广播 shop: 事件、管金币/背包)。world 路由 move_up/
## move_down/farm_use 到 handle_action。

var _shop
var _reg
var _bag
var _world                 ## World(工具升级购买 + 金币源)
var _rows: Array = []   ## [{kind:"buy"/"sell"/"upgrade", id, price}]
var _cursor := 0
var _list: VBoxContainer
var _info: Label


func bind(shop, reg, bag, world) -> void:
	_shop = shop
	_reg = reg
	_bag = bag
	_world = world


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.position = Vector2(60, 60)
	add_child(box)
	var title := Label.new()
	title.text = "商店  (↑↓ 选,J 买/卖,P 关闭)"
	box.add_child(title)
	_info = Label.new()
	box.add_child(_info)
	_list = VBoxContainer.new()
	box.add_child(_list)
	_build_rows()
	_refresh()


func _build_rows() -> void:
	_rows.clear()
	for id in _reg.ids(&"item", true):        # 可买:种子且有买价
		var d = _reg.get_def(&"item", id)
		if d.category == &"seed" and d.buy_price > 0:
			_rows.append({"kind": "buy", "id": id, "price": int(d.buy_price)})
	for id in _reg.ids(&"item", true):        # 可卖:产物且有卖价
		var d = _reg.get_def(&"item", id)
		if d.category == &"produce" and d.sell_price > 0:
			_rows.append({"kind": "sell", "id": id, "price": int(d.sell_price)})
	if _world != null and not _world.water_upgraded():   # 工具升级行(仅未升级时出现)
		_rows.append({"kind": "upgrade", "id": &"", "price": int(_world.WATER_UPGRADE_COST)})


func _refresh() -> void:
	_info.text = "金币: %d" % _shop.gold
	for ch in _list.get_children():
		ch.queue_free()
	for i in range(_rows.size()):
		var r = _rows[i]
		var mark := "▶ " if i == _cursor else "   "
		var l := Label.new()
		if r.kind == "upgrade":
			l.text = "%s[升级] 水壶 3×3 浇水  价%d" % [mark, int(r.price)]
		else:
			var d = _reg.get_def(&"item", r.id)
			var verb := "买" if r.kind == "buy" else "卖"
			l.text = "%s[%s] %s  价%d  (持有%d)" % [mark, verb, d.display_name, int(r.price), _bag.count(r.id)]
		_list.add_child(l)


func handle_action(action: String) -> void:
	if _rows.is_empty():
		return
	match action:
		"move_up":
			_cursor = (_cursor - 1 + _rows.size()) % _rows.size()
			_refresh()
		"move_down":
			_cursor = (_cursor + 1) % _rows.size()
			_refresh()
		"farm_use":
			_do(_rows[_cursor])
			_refresh()


func _do(r) -> void:
	if r.kind == "buy":
		_shop.buy(r.id, 1)
	elif r.kind == "sell":
		var n = _bag.count(r.id)   # _bag 无类型,不用 :=
		if n > 0:
			_shop.sell(r.id, n)   # 卖光该产物
	elif r.kind == "upgrade":
		if _world.buy_water_upgrade():
			_build_rows()          # 升级成功 → 移除该行
			_cursor = mini(_cursor, maxi(0, _rows.size() - 1))
