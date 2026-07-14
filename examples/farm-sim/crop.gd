extends Node
## 一株已播种作物(农田子节点)。生命周期用 KitStateMachine 建模:Growing → Mature。
## 订阅 CoreKit.bus 的 clock:day_changed 推进生长天数,到 grow_days 就把状态机转到 Mature;
## is_ready()(供农田收获判定)= 状态机处于 Mature。
##
## dogfood 点:KitStateMachine 在【每实体状态】这一教科书用例——game 侧代码建机、
## KitState 子节点、initial_state、transition_to、current_state 查询、state_changed 信号。
## 状态用内部类(避免多加文件);生长计数留在 crop(相位切换才交给 FSM)。
## bus 事件命名约定 namespace:event 的消费端;Node 监听者 _exit_tree 主动 unsubscribe_all。
##
## (自然扩展:再加个 Withered 态 + Mature→Withered 的"过熟"转移即可,本骨架未做。)

var def                     ## CropDef Resource(由 Farm 播种时注入)
var crop_id: StringName = &""
var _stage := 0             ## 已生长天数
var _sm                     ## KitStateMachine


## 生长态 / 成熟态:命名相位标记(存在即语义,enter/exit 钩子可承载 game 侧表现)。
class GrowingState extends KitState:
	pass


class MatureState extends KitState:
	pass


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
	CoreKit.bus.subscribe(CoreKit.clock.EV_DAY_CHANGED, _on_day)


func _exit_tree() -> void:
	CoreKit.bus.unsubscribe_all(self)


## 是否已成熟可收(= 状态机处于 Mature)。
func is_ready() -> bool:
	return _sm.current_state != null and String(_sm.current_state.name) == "Mature"


func _on_day(snap: Dictionary) -> void:
	if is_ready():
		return  # 已成熟:不再生长,也不再刷屏
	_stage += 1
	CoreKit.log.info("[Crop:%s] 第 %d 天 生长 %d/%d" % [
		def.display_name, int(snap.get("day", 0)), _stage, def.grow_days])
	if _stage >= def.grow_days:
		_sm.transition_to("Mature")


## 状态机转移回调:成熟时打一行,证明 FSM 驱动了生命周期(初始 ""→Growing 静默跳过)。
func _on_state_changed(from_name: String, to_name: String) -> void:
	if to_name == "Mature":
		CoreKit.log.info("[Crop:%s] 状态 %s→%s 已成熟" % [def.display_name, from_name, to_name])
