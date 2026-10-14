# AudioManager —— 总线音量 + BGM/环境音交叉淡入淡出 + SFX/UI 轮转池

> `CoreKit.audio` · `systems/audio_manager.gd`

## 职责

`_ready` 保障四条总线存在:Music、SFX send 到 Master;UI、Ambient send 到 SFX。缺的就创建，已有的尊重工程原有布局。UI 和 Ambient 挂在 SFX 下面，所以玩家只拖「音效」一条滑条就能同时控制三者；想单独调的游戏再用 `set_volume("ui" | "ambient", x)`。

常驻的播放器：音乐 A/B 两个、环境音 A/B 两个（交叉淡切用）、`sfx_pool_size` 个 SFX、`ui_pool_size` 个 UI。音量以线性 0~1 为 API 和存储域（玩家滑条天然线性），写 `AudioServer` 时才转 dB；经 `bind_settings` 注入的 Settings 持久化（section `"audio"`）。池满时抢占游标位（最早启用的）：新音效通常与当下操作强相关，旧的最可牺牲。

## 暂停行为（0.26.0 起）

| 通道 | `get_tree().paused = true` 时 | 理由 |
|---|---|---|
| Music | **继续播**（淡切 Tween 也继续走） | 暂停菜单要有背景音乐 |
| UI | 继续播 | 暂停菜单的按钮要有声音 |
| SFX | 跟着暂停 | 游戏世界内的声音 |
| Ambient | 跟着暂停 | 游戏世界内的声音 |

**行为变更**：0.25 及以前 BGM 会随暂停停下。要恢复旧行为，在 `_ready` 前设 `pause_music_with_tree = true`。

## 公开 API

```gdscript
signal music_changed(stream: AudioStream)  # BGM 实际切换(play_music 生效)后广播;stop_music 广播 null

var bus_music := "Music"      # 总线名;不存在则自动创建
var bus_sfx := "SFX"
var bus_ui := "UI"            # send 到 bus_sfx
var bus_ambient := "Ambient"  # send 到 bus_sfx
var sfx_pool_size: int = 8    # 池大小;_ready 时建池,之后改动不生效
var ui_pool_size: int = 4
var pause_music_with_tree := false  # true = BGM 随暂停停下(旧行为);须在 _ready 前设置

func bind_settings(settings) -> void
    # 注入 Settings:恢复 master/music/sfx/ui/ambient 音量(缺省不动)并持有引用
func set_volume(bus_key: String, linear: float) -> void
    # bus_key ∈ master/music/sfx/ui/ambient;linear 0.0~1.0(clamp)。写 AudioServer 并持久化
func get_volume(bus_key: String) -> float
    # 返回当前线性音量;未知 bus_key 返回 1.0(附警告)

func play_music(stream: AudioStream, fade_sec := 0.0, from_position := 0.0) -> void
    # fade_sec>0 交叉淡入淡出,=0 硬切;from_position 起播秒数
    # 同一资源在播 → 空操作(from_position 也被忽略);stream=null → 等价 stop_music
func stop_music(fade_sec := 0.0) -> void
func is_music_playing() -> bool
func current_music() -> AudioStream      # 未播放返回 null
func get_music_position() -> float       # 未播放返回 0.0

func play_ambient(stream: AudioStream, fade_sec := 0.0) -> void
    # 单层环境音,语义同 play_music(同资源空操作、null 等价停止、fade 交叉淡切)
func stop_ambient(fade_sec := 0.0) -> void

func play_sfx(stream: AudioStream, volume_db := 0.0, pitch_scale := 1.0) -> int
    # 返回句柄;stream 为 null 或池为空返回 0。不接返回值的旧写法照常可用
func stop_sfx(handle: int) -> void
    # 只停这个句柄对应的那一次;播放器已被抢占去播别的 → 空操作,不会误停别人
func stop_all_sfx() -> void              # 停 SFX 池全部,不影响 UI 池
func play_ui_sfx(stream: AudioStream, volume_db := 0.0, pitch_scale := 1.0) -> int
    # UI 总线 + 独立池,暂停时照常播;stop_sfx 不认 UI 池的句柄
```

## 依赖

被 `CoreKit` 门面经 `bind_settings(self)` 注入 Settings，做音量持久化（section `"audio"`）；未注入（如脱离门面单测）时功能正常但不落盘。未知总线名等运行期告警经 `CoreKit.log.warn` 输出。

## 用法示例

```gdscript
# BGM 3 秒交叉淡切;环境音换场景时 2 秒交叉淡切
CoreKit.audio.play_music(preload("res://bgm/level1.ogg"), 3.0)
CoreKit.audio.play_ambient(preload("res://amb/forest.ogg"), 2.0)

# 打 boss 前记住原曲位置,打完回到原位
var resume_at := CoreKit.audio.get_music_position()
var field_bgm := CoreKit.audio.current_music()
CoreKit.audio.play_music(preload("res://bgm/boss.ogg"), 1.0)
# ...
CoreKit.audio.play_music(field_bgm, 1.0, resume_at)

# 循环音效(引擎声、蓄力声):留句柄,结束时停
var charge := CoreKit.audio.play_sfx(preload("res://sfx/charge_loop.ogg"))
# ...
CoreKit.audio.stop_sfx(charge)

# 暂停菜单的按钮音
CoreKit.audio.play_ui_sfx(preload("res://sfx/click.ogg"))

# 调整音量(自动写 AudioServer + 落盘到 Settings)
CoreKit.audio.set_volume("music", 0.6)
```

## 注意事项

- **总线布局尊重工程既有设置**：`_ready` 只在总线缺失时创建（append 到末尾），已存在的不改动。工程自己建了 UI/Ambient 总线时，它们 send 到哪里由工程决定。
- **音量域**：API 和存储全程线性 0~1，只在写 `AudioServer` 时转 dB；`set_volume`/`get_volume` 对未知 `bus_key` 分别是「忽略写入（警告）」和「返回 1.0（警告）」。
- **交叉淡切**：Music 与 Ambient 各有一对常驻播放器轮换角色，并行 Tween 同时推 incoming/outgoing 的 `volume_db`，`-60dB`（低于可闻阈）当淡出终点/淡入起点。
- **句柄**：全局递增整数，SFX 与 UI 两池共用计数器，所以两边的句柄不会重叠。播放器被抢占时句柄自然失效。
- **池抢占无优先级**：池全忙时直接抢占游标位，不做优先级、2D 定位、ducking。
- **Web 自动播放策略**：首次用户手势前 `AudioContext` 可能被浏览器挂起，提前 `play_music` 不报错，手势后自动出声，是引擎层行为，无需特殊处理。
- **单测隔离**：要在同进程内跑一套独立总线图（避免与 `CoreKit.audio` 共用播放器/Tween 而在退出时竞态），须在该节点 `_ready` 前设置四个 `bus_*` 和池大小。
- **不做**：位置音效、ducking、音频事件表、多层环境音、播放列表、按句柄调音量或音调。
