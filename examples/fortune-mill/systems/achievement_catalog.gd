class_name AchievementCatalog
extends RefCounted
## 本作 51 条成就的定义目录:代码构建 AchievementDef → 注册进 KitDataRegistry 的 &"achievement" 类。
## 为何代码生成而非 51 个 .tres:成就高度系统化(17 靶心档 + 5 守卫 + 一批里程碑),
## 逐条建 def 比逐个手搓 .tres 可读得多;真要覆盖/新增某条,往 data/achievements/ 丢同 id 的
## .tres 经 registry.load_dir(&"achievement", ...) 覆盖即可(drop-in,零改代码)。
##
## 每条声明式:{id, title, desc, stat_key, threshold}——KitStats 到阈值即由 KitAchievements 解锁。
## 统计键(stat_key)由 [[fortune_state]] 在命令入口喂食;判定与去重见 [[kit_achievements]]。

const TYPE := &"achievement"

## 飞镖 17 档靶心倍率(镜像 DartsRoom.BULLSEYE,仅用于成就标题展示)。
const BULLSEYE := [1.5, 2.0, 3.0, 5.0, 8.0, 12.0, 20.0, 30.0, 50.0, 80.0, 125.0, 200.0, 300.0, 500.0, 800.0, 1200.0, 2500.0]

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

	# --- 17 档靶心首命中(dart_tier_<n> >= 1)---
	for i in range(1, 18):
		out.append(_mk(
			StringName("dart_tier_%02d" % i),
			"靶心 T%d (×%s)" % [i, str(BULLSEYE[i - 1])],
			"首次命中第 %d 档靶心" % i,
			StringName("dart_tier_%d" % i), 1.0, &"bullseye"))

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
