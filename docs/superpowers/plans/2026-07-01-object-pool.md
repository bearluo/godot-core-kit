# ObjectPool 子系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 godot-core-kit 实现 `ObjectPool` 全局对象池单例（`register`/`has_pool`/`acquire`/
`release`/`clear`/`available_count`/`in_use_count`/`total_count`），按字符串 key 管理若干具名
节点池，供后续游戏项目复用高频 spawn/despawn 的 `Node` 实例。

**Scope boundary（范围边界，务必遵守）：** 本计划**只**覆盖三个文件——
`addons/godot-core-kit/object_pool.gd`、`test/test_object_pool.gd`、
`test/fixtures/object_pool_probe.gd`。**不**把 `ObjectPool` 接线为 autoload（不改
`project.godot`/`plugin.gd`）、**不**升版本号（不改 `plugin.cfg`/`core_kit.gd`）、**不**改
`README.md`、**不**加 demo 场景冒烟段。这些属于后续独立的集成步骤（模式同 Logger 子系统的
Task 2，但本计划不包含它）。

**Architecture:** 单文件（`object_pool.gd`），`extends Node`，无 `class_name`（与 `Log` 先例
一致，仅暴露全局 autoload 名，无独立可实例化类）。按 key 分桶的记账封装进私有内部类
`_PoolEntry`（`extends RefCounted`：`scene`/`max_count`/`manage_visibility`/`total_count`/
`available`/`in_use` 六个字段），`_pools: Dictionary`（`key -> _PoolEntry`）是唯一状态。
`register`/`has_pool`/`acquire`/`release`/`clear`/三个计数方法全部是不依赖场景树的纯 `Object`
层逻辑，只操作**传入的 `node` 参数**的父子关系，从不对 `self` 调用 `add_child`——因此可以像
`test_log.gd` 一样直接 `preload(...).new()` 拿裸实例测试，无需真正把 `ObjectPool` 注册为
autoload。`release()` 里唯一有真实引擎副作用且不可 headless 单帧断言的部分（`remove_child`
的 `call_deferred`）留给后续集成步骤的 demo 冒烟验证。

**Tech Stack:** Godot 4.7，纯 GDScript，Compatibility 渲染器。无第三方测试框架。可依赖已实现
的 `Log` autoload（0.2.0，已在 `project.godot` 注册，`ObjectPool` 脚本内可直接引用全局单例
`Log`，无需在测试里额外桩接）。

## Global Constraints

以下为本计划全局约束，每个任务隐含遵守：

- 引擎 Godot 4.7，`config_version=5`；纯 GDScript，**不含 C#**；不用线程、无文件 IO（Web 导出
  兼容）。
- Autoload 名 `ObjectPool`（**本计划不实际注册**，只是脚本内部注释按此约定编写，供后续集成
  步骤直接 `add_autoload_singleton("ObjectPool", ...)`），文件路径
  `addons/godot-core-kit/object_pool.gd`。
- `register`/`acquire`/`release`/`clear`/`available_count`/`in_use_count`/`total_count` 这套
  记账 API 必须能在裸 `preload("res://addons/godot-core-kit/object_pool.gd").new()` 实例上
  直接调用——这些方法只会 mutate 传入的 `node` 参数的父节点关系，绝不对 `self` 调用
  `add_child`。
- headless 测试 `test/test_object_pool.gd`：`extends SceneTree`，断言写在 `_initialize()`
  里，全部通过打印 `test_object_pool: ALL PASS` 并 `quit(0)`；任一失败逐条打印详情、
  `quit(1)`。不引入第三方测试框架。
- **已知限制**：`release()` 的 `remove_child` 是 `call_deferred`，在单次 `_initialize()` 内跑
  完就 `quit()` 的 headless harness 中不会真正 flush（deferred 调用要等下一帧才执行）。本计划
  的 headless 断言只覆盖同步、纯粹的部分（计数/元数据/钩子调用时机/可见性），把“摘除父节点”这
  个 deferred 副作用真的执行了留给后续集成步骤的 demo 场景冒烟。
