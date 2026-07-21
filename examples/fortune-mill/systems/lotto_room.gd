class_name LottoRoom
extends RefCounted
## 刮刮乐房 model(纯数据,不挂节点树)。刮卡 → 加权中奖表 → money;升级经 KitModifiers 聚合;
## 攒够 BRIBE_COST 贿赂守卫 Gorgon 过关。
##
## 跨房协同(spec §5.6 的形状):JACKPOT 命中 → 往 **global_mul** target 叠一条永久乘法层
## (源 lotto_jackpot,值 JACKPOT_MUL^count)。所有房间产出都 × value_for(global_mul),故经共享
## KitModifiers 这个唯一求值点,一次 jackpot 放大全房间(含飞镖)。_jackpot_count 是权威态(存档),
## 每命中重算这条 mul(一源一条,不多源累加),from_dict 重放。

## 中奖表(自定):倍率 + 权重(与 PRIZE_MULT 同下标)。末档 = JACKPOT(大赔付 + 触发 global_mul)。
const PRIZE_MULT := [1.0, 3.0, 8.0, 25.0, 200.0]
const PRIZE_WEIGHT := [60.0, 25.0, 10.0, 4.5, 0.5]
const JACKPOT_TIER := 4              ## PRIZE_* 里 jackpot 档的下标
const CARD_BASE := 1.0               ## 单卡基础 money(未加成)
const JACKPOT_MUL := 1.5             ## 每次 JACKPOT 的永久全局乘数
const GLOBAL_MUL := &"global_mul"    ## 跨房协同求值 target(全房间共读)
const BRIBE_COST := 1_000_000.0      ## 贿赂 Gorgon 门槛

var _money: Currency
var _modifiers: KitModifiers
var _registry: KitDataRegistry
var _levels: Dictionary = {}         # StringName(id) -> int(level)
var _jackpot_weight_level: int = 0   # lucky_charm 升级档(抬高 jackpot 权重)
var _jackpot_count: int = 0          # 累计 JACKPOT 命中(权威,存档;驱动 global_mul)
var _cleared: bool = false
var _rng := RandomNumberGenerator.new()


func _init(money: Currency, modifiers: KitModifiers, registry: KitDataRegistry) -> void:
	_money = money
	_modifiers = modifiers
	_registry = registry
	_rng.randomize()


func seed_rng(s: int) -> void:
	_rng.seed = s


func jackpot_count() -> int:
	return _jackpot_count


func level_of(id: StringName) -> int:
	return int(_levels.get(id, 0))


## 下一级成本 = base_cost × growth^当前level。
func cost_of(id: StringName) -> float:
	var def = _registry.get_def(&"lotto_upgrade", id)
	if def == null:
		return INF
	return float(def.base_cost) * pow(float(def.growth), level_of(id))


## 当前 jackpot 档权重(随 lucky_charm 升级抬高)。
func _jackpot_weight() -> float:
	return PRIZE_WEIGHT[JACKPOT_TIER] * (1.0 + 0.5 * float(_jackpot_weight_level))


## 当前权重表(仅 jackpot 档随升级变)。
func _weights() -> Array:
	var w := PRIZE_WEIGHT.duplicate()
	w[JACKPOT_TIER] = _jackpot_weight()
	return w


## 加权随机中奖档(0-based)。
func _roll_prize() -> int:
	var w := _weights()
	var sum := 0.0
	for x in w:
		sum += x
	var pick := _rng.randf() * sum
	var acc := 0.0
	for i in range(w.size()):
		acc += w[i]
		if pick <= acc:
			return i
	return w.size() - 1


## 刮一次(含多卡)。每卡:money_per_card 聚合值 × 中奖倍率 × global_mul。命中 jackpot 档
## → 叠永久 global_mul(下次刮起生效,本次用刮前的 gmul,避免刮内顺序依赖)。
## 返回 {money, cards, jackpot(bool), jackpots(本次命中数)}。
func scratch() -> Dictionary:
	var cards := maxi(1, int(_modifiers.value_for(&"cards_per_scratch", 1.0)))
	var per_card := _modifiers.value_for(&"money_per_card", CARD_BASE)
	var gmul := _modifiers.value_for(GLOBAL_MUL, 1.0)
	var total := 0.0
	var hits := 0
	for _i in cards:
		var tier := _roll_prize()
		total += per_card * PRIZE_MULT[tier] * gmul
		if tier == JACKPOT_TIER:
			hits += 1
	if hits > 0:
		_jackpot_count += hits
		_apply_jackpot_mul()
	_money.add(total)
	return {"money": total, "cards": cards, "jackpot": hits > 0, "jackpots": hits}


