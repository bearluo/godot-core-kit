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
	_probe_persistence()
	_probe_pack_mount()
	_probe_cdn_download()

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

	# 转场缓动 冒烟:构造 SLIDE KitTransition + 纯几何 marker(不真切场景,headless 确定性)
	var tr := KitTransition.new()
	tr.type = KitTransition.Type.SLIDE
	tr.direction = KitTransition.Dir.LEFT
	tr.duration = 0.4
	CoreKit.log.info("Transition: type=SLIDE none=%s slide_cover_from=%s" % [
		tr.is_none(), tr.slide_cover_from(Vector2(800, 600))])

	# UI 栈导航 冒烟:代码建栈 push 3 屏(含 1 模态)+ 读 marker(类库,不经门面)
	var ui_stack := KitUiStack.new()
	add_child(ui_stack)
	var sa := Control.new(); sa.name = "ScreenA"; ui_stack.push(sa)
	var sb := Control.new(); sb.name = "ScreenB"; ui_stack.push(sb)
	var sc := Control.new(); sc.name = "ScreenC"
	ui_stack.push(sc, {"hide_below": false, "dim": Color(0, 0, 0, 0.4)})
	CoreKit.log.info("UiStack: depth=%d top=%s modal_backdrop=%s" % [
		ui_stack.depth(), ui_stack.top().name, ui_stack._stack[-1]["backdrop"] != null])
	ui_stack.clear()
	ui_stack.free()

	# UI 层级管理器 冒烟:mount 一个 Control 到 hud 层 + 读 z marker(经门面第 13 子系统)
	var hud_probe := Control.new()
	CoreKit.layers.mount(hud_probe, "hud")
	CoreKit.log.info("Layers: hud_z=%d modal_z=%d mounted=%s" % [
		CoreKit.layers.layer("hud").layer, CoreKit.layers.MODAL,
		hud_probe.get_parent() == CoreKit.layers.layer("hud")])
	CoreKit.layers.clear("hud")

	# 游戏时钟 冒烟:订阅 clock:day_changed + advance_day(经门面第 14 子系统)
	var day_evt := {"hit": false}
	CoreKit.bus.subscribe(CoreKit.clock.EV_DAY_CHANGED, func(_p): day_evt["hit"] = true)
	CoreKit.clock.advance_day()
	CoreKit.log.info("Clock: y%d %s d%d %02d:%02d day_evt=%s" % [
		CoreKit.clock.year(), CoreKit.clock.season_name(), CoreKit.clock.day(),
		CoreKit.clock.hour(), CoreKit.clock.minute(), day_evt["hit"]])

	# 物品背包 冒烟:溢出到多格 + move 交换(经 off-facade KitInventory)
	var bag := KitInventory.new(4, 99)
	bag.add(&"wood", 120)          # slot0=99 slot1=21
	bag.set_slot(3, &"stone", 5)
	bag.move(3, 1)                 # 异物交换:slot1=stone slot3=wood
	CoreKit.log.info("Inventory: wood=%d used=%d moved=%s" % [
		bag.count(&"wood"), bag.used_slots(), bag.slot(1).get("id") == &"stone"])

	# 数据表 冒烟:register 两条 + count/get_def(经 off-facade KitDataRegistry)
	var reg := KitDataRegistry.new()
	reg.register(&"crop", &"turnip", {"growth_days": 4})
	reg.register(&"crop", &"potato", {"growth_days": 6})
	CoreKit.log.info("DataRegistry: crops=%d turnip_ok=%s" % [
		reg.count(&"crop"), reg.get_def(&"crop", &"turnip") != null])

	# 内容包更新器 冒烟:相 A 查询 API(无网络,不触发下载/挂载/重启)——
	# 全新工程无已安装包,mounted/local_version 均为 0(经门面第 15 子系统)。
	# 刻意不调 restart_to_apply():非 headless 下它会 set_restart_on_exit+quit,副作用危险。
	CoreKit.log.info("PackUpdater: mounted=%d content_ver=%d errors=%d" % [
		CoreKit.updater.mounted_packs().size(),
		CoreKit.updater.local_version("content"),
		CoreKit.updater.mount_errors().size()])

	CoreKit.log.info("CoreKit v%s — all subsystems smoke-tested" % CoreKit.VERSION)


