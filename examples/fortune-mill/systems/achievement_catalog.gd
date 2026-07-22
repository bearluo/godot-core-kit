class_name AchievementCatalog
extends RefCounted
## 本作 51 条成就的定义目录:代码构建 AchievementDef → 注册进 KitDataRegistry 的 &"achievement" 类。
## 为何代码生成而非 51 个 .tres:成就高度系统化(17 转盘奖区 + 5 守卫 + 一批里程碑),
## 逐条建 def 比逐个手搓 .tres 可读得多;真要覆盖/新增某条,往 data/achievements/ 丢同 id 的
## .tres 经 registry.load_dir(&"achievement", ...) 覆盖即可(drop-in,零改代码)。
##
## 每条声明式:{id, title, desc, stat_key, threshold}——KitStats 到阈值即由 KitAchievements 解锁。
## 统计键(stat_key)由 [[fortune_state]] 在命令入口喂食;判定与去重见 [[kit_achievements]]。

const TYPE := &"achievement"

## 5 房 → 守卫名(贿赂成就用)。
const GUARDS := [
	[&"darts", "Verminous"], [&"lotto", "Gorgon"], [&"pachinko", "Rimmington"],
	[&"sushi", "Hivemind"], [&"gacha", "Executor"],
]


## 构建并注册全部成就 def 进 reg,返回条数(应为 51)。
static func build(reg) -> int:
	var defs := _defs()
	for d in defs:
		reg.register(TYPE, d.id, d)
	return defs.size()


static func _mk(id: StringName, title: String, desc: String, stat_key: StringName, threshold: float, category: StringName) -> AchievementDef:
	var a := AchievementDef.new()
	a.id = id
	a.title = title
	a.desc = desc
	a.stat_key = stat_key
	a.threshold = threshold
	a.category = category
	return a


