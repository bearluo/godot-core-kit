extends SceneTree
## 生产场景冒烟:加载 main.tscn 跑若干帧,断言无 SCRIPT ERROR
## 运行: godot --headless --path . -s res://test/test_crystal_line_smoke.gd

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
	await process_frame
	await process_frame

	# 驱动若干逻辑帧
	for i in 30:
		await process_frame

	# 经 sim 放塔+开波(直接访问脚本字段)
	if root_node.sim == null:
		print("FAIL 2: sim 未初始化")
		failures += 1
	else:
		root_node.sim.gold = 200
		root_node.sim.place_tower(1, 3, &"fire")
		root_node.sim.place_tower(3, 3, &"ice")
		root_node.sim.start_wave()
		for j in 60:
			await process_frame
		if root_node.sim.tower_count() < 2:
			print("FAIL 3: 放塔未生效 count=%d gold=%d event=%s" % [
				root_node.sim.tower_count(), root_node.sim.gold, root_node.sim.last_event])
			failures += 1
		print("smoke towers=%d enemies=%d wave=%d gold=%d source_art=%s source_sfx=%s" % [
			root_node.sim.tower_count(),
			root_node.sim.enemy_count(),
			root_node.sim.wave,
			root_node.sim.gold,
			root_node.art.source_for(&"tower_fire"),
			root_node.sfx.source_for(&"place"),
		])

	if root_node.art == null or root_node.sfx == null:
		print("FAIL 4: bank 未初始化")
		failures += 1

	root_node.queue_free()
	await process_frame

	if failures == 0:
		print("test_crystal_line_smoke: ALL PASS")
		quit(0)
	else:
		print("test_crystal_line_smoke: %d FAILURE(S)" % failures)
		quit(1)
