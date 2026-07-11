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

	# SaveManager 资源守卫冒烟:含 Object 的 save 被拒(返回 false,不落盘)
	var guard_ok := CoreKit.saves.save("__demo_guard__", {"bad": Resource.new()})
	CoreKit.log.info("SaveManager 资源守卫拒 Object save=%s (应为 false)" % guard_ok)

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

	# KitStateMachine 冒烟:代码组一台三态状态机(类库,不经门面)——transition_to + dispatch + pushdown
	var machine := KitStateMachine.new()
	var idle := KitState.new()
	idle.name = "Idle"
	machine.add_child(idle)
	var run := KitState.new()
	run.name = "Run"
	machine.add_child(run)
	var menu := KitState.new()
	menu.name = "Menu"
	machine.add_child(menu)
	machine.state_changed.connect(func(from: String, to: String) -> void:
		CoreKit.log.info("KitStateMachine: [%s] -> [%s]" % [from, to]))
	add_child(machine)          # 触发 _ready:进 Idle
	machine.transition_to("Run")
	machine.add_transition(machine.ANYSTATE, "Idle", "stop")   # 通配事件:任意态收到 stop → Idle
	CoreKit.log.info("KitStateMachine: dispatch(stop) hit=%s" % machine.dispatch("stop"))  # Run --stop--> Idle
	machine.push_state("Menu")  # 暂停 Idle,压栈,进 Menu(暂停语义)
	machine.pop_state()         # 弹回 Idle(resume),现场保留
	CoreKit.log.info("KitStateMachine: stack_depth=%d" % machine.stack_depth())

	# KitContext 冒烟:全局 provide/service + 作用域容器 + 收养随树释放(DI 容器,类库)
	CoreKit.provide("demo_service", {"id": 7})
	var ctx := KitContext.new()
	ctx.name = "DemoCtx"
	add_child(ctx)
	ctx.provide("scoped", "level-only")
	ctx.provide_child("owned_child", Node.new())
	CoreKit.log.info("KitContext: scoped=%s global=%s builtin_audio=%s owned=%d" % [
		KitContext.resolve(ctx, "scoped"),
		KitContext.resolve(ctx, "demo_service"),
		ctx.service("audio") == CoreKit.audio,
		ctx.get_child_count()])

	# 订阅式解析 + 工厂 scope 冒烟
	ctx.subscribe("late_svc", func(v): CoreKit.log.info("KitContext: 订阅回调 late_svc=%s" % v))
	ctx.provide("late_svc", "arrived")   # 触发上面订阅回调
	ctx.provide_factory("rng", func() -> RefCounted: return RefCounted.new(), KitContext.Scope.TRANSIENT)
	CoreKit.log.info("KitContext: transient 两次不同=%s" % (ctx.service("rng") != ctx.service("rng")))

	ctx.free()  # 随树释放,收养的子节点连带回收

	# DevConsole 冒烟:注册作弊命令 + 绑定上下文 + watch + 程序化 execute(经门面)
	var cheat := func(args: PackedStringArray) -> Variant: return "god mode"
	CoreKit.console.register_command("god", cheat, "toggle god mode")
	CoreKit.console.bind_context("demo_ctx", self)
	CoreKit.console.watch("1 + 1")
	CoreKit.log.info("DevConsole: execute(1+2)=%s" % CoreKit.console.execute("1 + 2"))
	CoreKit.log.info("DevConsole: god cheat -> %s" % CoreKit.console.execute("god"))

	# i18n 冒烟:内存注册两语翻译 + 切语言 + 托管 t() + 字体绑定(经门面第 12 子系统)
	var en_tr := Translation.new()
	en_tr.locale = "en"
	en_tr.add_message("DEMO_HELLO", "Hello")
	var zh_tr := Translation.new()
	zh_tr.locale = "zh"
	zh_tr.add_message("DEMO_HELLO", "你好")
	CoreKit.i18n.add_translation(en_tr)
	CoreKit.i18n.add_translation(zh_tr)
	CoreKit.i18n.register_locale_font("zh", FontFile.new())
	CoreKit.i18n.bind_theme(Theme.new())
	CoreKit.i18n.set_locale("en")
	CoreKit.log.info("i18n: locale=%s t(DEMO_HELLO)=%s" % [CoreKit.i18n.get_locale(), CoreKit.i18n.t("DEMO_HELLO")])
	CoreKit.i18n.set_locale("zh")
	CoreKit.log.info("i18n: locale=%s t(DEMO_HELLO)=%s available=%s" % [
		CoreKit.i18n.get_locale(), CoreKit.i18n.t("DEMO_HELLO"), CoreKit.i18n.available_locales()])
	CoreKit.settings.erase_section("locale")  # 清 demo 落盘的 locale,保多次运行确定性

	# 设置/重绑定 UI 冒烟:临时动作 + KitRebindButton 程序化 capture(正常 + 冲突拦截)
	InputMap.add_action("demo_rebind_a")
	InputMap.action_add_event("demo_rebind_a", _demo_key(KEY_SPACE))
	InputMap.add_action("demo_rebind_b")
	InputMap.action_add_event("demo_rebind_b", _demo_key(KEY_G))
	CoreKit.input._snapshot_defaults()  # 让 InputManager 认识新动作(快照默认)
	var rebind_btn := KitRebindButton.new()
	rebind_btn.setup("demo_rebind_a", PackedStringArray(["demo_rebind_a", "demo_rebind_b"]))
	var rb_ok := rebind_btn.capture_event(_demo_key(KEY_F, true))       # 正常重绑 a -> F
	var rb_conflict := rebind_btn.capture_event(_demo_key(KEY_G, true)) # 撞 b(G),拦截
	CoreKit.log.info("RebindUI: rebind ok=%s conflict_blocked=%s" % [rb_ok, not rb_conflict])
	rebind_btn.free()
	InputMap.erase_action("demo_rebind_a")
	InputMap.erase_action("demo_rebind_b")
	CoreKit.settings.erase_value("input", "demo_rebind_a")  # 清 demo 重绑落盘,保确定性

	CoreKit.log.info("CoreKit v%s — all subsystems smoke-tested" % CoreKit.VERSION)


func _on_demo_event(payload) -> void:
	CoreKit.log.info("EventBus delivered: %s" % payload)


func _make_dummy_scene() -> PackedScene:
	var scene := PackedScene.new()
	var root := Node.new()
	scene.pack(root)
	root.free()
	return scene


func _demo_key(keycode: int, pressed: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = pressed
	return ev
