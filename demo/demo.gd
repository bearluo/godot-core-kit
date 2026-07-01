extends Node
## 冒烟测试场景:证明全部 core-kit autoload 已就绪且可调用
## (Log / EventBus / SceneManager / ObjectPool / SaveManager / CoreKit)。
## 用 Godot 4 打开工程直接运行即可,输出应看到各子系统按预期响应、无报错。

func _ready() -> void:
	Log.info("demo scene loaded — core-kit is wired up correctly")

	# EventBus 冒烟:订阅 → 发布 → 同步回调
	EventBus.subscribe("demo_event", _on_demo_event)
	EventBus.publish("demo_event", "hello from EventBus")

	# SceneManager 冒烟:查询状态(不真正切场景)
	Log.info("SceneManager.is_changing = %s" % SceneManager.is_changing())

	# ObjectPool 冒烟:注册 → 借出 → 归还
	ObjectPool.register("demo_pool", _make_dummy_scene(), 2)
	var n: Node = ObjectPool.acquire("demo_pool")
	Log.info("ObjectPool acquired=%s available=%d in_use=%d" % [
		n != null, ObjectPool.available_count("demo_pool"), ObjectPool.in_use_count("demo_pool")])
	ObjectPool.release(n)

	# SaveManager 冒烟:存 → 读 → 删(user:// 落盘往返)
	var ok := SaveManager.save("__demo_smoke__", {"score": 42, "name": "hero"})
	var data := SaveManager.load("__demo_smoke__")
	Log.info("SaveManager save=%s load=%s" % [ok, data])
	SaveManager.delete_slot("__demo_smoke__")

	Log.info("CoreKit v%s — all subsystems smoke-tested" % CoreKit.VERSION)


func _on_demo_event(payload) -> void:
	Log.info("EventBus delivered: %s" % payload)


func _make_dummy_scene() -> PackedScene:
	var scene := PackedScene.new()
	var root := Node.new()
	scene.pack(root)
	root.free()
	return scene
