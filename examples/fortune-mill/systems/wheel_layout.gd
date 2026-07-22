class_name FortuneWheelLayout
extends RefCounted
## 命运转盘的几何 + 结算数学。全静态、无状态、纯 float 运算 → headless 可测。
## model(DartsRoom)与 view 都调此;view 只用来渲染,权威结算在 DartsRoom.throw 里经此计算。

## 扇区(顺时针,从 0° 起铺满 360°)。宽度=难度:越窄倍率越高;含一块 vermin 没收段。
const SEGMENTS := [
	{"name": &"jackpot", "span": 18.0, "mult": 500.0, "vermin": false},
	{"name": &"x2a",     "span": 72.0, "mult": 2.0,   "vermin": false},
	{"name": &"x20a",    "span": 40.0, "mult": 20.0,  "vermin": false},
	{"name": &"x5",      "span": 58.0, "mult": 5.0,   "vermin": false},
	{"name": &"vermin",  "span": 40.0, "mult": 0.0,   "vermin": true},
	{"name": &"x100",    "span": 30.0, "mult": 100.0, "vermin": false},
	{"name": &"x2b",     "span": 62.0, "mult": 2.0,   "vermin": false},
	{"name": &"x20b",    "span": 40.0, "mult": 20.0,  "vermin": false},
]

const AIM_ARC := 120.0      ## aim 0..1 映射到 ±AIM_ARC/2 的盘面角偏移
const POWER_SWEET := 0.6    ## 力度甜点(落盘心);偏离 → 落点外移
const FAN_STEP := 14.0      ## 扇形多镖每支相邻角距(°)
const AI_RADIAL := 1.5      ## AI/离线期望的平均径向加成(手动走真 radial_bonus)


## jackpot 段中心角(°)。
static func jackpot_center() -> float:
	return _center_of(&"jackpot")


static func vermin_center() -> float:
	return _center_of(&"vermin")


## jackpot 基础半宽(°)。
static func jackpot_half_base() -> float:
	return _span_of(&"jackpot") * 0.5


## 命中角落在哪个奖区。win_bonus(°)加宽 jackpot 命中带(以中心对称扩)。
## 语义:先判「加宽后的 jackpot 带」,否则回落基础扇区。
static func segment_at(angle_deg: float, win_bonus: float) -> Dictionary:
	var a := fposmod(angle_deg, 360.0)
	var jc := jackpot_center()
	var half := jackpot_half_base() + maxf(0.0, win_bonus) * 0.5
	if _arc_dist(a, jc) <= half:
		return {"name": &"jackpot", "mult": 500.0, "vermin": false}
	var acc := 0.0
	for s in SEGMENTS:
		var a0 := acc; var a1 := acc + float(s["span"])
		if a >= a0 and a < a1:
			return {"name": s["name"], "mult": float(s["mult"]), "vermin": bool(s.get("vermin", false))}
		acc = a1
	# 边界兜底(a==360 之类)
	var last: Dictionary = SEGMENTS[SEGMENTS.size() - 1]
	return {"name": last["name"], "mult": float(last["mult"]), "vermin": bool(last.get("vermin", false))}


## AI/离线的期望倍率(含平均径向)。ai_skill 0=近均匀(含 vermin 拖累),1=偏向高奖、避 vermin。
static func expected_mult(ai_skill: float) -> float:
	var s := clampf(ai_skill, 0.0, 1.0)
	# 均匀期望(按 span 加权,vermin=0 计入)
	var uniform := 0.0
	var top := 0.0
	for seg in SEGMENTS:
		uniform += (float(seg["span"]) / 360.0) * float(seg["mult"])
		top = maxf(top, float(seg["mult"]))
	# 高目标:偏向但不满命中 jackpot(用 x100 量级更稳,避免离散暴涨)
	var high := 100.0
	var e_seg: float = lerpf(uniform, high, s)
	return e_seg * AI_RADIAL


## 径向精度加成:盘心 2.0 → 边缘 1.0(r 归一化 0..1)。
static func radial_bonus(r: float) -> float:
	return lerpf(2.0, 1.0, clampf(r, 0.0, 1.0))


## (aim,power) → 盘面落点 {r(离盘心 0..1), a_off(盘面角偏移 °)}。纯确定性,无 RNG。
static func landing(aim: float, power: float) -> Dictionary:
	var a_off := (clampf(aim, 0.0, 1.0) - 0.5) * AIM_ARC
	var r := clampf(absf(power - POWER_SWEET) / POWER_SWEET, 0.0, 1.0)
	return {"r": r, "a_off": a_off}


## n 支扇形多镖的角偏移(居中对称,和为 0)。
static func fan_offsets(n: int) -> Array:
	var out: Array = []
	var cnt := maxi(1, n)
	var start := -FAN_STEP * (float(cnt) - 1.0) * 0.5
	for i in cnt:
		out.append(start + FAN_STEP * float(i))
	return out


static func _center_of(name: StringName) -> float:
	var acc := 0.0
	for s in SEGMENTS:
		if s["name"] == name:
			return acc + float(s["span"]) * 0.5
		acc += float(s["span"])
	return 0.0


static func _span_of(name: StringName) -> float:
	for s in SEGMENTS:
		if s["name"] == name:
			return float(s["span"])
	return 0.0


## 两角在圆周上的最短角距(°)。
static func _arc_dist(a: float, b: float) -> float:
	var d := absf(fposmod(a - b, 360.0))
	return minf(d, 360.0 - d)