## 跨重启持久化探针(spike 专用,不进 main):每次启动把计数 +1 存回。
## 「本轮存回立读」验的是同会话往返(v0.24.3 修的就是这个);
## 「上次记录」验的是重启后还在不在——微信小游戏只有 /CustomWritablePath
## 下的路径才落磁盘,其余走 MEMFS 内存盘,一关就没。若反复重启永远读到 0,
## 说明 Godot 模板把 user:// 映射到了 MEMFS,那是另一个坑。
func _probe_persistence() -> void:
	var prev := CoreKit.saves.load("__persist__")
	var n := int(prev.get("launches", 0))
	CoreKit.saves.save("__persist__", {"launches": n + 1})
	var back := CoreKit.saves.load("__persist__")
	CoreKit.log.info("PROBE 持久化 上次记录=%d 本轮存回立读=%s (期望 launches=%d)" % [
		n, back, n + 1])


## 挂载探针(spike 专用,不进 main):`CoreKit.updater._mount_one` 在微信上唯一
## 没被验证过的假设就是 `ProjectSettings.load_resource_pack("user://…")`。
## 分三段,失败时能分辨是「造不出包」还是「挂不上包」:
##   ① ZIPPacker 能不能往 user:// 写出非空文件(load_resource_pack 也吃 zip)
##   ② GODOTSDK 能不能从 GDScript 摸到 + 该文件在微信 FS 里的真实路径
##   ③ load_resource_pack 挂上后,包内文件是否变成可读的 res:// 资源
func _probe_pack_mount() -> void:
	var zip_path := "user://probe_pack.zip"
	var packer := ZIPPacker.new()
	var open_err := packer.open(zip_path)
	if open_err != OK:
		CoreKit.log.info("PROBE 挂载 ① ZIPPacker.open 失败 err=%d — 造不出包,后两段跳过" % open_err)
		return
	packer.start_file("probe_mounted.txt")
	packer.write_file("hello-from-pack".to_utf8_buffer())
	packer.close_file()
	packer.close()
	var size := FileAccess.get_file_as_bytes(zip_path).size()
	CoreKit.log.info("PROBE 挂载 ① zip 落盘 size=%d (0 就是没真写进去)" % size)

	var sdk = JavaScriptBridge.get_interface("GODOTSDK") if OS.has_feature("web") else null
	var wx_path := ""
	if sdk != null:
		wx_path = str(sdk.getWxPath(zip_path))
	CoreKit.log.info("PROBE 挂载 ② GODOTSDK=%s wx 真实路径=%s" % [sdk != null, wx_path])

	var before := FileAccess.file_exists("res://probe_mounted.txt")
	var mounted := ProjectSettings.load_resource_pack(zip_path, true, 0)
	var after := FileAccess.file_exists("res://probe_mounted.txt")
	var content := FileAccess.get_file_as_string("res://probe_mounted.txt") if after else "<无>"
	CoreKit.log.info("PROBE 挂载 ③ load_resource_pack=%s before=%s after=%s content=%s" % [
		mounted, before, after, content])


