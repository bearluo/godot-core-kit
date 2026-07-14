extends Control
## 极简背包 UI 面板(演示 KitUiStack.push 承载游戏面板)。给定背包 + 物品表,构建一列
## Label 列出"物品展示名 × 总数"。headless 下 Control 照常构建(只是不渲染),本例把面板
## 每行内容打进日志以证明 UI 反映了背包状态。
##
## 说明:这里用最朴素的 Control + VBox;真实项目可让面板组合一个 KitUiScreen 子节点拿到
## entered/exited/covered/revealed 生命周期钩子(见 docs/ui/ui-stack.md)。

var _lines: PackedStringArray = PackedStringArray()


## 由背包 + 物品表构建面板内容(需在 push 前调用)。
func setup(bag, registry) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vbox := VBoxContainer.new()
	add_child(vbox)
	var title := Label.new()
	title.text = "背包"
	vbox.add_child(title)
	_lines = PackedStringArray()
	for entry in _aggregate(bag):
		var idef = registry.get_def_or(&"item", entry["id"], null)
		var display := String(idef.display_name) if idef != null else String(entry["id"])
		var line := "%s x%d" % [display, entry["count"]]
		_lines.append(line)
		var lbl := Label.new()
		lbl.text = line
		vbox.add_child(lbl)


## 面板当前显示的每一行(供日志/断言用)。
func lines() -> PackedStringArray:
	return _lines


## 用 KitInventory.totals()(v0.18.0)拿 {id:总数} 聚合,再按 id 字母序排成 [{id,count}, ...]。
## (totals 返回 dict、无序,故仍需 sort_custom;字典序理由见 KitDataRegistry 文档的 StringName 坑。)
func _aggregate(bag) -> Array:
	var totals = bag.totals()
	var ids = totals.keys()
	ids.sort_custom(func(x, y): return String(x) < String(y))
	var out := []
	for id in ids:
		out.append({"id": id, "count": totals[id]})
	return out
