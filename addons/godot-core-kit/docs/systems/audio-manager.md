# AudioManager —— 总线音量 + BGM 交叉淡入淡出 + SFX 轮转池

> `CoreKit.audio` · `systems/audio_manager.gd`

## 职责

`_ready` 保障 Music/SFX 总线存在(缺则创建并 send 到 Master,已有则尊重工程布局),并常驻两个音乐播放器(交叉淡切用)+ `sfx_pool_size` 个 SFX 播放器。音量以线性 0~1 为 API/存储域(玩家滑条天然线性),写 `AudioServer` 时才转 dB;经 `bind_settings` 注入的 Settings 持久化(section `"audio"`)。SFX 池满时抢占游标位(最早启用的):新音效通常与当下操作强相关,旧的最可牺牲。2D 位置音效、音频事件表、ducking 均不在 v1 范围。

## 公开 API

```gdscript
signal music_changed(stream: AudioStream)  # BGM 实际切换(play_music 生效)后广播;stop_music 广播 null

var bus_music := "Music"    # 音乐总线名;不存在则自动创建并 send 到 Master
var bus_sfx := "SFX"        # 音效总线名;同上
var sfx_pool_size: int = 8  # SFX 轮转池大小;_ready 时建池,之后改动不生效——测试注入接缝:同进程内隔离独立总线图须在 _ready 前设置

func bind_settings(settings) -> void
    # 注入 Settings:恢复 master/music/sfx 三总线音量(缺省不动)并持有引用

func set_volume(bus_key: String, linear: float) -> void
    # bus_key ∈ master/music/sfx;linear 0.0~1.0(clamp)。写 AudioServer 并持久化

func get_volume(bus_key: String) -> float
    # 返回当前线性音量;未知 bus_key 返回 1.0(附警告)

func play_music(stream: AudioStream, fade_sec: float = 0.0) -> void
    # fade_sec>0 与当前曲交叉淡入淡出,=0 硬切;同一资源在播 → 空操作;stream=null → 等价 stop_music

func stop_music(fade_sec: float = 0.0) -> void
    # 停止 BGM,可选淡出

func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void
    # 轮转池取下一个空闲播放器播放一次性音效;全忙时抢占游标位
```

## 依赖

被 `CoreKit` 门面经 `bind_settings(self)` 注入 Settings,做音量持久化(section `"audio"`);未注入(如脱离门面单测)时功能正常但不落盘。未知总线名等运行期告警经 `CoreKit.log.warn` 输出。

## 用法示例

```gdscript
# 播放 BGM,3 秒交叉淡入淡出
CoreKit.audio.play_music(preload("res://bgm/level1.ogg"), 3.0)

# 播放一次性音效
CoreKit.audio.play_sfx(preload("res://sfx/jump.ogg"))

# 调整音量(自动写 AudioServer + 落盘到 Settings)
CoreKit.audio.set_volume("music", 0.6)
```

## 注意事项

- **总线布局尊重工程既有设置**:`_ready` 只在 Music/SFX 总线缺失时创建(append 到末尾 + send 到 Master),已存在的总线不会被改动。
- **音量域**:API/存储全程线性 0~1,只在写 `AudioServer` 时转 dB;`set_volume`/`get_volume` 对未知 `bus_key` 分别是"忽略写入(警告)"和"返回 1.0(警告)"。
- **BGM 交叉淡切**:两个常驻播放器 A/B 轮换角色,crossfade 用并行 Tween 同时推 incoming/outgoing 的 `volume_db`,`-60dB`(低于可闻阈)当作淡出终点/淡入起点;`play_music` 对同一资源正在播放是空操作。
- **SFX 池抢占无优先级**:池(默认 8 个)全忙时直接抢占游标位——最早启用的播放器被新音效顶掉,不做优先级/2D 定位/ducking(v1 不做)。
- **Web 自动播放策略**:首次用户手势前 `AudioContext` 可能被浏览器挂起,提前 `play_music` 不报错,手势后自动出声,是引擎层行为,无需特殊处理。
- **单测隔离**:要在同进程内跑一套独立总线图(避免与 `CoreKit.audio` 共用播放器/Tween 而在退出时竞态),须在该节点 `_ready` 前设置 `bus_music`/`bus_sfx`/`sfx_pool_size`。
