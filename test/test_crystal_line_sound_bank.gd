extends SceneTree
## CrystalSoundBank 三级接缝 + bake 契约
## 运行: godot --headless --path . -s res://test/test_crystal_line_sound_bank.gd

func _initialize() -> void:
	var failures := 0
	var Bank = load("res://game/crystal_line/sfx/sound_bank.gd")
	var bank = Bank.new()

	var keys: Array = bank.bake_keys()
	if keys.is_empty():
		print("FAIL 1: bake_keys 空")
		failures += 1

	for k in keys:
		var s: AudioStreamWAV = bank.bake_stream(k)
		if s == null or s.data.is_empty():
			print("FAIL 2: bake_stream 空 key=%s" % k)
			failures += 1
			continue
		if s.mix_rate != 22050:
			print("FAIL 2b: mix_rate key=%s" % k)
			failures += 1

	var stream: AudioStream = bank.stream_for(&"place")
	if stream == null:
		print("FAIL 3: stream_for place null")
		failures += 1

	var src: String = bank.source_for(&"place")
	if src != "baked" and src != "procedural" and src != "asset":
		print("FAIL 4: source_for 非法 %s" % src)
		failures += 1
	print("source place=%s" % src)

	var b: Dictionary = bank.brief(&"clear")
	if not b.has("prompt") or str(b["prompt"]).is_empty():
		print("FAIL 5: brief 缺 prompt")
		failures += 1

	# 核心瞬间相关 key 必须在 VOICES
	for need in [&"place", &"clear", &"leak"]:
		if not keys.has(need):
			print("FAIL 6: 缺核心 key %s" % need)
			failures += 1

	if failures == 0:
		print("test_crystal_line_sound_bank: ALL PASS")
		quit(0)
	else:
		print("test_crystal_line_sound_bank: %d FAILURE(S)" % failures)
		quit(1)
