extends Node
## 一株已播种作物(农田子节点)。生命周期用 KitStateMachine 建模:Growing → Mature。
## 订阅 CoreKit.bus 的 weather:changed 推进生长(每天长 1 格,雨天 +1),到 grow_days 就把
## 状态机转到 Mature;is_ready()(供农田收获判定)= 状态机处于 Mature。
##
## 【增量9】生长改由 weather:changed 驱动(而非直接认 clock:day_changed)——天气系统把
## clock:day_changed 丰富成带 growth_bonus 的 weather:changed,作物只认后者:clock→weather→crop
## 的 bus 事件链,每级无直接引用。
##
## 【增量8】改为可被 CoreKit.pool 复用:同一个 Crop 实例收获后归还池、下次播种时借出重用,
## 免去反复 instantiate/free。池化有状态节点踩到的关键坑——
##   - `_ready` 一生只跑一次(即使节点被反复摘挂树也不重跑)→ 只用来建 FSM(建一次);
##   - 订阅/退订必须放 `_enter_tree`/`_exit_tree`(每次进出树都跑),否则复用后收不到事件;
##   - 实现约定钩子 `_pool_reset()`,归还时清掉本轮生长状态,供下次从头开始。
##
## dogfood 点:KitStateMachine 每实体状态用例 + CoreKit.pool 复用有状态节点 +
## bus 事件命名约定 namespace:event 的消费端(天气事件链);Node 监听者进出树对称订阅/退订。
##
## (自然扩展:再加个 Withered 态 + Mature→Withered 的"过熟"转移即可,本骨架未做。)

const EV_WEATHER := "weather:changed"   ## 游戏侧天气事件(见 weather_system.gd,按约定用字面量解耦)

var def                     ## CropDef Resource(由 Farm 播种时注入)
var crop_id: StringName = &""
var _stage := 0             ## 已生长天数
var _sm                     ## KitStateMachine


## 生长态 / 成熟态:命名相位标记(存在即语义,enter/exit 钩子可承载 game 侧表现)。
class GrowingState extends KitState:
	pass


class MatureState extends KitState:
	pass


## 仅一次:建状态机。_ready 一生只跑一次,即使被对象池反复摘挂树也不重跑,故这里只放
## "创建期一次性搭建",反复要做的订阅放 _enter_tree。
func _ready() -> void:
	_sm = KitStateMachine.new()
	_sm.name = "CropFSM"
	var growing := GrowingState.new(); growing.name = "Growing"
	var mature := MatureState.new(); mature.name = "Mature"
	_sm.add_child(growing)
	_sm.add_child(mature)
	_sm.initial_state = growing        # 须在 add_child(入树触发机器 _ready)之前设好
	_sm.state_changed.connect(_on_state_changed)
	add_child(_sm)                     # 入树 → 机器 _ready 注册状态并进入 Growing


## 每次入树都订阅:池复用时 _ready 不再触发,订阅只能放这里,否则复用后收不到天气事件。
## (首次入树 _enter_tree 先于 _ready,此刻 _sm 尚未建;但 _on_weather 要等下一次 advance_day
##  才可能被调,那时 _ready 早已跑完,安全。)
func _enter_tree() -> void:
	CoreKit.bus.subscribe(EV_WEATHER, _on_weather)


func _exit_tree() -> void:
	CoreKit.bus.unsubscribe_all(self)


## 对象池归还钩子(release 时被调):清掉本轮生长状态,FSM 拨回 Growing,供下次复用从头长。
func _pool_reset() -> void:
	_stage = 0
	if _sm != null:
		_sm.transition_to("Growing")


## 是否已成熟可收(= 状态机处于 Mature)。is_in 为 v0.18.0 便利方法(null 安全)。
func is_ready() -> bool:
	return _sm.is_in("Mature")


## weather:changed 处理:每天长 1 格,雨天额外 +growth_bonus。到 grow_days 转 Mature。
func _on_weather(payload: Dictionary) -> void:
	if is_ready():
		return  # 已成熟:不再生长,也不再刷屏
	var bonus := int(payload.get("growth_bonus", 0))
	_stage += 1 + bonus
	var shown = _stage if _stage < def.grow_days else def.grow_days   # 显示封顶到 grow_days(def 无类型,不用 :=)
	CoreKit.log.info("[Crop:%s] 第 %d 天 生长 %d/%d%s" % [
		def.display_name, int(payload.get("day", 0)), shown, def.grow_days,
		"(雨+%d)" % bonus if bonus > 0 else ""])
	if _stage >= def.grow_days:
		_sm.transition_to("Mature")


## 状态机转移回调:成熟时打一行,证明 FSM 驱动了生命周期(初始 ""→Growing 静默跳过)。
func _on_state_changed(from_name: String, to_name: String) -> void:
	if to_name == "Mature":
		CoreKit.log.info("[Crop:%s] 状态 %s→%s 已成熟" % [def.display_name, from_name, to_name])
