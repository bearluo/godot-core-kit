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
