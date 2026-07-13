extends SceneTree
## LayerManager headless 断言。管理器入树(root.add_child + await frame)后
## 懒建/取具名 CanvasLayer、mount/clear/register_layer。零依赖,直接 load() 实例化。
## 运行:godot --headless --path . -s res://test/test_layer_manager.gd

var LayerScript


func _initialize() -> void:
	LayerScript = load("res://addons/godot-core-kit/systems/layer_manager.gd")
	var failures := 0

	var lm = LayerScript.new()
	root.add_child(lm)
	await process_frame

	# 1. 懒建 + 缓存 + z 值
	var hud = lm.layer("hud")
	if hud == null or not (hud is CanvasLayer) or hud.layer != 10:
		print("FAIL 1: layer('hud') 应是 layer=10 的 CanvasLayer"); failures += 1
	if lm.layer("hud") != hud:
		print("FAIL 1: 二次 layer('hud') 应返回同一实例(缓存)"); failures += 1
	if lm.layer("modal").layer != 40 or lm.layer("background").layer != -10:
		print("FAIL 1: modal 应 40、background 应 -10"); failures += 1

	# 2. 内置 z 序常量
	if lm.HUD != 10 or lm.WINDOW != 20 or lm.POPUP != 30 or lm.MODAL != 40 or lm.NOTIFY != 50 or lm.SYSTEM != 60 or lm.BACKGROUND != -10:
		print("FAIL 2: 内置 z 常量不符"); failures += 1

	# 3. 保留带常量 + 不创建
	if lm.CONSOLE != 128 or lm.TRANSITION != 4096:
		print("FAIL 3: 保留带常量应 CONSOLE=128 TRANSITION=4096"); failures += 1
	if lm.has_layer("console") or lm.has_layer("transition"):
		print("FAIL 3: 管理器不应登记 console/transition"); failures += 1
	if lm.layer("console") != null:
		print("FAIL 3: layer('console') 未知名应 null"); failures += 1

	# 4. mount 搬入 + 摘旧父
	var tmp := Node.new()
	root.add_child(tmp)
	var n := Control.new()
	tmp.add_child(n)
	lm.mount(n, "popup")
	if n.get_parent() != lm.layer("popup") or tmp.get_child_count() != 0:
		print("FAIL 4: mount 应把 n 从旧父搬进 popup 层"); failures += 1
	tmp.free()

	# 5. clear
	lm.mount(Control.new(), "notify")
	lm.mount(Control.new(), "notify")
	lm.clear("notify")
	await process_frame
	if lm.layer("notify").get_child_count() != 0:
		print("FAIL 5: clear 应清空 notify 层"); failures += 1

	# 6. register_layer + 懒建
	lm.register_layer("weather", -5)
	if not lm.has_layer("weather") or lm.layer("weather").layer != -5:
		print("FAIL 6: register_layer('weather',-5) 后应可建 layer=-5"); failures += 1

	# 7. register 重名拒
	lm.register_layer("hud", 999)
	if lm.layer("hud").layer != 10:
		print("FAIL 7: 重名 register 应被拒,hud 仍 10"); failures += 1

	# 8. 层挂在管理器下(常驻结构佐证)
	if lm.layer("hud").get_parent() != lm:
		print("FAIL 8: 具名层应是 LayerManager 的子节点"); failures += 1

	lm.free()

	if failures == 0:
		print("test_layer_manager: ALL PASS")
		quit(0)
	else:
		print("test_layer_manager: %d FAILURE(S)" % failures)
		quit(1)
