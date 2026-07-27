extends SceneTree
## 生产场景冒烟:加载 main.tscn 跑真实帧,断言场景层接线成立
## 运行: godot --headless --path . -s res://test/test_crystal_line_smoke.gd
##
## 除原有「能实例化 + 能放塔 + 无脚本错误」外,R1 追加:
##   CL-004  hit 音效在真实游戏流程里被播放(不是 bake_keys 里的死资源)
##   CL-006  音效经 CoreKit.audio;跨局进度经 CoreKit.saves 落盘

func _initialize() -> void:
	var failures := 0
	await process_frame

	var packed: PackedScene = load("res://game/crystal_line/main.tscn")
	if packed == null:
		print("FAIL 1: 无法 load main.tscn")
		print("test_crystal_line_smoke: 1 FAILURE(S)")
		quit(1)
		return

	var root_node = packed.instantiate()
	root.add_child(root_node)
	for _i in 5:
		await process_frame

	if root_node.sim == null or root_node.art == null or root_node.sfx == null:
		print("FAIL 2: sim/art/sfx 未初始化")
		print("test_crystal_line_smoke: 1 FAILURE(S)")
		quit(1)
		return

	# CL-006: 音效路由到 CoreKit.audio
	if root_node.sfx_route != "corekit":
		print("FAIL 3: 音效未经 CoreKit.audio route=%s" % root_node.sfx_route)
		failures += 1

	# 玩家动作:选塔(ui 音)→ 放塔(place 音)→ 开波
	root_node._select(&"fire")
	root_node.sim.gold = 300
	root_node._try_place(Vector2i(1, 0))   # 紧贴入口,开波即可交火
	root_node._try_place(Vector2i(2, 2))
	root_node._on_wave()
	for _j in 90:
		await process_frame

	if root_node.sim.tower_count() < 2:
		print("FAIL 4: 放塔未生效 count=%d gold=%d event=%s" % [
			root_node.sim.tower_count(), root_node.sim.gold, root_node.sim.last_event])
		failures += 1
	if root_node.sim.hits <= 0:
		print("FAIL 5: 真实帧内塔未开火 hits=%d enemies=%d" % [
			root_node.sim.hits, root_node.sim.enemy_count()])
		failures += 1
	for key in ["ui", "place", "hit"]:
		if not root_node.sfx_plays.has(StringName(key)):
			print("FAIL 6: 音效 %s 在流程中从未播放 plays=%s" % [key, root_node.sfx_plays])
			failures += 1
	# hit 必须仍在烘焙清单里(接缝完整),且确实被用到
	if not root_node.sfx.bake_keys().has(&"hit"):
		print("FAIL 7: sound_bank 缺少 hit 键")
		failures += 1

	print("smoke towers=%d enemies=%d wave=%d gold=%d hits=%d sfx=%s route=%s art=%s" % [
		root_node.sim.tower_count(), root_node.sim.enemy_count(), root_node.sim.wave,
		root_node.sim.gold, root_node.sim.hits, root_node.sfx_plays, root_node.sfx_route,
		root_node.art.source_for(&"tower_fire")])

	# CL-003/CL-006: 推到局终 → 结算面板弹出 → 跨局进度经 CoreKit.saves 落盘
	var guard := 0
	while not root_node.sim.is_round_over() and guard < 20000:
		root_node.sim.tick(0.05)
		guard += 1
	for _k in 4:
		await process_frame
	if not root_node.get_node("Result").visible:
		print("FAIL 8: 局终未弹出结算面板")
		failures += 1
	var kit = root.get_node_or_null("CoreKit")
	if kit == null or kit.saves == null:
		print("FAIL 9: CoreKit.saves 不可用")
		failures += 1
	elif not kit.saves.has_slot("crystal_line"):
		print("FAIL 9b: 跨局进度未经 CoreKit.saves 落盘")
		failures += 1
	else:
		var rec: Dictionary = kit.saves.load("crystal_line")
		if int(rec.get("plays", 0)) < 1 or not rec.has("best_wave"):
			print("FAIL 9c: 存档内容不对 %s" % rec)
			failures += 1
		else:
			print("smoke record=%s" % rec)

	root_node.queue_free()
	await process_frame

	if failures == 0:
		print("test_crystal_line_smoke: ALL PASS")
		quit(0)
	else:
		print("test_crystal_line_smoke: %d FAILURE(S)" % failures)
		quit(1)
