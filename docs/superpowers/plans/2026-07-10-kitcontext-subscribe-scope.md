# KitContext 订阅式解析 + scope 语义 实现计划(v0.6.0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development(推荐)或 superpowers:executing-plans 逐任务实现。步骤用 `- [ ]` 勾选跟踪。

**Goal:** 给 `KitContext` 叠加「订阅式解析(含向下传播)」与「工厂式 scope(SINGLETON/TRANSIENT)」两条能力,纯向后兼容。

**Architecture:** 在既有节点绑定层级服务定位器上叠加:(1)`_factories`/`_singletons` + `provide_factory` + 解析改「先 `_local` 后 `_factories`」;(2)`_subscribers`/`_child_ctxs` + `subscribe`/`unsubscribe` + owner provide 时 `_notify`→`_deliver` 沿子容器树向下投递(shadow 分支剪枝)。

**Tech Stack:** Godot 4.x,GDScript,headless SceneTree 断言测试。

**Spec:** `docs/superpowers/specs/2026-07-10-kitcontext-subscribe-scope-design.md`

## Global Constraints

- **向后兼容(硬约束)**:`provide` / `provide_child` / `service` / `has` / `service_or` / 静态 `of` / `resolve` 的**签名与语义一律不变**;未使用新能力时行为逐字不变。既有 `test/test_kit_context.gd` 段 1–7 断言必须继续通过。
- **懒创建不变式**:无订阅者时 SINGLETON 工厂**不得**在 `provide_factory` 时被调用;仅首次 `service()` 触发。
- **释放语义不变**:`provide_child` 收养的 Node 随容器 `PREDELETE` 释放;ref-only `provide` 的对象不被释放。
- **枚举定值**:`enum Scope { SINGLETON, TRANSIENT }`(SINGLETON=0,TRANSIENT=1),顺序不可改。
- **零新依赖**;注释风格、命名与文件现有中文注释一致。
- **类缓存**:改动 `KitContext` 后,headless 跑测试前若报 `KitContext` 解析错误,先执行一次 `godot --headless --path . --import`。
- **测试运行器**:单测 `godot --headless --path . -s res://test/test_kit_context.gd`(exit 0 = 通过);全量 `pwsh test/run_all.ps1`。
- `godot` 在 PowerShell 可用(Git Bash 下 exit 127);Bash 里用 `--import`/`-s` 需走完整 exe 路径或改用 PowerShell 工具。

**当前文件**:`addons/godot-core-kit/di/kit_context.gd`(现有内容见 spec §2 与仓库)。以下任务给出**目标函数完整体**,用 Edit 替换对应函数;新增字段/方法按指示插入。

---

### Task 1: 工厂式 scope(SINGLETON / TRANSIENT)

**Files:**
- Modify: `addons/godot-core-kit/di/kit_context.gd`
- Test: `test/test_kit_context.gd`

**Interfaces:**
- Produces: `enum Scope { SINGLETON, TRANSIENT }`;`func provide_factory(key: String, factory: Callable, scope: int = Scope.SINGLETON) -> void`;内部 `_resolve_factory(key)`、字段 `_factories`/`_singletons`。
- Consumes: 既有 `_local`/`_parent_ctx`/`service`/`has`。

- [ ] **Step 1: 写失败测试** —— 在 `test/test_kit_context.gd` 中,紧邻结尾汇总块

```gdscript
	if failures == 0:
```

之前插入两段(段 8、段 9):

