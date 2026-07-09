# KitContext DI 容器 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 godot-core-kit 加一个对外开放的服务定位器:CoreKit 全局根 + 节点绑定的层级作用域容器 `KitContext`。

**Architecture:** CoreKit 门面新增一张全局服务表(`provide/service/has/service_or`),`_ready` 里把 10 个内置子系统按 key 预注册。新增 `class_name KitContext extends Node`(off-facade 类库,放 `di/`):挂在场景树上,`service(key)` 沿本层 → 最近祖先容器 → CoreKit 全局根逐层解析,子层可 shadow,生命周期随节点。`provide` 只存引用,`provide_child` 收养为子节点。

**Tech Stack:** Godot 4.7 / 纯 GDScript / Web 导出兼容;headless `-s` SceneTree 断言测试;PowerShell runner。

## Global Constraints

- **版本 0.5.0**:三处同源必须一致 —— `plugin.cfg` 的 `version=`、`core_kit.gd` 的 `const VERSION`、`test_core_kit.gd` 的 VERSION 断言。
- **缩进用 Tab**(全仓库),不用空格。
- **子系统不加 `class_name`**;但 `KitContext` 是 off-facade 类库,**允许**且**应当**加 `class_name`(同 `KitStateMachine`)。
- **测试约定**:`extends SceneTree`,`_initialize()` 里**运行时 `load(...)`**(不用顶层 `const preload`);每次 `add_child` 后 `await process_frame`;`failures` 计数;结尾 `print("test_x: ALL PASS"); quit(0)` 或 `... %d FAILURE(S); quit(1)`。
- **KitContext → CoreKit 依赖**只允许"树顶兜底"经 `get_tree().root.get_node_or_null("CoreKit")` 的 duck-typed `.call("service"/"has", ...)`,不引入类型耦合。
- **依赖纪律**:子系统之间仍禁止互相 `preload`;`di/` 不被 `core/`、`systems/` 依赖。
- **验收门**:`powershell -File test\run_all.ps1` 末行 `=== SUMMARY FAILS=0 ===`(import → 13 测试全 ALL PASS → demo 冒烟命中全部 marker、stderr 无 `ERROR:`/`SCRIPT ERROR:`)。

---

### Task 1: CoreKit 全局根服务表 + 版本升 0.5.0

**Files:**
- Modify: `addons/godot-core-kit/core_kit.gd`
- Modify: `addons/godot-core-kit/plugin.cfg`
- Test: `test/test_core_kit.gd`

**Interfaces:**
- Produces(供 Task 2/3 消费):
  - `CoreKit.provide(key: String, svc: Variant) -> void` —— 保留键拒绝,重复键覆盖告警。
  - `CoreKit.service(key: String) -> Variant` —— 未注册 → `push_error` + `null`(全链唯一报错点)。
  - `CoreKit.has(key: String) -> bool`
  - `CoreKit.service_or(key: String, fallback: Variant) -> Variant`
  - `CoreKit.RESERVED_KEYS: Array`(10 个内置属性名)
  - `CoreKit.VERSION == "0.5.0"`;`_ready` 后 `_services` 已含 10 个内置(`service("audio") == CoreKit.audio`)。

- [ ] **Step 1: 改回归测试 `test/test_core_kit.gd` —— VERSION 断言升级**

把版本断言从 0.4.1 改成 0.5.0。

old_string:
```gdscript
	# 1. 版本
	if kit.VERSION != "0.4.1":
		print("FAIL 1: VERSION 应为 0.4.1,实际 %s" % kit.VERSION)
		failures += 1
```
new_string:
```gdscript
	# 1. 版本
	if kit.VERSION != "0.5.0":
		print("FAIL 1: VERSION 应为 0.5.0,实际 %s" % kit.VERSION)
		failures += 1
```

- [ ] **Step 2: 改回归测试 —— 追加全局根断言(第 6 段,插在 `if failures == 0:` 之前)**

old_string:
```gdscript
	if failures == 0:
		print("test_core_kit: ALL PASS")
```
new_string:
```gdscript
	# 6. 全局根:内置已按 key 预注册 + provide/service/has/service_or 冒烟
	var builtin_keys := ["log", "settings", "bus", "scenes", "pool", "saves",
		"ticker", "input", "audio", "res"]
	for k in builtin_keys:
		if kit.service(k) != kit.get(k):
			print("FAIL 6: CoreKit.service('%s') 未指向内置子系统" % k)
			failures += 1
	if not kit.has("audio"):
		print("FAIL 6: has('audio') 应为 true")
		failures += 1
	kit.provide("audio", 999)  # 保留键:应被拒,audio 仍指向内置
	if kit.service("audio") != kit.audio:
		print("FAIL 6: 保留键 audio 不应被 provide 覆盖")
		failures += 1
	kit.provide("__facade_custom__", 55)
	if kit.service("__facade_custom__") != 55:
		print("FAIL 6: 全局 provide/service 冒烟失败")
		failures += 1
	if kit.service_or("__facade_absent__", -1) != -1:
		print("FAIL 6: service_or 应返回 fallback")
		failures += 1

	if failures == 0:
		print("test_core_kit: ALL PASS")
```

