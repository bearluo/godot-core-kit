extends Control
## 背包面板(P1 占位 UI):只读列出背包物品×数量(字母序,展示名走 item 表)。由 world 经
## KitUiStack push;每次打开现建现填。P5 换真素材/网格布局不动逻辑。

var _bag
var _reg
var _list: VBoxContainer


func bind(bag, reg) -> void:
	_bag = bag
	_reg = reg


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.position = Vector2(60, 60)
	add_child(box)
	var title := Label.new()
	title.text = "背包  (I 关闭)"
	box.add_child(title)
	_list = VBoxContainer.new()
	box.add_child(_list)
	_refresh()


func _refresh() -> void:
	for ch in _list.get_children():
		ch.queue_free()
	var totals: Dictionary = _bag.totals()   # {id: 总数}
	var ids: Array = totals.keys()
	ids.sort_custom(func(a, b): return String(a) < String(b))
	if ids.is_empty():
		var e := Label.new()
		e.text = "(空)"
		_list.add_child(e)
		return
	for id in ids:
		var l := Label.new()
		l.text = "%s  ×%d" % [_name_of(id), int(totals[id])]
		_list.add_child(l)


func _name_of(id) -> String:
	var d = _reg.get_def_or(&"item", id, null)
	return d.display_name if d != null else String(id)


## 只读面板,无交互(world 路由的动作在此空转)。
func handle_action(_action: String) -> void:
	pass
