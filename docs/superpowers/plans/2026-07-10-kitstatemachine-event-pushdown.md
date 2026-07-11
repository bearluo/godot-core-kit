# KitStateMachine 事件派发解耦 + pushdown 栈 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在已测的 `KitStateMachine` 上叠加两组正交能力——事件 dispatch 解耦(`add_transition`/`dispatch` + `ANYSTATE` 通配)与 pushdown 栈(`push_state`/`pop_state`,暂停语义),纯增量、向后兼容,发版 0.8.0。

**Architecture:** 能力叠加进现有单文件 `kit_state_machine.gd`,复用其转换核心(`_run_transition`/`_transitioning`/`_pending`/`MAX_CHAIN`),与 `transition_to` 并存;`kit_state.gd` 加两个 default-pass 虚方法 `pause`/`resume`。不拆 mixin/新文件、保持零依赖、不挂 `CoreKit` 门面、per-entity。

**Tech Stack:** Godot 4.7-stable-mono、GDScript、headless `SceneTree` 断言测试(`test/test_state_machine.gd` + 路径式 fixtures)。

## Global Constraints

*(每个任务的要求都隐含包含本节;值逐字取自 spec。)*

- **版本 `0.7.0 → 0.8.0`,三处同步**:`core_kit.gd` 的 `const VERSION`、`plugin.cfg` 的 `version` + `description`、`test/test_core_kit.gd` 硬编码版本断言。
- **零依赖**:诊断只用引擎原生 `push_warning`/`push_error`,不引入第三方库、不依赖其它子系统。
- **不挂 `CoreKit` 门面、per-entity**:`KitStateMachine`/`KitState` 是 off-facade 类库,谁要用就自己 `new()`。
- **纯增量、向后兼容**:现有公开面(`transition_to`/`get_state`/`current_state`/`state_changed`/`initial_state`/`MAX_CHAIN`、`KitState` 五虚方法 + `transition_to` 语法糖)签名与语义**零改动**;现有 9 组断言逐字保留、必须全绿。
- **叠加单文件**:新能力叠进 `kit_state_machine.gd`,不拆新文件/mixin。
- `ANYSTATE := "*"` 为**保留名**;若某 `KitState` 子节点名恰为 `"*"`,`_ready` 注册时 `push_error`。
- `MAX_STACK := 32` 栈深守卫;**pushdown 不参与** `MAX_CHAIN` 连锁计数。
- `pause()`/`resume()` 为 **default-pass 虚方法**(老状态子类不覆写无感)。
- `dispatch(event)` 返回 `bool`;无匹配**静默返回 `false`**(不 warning)。
- `push_state`/`pop_state` **复用 `state_changed`**,不新增专用信号;**转换进行中**(`_transitioning`)`push`/`pop` **拒绝**(`push_warning`),`dispatch` **入 `_pending`**。
- **匹配优先级**:`dispatch` 先查 `(current, event)` 再查 `(ANYSTATE, event)`,**具体 from 优先通配**。
- **暂停语义**:`push_state` 调被压态 `pause()`(不 `exit`),`pop_state` 调恢复态 `resume()`(不重新 `enter`),被压态现场保留。

**运行命令(PowerShell,`godot` 已在 PATH):**
- 单测:`godot --headless --path . -s res://test/test_state_machine.gd` → stdout 含 `test_state_machine: ALL PASS`、exit 0。
- 版本测:`godot --headless --path . -s res://test/test_core_kit.gd` → `ALL PASS`、exit 0。
- 全量:`& .\test\run_all.ps1` → 末行 `=== SUMMARY FAILS=0 ===`(13 测试 OK + 6→9 demo marker present + demo stderr `no`)。

---

### Task 1: 事件 dispatch 解耦

**Files:**
- Modify: `addons/godot-core-kit/state_machine/kit_state_machine.gd`(加 `ANYSTATE`、`_transitions`、`add_transition`、`dispatch`、`_ready` 保留名守卫)
- Modify: `test/fixtures/probe_decision_state.gd`(加 `dispatch_on_enter` 字段,供"转换中 dispatch 入队"测试)
- Test: `test/test_state_machine.gd`(在末尾断言前插入 E1–E7)

**Interfaces:**
- Consumes(现有,不改):`_states: Dictionary`、`current_state: KitState`、`_transitioning: bool`、`_pending: Array[String]`、`_run_transition(from_name: String, to_state: KitState) -> void`。
- Produces(后续任务/文档引用):
  - `const ANYSTATE := "*"`
  - `func add_transition(from_name: String, to_name: String, event: String) -> void`
  - `func dispatch(event: String) -> bool`

- [ ] **Step 1a: 扩展决策态探针,支持 enter 里 dispatch**

