extends SceneTree
## EventBus headless 断言测试(不依赖 autoload,直接实例化脚本)。
## 覆盖 docs/superpowers/specs/2026-07-01-event-bus-design.md 规划的 13 个测试用例。
## 运行:godot --headless --path . -s res://test/test_event_bus.gd

const EventBusScript := preload("res://addons/godot-core-kit/event_bus.gd")


## 测试用监听者:Node 子类,记录被调用次数与最近一次收到的 payload。
## 用 Node(而非 RefCounted)是为了覆盖"监听者被 free() 后自动失效"路径
## ——RefCounted 监听者的 Callable 不会自然失效,细节见设计文档的边界情况说明。
class TestListener:
	extends Node
	var call_count: int = 0
	var last_payload = null

	func on_event(payload) -> void:
		call_count += 1
		last_payload = payload


func _initialize() -> void:
	var failures := 0
	failures += _test_basic_subscribe_publish()          # 1. 基本订阅/发布
	failures += _test_multi_subscribe_order()             # 2. 多订阅顺序 FIFO
	failures += _test_unsubscribe()                       # 3. unsubscribe 生效
	failures += _test_event_name_isolation()               # 4. 事件名隔离
	failures += _test_subscribe_once()                    # 5. subscribe_once
	failures += _test_duplicate_subscribe_dedup()          # 6. 重复订阅去重
	failures += _test_auto_prune_invalid_listener()        # 7. 自动剔除失效监听
	failures += _test_unsubscribe_all()                    # 8. unsubscribe_all(target)
	failures += _test_reentrant_subscribe_during_dispatch()    # 9. 重入:派发中 subscribe
	failures += _test_reentrant_unsubscribe_during_dispatch()  # 10. 重入:派发中 unsubscribe
	failures += _test_event_published_wildcard_signal()    # 11. event_published 旁路信号
	failures += _test_clear()                              # 12. clear(event_name) 与 clear()
	failures += _test_default_payload()                    # 13. 默认 payload 为 null

	if failures == 0:
		print("test_event_bus: ALL PASS")
		quit(0)
	else:
		print("test_event_bus: %d FAILURE(S)" % failures)
		quit(1)


func _test_basic_subscribe_publish() -> int:
	var bus = EventBusScript.new()
	var listener := TestListener.new()
	bus.subscribe("evt", listener.on_event)
	bus.publish("evt", {"x": 1})
	var fails := 0
	if listener.call_count != 1:
		print("FAIL basic_subscribe_publish: call_count 应为 1,得到 %d" % listener.call_count)
		fails += 1
	if listener.last_payload == null or listener.last_payload.get("x") != 1:
		print("FAIL basic_subscribe_publish: payload 不匹配,得到 %s" % [listener.last_payload])
		fails += 1
	listener.free()
	bus.free()
	return fails


func _test_multi_subscribe_order() -> int:
	var bus = EventBusScript.new()
	var order: Array = []
	var handler_a := func(_p): order.append("A")
	var handler_b := func(_p): order.append("B")
	var handler_c := func(_p): order.append("C")
	bus.subscribe("evt", handler_a)
	bus.subscribe("evt", handler_b)
	bus.subscribe("evt", handler_c)
	bus.publish("evt")
	var fails := 0
	if order != ["A", "B", "C"]:
		print("FAIL multi_subscribe_order: 得到 %s" % [order])
		fails += 1
	bus.free()
	return fails


func _test_unsubscribe() -> int:
	var bus = EventBusScript.new()
	var listener := TestListener.new()
	bus.subscribe("evt", listener.on_event)
	bus.unsubscribe("evt", listener.on_event)
	bus.publish("evt")
	var fails := 0
	if listener.call_count != 0:
		print("FAIL unsubscribe: call_count 应为 0,得到 %d" % listener.call_count)
		fails += 1
	listener.free()
	bus.free()
	return fails


func _test_event_name_isolation() -> int:
	var bus = EventBusScript.new()
	var listener := TestListener.new()
	bus.subscribe("a", listener.on_event)
	bus.publish("b")
	var fails := 0
	if listener.call_count != 0:
		print("FAIL event_name_isolation: call_count 应为 0,得到 %d" % listener.call_count)
		fails += 1
	listener.free()
	bus.free()
	return fails


func _test_subscribe_once() -> int:
	var bus = EventBusScript.new()
	var listener := TestListener.new()
	bus.subscribe_once("evt", listener.on_event)
	bus.publish("evt")
	bus.publish("evt")
	var fails := 0
	if listener.call_count != 1:
		print("FAIL subscribe_once: call_count 应为 1,得到 %d" % listener.call_count)
		fails += 1
	if bus.get_listener_count("evt") != 0:
		print("FAIL subscribe_once: get_listener_count 应为 0,得到 %d" % bus.get_listener_count("evt"))
		fails += 1
	listener.free()
	bus.free()
	return fails


func _test_duplicate_subscribe_dedup() -> int:
	var bus = EventBusScript.new()
	var listener := TestListener.new()
	bus.subscribe("evt", listener.on_event)
	bus.subscribe("evt", listener.on_event)
	bus.publish("evt")
	var fails := 0
	if listener.call_count != 1:
		print("FAIL duplicate_subscribe_dedup: call_count 应为 1,得到 %d" % listener.call_count)
		fails += 1
	if bus.get_listener_count("evt") != 1:
		print("FAIL duplicate_subscribe_dedup: get_listener_count 应为 1,得到 %d" % bus.get_listener_count("evt"))
		fails += 1
	listener.free()
	bus.free()
	return fails


