class_name CrystalArtBank
extends RefCounted
## 《晶核防线》美术接缝 + 可烘焙基线。
## 三级: assets/<key>.png → assets/generated/<key>.png → _make_image()

const ASSET_DIR := "res://game/crystal_line/assets"
const GENERATED_SUBDIR := "generated"
const ICON_SIZE := 48

## key → 强调色(对齐愿景一页纸配色)
const PALETTE := {
	&"tower_fire": Color("e67e22"),
	&"tower_ice": Color("4fc3f7"),
	&"enemy": Color("c0392b"),
	&"core": Color("e74c5e"),
	&"path": Color("3d4a6b"),
	&"cell": Color("243056"),
	&"gold": Color("f1c40f"),
}
const DEFAULT_COLOR := Color("9aa0a6")

var _cache: Dictionary = {}


func texture_for(key: StringName, size: int = ICON_SIZE) -> Texture2D:
	var ck := "%s@%d" % [key, size]
	if _cache.has(ck):
		return _cache[ck]
	var tex := _load_first([_real_path(key), _baked_path(key)])
	if tex == null:
		tex = ImageTexture.create_from_image(_make_image(key, size))
	_cache[ck] = tex
	return tex


func source_for(key: StringName) -> String:
	if ResourceLoader.exists(_real_path(key)):
		return "asset"
	if ResourceLoader.exists(_baked_path(key)):
		return "baked"
	return "procedural"


func color_for(key: StringName) -> Color:
	return PALETTE.get(key, DEFAULT_COLOR)


func _real_path(key: StringName) -> String:
	return "%s/%s.png" % [ASSET_DIR, key]


func _baked_path(key: StringName) -> String:
	return "%s/%s.png" % [generated_dir(), key]


func _load_first(paths: Array) -> Texture2D:
	for p in paths:
		if ResourceLoader.exists(p):
			var r = load(p)
			if r is Texture2D:
				return r
	return null


func generated_dir() -> String:
	return "%s/%s" % [ASSET_DIR, GENERATED_SUBDIR]


func bake_keys() -> Array:
	return PALETTE.keys()


func bake_image(key: StringName) -> Image:
	return _make_image(key, ICON_SIZE)


func brief(key: StringName) -> Dictionary:
	var c := color_for(key)
	var shape := "圆角棋子图标"
	match key:
		&"tower_fire":
			shape = "火塔:圆盘底座+中心火焰三角,暖橙"
		&"tower_ice":
			shape = "冰塔:圆盘底座+中心菱形,冰蓝"
		&"enemy":
			shape = "向下裂隙爬虫:三角/菱形红体"
		&"core":
			shape = "底部晶核:脉动红宝石方晶"
		&"path":
			shape = "裂隙路径地砖"
		&"cell":
			shape = "可建造深色格子"
		&"gold":
			shape = "金币 UI 圆片"
	return {
		"key": key,
		"size": "%dx%d" % [ICON_SIZE, ICON_SIZE],
		"color": "#" + c.to_html(false),
		"prompt": "手游竖屏塔防 UI 图标 <%s>,主色 #%s,%s,几何低多边形,清晰剪影,透明底" % [
			key, c.to_html(false), shape],
	}


## 确定性占位:径向圆盘;塔类加中心符号以承载「棋子」形状语言。
func _make_image(key: StringName, size: int) -> Image:
	var col := color_for(key)
	var inner := col.lightened(0.35)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rad := size * 0.5
	var c := size * 0.5
	for y in size:
		for x in size:
			var dx := (x + 0.5) - c
			var dy := (y + 0.5) - c
			var d := sqrt(dx * dx + dy * dy)
			if d <= rad - 1.0:
				var t := clampf(d / rad, 0.0, 1.0)
				img.set_pixel(x, y, col.lerp(inner, 1.0 - t))
			elif d <= rad:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0 - (d - (rad - 1.0))))
	# 中心符号(形状语言,不是纯色块)
	match String(key):
		"tower_fire":
			_draw_tri(img, size, Color.WHITE)
		"tower_ice":
			_draw_diamond(img, size, Color.WHITE)
		"enemy":
			_draw_tri_down(img, size, Color("2c0a0a"))
		"core":
			_draw_square(img, size, Color("fff0f0"))
		"gold":
			_draw_diamond(img, size, Color("fff8dc"))
	return img


func _draw_tri(img: Image, size: int, col: Color) -> void:
	var mid := size / 2
	var top := size / 4
	var bot := size * 3 / 4
	for y in range(top, bot):
		var w := int(float(y - top) / float(bot - top) * float(size / 4))
		for x in range(mid - w, mid + w + 1):
			if x >= 0 and x < size:
				img.set_pixel(x, y, col)


func _draw_tri_down(img: Image, size: int, col: Color) -> void:
	var mid := size / 2
	var top := size / 4
	var bot := size * 3 / 4
	for y in range(top, bot):
		var w := int(float(bot - y) / float(bot - top) * float(size / 4))
		for x in range(mid - w, mid + w + 1):
			if x >= 0 and x < size:
				img.set_pixel(x, y, col)


func _draw_diamond(img: Image, size: int, col: Color) -> void:
	var mid := size / 2
	var r := size / 5
	for y in range(mid - r, mid + r + 1):
		var w := r - absi(y - mid)
		for x in range(mid - w, mid + w + 1):
			if x >= 0 and x < size and y >= 0 and y < size:
				img.set_pixel(x, y, col)


func _draw_square(img: Image, size: int, col: Color) -> void:
	var m := size / 3
	for y in range(m, size - m):
		for x in range(m, size - m):
			img.set_pixel(x, y, col)
