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

## 总线名;默认 "Music"/"SFX",与真实 autoload 消费者行为一致。若需在同
## 进程内隔离出独立总线(如单测,避免与 CoreKit.audio 的全局总线图共用播放
## 器/Tween 而在退出时竞态),须在该节点 _ready 前设置(如 sfx_pool_size)。
var bus_music := "Music"
var bus_sfx := "SFX"
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
	_ensure_bus(bus_music)
	_ensure_bus(bus_sfx)
	_music_a = _make_player(bus_music)
	_music_b = _make_player(bus_music)
	_active_music = _music_a
	for i in sfx_pool_size:
		_sfx_players.append(_make_player(bus_sfx))


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
			return AudioServer.get_bus_index(bus_music)
		"sfx":
			return AudioServer.get_bus_index(bus_sfx)
	return -1


func _kill_music_tween() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