`test/fixtures/probe_decision_state.gd` —— 整文件替换为:

```gdscript
extends "res://test/fixtures/probe_state.gd"
## 决策态探针:enter 记录后按字段立即触发一次转移/派发(为 "" 则不动)。
## 用于验证连锁转换、MAX_CHAIN 死循环保护、以及转换中 dispatch 入队。

var next_on_enter: String = ""       # enter 里 transition_to(该名)
var dispatch_on_enter: String = ""   # enter 里 machine.dispatch(该事件)


func enter(prev_state_name: String) -> void:
	super.enter(prev_state_name)
	if next_on_enter != "":
		transition_to(next_on_enter)
	elif dispatch_on_enter != "":
		machine.dispatch(dispatch_on_enter)
```

- [ ] **Step 1b: 写失败测试(E1–E7)**

`test/test_state_machine.gd` —— 用 Edit 把:

```gdscript
	empty_machine.free()

	if failures == 0:
```

替换为(在 `empty_machine.free()` 与 `if failures == 0:` 之间插入 E1–E7):

```gdscript
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
	m7.add_transition("A", "B", "go")   # 须在 add_child+await 之后:_states 于 _ready 才注册
	sig7.clear()
	m7.transition_to("A")   # A.enter 里 dispatch("go") → 入队 B
	if sig7 != [["Start", "A"], ["A", "B"]] or m7.current_state.name != &"B":
		print("FAIL E7: 转换中 dispatch 应入队,最终落 B,signals=%s cur=%s" % [sig7, m7.current_state.name])
		failures += 1
	m7.free()

	if failures == 0:
```

- [ ] **Step 2: 运行,确认失败**

Run: `godot --headless --path . -s res://test/test_state_machine.gd`
Expected: FAIL —— stderr 出现 `SCRIPT ERROR: ... Nonexistent function 'add_transition'`(或 `dispatch`),测试无法打印 `ALL PASS`,exit 非 0。

- [ ] **Step 3: 实现事件 dispatch 解耦**

`addons/godot-core-kit/state_machine/kit_state_machine.gd`:

**3-1** 在 `const MAX_CHAIN := 8` 下一行加通配常量。用 Edit 把:

```gdscript
const MAX_CHAIN := 8
```

替换为:

```gdscript
const MAX_CHAIN := 8

## 事件转移表的通配 from 状态名(保留名;子节点不得取此名)。
const ANYSTATE := "*"
```

**3-2** 在 `_pending` 声明下一行加转移表。用 Edit 把:

```gdscript
var _pending: Array[String] = []  # 转换执行中收到的后续转换请求
```

替换为:

```gdscript
var _pending: Array[String] = []  # 转换执行中收到的后续转换请求
var _transitions: Dictionary = {} # "from|event" -> to_name(事件派发转移表)
```

**3-3** 在 `_ready` 注册循环里加保留名守卫。用 Edit 把:

```gdscript
	for child in get_children():
		if child is KitState:
			_states[String(child.name)] = child
			child.machine = self
```

替换为:

```gdscript
	for child in get_children():
		if child is KitState:
			var sname := String(child.name)
			if sname == ANYSTATE:
				push_error("KitStateMachine(%s): 状态名 '%s' 与通配保留名冲突,dispatch 无法精确命中该态" % [get_path(), ANYSTATE])
			_states[sname] = child
			child.machine = self
```

**3-4** 在 `get_state` 方法之后(即 `func get_state(...)` 的 `return _states.get(state_name)` 那行之后、`_run_transition` 之前)插入两个新方法。用 Edit 把:

```gdscript
## 按名取状态节点;未知名字返回 null。
func get_state(state_name: String) -> KitState:
	return _states.get(state_name)
```

替换为:

```gdscript
## 按名取状态节点;未知名字返回 null。
func get_state(state_name: String) -> KitState:
	return _states.get(state_name)


## 登记一条事件转移。from_name 可为已注册态名或 ANYSTATE;event 为命名事件。
## to_name 未注册 → push_warning + 忽略;同 (from,event) 重复登记 → 覆盖 + push_warning。
func add_transition(from_name: String, to_name: String, event: String) -> void:
	if not _states.has(to_name):
		push_warning("KitStateMachine(%s): add_transition 目标态 '%s' 未注册,忽略" % [get_path(), to_name])
		return
	var key := "%s|%s" % [from_name, event]
	if _transitions.has(key):
		push_warning("KitStateMachine(%s): 转移 (%s, %s) 重复登记,覆盖旧目标" % [get_path(), from_name, event])
	_transitions[key] = to_name


## 按当前态派发事件:先查 (current, event) 再查 (ANYSTATE, event),命中则转移
## (非转换中走 _run_transition;转换中入 _pending)返回 true;无匹配静默返回 false。
func dispatch(event: String) -> bool:
	if current_state == null:
		return false
	var to_name: String = _transitions.get("%s|%s" % [String(current_state.name), event], "")
	if to_name == "":
		to_name = _transitions.get("%s|%s" % [ANYSTATE, event], "")
	if to_name == "":
		return false
	if _transitioning:
		_pending.append(to_name)
		return true
	_run_transition(String(current_state.name), _states[to_name])
	return true
```