- [ ] **Step 3: 跑测试确认失败(RED)**

Run: `godot --headless --path . -s res://test/test_core_kit.gd`
Expected: FAIL —— VERSION 断言不符 + `kit.provide/service` 方法不存在导致报错/未 ALL PASS。

- [ ] **Step 4: 改 `core_kit.gd` —— VERSION + RESERVED_KEYS**

old_string:
```gdscript
const VERSION := "0.4.1"
```
new_string:
```gdscript
const VERSION := "0.5.0"

## 全局根的保留键 = 10 个内置子系统的属性名。CoreKit.provide 拒绝覆盖这些键;
## 子作用域(KitContext)不受此限,可 shadow。
const RESERVED_KEYS := ["log", "settings", "bus", "scenes", "pool", "saves",
	"ticker", "input", "audio", "res"]
```

- [ ] **Step 5: 改 `core_kit.gd` —— 新增全局根注册表成员**

old_string:
```gdscript
var res: ResourceManagerScript
```
new_string:
```gdscript
var res: ResourceManagerScript

## 全局根服务注册表:key:String -> service:Variant。内置在 _ready 预注册,
## 游戏代码经 provide/service 增删查;KitContext 作用域向上回退最终兜底到这里。
var _services: Dictionary = {}
```

- [ ] **Step 6: 改 `core_kit.gd` —— `_ready` 预注册内置 + 四个全局根方法**

old_string:
```gdscript
func _ready() -> void:
	# 唯一的跨子系统接线点:此时全部子系统已各自 _ready 完毕。
	input.bind_settings(settings)
	audio.bind_settings(settings)
	res.bind_ticker(ticker)
	log.info("CoreKit v%s ready" % VERSION)
```
new_string:
```gdscript
func _ready() -> void:
	# 唯一的跨子系统接线点:此时全部子系统已各自 _ready 完毕。
	input.bind_settings(settings)
	audio.bind_settings(settings)
	res.bind_ticker(ticker)

	# 内置子系统按 key 预注册进全局根(强类型属性照旧保留),使 service("audio") 及
	# 任意 KitContext 作用域向上回退可达内置。直接写 _services,绕过 provide 的保留键自拒。
	_services["log"] = log
	_services["settings"] = settings
	_services["bus"] = bus
	_services["scenes"] = scenes
	_services["pool"] = pool
	_services["saves"] = saves
	_services["ticker"] = ticker
	_services["input"] = input
	_services["audio"] = audio
	_services["res"] = res

	log.info("CoreKit v%s ready" % VERSION)


## --- 全局根服务定位器(对外扩展点)------------------------------------------

## 注册一个全局服务。保留键(内置)拒绝;重复键覆盖并告警。
func provide(key: String, svc: Variant) -> void:
	if key in RESERVED_KEYS:
		push_error("CoreKit.provide('%s'): 保留键(内置子系统),不可覆盖" % key)
		return
	if _services.has(key):
		push_warning("CoreKit.provide('%s'): 覆盖已注册全局服务" % key)
	_services[key] = svc


## 取全局服务;未注册 → push_error + null(整条解析链唯一的"未找到"报错点)。
func service(key: String) -> Variant:
	if _services.has(key):
		return _services[key]
	push_error("CoreKit.service('%s'): 未注册" % key)
	return null


## 不报错的存在性检查。
func has(key: String) -> bool:
	return _services.has(key)


## 取全局服务;未注册返回 fallback,不报错。
func service_or(key: String, fallback: Variant) -> Variant:
	return _services[key] if _services.has(key) else fallback
```

- [ ] **Step 7: 跑测试确认通过(GREEN)**

Run: `godot --headless --path . -s res://test/test_core_kit.gd`
Expected: `test_core_kit: ALL PASS`,exit 0。

- [ ] **Step 8: 同步 `plugin.cfg` 版本与描述**

先 Read `addons/godot-core-kit/plugin.cfg`。把 `version="0.4.1"` 改为 `version="0.5.0"`;并在 `description="..."` 引号内文字末尾追加一句 `;新增 KitContext 层级服务容器(DI)`。

- [ ] **Step 9: Commit**

```bash
git add addons/godot-core-kit/core_kit.gd addons/godot-core-kit/plugin.cfg test/test_core_kit.gd
git commit -m "feat: add CoreKit global service registry (provide/service), bump 0.5.0"
```

---

### Task 2: KitContext 节点绑定层级服务定位器

**Files:**
- Create: `addons/godot-core-kit/di/kit_context.gd`
- Test: `test/test_kit_context.gd`

