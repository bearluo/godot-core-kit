class_name FortuneSoundBank
extends RefCounted
## 程序化「音效接缝」:动作 SFX 统一经此取。优先加载 assets/<key>.wav|.ogg 真音频(零改代码 drop-in),
## 缺素材时按 key 的 voice 参数确定性合成 AudioStreamWAV 兜底。纯样本运算 headless 可用(dummy 音频驱动),
## 故可进 kit 门测试。约定同 gfx/art_bank.gd:真音频文件名 = key,丢进 assets/ 即自动顶替程序化音,无需改代码。

const ASSET_DIR := "res://examples/fortune-mill/assets"
const MIX_RATE := 22050

## 每类动作的合成参数:freq 基频 / dur 时长秒 / wave 波形(blip/noise/arp)/ sweep 末频比率(线性扫频)。
## key 对齐 world 动作命令。
const VOICES := {
	&"throw":   {"freq": 660.0,  "dur": 0.10, "wave": "blip",  "sweep": 1.0},
	&"scratch": {"freq": 1200.0, "dur": 0.16, "wave": "noise", "sweep": 0.5},
	&"pull":    {"freq": 520.0,  "dur": 0.14, "wave": "blip",  "sweep": 1.8},   # 上扬 coin
	&"drop":    {"freq": 300.0,  "dur": 0.09, "wave": "blip",  "sweep": 1.0},
	&"jackpot": {"freq": 440.0,  "dur": 0.45, "wave": "arp",   "sweep": 1.0},   # 上行琶音
	&"clear":   {"freq": 392.0,  "dur": 0.50, "wave": "arp",   "sweep": 1.0},   # 过关 fanfare
}
const DEFAULT_VOICE := {"freq": 500.0, "dur": 0.10, "wave": "blip", "sweep": 1.0}

var _cache: Dictionary = {}   # key -> AudioStream


## 取 key 对应音效:先真音频(drop-in)后程序化兜底,结果缓存。
func stream_for(key: StringName) -> AudioStream:
	if _cache.has(key):
		return _cache[key]
	var s := _load_asset(key)
	if s == null:
		s = _make_voice(key)
	_cache[key] = s
	return s


## key 的真音频投放路径(wav 优先,ogg 次之;把此路径的文件丢进去即自动顶替)。
func asset_path_wav(key: StringName) -> String:
	return "%s/%s.wav" % [ASSET_DIR, key]


func asset_path_ogg(key: StringName) -> String:
	return "%s/%s.ogg" % [ASSET_DIR, key]


## 当前解析来源:真音频存在返 "asset",否则 "procedural"。
func source_for(key: StringName) -> String:
	if ResourceLoader.exists(asset_path_wav(key)) or ResourceLoader.exists(asset_path_ogg(key)):
		return "asset"
	return "procedural"


func _load_asset(key: StringName) -> AudioStream:
	for p in [asset_path_wav(key), asset_path_ogg(key)]:
		if ResourceLoader.exists(p):
			var r = load(p)
			if r is AudioStream:
				return r
	return null


## 按 voice 参数确定性合成 16-bit 单声道 AudioStreamWAV(快起短衰包络)。零素材。
func _make_voice(key: StringName) -> AudioStreamWAV:
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
		var f := freq * lerpf(1.0, sweep, frac)   # 线性扫频(lerpf 返 float,lerp 返 Variant 会破 := 推断)
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
