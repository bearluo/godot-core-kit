extends Control
## 任务/成就日志面板(P2 占位 UI)。只读展示 quest_log.summary_lines() + achievement_tracker
## .summary_lines()。由 world 经 KitUiStack push;每次打开现建现填。L 键开关。
## dogfood 边界:任务=每档进度(随存档),成就=账号级(存 settings)——面板只读、不改状态。

var _quest_log
var _tracker
var _list: VBoxContainer


func bind(quest_log, tracker) -> void:
	_quest_log = quest_log
	_tracker = tracker


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.position = Vector2(60, 60)
	add_child(box)
	var title := Label.new()
	title.text = CoreKit.i18n.t("LOG_TITLE")
	box.add_child(title)
	_list = VBoxContainer.new()
	box.add_child(_list)
	_refresh()


func _refresh() -> void:
	for ch in _list.get_children():
		ch.queue_free()
	_section("── 任务 (%d/%d) ──" % [_quest_log.done_count(), _quest_log.quest_count()],
		_quest_log.summary_lines())
	_section("── 成就 (%d/%d) ──" % [_tracker.unlocked_count(), _tracker.total()],
		_tracker.summary_lines())


func _section(header: String, lines: Array) -> void:
	var h := Label.new()
	h.text = header
	_list.add_child(h)
	for line in lines:
		var l := Label.new()
		l.text = "  " + str(line)
		_list.add_child(l)


## 只读面板,无交互(world 路由的动作在此空转)。
func handle_action(_action: String) -> void:
	pass
