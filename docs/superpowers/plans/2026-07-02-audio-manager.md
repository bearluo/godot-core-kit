# AudioManager 子系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现音频子系统 AudioManager(总线保障与线性音量持久化、双播放器交叉淡切 BGM、SFX 轮转池)。

**Architecture:** 见 spec `docs/superpowers/specs/2026-07-02-audio-manager-design.md`。单文件 Node;依赖 Settings(波 1,经 `bind_settings()` 注入);门面接线留给集成任务。

**Tech Stack:** Godot 4.7 / 纯 GDScript / headless `-s` 断言测试(headless 下 AudioServer 总线 API 完全可用;`create_tween` 需在树内 → 实例挂到测试 SceneTree 的 root)

## Global Constraints

- 分支:全部工作在 `feat/framework-v0.4` 上(从 main 切出);线性历史,不得产生 merge commit。
- 纯 GDScript、Tab 缩进;无 C#、无 GDExtension、无第三方依赖;命令行 `godot` 已在 PATH。
- Web 导出兼容:禁用线程/平台专属 API。
- 依赖纪律:仅 `CoreKit.log.warn`(运行期)与注入的 Settings(未注入时降级不持久化);初始化期诊断用 `push_warning`。
- 测试纪律(`-s` 避坑手册):`-s` 主脚本不得在类作用域 preload 任何引用 `CoreKit` 全局的脚本(`_initialize()` 内运行时 `load()`);untyped 值的下游变量显式标注类型(不用 `:=`);测试无论成败必须到达 `quit()`。
- 运行测试用硬超时模板(PowerShell,单测 60s 上限):

```powershell
$p = Start-Process godot -ArgumentList '--headless','--path','.','-s','res://test/test_audio_manager.gd' -RedirectStandardOutput "$env:TEMP\gck-out.txt" -RedirectStandardError "$env:TEMP\gck-err.txt" -PassThru -NoNewWindow; if (-not $p.WaitForExit(60000)) { $p.Kill(); 'TIMEOUT(疑似测试报错未达 quit)' }; Get-Content "$env:TEMP\gck-out.txt"
```

- git 提交消息不得含英文双引号(PowerShell here-string 坑)。

---

### Task 1: AudioManager 核心

**Files:**
- Create: `addons/godot-core-kit/audio_manager.gd`
- Test: `test/test_audio_manager.gd`

**Interfaces:**
- Consumes: Settings 实例(波 1):`get_value(section, key, default=null)`、`set_value(section, key, value)`;`CoreKit.log.warn(msg: String)`。
- Produces: `signal music_changed(stream: AudioStream)`;`const BUS_MUSIC := "Music"`、`const BUS_SFX := "SFX"`;`var sfx_pool_size: int = 8`(入树前设置);`bind_settings(settings) -> void`;`set_volume(bus_key: String, linear: float) -> void`(bus_key ∈ master/music/sfx);`get_volume(bus_key: String) -> float`;`play_music(stream: AudioStream, fade_sec: float = 0.0) -> void`;`stop_music(fade_sec: float = 0.0) -> void`;`play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void`;接缝 `_bus_key_to_index(bus_key) -> int`、`_ensure_bus(bus_name) -> void`、`var _settings`、`var _active_music`、`var _sfx_players: Array`。集成任务将调用 `CoreKit.audio.bind_settings(CoreKit.settings)`。

- [ ] **Step 1: 写失败测试 test/test_audio_manager.gd**

```gdscript
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
	root.add_child(am)    # 触发 _ready:建总线 + 2 音乐播放器 + 2 SFX 播放器

	# 1. Music/SFX 总线存在且 send 到 Master;重复 _ensure_bus 不重复创建
	var music_idx := AudioServer.get_bus_index("Music")
	var sfx_idx := AudioServer.get_bus_index("SFX")
	if music_idx == -1 or sfx_idx == -1:
		print("FAIL 1: Music/SFX 总线应被创建")
		failures += 1
	if AudioServer.get_bus_send(music_idx) != &"Master" or AudioServer.get_bus_send(sfx_idx) != &"Master":
		print("FAIL 1: 新建总线应 send 到 Master")
		failures += 1
	var bus_count_before := AudioServer.bus_count
	am._ensure_bus("Music")
	am._ensure_bus("SFX")
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
		if child is AudioStreamPlayer and child.playing and child.bus == "Music":
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

	# 清理
	am.free()
	settings.free()
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)

	if failures == 0:
		print("test_audio_manager: ALL PASS")
		quit(0)
	else:
		print("test_audio_manager: %d FAILURE(S)" % failures)
		quit(1)
```

- [ ] **Step 2: 跑测试确认失败**

用 Global Constraints 的硬超时模板运行。Expected: 报错退出,退出码非 0。

- [ ] **Step 3: 实现 addons/godot-core-kit/audio_manager.gd**

