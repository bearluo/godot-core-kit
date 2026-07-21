class_name FortuneArtBank
extends RefCounted
## 程序化「美术接缝」:UI 图标/贴图统一经此取。优先加载 assets/<key>.png 真素材(零改代码 drop-in),
## 缺素材时按房间调色板确定性生成 ImageTexture 兜底。纯 Image 运算,headless 可用,故可进 kit 门测试。
##
## 约定同 farm-sim art_bank:真素材文件名 = key(如 darts.png),丢进 assets/ 即自动顶替程序化图,
## 无需改任何代码。source_for() 指认当前解析来源(asset / procedural)。

const ASSET_DIR := "res://examples/fortune-mill/assets"
const ICON_SIZE := 48

## 七房强调色(房间辨识 + 图标底色)。key 对齐 i18n 的 room_* 后缀与 world 列。
const PALETTE := {
	&"darts":    Color("d94f4f"),   # 红
	&"lotto":    Color("f2b134"),   # 金
	&"pachinko": Color("4f9dd9"),   # 蓝
	&"sushi":    Color("6fbf5f"),   # 绿
	&"gacha":    Color("b06fd9"),   # 紫
	&"meta":     Color("d97fae"),   # 粉
	&"ach":      Color("e6c34d"),   # 琥珀
}
const DEFAULT_COLOR := Color("9aa0a6")

var _cache: Dictionary = {}   # "key@size" -> Texture2D


## 取 key 对应贴图:先真素材(drop-in)后程序化兜底,结果缓存。size 仅影响程序化图。
func texture_for(key: StringName, size: int = ICON_SIZE) -> Texture2D:
	var ck := "%s@%d" % [key, size]
	if _cache.has(ck):
		return _cache[ck]
	var tex := _load_asset(key)
	if tex == null:
		tex = _make_icon(key, size)
	_cache[ck] = tex
	return tex


## 某 key 的真素材投放路径(文档/测试指认接缝;把此路径的 png 丢进去即自动顶替)。
func asset_path(key: StringName) -> String:
	return "%s/%s.png" % [ASSET_DIR, key]


## key 的强调色(房间辨识用;UI 面板边框/图标底取此上色)。未登记 key 取 DEFAULT_COLOR。
func color_for(key: StringName) -> Color:
	return PALETTE.get(key, DEFAULT_COLOR)


## 当前解析来源:真素材存在返 "asset",否则 "procedural"(可断言接缝走向)。
func source_for(key: StringName) -> String:
	return "asset" if ResourceLoader.exists(asset_path(key)) else "procedural"


func _load_asset(key: StringName) -> Texture2D:
	var p := asset_path(key)
	if ResourceLoader.exists(p):
		var r = load(p)
		if r is Texture2D:
			return r
	return null


## 程序化筹码图标:房间强调色径向渐变圆盘 + 抗锯齿边,确定性(同 key 同图)。零素材。
func _make_icon(key: StringName, size: int) -> ImageTexture:
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
				var t := clampf(d / rad, 0.0, 1.0)   # 近中心更亮
				img.set_pixel(x, y, col.lerp(inner, 1.0 - t))
			elif d <= rad:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0 - (d - (rad - 1.0))))
	return ImageTexture.create_from_image(img)
