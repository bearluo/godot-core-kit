class_name PachinkoRoom
extends RefCounted
## 柏青哥房 model(纯数据,不挂节点树)。落球 → 加权落槽 → tickets;升级经 KitModifiers;
## 攒够 BRIBE_COST 贿赂守卫 Rimmington 过关。
##
## 真物理是**表现层 juice**:物理球落进底部槽回调 award_slot(k)(手动走真物理);
## 自动 / 离线 / headless smoke 走 drop_ball 的加权 RNG。award_slot 是唯一权威入账点。
##
## 骰子 DICE(跨房协同 · 临时型):落球累积 _dice_meter,攒够 roll_dice → 往 global_mul 叠一条
## **临时** mul(源 pachinko_dice,值 DICE_MUL),update(dt) 倒计时到 0 自动 remove_source。
## 与 JACKPOT 永久 mul 同 target(global_mul)不同 source_id,Πmul 乘性叠加,一起放大全房间。
## DICE 是 live buff——**不持久化**(存档不存 dice_seconds_left,读档不恢复 buff)。

const SLOT_VALUES := [50.0, 5.0, 1.0, 5.0, 50.0]   ## plinko 式:中间小值常见、边缘大值稀有
const SLOT_WEIGHTS := [1.0, 4.0, 10.0, 4.0, 1.0]
const BALL_BASE := 1.0               ## 单球基础系数(未加成;× 槽值)
const GLOBAL_MUL := &"global_mul"
const DICE_MUL := 3.0                ## 骰子期间全局乘数
const DICE_DURATION := 10.0          ## 骰子 buff 持续秒
const DICE_METER_MAX := 20.0         ## 骰子蓄力上限(每落一球 +1)
const BRIBE_COST := 1_000_000.0      ## 贿赂 Rimmington 门槛

var _tickets: Currency
var _modifiers: KitModifiers
var _registry: KitDataRegistry
var _levels: Dictionary = {}
var _dice_freq_level: int = 0        ## loaded_dice 升级档(降蓄力门槛)
var _dice_meter: float = 0.0         ## 落球累积的骰子蓄力
var _dice_seconds_left: float = 0.0  ## 骰子 buff 剩余秒(>0 = 生效);live,不持久化
var _cleared: bool = false
var _rng := RandomNumberGenerator.new()


func _init(tickets: Currency, modifiers: KitModifiers, registry: KitDataRegistry) -> void:
	_tickets = tickets
	_modifiers = modifiers
	_registry = registry
	_rng.randomize()


func seed_rng(s: int) -> void:
	_rng.seed = s


func level_of(id: StringName) -> int:
	return int(_levels.get(id, 0))


func cost_of(id: StringName) -> float:
	var def = _registry.get_def(&"pachinko_upgrade", id)
	if def == null:
		return INF
	return float(def.base_cost) * pow(float(def.growth), level_of(id))


# --- 骰子 DICE 查询 ---

## 蓄力门槛(随 loaded_dice 升级降低:每级 -10%,封底 20%)。
func _dice_threshold() -> float:
	return DICE_METER_MAX * maxf(0.2, 1.0 - 0.1 * float(_dice_freq_level))

func dice_meter() -> float: return _dice_meter
func dice_threshold() -> float: return _dice_threshold()
func dice_ready() -> bool: return _dice_meter >= _dice_threshold()
func dice_active() -> bool: return _dice_seconds_left > 0.0
func dice_seconds_left() -> float: return _dice_seconds_left


## 加权落槽(0-based)。
func _roll_slot() -> int:
	var sum := 0.0
	for w in SLOT_WEIGHTS:
		sum += w
	var pick := _rng.randf() * sum
	var acc := 0.0
	for i in range(SLOT_WEIGHTS.size()):
		acc += SLOT_WEIGHTS[i]
		if pick <= acc:
			return i
	return SLOT_WEIGHTS.size() - 1


## 落进槽 slot 的权威入账:tickets_per_ball 聚合 × 槽值 × global_mul。返回 tickets。
## 供物理层落槽回调,或 drop_ball 内部调用。每落一球累积骰子蓄力。
func award_slot(slot: int) -> float:
	var per_ball := _modifiers.value_for(&"tickets_per_ball", BALL_BASE)
	var gmul := _modifiers.value_for(GLOBAL_MUL, 1.0)
	var t: float = per_ball * SLOT_VALUES[slot] * gmul
	_tickets.add(t)
	_dice_meter = minf(_dice_meter + 1.0, DICE_METER_MAX)
	return t


## 落球(含多球)。每球 RNG 落槽 + award_slot。返回 {tickets, balls, slots}。
func drop_ball() -> Dictionary:
	var balls := maxi(1, int(_modifiers.value_for(&"balls_per_drop", 1.0)))
	var total := 0.0
	var slots: Array = []
	for _i in balls:
		var s := _roll_slot()
		slots.append(s)
		total += award_slot(s)
	return {"tickets": total, "balls": balls, "slots": slots}


