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

## 工厂注册的生命周期:SINGLETON 首次 service 创建并缓存;TRANSIENT 每次 service 新建。
enum Scope { SINGLETON, TRANSIENT }

var _factories: Dictionary = {}    # key:String -> {"factory": Callable, "scope": int}
var _singletons: Dictionary = {}   # key:String -> 已实例化的 SINGLETON 缓存

var _subscribers: Dictionary = {}  # key:String -> Array[Callable]
var _child_ctxs: Array = []        # 直接子容器(KitContext);不标类型,避免自引用编译风险


## 注册服务到本层。只存引用,绝不动树。重复键覆盖并告警。可 shadow 祖先/全局同名键。
func provide(key: String, svc: Variant) -> void:
	if _local.has(key) or _factories.has(key):
		push_warning("KitContext.provide('%s'): 覆盖同层已注册服务" % key)
	_local[key] = svc
	_factories.erase(key)
	_singletons.erase(key)
	_notify(key)


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
	_notify(key)


## 以工厂注册服务。SINGLETON:首次 service() 调一次工厂并缓存;TRANSIENT:每次
## service() 都调工厂返新实例。面向普通值 / RefCounted;Node 型服务请用 provide_child
## (容器负责其生命周期)。同层覆盖 value/其它工厂并告警。
func provide_factory(key: String, factory: Callable, scope: int = Scope.SINGLETON) -> void:
	if _local.has(key) or _factories.has(key):
		push_warning("KitContext.provide_factory('%s'): 覆盖同层已注册服务" % key)
	_factories[key] = {"factory": factory, "scope": scope}
	_local.erase(key)
	_singletons.erase(key)
	_notify(key)


## 解析:本层 value → 本层 factory → 最近祖先容器 → CoreKit 全局根。
func service(key: String) -> Variant:
	if _local.has(key):
		return _local[key]
	if _factories.has(key):
		return _resolve_factory(key)
	if _parent_ctx != null:
		return _parent_ctx.service(key)
	return _global(key)


## 沿同一条链的存在性检查,不报错。
func has(key: String) -> bool:
	if _local.has(key) or _factories.has(key):
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
	# 两处迭代都取快照(.duplicate()):投递中订阅者可能在自己的回调里 unsubscribe
	# (subscribe-once 模式),迭代活数组会因索引前移漏投同 key 的兄弟订阅者。
	for cb in _subscribers.get(key, []).duplicate():
		(cb as Callable).call(owner._owner_value(key))
	for child in _child_ctxs.duplicate():
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
	if _parent_ctx != null and not _parent_ctx._child_ctxs.has(self):
		_parent_ctx._child_ctxs.append(self)


func _exit_tree() -> void:
	# 仅注销树成员关系(_child_ctxs):节点离开旧父(reparent 或移除)时从旧父的子容器表
	# 移除,避免旧父继续向已移走的子树投递(stale delivery)。此刻 _parent_ctx 仍是旧父
	# (下次 _enter_tree 才重算)。不清服务表——disposal 仍只走 PREDELETE。
	if _parent_ctx != null and is_instance_valid(_parent_ctx):
		_parent_ctx._child_ctxs.erase(self)


func _find_parent_ctx() -> KitContext:
	var n := get_parent()
	while n != null:
		if n is KitContext:
			return n as KitContext
		n = n.get_parent()
	return null


## 按 scope 解析工厂:TRANSIENT 每次新建;SINGLETON 首次创建并缓存。
func _resolve_factory(key: String) -> Variant:
	var e: Dictionary = _factories[key]
	if int(e["scope"]) == Scope.TRANSIENT:
		return (e["factory"] as Callable).call()
	if not _singletons.has(key):
		_singletons[key] = (e["factory"] as Callable).call()
	return _singletons[key]


func _notification(what: int) -> void:
	# disposal 走 PREDELETE:_exit_tree 在 reparent 时也触发,不能用来清表。
	if what == NOTIFICATION_PREDELETE:
		if _parent_ctx != null and is_instance_valid(_parent_ctx):
			_parent_ctx._child_ctxs.erase(self)
		_local.clear()
		_factories.clear()
		_singletons.clear()
		_subscribers.clear()


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
