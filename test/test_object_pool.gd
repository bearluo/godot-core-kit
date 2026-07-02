extends SceneTree
## ObjectPool headless 断言测试(直接实例化脚本,不依赖 ObjectPool 是否已注册为 autoload;
## 依赖项目已注册的 Log autoload 用于内部 Log.warn/Log.error 调用)。
## 运行:godot --headless -s res://test/test_object_pool.gd
##
## 已知例外:release() 里的 remove_child 是 call_deferred,在单次 _initialize() 里跑完
## 就 quit() 的 headless harness 中不会真正 flush(deferred 调用要等下一帧才执行)。本
## 文件只断言同步、纯粹的部分(计数/元数据/钩子调用时机/可见性);"摘除父节点"这个
## deferred 副作用留给后续集成步骤的 demo 场景冒烟验证。

## 注:object_pool.gd 用运行时 load()(而非顶层 const preload())取得。原因:headless
## -s 执行时,-s 主脚本的编译期 preload 依赖图会在 autoload 注册之前编译,而
## object_pool.gd 引用了全局 Log autoload,preload 链会因 "Identifier not found: Log" 失败。
## 改为在 _initialize() 内用运行时 load()(此时 autoload 已注册)规避引擎时序限制;
## 断言内容、顺序不变。ProbeScript 不引用 Log,保留 const preload。
const ProbeScript := preload("res://test/fixtures/object_pool_probe.gd")


func _make_trivial_scene() -> PackedScene:
	var scene := PackedScene.new()
	var root := Node.new()
	scene.pack(root)
	root.free()
	return scene


func _make_probe_scene() -> PackedScene:
	var scene := PackedScene.new()
	var root := Node.new()
	root.set_script(ProbeScript)
	scene.pack(root)
	root.free()
	return scene


func _make_control_scene() -> PackedScene:
	var scene := PackedScene.new()
	var root := Control.new()
	scene.pack(root)
	root.free()
	return scene


