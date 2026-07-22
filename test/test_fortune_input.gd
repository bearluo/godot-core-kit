extends SceneTree
## FortuneDartsInput 纯输入映射断言(不含节点/事件)。运行:-s res://test/test_fortune_input.gd
## 注:darts_input.gd 引用 CoreKit.settings(detect_mode),故用运行时 load() 而非顶层 preload
## (顶层 preload 在 autoload 注册前编译会撞 CoreKit 未声明——本仓库血泪坑)。

func _initialize() -> void:
	var DI = load("res://examples/fortune-mill/scenes/darts_input.gd")
	if DI == null:
		print("test_fortune_input: FAIL (script missing)"); quit(1); return
	var failures := 0

	# 1. desktop_aim:鼠标顶端→0、底端→1、中间→0.5
	if absf(DI.desktop_aim(0.0, 600.0) - 0.0) > 0.001 or absf(DI.desktop_aim(600.0, 600.0) - 1.0) > 0.001 or absf(DI.desktop_aim(300.0, 600.0) - 0.5) > 0.001:
		print("FAIL 1: desktop_aim 边界/中点"); failures += 1

	# 2. desktop_power:三角摆动在 [0,1],甜点附近达峰
	var p: float = DI.desktop_power(0.0, 0.6)
	if p < 0.0 or p > 1.0:
		print("FAIL 2: desktop_power 应在 [0,1]"); failures += 1

	# 3. touch:向左上拖 → 反方向(右下)=方向;拖越长 power 越大
	var short: float = DI.touch_power(Vector2(-40, 0), 200.0)
	var long: float = DI.touch_power(Vector2(-160, 0), 200.0)
	if not (long > short and long <= 1.0 and short >= 0.0):
		print("FAIL 3: touch_power 应随拖长单调升且封顶 1"); failures += 1

	# 4. touch_aim:纯水平拖 aim≈0.5(无纵向分量);向下拖 aim 增
	var a_mid: float = DI.touch_aim(Vector2(-100, 0))
	var a_dn: float = DI.touch_aim(Vector2(-100, 80))
	if absf(a_mid - 0.5) > 0.05 or not (a_dn > a_mid):
		print("FAIL 4: touch_aim 纵向映射"); failures += 1

	if failures == 0:
		print("test_fortune_input: ALL PASS"); quit(0)
	else:
		print("test_fortune_input: %d FAILURE(S)" % failures); quit(1)
