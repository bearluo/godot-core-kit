extends Node
## 冒烟测试场景:证明 CoreKit 门面与全部子系统已就绪且可调用。
## 用 Godot 4 打开工程直接运行即可,输出应看到各子系统按预期响应、无报错。

func _ready() -> void:
	CoreKit.log.info("demo scene loaded — core-kit is wired up correctly")

	# EventBus 冒烟:订阅 → 发布 → 同步回调
	CoreKit.bus.subscribe("demo_event", _on_demo_event)
	CoreKit.bus.publish("demo_event", "hello from EventBus")

	# SceneManager 冒烟:查询状态(不真正切场景)
	CoreKit.log.info("SceneManager.is_changing = %s" % CoreKit.scenes.is_changing())

	# ObjectPool 冒烟:注册 → 借出 → 归还
	CoreKit.pool.register("demo_pool", _make_dummy_scene(), 2)
	var n: Node = CoreKit.pool.acquire("demo_pool")
	CoreKit.log.info("ObjectPool acquired=%s available=%d in_use=%d" % [
		n != null, CoreKit.pool.available_count("demo_pool"), CoreKit.pool.in_use_count("demo_pool")])
	CoreKit.pool.release(n)

	# SaveManager 冒烟:存 → 读 → 删(user:// 落盘往返)
	var ok := CoreKit.saves.save("__demo_smoke__", {"score": 42, "name": "hero"})
	var data := CoreKit.saves.load("__demo_smoke__")
	CoreKit.log.info("SaveManager save=%s load=%s" % [ok, data])
	CoreKit.saves.delete_slot("__demo_smoke__")

	CoreKit.log.info("CoreKit v%s — facade smoke-tested" % CoreKit.VERSION)


func _on_demo_event(payload) -> void:
	CoreKit.log.info("EventBus delivered: %s" % payload)


func _make_dummy_scene() -> PackedScene:
	var scene := PackedScene.new()
	var root := Node.new()
	scene.pack(root)
	root.free()
	return scene
