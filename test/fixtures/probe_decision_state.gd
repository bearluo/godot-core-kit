extends "res://test/fixtures/probe_state.gd"
## 决策态探针:enter 记录后立即转向 next_on_enter(为 "" 则不转)。
## 用于验证连锁转换与 MAX_CHAIN 死循环保护。

var next_on_enter: String = ""


func enter(prev_state_name: String) -> void:
	super.enter(prev_state_name)
	if next_on_enter != "":
		transition_to(next_on_enter)