```gdscript
	# --- 8. provide_factory: SINGLETON 懒创建+缓存,TRANSIENT 每次新建 ---
	var fctx = KC.new()
	fctx.name = "FactoryCtx"
	root.add_child(fctx)
	await process_frame
	var s_calls := [0]
	var s_factory := func() -> RefCounted:
		s_calls[0] += 1
		return RefCounted.new()
	fctx.provide_factory("singleton", s_factory)  # 默认 SINGLETON
	if s_calls[0] != 0:
		print("FAIL 8: SINGLETON 工厂不应在 provide 时被调用(应懒)")
		failures += 1
	var s1 = fctx.service("singleton")
	var s2 = fctx.service("singleton")
	if s1 != s2:
		print("FAIL 8: SINGLETON 两次 service 应同一实例")
		failures += 1
	if s_calls[0] != 1:
		print("FAIL 8: SINGLETON 工厂应只被调用一次")
		failures += 1
	var t_calls := [0]
	var t_factory := func() -> RefCounted:
		t_calls[0] += 1
		return RefCounted.new()
	fctx.provide_factory("transient", t_factory, KC.Scope.TRANSIENT)
	var u1 = fctx.service("transient")
	var u2 = fctx.service("transient")
	if u1 == u2:
		print("FAIL 8: TRANSIENT 两次 service 应不同实例")
		failures += 1
	if t_calls[0] != 2:
		print("FAIL 8: TRANSIENT 工厂应每次 service 都调用")
		failures += 1

	# --- 9. 工厂沿链解析 + 子层 shadow + 三注册互斥 ---
	var fp = KC.new()
	fp.name = "FP"
	root.add_child(fp)
	await process_frame
	var fc = KC.new()
	fc.name = "FC"
	fp.add_child(fc)
	await process_frame
	var pfac := func() -> String:
		return "from_parent_factory"
	fp.provide_factory("f_shared", pfac)
	if fc.service("f_shared") != "from_parent_factory":
		print("FAIL 9: 子层未向上解析到父层工厂")
		failures += 1
	fc.provide("f_shared", "child_override")   # 子层 value 覆盖 → shadow 父层工厂
	if fc.service("f_shared") != "child_override":
		print("FAIL 9: 子层 value 未 shadow 父层工厂")
		failures += 1
	var mx_calls := [0]
	var mfac := func() -> int:
		mx_calls[0] += 1
		return 999
	fp.provide_factory("mx", mfac)
	fp.provide("mx", 111)          # value 覆盖同层 factory
	if fp.service("mx") != 111:
		print("FAIL 9: provide value 未覆盖同层 factory")
		failures += 1
	if mx_calls[0] != 0:
		print("FAIL 9: 被覆盖的 factory 不应再被调用")
		failures += 1
```

- [ ] **Step 2: 跑测试确认失败**

Run(PowerShell):`godot --headless --path . --import; godot --headless --path . -s res://test/test_kit_context.gd`
Expected: FAIL —— `provide_factory` 未定义(解析错误或运行期报错),或段 8/9 断言失败。

- [ ] **Step 3: 实现** —— 在 `addons/godot-core-kit/di/kit_context.gd`:

(a) 在字段区(`var _parent_ctx ...` 之后)插入:

```gdscript

## 工厂注册的生命周期:SINGLETON 首次 service 创建并缓存;TRANSIENT 每次 service 新建。
enum Scope { SINGLETON, TRANSIENT }

var _factories: Dictionary = {}    # key:String -> {"factory": Callable, "scope": int}
var _singletons: Dictionary = {}   # key:String -> 已实例化的 SINGLETON 缓存
```

(b) 将 `provide` 替换为(新增清工厂表):

```gdscript
## 注册服务到本层。只存引用,绝不动树。重复键覆盖并告警。可 shadow 祖先/全局同名键。
func provide(key: String, svc: Variant) -> void:
	if _local.has(key) or _factories.has(key):
		push_warning("KitContext.provide('%s'): 覆盖同层已注册服务" % key)
	_local[key] = svc
	_factories.erase(key)
	_singletons.erase(key)
```

(c) 将 `provide_child` 替换为(新增清工厂表):

```gdscript
## 收养一个无父节点为子节点并注册;随本容器释放。node 已有父 → push_error 跳过。
func provide_child(key: String, node: Node) -> void:
	if node.get_parent() != null:
		push_error("KitContext.provide_child('%s'): 需要无父节点,请先自行 reparent" % key)
		return
	add_child(node)
	if _local.has(key) or _factories.has(key):
		push_warning("KitContext.provide_child('%s'): 覆盖同层已注册服务" % key)
	_local[key] = node
	_factories.erase(key)
	_singletons.erase(key)
```

(d) 在 `provide_child` 之后新增:

```gdscript
## 以工厂注册服务。SINGLETON:首次 service() 调一次工厂并缓存;TRANSIENT:每次
## service() 都调工厂返新实例。面向普通值 / RefCounted;Node 型服务请用 provide_child
## (容器负责其生命周期)。同层覆盖 value/其它工厂并告警。
func provide_factory(key: String, factory: Callable, scope: int = Scope.SINGLETON) -> void:
	if _local.has(key) or _factories.has(key):
		push_warning("KitContext.provide_factory('%s'): 覆盖同层已注册服务" % key)
	_factories[key] = {"factory": factory, "scope": scope}
	_local.erase(key)
	_singletons.erase(key)
```

(e) 将 `service` 替换为(插入工厂分支):

```gdscript
## 解析:本层 value → 本层 factory → 最近祖先容器 → CoreKit 全局根。
func service(key: String) -> Variant:
	if _local.has(key):
		return _local[key]
	if _factories.has(key):
		return _resolve_factory(key)
	if _parent_ctx != null:
		return _parent_ctx.service(key)
	return _global(key)
```

