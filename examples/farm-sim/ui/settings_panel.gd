extends Control
## 设置面板(P2)。语言切换(J 或点击)+ 音量三条 HSlider(master/music/sfx)+ 键位重绑定
## (KitRebindList)。由暂停菜单"设置"打开;world 路由 farm_use 到 handle_action 切语言,音量/
## 重绑定走鼠标 GUI。locale_changed 时 world 重建本面板,故语言与各标签即时刷新。

var _world
var _lang_label: Label


func bind(world) -> void:
	_world = world


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.position = Vector2(60, 50)
	add_child(box)
	var title := Label.new()
	title.text = CoreKit.i18n.t("SET_TITLE")
	box.add_child(title)

	# 语言(J 切换,或点标签)
	_lang_label = Label.new()
	box.add_child(_lang_label)
	_refresh_lang()

	# 音量三条(鼠标拖动;写 AudioServer 并落 Settings)
	box.add_child(_volume_row("SET_VOL_MASTER", "master"))
	box.add_child(_volume_row("SET_VOL_MUSIC", "music"))
	box.add_child(_volume_row("SET_VOL_SFX", "sfx"))

	# 键位重绑定(点按钮→按新键;KitRebindList 自动冲突拦截 + 落 Settings)
	var rebind_title := Label.new()
	rebind_title.text = CoreKit.i18n.t("SET_REBIND")
	box.add_child(rebind_title)
	var list := KitRebindList.new()
	box.add_child(list)
	list.setup([
		{"action": "move_up", "label": CoreKit.i18n.t("KEY_UP")},
		{"action": "move_down", "label": CoreKit.i18n.t("KEY_DOWN")},
		{"action": "move_left", "label": CoreKit.i18n.t("KEY_LEFT")},
		{"action": "move_right", "label": CoreKit.i18n.t("KEY_RIGHT")},
		{"action": "farm_use", "label": CoreKit.i18n.t("KEY_USE")},
		{"action": "farm_next_day", "label": CoreKit.i18n.t("KEY_SLEEP")},
		{"action": "cycle_seed", "label": CoreKit.i18n.t("KEY_SEED")},
	])


func _refresh_lang() -> void:
	var loc := CoreKit.i18n.get_locale()
	_lang_label.text = "%s: %s  (J)" % [CoreKit.i18n.t("SET_LANG"), "中文" if loc == "zh" else "English"]


func _volume_row(key: String, bus: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = CoreKit.i18n.t(key)
	l.custom_minimum_size = Vector2(96, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(180, 0)
	s.value = CoreKit.audio.get_volume(bus)
	s.value_changed.connect(func(v): CoreKit.audio.set_volume(bus, v))
	row.add_child(s)
	return row


## world 路由:J(farm_use)切语言(切后 world 经 locale_changed 重建本面板)。
func handle_action(action: String) -> void:
	if action == "farm_use":
		_world.cycle_locale()