func _test_auto_prune_invalid_listener() -> int:
	var bus = EventBusScript.new()
	var listener := TestListener.new()
	bus.subscribe("evt", listener.on_event)
	listener.free()
	var fails := 0
	bus.publish("evt")  # 不应报错
	if bus.get_listener_count("evt") != 0:
		print("FAIL auto_prune_invalid_listener: get_listener_count 应为 0,得到 %d" % bus.get_listener_count("evt"))
		fails += 1
	bus.free()
	return fails


func _test_unsubscribe_all() -> int:
	var bus = EventBusScript.new()
	var listener := TestListener.new()
	bus.subscribe("evt_a", listener.on_event)
	bus.subscribe("evt_b", listener.on_event)
	bus.unsubscribe_all(listener)
	bus.publish("evt_a")
	bus.publish("evt_b")
	var fails := 0
	if listener.call_count != 0:
		print("FAIL unsubscribe_all: call_count 应为 0,得到 %d" % listener.call_count)
		fails += 1
	listener.free()
	bus.free()
	return fails


func _test_reentrant_subscribe_during_dispatch() -> int:
	var bus = EventBusScript.new()
	var d_calls := [0]  # 用单元素 Array 包裹计数器:GDScript lambda 捕获局部变量是按值捕获,
	                     # 在 lambda 内部对 int/bool 之类值类型的修改不会回写外层变量,
	                     # 但 Array/Dictionary/Object 是引用类型,修改会双向可见。
	var handler_d := func(_p): d_calls[0] += 1
	var handler_a := func(_p): bus.subscribe("evt", handler_d)
	bus.subscribe("evt", handler_a)
	bus.publish("evt")
	var fails := 0
	if d_calls[0] != 0:
		print("FAIL reentrant_subscribe: 本轮 D 不应被调用,得到 %d 次" % d_calls[0])
		fails += 1
	bus.publish("evt")
	if d_calls[0] != 1:
		print("FAIL reentrant_subscribe: 下一轮 D 应被调用一次,得到 %d 次" % d_calls[0])
		fails += 1
	bus.free()
	return fails


func _test_reentrant_unsubscribe_during_dispatch() -> int:
	var bus = EventBusScript.new()
	var c_calls := [0]
	var handler_c := func(_p): c_calls[0] += 1
	var handler_a := func(_p): bus.unsubscribe("evt", handler_c)
	bus.subscribe("evt", handler_a)
	bus.subscribe("evt", handler_c)
	bus.publish("evt")
	var fails := 0
	if c_calls[0] != 1:
		print("FAIL reentrant_unsubscribe: 本轮 C 仍应被调用一次(快照语义),得到 %d 次" % c_calls[0])
		fails += 1
	bus.publish("evt")
	if c_calls[0] != 1:
		print("FAIL reentrant_unsubscribe: 下一轮 C 不应再被调用,累计得到 %d 次" % c_calls[0])
		fails += 1
	bus.free()
	return fails


func _test_event_published_wildcard_signal() -> int:
	var bus = EventBusScript.new()
	var received: Array = []
	bus.event_published.connect(func(event_name, payload): received.append([event_name, payload]))
	bus.publish("evt_with_listener", "p1")
	bus.subscribe("evt_with_listener", func(_p): pass)
	bus.publish("evt_no_listener", "p2")
	var fails := 0
	if received.size() != 2:
		print("FAIL event_published_wildcard: 应收到 2 次广播,得到 %d" % received.size())
		fails += 1
	else:
		if received[0][0] != "evt_with_listener" or received[0][1] != "p1":
			print("FAIL event_published_wildcard: 第 1 次广播内容不匹配,得到 %s" % [received[0]])
			fails += 1
		if received[1][0] != "evt_no_listener" or received[1][1] != "p2":
			print("FAIL event_published_wildcard: 第 2 次广播内容不匹配,得到 %s" % [received[1]])
			fails += 1
	bus.free()
	return fails


func _test_clear() -> int:
	var bus = EventBusScript.new()
	var listener := TestListener.new()
	bus.subscribe("evt_a", listener.on_event)
	bus.subscribe("evt_b", listener.on_event)
	bus.clear("evt_a")
	var fails := 0
	if bus.has_listeners("evt_a"):
		print("FAIL clear: clear(evt_a) 后 evt_a 不应再有监听者")
		fails += 1
	if not bus.has_listeners("evt_b"):
		print("FAIL clear: clear(evt_a) 不应影响 evt_b")
		fails += 1
	bus.clear()
	if bus.has_listeners("evt_b"):
		print("FAIL clear: clear() 后 evt_b 不应再有监听者")
		fails += 1
	bus.publish("evt_a")
	bus.publish("evt_b")
	if listener.call_count != 0:
		print("FAIL clear: 全部 clear 后 publish 不应触发任何回调,得到 %d 次" % listener.call_count)
		fails += 1
	listener.free()
	bus.free()
	return fails


func _test_default_payload() -> int:
	var bus = EventBusScript.new()
	var listener := TestListener.new()
	bus.subscribe("evt", listener.on_event)
	bus.publish("evt")
	var fails := 0
	if listener.last_payload != null:
		print("FAIL default_payload: 未传 payload 时应收到 null,得到 %s" % [listener.last_payload])
		fails += 1
	listener.free()
	bus.free()
	return fails