(f) 将 `has` 替换为(本层含工厂):

```gdscript
## 沿同一条链的存在性检查,不报错。
func has(key: String) -> bool:
	if _local.has(key) or _factories.has(key):
		return true
	if _parent_ctx != null:
		return _parent_ctx.has(key)
	var ck := _corekit()
	return ck != null and bool(ck.call("has", key))
```

(g) 在 `has`/`service_or` 附近新增私有:

```gdscript
## 按 scope 解析工厂:TRANSIENT 每次新建;SINGLETON 首次创建并缓存。
func _resolve_factory(key: String) -> Variant:
	var e: Dictionary = _factories[key]
	if int(e["scope"]) == Scope.TRANSIENT:
		return (e["factory"] as Callable).call()
	if not _singletons.has(key):
		_singletons[key] = (e["factory"] as Callable).call()
	return _singletons[key]
```

(h) 将 `_notification` 替换为(PREDELETE 同时清工厂表):

```gdscript
func _notification(what: int) -> void:
	# disposal 走 PREDELETE:_exit_tree 在 reparent 时也触发,不能用来清表。
	if what == NOTIFICATION_PREDELETE:
		_local.clear()
		_factories.clear()
		_singletons.clear()
```

- [ ] **Step 4: 跑测试确认通过**

Run:`godot --headless --path . -s res://test/test_kit_context.gd`
Expected: `test_kit_context: ALL PASS`,exit 0。

- [ ] **Step 5: 提交**

```bash
git add addons/godot-core-kit/di/kit_context.gd test/test_kit_context.gd
git commit -m "feat(kitcontext): factory-based scope (SINGLETON/TRANSIENT)"
```

---

### Task 2: 订阅式解析 + 向下传播

**Files:**
- Modify: `addons/godot-core-kit/di/kit_context.gd`
- Test: `test/test_kit_context.gd`

**Interfaces:**
- Consumes(Task 1):`_resolve_factory`、`_factories`、`Scope`。
- Produces:`func subscribe(key: String, cb: Callable) -> void`;`func unsubscribe(key: String, cb: Callable) -> void`;字段 `_subscribers`/`_child_ctxs`;内部 `_notify`/`_deliver`/`_owns`/`_owner_value`。

- [ ] **Step 1: 写失败测试** —— 在结尾汇总块 `if failures == 0:` 之前插入(段 10–13):

```gdscript
	# --- 10. subscribe: 已可解析→立即回调;本层延后 provide→再回调 ---
	var sctx = KC.new()
	sctx.name = "SubCtx"
	root.add_child(sctx)
	await process_frame
	sctx.provide("imm", 1)
	var got_imm := [null]
	sctx.subscribe("imm", func(v): got_imm[0] = v)
	if got_imm[0] != 1:
		print("FAIL 10: subscribe 已可解析应立即回调")
		failures += 1
	var got_def := [null]
	sctx.subscribe("def", func(v): got_def[0] = v)
	if got_def[0] != null:
		print("FAIL 10: 未 provide 前不应回调")
		failures += 1
	sctx.provide("def", 2)
	if got_def[0] != 2:
		print("FAIL 10: 本层 provide 后应回调订阅者")
		failures += 1

	# --- 11. subscribe: 祖先延后 provide(核心时序)+ shadow 剪枝 ---
	var gp = KC.new()
	gp.name = "GP"
	root.add_child(gp)
	await process_frame
	var p = KC.new()
	p.name = "P"
	gp.add_child(p)
	await process_frame
	var c = KC.new()
	c.name = "C"
	p.add_child(c)
	await process_frame
	var fires := []
	c.subscribe("k", func(v): fires.append(v))   # 此刻不可解析,不回调
	if fires.size() != 0:
		print("FAIL 11: 不可解析时不应回调")
		failures += 1
	p.provide("k", "P")        # 更近祖先 provide → 经向下传播回调 c
	if fires != ["P"]:
		print("FAIL 11: 祖先 provide 未经向下传播回调后代订阅者")
		failures += 1
	gp.provide("k", "G")       # 更远祖先 provide → 被 P 层 shadow 剪枝,不应再回调 c
	if fires != ["P"]:
		print("FAIL 11: 更远祖先 provide 未被 shadow 剪枝(重复回调)")
		failures += 1

	# --- 12. unsubscribe 后不再回调 ---
	var uctx = KC.new()
	uctx.name = "UnsubCtx"
	root.add_child(uctx)
	await process_frame
	var ucount := [0]
	var ucb := func(_v): ucount[0] += 1
	uctx.subscribe("u", ucb)
	uctx.provide("u", 1)       # 回调一次 → 1
	uctx.unsubscribe("u", ucb)
	uctx.provide("u", 2)       # 已退订 → 不再增
	if ucount[0] != 1:
		print("FAIL 12: unsubscribe 后不应再回调")
		failures += 1

	# --- 13. 子容器 free 后,父层 provide 不触达已释放子容器 ---
	var pc = KC.new()
	pc.name = "PC"
	root.add_child(pc)
	await process_frame
	var cc = KC.new()
	cc.name = "CC"
	pc.add_child(cc)
	await process_frame
	var pc_got := [null]
	pc.subscribe("w", func(v): pc_got[0] = v)
	cc.free()
	await process_frame
	pc.provide("w", 9)         # 若 _child_ctxs 仍含已释放 cc,向下传播会对空实例报错
	if pc_got[0] != 9:
		print("FAIL 13: 子容器释放后父层订阅投递异常")
		failures += 1
```

