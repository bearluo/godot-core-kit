extends RefCounted
## 程序化音频(P2 占位,零二进制资产):代码合成 AudioStreamWAV。SFX = 正弦 + 指数衰减包络,
## 按 name 缓存;BGM = 一小段四音循环(loop_mode=LOOP_FORWARD)。headless dummy 音频驱动下
## 生成/播放均不崩。真素材(ogg BGM + wav 音效)留 P5 换,接口 sfx()/bgm() 不变。

const RATE := 22050
## 循环流尾部补的帧数,供混音器在回绕处插值,详见 _wav()。
const LOOP_PAD_FRAMES := 8

static var _cache := {}


## 取音效流(缓存):till/plant/water/harvest/buy/sell/day/rain。
static func sfx(name: StringName) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var s: AudioStreamWAV
	match name:
		&"till":    s = _tone(180.0, 0.12, 0.5, 9.0)
		&"plant":   s = _tone(523.0, 0.10, 0.4, 11.0)
		&"water":   s = _tone(700.0, 0.14, 0.35, 7.0)
		&"harvest": s = _chord([523.0, 784.0], 0.20, 0.35)
		&"buy":     s = _tone(880.0, 0.08, 0.4, 13.0)
		&"sell":    s = _tone(988.0, 0.10, 0.4, 13.0)
		&"day":     s = _tone(330.0, 0.28, 0.3, 3.0)
		&"rain":    s = _noise(0.22, 0.18)
		_:          s = _tone(440.0, 0.10, 0.3, 9.0)
	_cache[name] = s
	return s


## 取循环 BGM(缓存):G-A-C-A 四音软起软落。
static func bgm() -> AudioStreamWAV:
	if _cache.has(&"__bgm"):
		return _cache[&"__bgm"]
	var notes := [392.0, 440.0, 523.0, 440.0]
	var note_dur := 0.45
	var per := int(RATE * note_dur)
	var data := PackedByteArray()
	data.resize(notes.size() * per * 2)
	var idx := 0
	for note in notes:
		for i in range(per):
			var t := float(i) / RATE
			var env := 0.6 * (1.0 - exp(-25.0 * t)) * exp(-1.8 * t)   # 软起 + 缓落
			var v := int(clampf(sin(TAU * note * t) * env * 0.4, -1.0, 1.0) * 32767.0)
			data.encode_s16(idx, v)
			idx += 2
	var w := _wav(data, true)
	_cache[&"__bgm"] = w
	return w


static func _tone(freq: float, dur: float, vol: float, decay: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / RATE
		var v := int(clampf(sin(TAU * freq * t) * exp(-decay * t) * vol, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	return _wav(data, false)


static func _chord(freqs: Array, dur: float, vol: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / RATE
		var s := 0.0
		for f in freqs:
			s += sin(TAU * float(f) * t)
		var v := int(clampf((s / float(freqs.size())) * exp(-6.0 * t) * vol, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	return _wav(data, false)


## 无引擎 RNG 的伪噪声(sin 高频取小数),避免依赖随机源;够"沙沙"占位即可。
static func _noise(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / RATE
		var r := fmod(sin(float(i) * 12.9898) * 43758.5453, 2.0) - 1.0
		var v := int(clampf(r * exp(-7.0 * t) * vol, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	return _wav(data, false)


static func _wav(data: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	if loop:
		# 混音器在回绕处要读 loop_end 之后的帧做插值。导入器生成的 WAV 自带尾部
		# padding,这里手工拼的缓冲没有,于是循环第一次回绕就读出 data 末尾——
		# 桌面上多半只是读到相邻堆数据,Android 上直接 SIGSEGV(SEGV_ACCERR)。
		# 补一段循环起点的拷贝:既让插值有帧可落,又让跨接点在听感上连续。
		var padded := data.duplicate()
		padded.append_array(data.slice(0, LOOP_PAD_FRAMES * 2))
		w.data = padded
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(data.size() / 2)
	else:
		w.data = data
	return w
