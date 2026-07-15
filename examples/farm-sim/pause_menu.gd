extends Control
## 暂停菜单(P1 占位 UI):存档 / 读档 / 继续。↑↓ 选,J 确认,Esc 关闭。存读档委托给 world
## (world.save_game/load_game/close_menu)。

var _world
var _items := ["MENU_SAVE", "MENU_LOAD", "MENU_SETTINGS", "MENU_CONTINUE"]   ## i18n key
var _cursor := 0
var _list: VBoxContainer
var _msg: Label


func bind(world) -> void:
	_world = world


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.position = Vector2(80, 80)
	add_child(box)
	var title := Label.new()
	title.text = CoreKit.i18n.t("MENU_TITLE")
	box.add_child(title)
	_list = VBoxContainer.new()
	box.add_child(_list)
	_msg = Label.new()
	box.add_child(_msg)
	_refresh()


func _refresh() -> void:
	for ch in _list.get_children():
		ch.queue_free()
	for i in range(_items.size()):
		var mark := "▶ " if i == _cursor else "   "
		var l := Label.new()
		l.text = mark + CoreKit.i18n.t(_items[i])
		_list.add_child(l)


func handle_action(action: String) -> void:
	match action:
		"move_up":
			_cursor = (_cursor - 1 + _items.size()) % _items.size()
			_refresh()
		"move_down":
			_cursor = (_cursor + 1) % _items.size()
			_refresh()
		"farm_use":
			_activate()


func _activate() -> void:
	match _cursor:
		0:
			_world.save_game()
			_msg.text = CoreKit.i18n.t("MENU_SAVED")
		1:
			if _world.load_game():
				_msg.text = CoreKit.i18n.t("MENU_LOADED")
			else:
				_msg.text = CoreKit.i18n.t("MENU_NOSAVE")
		2:
			_world.open_settings()
		3:
			_world.close_menu()