- [ ] **Step 2: 跑测试确认失败**

Run:`godot --headless --path . -s res://test/test_kit_context.gd`
Expected: FAIL —— `subscribe`/`unsubscribe` 未定义。

- [ ] **Step 3: 实现** —— 在 `addons/godot-core-kit/di/kit_context.gd`:

(a) 在 Task 1 的工厂字段之后新增:

```gdscript

var _subscribers: Dictionary = {}  # key:String -> Array[Callable]
var _child_ctxs: Array = []        # 直接子容器(KitContext);不标类型,避免自引用编译风险
```

(b) 在 `provide` / `provide_child` / `provide_factory` 三个函数体**末尾各追加一行** `_notify(key)`(在已有的 `_singletons.erase(key)` 之后):

```gdscript
	_notify(key)
```

(c) 在 `service_or` 之后新增订阅与传播:

```gdscript
## 订阅某 key 的解析结果。订阅时若已可解析 → 立即回调一次;之后该 key 在本容器或
## 任一祖先容器被 provide/provide_child/provide_factory(且本容器沿链解析值因此变化)时再次回调。
## 取消订阅需用同一 Callable(同对象同方法)。
func subscribe(key: String, cb: Callable) -> void:
	if has(key):
		cb.call(service(key))
	if not _subscribers.has(key):
		_subscribers[key] = []
	_subscribers[key].append(cb)


## 取消订阅。key 或 cb 未注册则空操作。
func unsubscribe(key: String, cb: Callable) -> void:
	if not _subscribers.has(key):
		return
	_subscribers[key].erase(cb)
	if _subscribers[key].is_empty():
		_subscribers.erase(key)


## 本容器成为某 key 的 owner 后触发:向 self 及未 shadow 的后代容器投递。
func _notify(key: String) -> void:
	_deliver(key, self)


## 在 self 及未 shadow 该 key 的后代容器上,用 owner 本层解析值回调订阅者。
func _deliver(key: String, owner: KitContext) -> void:
	for cb in _subscribers.get(key, []):
		(cb as Callable).call(owner._owner_value(key))
	for child in _child_ctxs:
		if not is_instance_valid(child):
			continue
		if child._owns(key):   # 后代自己 shadow → 整个子树跳过
			continue
		child._deliver(key, owner)


## 本层是否拥有该 key(value 或 factory)。
func _owns(key: String) -> bool:
	return _local.has(key) or _factories.has(key)


## owner 本层的解析值(懒:仅在有订阅者需要投递时被调用,不提前实例化 SINGLETON)。
func _owner_value(key: String) -> Variant:
	if _local.has(key):
		return _local[key]
	return _resolve_factory(key)
```

(d) 将 `_enter_tree` 替换为(登记进父容器 `_child_ctxs`):

```gdscript
func _enter_tree() -> void:
	_parent_ctx = _find_parent_ctx()
	if _parent_ctx != null and not _parent_ctx._child_ctxs.has(self):
		_parent_ctx._child_ctxs.append(self)
```

(e) 将 `_notification` 替换为(从父容器注销 + 清订阅表):

```gdscript
func _notification(what: int) -> void:
	# disposal 走 PREDELETE:_exit_tree 在 reparent 时也触发,不能用来清表。
	if what == NOTIFICATION_PREDELETE:
		if _parent_ctx != null and is_instance_valid(_parent_ctx):
			_parent_ctx._child_ctxs.erase(self)
		_local.clear()
		_factories.clear()
		_singletons.clear()
		_subscribers.clear()
```

- [ ] **Step 4: 跑测试确认通过**

Run:`godot --headless --path . -s res://test/test_kit_context.gd`
Expected: `test_kit_context: ALL PASS`,exit 0。

- [ ] **Step 5: 提交**

