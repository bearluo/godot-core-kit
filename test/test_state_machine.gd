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

	# ===== 事件 dispatch 解耦(spec §7 事件派发 1-7) =====

	# E1. add_transition + dispatch 命中具体 from → 转移到目标态
	var be1: Array = _build([["Idle", ProbeState], ["Run", ProbeState]])
	var m1 = be1[0]
	root.add_child(m1)
	await process_frame
	m1.add_transition("Idle", "Run", "go")
	var e1_hit: bool = m1.dispatch("go")
	if not e1_hit or m1.current_state.name != &"Run":
		print("FAIL E1: dispatch 命中具体 from 应转移到 Run,hit=%s cur=%s" % [e1_hit, m1.current_state.name])
		failures += 1
	m1.free()

	# E2. ANYSTATE 通配:任意态 dispatch 该事件都转移
	var be2: Array = _build([["Idle", ProbeState], ["Run", ProbeState], ["Dead", ProbeState]])
	var m2 = be2[0]
	root.add_child(m2)
	await process_frame
	m2.add_transition(m2.ANYSTATE, "Dead", "die")
	m2.transition_to("Run")
	var e2_hit: bool = m2.dispatch("die")   # 从 Run 通配到 Dead
	if not e2_hit or m2.current_state.name != &"Dead":
		print("FAIL E2: ANYSTATE 通配应从任意态转移到 Dead,hit=%s cur=%s" % [e2_hit, m2.current_state.name])
		failures += 1
	m2.free()

	# E3. 具体 from 优先 ANYSTATE:同 event 既有具体又有通配,当前态命中具体的
	var be3: Array = _build([["Idle", ProbeState], ["Run", ProbeState], ["Dead", ProbeState]])
	var m3 = be3[0]
	root.add_child(m3)
	await process_frame
	m3.add_transition(m3.ANYSTATE, "Dead", "ev")
	m3.add_transition("Idle", "Run", "ev")   # 当前态 Idle 有具体转移
	var e3_hit: bool = m3.dispatch("ev")
	if not e3_hit or m3.current_state.name != &"Run":
		print("FAIL E3: 具体 from 应优先通配,期望 Run,实际 %s" % [m3.current_state.name])
		failures += 1
	m3.free()

	# E4. 无匹配:dispatch 返回 false、current_state 不变、无 exit/enter
	var be4: Array = _build([["Idle", ProbeState], ["Run", ProbeState]])
	var m4 = be4[0]
	var j4: Array = be4[1]
	root.add_child(m4)
	await process_frame
	j4.clear()
	var e4_hit: bool = m4.dispatch("nope")
	if e4_hit or m4.current_state.name != &"Idle" or not j4.is_empty():
		print("FAIL E4: 无匹配应返回 false、不转移、无生命周期,hit=%s cur=%s journal=%s" % [e4_hit, m4.current_state.name, j4])
		failures += 1
	m4.free()

	# E5. 重复 add_transition 覆盖:后者生效
	var be5: Array = _build([["Idle", ProbeState], ["Run", ProbeState], ["Dead", ProbeState]])
	var m5 = be5[0]
	root.add_child(m5)
	await process_frame
	m5.add_transition("Idle", "Run", "go")
	m5.add_transition("Idle", "Dead", "go")   # 覆盖上一条
	m5.dispatch("go")
	if m5.current_state.name != &"Dead":
		print("FAIL E5: 重复登记应后者生效(Dead),实际 %s" % [m5.current_state.name])
		failures += 1
	m5.free()

	# E6. dispatch 复用转换核心:journal 序列为 exit→enter、发 state_changed
	var be6: Array = _build([["Idle", ProbeState], ["Run", ProbeState]])
	var m6 = be6[0]
	var j6: Array = be6[1]
	var sig6 := []
	m6.state_changed.connect(func(from: String, to: String) -> void: sig6.append([from, to]))
	root.add_child(m6)
	await process_frame
	m6.add_transition("Idle", "Run", "go")
	j6.clear()
	sig6.clear()
	m6.dispatch("go")
	if j6 != [["Idle", "exit", "Run"], ["Run", "enter", "Idle"]]:
		print("FAIL E6: dispatch 应复用转换核心(exit→enter),实际 %s" % [j6])
		failures += 1
	if sig6 != [["Idle", "Run"]]:
		print("FAIL E6: dispatch 应发 state_changed,实际 %s" % [sig6])
		failures += 1
	m6.free()

	# E7. 转换中 dispatch 入队:决策态 enter 里 dispatch,最终落队列目标态
	var be7: Array = _build([["Start", ProbeState], ["A", ProbeDecisionState], ["B", ProbeState]])
	var m7 = be7[0]
	m7.get_child(1).dispatch_on_enter = "go"
	var sig7 := []
	m7.state_changed.connect(func(from: String, to: String) -> void: sig7.append([from, to]))
	root.add_child(m7)
	await process_frame
	m7.add_transition("A", "B", "go")
	sig7.clear()
	m7.transition_to("A")   # A.enter 里 dispatch("go") → 入队 B
	if sig7 != [["Start", "A"], ["A", "B"]] or m7.current_state.name != &"B":
		print("FAIL E7: 转换中 dispatch 应入队,最终落 B,signals=%s cur=%s" % [sig7, m7.current_state.name])
		failures += 1
	m7.free()

	# ===== pushdown 栈(spec §7 pushdown 8-13) =====

	# P8. push_state:旧态 pause() 被调、栈深+1、新态 enter(旧名)、state_changed
	var bp8: Array = _build([["Game", ProbeState], ["Menu", ProbeState]])
	var m8 = bp8[0]
	var j8: Array = bp8[1]
	var sig8 := []
	m8.state_changed.connect(func(from: String, to: String) -> void: sig8.append([from, to]))
	root.add_child(m8)
	await process_frame        # 进 Game(初始)
	j8.clear()
	sig8.clear()
	m8.push_state("Menu")
	if j8 != [["Game", "pause"], ["Menu", "enter", "Game"]]:
		print("FAIL P8: push 应 pause 旧态并 enter 新态,实际 %s" % [j8])
		failures += 1
	if m8.stack_depth() != 1 or m8.current_state.name != &"Menu" or sig8 != [["Game", "Menu"]]:
		print("FAIL P8: push 后栈深/当前态/信号不正确,depth=%d cur=%s sig=%s" % [m8.stack_depth(), m8.current_state.name, sig8])
		failures += 1
	m8.free()

	# P9. pop_state:活动态 exit(栈顶名)、栈深-1、恢复态 resume() 被调且未重新 enter、state_changed
	var bp9: Array = _build([["Game", ProbeState], ["Menu", ProbeState]])
	var m9 = bp9[0]
	var j9: Array = bp9[1]
	var sig9 := []
	m9.state_changed.connect(func(from: String, to: String) -> void: sig9.append([from, to]))
	root.add_child(m9)
	await process_frame
	m9.push_state("Menu")      # Game 暂停,进 Menu
	j9.clear()
	sig9.clear()
	m9.pop_state()             # 弹回 Game
	if j9 != [["Menu", "exit", "Game"], ["Game", "resume"]]:
		print("FAIL P9: pop 应 exit 活动态并 resume 恢复态(不重 enter),实际 %s" % [j9])
		failures += 1
	if m9.stack_depth() != 0 or m9.current_state.name != &"Game" or sig9 != [["Menu", "Game"]]:
		print("FAIL P9: pop 后栈深/当前态/信号不正确,depth=%d cur=%s sig=%s" % [m9.stack_depth(), m9.current_state.name, sig9])
		failures += 1
	m9.free()

	# P10. 栈空 pop_state:no-op、current 不变
	var bp10: Array = _build([["Game", ProbeState], ["Menu", ProbeState]])
	var m10 = bp10[0]
	var j10: Array = bp10[1]
	root.add_child(m10)
	await process_frame
	j10.clear()
	m10.pop_state()            # 栈空
	if not j10.is_empty() or m10.current_state.name != &"Game" or m10.stack_depth() != 0:
		print("FAIL P10: 栈空 pop 应 no-op,journal=%s cur=%s depth=%d" % [j10, m10.current_state.name, m10.stack_depth()])
		failures += 1
	m10.free()

	# P11. MAX_STACK 守卫:连续 push 超上限被拒、栈深不超 MAX_STACK
	var bp11: Array = _build([["Game", ProbeState], ["Menu", ProbeState]])
	var m11 = bp11[0]
	root.add_child(m11)
	await process_frame
	for i in range(m11.MAX_STACK + 2):
		m11.push_state("Menu")   # 反复自压(仅为快速压满栈摸边界,非真实用法);超上限两次被 push_error 拒
	if m11.stack_depth() != m11.MAX_STACK:
		print("FAIL P11: 栈深应被 MAX_STACK(%d) 截断,实际 %d" % [m11.MAX_STACK, m11.stack_depth()])
		failures += 1
	m11.free()

	# P12. push 后 update 只转发栈顶活动态(栈下挂起态不收 update)
	var bp12: Array = _build([["Game", ProbeState], ["Menu", ProbeState]])
	var m12 = bp12[0]
	var j12: Array = bp12[1]
	root.add_child(m12)
	await process_frame
	m12.push_state("Menu")     # current=Menu, Game 挂起
	j12.clear()
	m12._process(0.25)
	if j12 != [["Menu", "update", 0.25]]:
		print("FAIL P12: push 后 update 应只转发活动态 Menu,实际 %s" % [j12])
		failures += 1
	m12.free()

	# P13. push 转换中拒绝:决策态 enter(转换中)里试 push_state → 被拒,栈空、停在该态
	var bp13: Array = _build([["Start", ProbeDecisionState], ["Menu", ProbeState]])
	var m13 = bp13[0]
	m13.get_child(0).push_on_enter = "Menu"   # Start.enter(初始,_transitioning=true)里试 push
	root.add_child(m13)
	await process_frame        # 进 Start,其 enter 试 push_state("Menu")
	if m13.stack_depth() != 0 or m13.current_state.name != &"Start":
		print("FAIL P13: 转换中 push 应被拒,栈应空且停在 Start,depth=%d cur=%s" % [m13.stack_depth(), m13.current_state.name])
		failures += 1
	m13.free()

	# P14. state_name / is_in 便利查询(null 安全)
	var b14: Array = _build([["Idle", ProbeState], ["Run", ProbeState]])
	var m14 = b14[0]
	root.add_child(m14)
	await process_frame
	if m14.state_name() != "Idle" or not m14.is_in("Idle") or m14.is_in("Run"):
		print("FAIL P14: 初始 state_name/is_in 不正确,name=%s" % m14.state_name())
		failures += 1
	m14.transition_to("Run")
	if m14.state_name() != "Run" or not m14.is_in("Run"):
		print("FAIL P14: 转移后 state_name/is_in 不正确,name=%s" % m14.state_name())
		failures += 1
	m14.free()
	var empty14 = MachineScript.new()   # 无状态子节点 → 无当前态
	root.add_child(empty14)
	await process_frame
	if empty14.state_name() != "" or empty14.is_in("X"):
		print("FAIL P14: 空机器 state_name 应空串、is_in 应 false")
		failures += 1
	empty14.free()

	if failures == 0:
		print("test_state_machine: ALL PASS")
		quit(0)
	else:
		print("test_state_machine: %d FAILURE(S)" % failures)
		quit(1)
