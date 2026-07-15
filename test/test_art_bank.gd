extends SceneTree
## test/test_art_bank.gd —— 美术接缝 art_bank 逻辑测(不依赖 CoreKit;运行时 load)。
## 覆盖:各 key tex() 返回非空 Texture2D + 尺寸正确 + 缓存命中(同 key 返回同实例)+ 未知 key 回退不崩。
## 按需单跑(不进 run_all $tests):godot --headless --path . -s res://test/test_art_bank.gd

func _initialize() -> void:
	var ArtBank = load("res://examples/farm-sim/gfx/art_bank.gd")
	var failures := 0

	ArtBank.clear_cache()

	# 瓦片:32×32 非空
	for key in [&"tile_grass", &"tile_tilled", &"tile_watered"]:
		var t = ArtBank.tex(key)
		if t == null or not (t is Texture2D):
			failures += 1; print("FAIL: %s not a Texture2D" % key)
		elif t.get_width() != 32 or t.get_height() != 32:
			failures += 1; print("FAIL: %s size %dx%d" % [key, t.get_width(), t.get_height()])

	# 作物:32×32 非空
	var crop = ArtBank.tex(&"crop")
	if crop == null or crop.get_width() != 32:
		failures += 1; print("FAIL: crop tex")

	# 角色/物件精灵:各 key 生成非空 Texture2D + 期望尺寸
	var sprite_specs := {
		&"player_down_0": Vector2i(24, 24), &"player_down_1": Vector2i(24, 24),
		&"player_up_0": Vector2i(24, 24), &"player_left_0": Vector2i(24, 24),
		&"player_right_0": Vector2i(24, 24), &"npc": Vector2i(24, 24),
		&"bed": Vector2i(48, 64), &"shop_sign": Vector2i(72, 56), &"door": Vector2i(40, 40),
		&"fx_star": Vector2i(8, 8), &"fx_drop": Vector2i(8, 8),
		&"fx_dust": Vector2i(8, 8), &"fx_gold": Vector2i(8, 8),
	}
	for key in sprite_specs:
		var t = ArtBank.tex(key)
		var want: Vector2i = sprite_specs[key]
		if t == null or not (t is Texture2D):
			failures += 1; print("FAIL: %s not a Texture2D" % key)
		elif t.get_width() != want.x or t.get_height() != want.y:
			failures += 1; print("FAIL: %s size %dx%d want %dx%d" % [key, t.get_width(), t.get_height(), want.x, want.y])

	# 缓存命中:同 key 两次返回同一实例
	var a = ArtBank.tex(&"tile_grass")
	var b = ArtBank.tex(&"tile_grass")
	if a != b:
		failures += 1; print("FAIL: cache miss (different instances)")

	# 未知 key:回退不崩、返回非空(品红 fallback)
	var unknown = ArtBank.tex(&"__nope__")
	if unknown == null or not (unknown is Texture2D):
		failures += 1; print("FAIL: unknown key fallback")

	# clear_cache 后重新生成(非崩溃即可)
	ArtBank.clear_cache()
	var c = ArtBank.tex(&"tile_grass")
	if c == null:
		failures += 1; print("FAIL: regen after clear")

	if failures == 0:
		print("test_art_bank: ALL PASS")
		quit(0)
	else:
		print("test_art_bank: %d FAILURE(S)" % failures)
		quit(1)