```bash
git add addons/godot-core-kit/di/kit_context.gd test/test_kit_context.gd
git commit -m "feat(kitcontext): subscription-based resolution with downward propagation"
```

---

### Task 3: 版本 / 文档 / demo 收尾

**Files:**
- Modify: `addons/godot-core-kit/core_kit.gd`(VERSION)
- Modify: `addons/godot-core-kit/plugin.cfg`(version + description)
- Modify: `addons/godot-core-kit/docs/di/kit-context.md`(新增两节)
- Modify: `demo/demo.gd`(冒烟)

**Interfaces:** 无新增对外接口;仅版本、文档、demo。

- [ ] **Step 1: 版本号** —— `core_kit.gd` 第 13 行:

```gdscript
const VERSION := "0.6.0"
```

`plugin.cfg`:`version="0.6.0"`;description 末尾追加 `;0.6.0 KitContext 增订阅式解析 subscribe + 工厂式 scope provide_factory`。

- [ ] **Step 2: 文档** —— 在 `addons/godot-core-kit/docs/di/kit-context.md` 的「公开 API」之后追加两节:

```markdown
## 订阅式解析(subscribe)

`ctx.subscribe(key, callable)` 订阅某 key 的解析结果:订阅时若已可解析立即回调一次,
之后该 key 在**本容器或任一祖先容器**被 provide 时(且本容器沿链解析值因此变化)再次回调。
用于化解 Godot「后代 `_ready` 早于祖先」的时序坑——后代先订阅,祖先稍后 provide 时被回调。
`unsubscribe(key, callable)` 取消(需用同一 Callable)。

```gdscript
# 后代消费者(在其 _ready 里)
KitContext.of(self).subscribe("player", func(p): _player = p)
# 祖先容器(在其更晚的 _ready 里)provide → 上面回调被触发
ctx.provide("player", player_node)
```

传播只在 KitContext 链内;shadow 分支自动剪枝(更近祖先的值优先,更远祖先不覆盖)。
不追溯 reparent(容器换链后不重投既有订阅)。

## 工厂式 scope(provide_factory)

`ctx.provide_factory(key, factory: Callable, scope)` 以工厂注册,`scope ∈ {KitContext.Scope.SINGLETON, KitContext.Scope.TRANSIENT}`:

- `SINGLETON`(默认):首次 `service(key)` 调一次工厂并缓存,后续复用同一实例;无人取用则不创建(懒)。
- `TRANSIENT`:每次 `service(key)` 都调工厂返新实例。

```gdscript
ctx.provide_factory("rng", func(): return RandomNumberGenerator.new(), KitContext.Scope.TRANSIENT)
```

**边界**:工厂面向普通值 / `RefCounted`;**Node 型服务用 `provide_child`**(容器负责其生命周期)。
TRANSIENT 工厂若返回 Node,其生命周期归调用方。同层对同 key 的 `provide` / `provide_child` /
`provide_factory` 互相覆盖(并清另两种表示)。
```

- [ ] **Step 3: demo 冒烟** —— 在 `demo/demo.gd` 的 `ctx.free()` 行之前插入:

```gdscript
	# 订阅式解析 + 工厂 scope 冒烟
	ctx.subscribe("late_svc", func(v): CoreKit.log.info("KitContext: 订阅回调 late_svc=%s" % v))
	ctx.provide("late_svc", "arrived")   # 触发上面订阅回调
	ctx.provide_factory("rng", func() -> RefCounted: return RefCounted.new(), KitContext.Scope.TRANSIENT)
	CoreKit.log.info("KitContext: transient 两次不同=%s" % (ctx.service("rng") != ctx.service("rng")))
```

- [ ] **Step 4: 全量验证**

Run:`godot --headless --path . --import; pwsh test/run_all.ps1`
Expected: 全部 13 个测试通过;demo 冒烟输出含 `KitContext: 订阅回调 late_svc=arrived` 与 `transient 两次不同=true`,stderr 无 ERROR。

- [ ] **Step 5: 提交**

```bash
git add addons/godot-core-kit/core_kit.gd addons/godot-core-kit/plugin.cfg addons/godot-core-kit/docs/di/kit-context.md demo/demo.gd
git commit -m "docs(kitcontext): v0.6.0 — bump version, doc subscribe/scope, demo smoke"
```

---

## 完成后

三个任务合并后,`KitContext` 具备订阅式解析 + 工厂式 scope。走 subagent-driven-development 的最终 whole-branch review,再按 [[workflow-ff-merge-user-pushes]] ff-merge 到 main(push 留给用户)。下一子项目:SaveManager 可插拔序列化 + 原子写。
