extends SceneTree
## CoreKit 门面接线 headless 断言测试——测的就是 autoload 接线本身,
## 因此例外地直接使用 /root/CoreKit(与其余测试"直接实例化脚本"的模式不同)。
## 运行:godot --headless --path . -s res://test/test_core_kit.gd
##
## 环境坑(与 test_state_machine.gd / test_audio_manager.gd 一致):-s 自定义
## SceneTree 脚本的 _initialize() 在主循环开始前执行,此时 root 尚未真正"入树",
## CoreKit 自身已在 _init 中构造好全部子节点(属性/子节点顺序此刻已就绪),但
## CoreKit._ready()(bind_settings/bind_ticker 接线发生处)要等主循环跑起来才
## 触发,故须先 await 一帧,再做接线断言。


func _initialize() -> void:
	var failures := 0
	var kit = root.get_node_or_null("CoreKit")
	if kit == null:
		print("FAIL 0: /root/CoreKit autoload 缺失")
		print("test_core_kit: 1 FAILURE(S)")
		quit(1)
		return

	await process_frame  # 补一帧,让 CoreKit._ready() 的 bind_* 接线跑完

	# 1. 版本
	if kit.VERSION != "0.24.1":
		print("FAIL 1: VERSION 应为 0.24.1,实际 %s" % kit.VERSION)
		failures += 1

	# 2. 十四个门面属性非 null 且脚本路径正确
	var expected := [
		["log", "res://addons/godot-core-kit/core/log.gd"],
		["settings", "res://addons/godot-core-kit/core/settings.gd"],
		["bus", "res://addons/godot-core-kit/core/event_bus.gd"],
		["scenes", "res://addons/godot-core-kit/systems/scene_manager.gd"],
		["pool", "res://addons/godot-core-kit/systems/object_pool.gd"],
		["saves", "res://addons/godot-core-kit/systems/save_manager.gd"],
		["ticker", "res://addons/godot-core-kit/systems/frame_scheduler.gd"],
		["input", "res://addons/godot-core-kit/systems/input_manager.gd"],
		["audio", "res://addons/godot-core-kit/systems/audio_manager.gd"],
		["res", "res://addons/godot-core-kit/systems/resource_manager.gd"],
		["console", "res://addons/godot-core-kit/console/dev_console.gd"],
		["i18n", "res://addons/godot-core-kit/systems/locale_manager.gd"],
		["layers", "res://addons/godot-core-kit/systems/layer_manager.gd"],
		["clock", "res://addons/godot-core-kit/systems/game_clock.gd"],
		["updater", "res://addons/godot-core-kit/systems/pack_updater.gd"],
	]
	for pair in expected:
		var sub = kit.get(pair[0])
		if sub == null:
			print("FAIL 2: CoreKit.%s 为 null" % pair[0])
			failures += 1
			continue
		var script: Resource = sub.get_script()
		if script == null or script.resource_path != pair[1]:
			print("FAIL 2: CoreKit.%s 的脚本不是 %s" % [pair[0], pair[1]])
			failures += 1

	# 3. 子节点顺序 = 构造顺序(_ready 触发序可复现)
	var order := ["Log", "Settings", "EventBus", "SceneManager", "ObjectPool",
		"SaveManager", "FrameScheduler", "InputManager", "AudioManager", "ResourceManager", "DevConsole", "LocaleManager", "LayerManager", "GameClock", "PackUpdater"]
	if kit.get_child_count() != order.size():
		print("FAIL 3: 子节点数应为 %d,实际 %d" % [order.size(), kit.get_child_count()])
		failures += 1
	else:
		for i in order.size():
			if String(kit.get_child(i).name) != order[i]:
				print("FAIL 3: 第 %d 个子节点应为 %s,实际 %s" % [i, order[i], kit.get_child(i).name])
				failures += 1

	# 4. 接线:bind_settings / bind_ticker 已生效
	if kit.input._settings != kit.settings:
		print("FAIL 4: input 未绑定 settings")
		failures += 1
	if kit.audio._settings != kit.settings:
		print("FAIL 4: audio 未绑定 settings")
		failures += 1
	if kit.res._ticker != kit.ticker:
		print("FAIL 4: res 未绑定 ticker")
		failures += 1
	if kit.clock._bus != kit.bus:
		print("FAIL 4: clock 未绑定 bus")
		failures += 1

	# 5. 老 API 经门面冒烟
	var box := {"payload": null}
	kit.bus.subscribe("__facade_smoke__", func(payload) -> void: box["payload"] = payload)
	kit.bus.publish("__facade_smoke__", 42)
	if box["payload"] != 42:
		print("FAIL 5: EventBus 经门面发布订阅失败")
		failures += 1
	if kit.saves.has_slot("__facade_smoke_nonexistent__"):
		print("FAIL 5: SaveManager 经门面调用失败(不存在的 slot 应 has_slot=false)")
		failures += 1

	# 6. 全局根:内置已按 key 预注册 + provide/service/has/service_or 冒烟
	var builtin_keys := ["log", "settings", "bus", "scenes", "pool", "saves",
		"ticker", "input", "audio", "res", "console", "i18n", "layers", "clock", "updater"]
	for k in builtin_keys:
		if kit.service(k) != kit.get(k):
			print("FAIL 6: CoreKit.service('%s') 未指向内置子系统" % k)
			failures += 1
	if not kit.has("audio"):
		print("FAIL 6: has('audio') 应为 true")
		failures += 1
	kit.provide("audio", 999)  # 保留键:应被拒,audio 仍指向内置
	if kit.service("audio") != kit.audio:
		print("FAIL 6: 保留键 audio 不应被 provide 覆盖")
		failures += 1
	kit.provide("layers", 1)  # 保留键:应被拒
	if kit.service("layers") != kit.layers:
		print("FAIL 6: 保留键 layers 不应被 provide 覆盖")
		failures += 1
	kit.provide("clock", 1)  # 保留键:应被拒
	if kit.service("clock") != kit.clock:
		print("FAIL 6: 保留键 clock 不应被 provide 覆盖")
		failures += 1
	kit.provide("__facade_custom__", 55)
	if kit.service("__facade_custom__") != 55:
		print("FAIL 6: 全局 provide/service 冒烟失败")
		failures += 1
	kit.provide("__facade_custom__", 66)  # 重复键:应覆盖为新值(并告警)
	if kit.service("__facade_custom__") != 66:
		print("FAIL 6: 重复 key 应覆盖为新值")
		failures += 1
	if kit.service_or("__facade_absent__", -1) != -1:
		print("FAIL 6: service_or 应返回 fallback")
		failures += 1

	if failures == 0:
		print("test_core_kit: ALL PASS")
		quit(0)
	else:
		print("test_core_kit: %d FAILURE(S)" % failures)
		quit(1)
