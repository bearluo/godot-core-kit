extends Node
## 天气系统。每天(订阅 clock:day_changed)按固定种子 RNG 掷出当日天气,广播 weather:changed。
## 晴 sunny(生长 +0)/ 雨 rainy(生长 +1)。作物订阅 weather:changed 据此决定当天长几格。
##
## dogfood 点:
## - CoreKit.bus 作【事件链/管道】—— clock:day_changed →(本系统丰富为)→ weather:changed,
##   每级只认上一级的事件、无直接引用(crop 认 weather、weather 认 clock、彼此不 preload);
## - weather: 是游戏第 4 个自有命名空间(与 clock:/shop:/quest: 并存);
## - "天气影响作物生长"这种跨系统效果完全靠广播达成,零耦合。
## - 嵌套 publish:本系统在 clock:day_changed 处理器里再 publish weather:changed,
##   靠 EventBus 的快照派发(重入安全)成立。

const EV_CHANGED := "weather:changed"   ## payload {day:int, kind:StringName, growth_bonus:int}

const SUNNY := &"sunny"
const RAINY := &"rainy"
const RAIN_CHANCE := 0.42               ## 雨天概率(固定种子下序列确定)

var _rng := RandomNumberGenerator.new()
var _kind: StringName = &""             ## 初始空:保证第一天必打印一次"当前天气"


func _ready() -> void:
	_rng.seed = 20260714                # 固定种子 → 天气序列可复现(确定性 demo)
	CoreKit.bus.subscribe(CoreKit.clock.EV_DAY_CHANGED, _on_day)


func _exit_tree() -> void:
	CoreKit.bus.unsubscribe_all(self)


## 每天掷天气 → 广播 weather:changed(嵌套在 clock:day_changed 处理内)。只在天气变化时打印。
func _on_day(snap: Dictionary) -> void:
	var day := int(snap.get("day", 0))
	var prev := _kind
	_kind = RAINY if _rng.randf() < RAIN_CHANCE else SUNNY
	var bonus := bonus_of(_kind)
	if _kind != prev:
		CoreKit.log.info("[Weather] 第 %d 天 %s(作物生长 +%d)" % [day, name_of(_kind), bonus])
	CoreKit.bus.publish(EV_CHANGED, {"day": day, "kind": _kind, "growth_bonus": bonus})


func current_kind() -> StringName:
	return _kind


static func bonus_of(kind: StringName) -> int:
	return 1 if kind == RAINY else 0


static func name_of(kind: StringName) -> String:
	return "下雨" if kind == RAINY else "晴天"