func _initialize() -> void:
	var failures := 0
	var pool = load("res://addons/godot-core-kit/object_pool.gd").new()  # 运行时 load,见顶部注释

	# 1. register() 后 has_pool(key) 为真;acquire(key) 返回非 null 的有效节点
	pool.register("a", _make_trivial_scene())
	if not pool.has_pool("a"):
		print("FAIL 1: has_pool('a') 应为 true")
		failures += 1
	var node_a: Node = pool.acquire("a")
	if node_a == null or not is_instance_valid(node_a):
		print("FAIL 1: acquire('a') 应返回有效节点")
		failures += 1
	pool.release(node_a)

	# 2. prewarm=N 时,register() 之后不调用 acquire():计数正确,且 probe 未触发 reset
	var probe_scene := _make_probe_scene()
	pool.register("probe", probe_scene, 3)
	if pool.available_count("probe") != 3:
		print("FAIL 2: available_count 应为 3,实际 %d" % pool.available_count("probe"))
		failures += 1
	if pool.in_use_count("probe") != 0:
		print("FAIL 2: in_use_count 应为 0,实际 %d" % pool.in_use_count("probe"))
		failures += 1
	if pool.total_count("probe") != 3:
		print("FAIL 2: total_count 应为 3,实际 %d" % pool.total_count("probe"))
		failures += 1
	for probe_node in pool._pools["probe"].available:
		if probe_node.reset_calls != 0:
			print("FAIL 2: prewarm 不应触发 _pool_reset()")
			failures += 1

	# 3. 池非空时 acquire() 复用空闲队列而非新建
	var total_before: int = pool.total_count("probe")
	var probe1: Node = pool.acquire("probe")
	if pool.total_count("probe") != total_before:
		print("FAIL 3: acquire 复用空闲不应改变 total_count")
		failures += 1
	if pool.available_count("probe") != 2:
		print("FAIL 3: available_count 应减为 2,实际 %d" % pool.available_count("probe"))
		failures += 1
	if pool.in_use_count("probe") != 1:
		print("FAIL 3: in_use_count 应增为 1,实际 %d" % pool.in_use_count("probe"))
		failures += 1

	# 4. 池为空且未设上限时 acquire() 新建
	pool.register("b", _make_trivial_scene())  # max_count=0,不限
	var b1: Node = pool.acquire("b")
	var b2: Node = pool.acquire("b")
	if pool.total_count("b") != 2:
		print("FAIL 4: 空闲耗尽应新建,total_count 应为 2,实际 %d" % pool.total_count("b"))
		failures += 1
	pool.release(b1)
	pool.release(b2)

	# 5. release() 后再次 acquire() 返回同一个节点实例
	pool.register("c", _make_trivial_scene())
	var c1: Node = pool.acquire("c")
	var c1_id := c1.get_instance_id()
	pool.release(c1)
	var c2: Node = pool.acquire("c")
	if c2.get_instance_id() != c1_id:
		print("FAIL 5: release 后 acquire 应复用同一实例")
		failures += 1
	pool.release(c2)

	# 6. release() 对定义了 _pool_reset() 的节点恰好调用一次;对普通节点 release 不报错
	var probe2: Node = pool.acquire("probe")
	pool.release(probe2)
	if probe2.reset_calls != 1:
		print("FAIL 6: release 应恰好调用一次 _pool_reset(),实际 %d" % probe2.reset_calls)
		failures += 1
	pool.register("plain", _make_trivial_scene())
	var plain1: Node = pool.acquire("plain")
	pool.release(plain1)  # 无 _pool_reset() 方法,不应报错/崩溃(能执行到下一行即为通过)

	# 7. release() 对 CanvasItem 子类节点同步设 visible=false;acquire() 复用时设回 true
	pool.register("vis", _make_control_scene())
	var vis_node: Control = pool.acquire("vis")
	vis_node.visible = true
	pool.release(vis_node)
	if vis_node.visible:
		print("FAIL 7: release 应将 CanvasItem.visible 设为 false")
		failures += 1
	var reacquired_vis: Control = pool.acquire("vis")
	if not reacquired_vis.visible:
		print("FAIL 7: acquire 应将 CanvasItem.visible 设回 true")
		failures += 1
	pool.release(reacquired_vis)

	# 8. 双重释放安全
	pool.register("d", _make_trivial_scene())
	var d1: Node = pool.acquire("d")
	pool.release(d1)
	var avail_after_first_release: int = pool.available_count("d")
	pool.release(d1)  # 第二次应为 no-op
	if pool.available_count("d") != avail_after_first_release:
		print("FAIL 8: 双重 release 不应重复入队")
		failures += 1

	# 9. 非本池节点安全
	var stray := Node.new()
	pool.release(stray)  # no-op,不应崩溃、不应影响任何池
	stray.free()

	# 10. 上限安全:max_count=1
	pool.register("capped", _make_trivial_scene(), 0, 1)
	var cap1: Node = pool.acquire("capped")
	if cap1 == null:
		print("FAIL 10: 首次 acquire 应成功")
		failures += 1
	var cap2: Node = pool.acquire("capped")
	if cap2 != null:
		print("FAIL 10: 达到 max_count 后应返回 null")
		failures += 1
	if pool.total_count("capped") > 1:
		print("FAIL 10: total_count 不应超过 max_count,实际 %d" % pool.total_count("capped"))
		failures += 1
	pool.release(cap1)

	# 11. 僵尸空闲实例安全
	pool.register("zombie", _make_trivial_scene(), 1)  # prewarm=1,放进空闲队列
	var zombie_node: Node = pool._pools["zombie"].available[0]
	zombie_node.free()  # 绕过 release() 直接 free()
	var zombie_acquired: Node = pool.acquire("zombie")
	if zombie_acquired == null or not is_instance_valid(zombie_acquired):
		print("FAIL 11: 丢弃僵尸引用后应返回新的有效节点")
		failures += 1
	pool.release(zombie_acquired)

	# 12. 重复注册幂等性(同一 PackedScene 引用)
	var shared_scene := _make_trivial_scene()
	pool.register("dup", shared_scene)
	var dup1: Node = pool.acquire("dup")
	pool.register("dup", shared_scene)  # 第二次注册不应重置已有状态
	if pool.in_use_count("dup") != 1:
		print("FAIL 12: 重复 register 不应重置 in_use_count,实际 %d" % pool.in_use_count("dup"))
		failures += 1
	pool.release(dup1)

	# 13. clear(key)
	pool.register("clr", _make_trivial_scene(), 2)  # prewarm=2,从未 acquire
	pool.clear("clr")
	if pool.available_count("clr") != 0:
		print("FAIL 13: clear 后 available_count 应为 0")
		failures += 1
	if pool.total_count("clr") != 0:
		print("FAIL 13: clear 后 total_count 应为 0")
		failures += 1
	if not pool.has_pool("clr"):
		print("FAIL 13: clear 不应移除注册信息")
		failures += 1
	var clr_reacquired: Node = pool.acquire("clr")
	if clr_reacquired == null:
		print("FAIL 13: clear 后仍应能 acquire(重新 instantiate)")
		failures += 1
	pool.release(clr_reacquired)

	# 14. manage_visibility=false 时 acquire()/release() 均不管可见性
	pool.register("novis", _make_control_scene(), 0, 0, false)
	var novis_node: Control = pool.acquire("novis")
	novis_node.visible = true  # 调用方自行接管可见性(如自定义淡入淡出)
	pool.release(novis_node)
	if not novis_node.visible:
		print("FAIL 14: manage_visibility=false 时 release 不应把 visible 改为 false")
		failures += 1
	novis_node.visible = false  # 手动摆好前置状态,用于验证 acquire 不强制 visible=true
	var novis_reacquired: Node = pool.acquire("novis")
	if novis_reacquired.visible:
		print("FAIL 14: manage_visibility=false 时 acquire 不应把 visible 强制设为 true")
		failures += 1
	pool.release(novis_reacquired)

	# 15. release() 对已被外部 free() 的节点安全:静默 no-op,不崩溃
	#     (回归:release 形参曾标注 typed Node,传入已 free 实例会在调用边界抛
	#      "invalid freed instance",内部 is_instance_valid 守卫根本到不了)
	pool.register("freed", _make_trivial_scene())
	var freed_node: Node = pool.acquire("freed")
	freed_node.free()  # 绕过 release() 直接 free()
	pool.release(freed_node)  # 传入已失效引用 → 应静默 no-op,不抛错(能执行到下一行即通过)

	pool.free()

	if failures == 0:
		print("test_object_pool: ALL PASS")
		quit(0)
	else:
		print("test_object_pool: %d FAILURE(S)" % failures)
		quit(1)
