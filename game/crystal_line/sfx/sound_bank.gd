class_name CrystalSoundBank
extends RefCounted
## 《晶核防线》音效接缝 + 可烘焙基线。
## 三级: assets/<key>.wav|.ogg → assets/generated/<key>.wav → _make_stream()

const ASSET_DIR := "res://game/crystal_line/assets"
const GENERATED_SUBDIR := "generated"
const MIX_RATE := 22050

## 对齐核心瞬间:放塔 blip、击杀 tick、清波 arp、漏怪 noise、点 UI 轻音
const VOICES := {
	&"place": {"freq": 720.0, "dur": 0.12, "wave": "blip", "sweep": 1.4},
	&"hit": {"freq": 480.0, "dur": 0.06, "wave": "blip", "sweep": 0.7},
	&"clear": {"freq": 392.0, "dur": 0.45, "wave": "arp", "sweep": 1.0},
	&"leak": {"freq": 180.0, "dur": 0.28, "wave": "noise", "sweep": 0.5},
	&"ui": {"freq": 880.0, "dur": 0.05, "wave": "blip", "sweep": 1.0},
	&"deny": {"freq": 220.0, "dur": 0.10, "wave": "blip", "sweep": 0.6},
}
const DEFAULT_VOICE := {"freq": 500.0, "dur": 0.10, "wave": "blip", "sweep": 1.0}

var _cache: Dictionary = {}


func stream_for(key: StringName) -> AudioStream:
	if _cache.has(key):
		return _cache[key]
	var s := _load_first([_real_wav(key), _real_ogg(key), _baked_wav(key)])
	if s == null:
		s = _make_stream(key)
	_cache[key] = s
	return s


func source_for(key: StringName) -> String:
	if ResourceLoader.exists(_real_wav(key)) or ResourceLoader.exists(_real_ogg(key)):
		return "asset"
	if ResourceLoader.exists(_baked_wav(key)):
		return "baked"
	return "procedural"


func _real_wav(key: StringName) -> String:
	return "%s/%s.wav" % [ASSET_DIR, key]


func _real_ogg(key: StringName) -> String:
	return "%s/%s.ogg" % [ASSET_DIR, key]


func _baked_wav(key: StringName) -> String:
	return "%s/%s.wav" % [generated_dir(), key]


func _load_first(paths: Array) -> AudioStream:
	for p in paths:
		if ResourceLoader.exists(p):
			var r = load(p)
			if r is AudioStream:
				return r
	return null


func generated_dir() -> String:
	return "%s/%s" % [ASSET_DIR, GENERATED_SUBDIR]


func bake_keys() -> Array:
	return VOICES.keys()


func bake_stream(key: StringName) -> AudioStreamWAV:
	return _make_stream(key)


func brief(key: StringName) -> Dictionary:
	var v: Dictionary = VOICES.get(key, DEFAULT_VOICE)
	var mood := "塔防 UI"
	match key:
		&"place":
			mood = "召唤落下,短促上扬,笃定"
		&"hit":
			mood = "命中轻 tick"
		&"clear":
			mood = "清波胜利琶音,松一口气"
		&"leak":
			mood = "漏怪低沉噪声警告"
		&"ui":
			mood = "点选轻反馈"
		&"deny":
			mood = "无法放置低沉否认"
	return {
		"key": key,
		"freq": v["freq"],
		"dur": v["dur"],
		"wave": v["wave"],
		"prompt": "<%s> 手游 SFX,基频 %.0fHz 时长 %.2fs 波形 %s,%s,8bit 干净无混响" % [
			key, v["freq"], v["dur"], v["wave"], mood],
	}


func _make_stream(key: StringName) -> AudioStreamWAV:
	var v: Dictionary = VOICES.get(key, DEFAULT_VOICE)
	var freq: float = v["freq"]
	var dur: float = v["dur"]
	var wave: String = v["wave"]
	var sweep: float = v["sweep"]
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var frac := float(i) / float(maxi(n, 1))
		var env := _env(frac)
		var f := freq * lerpf(1.0, sweep, frac)
		phase += TAU * f / float(MIX_RATE)
		var s := 0.0
		match wave:
			"noise":
				s = _noise(i) * env
			"arp":
				var step := clampi(int(frac * 4.0), 0, 3)
				var mult: float = [1.0, 1.25, 1.5, 2.0][step]
				s = sin(phase * mult) * env
			_:
				s = sin(phase) * env
		data.encode_s16(i * 2, int(clampf(s * 0.4, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	return w


func _env(frac: float) -> float:
	if frac < 0.05:
		return frac / 0.05
	var d := (frac - 0.05) / 0.95
	return (1.0 - d) * (1.0 - d)


func _noise(i: int) -> float:
	var x := sin(float(i) * 12.9898) * 43758.5453
	return (x - floor(x)) * 2.0 - 1.0
