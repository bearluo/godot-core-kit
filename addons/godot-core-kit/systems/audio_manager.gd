extends Node
## AudioManager —— 总线音量 + BGM/环境音交叉淡入淡出 + SFX/UI 轮转池。
##
## _ready 保障 Music/SFX/UI/Ambient 总线存在(缺则创建,已有则尊重工程布局;
## Music/SFX send 到 Master,UI/Ambient send 到 SFX → 一条「音效」滑条管三者),
## 并常驻:音乐 A/B 双播放器、环境音 A/B 双播放器(交叉淡切用)、sfx_pool_size
## 个 SFX 播放器、ui_pool_size 个 UI 播放器。音量以线性 0~1 为 API/存储域(玩家
## 滑条天然线性),写 AudioServer 时转 dB;经 bind_settings 注入的 Settings 持久化
## (section "audio")。池满时抢占游标位(最早启用的):新音效通常与当下操作强相
## 关,旧的最可牺牲。
##
## 暂停策略(tree.paused):Music 与 UI 继续播(暂停菜单要有音乐和按钮声),
## SFX 与 Ambient 跟随暂停(游戏世界内的声音)。pause_music_with_tree = true 恢复
## v0.25 及以前「BGM 随暂停停下」的旧行为。
## 2D 位置音效、音频事件表、ducking、多层环境音、播放列表均不在范围内。
##
## Web 注:浏览器自动播放策略下,首次用户手势前 AudioContext 可能被挂起,
## 提前 play_music 不报错、手势后出声(引擎层行为,无需特殊处理)。

## BGM 实际切换(play_music 生效)后广播;stop_music 广播 null。
signal music_changed(stream: AudioStream)

## 总线名;默认 "Music"/"SFX"/"UI"/"Ambient",与真实 autoload 消费者行为一致。
## 若需在同进程内隔离出独立总线(如单测,避免与 CoreKit.audio 的全局总线图共用
## 播放器/Tween 而在退出时竞态),须在该节点 _ready 前设置(如 sfx_pool_size)。
var bus_music := "Music"
var bus_sfx := "SFX"
var bus_ui := "UI"
var bus_ambient := "Ambient"
const SETTINGS_SECTION := "audio"
## 淡入起点/淡出终点(dB);-60dB 已低于可闻阈,足够平滑。
const FADE_MIN_DB := -60.0

## 轮转池大小;_ready 时建池,之后改动不生效。
var sfx_pool_size: int = 8
var ui_pool_size: int = 4
## true = BGM 随 tree 暂停停下(v0.25 及以前的行为);须在 _ready 前设置。
var pause_music_with_tree := false

## bind_settings 注入;untyped:未注入(脱离门面单测/不持久化)时为 null。
var _settings = null
var _music: _CrossfadeChannel
var _ambient: _CrossfadeChannel
var _sfx_players: Array = []
var _ui_players: Array = []
## 与池内播放器一一对应:该播放器当前这一次播放的句柄。句柄全局递增,SFX 与
## UI 两池共用计数器 → 句柄空间天然不重叠;被抢占即覆盖 → 旧句柄自然失效。
var _sfx_handles: Array = []
var _ui_handles: Array = []
var _sfx_cursor: int = 0
var _ui_cursor: int = 0
var _next_handle: int = 1


func _ready() -> void:
	_ensure_bus(bus_music)
	_ensure_bus(bus_sfx)
	_ensure_bus(bus_ui, bus_sfx)
	_ensure_bus(bus_ambient, bus_sfx)
	var music_mode := PROCESS_MODE_INHERIT if pause_music_with_tree else PROCESS_MODE_ALWAYS
	_music = _CrossfadeChannel.new(self, bus_music, music_mode)
	_ambient = _CrossfadeChannel.new(self, bus_ambient, PROCESS_MODE_INHERIT)
	for i in sfx_pool_size:
		_sfx_players.append(_make_player(bus_sfx))
		_sfx_handles.append(0)
	for i in ui_pool_size:
		_ui_players.append(_make_player(bus_ui, PROCESS_MODE_ALWAYS))
		_ui_handles.append(0)


## 注入 Settings:恢复各总线音量(缺省不动)并持有引用。
func bind_settings(settings) -> void:
	_settings = settings
	if _settings == null:
		return
	for bus_key in ["master", "music", "sfx", "ui", "ambient"]:
		var stored = _settings.get_value(SETTINGS_SECTION, bus_key)
		if typeof(stored) in [TYPE_INT, TYPE_FLOAT]:
			_apply_volume(bus_key, clampf(float(stored), 0.0, 1.0))


## bus_key ∈ master/music/sfx/ui/ambient;linear 0.0~1.0(clamp)。写 AudioServer 并持久化。
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


## 播放 BGM。fade_sec > 0 与当前曲交叉淡入淡出,= 0 硬切;from_position 为起播
## 秒数(配合 get_music_position 回到原曲原位置)。与当前正在播放的是同一资源 →
## 空操作(from_position 也被忽略);stream 为 null → 等价 stop_music。
func play_music(stream: AudioStream, fade_sec: float = 0.0, from_position: float = 0.0) -> void:
	if stream == null:
		stop_music(fade_sec)
		return
	if _music.play(stream, fade_sec, from_position):
		music_changed.emit(stream)


func stop_music(fade_sec: float = 0.0) -> void:
	if _music.stop(fade_sec):
		music_changed.emit(null)


func is_music_playing() -> bool:
	return _music.active.playing


## 当前在播的 BGM;未播放返回 null。
func current_music() -> AudioStream:
	return _music.active.stream if _music.active.playing else null