- [ ] **Step 4: 运行,确认通过**

Run: `godot --headless --path . -s res://test/test_state_machine.gd`
Expected: PASS —— stdout `test_state_machine: ALL PASS`、exit 0(现有 9 组 + E1–E7 全绿)。

- [ ] **Step 5: 提交**

```bash
git add addons/godot-core-kit/state_machine/kit_state_machine.gd test/fixtures/probe_decision_state.gd test/test_state_machine.gd
git commit -m "feat(state-machine): 事件 dispatch 解耦 add_transition/dispatch + ANYSTATE 通配"
```

---

### Task 2: pushdown 栈(暂停语义)

**Files:**
- Modify: `addons/godot-core-kit/state_machine/kit_state.gd`(加 `pause`/`resume` default-pass 虚方法)
- Modify: `addons/godot-core-kit/state_machine/kit_state_machine.gd`(加 `MAX_STACK`、`_stack`、`push_state`、`pop_state`、`stack_depth`)
- Modify: `test/fixtures/probe_state.gd`(journal 记录 `pause`/`resume`)
- Modify: `test/fixtures/probe_decision_state.gd`(加 `push_on_enter` 字段,供"转换中 push 拒绝"测试)
- Test: `test/test_state_machine.gd`(在末尾断言前插入 P8–P13)

**Interfaces:**
- Consumes(现有,不改):`_states`、`current_state`、`_transitioning`、`_run_transition`;`state_changed` 信号。
- Produces:
  - `KitState`:`func pause() -> void`、`func resume() -> void`(default-pass)
  - `KitStateMachine`:`const MAX_STACK := 32`、`func push_state(state_name: String) -> void`、`func pop_state() -> void`、`func stack_depth() -> int`

- [ ] **Step 1a: 探针记录 pause/resume**

`test/fixtures/probe_state.gd` —— 用 Edit 把:

```gdscript
func update(delta: float) -> void:
	journal.append([String(name), "update", delta])
```

替换为:

```gdscript
func update(delta: float) -> void:
	journal.append([String(name), "update", delta])


func pause() -> void:
	journal.append([String(name), "pause"])


func resume() -> void:
	journal.append([String(name), "resume"])
```

- [ ] **Step 1b: 决策态探针支持 enter 里 push**

`test/fixtures/probe_decision_state.gd` —— 用 Edit 把:

```gdscript
var next_on_enter: String = ""       # enter 里 transition_to(该名)
var dispatch_on_enter: String = ""   # enter 里 machine.dispatch(该事件)


func enter(prev_state_name: String) -> void:
	super.enter(prev_state_name)
	if next_on_enter != "":
		transition_to(next_on_enter)
	elif dispatch_on_enter != "":
		machine.dispatch(dispatch_on_enter)
```

替换为:

```gdscript
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
```

- [ ] **Step 1c: 写失败测试(P8–P13)**

`test/test_state_machine.gd` —— 用 Edit 把(此时 Task 1 已把 E7 的 `m7.free()` 置于断言前):

```gdscript
	m7.free()

	if failures == 0:
```

替换为(在 `m7.free()` 与 `if failures == 0:` 之间插入 P8–P13):

```gdscript
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
		m11.push_state("Menu")   # 反复压(超上限的两次被 push_error 拒)
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

	if failures == 0:
```

- [ ] **Step 2: 运行,确认失败**

Run: `godot --headless --path . -s res://test/test_state_machine.gd`
Expected: FAIL —— stderr 出现 `SCRIPT ERROR: ... Nonexistent function 'push_state'`(或 `pop_state`/`stack_depth`),无 `ALL PASS`、exit 非 0。

- [ ] **Step 3a: KitState 加 pause/resume 虚方法**

`addons/godot-core-kit/state_machine/kit_state.gd` —— 用 Edit 把:

```gdscript
## 语法糖:machine.transition_to(state_name)。
func transition_to(state_name: String) -> void:
	if machine != null:
		machine.transition_to(state_name)
```

替换为:

```gdscript
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
```

- [ ] **Step 3b: KitStateMachine 加栈常量与字段**

`addons/godot-core-kit/state_machine/kit_state_machine.gd`:

**3b-1** 在 `const ANYSTATE := "*"` 之后加栈深守卫常量。用 Edit 把:

```gdscript
## 事件转移表的通配 from 状态名(保留名;子节点不得取此名)。
const ANYSTATE := "*"
```

替换为:

```gdscript
## 事件转移表的通配 from 状态名(保留名;子节点不得取此名)。
const ANYSTATE := "*"

## pushdown 栈深守卫(防无限 push)。
const MAX_STACK := 32
```

**3b-2** 在 `_transitions` 声明之后加栈字段。用 Edit 把:

```gdscript
var _transitions: Dictionary = {} # "from|event" -> to_name(事件派发转移表)
```

替换为:

```gdscript
var _transitions: Dictionary = {} # "from|event" -> to_name(事件派发转移表)
var _stack: Array[String] = []    # pushdown 被压挂起态名(栈底->栈顶)
```

- [ ] **Step 3c: 实现 push_state/pop_state/stack_depth**

`addons/godot-core-kit/state_machine/kit_state_machine.gd` —— 在 `dispatch` 方法之后(其 `return true` 那行之后、`_run_transition` 之前)插入。用 Edit 把:

```gdscript
	if _transitioning:
		_pending.append(to_name)
		return true
	_run_transition(String(current_state.name), _states[to_name])
	return true


## 执行一次转换,并按序消化期间入队的连锁转换(上限 MAX_CHAIN 防死循环)。
func _run_transition(from_name: String, to_state: KitState) -> void:
```

替换为:

```gdscript
	if _transitioning:
		_pending.append(to_name)
		return true
	_run_transition(String(current_state.name), _states[to_name])
	return true


## 压栈进入 state_name(暂停语义):current.pause() → 当前态入栈 → 进新态(enter)。
## 未知态 → push_warning + no-op;转换进行中 → push_warning + 拒绝;栈满 → push_error + 拒绝。
func push_state(state_name: String) -> void:
	if not _states.has(state_name):
		push_warning("KitStateMachine(%s): push_state 未知态 '%s',忽略" % [get_path(), state_name])
		return
	if _transitioning:
		push_warning("KitStateMachine(%s): 转换进行中拒绝 push_state('%s')" % [get_path(), state_name])
		return
	if _stack.size() >= MAX_STACK:
		push_error("KitStateMachine(%s): 栈深达上限 %d,拒绝 push_state('%s')" % [get_path(), MAX_STACK, state_name])
		return
	var paused_name := String(current_state.name)
	current_state.pause()
	_stack.append(paused_name)
	current_state = _states[state_name]
	current_state.enter(paused_name)
	state_changed.emit(paused_name, state_name)


## 弹栈恢复(暂停语义):current.exit(栈顶名) → 弹栈顶 → 切回该态 → 该态.resume()。
## 栈空 → push_warning + no-op;转换进行中 → push_warning + 拒绝。
func pop_state() -> void:
	if _stack.is_empty():
		push_warning("KitStateMachine(%s): 栈空,pop_state 忽略" % get_path())
		return
	if _transitioning:
		push_warning("KitStateMachine(%s): 转换进行中拒绝 pop_state" % get_path())
		return
	var active_name := String(current_state.name)
	var restored_name: String = _stack.pop_back()
	current_state.exit(restored_name)
	current_state = _states[restored_name]
	current_state.resume()
	state_changed.emit(active_name, restored_name)


## 只读当前 pushdown 栈深(调试/测试)。
func stack_depth() -> int:
	return _stack.size()


## 执行一次转换,并按序消化期间入队的连锁转换(上限 MAX_CHAIN 防死循环)。
func _run_transition(from_name: String, to_state: KitState) -> void:
```

- [ ] **Step 4: 运行,确认通过**

Run: `godot --headless --path . -s res://test/test_state_machine.gd`
Expected: PASS —— stdout `test_state_machine: ALL PASS`、exit 0(现有 9 + E1–E7 + P8–P13 全绿)。注:P11、P13 会向 stderr 打 `push_error`/`push_warning`,属预期诊断,不影响 `ALL PASS` 与 exit 0。

- [ ] **Step 5: 提交**

```bash
git add addons/godot-core-kit/state_machine/kit_state.gd addons/godot-core-kit/state_machine/kit_state_machine.gd test/fixtures/probe_state.gd test/fixtures/probe_decision_state.gd test/test_state_machine.gd
git commit -m "feat(state-machine): pushdown 栈 push_state/pop_state(暂停语义 + pause/resume 钩子)"
```

---

### Task 3: 版本 0.8.0 + 文档 + demo 冒烟 + 全量绿