**Interfaces:**
- Consumes(来自 Task 1):`CoreKit.service(key)` / `CoreKit.has(key)`(经节点查找 duck-typed 调用,作树顶兜底)。
- Produces(供 Task 3 消费):
  - `class_name KitContext extends Node`
  - 实例:`provide(key, svc)`、`provide_child(key, node)`、`service(key) -> Variant`、`has(key) -> bool`、`service_or(key, fallback) -> Variant`
  - 静态:`KitContext.of(node) -> KitContext`、`KitContext.resolve(node, key) -> Variant`

- [ ] **Step 1: 写失败测试 `test/test_kit_context.gd`(完整文件)**

```gdscript
extends SceneTree
## KitContext headless 断言测试。经 load 脚本 + .new() 直接实例化,挂 root 入树。
## 坑:每次 add_child 后 await process_frame,_enter_tree/_ready 才落定(见 test_state_machine 头注释)。
## 树顶兜底测试依赖 CoreKit autoload(headless 下会加载);多次 await 后其 _ready 预注册内置已完成。
## 运行:godot --headless --path . -s res://test/test_kit_context.gd(须先 --import 生成 KitContext 类缓存)

const CTX_PATH := "res://addons/godot-core-kit/di/kit_context.gd"


func _initialize() -> void:
	var failures := 0
	var KC = load(CTX_PATH)

	# --- 1. 本层 provide / service 命中 + has ---
	var a = KC.new()
	a.name = "A"
	root.add_child(a)
	await process_frame
	a.provide("svc", 123)
	if a.service("svc") != 123:
		print("FAIL 1: 本层 service 未命中")
		failures += 1
	if not a.has("svc"):
		print("FAIL 1: has('svc') 应为 true")
		failures += 1

	# --- 2. miss 行为:service→null, service_or→fallback, has→false ---
	if a.service("nope") != null:
		print("FAIL 2: miss 的 service 应为 null")
		failures += 1
	if a.service_or("nope", 7) != 7:
		print("FAIL 2: service_or 应返回 fallback")
		failures += 1
	if a.has("nope"):
		print("FAIL 2: has('nope') 应为 false")
		failures += 1

	# --- 3. provide_child 收养;provide 不动树;provide_child 拒绝已有父 ---
	var owned := Node.new()
	owned.name = "Owned"
	a.provide_child("owned", owned)
	if owned.get_parent() != a:
		print("FAIL 3: provide_child 未收养为子节点")
		failures += 1
	var refonly := Node.new()
	refonly.name = "RefOnly"
	a.provide("refonly", refonly)
	if refonly.get_parent() != null:
		print("FAIL 3: provide 不应 reparent(应保持无父)")
		failures += 1
	var parented := Node.new()
	a.add_child(parented)
	a.provide_child("parented", parented)  # 已有父 → 应拒绝
	if a.has("parented"):
		print("FAIL 3: provide_child 应拒绝已有父节点")
		failures += 1

	# --- 4. 父子两层:向上回退 + shadow ---
	var parent := KC.new()
	parent.name = "Parent"
	root.add_child(parent)
	await process_frame
	var child := KC.new()
	child.name = "Child"
	parent.add_child(child)
	await process_frame
	parent.provide("p_only", "P")
	parent.provide("shared", "parent_val")
	child.provide("shared", "child_val")  # shadow 父层
	if child.service("p_only") != "P":
		print("FAIL 4: 子容器未向上回退到父层")
		failures += 1
	if child.service("shared") != "child_val":
		print("FAIL 4: 子容器未 shadow 父层同名键")
		failures += 1
	if parent.service("shared") != "parent_val":
		print("FAIL 4: 父层不应被子层影响")
		failures += 1

	# --- 5. 静态 of() / resolve() ---
	var leaf := Node.new()
	leaf.name = "Leaf"
	child.add_child(leaf)
	await process_frame
	if KC.of(leaf) != child:
		print("FAIL 5: of() 未找到最近祖先容器")
		failures += 1
	if KC.of(child) != child:
		print("FAIL 5: of() 应含自身")
		failures += 1
	if KC.resolve(leaf, "p_only") != "P":
		print("FAIL 5: resolve 未向上解析到父层")
		failures += 1
	if KC.resolve(leaf, "shared") != "child_val":
		print("FAIL 5: resolve 未命中最近 shadow")
		failures += 1

	# --- 6. 树顶兜底:命中 CoreKit 内置 ---
	var ck = root.get_node_or_null("CoreKit")
	if ck == null:
		print("FAIL 6: CoreKit autoload 缺失")
		failures += 1
	else:
		if a.service("audio") != ck.audio:
			print("FAIL 6: 兜底未命中内置 audio")
			failures += 1
		if KC.resolve(leaf, "log") != ck.log:
			print("FAIL 6: resolve 兜底未命中内置 log")
			failures += 1

	# --- 7. provide_child 随容器 free 释放;ref-only 不释放 ---
	a.free()
	await process_frame
	if is_instance_valid(owned):
		print("FAIL 7: provide_child 的节点应随容器释放")
		failures += 1
	if not is_instance_valid(refonly):
		print("FAIL 7: ref-only 节点不应被容器释放")
		failures += 1
	if is_instance_valid(refonly):
		refonly.free()

	if failures == 0:
		print("test_kit_context: ALL PASS")
		quit(0)
	else:
		print("test_kit_context: %d FAILURE(S)" % failures)
		quit(1)
```

