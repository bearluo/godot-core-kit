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
		var candidate = entry.available.pop_back()  # 不标注类型:僵尸(已 free)实例赋给 typed Node 会抛"invalid freed instance"
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
