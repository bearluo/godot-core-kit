extends SceneTree
## KitTransition 纯逻辑 headless 断言(默认值 / is_none / normalized 夹取+副本 / SLIDE 四向几何)。
## KitTransition 零依赖,直接 load() 脚本实例化,不碰场景树、不经门面。
## 运行:godot --headless --path . -s res://test/test_transition.gd

var TransitionScript


func _initialize() -> void:
	TransitionScript = load("res://addons/godot-core-kit/transitions/kit_transition.gd")
	var failures := 0

	# 1. 默认值
	var t = TransitionScript.new()
	if t.type != TransitionScript.Type.FADE:
		print("FAIL 1: 默认 type 应为 FADE,得到 %s" % t.type)
		failures += 1
	if t.duration != 0.3:
		print("FAIL 1: 默认 duration 应为 0.3,得到 %s" % t.duration)
		failures += 1
	if t.color != Color.BLACK:
		print("FAIL 1: 默认 color 应为 BLACK")
		failures += 1
	if t.direction != TransitionScript.Dir.LEFT:
		print("FAIL 1: 默认 direction 应为 LEFT")
		failures += 1
	if t.ease_type != Tween.EASE_IN_OUT:
		print("FAIL 1: 默认 ease_type 应为 EASE_IN_OUT")
		failures += 1
	if t.trans_type != Tween.TRANS_LINEAR:
		print("FAIL 1: 默认 trans_type 应为 TRANS_LINEAR")
		failures += 1

	# 2. is_none
	if t.is_none():
		print("FAIL 2: FADE 实例 is_none() 应为 false")
		failures += 1
	var none_t = TransitionScript.new()
	none_t.type = TransitionScript.Type.NONE
	if not none_t.is_none():
		print("FAIL 2: NONE 实例 is_none() 应为 true")
		failures += 1

	# 3. normalized 夹取 + 副本不改原
	var bad = TransitionScript.new()
	bad.duration = -5.0
	bad.type = 999
	var fixed = bad.normalized()
	if fixed.duration != 0.0:
		print("FAIL 3: normalized duration 应夹到 0.0,得到 %s" % fixed.duration)
		failures += 1
	if fixed.type != TransitionScript.Type.FADE:
		print("FAIL 3: normalized 越界 type 应回 FADE,得到 %s" % fixed.type)
		failures += 1
	if bad.duration != -5.0:
		print("FAIL 3: normalized 不应改原实例 duration(应仍 -5.0,得到 %s)" % bad.duration)
		failures += 1

	# 4. SLIDE 四向几何(size=800x600)
	var size := Vector2(800, 600)
	var s = TransitionScript.new()
	s.type = TransitionScript.Type.SLIDE
	var cases := {
		TransitionScript.Dir.LEFT:  [Vector2(800, 0), Vector2(-800, 0)],
		TransitionScript.Dir.RIGHT: [Vector2(-800, 0), Vector2(800, 0)],
		TransitionScript.Dir.UP:    [Vector2(0, 600), Vector2(0, -600)],
		TransitionScript.Dir.DOWN:  [Vector2(0, -600), Vector2(0, 600)],
	}
	for dir in cases:
		s.direction = dir
		var expect = cases[dir]
		if s.slide_cover_from(size) != expect[0]:
			print("FAIL 4: dir=%s cover_from 应 %s,得到 %s" % [dir, expect[0], s.slide_cover_from(size)])
			failures += 1
		if s.slide_reveal_to(size) != expect[1]:
			print("FAIL 4: dir=%s reveal_to 应 %s,得到 %s" % [dir, expect[1], s.slide_reveal_to(size)])
			failures += 1

	if failures == 0:
		print("test_transition: ALL PASS")
		quit(0)
	else:
		print("test_transition: %d FAILURE(S)" % failures)
		quit(1)