## CDN 下载探针(spike 专用,不进 main):验 `CoreKit.updater` 的**下载段**在微信上
## 能否跑通 —— 挂载段已由 `_probe_pack_mount` 证过,check/download 这段是唯一空白。
## 素材由本机 `cdn/serve.py` 在 http://127.0.0.1:8099 上提供(manifest.json +
## probe_pack-v1.zip)。模拟器 `urlCheck:false` 不校验合法域名所以本地地址能通,
## **真机不成立**(要局域网 IP + 白名单 + 备案)。分四段:
##   ⓪ 引擎号与本地已装版本 —— manifest 的 engine 对不上 check 会直接失败,先打出来
##   ④ 先跑 mount_installed:上轮装过的话这轮该挂上,读到内容 = 端到端闭环
##   ① check → update_available / up_to_date / check_failed
##   ②③ download → downloaded → ready_to_apply + state.json
func _probe_cdn_download() -> void:
	var u = CoreKit.updater
	var info := Engine.get_version_info()
	CoreKit.log.info("PROBE CDN ⓪ 引擎=%d.%d 已装版本=%d" % [
		info.major, info.minor, u.local_version("cdnprobe")])

	u.mount_installed()
	var has := FileAccess.file_exists("res://probe_cdn.txt")
	CoreKit.log.info("PROBE CDN ④ 重启后 挂上=%s 内容=%s 挂载错误=%s" % [
		u.mounted_packs(),
		FileAccess.get_file_as_string("res://probe_cdn.txt") if has else "<无>",
		u.mount_errors()])

	u.check_failed.connect(_on_cdn_check_failed, CONNECT_ONE_SHOT)
	u.up_to_date.connect(_on_cdn_up_to_date, CONNECT_ONE_SHOT)
	u.update_available.connect(_on_cdn_update_available, CONNECT_ONE_SHOT)
	u.downloaded.connect(_on_cdn_downloaded, CONNECT_ONE_SHOT)
	u.download_failed.connect(_on_cdn_download_failed, CONNECT_ONE_SHOT)
	u.ready_to_apply.connect(_on_cdn_ready_to_apply, CONNECT_ONE_SHOT)

	await get_tree().process_frame  # HTTPRequest 须树跑起来后才发得出(否则 err=3)
	# filebrowser 的公开分享直链(局域网 IP,真机也够得着);/share/<hash> 是给人看的
	# 页面,机器下载要走 /api/public/dl/<hash>/<文件>。切回本地 py server 就改成
	# http://127.0.0.1:8099/manifest.json。
	u.check("http://172.25.50.135:8081/api/public/dl/5MwZWGEX/manifest.json")


func _on_cdn_check_failed(reason: String) -> void:
	CoreKit.log.info("PROBE CDN ① check_failed=%s" % reason)


func _on_cdn_up_to_date() -> void:
	CoreKit.log.info("PROBE CDN ① up_to_date —— 已装最新,本轮不下载")


func _on_cdn_update_available(plan: Dictionary) -> void:
	CoreKit.log.info("PROBE CDN ① update_available packs=%d" % plan["packs"].size())
	CoreKit.updater.download(plan)


func _on_cdn_downloaded(id: String) -> void:
	CoreKit.log.info("PROBE CDN ② downloaded id=%s" % id)


func _on_cdn_download_failed(id: String, reason: String) -> void:
	CoreKit.log.info("PROBE CDN ② download_failed id=%s reason=%s" % [id, reason])


func _on_cdn_ready_to_apply() -> void:
	var pack := "user://kit_updater/packs/cdnprobe-v%d.pck" % CoreKit.updater.local_version("cdnprobe")
	CoreKit.log.info("PROBE CDN ③ ready_to_apply 落盘包=%d 字节 state=%s" % [
		FileAccess.get_file_as_bytes(pack).size(),
		FileAccess.get_file_as_string("user://kit_updater/state.json")])
	# ③b 下完立刻挂 —— 验「标准 4.7 导出的 `.pck`(GDPC 头)微信定制运行时收不收」。
	# 这是 _probe_pack_mount 的 zip 验不到的独立风险(zip 无引擎头),且不必等下次启动:
	# 跨重启持久本身已由 ④ 段与 up_to_date 覆盖。
	CoreKit.updater.mount_installed()
	var has := FileAccess.file_exists("res://probe_cdn.txt")
	CoreKit.log.info("PROBE CDN ③b 本轮即挂 挂上=%s 内容=%s 错误=%s" % [
		CoreKit.updater.mounted_packs(),
		FileAccess.get_file_as_string("res://probe_cdn.txt") if has else "<无>",
		CoreKit.updater.mount_errors()])


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
