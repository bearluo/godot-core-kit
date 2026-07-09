extends Node
## 冒烟测试场景:证明 CoreKit 门面与全部子系统已就绪且可调用。
## 用 Godot 4 打开工程直接运行(或 headless --quit-after 60)即可,
## 输出应看到各子系统按预期响应、无报错。

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

	# Settings 冒烟:写 → 读 → 清(user://settings.json 写透)
	CoreKit.settings.set_value("demo", "flag", true)
	CoreKit.log.info("Settings demo.flag = %s" % CoreKit.settings.get_value("demo", "flag"))
	CoreKit.settings.erase_section("demo")

	# FrameScheduler 冒烟:降频心跳 + 预算任务(输出在后续帧出现)
	CoreKit.ticker.every_n(func() -> void: CoreKit.log.info("FrameScheduler: 每 30 帧心跳"), 30)
	CoreKit.ticker.queue_task(func() -> void: CoreKit.log.info("FrameScheduler: 预算任务已执行"))

	# InputManager 冒烟:设备与缓冲查询
	CoreKit.log.info("InputManager current_device = %d, jump buffered = %s" % [
		CoreKit.input.current_device, CoreKit.input.is_action_buffered("ui_accept", 0.2)])

	# AudioManager 冒烟:音量设置(经 Settings 持久化)
	CoreKit.audio.set_volume("music", 0.8)
	CoreKit.log.info("AudioManager music volume = %.2f" % CoreKit.audio.get_volume("music"))

	# ResourceManager 冒烟:异步预热(completed 在后续帧广播,验证 deferred 投递)
	CoreKit.res.batch_completed.connect(func() -> void: CoreKit.log.info("ResourceManager: 预热批完成"))
	CoreKit.res.preload_batch(["res://addons/godot-core-kit/core/log.gd"])

	# KitStateMachine 冒烟:代码组一台两态状态机(类库,不经门面)
	var machine := KitStateMachine.new()
	var idle := KitState.new()
	idle.name = "Idle"
	machine.add_child(idle)
	var run := KitState.new()
	run.name = "Run"
	machine.add_child(run)
	machine.state_changed.connect(func(from: String, to: String) -> void:
		CoreKit.log.info("KitStateMachine: [%s] -> [%s]" % [from, to]))
	add_child(machine)          # 触发 _ready:进 Idle
	machine.transition_to("Run")

	CoreKit.log.info("CoreKit v%s — all subsystems smoke-tested" % CoreKit.VERSION)


func _on_demo_event(payload) -> void:
	CoreKit.log.info("EventBus delivered: %s" % payload)


func _make_dummy_scene() -> PackedScene:
	var scene := PackedScene.new()
	var root := Node.new()
	scene.pack(root)
	root.free()
	return scene
