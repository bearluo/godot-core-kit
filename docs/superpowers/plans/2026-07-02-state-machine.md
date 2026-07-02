# KitStateMachine 状态机类库 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 Node 型有限状态机类库 KitStateMachine/KitState(class_name 分发,零依赖,非 autoload)。

**Architecture:** 见 spec `docs/superpowers/specs/2026-07-02-state-machine-design.md`。`state_machine/` 子目录两个文件;不进 CoreKit 门面,不需要集成任务接线。

**Tech Stack:** Godot 4.7 / 纯 GDScript / headless `-s` 断言测试(代码组树 + 探针状态 fixture)

## Global Constraints

- 分支:全部工作在 `feat/framework-v0.4` 上(从 main 切出);线性历史,不得产生 merge commit。
- 纯 GDScript、Tab 缩进;无 C#、无 GDExtension、无第三方依赖;命令行 `godot` 已在 PATH。
- Web 导出兼容:禁用线程/平台专属 API。
- 依赖纪律:本类库**零依赖**(不引用 CoreKit/Log;诊断用 `push_warning`/`push_error`),可完全脱离框架使用。
- 测试纪律(`-s` 避坑手册):untyped 值的下游变量显式标注类型(不用 `:=`);测试无论成败必须到达 `quit()`。
- **class_name 缓存坑**:`class_name` 注册进 `res://.godot/global_script_class_cache.cfg`,由编辑器/import 扫描生成;新建 class_name 文件后**必须先跑一次 import**(Step 3),否则 headless `-s` 编译 `kit_state_machine.gd` 时 `KitState` 标识符解析失败。
- 运行测试用硬超时模板(PowerShell,单测 60s 上限):

```powershell
$p = Start-Process godot -ArgumentList '--headless','--path','.','-s','res://test/test_state_machine.gd' -RedirectStandardOutput "$env:TEMP\gck-out.txt" -RedirectStandardError "$env:TEMP\gck-err.txt" -PassThru -NoNewWindow; if (-not $p.WaitForExit(60000)) { $p.Kill(); 'TIMEOUT(疑似测试报错未达 quit)' }; Get-Content "$env:TEMP\gck-out.txt"
```

- git 提交消息不得含英文双引号(PowerShell here-string 坑)。

---

### Task 1: KitState + KitStateMachine 核心

**Files:**
- Create: `addons/godot-core-kit/state_machine/kit_state.gd`
- Create: `addons/godot-core-kit/state_machine/kit_state_machine.gd`
- Create: `test/fixtures/probe_state.gd`(探针状态)
- Create: `test/fixtures/probe_decision_state.gd`(enter 里连转的决策态探针)
- Test: `test/test_state_machine.gd`

**Interfaces:**
- Consumes: 无(零依赖)。
- Produces: `class_name KitState`(虚方法 `enter(prev_state_name: String)` / `exit(next_state_name: String)` / `update(delta: float)` / `physics_update(delta: float)` / `handle_input(event: InputEvent)`;`var machine`;`transition_to(state_name: String)`);`class_name KitStateMachine`(`signal state_changed(from_name, to_name)`;`@export var initial_state: KitState`;`var current_state: KitState`;`transition_to(state_name: String)`;`get_state(state_name: String) -> KitState`;`const MAX_CHAIN := 8`)。集成任务的 demo 会代码组一台两态状态机冒烟。

- [ ] **Step 1: 实现 kit_state.gd(先写实现:两份 fixture 都要 extends 它,测试无法先行编译)**

```gdscript
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


## 语法糖:machine.transition_to(state_name)。
func transition_to(state_name: String) -> void:
	if machine != null:
		machine.transition_to(state_name)
```

- [ ] **Step 2: 实现 kit_state_machine.gd**

```gdscript
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
```

- [ ] **Step 3: 刷新 class_name 缓存**

```powershell
$p = Start-Process godot -ArgumentList '--headless','--path','.','--import' -PassThru -NoNewWindow; if (-not $p.WaitForExit(120000)) { $p.Kill(); 'TIMEOUT' }
```

Expected: 正常退出;`.godot/global_script_class_cache.cfg` 里出现 KitState/KitStateMachine 条目。

- [ ] **Step 4: 写 fixtures(路径 extends,避免 fixture 自身依赖 class 缓存)**

`test/fixtures/probe_state.gd`:

```gdscript
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
```

`test/fixtures/probe_decision_state.gd`:

```gdscript
extends "res://test/fixtures/probe_state.gd"
## 决策态探针:enter 记录后立即转向 next_on_enter(为 "" 则不转)。
## 用于验证连锁转换与 MAX_CHAIN 死循环保护。

var next_on_enter: String = ""


func enter(prev_state_name: String) -> void:
	super.enter(prev_state_name)
	if next_on_enter != "":
		transition_to(next_on_enter)
```

- [ ] **Step 5: 写失败测试 test/test_state_machine.gd**

```gdscript
extends SceneTree
## KitStateMachine headless 断言测试:代码组树(machine + 探针状态子节点),
## root.add_child 触发 _ready 注册与初始进入;转发用手动 machine._process 驱动。
## 运行:godot --headless --path . -s res://test/test_state_machine.gd
##
## 前置:须先跑过一次 godot --headless --path . --import(class_name 缓存),
## 否则 kit_state_machine.gd 编译时解析不到 KitState。fixtures 用路径 extends,
## 不受缓存影响。机器脚本零 autoload 依赖,但沿用运行时 load() 惯例。

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
```

- [ ] **Step 6: 跑测试确认全绿**

用 Global Constraints 的硬超时模板运行。Expected: `test_state_machine: ALL PASS`,退出码 0。
若报 `Identifier not found: KitState` → 重跑 Step 3 的 import(class 缓存未刷新)。

- [ ] **Step 7: 提交**

```powershell
git add addons/godot-core-kit/state_machine/kit_state.gd addons/godot-core-kit/state_machine/kit_state_machine.gd test/fixtures/probe_state.gd test/fixtures/probe_decision_state.gd test/test_state_machine.gd
git commit -m 'feat: add KitStateMachine/KitState node-based FSM library'
```
