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
		&"player_down_0":
			return _player_tex("down", 0)
		&"player_down_1":
			return _player_tex("down", 1)
		&"player_up_0":
			return _player_tex("up", 0)
		&"player_up_1":
			return _player_tex("up", 1)
		&"player_left_0":
			return _player_tex("left", 0)
		&"player_left_1":
			return _player_tex("left", 1)
		&"player_right_0":
			return _player_tex("right", 0)
		&"player_right_1":
			return _player_tex("right", 1)
		&"npc":
			return _npc_tex()
		&"bed":
			return _bed_tex()
		&"shop_sign":
			return _shop_sign_tex()
		&"door":
			return _door_tex()
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


## 玩家 24² 小人:头 + 躯干 + 两腿(踏步帧交替抬腿)+ 朝向标记。透明底。
static func _player_tex(dir: String, frame: int) -> Texture2D:
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var skin := Color(0.96, 0.82, 0.66)
	var shirt := Color(0.86, 0.83, 0.62)
	var dark := Color(0.35, 0.3, 0.22)
	var l1y := 19 if frame == 0 else 20      # 踏步:两腿一前一后
	var l2y := 20 if frame == 0 else 19
	_rect(img, 8, l1y, 11, 23, dark)
	_rect(img, 13, l2y, 16, 23, dark)
	_rect(img, 7, 11, 17, 19, shirt)         # 躯干
	_disc(img, 12, 7, 5, skin)               # 头
	match dir:                               # 朝向标记(深色)
		"down":
			_rect(img, 10, 8, 14, 9, dark)
		"up":
			_rect(img, 10, 4, 14, 5, dark)
		"left":
			_rect(img, 7, 6, 9, 8, dark)
		"right":
			_rect(img, 15, 6, 17, 8, dark)
	return ImageTexture.create_from_image(img)


## NPC 24² 小人(蓝衣,区别于玩家)。
static func _npc_tex() -> Texture2D:
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_rect(img, 8, 19, 11, 23, Color(0.25, 0.2, 0.3))
	_rect(img, 13, 19, 16, 23, Color(0.25, 0.2, 0.3))
	_rect(img, 7, 11, 17, 19, Color(0.4, 0.52, 0.82))   # 蓝衣
	_disc(img, 12, 7, 5, Color(0.95, 0.82, 0.66))
	_rect(img, 10, 8, 14, 9, Color(0.2, 0.2, 0.3))      # 脸朝下
	return ImageTexture.create_from_image(img)


## 农舍床 48×64:木框 + 被褥 + 枕头。
static func _bed_tex() -> Texture2D:
	var img := Image.create(48, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_rect(img, 2, 2, 45, 61, Color(0.5, 0.32, 0.2))
	_rect(img, 5, 6, 42, 57, Color(0.75, 0.42, 0.42))
	_rect(img, 7, 8, 40, 22, Color(0.92, 0.9, 0.86))
	return ImageTexture.create_from_image(img)


## 小镇商店牌 72×56:牌面 + 顶边 + 柱。
static func _shop_sign_tex() -> Texture2D:
	var img := Image.create(72, 56, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_rect(img, 4, 4, 67, 40, Color(0.72, 0.6, 0.3))
	_rect(img, 4, 4, 67, 8, Color(0.55, 0.42, 0.2))
	_rect(img, 32, 40, 39, 55, Color(0.4, 0.3, 0.18))
	return ImageTexture.create_from_image(img)


## 门 40²(近白,door.gd 用 modulate 上各门颜色)+ 门把。
static func _door_tex() -> Texture2D:
	var img := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_rect(img, 3, 3, 36, 36, Color(0.95, 0.95, 0.95))
	_rect(img, 3, 3, 36, 7, Color(0.75, 0.75, 0.75))
	_disc(img, 30, 20, 2, Color(1, 1, 0.7))
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


## 填实心矩形(x0,y0..x1,y1 含端点,越界自动裁)。
static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(maxi(0, y0), mini(h, y1 + 1)):
		for x in range(maxi(0, x0), mini(w, x1 + 1)):
			img.set_pixel(x, y, color)


## 填实心圆(cx,cy 圆心,r 半径;按图像实际尺寸裁边)。
static func _disc(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x >= 0 and y >= 0 and x < w and y < h:
				var dx := x - cx
				var dy := y - cy
				if dx * dx + dy * dy <= r * r:
					img.set_pixel(x, y, color)
