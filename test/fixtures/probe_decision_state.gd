extends "res://test/fixtures/probe_state.gd"
## 决策态探针:enter 记录后按字段立即触发一次转移/派发(为 "" 则不动)。
## 用于验证连锁转换、MAX_CHAIN 死循环保护、以及转换中 dispatch 入队。

var next_on_enter: String = ""       # enter 里 transition_to(该名)
var dispatch_on_enter: String = ""   # enter 里 machine.dispatch(该事件)
var push_on_enter: String = ""       # enter 里 machine.push_state(该名)


func enter(prev_state_name: String) -> void:
	super.enter(prev_state_name)
	if next_on_enter != "":
		transition_to(next_on_enter)
	elif dispatch_on_enter != "":
		machine.dispatch(dispatch_on_enter)
	elif push_on_enter != "":
		machine.push_state(push_on_enter)
