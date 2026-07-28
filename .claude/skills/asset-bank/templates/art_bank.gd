class_name GameArtBank   # ← 重命名成你游戏的(如 FooArtBank)
extends RefCounted
## 「美术接缝」+ 可烘焙基线。取图统一经 texture_for(key),三级解析:
##   1) assets/<key>.png            真/AI 素材(手投,最高优先,零改代码 drop-in)
##   2) assets/generated/<key>.png  确定性烘焙基线(bake_assets.gd 产,提交进仓库)
##   3) 运行时 _make_image()        最后兜底(没烘焙过的新 key 也不崩)
## 生成逻辑集中在 _make_image(),bake(2)与 runtime(3)共用同一份 → 零漂移。
## 纯 Image 运算,headless 可用,故可进 kit 门测试。

const ASSET_DIR := "res://<game>/assets"      # ← 改成你游戏的 assets 路径
const GENERATED_SUBDIR := "generated"
const ICON_SIZE := 48

## key → 强调色(对象辨识 + 图标底色)。key 对齐你游戏里的动作/对象命名。
const PALETTE := {
	&"key_a": Color("d94f4f"),
	&"key_b": Color("4f9dd9"),
}
const DEFAULT_COLOR := Color("9aa0a6")

var _cache: Dictionary = {}   # "key@size" -> Texture2D
## 本次运行中被取用过的 key(死资源 / 幽灵 key 对账用,见 SKILL.md 第五节)
var _requested: Dictionary = {}


# ---- 接缝:取图(三级)----
func texture_for(key: StringName, size: int = ICON_SIZE) -> Texture2D:
	_requested[key] = true
	var ck := "%s@%d" % [key, size]
	if _cache.has(ck):
		return _cache[ck]
	var tex := _load_first([_real_path(key), _baked_path(key)])
	if tex == null:
		tex = ImageTexture.create_from_image(_make_image(key, size))
	_cache[ck] = tex
	return tex


## 冒烟测试对账用:跑完一段真实流程后,
##   bake_keys() 里没出现在这儿的 = 死资源;这儿有而 bake_keys() 没有的 = 幽灵 key。
## ⚠️ 取到 Texture2D ≠ 玩家看见了 —— 还要确认它真的被 draw_texture 出去
##    (绘制入口累加 drawn[key],冒烟里断言每个图 key 都出现过;见 SKILL.md 第五节)。
func requested_keys() -> Array:
	return _requested.keys()


## 当前解析来源:asset(真素材)/ baked(烘焙基线)/ procedural(运行时)。
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


# ---- 烘焙契约(bake_assets.gd 调用)----
func generated_dir() -> String:
	return "%s/%s" % [ASSET_DIR, GENERATED_SUBDIR]


func bake_keys() -> Array:
	return PALETTE.keys()


func bake_image(key: StringName) -> Image:
	return _make_image(key, ICON_SIZE)


func brief(key: StringName) -> Dictionary:
	var c := color_for(key)
	return {
		"key": key,
		"size": "%dx%d" % [ICON_SIZE, ICON_SIZE],
		"color": "#" + c.to_html(false),
		"prompt": "<%s> 图标,主色 #%s,风格 ___(照愿景填:形状语言 / 质感 / 描边)" % [key, c.to_html(false)],
	}


# ---- 确定性生成(bake 与 runtime 共用的唯一一份)----
## 房间强调色径向渐变圆盘 + 抗锯齿边,确定性(同 key 同图)。零素材。
## 换成你想要的占位外观时,只改这里,bake 与 runtime 一起变。
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
				var t := clampf(d / rad, 0.0, 1.0)   # 近中心更亮
				img.set_pixel(x, y, col.lerp(inner, 1.0 - t))
			elif d <= rad:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0 - (d - (rad - 1.0))))
	return img