- [ ] **Step 2: 跑测试确认失败(RED)**

Run: `godot --headless --path . -s res://test/test_kit_context.gd`
Expected: FAIL —— `load(CTX_PATH)` 返回 null(文件不存在),`KC.new()` 报错。

- [ ] **Step 3: 写实现 `addons/godot-core-kit/di/kit_context.gd`(完整文件)**

```gdscript
class_name KitContext
extends Node
## KitContext —— 节点绑定的层级服务定位器(off-facade 类库,不挂门面)。
## 挂在场景树子树根;子树内经静态 resolve()/of() 或 ctx.service() 按字符串 key 取服务。
## 解析:本层 _local → 最近祖先容器 _parent_ctx → 树顶兜底 CoreKit 全局根。子层可 shadow。
## 生命周期随节点:NOTIFICATION_PREDELETE 清注册表;provide_child 的子节点随本节点释放。
## 依赖:仅"树顶兜底"经节点查找 duck-typed 调用 CoreKit,单向、无类型耦合。
## 首次引用本 class_name 的脚本须先跑一次 `godot --headless --path . --import` 生成类缓存。

var _local: Dictionary = {}          # key:String -> service:Variant
var _parent_ctx: KitContext = null   # 最近的严格祖先容器(不含自己),_enter_tree 重算


## 注册服务到本层。只存引用,绝不动树。重复键覆盖并告警。可 shadow 祖先/全局同名键。
func provide(key: String, svc: Variant) -> void:
	if _local.has(key):
		push_warning("KitContext.provide('%s'): 覆盖同层已注册服务" % key)
	_local[key] = svc


## 收养一个无父节点为子节点并注册;随本容器释放。node 已有父 → push_error 跳过。
func provide_child(key: String, node: Node) -> void:
	if node.get_parent() != null:
		push_error("KitContext.provide_child('%s'): 需要无父节点,请先自行 reparent" % key)
		return
	add_child(node)
	if _local.has(key):
		push_warning("KitContext.provide_child('%s'): 覆盖同层已注册服务" % key)
	_local[key] = node


## 解析:本层 → 最近祖先容器 → CoreKit 全局根。
func service(key: String) -> Variant:
	if _local.has(key):
		return _local[key]
	if _parent_ctx != null:
		return _parent_ctx.service(key)
	return _global(key)


## 沿同一条链的存在性检查,不报错。
func has(key: String) -> bool:
	if _local.has(key):
		return true
	if _parent_ctx != null:
		return _parent_ctx.has(key)
	var ck := _corekit()
	return ck != null and bool(ck.call("has", key))


## 沿链解析;整链 miss 返回 fallback,不报错。
func service_or(key: String, fallback: Variant) -> Variant:
	if has(key):
		return service(key)
	return fallback


## 树顶兜底:duck-typed 调用 CoreKit.service;无 CoreKit(如隔离单测)优雅返回 null。
func _global(key: String) -> Variant:
	var ck := _corekit()
	if ck == null:
		return null
	return ck.call("service", key)


func _corekit() -> Node:
	var t := get_tree()
	if t == null:
		return null
	return t.root.get_node_or_null("CoreKit")


func _enter_tree() -> void:
	_parent_ctx = _find_parent_ctx()


func _find_parent_ctx() -> KitContext:
	var n := get_parent()
	while n != null:
		if n is KitContext:
			return n as KitContext
		n = n.get_parent()
	return null


func _notification(what: int) -> void:
	# disposal 走 PREDELETE:_exit_tree 在 reparent 时也触发,不能用来清表。
	if what == NOTIFICATION_PREDELETE:
		_local.clear()


## 从 node 起(含自身)向上找最近容器;树中无容器 → null。
static func of(node: Node) -> KitContext:
	var n := node
	while n != null:
		if n is KitContext:
			return n as KitContext
		n = n.get_parent()
	return null


## 非容器节点的解析入口:of(node) 命中即取,否则兜底 CoreKit 全局根。
static func resolve(node: Node, key: String) -> Variant:
	var c := of(node)
	if c != null:
		return c.service(key)
	var t := node.get_tree()
	if t == null:
		return null
	var ck := t.root.get_node_or_null("CoreKit")
	if ck == null:
		return null
	return ck.call("service", key)
```

- [ ] **Step 4: 生成类缓存并跑测试确认通过(GREEN)**

Run: `godot --headless --path . --import`
再 Run: `godot --headless --path . -s res://test/test_kit_context.gd`
Expected: `test_kit_context: ALL PASS`,exit 0。

- [ ] **Step 5: Commit**