```gdscript
extends Node
## AudioManager —— 总线音量 + BGM 交叉淡入淡出 + SFX 轮转池。
##
## _ready 保障 Music/SFX 总线存在(缺则创建并 send 到 Master,已有则尊重
## 工程布局),并常驻两个音乐播放器(交叉淡切用)+ sfx_pool_size 个 SFX
## 播放器。音量以线性 0~1 为 API/存储域(玩家滑条天然线性),写 AudioServer
## 时转 dB;经 bind_settings 注入的 Settings 持久化(section "audio")。
## SFX 池满时抢占游标位(最早启用的):新音效通常与当下操作强相关,旧的最
## 可牺牲。2D 位置音效、音频事件表、ducking 均不在 v1 范围。
##
## Web 注:浏览器自动播放策略下,首次用户手势前 AudioContext 可能被挂起,
## 提前 play_music 不报错、手势后出声(引擎层行为,无需特殊处理)。

## BGM 实际切换(play_music 生效)后广播;stop_music 广播 null。
signal music_changed(stream: AudioStream)

const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const SETTINGS_SECTION := "audio"
## 淡入起点/淡出终点(dB);-60dB 已低于可闻阈,足够平滑。
const FADE_MIN_DB := -60.0

## SFX 轮转池大小;_ready 时建池,之后改动不生效。
var sfx_pool_size: int = 8

## bind_settings 注入;untyped:未注入(脱离门面单测/不持久化)时为 null。
var _settings = null
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active_music: AudioStreamPlayer
var _music_tween: Tween
var _sfx_players: Array = []
var _sfx_cursor: int = 0


func _ready() -> void:
	_ensure_bus(BUS_MUSIC)
	_ensure_bus(BUS_SFX)
	_music_a = _make_player(BUS_MUSIC)
	_music_b = _make_player(BUS_MUSIC)
	_active_music = _music_a
	for i in sfx_pool_size:
		_sfx_players.append(_make_player(BUS_SFX))


## 注入 Settings:恢复三总线音量(缺省不动)并持有引用。
func bind_settings(settings) -> void:
	_settings = settings
	if _settings == null:
		return
	for bus_key in ["master", "music", "sfx"]:
		var stored = _settings.get_value(SETTINGS_SECTION, bus_key)
		if typeof(stored) in [TYPE_INT, TYPE_FLOAT]:
			_apply_volume(bus_key, clampf(float(stored), 0.0, 1.0))


## bus_key ∈ master/music/sfx;linear 0.0~1.0(clamp)。写 AudioServer 并持久化。
func set_volume(bus_key: String, linear: float) -> void:
	var idx := _bus_key_to_index(bus_key)
	if idx == -1:
		CoreKit.log.warn("AudioManager: 未知总线 '%s',忽略 set_volume" % bus_key)
		return
	var clamped := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clamped))
	if _settings != null:
		_settings.set_value(SETTINGS_SECTION, bus_key, clamped)


## 返回当前线性音量;未知 bus_key 返回 1.0(附警告)。
func get_volume(bus_key: String) -> float:
	var idx := _bus_key_to_index(bus_key)
	if idx == -1:
		CoreKit.log.warn("AudioManager: 未知总线 '%s',get_volume 返回 1.0" % bus_key)
		return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


## 播放 BGM。fade_sec > 0 与当前曲交叉淡入淡出,= 0 硬切;
## 与当前正在播放的是同一资源 → 空操作;stream 为 null → 等价 stop_music。
func play_music(stream: AudioStream, fade_sec: float = 0.0) -> void:
	if stream == null:
		stop_music(fade_sec)
		return
	if _active_music.playing and _active_music.stream == stream:
		return
	_kill_music_tween()
	var incoming := _music_b if _active_music == _music_a else _music_a
	var outgoing := _active_music
	incoming.stream = stream
	if fade_sec <= 0.0:
		outgoing.stop()
		incoming.volume_db = 0.0
		incoming.play()
	else:
		incoming.volume_db = FADE_MIN_DB
		incoming.play()
		_music_tween = create_tween().set_parallel(true)
		_music_tween.tween_property(incoming, "volume_db", 0.0, fade_sec)
		_music_tween.tween_property(outgoing, "volume_db", FADE_MIN_DB, fade_sec)
		_music_tween.chain().tween_callback(outgoing.stop)
	_active_music = incoming
	music_changed.emit(stream)


func stop_music(fade_sec: float = 0.0) -> void:
	if not _active_music.playing:
		return
	_kill_music_tween()
	if fade_sec <= 0.0:
		_active_music.stop()
	else:
		var fading := _active_music
		_music_tween = create_tween()
		_music_tween.tween_property(fading, "volume_db", FADE_MIN_DB, fade_sec)
		_music_tween.tween_callback(fading.stop)
	music_changed.emit(null)


## one-shot 音效:取轮转池下一个空闲播放器;全忙时抢占游标位。
func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null or _sfx_players.is_empty():
		return
	var player: AudioStreamPlayer = null
	for i in _sfx_players.size():
		var candidate: AudioStreamPlayer = _sfx_players[(_sfx_cursor + i) % _sfx_players.size()]
		if not candidate.playing:
			player = candidate
			_sfx_cursor = (_sfx_cursor + i + 1) % _sfx_players.size()
			break
	if player == null:
		player = _sfx_players[_sfx_cursor]
		_sfx_cursor = (_sfx_cursor + 1) % _sfx_players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()


func _make_player(bus_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus_name
	add_child(player)
	return player


## 总线不存在则创建(append 到末尾)并 send 到 Master;已存在则不动。
func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func _apply_volume(bus_key: String, linear: float) -> void:
	var idx := _bus_key_to_index(bus_key)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))


func _bus_key_to_index(bus_key: String) -> int:
	match bus_key:
		"master":
			return AudioServer.get_bus_index("Master")
		"music":
			return AudioServer.get_bus_index(BUS_MUSIC)
		"sfx":
			return AudioServer.get_bus_index(BUS_SFX)
	return -1


func _kill_music_tween() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
```

- [ ] **Step 4: 跑测试确认全绿**

同 Step 2 命令。Expected: `test_audio_manager: ALL PASS`,退出码 0。
若测试 4 的 bind_settings 恢复断言失败,先确认 Settings(波 1)已合入当前分支。

- [ ] **Step 5: 提交**

```powershell
git add addons/godot-core-kit/audio_manager.gd test/test_audio_manager.gd
git commit -m 'feat: add AudioManager core (bus volumes, crossfade music, sfx pool)'
```