**Files:**
- Modify: `test/test_core_kit.gd:25-26`(版本断言 0.7.0→0.8.0)
- Modify: `addons/godot-core-kit/core_kit.gd:13`(`const VERSION`)
- Modify: `addons/godot-core-kit/plugin.cfg`(`version` + `description`)
- Modify: `addons/godot-core-kit/docs/state-machine.md`(API 补充 + 两节新文档 + 注意事项)
- Modify: `addons/godot-core-kit/docs/architecture.md:89`(版本段)
- Modify: `README.md`(changelog 补 0.8.0)
- Modify: `demo/demo.gd:54-65`(状态机冒烟增 dispatch + push/pop)
- Modify: `test/run_all.ps1:72`(demo marker 列表)

**Interfaces:**
- Consumes:Task 1 的 `add_transition`/`dispatch`/`ANYSTATE`、Task 2 的 `push_state`/`pop_state`/`stack_depth`(demo 与文档引用)。
- Produces:无(收尾发版任务)。

- [ ] **Step 1: 版本断言先行改到 0.8.0(RED)**

`test/test_core_kit.gd` —— 用 Edit 把:

```gdscript
	if kit.VERSION != "0.7.0":
		print("FAIL 1: VERSION 应为 0.7.0,实际 %s" % kit.VERSION)
```

替换为:

```gdscript
	if kit.VERSION != "0.8.0":
		print("FAIL 1: VERSION 应为 0.8.0,实际 %s" % kit.VERSION)
```

- [ ] **Step 2: 运行版本测,确认失败**

Run: `godot --headless --path . -s res://test/test_core_kit.gd`
Expected: FAIL —— stdout `FAIL 1: VERSION 应为 0.8.0,实际 0.7.0`、exit 1。

- [ ] **Step 3: 同步版本三处的另外两处(GREEN)**

**3-1** `addons/godot-core-kit/core_kit.gd` —— 用 Edit 把:

```gdscript
const VERSION := "0.7.0"
```

替换为:

```gdscript
const VERSION := "0.8.0"
```

**3-2** `addons/godot-core-kit/plugin.cfg` —— 用 Edit 把:

```
description="Reusable Godot 4 GDScript foundation library for 2D games. CoreKit facade over core/ (Log, EventBus, Settings) and systems/ (SceneManager, ObjectPool, SaveManager, FrameScheduler, InputManager, AudioManager, ResourceManager), plus a KitStateMachine class library;新增 KitContext 层级服务容器(DI);0.6.0 KitContext 增订阅式解析 subscribe + 工厂式 scope provide_factory;0.7.0 SaveManager 增可插拔序列化 SaveSerializer + 原子写(temp+rename)+ 资源引用守卫"
author="luohao"
version="0.7.0"
```

替换为:

```
description="Reusable Godot 4 GDScript foundation library for 2D games. CoreKit facade over core/ (Log, EventBus, Settings) and systems/ (SceneManager, ObjectPool, SaveManager, FrameScheduler, InputManager, AudioManager, ResourceManager), plus a KitStateMachine class library;新增 KitContext 层级服务容器(DI);0.6.0 KitContext 增订阅式解析 subscribe + 工厂式 scope provide_factory;0.7.0 SaveManager 增可插拔序列化 SaveSerializer + 原子写(temp+rename)+ 资源引用守卫;0.8.0 KitStateMachine 增事件 dispatch 解耦 add_transition/dispatch(ANYSTATE 通配)+ pushdown push_state/pop_state(暂停语义)"
author="luohao"
version="0.8.0"
```

- [ ] **Step 4: 运行版本测,确认通过**

Run: `godot --headless --path . -s res://test/test_core_kit.gd`
Expected: PASS —— stdout `test_core_kit: ALL PASS`(或该测试的等价 ALL PASS 行)、exit 0。

- [ ] **Step 5: 文档 —— state-machine.md**

`addons/godot-core-kit/docs/state-machine.md`:

**5-1** KitState API 块补 `pause`/`resume`。用 Edit 把:

```gdscript
func transition_to(state_name: String) -> void     # 语法糖:machine.transition_to(state_name)
```

替换为:

```gdscript
func transition_to(state_name: String) -> void     # 语法糖:machine.transition_to(state_name)
func pause() -> void                                # 被 push_state 压栈让位时调用(暂停,现场保留)
func resume() -> void                               # 经 pop_state 弹回成为活动态时调用
```

**5-2** KitStateMachine API 块补新增面。用 Edit 把:

```gdscript
func transition_to(state_name: String) -> void    # 按状态名转换;未知名字 push_warning + 空操作
func get_state(state_name: String) -> KitState    # 按名取状态节点;未知名字返回 null
```

替换为:

```gdscript
const ANYSTATE := "*"                              # 事件转移表通配 from(保留名)
const MAX_STACK := 32                              # pushdown 栈深守卫

func transition_to(state_name: String) -> void    # 按状态名转换;未知名字 push_warning + 空操作
func get_state(state_name: String) -> KitState    # 按名取状态节点;未知名字返回 null
func add_transition(from_name: String, to_name: String, event: String) -> void  # 登记事件转移(from 可为 ANYSTATE)
func dispatch(event: String) -> bool               # 派发事件:命中则转移返回 true;无匹配静默 false
func push_state(state_name: String) -> void        # 压栈进新态(暂停语义,current.pause())
func pop_state() -> void                            # 弹栈回挂起态(current 弹出态.resume())
func stack_depth() -> int                           # 只读当前 pushdown 栈深
```

**5-3** 在「用法示例」的最后一个代码块之后、「## 注意事项」之前插入两节。用 Edit 把:

```gdscript
func update(_delta: float) -> void:
    if target_out_of_range():
        machine.transition_to("Idle")
```

## 注意事项
```

替换为:

```gdscript
func update(_delta: float) -> void:
    if target_out_of_range():
        machine.transition_to("Idle")
```

## 事件派发解耦(add_transition / dispatch)

除了状态里写死后继态名(`machine.transition_to("Idle")`),还可把转移集中登记到机器上,让状态只发**命名事件**、由机器决定后继:

```gdscript
machine.add_transition("Run", "Idle", "stop")            # Run 收到 stop → Idle
machine.add_transition(machine.ANYSTATE, "Dead", "die")  # 任意态收到 die → Dead(通配)

machine.dispatch("stop")   # 命中当前态转移,返回 true;无匹配静默返回 false
```

- **转移表**:key 为 `"<from>|<event>"`,`from` 为已注册态名或 `ANYSTATE`("*")。`add_transition` 目标态未注册 → `push_warning` 忽略;同 `(from, event)` 重复登记 → 覆盖并 `push_warning`。
- **匹配优先级**:`dispatch(event)` 先查当前态的具体转移 `(current, event)`,未命中再查通配 `(ANYSTATE, event)`;**具体 from 优先于通配**。两者都无匹配 → 静默返回 `false`(事件派发常态:多数事件在多数态无转移)。
- **复用转换核心**:命中后走与 `transition_to` 完全相同的路径——非转换中直接 `exit→enter→state_changed`(连锁 / `MAX_CHAIN` 语义不变),转换进行中则把目标入 `_pending` 队列。
- 与 `transition_to` **并存**:两种触发方式可混用,互不影响。

## pushdown 栈(push_state / pop_state,暂停语义)

菜单、暂停界面等"临时盖一层、回来还在原地"的场景,用 pushdown 栈:压当前态(**暂停**而非退出)、进临时态,弹回时被压态**现场保留**。

```gdscript
machine.push_state("PauseMenu")   # 暂停当前态(current.pause())、压栈、进 PauseMenu
# ……玩家在暂停菜单操作……
machine.pop_state()               # 退出 PauseMenu、弹回被压态、该态 resume()
machine.stack_depth()             # 当前栈深
```

- **暂停语义**:`push_state` 调被压态的 `pause()`(**不** `exit`),`pop_state` 调恢复态的 `resume()`(**不**重新 `enter`)。故被压态**不重置、现场保留**——这是与普通转移的本质区别。老状态子类不覆写 `pause`/`resume` 完全无感(default-pass)。
- **信号复用**:push/pop 改变 `current_state`,复用 `state_changed`(push 发 `(被压态, 新态)`、pop 发 `(被弹活动态, 恢复态)`),不新增专用信号。
- **栈存态名**:`_stack` 存被压态的名字;节点不销毁,`resume` 时仍是同一节点。`current_state` 始终是活动态(不在栈里)。
- **转发**:`update`/`physics_update`/`handle_input` 始终只转发 `current_state`,栈下挂起态不收。
- **守卫**:未知态 → `push_warning` no-op;栈满(≥ `MAX_STACK` = 32)→ `push_error` 拒绝;转换进行中(`_transitioning`)调 `push_state`/`pop_state` → `push_warning` 拒绝;栈空 `pop_state` → `push_warning` no-op。pushdown 不参与 `MAX_CHAIN` 连锁计数。
- **栈非空仍可转移**:`transition_to`/`dispatch` 照常替换 `current_state`(栈不动),`pop_state` 仍弹回栈下挂起态。

## 注意事项
```

**5-4** 「注意事项」末尾补两条。用 Edit 把:

```markdown
- 没有任何 `KitState` 子节点时状态机空转(`push_warning`),`current_state` 保持 `null`,不会报错但也没有任何状态生效。
```

替换为:

```markdown
- 没有任何 `KitState` 子节点时状态机空转(`push_warning`),`current_state` 保持 `null`,不会报错但也没有任何状态生效。
- **`ANYSTATE`("*")为保留名**:事件转移表用 "*" 表示通配 from;若某 `KitState` 子节点名恰为 "*",`_ready` 注册时 `push_error`(该名会与通配 key 混淆)。
- **pushdown 是暂停不是转移**:`push_state`/`pop_state` 走 `pause`/`resume` 钩子,被压态现场保留;需要重置就用 `transition_to`。
```

- [ ] **Step 6: 文档 —— architecture.md 版本段**

`addons/godot-core-kit/docs/architecture.md` —— 用 Edit 把:

```markdown
当前 `0.7.0`(`plugin.cfg` 与 `CoreKit.VERSION` 同源)。0.6.0→0.7.0 给 SaveManager 叠加可插拔序列化(`SaveSerializer` 基类 + 默认 `JsonSaveSerializer`,逐字节兼容旧 `.json`)、原子写(temp+rename)、资源引用安全守卫(拒 Object/Callable/Signal/RID),纯增量、向后兼容;
```

替换为:

```markdown
当前 `0.8.0`(`plugin.cfg` 与 `CoreKit.VERSION` 同源)。0.7.0→0.8.0 给 KitStateMachine 叠加事件 dispatch 解耦(`add_transition`/`dispatch` + `ANYSTATE` 通配,与 `transition_to` 并存)与 pushdown 栈(`push_state`/`pop_state`,暂停语义 + `KitState.pause`/`resume` 钩子),纯增量、向后兼容;0.6.0→0.7.0 给 SaveManager 叠加可插拔序列化(`SaveSerializer` 基类 + 默认 `JsonSaveSerializer`,逐字节兼容旧 `.json`)、原子写(temp+rename)、资源引用安全守卫(拒 Object/Callable/Signal/RID),纯增量、向后兼容;
```

- [ ] **Step 7: 文档 —— README changelog**

`README.md` —— 用 Edit 把:

```markdown
- **0.7.0** — `SaveManager` 叠加可插拔序列化(`SaveSerializer` 基类 + 默认 `JsonSaveSerializer`,逐字节兼容旧 `.json`)、原子写(temp+rename)、资源引用安全守卫(拒 Object/Callable/Signal/RID);纯增量,API 无破坏。
```

替换为:

```markdown
- **0.8.0** — `KitStateMachine` 叠加事件 dispatch 解耦(`add_transition`/`dispatch` + `ANYSTATE` 通配,与 `transition_to` 并存)与 pushdown 栈(`push_state`/`pop_state`,暂停语义 + `KitState.pause`/`resume` 钩子);纯增量,API 无破坏。
- **0.7.0** — `SaveManager` 叠加可插拔序列化(`SaveSerializer` 基类 + 默认 `JsonSaveSerializer`,逐字节兼容旧 `.json`)、原子写(temp+rename)、资源引用安全守卫(拒 Object/Callable/Signal/RID);纯增量,API 无破坏。
```

- [ ] **Step 8: demo 冒烟增 dispatch + push/pop**

`demo/demo.gd` —— 用 Edit 把:

```gdscript
	# KitStateMachine 冒烟:代码组一台两态状态机(类库,不经门面)
	var machine := KitStateMachine.new()
	var idle := KitState.new()
	idle.name = "Idle"
	machine.add_child(idle)
	var run := KitState.new()
	run.name = "Run"
	machine.add_child(run)
	machine.state_changed.connect(func(from: String, to: String) -> void:
		CoreKit.log.info("KitStateMachine: [%s] -> [%s]" % [from, to]))
	add_child(machine)          # 触发 _ready:进 Idle
	machine.transition_to("Run")
```

替换为:

```gdscript
	# KitStateMachine 冒烟:代码组一台三态状态机(类库,不经门面)——transition_to + dispatch + pushdown
	var machine := KitStateMachine.new()
	var idle := KitState.new()
	idle.name = "Idle"
	machine.add_child(idle)
	var run := KitState.new()
	run.name = "Run"
	machine.add_child(run)
	var menu := KitState.new()
	menu.name = "Menu"
	machine.add_child(menu)
	machine.state_changed.connect(func(from: String, to: String) -> void:
		CoreKit.log.info("KitStateMachine: [%s] -> [%s]" % [from, to]))
	add_child(machine)          # 触发 _ready:进 Idle
	machine.transition_to("Run")
	machine.add_transition(machine.ANYSTATE, "Idle", "stop")   # 通配事件:任意态收到 stop → Idle
	CoreKit.log.info("KitStateMachine: dispatch(stop) hit=%s" % machine.dispatch("stop"))  # Run --stop--> Idle
	machine.push_state("Menu")  # 暂停 Idle,压栈,进 Menu(暂停语义)
	machine.pop_state()         # 弹回 Idle(resume),现场保留
	CoreKit.log.info("KitStateMachine: stack_depth=%d" % machine.stack_depth())
```

