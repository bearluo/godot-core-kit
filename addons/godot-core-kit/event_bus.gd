extends Node
## EventBus —— godot-core-kit 全局发布/订阅事件总线(骨架首版)。
##
## 由 CoreKit 门面在 _init 中构造并 add_child,不再是独立注册的 project autoload,
## 经 CoreKit.bus 访问(唯一 autoload 是 CoreKit 本身)。用字符串事件名解耦"发布方"与"订阅方",
## 补充(而非取代)Godot 原生 signal:两节点有直接引用关系时仍优先用原生
## signal/connect;EventBus 只用于没有引用关系、订阅方不确定的广播场景。
##
## 核心语义:单个 Variant payload;publish() 按订阅顺序(FIFO)对当前订阅
## 做一次快照后同步派发,派发期间对该事件的 subscribe/unsubscribe 只影响
## 下一次 publish(重入安全);查询/派发时惰性剔除已失效(被 free() 的
## Node/Object)的 Callable,无需轮询或手动 unsubscribe。
##
## 用法:
##   CoreKit.bus.subscribe("player_died", _on_player_died)
##   CoreKit.bus.publish("player_died", {"hp": 0})
##
## 注意(RefCounted 监听者的边界情况):Callable 绑定到 RefCounted(含普通
## `class ... extends RefCounted`、Resource 等)方法时,Callable 本身持有
## 该对象一份强引用,只要订阅还在,目标对象就不会被引用计数归零——纯
## RefCounted 监听者不会自然触发自动剔除,必须显式 unsubscribe()/
## unsubscribe_all()。自动剔除主要覆盖 Node/Object(非引用计数)监听者。
##
## EventBus 零依赖:不依赖本仓库的 Log/SceneManager/ObjectPool/SaveManager。

## 每次 publish() 之后广播一次,payload 为 null 表示无载荷。
## 用于旁路监听"全部事件"(调试面板、埋点),常规业务订阅请用 subscribe()。
signal event_published(event_name: String, payload: Variant)


## 单条订阅记录:callable + 是否一次性。用内部类而非裸 Callable 数组,
## 让 once 标记跟随订阅记录本身,不需要额外平行数组。
class _Subscription:
	extends RefCounted
	var callable: Callable
	var once: bool

	func _init(p_callable: Callable, p_once: bool) -> void:
		callable = p_callable
		once = p_once


## event_name(String) -> Array[_Subscription],value 为该事件当前订阅记录的
## 有序数组(插入顺序 = 触发顺序)。
var _listeners: Dictionary = {}


## 订阅 event_name。listener 应为形如 func(payload: Variant) -> void 的 Callable。
## 同一 (event_name, listener) 重复订阅为幂等空操作(不会重复触发)。
## once = true 等价于 subscribe_once()。event_name 不可为空字符串(保留给 clear() 语义)。
func subscribe(event_name: String, listener: Callable, once: bool = false) -> void:
	if event_name.is_empty():
		return
	if not _listeners.has(event_name):
		_listeners[event_name] = []
	var bucket: Array = _listeners[event_name]
	for sub in bucket:
		if sub.callable == listener:
			return
	bucket.append(_Subscription.new(listener, once))


## 语法糖:subscribe(event_name, listener, true)。触发一次后自动取消订阅。
func subscribe_once(event_name: String, listener: Callable) -> void:
	subscribe(event_name, listener, true)


## 取消订阅指定 (event_name, listener)。listener 未订阅时为空操作,不报错。
func unsubscribe(event_name: String, listener: Callable) -> void:
	if not _listeners.has(event_name):
		return
	var bucket: Array = _listeners[event_name]
	for i in range(bucket.size()):
		if bucket[i].callable == listener:
			bucket.remove_at(i)
			break
	if bucket.is_empty():
		_listeners.erase(event_name)


## 取消 target 在所有事件上的全部订阅(Callable.get_object() == target 的都移除)。
## 用于对象在 _exit_tree()/queue_free 前主动清理,是自动失效清理之外的显式手段。
func unsubscribe_all(target: Object) -> void:
	var empty_keys: Array = []
	for event_name in _listeners.keys():
		var bucket: Array = _listeners[event_name]
		var i := bucket.size() - 1
		while i >= 0:
			if bucket[i].callable.get_object() == target:
				bucket.remove_at(i)
			i -= 1
		if bucket.is_empty():
			empty_keys.append(event_name)
	for key in empty_keys:
		_listeners.erase(key)


## 同步派发 event_name。按订阅顺序(FIFO)依次调用当前快照里的 listener.call(payload)。
## 派发期间对该事件的 subscribe/unsubscribe 只影响下一次 publish(),不影响本次快照。
## 无论是否有订阅者,都会额外广播一次 event_published 信号(供旁路监听)。
func publish(event_name: String, payload: Variant = null) -> void:
	var snapshot: Array = []
	if _listeners.has(event_name):
		snapshot = (_listeners[event_name] as Array).duplicate()
	var to_remove: Array = []
	for sub in snapshot:
		if not sub.callable.is_valid():
			to_remove.append(sub)
			continue
		sub.callable.call(payload)
		if sub.once:
			to_remove.append(sub)
	if not to_remove.is_empty() and _listeners.has(event_name):
		var live: Array = _listeners[event_name]
		for sub in to_remove:
			live.erase(sub)
		if live.is_empty():
			_listeners.erase(event_name)
	emit_signal("event_published", event_name, payload)


## 是否存在至少一个有效订阅(查询时惰性剔除已失效的 Callable)。
func has_listeners(event_name: String) -> bool:
	return get_listener_count(event_name) > 0


## 返回 event_name 当前有效订阅数(查询时惰性剔除已失效的 Callable)。
func get_listener_count(event_name: String) -> int:
	_prune_invalid(event_name)
	if not _listeners.has(event_name):
		return 0
	return (_listeners[event_name] as Array).size()


## 清空指定事件的全部订阅;event_name 为空字符串(默认)时清空所有事件的全部订阅。
## 供测试隔离 / 场景切换重置使用。
func clear(event_name: String = "") -> void:
	if event_name.is_empty():
		_listeners.clear()
	else:
		_listeners.erase(event_name)


## 剔除 event_name 桶里已失效的 Callable(供 has_listeners/get_listener_count 复用)。
func _prune_invalid(event_name: String) -> void:
	if not _listeners.has(event_name):
		return
	var bucket: Array = _listeners[event_name]
	var i := bucket.size() - 1
	while i >= 0:
		if not bucket[i].callable.is_valid():
			bucket.remove_at(i)
		i -= 1
	if bucket.is_empty():
		_listeners.erase(event_name)
