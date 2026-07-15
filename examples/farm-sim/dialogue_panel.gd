extends Control
## NPC 对话面板(P3,走 KitUiStack 模态,锁玩家)。顶部 NPC 名 + 当前台词;下方选项
## [聊天]/[送礼]/[离开](↑↓ 选,J 确认)。聊天→出下一句台词轮换。**本 Task(4)先只做聊天与离开**,
## [送礼] 占位置灰(Task5 启用)。chrome 文案走 i18n key;NPC 名与台词用 .tres 原文。

var _farm
var _def
var _line_idx := 0
var _cursor := 0
var _options := ["DLG_CHAT", "DLG_GIFT", "DLG_LEAVE"]   ## i18n key
var _gift_enabled := false   ## Task5 送礼启用

var _name_label: Label
var _line_label: Label
var _opt_list: VBoxContainer


## def = npc_def Resource;farm = Farm autoload(聊天/送礼/关面板回调)。
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
	_refresh_options()


func _current_line() -> String:
	var lines: Array = _def.dialogue
	if lines.is_empty():
		return "……"
	return String(lines[_line_idx % lines.size()])


func _refresh_options() -> void:
	for ch in _opt_list.get_children():
		ch.queue_free()
	for i in range(_options.size()):
		var mark := "▶ " if i == _cursor else "   "
		var l := Label.new()
		l.text = mark + CoreKit.i18n.t(_options[i])
		if _options[i] == "DLG_GIFT" and not _gift_enabled:
			l.modulate = Color(1, 1, 1, 0.35)   # 占位禁用
		_opt_list.add_child(l)


## 面板开时区域把 move_up/down/farm_use 路由进来。
func handle_action(action: String) -> void:
	match action:
		"move_up":
			_cursor = (_cursor - 1 + _options.size()) % _options.size()
			_refresh_options()
		"move_down":
			_cursor = (_cursor + 1) % _options.size()
			_refresh_options()
		"farm_use":
			_activate()


func _activate() -> void:
	match _options[_cursor]:
		"DLG_CHAT":
			_line_idx += 1
			_line_label.text = _current_line()
		"DLG_GIFT":
			pass   # Task5 启用
		"DLG_LEAVE":
			_farm.close_menu()
