extends SceneTree
## FortuneSoundBank 程序化音效接缝 headless 断言。
## 运行:godot --headless --path . -s res://test/test_fortune_sound_bank.gd
## 重点:① 每个动作 key 合成非空 AudioStream 且时长 > 0 ② 缓存返回同一实例
##       ③ 不同 voice 参数 → 时长不同(音效可辨识) ④ asset_path_wav/ogg 指向 drop-in 接缝
##       ⑤ 仓库未投放真音频 → source_for=procedural(兜底路径) ⑥ 未登记 key 用默认 voice 兜底。
## FortuneSoundBank 为 example 本地类、不引用门面,可顶层 preload(同 FortuneArtBank/Currency)。
const FortuneSoundBank := preload("res://examples/fortune-mill/sfx/sound_bank.gd")


func _initialize() -> void:
	var failures := 0
	var sb = FortuneSoundBank.new()

	# 1. 每个动作 key 合成非空 AudioStream,时长 > 0
	var keys := [&"throw", &"scratch", &"pull", &"drop", &"jackpot", &"clear"]
	for k in keys:
		var s = sb.stream_for(k)
		if s == null or not (s is AudioStream):
			print("FAIL 1: stream_for(%s) 应返回 AudioStream" % k); failures += 1
		elif s.get_length() <= 0.0:
			print("FAIL 1: stream_for(%s) 时长应 > 0,得 %.4f" % [k, s.get_length()]); failures += 1

	# 2. 缓存:同 key 返回同一实例
	if sb.stream_for(&"throw") != sb.stream_for(&"throw"):
		print("FAIL 2: 同 key 应命中缓存返回同一实例"); failures += 1

	# 3. 不同 voice → 时长不同(jackpot 琶音明显长于 throw 短 blip)
	if sb.stream_for(&"jackpot").get_length() <= sb.stream_for(&"throw").get_length():
		print("FAIL 3: jackpot 应比 throw 长(音效可辨识)"); failures += 1

	# 4. asset_path 指向 drop-in 接缝:assets/<key>.wav|.ogg
	if sb.asset_path_wav(&"throw") != "res://examples/fortune-mill/assets/throw.wav":
		print("FAIL 4: asset_path_wav 应指向 assets/<key>.wav,得 %s" % sb.asset_path_wav(&"throw")); failures += 1
	if sb.asset_path_ogg(&"throw") != "res://examples/fortune-mill/assets/throw.ogg":
		print("FAIL 4: asset_path_ogg 应指向 assets/<key>.ogg,得 %s" % sb.asset_path_ogg(&"throw")); failures += 1

	# 5. 仓库未投放真音频 → 全部走程序化兜底
	if sb.source_for(&"throw") != "procedural":
		print("FAIL 5: 无真音频时 source_for 应为 procedural"); failures += 1

	# 6. 未登记 key 用默认 voice 兜底(不崩,仍出音)
	var fb = sb.stream_for(&"__unknown__")
	if fb == null or fb.get_length() <= 0.0:
		print("FAIL 6: 未登记 key 应仍合成默认 voice 兜底音"); failures += 1

	if failures == 0:
		print("test_fortune_sound_bank: ALL PASS")
		quit(0)
	else:
		print("test_fortune_sound_bank: %d FAILURE(S)" % failures)
		quit(1)
