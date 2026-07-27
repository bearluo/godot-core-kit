extends SceneTree
## CrystalArtBank 三级接缝 + bake 契约
## 运行: godot --headless --path . -s res://test/test_crystal_line_art_bank.gd

func _initialize() -> void:
	var failures := 0
	var Bank = load("res://game/crystal_line/gfx/art_bank.gd")
	var bank = Bank.new()

	# 1. bake_keys 非空
	var keys: Array = bank.bake_keys()
	if keys.is_empty():
		print("FAIL 1: bake_keys 空")
		failures += 1

	# 2. 每个 key bake_image 非空且尺寸对
	for k in keys:
		var img: Image = bank.bake_image(k)
		if img == null or img.is_empty():
			print("FAIL 2: bake_image 空 key=%s" % k)
			failures += 1
			continue
		if img.get_width() != 48 or img.get_height() != 48:
			print("FAIL 2b: 尺寸不对 key=%s %dx%d" % [k, img.get_width(), img.get_height()])
			failures += 1

	# 3. texture_for 返回 Texture2D
	var tex: Texture2D = bank.texture_for(&"tower_fire")
	if tex == null:
		print("FAIL 3: texture_for null")
		failures += 1

	# 4. source_for: 若已烘焙应为 baked,否则 procedural
	var src: String = bank.source_for(&"tower_fire")
	if src != "baked" and src != "procedural" and src != "asset":
		print("FAIL 4: source_for 非法 %s" % src)
		failures += 1
	print("source tower_fire=%s" % src)

	# 5. brief 含 prompt
	var b: Dictionary = bank.brief(&"tower_fire")
	if not b.has("prompt") or str(b["prompt"]).is_empty():
		print("FAIL 5: brief 缺 prompt")
		failures += 1

	# 6. generated_dir 指向游戏 assets
	if not str(bank.generated_dir()).contains("crystal_line"):
		print("FAIL 6: generated_dir 路径不对 %s" % bank.generated_dir())
		failures += 1

	if failures == 0:
		print("test_crystal_line_art_bank: ALL PASS")
		quit(0)
	else:
		print("test_crystal_line_art_bank: %d FAILURE(S)" % failures)
		quit(1)