- 测试用**运行时现造的 trivial `PackedScene`**（`PackedScene.new()` + `pack(Node.new())`），
  不引入额外 `.tscn` 资源文件；验证 `_pool_reset()` 调用时机需要一个独立 fixture 脚本
  `test/fixtures/object_pool_probe.gd`。
- 本机 Godot（验证用），下文命令记作 `$godot`：
  `D:\Program Files\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe`
  PowerShell 里先设 `$godot = "D:\Program Files\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe"`，再 `& $godot ...`。

## File Structure

| 文件 | 责任 | 动作 |
|---|---|---|
| `addons/godot-core-kit/object_pool.gd` | `ObjectPool` 单例：`_PoolEntry` 记账、register/acquire/release/clear/计数 | Create |
| `test/test_object_pool.gd` | headless 断言（14 条，见下） | Create |
| `test/fixtures/object_pool_probe.gd` | 探测 `_pool_reset()` 调用次数与时机的 fixture 脚本 | Create |

不在本计划范围内（后续独立集成步骤）：`project.godot`、`addons/godot-core-kit/plugin.gd`、
`addons/godot-core-kit/plugin.cfg`、`addons/godot-core-kit/core_kit.gd`、`README.md`、
`demo/demo.gd` / `demo/demo.tscn`。

---

## Task 1: ObjectPool 核心 —— 记账 / 借出 / 归还 / 回收

**Files:**
- Create: `addons/godot-core-kit/object_pool.gd`
- Test: `test/test_object_pool.gd`
- Test fixture: `test/fixtures/object_pool_probe.gd`

**Interfaces:**
- Consumes: `Log`（全局 autoload，已在 `project.godot` 注册；`ObjectPool` 内部对
  `Log.error(message)`/`Log.warn(message)` 的调用）。
- Produces:
  - `ObjectPool` 脚本（`extends Node`），供后续集成步骤注册为 autoload，也可直接
    `preload(...).new()` 测试。
  - `const META_POOL_KEY := "__object_pool_key"`
  - 内部类 `_PoolEntry`（`extends RefCounted`）
  - `func register(key: String, scene: PackedScene, prewarm: int = 0, max_count: int = 0, manage_visibility: bool = true) -> void`
  - `func has_pool(key: String) -> bool`
  - `func acquire(key: String) -> Node`
  - `func release(node: Node) -> void`
  - `func clear(key: String) -> void`
  - `func available_count(key: String) -> int` / `in_use_count` / `total_count`

- [ ] **Step 1: 写失败测试** `test/fixtures/object_pool_probe.gd` + `test/test_object_pool.gd`

先写 fixture（`_pool_reset()` 探针）：

```gdscript
extends Node
## ObjectPool 测试专用 fixture:探测 _pool_reset() 的调用次数与时机。
## 挂到一个 trivial 场景的根节点上,由 test_object_pool.gd 用于验证:
## prewarm 阶段不触发 _pool_reset();release() 归还时恰好触发一次。

var reset_calls := 0


func _pool_reset() -> void:
	reset_calls += 1
```

再写测试：

