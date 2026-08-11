class_name GameSoundBank   # ← 重命名成你游戏的(如 FooSoundBank)
extends RefCounted
## 「音效接缝」+ 可烘焙基线。取音统一经 stream_for(key),三级解析:
##   1) assets/<key>.wav | .ogg      真/AI 音频(手投,最高优先,wav 优先 ogg 次之)
##   2) assets/generated/<key>.wav   确定性烘焙基线(bake_assets.gd 产,提交进仓库)
##   3) 运行时 _make_stream()         最后兜底
## 合成逻辑集中在 _make_stream(),bake(2)与 runtime(3)共用同一份 → 零漂移。
## 纯样本运算 headless 可用(dummy 音频驱动),故可进 kit 门测试。

const ASSET_DIR := "res://<game>/assets"      # ← 改成你游戏的 assets 路径
const GENERATED_SUBDIR := "generated"
const MIX_RATE := 22050

## key → 合成参数:freq 基频 / dur 时长秒 / wave 波形(blip/noise/arp)/ sweep 末频比率(线性扫频)。
const VOICES := {
	&"key_a": {"freq": 660.0, "dur": 0.10, "wave": "blip", "sweep": 1.0},
	&"key_b": {"freq": 392.0, "dur": 0.50, "wave": "arp",  "sweep": 1.0},
}
const DEFAULT_VOICE := {"freq": 500.0, "dur": 0.10, "wave": "blip", "sweep": 1.0}

var _cache: Dictionary = {}   # key -> AudioStream


# ---- 接缝:取音(三级)----
func stream_for(key: StringName) -> AudioStream:
	if _cache.has(key):
		return _cache[key]
	var s := _load_first([_real_wav(key), _real_ogg(key), _baked_wav(key)])
	if s == null:
		s = _make_stream(key)
	_cache[key] = s
	return s


## 当前解析来源:asset / baked / procedural。
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


# ---- 烘焙契约(bake_assets.gd 调用)----
func generated_dir() -> String:
	return "%s/%s" % [ASSET_DIR, GENERATED_SUBDIR]


func bake_keys() -> Array:
	return VOICES.keys()


func bake_stream(key: StringName) -> AudioStreamWAV:
	return _make_stream(key)


func brief(key: StringName) -> Dictionary:
	var v: Dictionary = VOICES.get(key, DEFAULT_VOICE)
	return {
		"key": key,
		"freq": v["freq"],
		"dur": v["dur"],
		"wave": v["wave"],
		"prompt": "<%s> 音效,基频 %.0fHz 时长 %.2fs 波形 %s,风格 ___(照愿景填)" % [key, v["freq"], v["dur"], v["wave"]],
	}


# ---- 确定性合成(bake 与 runtime 共用的唯一一份)----
## 按 voice 参数合成 16-bit 单声道 AudioStreamWAV(快起短衰包络)。零素材。
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
		var frac := float(i) / float(n)
		var env := _env(frac)
		var f := freq * lerpf(1.0, sweep, frac)   # 线性扫频(lerpf 返 float;lerp 返 Variant 会破 := 推断)
		phase += TAU * f / float(MIX_RATE)
		var s := 0.0
		match wave:
			"noise":
				s = _noise(i) * env
			"arp":
				var step := clampi(int(frac * 4.0), 0, 3)   # 上行琶音:根/三度/五度/八度
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


## 包络:前 5% 线性起音,之后二次衰减到 0(短促打击感)。
func _env(frac: float) -> float:
	if frac < 0.05:
		return frac / 0.05
	var d := (frac - 0.05) / 0.95
	return (1.0 - d) * (1.0 - d)


## 确定性伪噪声(不用 randf,保 headless 可复现 + 同 key 同波)。
func _noise(i: int) -> float:
	var x := sin(float(i) * 12.9898) * 43758.5453
	return (x - floor(x)) * 2.0 - 1.0
