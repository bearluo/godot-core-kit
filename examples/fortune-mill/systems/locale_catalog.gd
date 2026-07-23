class_name LocaleCatalog
extends RefCounted
## fortune-mill 中英双语目录(example 内构建;经 kit CoreKit.i18n / LocaleManager 使用)。
##
## 代码内建 en/zh 两张 Translation 表(避免依赖编辑器导出的 .translation 二进制资源,
## 同 AchievementCatalog 代码注册先例),经 i18n.add_translation 注册进全局 TranslationServer。
## key 用 "fortune.*" 命名空间;缺翻译告警由 kit LocaleManager.t() 负责(push_warning 去重)。
##
## 是游戏专有内容(实际文案),不反哺;字体回退与语言切换按钮在表现层(world.gd)接线。

const DEFAULT_LOCALE := "zh"

## en/zh 两语言的 key → 文案。两语言 key 对齐;缺某语言的某 key → t() 回退原 key + 告警。
const STRINGS := {
	"en": {
		"fortune.title": "Fortune Mill",
		"fortune.lang": "中文 / EN",
		"fortune.throw": "Throw",
		"fortune.enter_darts": "Enter Darts",
		"fortune.scratch": "Scratch",
		"fortune.drop": "Drop",
		"fortune.craft": "Craft",
		"fortune.pull": "Pull",
		"fortune.ascend": "Ascend (NG+)",
		"fortune.room_darts": "Darts (gold / Verminous)",
		"fortune.room_lotto": "Lotto (money / Gorgon)",
		"fortune.room_pachinko": "Pachinko (tickets / Rimmington)",
		"fortune.room_sushi": "Sushi (ribbons / Hivemind)",
		"fortune.room_gacha": "Gacha (stuffing / Executor)",
		"fortune.room_meta": "Meta (NG+ / Lethal)",
		"fortune.room_ach": "Achievements (51)",
	},
	"zh": {
		"fortune.title": "财富磨坊",
		"fortune.lang": "中文 / EN",
		"fortune.throw": "投镖",
		"fortune.enter_darts": "进入飞镖房",
		"fortune.scratch": "刮卡",
		"fortune.drop": "落球",
		"fortune.craft": "开始制作",
		"fortune.pull": "抽扭蛋",
		"fortune.ascend": "进下一周目",
		"fortune.room_darts": "飞镖房 (gold / Verminous)",
		"fortune.room_lotto": "刮刮乐房 (money / Gorgon)",
		"fortune.room_pachinko": "柏青哥房 (tickets / Rimmington)",
		"fortune.room_sushi": "寿司房 (ribbons / Hivemind)",
		"fortune.room_gacha": "扭蛋房 (stuffing / Executor)",
		"fortune.room_meta": "元进度 (NG+ / Lethal)",
		"fortune.room_ach": "成就 (51 条)",
	},
}


## 把 en/zh 两表注册进 i18n(duck-typed:kit LocaleManager 或任何有 add_translation 的对象)。
## 返回注册的语言数。
static func apply(i18n) -> int:
	var count := 0
	for locale in STRINGS:
		var tr := Translation.new()
		tr.locale = locale
		var table: Dictionary = STRINGS[locale]
		for key in table:
			tr.add_message(key, table[key])
		i18n.add_translation(tr)
		count += 1
	return count