## 把累计 jackpot 折算成一条永久全局乘法层(源 lotto_jackpot)。一源一条,值随次数长。
func _apply_jackpot_mul() -> void:
	if _jackpot_count <= 0:
		return
	_modifiers.set_modifier(GLOBAL_MUL, &"lotto_jackpot", &"mul", pow(JACKPOT_MUL, _jackpot_count))


## 中奖倍率期望(按当前权重表,含 jackpot 档赔付期望)。
func _expected_prize_mult() -> float:
	var w := _weights()
	var sum := 0.0
	var wsum := 0.0
	for i in range(w.size()):
		wsum += w[i]
		sum += w[i] * PRIZE_MULT[i]
	return sum / wsum


## 自动刮的期望 money/秒(确定性:scratches/s × 多卡 × 单卡聚合 × 中奖期望 × global_mul)。
## scratches_per_sec 基值 0,买 auto_scratcher 才 >0。用期望值、不触发离散 jackpot(保在线=离线)。
func auto_money_rate() -> float:
	var sps := _modifiers.value_for(&"scratches_per_sec", 0.0)
	if sps <= 0.0:
		return 0.0
	var cards := maxi(1, int(_modifiers.value_for(&"cards_per_scratch", 1.0)))
	var per_card := _modifiers.value_for(&"money_per_card", CARD_BASE)
	var gmul := _modifiers.value_for(GLOBAL_MUL, 1.0)
	return sps * float(cards) * per_card * _expected_prize_mult() * gmul


## 自动化产出 dt 秒的 money(确定性,按 auto_money_rate)。返回本次新增 money。
func produce(dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	var m := auto_money_rate() * dt
	if m <= 0.0:
		return 0.0
	_money.add(m)
	return m


## 买一级升级。买不起 / 已满级 / 无此 def → false。
func buy_upgrade(id: StringName) -> bool:
	var def = _registry.get_def(&"lotto_upgrade", id)
	if def == null:
		return false
	var lvl := level_of(id)
	if def.max_level >= 0 and lvl >= def.max_level:
		return false
	if not _money.spend(cost_of(id)):
		return false
	_levels[id] = lvl + 1
	_apply_upgrade(def, lvl + 1)
	return true


## 把某升级在 level 时的效果落到 modifier(unlock 类改 jackpot 权重档)。覆盖式(同 source_id)。
func _apply_upgrade(def, level: int) -> void:
	if def.kind == &"unlock":
		_jackpot_weight_level = level
		return
	var v := 0.0
	if def.op == &"add":
		v = float(def.effect_per_level) * level
	else:  # mul:每级 ×(1+effect)
		v = pow(1.0 + float(def.effect_per_level), level)
	_modifiers.set_modifier(def.target, def.id, def.op, v)


func can_bribe() -> bool:
	return _money.get_amount() >= BRIBE_COST


## 达门槛则过关(不扣货币,过关即本房终点)。
func bribe() -> bool:
	if not can_bribe():
		return false
	_cleared = true
	return true


func is_cleared() -> bool:
	return _cleared


## 只存权威态(levels/cleared/jackpots);modifier 与 jackpot_weight 是派生值,from_dict 重算。
func to_dict() -> Dictionary:
	var lv := {}
	for id in _levels:
		lv[String(id)] = int(_levels[id])
	return {"levels": lv, "cleared": _cleared, "jackpots": _jackpot_count}


func from_dict(d: Dictionary) -> void:
	# 摘除本 room 此前施加的所有 modifier(升级层 + jackpot 全局层),派生态从零重算不叠残留。
	for old_id in _levels:
		var old_def = _registry.get_def(&"lotto_upgrade", old_id)
		if old_def != null and old_def.kind != &"unlock":
			_modifiers.remove_source(old_def.target, old_id)
	_modifiers.remove_source(GLOBAL_MUL, &"lotto_jackpot")
	_levels.clear()
	_jackpot_weight_level = 0
	_jackpot_count = 0
	_cleared = bool(d.get("cleared", false))
	var lv: Dictionary = d.get("levels", {})
	for k in lv:
		var id := StringName(k)
		var level := int(lv[k])
		_levels[id] = level
		var def = _registry.get_def(&"lotto_upgrade", id)
		if def != null:
			_apply_upgrade(def, level)
	_jackpot_count = int(d.get("jackpots", 0))
	_apply_jackpot_mul()
