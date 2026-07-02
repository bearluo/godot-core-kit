extends SceneTree
## KitStateMachine headless 断言测试:代码组树(machine + 探针状态子节点),
## root.add_child 触发 _ready 注册与初始进入;转发用手动 machine._process 驱动。
## 运行:godot --headless --path . -s res://test/test_state_machine.gd
##
## 前置:须先跑过一次 godot --headless --path . --import(class_name 缓存),
## 否则 kit_state_machine.gd 编译时解析不到 KitState。fixtures 用路径 extends,
## 不受缓存影响。机器脚本零 autoload 依赖,但沿用运行时 load() 惯例。
##
## 环境坑:-s 自定义 SceneTree 脚本的 _initialize() 在主循环开始前执行,此时
## root 自身尚未真正"入树"(root.is_inside_tree() 为 false),root.add_child()
## 不会同步触发子树的 NOTIFICATION_READY。每次 root.add_child 后 await 一次
## process_frame,让引擎跑够一帧把入树/_ready 通知补上;经验证这一帧不会额外
## 触发节点的 _process(探针 journal 无多余 update 记录),故不影响后续断言。

const ProbeState := preload("res://test/fixtures/probe_state.gd")
const ProbeDecisionState := preload("res://test/fixtures/probe_decision_state.gd")

var MachineScript


## 组一台状态机:states 为 名字 -> 探针脚本 的有序字典;返回 [machine, journal]。
func _build(state_defs: Array) -> Array:
	var machine = MachineScript.new()
	var journal: Array = []
	for def in state_defs:
		var state = def[1].new()
		state.name = def[0]
		state.journal = journal
		machine.add_child(state)
	return [machine, journal]


func _initialize() -> void:
	MachineScript = load("res://addons/godot-core-kit/state_machine/kit_state_machine.gd")
	var failures := 0

	# 1+2. 注册与初始进入(不设 initial_state → 取第一个子节点)
	var built: Array = _build([["Idle", ProbeState], ["Run", ProbeState], ["Jump", ProbeState]])
	var machine = built[0]
	var journal: Array = built[1]
	var signals := []
	machine.state_changed.connect(func(from: String, to: String) -> void:
		signals.append([from, to]))
	root.add_child(machine)
	await process_frame  # 补一帧:_initialize() 期间 root 尚未入树,需一帧才能触发 _ready
	if machine.get_state("Run") == null or machine.get_state("Nope") != null:
		print("FAIL 1: get_state 注册表不正确")
		failures += 1
	if machine.get_state("Idle").machine != machine:
		print("FAIL 1: 状态的 machine 引用未注入")
		failures += 1
	if journal != [["Idle", "enter", ""]]:
		print("FAIL 2: 初始进入应恰为 Idle.enter(空 prev),实际 %s" % [journal])
		failures += 1
	if signals != [["", "Idle"]] or machine.current_state.name != &"Idle":
		print("FAIL 2: 初始 state_changed/current_state 不正确")
		failures += 1

	# 3. transition_to:exit/enter 顺序与参数、current_state、信号
	journal.clear()
	signals.clear()
	machine.transition_to("Run")
	if journal != [["Idle", "exit", "Run"], ["Run", "enter", "Idle"]]:
		print("FAIL 3: 转换序列不正确,实际 %s" % [journal])
		failures += 1
	if signals != [["Idle", "Run"]] or machine.current_state.name != &"Run":
		print("FAIL 3: 信号/current_state 不正确")
		failures += 1

	# 4. 未知名字:空操作
	journal.clear()
	machine.transition_to("Nope")
	if not journal.is_empty() or machine.current_state.name != &"Run":
		print("FAIL 4: 未知状态应空操作")
		failures += 1

	# 5. 转发:_process 只转发给当前态
	journal.clear()
	machine._process(0.5)
	if journal != [["Run", "update", 0.5]]:
		print("FAIL 5: update 应只转发给当前态,实际 %s" % [journal])
		failures += 1

	# 8. 转换到当前态:重进重置(exit→enter 重跑)
	journal.clear()
	machine.transition_to("Run")
	if journal != [["Run", "exit", "Run"], ["Run", "enter", "Run"]]:
		print("FAIL 8: 自转换应重跑 exit/enter,实际 %s" % [journal])
		failures += 1
	machine.free()

	# 6. 决策态连转:外部转 A,A.enter 里转 B → 最终落 B,信号两条
	var built6: Array = _build([["Start", ProbeState], ["A", ProbeDecisionState], ["B", ProbeState]])
	var machine6 = built6[0]
	machine6.get_child(1).next_on_enter = "B"
	var signals6 := []
	machine6.state_changed.connect(func(from: String, to: String) -> void:
		signals6.append([from, to]))
	root.add_child(machine6)
	await process_frame
	signals6.clear()
	machine6.transition_to("A")
	if signals6 != [["Start", "A"], ["A", "B"]]:
		print("FAIL 6: 决策态连转信号不正确,实际 %s" % [signals6])
		failures += 1
	if machine6.current_state.name != &"B":
		print("FAIL 6: 连转后应停在 B")
		failures += 1
	machine6.free()

	# 7. 死循环保护:A.enter→B、B.enter→A 互转,连转数被 MAX_CHAIN 截断
	var built7: Array = _build([["Start", ProbeState], ["A", ProbeDecisionState], ["B", ProbeDecisionState]])
	var machine7 = built7[0]
	var journal7: Array = built7[1]
	machine7.get_child(1).next_on_enter = "B"
	machine7.get_child(2).next_on_enter = "A"
	root.add_child(machine7)
	await process_frame
	journal7.clear()
	machine7.transition_to("A")  # 触发 A↔B 互转
	var enter_count := 0
	for entry in journal7:
		if entry[1] == "enter":
			enter_count += 1
	if enter_count > machine7.MAX_CHAIN:
		print("FAIL 7: 连转应被 MAX_CHAIN(%d) 截断,实际 enter %d 次" % [machine7.MAX_CHAIN, enter_count])
		failures += 1
	if machine7.current_state == null or machine7._transitioning:
		print("FAIL 7: 截断后机器应停在确定态且不再处于转换中")
		failures += 1
	if not machine7._pending.is_empty():
		print("FAIL 7: 截断后应清空待处理队列")
		failures += 1
	machine7.free()

	# 9. 空机器:无 KitState 子节点,不崩、转发空操作
	var empty_machine = MachineScript.new()
	root.add_child(empty_machine)
	await process_frame
	empty_machine._process(0.016)  # 不崩即通过
	if empty_machine.current_state != null:
		print("FAIL 9: 空机器 current_state 应为 null")
		failures += 1
	empty_machine.free()

	if failures == 0:
		print("test_state_machine: ALL PASS")
		quit(0)
	else:
		print("test_state_machine: %d FAILURE(S)" % failures)
		quit(1)