```bash
git add addons/godot-core-kit/di/kit_context.gd addons/godot-core-kit/di/kit_context.gd.uid test/test_kit_context.gd
git commit -m "feat: add KitContext node-bound hierarchical service locator"
```
> 注:`.gd.uid` 由 `--import` 生成;若 `git status` 未见该文件,去掉它再提交即可。

---

### Task 3: 接入 runner + demo 冒烟(全量验收)

**Files:**
- Modify: `test/run_all.ps1`
- Modify: `demo/demo.gd`

**Interfaces:**
- Consumes:`KitContext`(Task 2)、`CoreKit.provide/service`(Task 1)。
- Produces:runner 的 `$tests` 含 `test_kit_context`;demo stdout 含 `KitContext:` marker。

- [ ] **Step 1: `test/run_all.ps1` —— `$tests` 加 test_kit_context(放 test_core_kit 之前)**

old_string:
```powershell
  'test_input_manager','test_audio_manager','test_resource_manager','test_core_kit')
```
new_string:
```powershell
  'test_input_manager','test_audio_manager','test_resource_manager','test_kit_context','test_core_kit')
```

- [ ] **Step 2: `test/run_all.ps1` —— 头注释测试数 12 → 13**

old_string:
```powershell
# godot-core-kit 全量验证:import -> 12 个断言测试 -> demo 冒烟
```
new_string:
```powershell
# godot-core-kit 全量验证:import -> 13 个断言测试 -> demo 冒烟
```

- [ ] **Step 3: `test/run_all.ps1` —— demo marker 列表加 `KitContext:`**

old_string:
```powershell
foreach ($e in @('all subsystems smoke-tested','FrameScheduler:','ResourceManager:','-> [Idle]','-> [Run]')) {
```
new_string:
```powershell
foreach ($e in @('all subsystems smoke-tested','FrameScheduler:','ResourceManager:','KitContext:','-> [Idle]','-> [Run]')) {
```

- [ ] **Step 4: `demo/demo.gd` —— 加 KitContext 冒烟块(插在最后一行汇总 log 之前)**

old_string:
```gdscript
	CoreKit.log.info("CoreKit v%s — all subsystems smoke-tested" % CoreKit.VERSION)
```
new_string:
```gdscript
	# KitContext 冒烟:全局 provide/service + 作用域容器 + 收养随树释放(DI 容器,类库)
	CoreKit.provide("demo_service", {"id": 7})
	var ctx := KitContext.new()
	ctx.name = "DemoCtx"
	add_child(ctx)
	ctx.provide("scoped", "level-only")
	ctx.provide_child("owned_child", Node.new())
	CoreKit.log.info("KitContext: scoped=%s global=%s builtin_audio=%s owned=%d" % [
		KitContext.resolve(ctx, "scoped"),
		KitContext.resolve(ctx, "demo_service"),
		ctx.service("audio") == CoreKit.audio,
		ctx.get_child_count()])
	ctx.free()  # 随树释放,收养的子节点连带回收

	CoreKit.log.info("CoreKit v%s — all subsystems smoke-tested" % CoreKit.VERSION)
```

- [ ] **Step 5: 全量验收(GREEN)**

Run: `powershell -File test\run_all.ps1`
Expected: 末行 `=== SUMMARY FAILS=0 ===`;13 个测试各 `pass=True OK`(含 test_kit_context、test_core_kit);demo marker `KitContext:` present;demo stderr `no`。

- [ ] **Step 6: Commit**

```bash
git add test/run_all.ps1 demo/demo.gd
git commit -m "test: wire test_kit_context into runner; add KitContext demo smoke"
```

---

### Task 4: 文档 + 技能同步

**Files:**
- Create: `addons/godot-core-kit/docs/di/kit-context.md`
- Modify: `addons/godot-core-kit/docs/architecture.md`
- Modify: `addons/godot-core-kit/docs/README.md`
- Modify: `README.md`
- Modify: `.claude/skills/using-core-kit/SKILL.md`
- Modify: `.claude/skills/developing-core-kit/SKILL.md`

**Interfaces:**
- Consumes:全部前序任务的最终 API(文档描述之)。
- Produces:随插件分发的 KitContext 文档 + 索引/路由/技能指针同步。
- 说明:本任务纯文档/指针同步,无行为规则变更,故不需要 skill-TDD 基线;"测试"= 文档链接可解析 + `run_all.ps1` 仍 `FAILS=0`。

- [ ] **Step 1: 新建 `addons/godot-core-kit/docs/di/kit-context.md`(完整文件)**

