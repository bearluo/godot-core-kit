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
	var parent = KC.new()
	parent.name = "Parent"
	root.add_child(parent)
	await process_frame
	var child = KC.new()
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

	if failures == 0:
		print("test_kit_context: ALL PASS")
		quit(0)
	else:
		print("test_kit_context: %d FAILURE(S)" % failures)
		quit(1)