## 掷骰(需蓄力够)。消耗蓄力,施加限时全局乘数 buff。返回是否成功。
func roll_dice() -> bool:
	if not dice_ready():
		return false
	_dice_meter = 0.0
	_dice_seconds_left = DICE_DURATION
	_modifiers.set_modifier(GLOBAL_MUL, &"pachinko_dice", &"mul", DICE_MUL)
	return true


## 时间推进:倒计时骰子 buff,到 0 撤下临时 mul。FortuneMill.tick 每帧调。
func update(dt: float) -> void:
	if _dice_seconds_left > 0.0:
		_dice_seconds_left -= dt
		if _dice_seconds_left <= 0.0:
			_dice_seconds_left = 0.0
			_modifiers.remove_source(GLOBAL_MUL, &"pachinko_dice")


# --- 自动化 ---

## 槽值期望(按权重)。
func _expected_slot() -> float:
	var sum := 0.0
	var wsum := 0.0
	for i in range(SLOT_WEIGHTS.size()):
		wsum += SLOT_WEIGHTS[i]
		sum += SLOT_WEIGHTS[i] * SLOT_VALUES[i]
	return sum / wsum


## 自动落球期望 tickets/秒(drops/s × 多球 × 单球聚合 × 槽期望 × global_mul)。
## drops_per_sec 基 0,买 auto_dropper 才 >0。用期望值、不触发骰子蓄力(保在线=离线)。
func auto_ticket_rate() -> float:
	var dps := _modifiers.value_for(&"drops_per_sec", 0.0)
	if dps <= 0.0:
		return 0.0
	var balls := maxi(1, int(_modifiers.value_for(&"balls_per_drop", 1.0)))
	var per_ball := _modifiers.value_for(&"tickets_per_ball", BALL_BASE)
	var gmul := _modifiers.value_for(GLOBAL_MUL, 1.0)
	return dps * float(balls) * per_ball * _expected_slot() * gmul


func produce(dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	var t := auto_ticket_rate() * dt
	if t <= 0.0:
		return 0.0
	_tickets.add(t)
	return t


# --- 升级 ---

func buy_upgrade(id: StringName) -> bool:
	var def = _registry.get_def(&"pachinko_upgrade", id)
	if def == null:
		return false
	var lvl := level_of(id)
	if def.max_level >= 0 and lvl >= def.max_level:
		return false
	if not _tickets.spend(cost_of(id)):
		return false
	_levels[id] = lvl + 1
	_apply_upgrade(def, lvl + 1)
	return true


## unlock 类改骰子频率档;其余落 modifier。覆盖式(同 source_id)。
func _apply_upgrade(def, level: int) -> void:
	if def.kind == &"unlock":
		_dice_freq_level = level
		return
	var v := 0.0
	if def.op == &"add":
		v = float(def.effect_per_level) * level
	else:  # mul:每级 ×(1+effect)
		v = pow(1.0 + float(def.effect_per_level), level)
	_modifiers.set_modifier(def.target, def.id, def.op, v)


func can_bribe() -> bool:
	return _tickets.get_amount() >= BRIBE_COST


func bribe() -> bool:
	if not can_bribe():
		return false
	_cleared = true
	return true


func is_cleared() -> bool:
	return _cleared


## 只存权威态(levels/cleared/dice_meter);modifier 与 dice_freq 是派生值,from_dict 重算。
## DICE 临时 buff(dice_seconds_left)是 live 态,**不持久化**。
func to_dict() -> Dictionary:
	var lv := {}
	for id in _levels:
		lv[String(id)] = int(_levels[id])
	return {"levels": lv, "cleared": _cleared, "dice_meter": _dice_meter}


func from_dict(d: Dictionary) -> void:
	# 摘除本 room 此前施加的升级 modifier + 任何 live DICE buff(派生态从零重算)。
	for old_id in _levels:
		var old_def = _registry.get_def(&"pachinko_upgrade", old_id)
		if old_def != null and old_def.kind != &"unlock":
			_modifiers.remove_source(old_def.target, old_id)
	_modifiers.remove_source(GLOBAL_MUL, &"pachinko_dice")
	_levels.clear()
	_dice_freq_level = 0
	_dice_seconds_left = 0.0
	_dice_meter = float(d.get("dice_meter", 0.0))
	_cleared = bool(d.get("cleared", false))
	var lv: Dictionary = d.get("levels", {})
	for k in lv:
		var id := StringName(k)
		var level := int(lv[k])
		_levels[id] = level
		var def = _registry.get_def(&"pachinko_upgrade", id)
		if def != null:
			_apply_upgrade(def, level)