```markdown
# KitContext —— 节点绑定的层级服务容器

> `class_name KitContext` · `di/kit_context.gd` · off-facade 类库(不挂门面)

## 职责

给使用 core-kit 的游戏代码一个**开放的服务定位器**:把自己的服务按字符串 key 注册进来、按 key 取。容器是场景树上的节点,解析沿祖先链向上回退、树顶兜底到 CoreKit 全局根,生命周期随节点。用于关卡级 / 实体级作用域服务,以及全局服务(经 `CoreKit.provide/service`)。

不是自动装配 / IoC 容器:不解析服务间依赖,消费方 pull(自己 `service(key)` 取)。

## 公开 API

### 全局根(CoreKit,整局作用域)

| 成员 | 说明 |
|---|---|
| `CoreKit.provide(key, svc) -> void` | 注册全局服务。保留键(10 个内置)拒绝;重复键覆盖告警。 |
| `CoreKit.service(key) -> Variant` | 取;未注册 → push_error + null。 |
| `CoreKit.has(key) -> bool` | 存在性,不报错。 |
| `CoreKit.service_or(key, fallback) -> Variant` | 未注册返回 fallback。 |

10 个内置子系统已按属性名预注册(`service("audio") == CoreKit.audio`),但内置首选仍走强类型属性(有补全 + 类型)。

### 作用域容器(KitContext,挂节点)

| 成员 | 说明 |
|---|---|
| `provide(key, svc) -> void` | 注册到本层,只存引用,绝不动树。重复键覆盖告警。可 shadow 祖先/全局同名键。 |
| `provide_child(key, node) -> void` | 收养:node 须无父(否则 push_error 跳过),`add_child` 后注册,随本容器释放。 |
| `service(key) -> Variant` | 本层 → 最近祖先容器 → CoreKit 全局根,逐层解析。 |
| `has(key) -> bool` / `service_or(key, fallback)` | 沿同一条链,不报错。 |
| `static of(node) -> KitContext` | node 自身或最近祖先容器;无 → null。 |
| `static resolve(node, key) -> Variant` | `of(node)` 命中即取,否则兜底全局根。非容器节点解析用它。 |

## 依赖

- 单向依赖 CoreKit autoload:仅"树顶兜底"经 `get_tree().root.get_node_or_null("CoreKit")` duck-typed 调用其 `service`/`has`。不引入类型耦合,与"人人可用 `CoreKit.log`"的全局链一致。
- 不被 `core/`、`systems/` 依赖;与 `state_machine/` 同为 off-facade 类库层。

## 用法示例

全局服务(整局可见):
```gdscript
CoreKit.provide("analytics", AnalyticsClient.new())
CoreKit.service("analytics").track("level_start")
CoreKit.service("audio").play_bgm("theme")   # 内置也可按 key 取
```

关卡作用域(随关卡卸载回收):
```gdscript
func _ready() -> void:
    var ctx := KitContext.new(); ctx.name = "LevelCtx"
    add_child(ctx)
    ctx.provide("spawner", BossSpawner.new())      # 只在本关可见
    ctx.provide_child("music", LevelMusic.new())   # 归 ctx,切关自动释放

# 关卡内任意节点
var spawner = KitContext.resolve(self, "spawner")   # 命中 LevelCtx
var save = KitContext.resolve(self, "save_cloud")   # LevelCtx miss → 兜底全局
```

实体作用域(配合状态机):
```gdscript
# enemy 根做成 / 挂一个 KitContext,provide("blackboard", bb)
# 该敌人子树内 resolve("blackboard") 命中本体,resolve("spawner") 向上命中 LevelCtx
# —— 与 per-entity KitStateMachine 同一心智。
```

## 注意事项

- **shadow**:子容器 `provide` 同名 key 即在子树内覆盖父层/全局(含内置)。
- **归属**:`provide` 只存引用、绝不 reparent;要随作用域释放用 `provide_child`(或自己 add_child 到该容器后再 provide)。
- **生命周期**:disposal 走 `NOTIFICATION_PREDELETE`(非 `_exit_tree`,后者 reparent 也触发);`provide_child` 的子节点随容器 free 连带释放。
- **class_name 缓存**:首次引用 `KitContext` 的脚本须先 `godot --headless --path . --import`。
- **热路径**:`resolve` 每次向上走 `get_parent()` 链;高频访问在 `_ready` 里 pull 一次存成员,别每帧解析。
- **autoload 非祖先**:树顶兜底是显式定位 CoreKit(它是当前场景的兄弟),不靠向上 `get_parent()` 走到它。
```

- [ ] **Step 2: 改 `docs/architecture.md` —— 5 处**

(a) 开头简介:
old_string:
```markdown
面向 2D 游戏的 Godot 4 GDScript 底层框架。一个 autoload 门面 `CoreKit` 统管 10 个子系统,外加一套 per-entity 的状态机类库。
```
new_string:
```markdown
面向 2D 游戏的 Godot 4 GDScript 底层框架。一个 autoload 门面 `CoreKit` 统管 10 个子系统,外加状态机与服务容器(KitContext)两套 off-facade 类库。
```

(b) 目录布局:
old_string:
```markdown
  state_machine/         class_name 状态机类库
  docs/                  本文档目录
```
new_string:
```markdown
  state_machine/         class_name 状态机类库
  di/                    class_name 服务容器类库(KitContext)
  docs/                  本文档目录
```

