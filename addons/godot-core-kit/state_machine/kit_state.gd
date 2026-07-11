class_name KitState
extends Node
## 单个状态。全部方法为虚方法,子类按需覆写。零依赖,可脱离框架单独使用。
## 状态由宿主 KitStateMachine 按【节点名】注册;改节点名即改状态名。

## 宿主状态机;由 KitStateMachine 在 _ready 时注入。
## 不标注 KitStateMachine 类型:打破两个 class_name 间的循环类型引用
## (机器 → 状态单向引用即可,循环引用在 headless class 缓存下有编译风险)。
var machine


## 进入本状态。prev_state_name 为上一个状态的名字,初始进入为 ""。
func enter(_prev_state_name: String) -> void:
	pass


## 离开本状态。next_state_name 为将要进入的状态名。
func exit(_next_state_name: String) -> void:
	pass


## 由宿主 _process 转发(仅当前状态收到)。
func update(_delta: float) -> void:
	pass


## 由宿主 _physics_process 转发(仅当前状态收到)。
func physics_update(_delta: float) -> void:
	pass


## 由宿主 _unhandled_input 转发(仅当前状态收到)。
func handle_input(_event: InputEvent) -> void:
	pass


## 本态被 push_state 压栈、让位给新态时调用(暂停语义,现场保留)。默认空。
func pause() -> void:
	pass


## 本态经 pop_state 从栈顶弹回、重新成为活动态时调用。默认空。
func resume() -> void:
	pass


## 语法糖:machine.transition_to(state_name)。
func transition_to(state_name: String) -> void:
	if machine != null:
		machine.transition_to(state_name)