## 当前 BGM 播放位置(秒);未播放返回 0.0。
func get_music_position() -> float:
	return _music.active.get_playback_position() if _music.active.playing else 0.0


## 单层环境音,语义同 play_music(同资源空操作、null 等价停止、fade 交叉淡切);
## 跟随 tree 暂停。
func play_ambient(stream: AudioStream, fade_sec: float = 0.0) -> void:
	if stream == null:
		stop_ambient(fade_sec)
		return
	_ambient.play(stream, fade_sec, 0.0)


func stop_ambient(fade_sec: float = 0.0) -> void:
	_ambient.stop(fade_sec)


## one-shot 音效:取轮转池下一个空闲播放器;全忙时抢占游标位。
## 返回句柄(供 stop_sfx 停循环音效);stream 为 null 或池为空返回 0。
func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> int:
	var slot := _pick_slot(_sfx_players, _sfx_cursor)
	if stream == null or slot == -1:
		return 0
	_sfx_cursor = (slot + 1) % _sfx_players.size()
	return _play_in(_sfx_players, _sfx_handles, slot, stream, volume_db, pitch_scale)


## UI 音效:独立 UI 总线 + 独立轮转池,tree 暂停时照常播放。返回句柄同 play_sfx,
## 但 stop_sfx 只认 SFX 池(UI 音效一般很短,无需停)。
func play_ui_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> int:
	var slot := _pick_slot(_ui_players, _ui_cursor)
	if stream == null or slot == -1:
		return 0
	_ui_cursor = (slot + 1) % _ui_players.size()
	return _play_in(_ui_players, _ui_handles, slot, stream, volume_db, pitch_scale)


## 停掉句柄对应的那一次 SFX;播放器已被抢占去播别的(句柄过期)则空操作。
func stop_sfx(handle: int) -> void:
	if handle == 0:
		return
	var slot := _sfx_handles.find(handle)
	if slot != -1:
		_sfx_players[slot].stop()


## 停掉 SFX 池全部声音(不影响 UI 池)。
func stop_all_sfx() -> void:
	for player in _sfx_players:
		player.stop()


## 从 cursor 起找第一个空闲播放器;全忙返回 cursor(抢占);池空返回 -1。
func _pick_slot(players: Array, cursor: int) -> int:
	if players.is_empty():
		return -1
	for i in players.size():
		var slot := (cursor + i) % players.size()
		if not players[slot].playing:
			return slot
	return cursor


func _play_in(players: Array, handles: Array, slot: int, stream: AudioStream, volume_db: float, pitch_scale: float) -> int:
	var player: AudioStreamPlayer = players[slot]
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	var handle := _next_handle
	_next_handle += 1
	handles[slot] = handle
	return handle


func _make_player(bus_name: String, mode: ProcessMode = PROCESS_MODE_INHERIT) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus_name
	player.process_mode = mode
	add_child(player)
	return player


## 总线不存在则创建(append 到末尾)并 send 到 send_to;已存在则不动。
func _ensure_bus(bus_name: String, send_to: String = "Master") -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send_to)


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
		"ui":
			return AudioServer.get_bus_index(bus_ui)
		"ambient":
			return AudioServer.get_bus_index(bus_ambient)
	return -1


## A/B 双播放器交叉淡切通道;Music 与 Ambient 各持一个。Tween 暂停模式跟随
## 播放器 process_mode,保证 ALWAYS 通道的淡切在 tree 暂停时也能走完。
class _CrossfadeChannel:
	var active: AudioStreamPlayer
	var _owner: Node
	var _a: AudioStreamPlayer
	var _b: AudioStreamPlayer
	var _tween: Tween
	var _tween_pause_mode: Tween.TweenPauseMode

	func _init(owner: Node, bus_name: String, mode: Node.ProcessMode) -> void:
		_owner = owner
		_a = owner._make_player(bus_name, mode)
		_b = owner._make_player(bus_name, mode)
		active = _a
		_tween_pause_mode = Tween.TWEEN_PAUSE_PROCESS if mode == Node.PROCESS_MODE_ALWAYS else Tween.TWEEN_PAUSE_BOUND

	## 实际切换返回 true;同资源在播返回 false。
	func play(stream: AudioStream, fade_sec: float, from_position: float) -> bool:
		if active.playing and active.stream == stream:
			return false
		_kill_tween()
		var incoming := _b if active == _a else _a
		var outgoing := active
		incoming.stream = stream
		if fade_sec <= 0.0:
			outgoing.stop()
			incoming.volume_db = 0.0
			incoming.play(from_position)
		else:
			incoming.volume_db = FADE_MIN_DB
			incoming.play(from_position)
			_tween = _new_tween().set_parallel(true)
			_tween.tween_property(incoming, "volume_db", 0.0, fade_sec)
			_tween.tween_property(outgoing, "volume_db", FADE_MIN_DB, fade_sec)
			_tween.chain().tween_callback(outgoing.stop)
		active = incoming
		return true

	## 实际停止返回 true;本就没在播返回 false。
	func stop(fade_sec: float) -> bool:
		if not active.playing:
			return false
		_kill_tween()
		if fade_sec <= 0.0:
			active.stop()
		else:
			var fading := active
			_tween = _new_tween()
			_tween.tween_property(fading, "volume_db", FADE_MIN_DB, fade_sec)
			_tween.tween_callback(fading.stop)
		return true

	func _new_tween() -> Tween:
		return _owner.create_tween().set_pause_mode(_tween_pause_mode)

	func _kill_tween() -> void:
		if _tween != null and _tween.is_valid():
			_tween.kill()
