extends RefCounted
## 农场示例的内存翻译表(中/英)+ 取名 helper。用 add_translation 现建现加(免 .po 编辑器导入)。
## 覆盖 HUD/菜单/面板 chrome + 季节/天气/作物名;数据驱动内容(商店物品名、任务标题)沿用 .tres
## 原文(演示聚焦"UI 可切语言")。CoreKit.i18n 切 locale 自动持久化(Settings section "locale")。

const ZH := {
	"HUD_WEATHER": "天气", "HUD_GOLD": "金币", "HUD_ENERGY": "体力",
	"HUD_SEED": "选中", "HUD_SEED_HINT": "(Q 切换)", "HUD_OFFSEASON": "[非当季]",
	"SEASON_spring": "春", "SEASON_summer": "夏", "SEASON_fall": "秋", "SEASON_winter": "冬",
	"WEATHER_sunny": "晴天", "WEATHER_rainy": "下雨",
	"CROP_turnip": "白萝卜", "CROP_parsnip": "防风草", "CROP_potato": "土豆", "CROP_pumpkin": "南瓜",
	"MENU_TITLE": "菜单  (↑↓ 选,J 确认,Esc 关闭)",
	"MENU_SAVE": "存档", "MENU_LOAD": "读档", "MENU_CONTINUE": "继续", "MENU_SETTINGS": "设置",
	"MENU_SAVED": "已存档", "MENU_LOADED": "已读档", "MENU_NOSAVE": "无存档",
	"SET_TITLE": "设置  (↑↓ 选,J 切换,Esc 关闭)", "SET_LANG": "语言",
	"SET_VOL_MASTER": "主音量", "SET_VOL_MUSIC": "音乐", "SET_VOL_SFX": "音效", "SET_REBIND": "按键",
	"INV_TITLE": "背包  (I 关闭)", "INV_EMPTY": "(空)",
	"SHOP_TITLE": "商店  (↑↓ 选,J 买/卖,P 关闭)",
	"LOG_TITLE": "任务 / 成就  (L 关闭)",
	"KEY_UP": "上", "KEY_DOWN": "下", "KEY_LEFT": "左", "KEY_RIGHT": "右",
	"KEY_USE": "用工具", "KEY_SLEEP": "睡觉", "KEY_SEED": "切种子",
}

const EN := {
	"HUD_WEATHER": "Weather", "HUD_GOLD": "Gold", "HUD_ENERGY": "Energy",
	"HUD_SEED": "Seed", "HUD_SEED_HINT": "(Q cycle)", "HUD_OFFSEASON": "[off-season]",
	"SEASON_spring": "Spring", "SEASON_summer": "Summer", "SEASON_fall": "Fall", "SEASON_winter": "Winter",
	"WEATHER_sunny": "Sunny", "WEATHER_rainy": "Rainy",
	"CROP_turnip": "Turnip", "CROP_parsnip": "Parsnip", "CROP_potato": "Potato", "CROP_pumpkin": "Pumpkin",
	"MENU_TITLE": "Menu  (Up/Down select, J confirm, Esc close)",
	"MENU_SAVE": "Save", "MENU_LOAD": "Load", "MENU_CONTINUE": "Continue", "MENU_SETTINGS": "Settings",
	"MENU_SAVED": "Saved", "MENU_LOADED": "Loaded", "MENU_NOSAVE": "No save",
	"SET_TITLE": "Settings  (Up/Down select, J toggle, Esc close)", "SET_LANG": "Language",
	"SET_VOL_MASTER": "Master", "SET_VOL_MUSIC": "Music", "SET_VOL_SFX": "SFX", "SET_REBIND": "Keys",
	"INV_TITLE": "Bag  (I close)", "INV_EMPTY": "(empty)",
	"SHOP_TITLE": "Shop  (Up/Down select, J buy/sell, P close)",
	"LOG_TITLE": "Quests / Achievements  (L close)",
	"KEY_UP": "Up", "KEY_DOWN": "Down", "KEY_LEFT": "Left", "KEY_RIGHT": "Right",
	"KEY_USE": "Use tool", "KEY_SLEEP": "Sleep", "KEY_SEED": "Cycle seed",
}


## 建两份内存 Translation 并注册进 CoreKit.i18n(幂等:同 locale 再 add 只是叠加同键覆盖)。
static func install() -> void:
	_add("zh", ZH)
	_add("en", EN)


static func _add(locale: String, msgs: Dictionary) -> void:
	var tr := Translation.new()
	tr.locale = locale
	for k in msgs:
		tr.add_message(k, msgs[k])
	CoreKit.i18n.add_translation(tr)


## 作物名:优先 CROP_<id> 译文,缺则回退 def.display_name(.tres 原文)。
static func crop_name(reg, crop_id) -> String:
	var key := "CROP_" + String(crop_id)
	if CoreKit.i18n.has_translation(key):
		return CoreKit.i18n.t(key)
	var d = reg.get_def_or(&"crop", crop_id, null)
	return d.display_name if d != null else String(crop_id)
