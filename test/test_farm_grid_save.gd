extends SceneTree
## FarmGrid 存档往返单测(headless)。跑法:
##   godot --headless --path . -s res://test/test_farm_grid_save.gd
## 建若干格状态 + 不同作物/生长阶段 → to_dict → 经 JSON stringify/parse 往返 → 新 grid from_dict
## → 断言状态/作物/stage 完全一致(证明扛得住存档 JSON 退化)。

func _initialize() -> void:
	var failures := 0
	var FarmGrid = load("res://examples/farm-sim/systems/farm_grid.gd")
	var KitInv = load("res://addons/godot-core-kit/inventory/kit_inventory.gd")
	var KitReg = load("res://addons/godot-core-kit/data/kit_data_registry.gd")

	var reg = KitReg.new()
	reg.load_dir(&"crop", "res://examples/farm-sim/data/crops")
	reg.load_dir(&"item", "res://examples/farm-sim/data/items")

	# 原始 grid:耕几格、种两种作物、推进不同天数造出不同 stage
	var bag = KitInv.new(20)
	bag.add(&"turnip_seed", 5, {}, 99)
	bag.add(&"parsnip_seed", 5, {}, 99)
	var g = FarmGrid.new()
	g.setup(reg, bag, 10, 8)
	g.till(Vector2i(1, 1)); g.plant(Vector2i(1, 1), &"turnip"); g.water(Vector2i(1, 1))
	g.till(Vector2i(2, 3)); g.plant(Vector2i(2, 3), &"parsnip")
	g.till(Vector2i(4, 4))                                   # 空耕地,无作物
	g.advance_day()                                          # turnip stage1, parsnip stage1

	# 存:to_dict → JSON 往返(模拟 CoreKit.saves 的 JSON 落盘)
	var saved = JSON.parse_string(JSON.stringify(g.to_dict()))

	# 读:新 grid setup 后 from_dict
	var g2 = FarmGrid.new()
	g2.setup(reg, KitInv.new(20), 10, 8)
	g2.from_dict(saved)

	# 断言:尺寸、格状态、作物 id/stage 一致
	if g2.size() != g.size():
		failures += 1; print("FAIL: size mismatch %s vs %s" % [g2.size(), g.size()])
	for cell in [Vector2i(1, 1), Vector2i(2, 3), Vector2i(4, 4), Vector2i(0, 0)]:
		if g2.tile_state(cell) != g.tile_state(cell):
			failures += 1; print("FAIL: state @ %s: %d vs %d" % [cell, g2.tile_state(cell), g.tile_state(cell)])
		if g2.has_crop(cell) != g.has_crop(cell):
			failures += 1; print("FAIL: has_crop @ %s" % cell)
		if g2.crop_id(cell) != g.crop_id(cell):
			failures += 1; print("FAIL: crop_id @ %s: %s vs %s" % [cell, g2.crop_id(cell), g.crop_id(cell)])
		if g2.crop_stage(cell) != g.crop_stage(cell):
			failures += 1; print("FAIL: stage @ %s: %d vs %d" % [cell, g2.crop_stage(cell), g.crop_stage(cell)])

	# id 必须归一回 StringName(而非 JSON 退化的 String),否则 get_def 索引会 miss
	if typeof(g2.crop_id(Vector2i(1, 1))) != TYPE_STRING_NAME:
		failures += 1; print("FAIL: crop_id not normalized to StringName")
	# 还原后仍能正常推进到成熟(证明 registry 查得到)
	while not g2.crop_mature(Vector2i(1, 1)):
		g2.advance_day()
	if not g2.crop_mature(Vector2i(1, 1)):
		failures += 1; print("FAIL: cannot mature after load")

	if failures == 0:
		print("test_farm_grid_save: ALL PASS")
		quit(0)
	else:
		print("test_farm_grid_save: %d FAILURE(S)" % failures)
		quit(1)