(c) 新增章节,插在 `## 已知引擎坑` 之前:
old_string:
```markdown
## 已知引擎坑
```
new_string:
```markdown
## 扩展容器(KitContext / DI)

`CoreKit` 除 10 个内置子系统外,还提供一个**对外开放的服务定位器**,让游戏代码注册自己的服务:

- **全局根**:`CoreKit.provide(key, svc)` / `service(key)` / `has(key)` / `service_or(key, fallback)`。10 个内置已按属性名预注册(`service("audio") == CoreKit.audio`),但内置首选仍走强类型属性。`provide` 拒绝覆盖内置保留键。
- **作用域容器** `KitContext`(`class_name`,挂在场景树节点上):`provide` / `provide_child` / `service`。解析沿祖先链向上回退、树顶兜底全局根;子层可 shadow;生命周期随节点(`NOTIFICATION_PREDELETE` 清表,`provide_child` 的子节点连带释放)。静态 `KitContext.of(node)` / `resolve(node, key)` 供非容器节点解析。
- 依赖方向:`KitContext → CoreKit` 单向(仅树顶兜底 duck-typed 调用),属"全局链"合法通道,不违反子系统依赖纪律。
- 详见 [di/kit-context.md](di/kit-context.md)。

## 已知引擎坑
```

(d) 测试段计数:
old_string:
```markdown
一键全量:`powershell -File test\run_all.ps1`(import → 12 测试 → demo 冒烟,末行 `FAILS=0` 为全绿)。
```
new_string:
```markdown
一键全量:`powershell -File test\run_all.ps1`(import → 13 测试 → demo 冒烟,末行 `FAILS=0` 为全绿)。
```

(e) 版本段:
old_string:
```markdown
当前 `0.4.1`(`plugin.cfg` 与 `CoreKit.VERSION` 同源)。0.3.x→0.4.0 是破坏性变更(五个老全局单例名下线,统一走 `CoreKit` 门面);0.4.1 为纯目录重排,对使用者 API 无破坏。
```
new_string:
```markdown
当前 `0.5.0`(`plugin.cfg` 与 `CoreKit.VERSION` 同源)。0.4.1→0.5.0 新增 KitContext 服务容器(纯增量,对既有 API 无破坏);0.3.x→0.4.0 是破坏性变更(五个老全局单例名下线,统一走 `CoreKit` 门面);0.4.1 为纯目录重排。
```

- [ ] **Step 3: 改 `docs/README.md` —— 2 处**

(a) 开头简介:
old_string:
```markdown
面向 2D 游戏的 Godot 4 GDScript 底层框架。一个 autoload 门面 `CoreKit` 统管 10 个子系统,外加一套 per-entity 状态机类库。
```
new_string:
```markdown
面向 2D 游戏的 Godot 4 GDScript 底层框架。一个 autoload 门面 `CoreKit` 统管 10 个子系统,外加状态机与服务容器两套 off-facade 类库。
```

(b) 类库小节(改标题 + 加行):
old_string:
```markdown
### 状态机类库

| 文档 | 访问 | 一句话 |
|---|---|---|
| [state-machine](state-machine.md) | `class_name KitStateMachine` | Node 型有限状态机,每个实体自己一台(不挂门面) |
```
new_string:
```markdown
### 类库(off-facade,不挂门面)

| 文档 | 访问 | 一句话 |
|---|---|---|
| [state-machine](state-machine.md) | `class_name KitStateMachine` | Node 型有限状态机,每个实体自己一台 |
| [kit-context](di/kit-context.md) | `class_name KitContext` | 节点绑定的层级服务容器(DI):游戏代码注册自己的服务 |
```

- [ ] **Step 4: 改仓库 `README.md` —— 3 处**

(a) 开头简介末句:
old_string:
```markdown
通用 2D 游戏开发底层框架(Godot 4.7,纯 GDScript,Web 导出兼容)。单一 autoload 门面 `CoreKit` 暴露全部子系统;`KitStateMachine`/`KitState` 以 class_name 类库随插件分发。
```
new_string:
```markdown
通用 2D 游戏开发底层框架(Godot 4.7,纯 GDScript,Web 导出兼容)。单一 autoload 门面 `CoreKit` 暴露全部子系统;`KitStateMachine`/`KitState`、`KitContext` 以 class_name 类库随插件分发。
```

(b) 路由表加 KitContext 行:
old_string:
```markdown
| `KitStateMachine`(类库) | Node 型状态机 | [state-machine](addons/godot-core-kit/docs/state-machine.md) |
```
new_string:
```markdown
| `KitStateMachine`(类库) | Node 型状态机 | [state-machine](addons/godot-core-kit/docs/state-machine.md) |
| `KitContext`(类库) | 节点绑定的层级服务容器(DI) | [kit-context](addons/godot-core-kit/docs/di/kit-context.md) |
```

