extends SceneTree
## SceneManager 纯接缝 headless 断言测试（不依赖 autoload，直接实例化脚本）。
## 覆盖 _validate_target / _resolve_target_path / _merge_options / is_changing。
## change_scene() 本体（协程、动场景树、fade）不在本文件断言范围内 —— 那需要一棵运行中
## 的场景树和真实可切换场景，属后续集成步骤的 demo 冒烟验证范畴。
## 运行：godot --headless -s res://test/test_scene_manager.gd
##
## 注：用运行时 load()（而非顶层 const preload()）取得 scene_manager.gd / demo.tscn。
## 原因：headless -s 执行时，-s 主脚本自身及其编译期 preload 依赖图，会在 SceneTree
## 把 autoload 注册为脚本全局标识符之前就被整体编译；scene_manager.gd 的 change_scene()
## 函数体内引用了全局标识符 CoreKit（即使本文件从不调用到该分支），静态分析仍会在编译期报
## "Identifier not found: CoreKit" 导致 preload 链失败。改为在 _initialize() 内用运行时
## load()（此时 autoload 已注册完毕）规避这一引擎时序限制；断言内容、顺序不变。

func _initialize() -> void:
	var failures := 0
	var SceneManagerScript = load("res://addons/godot-core-kit/systems/scene_manager.gd")
	var sm = SceneManagerScript.new()  # 裸 .new()，不 add_child，_ready() 不会跑

	# 1. _validate_target：真实存在的 .tscn 路径 → OK
	if sm._validate_target("res://demo/demo.tscn") != OK:
		print("FAIL _validate_target 应接受 res://demo/demo.tscn")
		failures += 1

	# 2. _validate_target：扩展名不对 → 非 OK
	if sm._validate_target("res://demo/demo.gd") == OK:
		print("FAIL _validate_target 应拒绝 res://demo/demo.gd(扩展名不对)")
		failures += 1

	# 3. _validate_target：空字符串 → 非 OK
	if sm._validate_target("") == OK:
		print("FAIL _validate_target 应拒绝空字符串")
		failures += 1

	# 4. _validate_target：非 res:// 开头 → 非 OK
	if sm._validate_target("user://x.tscn") == OK:
		print("FAIL _validate_target 应拒绝 user://x.tscn(非 res:// 开头)")
		failures += 1

	# 5. _validate_target：类型不对（int）→ 非 OK
	if sm._validate_target(123) == OK:
		print("FAIL _validate_target 应拒绝类型不对的 123")
		failures += 1

	# 6. _validate_target：真实 PackedScene → OK
	if sm._validate_target(load("res://demo/demo.tscn")) != OK:
		print("FAIL _validate_target 应接受真实 PackedScene")
		failures += 1

	# 7. _resolve_target_path：String 原样返回
	if sm._resolve_target_path("res://a.tscn") != "res://a.tscn":
		print("FAIL _resolve_target_path(String) 应原样返回")
		failures += 1

	# 8. _resolve_target_path：PackedScene 返回 resource_path
	var path: String = sm._resolve_target_path(load("res://demo/demo.tscn"))
	if path != "res://demo/demo.tscn":
		print("FAIL _resolve_target_path(PackedScene) 得到 '%s'" % path)
		failures += 1

	# 9. _merge_options({})：全部回退默认值
	var opts: Dictionary = sm._merge_options({})
	if opts["transition"] != SceneManagerScript.Transition.NONE:
		print("FAIL _merge_options({}) transition 应为 NONE")
		failures += 1
	if opts["duration"] != 0.3:
		print("FAIL _merge_options({}) duration 应为 0.3，得到 %s" % str(opts["duration"]))
		failures += 1
	if opts["color"] != Color.BLACK:
		print("FAIL _merge_options({}) color 应为 Color.BLACK")
		failures += 1

	# 10. _merge_options：合法 transition/duration 按传入值，color 回退默认
	var opts2: Dictionary = sm._merge_options({
		"transition": SceneManagerScript.Transition.FADE,
		"duration": 1.5,
	})
	if opts2["transition"] != SceneManagerScript.Transition.FADE:
		print("FAIL _merge_options transition 应保留传入的 FADE")
		failures += 1
	if opts2["duration"] != 1.5:
		print("FAIL _merge_options duration 应保留传入的 1.5")
		failures += 1
	if opts2["color"] != Color.BLACK:
		print("FAIL _merge_options 未传 color 时应回退默认黑色")
		failures += 1

	# 11. _merge_options：duration 负数夹到 0.0
	var opts3: Dictionary = sm._merge_options({"duration": -1})
	if opts3["duration"] != 0.0:
		print("FAIL _merge_options duration=-1 应夹到 0.0，得到 %s" % str(opts3["duration"]))
		failures += 1

	# 12. _merge_options：transition 超出枚举范围回退 NONE
	var opts4: Dictionary = sm._merge_options({"transition": 999})
	if opts4["transition"] != SceneManagerScript.Transition.NONE:
		print("FAIL _merge_options transition=999 应回退 NONE")
		failures += 1

	# 13. is_changing()：新实例默认 false
	if sm.is_changing():
		print("FAIL 新实例 is_changing() 应为 false")
		failures += 1

	sm.free()

	if failures == 0:
		print("test_scene_manager: ALL PASS")
		quit(0)
	else:
		print("test_scene_manager: %d FAILURE(S)" % failures)
		quit(1)
