extends "res://addons/godot-core-kit/state_machine/kit_state.gd"
## 状态机测试探针:把生命周期调用按序记入共享 journal。
## 用路径 extends(而非 extends KitState):fixture 不依赖 class_name 缓存。

var journal: Array = []  # 由测试注入同一个 Array 引用,跨状态共享记录


func enter(prev_state_name: String) -> void:
	journal.append([String(name), "enter", prev_state_name])


func exit(next_state_name: String) -> void:
	journal.append([String(name), "exit", next_state_name])


func update(delta: float) -> void:
	journal.append([String(name), "update", delta])


func pause() -> void:
	journal.append([String(name), "pause"])


func resume() -> void:
	journal.append([String(name), "resume"])