```gdscript
extends SceneTree
## ObjectPool headless 断言测试(直接实例化脚本,不依赖 ObjectPool 是否已注册为 autoload;
## 依赖项目已注册的 Log autoload 用于内部 Log.warn/Log.error 调用)。
## 运行:godot --headless -s res://test/test_object_pool.gd
##
## 已知例外:release() 里的 remove_child 是 call_deferred,在单次 _initialize() 里跑完
## 就 quit() 的 headless harness 中不会真正 flush(deferred 调用要等下一帧才执行)。本
## 文件只断言同步、纯粹的部分(计数/元数据/钩子调用时机/可见性);"摘除父节点"这个
## deferred 副作用留给后续集成步骤的 demo 场景冒烟验证。

const ObjectPoolScript := preload("res://addons/godot-core-kit/object_pool.gd")
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
	var pool = ObjectPoolScript.new()  # 变量名不标注具体类型,duck-typing 调用

	# 1. register() 后 has_pool(key) 为真;acquire(key) 返回非 null 的有效节点
	pool.register("a", _make_trivial_scene())
	if not pool.has_pool("a"):
		print("FAIL 1: has_pool('a') 应为 true")
		failures += 1
	var node_a := pool.acquire("a")
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
	var total_before := pool.total_count("probe")
	var probe1 := pool.acquire("probe")
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
	var b1 := pool.acquire("b")
	var b2 := pool.acquire("b")
	if pool.total_count("b") != 2:
		print("FAIL 4: 空闲耗尽应新建,total_count 应为 2,实际 %d" % pool.total_count("b"))
		failures += 1
	pool.release(b1)
	pool.release(b2)

	# 5. release() 后再次 acquire() 返回同一个节点实例
	pool.register("c", _make_trivial_scene())
	var c1 := pool.acquire("c")
	var c1_id := c1.get_instance_id()
	pool.release(c1)
	var c2 := pool.acquire("c")
	if c2.get_instance_id() != c1_id:
		print("FAIL 5: release 后 acquire 应复用同一实例")
		failures += 1
	pool.release(c2)

	# 6. release() 对定义了 _pool_reset() 的节点恰好调用一次;对普通节点 release 不报错
	var probe2 := pool.acquire("probe")
	pool.release(probe2)
	if probe2.reset_calls != 1:
		print("FAIL 6: release 应恰好调用一次 _pool_reset(),实际 %d" % probe2.reset_calls)
		failures += 1
	pool.register("plain", _make_trivial_scene())
	var plain1 := pool.acquire("plain")
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
	var d1 := pool.acquire("d")
	pool.release(d1)
	var avail_after_first_release := pool.available_count("d")
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
	var cap1 := pool.acquire("capped")
	if cap1 == null:
		print("FAIL 10: 首次 acquire 应成功")
		failures += 1
	var cap2 := pool.acquire("capped")
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
	var zombie_acquired := pool.acquire("zombie")
	if zombie_acquired == null or not is_instance_valid(zombie_acquired):
		print("FAIL 11: 丢弃僵尸引用后应返回新的有效节点")
		failures += 1
	pool.release(zombie_acquired)

	# 12. 重复注册幂等性(同一 PackedScene 引用)
	var shared_scene := _make_trivial_scene()
	pool.register("dup", shared_scene)
	var dup1 := pool.acquire("dup")
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
	var clr_reacquired := pool.acquire("clr")
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
	var novis_reacquired := pool.acquire("novis")
	if novis_reacquired.visible:
		print("FAIL 14: manage_visibility=false 时 acquire 不应把 visible 强制设为 true")
		failures += 1
	pool.release(novis_reacquired)

	pool.free()

	if failures == 0:
		print("test_object_pool: ALL PASS")
		quit(0)
	else:
		print("test_object_pool: %d FAILURE(S)" % failures)
		quit(1)
```

- [ ] **Step 2: 运行,确认失败**

```powershell
$godot = "D:\Program Files\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe"
& $godot --headless --path . -s res://test/test_object_pool.gd
```
Expected: 失败。`object_pool.gd` 尚不存在,顶层 `const ObjectPoolScript := preload(...)` 报错
（类似 `Could not preload resource file res://addons/godot-core-kit/object_pool.gd` 或等价
的“文件不存在/解析失败”提示），脚本无法加载,退出码非 0。

- [ ] **Step 3: 写实现** `addons/godot-core-kit/object_pool.gd`

