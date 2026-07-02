class_name KitStateMachine
extends Node
## 有限状态机宿主。直接子节点中的 KitState 按【节点名】注册为状态;
## 编辑器里可视化组装:实体节点 → KitStateMachine → 一态一子节点一脚本。
## 零依赖(诊断用 push_warning/push_error),可脱离框架单独使用。
##
## 转换语义:old.exit(new_name) → 切换 current_state → new.enter(old_name)
## → state_changed。enter/exit 执行中再调 transition_to 会入队,当前转换完成
## 后按序处理(支持"决策态"在 enter 里立即转走);同一次外部触发内最多连转
## MAX_CHAIN 次,超过按死循环处理(push_error + 丢弃剩余队列)。
## transition_to(当前态) 照常走 exit→enter(可用作"重进重置")。

## 每次完成一次转换后广播(初始进入也广播,from_name 为 "")。
signal state_changed(from_name: String, to_name: String)

const MAX_CHAIN := 8

## 初始状态;为 null 时取第一个 KitState 子节点。
@export var initial_state: KitState

## 当前状态(只读约定;转换请走 transition_to)。
var current_state: KitState

var _states: Dictionary = {}      # 状态名(String) -> KitState
var _transitioning: bool = false
var _pending: Array[String] = []  # 转换执行中收到的后续转换请求


func _ready() -> void:
	for child in get_children():
		if child is KitState:
			_states[String(child.name)] = child
			child.machine = self
	if _states.is_empty():
		push_warning("KitStateMachine(%s): 没有任何 KitState 子节点,状态机空转" % get_path())
		return
	var first: KitState = initial_state
	if first == null:
		for child in get_children():
			if child is KitState:
				first = child
				break
	_run_transition("", first)


## 按状态名转换。未知名字 → push_warning + 空操作。
func transition_to(state_name: String) -> void:
	if not _states.has(state_name):
		push_warning("KitStateMachine(%s): 未知状态 '%s',忽略" % [get_path(), state_name])
		return
	if _transitioning:
		_pending.append(state_name)
		return
	var from_name := ""
	if current_state != null:
		from_name = String(current_state.name)
	_run_transition(from_name, _states[state_name])


## 按名取状态节点;未知名字返回 null。
func get_state(state_name: String) -> KitState:
	return _states.get(state_name)


## 执行一次转换,并按序消化期间入队的连锁转换(上限 MAX_CHAIN 防死循环)。
func _run_transition(from_name: String, to_state: KitState) -> void:
	_transitioning = true
	var chain := 0
	var prev_name := from_name
	var next_state: KitState = to_state
	while next_state != null:
		if chain >= MAX_CHAIN:
			push_error("KitStateMachine(%s): 单次触发内连转超过 %d 次,疑似死循环,丢弃剩余转换" % [get_path(), MAX_CHAIN])
			_pending.clear()
			break
		chain += 1
		if current_state != null:
			current_state.exit(String(next_state.name))
		var old_name := prev_name
		current_state = next_state
		current_state.enter(old_name)
		state_changed.emit(old_name, String(current_state.name))
		prev_name = String(current_state.name)
		next_state = null
		if not _pending.is_empty():
			var pending_name: String = _pending.pop_front()
			next_state = _states.get(pending_name)
	_transitioning = false


func _process(delta: float) -> void:
	if current_state != null:
		current_state.update(delta)


func _physics_process(delta: float) -> void:
	if current_state != null:
		current_state.physics_update(delta)


func _unhandled_input(event: InputEvent) -> void:
	if current_state != null:
		current_state.handle_input(event)