static func _defs() -> Array:
	var out: Array = []

	# --- 17 转盘奖区成就(dart_seg_<name> 计数;命中不同难度扇区累计到阈值即解锁)---
	# 每条 [id 后缀, 扇区名, 阈值, 标题, 描述]。stat_key = dart_seg_<扇区名>,由 _track_throw 喂食。
	var seg_ach := [
		["jackpot_1",   &"jackpot", 1.0,   "命运头奖",   "首次扎中 JACKPOT 奖区(×500)"],
		["jackpot_10",  &"jackpot", 10.0,  "轮盘之宠",   "累计扎中 JACKPOT 10 次"],
		["jackpot_50",  &"jackpot", 50.0,  "头奖收割",   "累计扎中 JACKPOT 50 次"],
		["jackpot_200", &"jackpot", 200.0, "命运主宰",   "累计扎中 JACKPOT 200 次"],
		["x100_1",      &"x100",    1.0,   "百倍风暴",   "首次扎中 ×100 奖区"],
		["x100_10",     &"x100",    10.0,  "百倍常客",   "累计扎中 ×100 奖区 10 次"],
		["x100_100",    &"x100",    100.0, "百倍成瘾",   "累计扎中 ×100 奖区 100 次"],
		["x20a_1",      &"x20a",    1.0,   "廿倍!",      "首次扎中上侧 ×20 奖区"],
		["x20a_50",     &"x20a",    50.0,  "廿倍熟手",   "累计扎中上侧 ×20 奖区 50 次"],
		["x20b_1",      &"x20b",    1.0,   "廿倍·再来",  "首次扎中下侧 ×20 奖区"],
		["x20b_50",     &"x20b",    50.0,  "廿倍双修",   "累计扎中下侧 ×20 奖区 50 次"],
		["x5_1",        &"x5",      1.0,   "五倍奖区",   "首次扎中 ×5 奖区"],
		["x5_200",      &"x5",      200.0, "稳扎稳打",   "累计扎中 ×5 奖区 200 次"],
		["x2a_1",       &"x2a",     1.0,   "翻倍入账",   "首次扎中上侧 ×2 奖区"],
		["x2b_1",       &"x2b",     1.0,   "翻倍·彼岸",  "首次扎中下侧 ×2 奖区"],
		["vermin_1",    &"vermin",  1.0,   "喂了硕鼠",   "飞镖扎进 vermin 没收区(白扔一镖)"],
		["vermin_25",   &"vermin",  25.0,  "散财童子",   "累计 25 次扎进 vermin 没收区"],
	]
	for e in seg_ach:
		out.append(_mk(
			StringName("seg_%s" % e[0]),
			e[3], e[4],
			StringName("dart_seg_%s" % String(e[1])), float(e[2]), &"wheel"))

	# --- 5 守卫贿赂(guard_<room> >= 1)---
	for g in GUARDS:
		out.append(_mk(
			StringName("guard_%s" % g[0]),
			"贿赂 %s" % g[1],
			"贿赂守卫 %s,该房通关" % g[1],
			StringName("guard_%s" % g[0]), 1.0, &"guard"))

	# --- 累计产出里程碑(total_gold)---
	out.append(_mk(&"gold_1e3", "小有积蓄", "累计产出 1,000 gold", &"total_gold", 1_000.0, &"milestone"))
	out.append(_mk(&"gold_1e5", "腰缠万贯", "累计产出 100,000 gold", &"total_gold", 100_000.0, &"milestone"))
	out.append(_mk(&"gold_1e7", "富可敌国", "累计产出 10,000,000 gold", &"total_gold", 10_000_000.0, &"milestone"))
	out.append(_mk(&"gold_1e9", "富甲天下", "累计产出 1,000,000,000 gold", &"total_gold", 1_000_000_000.0, &"milestone"))

	# --- 单次最大产出(max_payout)---
	out.append(_mk(&"payout_1e2", "一镖百金", "单次投镖产出 ≥ 100 gold", &"max_payout", 100.0, &"milestone"))
	out.append(_mk(&"payout_1e4", "一镖万金", "单次投镖产出 ≥ 10,000 gold", &"max_payout", 10_000.0, &"milestone"))
	out.append(_mk(&"payout_1e6", "一镖百万", "单次投镖产出 ≥ 1,000,000 gold", &"max_payout", 1_000_000.0, &"milestone"))

	# --- 累计投镖数(dart_throws)---
	out.append(_mk(&"throws_100", "熟能生巧", "累计投镖 100 次", &"dart_throws", 100.0, &"milestone"))
	out.append(_mk(&"throws_1k", "百发千中", "累计投镖 1,000 次", &"dart_throws", 1_000.0, &"milestone"))
	out.append(_mk(&"throws_10k", "镖不离手", "累计投镖 10,000 次", &"dart_throws", 10_000.0, &"milestone"))

	# --- NG+ 周目(ng_level)---
	out.append(_mk(&"ng_1", "轮回之始", "首次进入 NG+", &"ng_level", 1.0, &"meta"))
	out.append(_mk(&"ng_2", "二周目", "进入 NG++", &"ng_level", 2.0, &"meta"))
	out.append(_mk(&"ng_3", "无尽轮回", "进入 NG+3", &"ng_level", 3.0, &"meta"))

	# --- Lethal 速通完成(lethal_runs)---
	out.append(_mk(&"lethal_1", "亡命一搏", "完成一局 Lethal 速通", &"lethal_runs", 1.0, &"meta"))

	# --- JACKPOT 命中(jackpots)---
	out.append(_mk(&"jackpot_1", "头奖!", "首次刮出 JACKPOT", &"jackpots", 1.0, &"room"))
	out.append(_mk(&"jackpot_10", "手气爆棚", "累计 10 次 JACKPOT", &"jackpots", 10.0, &"room"))
	out.append(_mk(&"jackpot_100", "天选之人", "累计 100 次 JACKPOT", &"jackpots", 100.0, &"room"))

	# --- 扭蛋抽卡(gacha_pulls)---
	out.append(_mk(&"pull_1", "第一发", "首次抽扭蛋", &"gacha_pulls", 1.0, &"room"))
	out.append(_mk(&"pull_50", "扭蛋成瘾", "累计抽扭蛋 50 次", &"gacha_pulls", 50.0, &"room"))
	out.append(_mk(&"pull_500", "开箱大师", "累计抽扭蛋 500 次", &"gacha_pulls", 500.0, &"room"))

	# --- 寿司制作(sushi_crafts)---
	out.append(_mk(&"craft_1", "学徒寿司", "首次制作寿司", &"sushi_crafts", 1.0, &"room"))
	out.append(_mk(&"craft_25", "寿司匠人", "累计制作寿司 25 次", &"sushi_crafts", 25.0, &"room"))

	# --- 柏青哥落球(pachinko_drops)---
	out.append(_mk(&"drop_1", "初次落球", "首次落球", &"pachinko_drops", 1.0, &"room"))
	out.append(_mk(&"drop_100", "钢珠如雨", "累计落球 100 次", &"pachinko_drops", 100.0, &"room"))

	# --- 刮刮乐刮卡(lotto_scratches)---
	out.append(_mk(&"scratch_1", "手气如何", "首次刮卡", &"lotto_scratches", 1.0, &"room"))
	out.append(_mk(&"scratch_100", "刮卡狂魔", "累计刮卡 100 次", &"lotto_scratches", 100.0, &"room"))

	# --- 其余单条 ---
	out.append(_mk(&"dice_1", "掷骰", "首次掷骰触发 DICE", &"dice_rolls", 1.0, &"room"))
	out.append(_mk(&"recipe_1", "解锁菜谱", "首次解锁高级寿司配方", &"recipes_unlocked", 1.0, &"room"))
	out.append(_mk(&"prestige_1", "威望初现", "首次购买 NG+ 专属升级", &"prestige_bought", 1.0, &"meta"))

	return out
