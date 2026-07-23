class_name FortuneWheelLayout
extends RefCounted
## 命运转盘的几何 + 结算数学。全静态、无状态、纯 float 运算 → headless 可测。
## 奖励区版图分 5 档(T0..T4):加宽头奖(widen_zone)等级 = 布局档,逐档把头奖(★500)做大、
## 劫区(vermin)压缩、x100 扩张(其余档不变)。model(DartsRoom)与 view 都调此:
## view 只渲染当前档布局,权威结算在 DartsRoom.throw 里经此计算。

const AIM_ARC := 120.0      ## aim 0..1 映射到 ±AIM_ARC/2 的盘面角偏移(历史常量,保留)
const POWER_SWEET := 0.5    ## 力度甜点(命中所瞄档、不偏移、radial 2.0);上下对称便于越界落空
const POWER_SHIFT := 150.0  ## 力度偏离甜点的竖直偏移基数(度):实际偏移=本值/(1+aim_steady)
const FAN_STEP := 14.0      ## 扇形多镖每支相邻角距(°)
const AI_RADIAL := 1.5      ## AI/离线期望的平均径向加成(手动走真 radial_bonus)

## 基础奖励区布局(T0,top→bottom)。宽度=难度:越窄倍率越高;含一块 vermin 没收段。span 和 ≡ 360。
## 语义为「墙」而非转盘:aim(发射角)线性映射到本序列,不旋转。旧引用 SEGMENTS 仍可用(= 基础档 T0)。
const SEGMENTS := [
	{"name": &"x20a",    "span": 40.0, "mult": 20.0,  "vermin": false},
	{"name": &"x2a",     "span": 72.0, "mult": 2.0,   "vermin": false},
	{"name": &"x100",    "span": 30.0, "mult": 100.0, "vermin": false},
	{"name": &"jackpot", "span": 18.0, "mult": 500.0, "vermin": false},
	{"name": &"vermin",  "span": 40.0, "mult": 0.0,   "vermin": true},
	{"name": &"x5",      "span": 58.0, "mult": 5.0,   "vermin": false},
	{"name": &"x2b",     "span": 62.0, "mult": 2.0,   "vermin": false},
	{"name": &"x20b",    "span": 40.0, "mult": 20.0,  "vermin": false},
]

## 5 套奖励区布局(T0..T4)。同 8 档、同名/同倍率、span 和≡360;逐档头奖 18→66°、劫区 40→8°、
## x100 30→54°(x2a/x2b 相应缩,x20/x5 不动)。加宽头奖等级 t → LAYOUTS[clamp(t,0,TIER_MAX)]。
const LAYOUTS := [
	SEGMENTS,   # T0 = 基础
	[  # T1
		{"name": &"x20a",    "span": 40.0, "mult": 20.0,  "vermin": false},
		{"name": &"x2a",     "span": 67.0, "mult": 2.0,   "vermin": false},
		{"name": &"x100",    "span": 36.0, "mult": 100.0, "vermin": false},
		{"name": &"jackpot", "span": 30.0, "mult": 500.0, "vermin": false},
		{"name": &"vermin",  "span": 32.0, "mult": 0.0,   "vermin": true},
		{"name": &"x5",      "span": 58.0, "mult": 5.0,   "vermin": false},
		{"name": &"x2b",     "span": 57.0, "mult": 2.0,   "vermin": false},
		{"name": &"x20b",    "span": 40.0, "mult": 20.0,  "vermin": false},
	],
	[  # T2
		{"name": &"x20a",    "span": 40.0, "mult": 20.0,  "vermin": false},
		{"name": &"x2a",     "span": 62.0, "mult": 2.0,   "vermin": false},
		{"name": &"x100",    "span": 42.0, "mult": 100.0, "vermin": false},
		{"name": &"jackpot", "span": 42.0, "mult": 500.0, "vermin": false},
		{"name": &"vermin",  "span": 24.0, "mult": 0.0,   "vermin": true},
		{"name": &"x5",      "span": 58.0, "mult": 5.0,   "vermin": false},
		{"name": &"x2b",     "span": 52.0, "mult": 2.0,   "vermin": false},
		{"name": &"x20b",    "span": 40.0, "mult": 20.0,  "vermin": false},
	],
	[  # T3
		{"name": &"x20a",    "span": 40.0, "mult": 20.0,  "vermin": false},
		{"name": &"x2a",     "span": 57.0, "mult": 2.0,   "vermin": false},
		{"name": &"x100",    "span": 48.0, "mult": 100.0, "vermin": false},
		{"name": &"jackpot", "span": 54.0, "mult": 500.0, "vermin": false},
		{"name": &"vermin",  "span": 16.0, "mult": 0.0,   "vermin": true},
		{"name": &"x5",      "span": 58.0, "mult": 5.0,   "vermin": false},
		{"name": &"x2b",     "span": 47.0, "mult": 2.0,   "vermin": false},
		{"name": &"x20b",    "span": 40.0, "mult": 20.0,  "vermin": false},
	],
	[  # T4
		{"name": &"x20a",    "span": 40.0, "mult": 20.0,  "vermin": false},
		{"name": &"x2a",     "span": 52.0, "mult": 2.0,   "vermin": false},
		{"name": &"x100",    "span": 54.0, "mult": 100.0, "vermin": false},
		{"name": &"jackpot", "span": 66.0, "mult": 500.0, "vermin": false},
		{"name": &"vermin",  "span": 8.0,  "mult": 0.0,   "vermin": true},
		{"name": &"x5",      "span": 58.0, "mult": 5.0,   "vermin": false},
		{"name": &"x2b",     "span": 42.0, "mult": 2.0,   "vermin": false},
		{"name": &"x20b",    "span": 40.0, "mult": 20.0,  "vermin": false},
	],
]