```gdscript
extends Node
## ObjectPool —— godot-core-kit 全局对象池单例(骨架首版)。
##
## 以 autoload "ObjectPool" 注册。按字符串 key 管理若干个具名节点池,复用子弹、敌人、
## 粒子等高频 spawn/despawn 的 Node 实例,避免反复 instantiate()/free() 造成的实例化
## 开销与内存抖动(尤其在 Web/WASM 导出下更明显)。register() 注册池、acquire() 借出、
## release() 归还、clear() 回收当前空闲实例。纯内存操作、无文件 IO、无线程,支持 Web
## 导出。可选依赖 Log(记录告警/错误),不依赖 EventBus/SceneManager/SaveManager。
##
## 用法:
##   ObjectPool.register("bullet", bullet_scene, 20, 200)
##   var b := ObjectPool.acquire("bullet")
##   if b != null:
##       add_child(b)
##   # ... 子弹逻辑自行决定何时释放 ...
##   ObjectPool.release(b)
##
## 被池化场景可选实现的复用钩子(不是本类的方法,是一份约定):
##   func _pool_reset() -> void
## release() 用 has_method("_pool_reset") 探测,若存在则归还时调用一次,用于清空本轮
## 使用留下的状态。调用时机保证节点已至少完整经历过一次 _ready(),@onready 引用可安全
## 访问。prewarm 阶段创建的实例不触发该钩子。

## 节点上的元数据 key:本子系统创建的每个实例都会打上(归属的池 key)。release() 靠它
## 判定"这是不是我这个池发出去的节点",不需要额外维护一份反查表。
const META_POOL_KEY := "__object_pool_key"


## 内部记账单元,不对外暴露(不是 class_name)。每个注册的 key 对应一个 _PoolEntry,
## 供 headless 测试直接构造 ObjectPool 脚本实例后通过 _pools[key] 访问断言。
class _PoolEntry:
	extends RefCounted
	var scene: PackedScene
	var max_count: int = 0            # 0 = 不限
	var manage_visibility: bool = true
	var total_count: int = 0          # 已创建的实例总数(in_use + available)
	var available: Array = []         # 空闲栈,LIFO(pop_back 复用最近归还的一个)
	var in_use: Dictionary = {}       # instance_id(int) -> true,当前借出的实例


# key(String) -> _PoolEntry
var _pools: Dictionary = {}


## 注册一个池。scene 的根节点类型会被反复 instantiate() 复用。
## prewarm:注册时立即创建并放入空闲队列的实例数,默认 0(不预热)。
## max_count:该 key 允许存在的实例总数上限(in_use + available),0 = 不限(默认)。
## manage_visibility:true(默认)时 acquire()/release() 对称管理 CanvasItem/Node3D 的
## visible 属性(借出时显示、归还时隐藏);false 时池完全不碰可见性,交给调用方自行
## 处理(例如自定义淡入淡出过渡)。
## 若 key 已存在且 scene 与原来是同一个 Resource:幂等重复注册,静默忽略。
## 若 key 已存在但 scene 不同:Log.warn,保留原池,不覆盖。
func register(key: String, scene: PackedScene, prewarm: int = 0, max_count: int = 0, manage_visibility: bool = true) -> void:
	if scene == null or not scene.can_instantiate():
		Log.error("ObjectPool.register: key '%s' 的 scene 无效,无法 instantiate(),已跳过注册" % key)
		return

	if _pools.has(key):
		var existing: _PoolEntry = _pools[key]
		if existing.scene != scene:
			Log.warn("ObjectPool.register: key '%s' 已注册为不同的 scene,保留原池,忽略本次注册" % key)
		return

	var entry := _PoolEntry.new()
	entry.scene = scene
	entry.max_count = max_count
	entry.manage_visibility = manage_visibility
	_pools[key] = entry

	var effective_prewarm := prewarm
	if max_count != 0 and prewarm > max_count:
		Log.warn("ObjectPool.register: key '%s' 的 prewarm(%d) 超过 max_count(%d),已收紧 prewarm 以满足上限" % [key, prewarm, max_count])
		effective_prewarm = max_count

	for i in range(effective_prewarm):
		var node: Node = scene.instantiate()
		node.set_meta(META_POOL_KEY, key)
		entry.available.append(node)
		entry.total_count += 1


## key 是否已注册过池。
func has_pool(key: String) -> bool:
	return _pools.has(key)


## 取一个可用实例:优先复用空闲队列(LIFO),为空则按 max_count 决定新建或返回 null。
## key 未注册 → Log.error 并返回 null。已达 max_count 且无空闲 → Log.warn 并返回 null。
## 返回的节点处于游离态(不在任何场景树上);是否/何时 add_child 由调用方决定。
func acquire(key: String) -> Node:
	if not _pools.has(key):
		Log.error("ObjectPool.acquire: 未注册的 key '%s'" % key)
		return null

	var entry: _PoolEntry = _pools[key]
	var node: Node = null

	while entry.available.size() > 0:
		var candidate: Node = entry.available.pop_back()
		if is_instance_valid(candidate):
			node = candidate
			break
		# 僵尸引用(被外部绕过 release() 直接 free() 掉):丢弃并扣减记账,继续找下一个。
		entry.total_count -= 1

	if node == null:
		if entry.max_count > 0 and entry.total_count >= entry.max_count:
			Log.warn("ObjectPool.acquire: 池 '%s' 已达上限(%d),返回 null" % [key, entry.max_count])
			return null
		node = entry.scene.instantiate()
		node.set_meta(META_POOL_KEY, key)
		entry.total_count += 1

	# 同步兜底:若上一次 release() 的 call_deferred 摘除尚未执行到,这里同步摘掉父节点,
	# 避免把仍挂着旧父节点的实例交给调用方(见 release() 里的竞态说明)。
	if node.get_parent() != null:
		node.get_parent().remove_child(node)

	if entry.manage_visibility and (node is CanvasItem or node is Node3D):
		node.visible = true

	entry.in_use[node.get_instance_id()] = true
	return node


## 归还一个由 acquire() 借出的节点。安全处理:node 为 null/已失效、非本子系统创建的
## 节点、对同一节点重复 release,均为静默 no-op(附 Log.warn),绝不抛错/崩溃。
## 正常路径:调用节点的可选钩子 _pool_reset()(若定义)→ 隐藏(manage_visibility 且为
## CanvasItem/Node3D)→ 记账挪回所属池的空闲队列 → 用 call_deferred 从当前父节点摘下。
## call_deferred 的原因:release() 常从节点自身碰撞回调(area_entered/body_entered)里
## 同步触发,物理体在自己碰撞回调里同步改树有 "flushing queries" 报错风险;记账、隐藏、
## _pool_reset() 都是纯属性/字典操作,没有这个风险,保持同步执行。
func release(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		Log.warn("ObjectPool.release: node 为 null 或已失效,忽略")
		return

	if not node.has_meta(META_POOL_KEY):
		Log.warn("ObjectPool.release: node 不是本子系统创建的节点,忽略")
		return

	var key: String = node.get_meta(META_POOL_KEY)
	if not _pools.has(key):
		Log.warn("ObjectPool.release: node 所属的池 '%s' 已不存在,忽略" % key)
		return

	var entry: _PoolEntry = _pools[key]
	var instance_id := node.get_instance_id()
	if not entry.in_use.has(instance_id):
		Log.warn("ObjectPool.release: node 当前并未处于借出状态(重复 release 或未经 acquire 就归还),忽略")
		return

	entry.in_use.erase(instance_id)

	if node.has_method("_pool_reset"):
		node.call("_pool_reset")

	if entry.manage_visibility and (node is CanvasItem or node is Node3D):
		node.visible = false

	entry.available.append(node)

	var parent := node.get_parent()
	if parent != null:
		parent.remove_child.call_deferred(node)


## 释放指定 key 当前空闲(available)的全部实例(queue_free)并清空空闲队列;仍在使用中
## (in_use)的实例不受影响(若非空会 Log.warn,但不阻止 clear 执行)。池的注册信息
## (scene/max_count/manage_visibility)保留,不等于 unregister,之后仍可 acquire()
## (空闲队列为空时会重新 instantiate)。
func clear(key: String) -> void:
	if not _pools.has(key):
		return

	var entry: _PoolEntry = _pools[key]
	if entry.in_use.size() > 0:
		Log.warn("ObjectPool.clear: 池 '%s' 仍有 %d 个实例在使用中,不受 clear 影响" % [key, entry.in_use.size()])

	var freed_count := entry.available.size()
	for node in entry.available:
		if is_instance_valid(node):
			node.queue_free()
	entry.available.clear()
	entry.total_count -= freed_count


func available_count(key: String) -> int:
	if not _pools.has(key):
		return 0
	return _pools[key].available.size()


func in_use_count(key: String) -> int:
	if not _pools.has(key):
		return 0
	return _pools[key].in_use.size()


func total_count(key: String) -> int:
	if not _pools.has(key):
		return 0
	return _pools[key].total_count
```