- [ ] **Step 9: run_all.ps1 demo marker 列表补 3 项**

`test/run_all.ps1` —— 用 Edit 把:

```powershell
foreach ($e in @('all subsystems smoke-tested','FrameScheduler:','ResourceManager:','KitContext:','-> [Idle]','-> [Run]')) {
```

替换为:

```powershell
foreach ($e in @('all subsystems smoke-tested','FrameScheduler:','ResourceManager:','KitContext:','-> [Idle]','-> [Run]','-> [Menu]','dispatch(stop) hit=true','stack_depth=0')) {
```

- [ ] **Step 10: 全量绿**

Run: `& .\test\run_all.ps1`
Expected: 末行 `=== SUMMARY FAILS=0 ===` —— 13 个测试全 `OK`(含 `test_state_machine`、`test_core_kit`),9 个 demo marker 全 `present`(含新增 `-> [Menu]`、`dispatch(stop) hit=true`、`stack_depth=0`),`demo stderr has ERROR: no`。

- [ ] **Step 11: 提交**

```bash
git add addons/godot-core-kit/core_kit.gd addons/godot-core-kit/plugin.cfg test/test_core_kit.gd addons/godot-core-kit/docs/state-machine.md addons/godot-core-kit/docs/architecture.md README.md demo/demo.gd test/run_all.ps1
git commit -m "chore(state-machine): 版本 0.8.0 + 文档 + demo 冒烟(dispatch/pushdown)"
```

---

## Self-Review

**1. Spec coverage(逐 §7 测试项 + §4 API + §8 发版):**

| spec 项 | 落点 |
|---|---|
| §7.1 dispatch 命中具体 from | Task 1 E1 |
| §7.2 ANYSTATE 通配 | Task 1 E2 |
| §7.3 具体优先通配 | Task 1 E3 |
| §7.4 无匹配 false/不变 | Task 1 E4 |
| §7.5 重复 add_transition 覆盖 | Task 1 E5 |
| §7.6 dispatch 复用转换核心(exit→enter、state_changed) | Task 1 E6 |
| §7.7 转换中 dispatch 入队 | Task 1 E7 |
| §7.8 push pause/栈深/enter/信号 | Task 2 P8 |
| §7.9 pop exit/栈深/resume 不重 enter/信号 | Task 2 P9 |
| §7.10 栈空 pop no-op | Task 2 P10 |
| §7.11 MAX_STACK 守卫 | Task 2 P11 |
| §7.12 push 后 update 只转发活动态 | Task 2 P12 |
| §7.13 push/pop 转换中拒绝 | Task 2 P13 |
| §7.14 现有 9 组回归 | 三个任务每次 `test_state_machine` 全量重跑,断言逐字保留 |
| §4 API(ANYSTATE/MAX_STACK/add_transition/dispatch/push_state/pop_state/stack_depth/pause/resume) | Task 1 Step 3、Task 2 Step 3 |
| §3.4.6 子节点名撞 "*" push_error | Task 1 Step 3-3(诊断守卫;§7 未列独立断言,与其余 push_warning 诊断路径同处理) |
| §8 版本三处同步 | Task 3 Step 1/3 |
| §8 文档(state-machine.md 两节 + architecture.md + README) | Task 3 Step 5/6/7 |
| §8 demo 冒烟 dispatch + push/pop | Task 3 Step 8/9 |

覆盖完整,无缺口。

**2. Placeholder scan:** 无 TBD/TODO/"类似上文"/裸描述;每个代码步给出完整 old/new 文本。通过。

**3. Type consistency:** `add_transition(from_name, to_name, event) -> void`、`dispatch(event) -> bool`、`push_state(state_name) -> void`、`pop_state() -> void`、`stack_depth() -> int`、`pause()/resume() -> void`、`ANYSTATE := "*"`、`MAX_STACK := 32`、`_transitions: Dictionary`、`_stack: Array[String]` 在 API 块、实现、文档、测试引用处名字与签名一致。demo 用 `machine.ANYSTATE`、探针用 `machine.dispatch`/`machine.push_state`(实例访问 const / 方法,GDScript 合法)。通过。

**编码注意:** `run_all.ps1` 的新 marker 全用 ASCII(`-> [Menu]`、`dispatch(stop) hit=true`、`stack_depth=0`),避开 PowerShell 5.1 读非 BOM UTF-8 中文的坑;demo 里对应的 `CoreKit.log.info` 文本亦为 ASCII。
