extends SceneTree
## FarmGrid 逻辑单测(headless,不经 CoreKit autoload,直接实例化)。跑法:
##   godot --headless --path . -s res://test/test_farm_grid.gd
## 覆盖:边界、耕地、播种(扣种子)、非法播种、浇水、生长到成熟、收获入背包、无种子播种。

func _initialize() -> void:
	var failures := 0
	var FarmGrid = load("res://examples/farm-sim/systems/farm_grid.gd")
	var KitInv = load("res://addons/godot-core-kit/inventory/kit_inventory.gd")
	var KitReg = load("res://addons/godot-core-kit/data/kit_data_registry.gd")

	var reg = KitReg.new()
	reg.load_dir(&"crop", "res://examples/farm-sim/data/crops")
	reg.load_dir(&"item", "res://examples/farm-sim/data/items")
	var bag = KitInv.new(20)
	var grid = FarmGrid.new()
	grid.setup(reg, bag, 10, 8)

	var EMPTY := int(FarmGrid.State.EMPTY)
	var TILLED := int(FarmGrid.State.TILLED)
	var WATERED := int(FarmGrid.State.WATERED)

	# 1. 尺寸与边界
	if grid.size() != Vector2i(10, 8):
		failures += 1; print("FAIL 1: size %s" % grid.size())
	if grid.cell_valid(Vector2i(10, 0)) or grid.cell_valid(Vector2i(-1, 0)):
		failures += 1; print("FAIL 1b: out-of-bounds treated valid")
	if not grid.cell_valid(Vector2i(0, 0)):
		failures += 1; print("FAIL 1c: in-bounds treated invalid")

	# 2. 耕地:空 → 已耕;重复耕失败
	var c := Vector2i(2, 2)
	if grid.tile_state(c) != EMPTY:
		failures += 1; print("FAIL 2: initial not EMPTY")
	if not grid.till(c) or grid.tile_state(c) != TILLED:
		failures += 1; print("FAIL 2b: till failed")
	if grid.till(c):
		failures += 1; print("FAIL 2c: re-till on TILLED succeeded")

	# 3. 未耕格播种失败
	if grid.plant(Vector2i(5, 5), &"turnip"):
		failures += 1; print("FAIL 3: plant on EMPTY succeeded")

	# 4. 有种子 → 播种成功,扣 1 种子
	bag.add(&"turnip_seed", 3, {}, 99)
	if not grid.plant(c, &"turnip"):
		failures += 1; print("FAIL 4: plant on TILLED with seed failed")
	if bag.count(&"turnip_seed") != 2:
		failures += 1; print("FAIL 4b: seed not consumed, count=%d" % bag.count(&"turnip_seed"))
	if not grid.has_crop(c) or grid.crop_stage(c) != 0:
		failures += 1; print("FAIL 4c: crop not planted at stage 0")

	# 5. 同格再种失败(已有作物)
	if grid.plant(c, &"turnip"):
		failures += 1; print("FAIL 5: replant on occupied succeeded")

	# 6. 浇水:已耕 → 已浇;重复浇失败
	if not grid.water(c) or grid.tile_state(c) != WATERED:
		failures += 1; print("FAIL 6: water failed")
	if grid.water(c):
		failures += 1; print("FAIL 6b: re-water on WATERED succeeded")

	# 7. 生长到成熟(turnip grow_days=2)
	if grid.crop_mature(c):
		failures += 1; print("FAIL 7: mature too early")
	grid.advance_day()
	grid.advance_day()
	if grid.crop_stage(c) != 2 or not grid.crop_mature(c):
		failures += 1; print("FAIL 7b: not mature after 2 days, stage=%d" % grid.crop_stage(c))

	# 8. 收获:产物入背包,格回已耕,作物清除
	if not grid.harvest(c):
		failures += 1; print("FAIL 8: harvest mature failed")
	if bag.count(&"turnip") != 3:
		failures += 1; print("FAIL 8b: harvest yield wrong, turnip=%d" % bag.count(&"turnip"))
	if grid.has_crop(c) or grid.tile_state(c) != TILLED:
		failures += 1; print("FAIL 8c: post-harvest state wrong")

	# 9. 无种子播种失败(背包无 parsnip_seed)
	var c2 := Vector2i(4, 4)
	grid.till(c2)
	if grid.plant(c2, &"parsnip"):
		failures += 1; print("FAIL 9: plant without seed succeeded")

	if failures == 0:
		print("test_farm_grid: ALL PASS")
		quit(0)
	else:
		print("test_farm_grid: %d FAILURE(S)" % failures)
		quit(1)
