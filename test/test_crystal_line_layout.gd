extends SceneTree
## 《晶核防线》布局 headless 断言(守 CL-001)
## 运行: godot --headless --path . -s res://test/test_crystal_line_layout.gd
##
## 截图是验收证据,这个测试是**回归护栏**:把「标题 / 晶核 HP / 金币 / 波次 /
## 完整 5x8 棋盘 / 全部底部按钮 同时在视口内且不被裁」写成断言,分辨率一变就报警。

const SCENE := "res://game/crystal_line/main.tscn"
## 被测视口尺寸。前两个是三档目标分辨率在 project.godot stretch 规则下的实际视口:
##   540x960  → scale 0.75  → 720x1280
##   720x1280 → scale 1.00  → 720x1280
##   1152x648 → scale 0.506 → 2276x1280
## 后两个是「万一有人关掉 stretch」的裸视口,顺带守住极端宽高比。
const SIZES := [
	Vector2i(720, 1280),
	Vector2i(2276, 1280),
	Vector2i(540, 960),
	Vector2i(1152, 648),
]

var failures := 0


func _initialize() -> void:
	await process_frame
	for s in SIZES:
		await _check_size(s)
	await _check_result_panel()

	if failures == 0:
		print("test_crystal_line_layout: ALL PASS")
		quit(0)
	else:
		print("test_crystal_line_layout: %d FAILURE(S)" % failures)
		quit(1)


func _fail(msg: String) -> void:
	print("FAIL %s" % msg)
	failures += 1


func _mount(size: Vector2i) -> Array:
	var packed: PackedScene = load(SCENE)
	var sub := SubViewport.new()
	sub.size = size
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub)
	var node = packed.instantiate()
	sub.add_child(node)
	return [sub, node]


func _check_size(size: Vector2i) -> void:
	var pair := _mount(size)
	var sub: SubViewport = pair[0]
	var node = pair[1]
	for _i in 4:
		await process_frame

	var vp := Vector2(size)
	var must_see := {
		"标题": node.get_node("Root/Title"),
		"晶核HP": node.get_node("Root/Hud/Hp"),
		"金币": node.get_node("Root/Hud/Gold"),
		"波次": node.get_node("Root/Hud/Wave"),
		"塔数": node.get_node("Root/Hud/Towers"),
		"棋盘": node.get_node("Root/Board"),
		"火塔按钮": node.get_node("Root/Bar/Fire"),
		"冰塔按钮": node.get_node("Root/Bar/Ice"),
		"开波按钮": node.get_node("Root/Bar/Wave"),
		"重开按钮": node.get_node("Root/Bar/Reset"),
		"提示": node.get_node("Root/Hint"),
	}
	for label in must_see.keys():
		var c: Control = must_see[label]
		var r: Rect2 = c.get_global_rect()
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			_fail("%s @%s 尺寸为零 %s" % [label, size, r])
			continue
		if r.position.x < -0.5 or r.position.y < -0.5:
			_fail("%s @%s 被推出视口左/上 %s" % [label, size, r])
		if r.end.x > vp.x + 0.5 or r.end.y > vp.y + 0.5:
			_fail("%s @%s 超出视口右/下 %s vp=%s" % [label, size, r, vp])

	# HUD 文案必须是真状态,不是占位符
	var hp_text: String = node.get_node("Root/Hud/Hp").text
	var gold_text: String = node.get_node("Root/Hud/Gold").text
	var wave_text: String = node.get_node("Root/Hud/Wave").text
	if not hp_text.begins_with("晶核") or not gold_text.begins_with("金币") \
			or not wave_text.begins_with("波次"):
		_fail("HUD 文案不对 @%s hp=%s gold=%s wave=%s" % [size, hp_text, gold_text, wave_text])

	# 完整 5x8 棋盘必须画得下,且落在 Board 控件内
	var board: Control = node.get_node("Root/Board")
	var m: Dictionary = node.board_metrics()
	var cell: float = m["cell"]
	var grid: Vector2 = m["size"]
	if cell <= 4.0:
		_fail("棋盘格边长过小 @%s cell=%.2f" % [size, cell])
	if grid.x > board.size.x + 0.5 or grid.y > board.size.y + 0.5:
		_fail("5x8 棋盘被裁 @%s grid=%s board=%s" % [size, grid, board.size])
	var grid_origin: Vector2 = board.get_global_rect().position + Vector2(m["origin"])
	if grid_origin.y < -0.5 or grid_origin.y + grid.y > vp.y + 0.5:
		_fail("棋盘纵向溢出视口 @%s origin=%s grid=%s" % [size, grid_origin, grid])

	# 纵向顺序:标题 → HUD → 棋盘 → 按钮栏 → 提示,互不重叠
	var order := ["Root/Title", "Root/Hud", "Root/Board", "Root/Bar", "Root/Hint"]
	var prev_bottom := -1.0
	for p in order:
		var c2: Control = node.get_node(p)
		var r2: Rect2 = c2.get_global_rect()
		if r2.position.y + 0.5 < prev_bottom:
			_fail("%s @%s 与上一段重叠 top=%.1f prev_bottom=%.1f" % [p, size, r2.position.y, prev_bottom])
		prev_bottom = r2.end.y

	print("LAYOUT ok @%dx%d cell=%.1f grid=%.0fx%.0f" % [size.x, size.y, cell, grid.x, grid.y])
	sub.queue_free()
	await process_frame


## 结算面板:开局隐藏 → 破核后弹出并带「再来一局」→ 点它回到可玩状态
func _check_result_panel() -> void:
	var pair := _mount(Vector2i(720, 1280))
	var sub: SubViewport = pair[0]
	var node = pair[1]
	for _i in 3:
		await process_frame

	if node.get_node("Result").visible:
		_fail("开局不应显示结算面板")

	# 不建塔快速推到破核(直接推逻辑,再让 _process 反应)
	var guard := 0
	while not node.sim.is_round_over() and guard < 20000:
		node.sim.tick(0.05)
		guard += 1
	for _i in 3:
		await process_frame

	if not node.get_node("Result").visible:
		_fail("破核后应弹出结算面板")
	var body: String = node.get_node("Result/Center/Panel/Box/RBody").text
	var title: String = node.get_node("Result/Center/Panel/Box/RTitle").text
	if body.is_empty() or not body.contains("波次"):
		_fail("结算面板缺少本局统计 body=%s" % body)
	if title.is_empty():
		_fail("结算面板缺少标题")
	var again: Button = node.get_node("Result/Center/Panel/Box/Again")
	if again.text.is_empty():
		_fail("缺少「再来一局」入口")
	var r: Rect2 = again.get_global_rect()
	if r.position.x < 0.0 or r.end.x > 720.0 or r.position.y < 0.0 or r.end.y > 1280.0:
		_fail("「再来一局」按钮不在视口内 %s" % r)

	again.pressed.emit()
	for _i in 2:
		await process_frame
	if node.get_node("Result").visible:
		_fail("再来一局后结算面板应关闭")
	if node.sim.is_round_over() or node.sim.wave != 0 or node.sim.core_hp != node.sim.START_HP:
		_fail("再来一局后应回到可玩状态 wave=%d hp=%d" % [node.sim.wave, node.sim.core_hp])
	print("LAYOUT result panel ok title=%s" % title)
	sub.queue_free()
	await process_frame
