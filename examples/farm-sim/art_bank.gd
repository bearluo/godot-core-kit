extends RefCounted
## 美术接缝(P5)。程序化生成全部贴图(瓦片/作物/角色/物件/粒子点),缓存,零二进制资产——对标
## audio_bank.gd 的程序化 SFX。取图接缝 tex(key):**先查 assets/<key>.png(真素材优先),否则程序化**;
## renderer 只认逻辑 key、不认来源。真素材(如 Sprout Lands)按 assets/README.md 约定命名丢进去,零改代码生效。
## headless 安全:ImageTexture/AtlasTexture/CPUParticles2D 在 dummy 驱动下均正常创建(已探针验证)。

const TILE := 32
const ASSETS_DIR := "res://examples/farm-sim/assets/"

static var _cache: Dictionary = {}


## 取贴图:真素材(assets/<key>.png)优先,否则程序化生成;结果缓存。
static func tex(key: StringName) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var t: Texture2D = _load_asset(key)
	if t == null:
		t = _generate(key)
	_cache[key] = t
	return t


static func clear_cache() -> void:
	_cache.clear()


static func _load_asset(key: StringName) -> Texture2D:
	var path := ASSETS_DIR + String(key) + ".png"
	if ResourceLoader.exists(path):
		var r = load(path)
		if r is Texture2D:
			return r
	return null


static func _generate(key: StringName) -> Texture2D:
	match key:
		&"tile_grass":
			return _tile(Color(0.36, 0.6, 0.26), "grass")
		&"tile_tilled":
			return _tile(Color(0.55, 0.36, 0.22), "furrow")
		&"tile_watered":
			return _tile(Color(0.34, 0.22, 0.13), "wet")
		&"crop":
			return _crop_tex()
		_:
			return _fallback()


# --- 程序化生成器(纯 Image 像素,确定性:用坐标哈希而非 RNG)---

static func _tile(base: Color, style: String) -> Texture2D:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	img.fill(base)
	for y in range(TILE):
		for x in range(TILE):
			var h := (x * 7 + y * 13 + x * y) % 11
			if style == "grass":
				if h == 0:
					img.set_pixel(x, y, base.lightened(0.12))
				elif h == 3:
					img.set_pixel(x, y, base.darkened(0.10))
			elif style == "furrow":
				if y % 6 == 0:
					img.set_pixel(x, y, base.darkened(0.20))
			elif style == "wet":
				if y % 6 == 0:
					img.set_pixel(x, y, base.darkened(0.16))
				elif h == 0:
					img.set_pixel(x, y, base.lerp(Color(0.3, 0.45, 0.7), 0.45))   # 水光
	_edge(img, base.darkened(0.30))
	return ImageTexture.create_from_image(img)


static func _crop_tex() -> Texture2D:
	# 近白的叶片剪影(透明底);view 用 modulate 把它染成 绿→金 并按生长比例缩放。
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(14, 28):                     # 茎
		img.set_pixel(16, y, Color(0.88, 0.95, 0.82))
		img.set_pixel(15, y, Color(0.82, 0.9, 0.78))
	_disc(img, 16, 13, 6, Color(0.95, 1.0, 0.9))
	_disc(img, 10, 18, 4, Color(0.9, 0.98, 0.85))
	_disc(img, 22, 18, 4, Color(0.9, 0.98, 0.85))
	return ImageTexture.create_from_image(img)


static func _fallback() -> Texture2D:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 1))   # 品红醒目,提示缺 key
	return ImageTexture.create_from_image(img)


# --- 像素 helper ---

## 描四边(顶/左深,底/右浅),做出瓦片轻立体感。
static func _edge(img: Image, color: Color) -> void:
	for i in range(TILE):
		img.set_pixel(i, 0, color)
		img.set_pixel(0, i, color)
		img.set_pixel(i, TILE - 1, color.lerp(Color(1, 1, 1), 0.25))
		img.set_pixel(TILE - 1, i, color.lerp(Color(1, 1, 1), 0.25))


## 填实心圆(cx,cy 圆心,r 半径)。
static func _disc(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x >= 0 and y >= 0 and x < TILE and y < TILE:
				var dx := x - cx
				var dy := y - cy
				if dx * dx + dy * dy <= r * r:
					img.set_pixel(x, y, color)
