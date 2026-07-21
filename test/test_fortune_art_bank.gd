extends SceneTree
## FortuneArtBank 程序化美术接缝 headless 断言。
## 运行:godot --headless --path . -s res://test/test_fortune_art_bank.gd
## 重点:① 每个房间 key 生成非空 Texture2D 且尺寸 = 请求尺寸 ② 缓存返回同一实例
##       ③ 不同房间 key → 中心主色不同(房间可辨识) ④ asset_path 指向 drop-in 接缝路径
##       ⑤ 仓库未投放真素材 → source_for=procedural(兜底路径) ⑥ 未登记 key 用默认色兜底不崩。
## FortuneArtBank 为 example 本地类、不引用门面,可顶层 preload(同 Currency/LocaleCatalog)。
const FortuneArtBank := preload("res://examples/fortune-mill/gfx/art_bank.gd")


func _initialize() -> void:
	var failures := 0
	var ab = FortuneArtBank.new()

	# 1. 每个房间 key 生成非空 Texture2D,尺寸 = 请求尺寸
	var keys := [&"darts", &"lotto", &"pachinko", &"sushi", &"gacha", &"meta", &"ach"]
	for k in keys:
		var tex = ab.texture_for(k, 32)
		if tex == null or not (tex is Texture2D):
			print("FAIL 1: texture_for(%s) 应返回 Texture2D" % k); failures += 1
		elif tex.get_width() != 32 or tex.get_height() != 32:
			print("FAIL 1: texture_for(%s) 尺寸应 32x32,得 %dx%d" % [k, tex.get_width(), tex.get_height()]); failures += 1

	# 2. 缓存:同 key+size 返回同一实例
	if ab.texture_for(&"darts", 32) != ab.texture_for(&"darts", 32):
		print("FAIL 2: 同 key+size 应命中缓存返回同一实例"); failures += 1

	# 3. 不同房间 → 中心主色不同(取中心像素)
	var c_darts = ab.texture_for(&"darts", 32).get_image().get_pixel(16, 16)
	var c_sushi = ab.texture_for(&"sushi", 32).get_image().get_pixel(16, 16)
	if c_darts.is_equal_approx(c_sushi):
		print("FAIL 3: 不同房间中心色应不同(darts≠sushi)"); failures += 1

	# 4. asset_path 指向 drop-in 接缝:assets/<key>.png
	if ab.asset_path(&"darts") != "res://examples/fortune-mill/assets/darts.png":
		print("FAIL 4: asset_path 应指向 assets/<key>.png,得 %s" % ab.asset_path(&"darts")); failures += 1

	# 5. 仓库未投放真素材 → 全部走程序化兜底
	if ab.source_for(&"darts") != "procedural":
		print("FAIL 5: 无真素材时 source_for 应为 procedural"); failures += 1

	# 6. 未登记 key 用默认色兜底(不崩,仍出图)
	var fallback = ab.texture_for(&"__unknown__", 16)
	if fallback == null or fallback.get_width() != 16:
		print("FAIL 6: 未登记 key 应仍生成默认色兜底图"); failures += 1

	if failures == 0:
		print("test_fortune_art_bank: ALL PASS")
		quit(0)
	else:
		print("test_fortune_art_bank: %d FAILURE(S)" % failures)
		quit(1)
