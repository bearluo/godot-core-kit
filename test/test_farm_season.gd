extends SceneTree
## 季节门 + 天气生长加成 单测(headless,不经 CoreKit autoload,直接实例化)。跑法:
##   godot --headless --path . -s res://test/test_farm_season.gd
## 覆盖:作物 seasons 字段载入、越季播种被拦(不消耗种子)、当季播种成功、全季作物不受季
## 节限制、advance_day(bonus) 生长加成(雨天 +1)。

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

	# 1. seasons 字段载入:南瓜秋季限定
	var pumpkin_def = reg.get_def(&"crop", &"pumpkin")
	if pumpkin_def == null or pumpkin_def.seasons != [&"fall"]:
		failures += 1; print("FAIL 1: pumpkin seasons != [fall], got %s" % [pumpkin_def.seasons if pumpkin_def else "null"])

	# 2. 越季播种被拦:春天种南瓜失败,种子不消耗
	bag.add(&"pumpkin_seed", 3, {}, 99)
	var c := Vector2i(2, 2)
	grid.till(c)
	if grid.plant(c, &"pumpkin", &"spring"):
		failures += 1; print("FAIL 2: planted fall-crop in spring")
	if bag.count(&"pumpkin_seed") != 3:
		failures += 1; print("FAIL 2b: seed consumed on out-of-season plant, count=%d" % bag.count(&"pumpkin_seed"))
	if grid.has_crop(c):
		failures += 1; print("FAIL 2c: crop placed despite season gate")

	# 3. 当季播种成功,种子 -1
	if not grid.plant(c, &"pumpkin", &"fall"):
		failures += 1; print("FAIL 3: plant pumpkin in fall failed")
	if bag.count(&"pumpkin_seed") != 2:
		failures += 1; print("FAIL 3b: seed not consumed in-season, count=%d" % bag.count(&"pumpkin_seed"))

	# 4. 全季作物(turnip seasons 空)任何季节可种
	if not grid.crop_plantable(&"turnip", &"winter"):
		failures += 1; print("FAIL 4: all-season crop blocked in winter")
	if not grid.crop_plantable(&"pumpkin", &""):
		failures += 1; print("FAIL 4b: season &'' should skip gate")

	# 5. advance_day(bonus):无加成 +1,雨天加成 +1 → +2(封顶在 grow_days)
	var c2 := Vector2i(5, 5)
	bag.add(&"turnip_seed", 3, {}, 99)
	grid.till(c2)
	grid.plant(c2, &"turnip", &"spring")   # turnip 全季,grow_days=2
	grid.advance_day(0)
	if grid.crop_stage(c2) != 1:
		failures += 1; print("FAIL 5: advance_day(0) stage=%d != 1" % grid.crop_stage(c2))
	grid.advance_day(1)                     # +2 但封顶到 grow_days=2
	if grid.crop_stage(c2) != 2 or not grid.crop_mature(c2):
		failures += 1; print("FAIL 5b: advance_day(1) stage=%d, mature=%s" % [grid.crop_stage(c2), grid.crop_mature(c2)])

	if failures == 0:
		print("test_farm_season: ALL PASS")
		quit(0)
	else:
		print("test_farm_season: %d FAILURE(S)" % failures)
		quit(1)