(c) 版本 changelog 加 0.5.0:
old_string:
```markdown
## 版本

- **0.4.1** — 子系统按角色归入 `core/` 与 `systems/`;新增 `addons/godot-core-kit/docs/` 架构文档。纯结构调整,API 无破坏。
```
new_string:
```markdown
## 版本

- **0.5.0** — 新增 `KitContext` 节点绑定层级服务容器(DI)+ `CoreKit` 全局根 `provide/service`;纯增量,API 无破坏。
- **0.4.1** — 子系统按角色归入 `core/` 与 `systems/`;新增 `addons/godot-core-kit/docs/` 架构文档。纯结构调整,API 无破坏。
```

- [ ] **Step 5: 改 `.claude/skills/using-core-kit/SKILL.md` —— 2 处**

(a) docs 清单加一行:
old_string:
```markdown
- `addons/godot-core-kit/docs/state-machine.md` —— KitStateMachine 类库。
```
new_string:
```markdown
- `addons/godot-core-kit/docs/state-machine.md` —— KitStateMachine 类库。
- `addons/godot-core-kit/docs/di/kit-context.md` —— KitContext 服务容器 + CoreKit 全局 provide/service。
```

(b) 类库说明补一段:
old_string:
```markdown
`KitStateMachine` / `KitState` 是 per-entity 的 `class_name` 类库,**不在门面上**——每个实体自己 `new()` 一台。见 `docs/state-machine.md`。
```
new_string:
```markdown
`KitStateMachine` / `KitState` 是 per-entity 的 `class_name` 类库,**不在门面上**——每个实体自己 `new()` 一台。见 `docs/state-machine.md`。

`KitContext` 同为 off-facade `class_name` 类库:游戏代码注册自己服务的**层级服务容器**(挂节点、随树回退)。全局服务用 `CoreKit.provide/service`;作用域服务用 `KitContext`。见 `docs/di/kit-context.md`。
```

- [ ] **Step 6: 改 `.claude/skills/developing-core-kit/SKILL.md` —— 「文件放哪」补类库去处**

old_string:
```markdown
- `systems/` —— 面向玩法的业务子系统(其余全部)。新子系统几乎都放这。
```
new_string:
```markdown
- `systems/` —— 面向玩法的业务子系统(其余全部)。新子系统几乎都放这。
- `state_machine/` / `di/` —— off-facade `class_name` 类库(`KitStateMachine`、`KitContext`),游戏代码直接 `new`/挂节点,不挂门面、不被 core/systems 依赖。新增"游戏侧直接用的可复用类"放这。
```

- [ ] **Step 7: 校验文档链接 + 复跑全量**

校验新增/改动文档里的相对链接可解析(`di/kit-context.md`、`architecture.md` 内 `[di/kit-context.md](di/kit-context.md)`、README 路由行的 `addons/godot-core-kit/docs/di/kit-context.md`)。
Run: `powershell -File test\run_all.ps1`
Expected: 仍 `=== SUMMARY FAILS=0 ===`(文档不影响测试)。

- [ ] **Step 8: Commit**

```bash
git add addons/godot-core-kit/docs README.md .claude/skills/using-core-kit/SKILL.md .claude/skills/developing-core-kit/SKILL.md
git commit -m "docs: document KitContext (DI container); sync architecture/README/skills"
```

---

## 自查(Self-Review)

**Spec 覆盖**(逐条对 `2026-07-09-corekit-di-container-design.md`):
- §5.1 CoreKit 全局根 4 方法 + RESERVED_KEYS + 预注册 → Task 1 ✓
- §5.2 KitContext provide/provide_child/service/has/service_or + 生命周期 → Task 2 ✓
- §5.3 静态 of/resolve → Task 2 ✓
- §6 解析语义(本层→父→全局、单一报错点、shadow、保留键) → Task 1(全局根报错/保留键)+ Task 2(层级/shadow)+ 测试 4/5/6 ✓
- §7 归属表(provide ref-only / provide_child 收养 / 拒绝已有父) → Task 2 测试 3 ✓
- §8 引擎坑(PREDELETE、class_name 缓存、await、autoload 非祖先) → Task 2 实现注释 + 文档注意事项 ✓
- §10 连带清单(版本三处、新增测试、门面回归、runner、文档、demo、技能) → Task 1/2/3/4 全覆盖 ✓
- §11 用法示例 → kit-context.md ✓
- §12 验收 FAILS=0(13 测试) → Task 3 Step 5 ✓

**占位符扫描**:无 TBD/TODO/"类似 Task N";每个代码步给出完整代码或精确 old/new。

**类型一致性**:`provide/provide_child/service/has/service_or`、`of/resolve`、`_parent_ctx`、`_services`、`RESERVED_KEYS`、`_global/_corekit/_find_parent_ctx` 在 Task 1↔2↔3↔4 及测试/文档中命名与签名一致;测试断言的 `service("audio") == CoreKit.audio`、`of()` 含自身语义与实现一致。
