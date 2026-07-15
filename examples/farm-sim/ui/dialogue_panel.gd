extends Control
## NPC 对话面板(P3,走 KitUiStack 模态,锁玩家)。顶部 NPC 名 + 当前台词;下方选项
## [聊天]/[送礼]/[离开](↑↓ 选,J 确认)。聊天→轮换台词 + 当日首聊 +好感;送礼→进入送礼子菜单
## (列背包 produce,选一个送,按 NPC 喜好加减好感 + 出反应台词 + 可能触发好感解锁)。chrome 走 i18n key。

var _farm
var _def
var _line_idx := 0
var _mode := "menu"          ## "menu" | "gift"
var _cursor := 0
var _menu_opts := ["DLG_CHAT", "DLG_GIFT", "DLG_LEAVE"]   ## i18n key
var _gift_list: Array = []   ## [{id, label}];末项 id=&"" 表示返回

var _name_label: Label
var _line_label: Label
var _opt_list: VBoxContainer


## def = npc_def Resource;farm = Farm autoload(chat_with/gift_to/giftable_items/close_menu)。
func bind(def, farm) -> void:
	_def = def
	_farm = farm


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.position = Vector2(80, 280)
	add_child(box)
	_name_label = Label.new()
	box.add_child(_name_label)
	_line_label = Label.new()
	box.add_child(_line_label)
	var hint := Label.new()
	hint.text = CoreKit.i18n.t("DLG_HINT")
	hint.modulate = Color(1, 1, 1, 0.6)
	box.add_child(hint)
	_opt_list = VBoxContainer.new()
	box.add_child(_opt_list)
	_name_label.text = _def.display_name
	_line_label.text = _current_line()
	_refresh()


func _current_line() -> String:
	var lines: Array = _def.dialogue
	if lines.is_empty():
		return "……"
	return String(lines[_line_idx % lines.size()])


func _count() -> int:
	return _menu_opts.size() if _mode == "menu" else _gift_list.size()


func _refresh() -> void:
	for ch in _opt_list.get_children():
		ch.queue_free()
	if _mode == "menu":
		for i in range(_menu_opts.size()):
			var mark := "▶ " if i == _cursor else "   "
			var l := Label.new()
			l.text = mark + CoreKit.i18n.t(_menu_opts[i])
			_opt_list.add_child(l)
	else:
		for i in range(_gift_list.size()):
			var mark := "▶ " if i == _cursor else "   "
			var l := Label.new()
			l.text = mark + String(_gift_list[i].label)
			_opt_list.add_child(l)


## 面板开时区域把 move_up/down/farm_use 路由进来。
func handle_action(action: String) -> void:
	match action:
		"move_up":
			_cursor = (_cursor - 1 + _count()) % _count()
			_refresh()
		"move_down":
			_cursor = (_cursor + 1) % _count()
			_refresh()
		"farm_use":
			_activate()


func _activate() -> void:
	if _mode == "menu":
		match _menu_opts[_cursor]:
			"DLG_CHAT":
				_line_idx += 1
				_line_label.text = _current_line()
				_farm.chat_with(_def.id)
			"DLG_GIFT":
				_enter_gift()
			"DLG_LEAVE":
				_farm.close_menu()
	else:
		var entry = _gift_list[_cursor]
		if String(entry.id) == "":
			_mode = "menu"; _cursor = 0; _refresh()
		else:
			var res = _farm.gift_to(_def.id, entry.id)
			_line_label.text = _reaction_line(res)
			_mode = "menu"; _cursor = 0; _refresh()


## 进送礼子菜单:列背包 produce + 末尾"返回"项;背包无可送物则留在主菜单并提示。
func _enter_gift() -> void:
	_gift_list = []
	for it in _farm.giftable_items():
		_gift_list.append({"id": it.id, "label": "%s ×%d" % [it.name, it.count]})
	if _gift_list.is_empty():
		_line_label.text = CoreKit.i18n.t("DLG_NOGIFT")
		return
	_gift_list.append({"id": &"", "label": CoreKit.i18n.t("DLG_LEAVE")})
	_mode = "gift"; _cursor = 0; _refresh()


## 送礼结果 → 反应台词(解锁优先播解锁语)。
func _reaction_line(res) -> String:
	if bool(res.get("unlocked", false)):
		return CoreKit.i18n.t("DLG_UNLOCK")
	match String(res.get("reaction", "none")):
		"loved":
			return CoreKit.i18n.t("DLG_REACT_LOVED")
		"liked":
			return CoreKit.i18n.t("DLG_REACT_LIKED")
		"disliked":
			return CoreKit.i18n.t("DLG_REACT_DISLIKED")
		"neutral":
			return CoreKit.i18n.t("DLG_REACT_NEUTRAL")
		"already":
			return CoreKit.i18n.t("DLG_REACT_ALREADY")
		_:
			return _current_line()
