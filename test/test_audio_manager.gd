extends SceneTree
## AudioManager headless 断言测试。headless 下 AudioServer 可正常建总线/设
## 音量;play 不出声但 playing/stream 状态可断言。create_tween 需在树内 →
## 实例 add_child 到 root(触发 _ready:建总线 + 建播放器)。
## 淡切只断言结构与终态指向(交叉期双 playing、kill 旧 Tween 不崩),帧级
## 中间态与听感留给 demo 冒烟。
## 运行:godot --headless --path . -s res://test/test_audio_manager.gd
##
## 加载注:audio_manager.gd 运行期引用全局 autoload 标识符 CoreKit,故不在
## 类作用域 preload,延迟到 _initialize() 内 load()。音源用 AudioStreamGenerator
## (无限长,不会自动播完,适合断言 playing 状态)。

var AudioManagerScript
var SettingsScript

const SETTINGS_PATH := "user://__test_audio_settings__.json"


func _initialize() -> void:
	AudioManagerScript = load("res://addons/godot-core-kit/audio_manager.gd")
	SettingsScript = load("res://addons/godot-core-kit/settings.gd")
	var failures := 0

	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)

	var am = AudioManagerScript.new()
	am.sfx_pool_size = 2  # 入树前设置,_ready 按此建池
	# 入树前设置独立总线名,与 CoreKit.audio 的全局 Music/SFX 总线隔离,避免
	# 两个 AudioManager 共用总线图上的播放器/Tween,在进程退出时发生 teardown 竞态。
	am.bus_music = "TestMusic"
	am.bus_sfx = "TestSFX"
	root.add_child(am)    # 触发 _ready:建总线 + 2 音乐播放器 + 2 SFX 播放器
	# 环境坑(与 test_state_machine.gd 一致):_initialize() 期间 root 尚未真正
	# "入树",root.add_child() 不会同步触发子树的 NOTIFICATION_READY,须补一帧。
	await process_frame

	# 1. Music/SFX 总线存在且 send 到 Master;重复 _ensure_bus 不重复创建
	var music_idx := AudioServer.get_bus_index("TestMusic")
	var sfx_idx := AudioServer.get_bus_index("TestSFX")
	if music_idx == -1 or sfx_idx == -1:
		print("FAIL 1: Music/SFX 总线应被创建")
		failures += 1
	if AudioServer.get_bus_send(music_idx) != &"Master" or AudioServer.get_bus_send(sfx_idx) != &"Master":
		print("FAIL 1: 新建总线应 send 到 Master")
		failures += 1
	var bus_count_before := AudioServer.bus_count
	am._ensure_bus("TestMusic")
	am._ensure_bus("TestSFX")
	if AudioServer.bus_count != bus_count_before:
		print("FAIL 1: 已存在的总线不应重复创建")
		failures += 1

	# 2. _bus_key_to_index / get_volume 未知 key
	if am._bus_key_to_index("master") != AudioServer.get_bus_index("Master"):
		print("FAIL 2: master 应映射到 Master 总线")
		failures += 1
	if am._bus_key_to_index("music") != music_idx or am._bus_key_to_index("sfx") != sfx_idx:
		print("FAIL 2: music/sfx 映射不正确")
		failures += 1
	if am._bus_key_to_index("alien") != -1:
		print("FAIL 2: 未知 key 应返回 -1")
		failures += 1
	if am.get_volume("alien") != 1.0:
		print("FAIL 2: 未知 key 的 get_volume 应返回 1.0")
		failures += 1

	# 3. set_volume 写 AudioServer + clamp;get_volume 往返
	am.set_volume("music", 0.5)
	if not is_equal_approx(AudioServer.get_bus_volume_db(music_idx), linear_to_db(0.5)):
		print("FAIL 3: set_volume 应写入 linear_to_db(0.5)")
		failures += 1
	if not is_equal_approx(am.get_volume("music"), 0.5):
		print("FAIL 3: get_volume 往返失败,得到 %f" % am.get_volume("music"))
		failures += 1
	am.set_volume("music", 1.5)  # clamp 到 1.0
	if not is_equal_approx(am.get_volume("music"), 1.0):
		print("FAIL 3: 超上限应 clamp 到 1.0")
		failures += 1
	am.set_volume("music", -0.5)  # clamp 到 0.0(即 -inf dB → 线性 0)
	if am.get_volume("music") > 0.0001:
		print("FAIL 3: 低于下限应 clamp 到 0.0")
		failures += 1

	# 4. 持久化:set_volume 写 settings;新实例 bind 后恢复到 AudioServer
	var settings = SettingsScript.new()
	settings.settings_path = SETTINGS_PATH
	am.bind_settings(settings)
	am.set_volume("sfx", 0.25)
	if settings.get_value("audio", "sfx") != 0.25:
		print("FAIL 4: set_volume 应写透 settings,得到 %s" % [settings.get_value("audio", "sfx")])
		failures += 1
	AudioServer.set_bus_volume_db(sfx_idx, 0.0)  # 模拟新会话:总线音量回默认
	var am2 = AudioManagerScript.new()  # 不入树:bind_settings 不依赖 _ready
	am2.bus_music = "TestMusic"  # 不入树不会经过 _ready,但为与 am 隔离一致仍显式设置
	am2.bus_sfx = "TestSFX"
	am2.bind_settings(settings)
	if not is_equal_approx(AudioServer.get_bus_volume_db(sfx_idx), linear_to_db(0.25)):
		print("FAIL 4: bind_settings 应恢复音量到 AudioServer")
		failures += 1
	am2.free()

	# 5. play_music 硬切:active 播放、信号、同 stream 空操作
	var stream_a := AudioStreamGenerator.new()
	var stream_b := AudioStreamGenerator.new()
	var music_events := []
	am.music_changed.connect(func(stream) -> void: music_events.append(stream))
	am.play_music(stream_a)
	if am._active_music == null or am._active_music.stream != stream_a or not am._active_music.playing:
		print("FAIL 5: 硬切后 active 应在播 stream_a")
		failures += 1
	if music_events != [stream_a]:
		print("FAIL 5: music_changed 应广播一次")
		failures += 1
	am.play_music(stream_a)  # 同 stream:空操作,不重发信号
	if music_events.size() != 1:
		print("FAIL 5: 同 stream 重复 play_music 应空操作")
		failures += 1

	# 6. play_music 淡切:交叉期双 playing;快速连切不崩且最终指向正确
	am.play_music(stream_b, 0.5)
	if not am._active_music.playing or am._active_music.stream != stream_b:
		print("FAIL 6: 淡切后 active 应在播 stream_b")
		failures += 1
	var playing_count := 0
	for child in am.get_children():
		if child is AudioStreamPlayer and child.playing and child.bus == "TestMusic":
			playing_count += 1
	if playing_count != 2:
		print("FAIL 6: 交叉期两个音乐播放器都应在播,实际 %d" % playing_count)
		failures += 1
	am.play_music(stream_a, 0.5)  # 淡切进行中立刻再切:kill 旧 Tween,不崩
	if am._active_music.stream != stream_a:
		print("FAIL 6: 连切后 active 应指向 stream_a")
		failures += 1

	# 7. stop_music:停止 + music_changed(null)
	music_events.clear()
	am.stop_music()
	if am._active_music.playing:
		print("FAIL 7: stop_music 后不应在播")
		failures += 1
	if music_events != [null]:
		print("FAIL 7: stop_music 应广播 music_changed(null)")
		failures += 1
	am.stop_music()  # 已停:空操作,不重发
	if music_events.size() != 1:
		print("FAIL 7: 已停止时 stop_music 应空操作")
		failures += 1

	# 8. SFX 轮转:pool=2 连播 3 个,第 3 个落在池内某个播放器上(复用/抢占),
	#    参数设置正确
	var sfx1 := AudioStreamGenerator.new()
	var sfx2 := AudioStreamGenerator.new()
	var sfx3 := AudioStreamGenerator.new()
	am.play_sfx(sfx1)
	am.play_sfx(sfx2, -6.0, 1.5)
	am.play_sfx(sfx3)
	var pool_streams := []
	for player in am._sfx_players:
		pool_streams.append(player.stream)
	if not pool_streams.has(sfx3):
		print("FAIL 8: 第 3 个 SFX 应落在池内(复用或抢占)")
		failures += 1
	if not pool_streams.has(sfx2):
		print("FAIL 8: 第 2 个 SFX 应还在池内")
		failures += 1
	var found_pitch := false
	for player in am._sfx_players:
		if player.stream == sfx2 and is_equal_approx(player.pitch_scale, 1.5) and is_equal_approx(player.volume_db, -6.0):
			found_pitch = true
	if not found_pitch and pool_streams.has(sfx2):
		print("FAIL 8: SFX 参数(volume_db/pitch)应设置到播放器")
		failures += 1
	am.play_sfx(null)  # null 空操作,不崩

	# 清理:先 stop_music 杀掉当前淡切 Tween;但 Tween 被 kill 时其 chain 里的
	# outgoing.stop() 回调不会触发,可能残留另一个音乐播放器(非 _active_music)
	# 仍处于 playing 状态,故显式遍历所有子播放器逐一 stop(),确保 free() 前
	# AudioServer 侧无任何播放中的流。
	# 关键坑(调试确认,见 scratchpad 报告):headless 下 process_frame 推进几乎
	# 不消耗真实墙钟时间,而音频混音在独立线程按真实时间节奏运行;仅 await
	# 帧不足以让混音线程追上已停止的播放器状态——反而更多帧推进=更多主线程
	# /音频线程交错窗口,经验证 crash 概率不降反升。改用 OS.delay_msec 给音频
	# 线程真实时间结算,再 free,避免与 quit() 竞态崩溃(已用 40 次连续 headless
	# 运行验证 0 崩溃)。
	am.stop_music()
	for child in am.get_children():
		if child is AudioStreamPlayer and child.playing:
			child.stop()
	OS.delay_msec(50)
	am.free()
	settings.free()
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	OS.delay_msec(50)

	if failures == 0:
		print("test_audio_manager: ALL PASS")
		quit(0)
	else:
		print("test_audio_manager: %d FAILURE(S)" % failures)
		quit(1)