- [ ] **Step 4: 运行,确认通过**

```powershell
& $godot --headless --path . --import
& $godot --headless --path . -s res://test/test_object_pool.gd
```
Expected: 输出含 `test_object_pool: ALL PASS`,退出码 0。(`--import` 顺带生成
`object_pool.gd.uid`、`test_object_pool.gd.uid`、`object_pool_probe.gd.uid` 边车文件。)

同时重跑既有 Logger 测试确保未回归:

```powershell
& $godot --headless --path . -s res://test/test_log.gd
```
Expected: `test_log: ALL PASS`,退出码 0(`object_pool.gd` 未改动 `Log`/`CoreKit`,理论上
不应有任何交互,此步骤仅作双保险)。

- [ ] **Step 5: 提交**

```powershell
git add addons/godot-core-kit/object_pool.gd addons/godot-core-kit/object_pool.gd.uid `
        test/test_object_pool.gd test/test_object_pool.gd.uid `
        test/fixtures/object_pool_probe.gd test/fixtures/object_pool_probe.gd.uid
git commit -m @'
feat: add ObjectPool core (register/acquire/release/clear)

ObjectPool 单例:_PoolEntry 记账(scene/max_count/manage_visibility/
total_count/available/in_use),register() 支持 prewarm 与 max_count
上限收紧、acquire() 复用空闲队列(僵尸引用检测)/新建/上限拒绝、
release() 走 _pool_reset() 钩子 + 对称可见性管理(manage_visibility 可
关闭)+ call_deferred 摘除父节点、clear() 回收空闲队列。headless 断言
14 条覆盖同步部分,deferred detach 留给后续集成步骤的 demo 冒烟。
尚未接线为 autoload、未升版本号(见计划范围边界)。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## 完成后

`object_pool.gd` + 测试完成后,`ObjectPool` 子系统的核心逻辑即已就绪,但**尚未接入工程**。
后续需要一个独立的集成步骤(结构参考 `2026-07-01-logger.md` 的 Task 2):把 `ObjectPool` 注册
为 autoload(`plugin.gd`/`project.godot`,顺序上可与 `Log`/`CoreKit` 并列,无需在其之前或之后,
因为 `ObjectPool` 不在 `_ready()` 里主动调用 `CoreKit`,只在方法体内调用 `Log`)、版本号
0.2.0 → 0.3.0(`plugin.cfg`/`core_kit.gd`/`README.md`)、demo 场景加冒烟段验证
`call_deferred` 摘除父节点确实生效。该集成步骤走 `/rebase-merge` 提 MR 合入,保持线性历史。