const TIER_MAX := 4   ## LAYOUTS.size() - 1;加宽头奖封顶档


## 布局档 tier → 对应奖励区布局(封顶 TIER_MAX,越界安全钳制)。
static func layout_for(tier: int) -> Array:
	return LAYOUTS[clampi(tier, 0, TIER_MAX)]


## 某档布局里某段的中心角(°)。
static func center_of(seg_name: StringName, layout: Array = SEGMENTS) -> float:
	var acc := 0.0
	for s in layout:
		if s["name"] == seg_name:
			return acc + float(s["span"]) * 0.5
		acc += float(s["span"])
	return 0.0


## 某档布局里某段的宽度(°)。
static func span_of(seg_name: StringName, layout: Array = SEGMENTS) -> float:
	for s in layout:
		if s["name"] == seg_name:
			return float(s["span"])
	return 0.0


## jackpot 段中心角(°)。
static func jackpot_center(layout: Array = SEGMENTS) -> float:
	return center_of(&"jackpot", layout)


static func vermin_center(layout: Array = SEGMENTS) -> float:
	return center_of(&"vermin", layout)


## jackpot 半宽(°)。
static func jackpot_half_base(layout: Array = SEGMENTS) -> float:
	return span_of(&"jackpot", layout) * 0.5


## 命中角落在该布局哪个奖区。纯按 span 累积找带(加宽头奖 = 换更大头奖的布局,不再连续加宽)。
static func segment_at(angle_deg: float, layout: Array = SEGMENTS) -> Dictionary:
	var a := fposmod(angle_deg, 360.0)
	var acc := 0.0
	for s in layout:
		var a0 := acc; var a1 := acc + float(s["span"])
		if a >= a0 and a < a1:
			return {"name": s["name"], "mult": float(s["mult"]), "vermin": bool(s.get("vermin", false))}
		acc = a1
	# 边界兜底(a==360 之类)
	var last: Dictionary = layout[layout.size() - 1]
	return {"name": last["name"], "mult": float(last["mult"]), "vermin": bool(last.get("vermin", false))}


## AI/离线的期望倍率(按某档布局 span 加权;高档头奖大 → 期望更高)。
## ai_skill 0=近均匀(含 vermin 拖累),1=偏向高奖、避 vermin。
static func expected_mult(ai_skill: float, layout: Array = SEGMENTS) -> float:
	var s := clampf(ai_skill, 0.0, 1.0)
	# 均匀期望(按 span 加权,vermin=0 计入)
	var uniform := 0.0
	for seg in layout:
		uniform += (float(seg["span"]) / 360.0) * float(seg["mult"])
	# 高目标:偏向但不满命中 jackpot(用 x100 量级更稳,避免离散暴涨)
	var high := 100.0
	var e_seg: float = lerpf(uniform, high, s)
	return e_seg * AI_RADIAL


## 径向精度加成:盘心 2.0 → 边缘 1.0(r 归一化 0..1)。
static func radial_bonus(r: float) -> float:
	return lerpf(2.0, 1.0, clampf(r, 0.0, 1.0))


## (aim,power,steady) → 墙面落点 {r(离档心 0..1), a_off(命中墙面角 °), whiff(是否落空)}。纯确定性,无 RNG。
## a_off = aim 铺满 0..360(顶→底)减力度竖直偏移:超甜点→上移(a_off 减)、欠→下移(a_off 增);甜点=不偏移。
## 偏移幅度 = POWER_SHIFT/(1+steady):steady(aim_steady)越高偏移越小——等级低漂移大、等级高漂移少。
## a_off 超出 [0,360) 即落空(whiff)不计分——不夹紧、不回绕,飞出墙外就是没中。
static func landing(aim: float, power: float, steady: float = 0.0) -> Dictionary:
	var miss := power - POWER_SWEET
	var shift := POWER_SHIFT / (1.0 + maxf(0.0, steady))
	var a_off := clampf(aim, 0.0, 1.0) * 360.0 - miss * shift
	var r := clampf(absf(miss) / POWER_SWEET, 0.0, 1.0)
	return {"r": r, "a_off": a_off, "whiff": a_off < 0.0 or a_off >= 360.0}


## 能确定命中某布局某档的 aim 值(该档中心角 / 360)。用于 smoke / 测试 / view 预览。
static func aim_for(name: StringName, layout: Array = SEGMENTS) -> float:
	return center_of(name, layout) / 360.0


## n 支扇形多镖的角偏移(居中对称,和为 0)。
static func fan_offsets(n: int) -> Array:
	var out: Array = []
	var cnt := maxi(1, n)
	var start := -FAN_STEP * (float(cnt) - 1.0) * 0.5
	for i in cnt:
		out.append(start + FAN_STEP * float(i))
	return out
