# godot-core-kit AudioManager 子系统设计

- 日期:2026-07-02
- 状态:已确认,待实现
- 版本目标:0.4.0
- 前置:`2026-07-02-corekit-facade-design.md`(总纲;门面属性 `CoreKit.audio`)、`2026-07-02-settings-design.md`(音量持久化依赖)

---

## 目标与定位

`AudioManager` 是 BGM/SFX 的统一播放口:**三总线音量(持久化)+ BGM 交叉淡入淡出 + SFX 轮转池**。

定位边界(用户拍板"标准档"):不做 2D 位置音效(`play_sfx_at`)、不做音频事件表/随机容器、不做 ducking/侧链;SFX 池自管 `AudioStreamPlayer`,**不走 ObjectPool**(ObjectPool 面向 PackedScene 实例,音频池只是 N 个常驻播放器轮转)。

## Public API(GDScript 精确签名)

```gdscript
extends Node
## AudioManager —— 总线音量 + BGM 交叉淡入淡出 + SFX 轮转池。

## BGM 实际切换(play_music 生效)后广播;stop_music 广播 null。
signal music_changed(stream: AudioStream)

const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

## SFX 轮转池大小;在 _ready 建池,运行时改动不生效(文档注明)。
var sfx_pool_size: int = 8

## 由 CoreKit._ready 注入 Settings:恢复三总线音量并持有引用。
## 未注入时 set_volume 仍生效,只是不持久化。
func bind_settings(settings) -> void

## bus_key ∈ "master"/"music"/"sfx";linear 0.0~1.0(clamp)。写 AudioServer 并持久化。
func set_volume(bus_key: String, linear: float) -> void

## 返回当前线性音量;未知 bus_key 返回 1.0 并 CoreKit.log.warn。
func get_volume(bus_key: String) -> float

## 播放 BGM。fade_sec > 0 时与当前曲交叉淡入淡出,= 0 硬切;
## stream 与当前正在播放的是同一资源 → 空操作。stream 为 null → 等价 stop_music。
func play_music(stream: AudioStream, fade_sec: float = 0.0) -> void

func stop_music(fade_sec: float = 0.0) -> void

## one-shot 音效:取轮转池下一个播放器播放;全忙时抢占最早启用的那个。
func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void
```

## Behavior & data flow

- **总线保障**(`_ready`):`AudioServer.get_bus_index("Music")` 为 -1 则 `add_bus` + `set_bus_name` + `set_bus_send`(→Master);SFX 同理。工程已有同名总线则直接使用,不动布局。
- **音量**:线性值经 `linear_to_db` 写 `AudioServer.set_bus_volume_db`;`bind_settings` 时从 `settings("audio", "master"/"music"/"sfx")` 恢复(缺省 1.0);`set_volume` 写透 `settings.set_value`。`_bus_key_to_index(bus_key) -> int` 为接缝(未知 key 返回 -1)。
- **BGM 双播放器**:`_ready` 建 `_music_a`/`_music_b` 两个 `AudioStreamPlayer`(bus=Music)子节点,`_active_music` 指向当前者。`play_music(stream, fade)`:
  - fade = 0:当前停,备用播放器设 stream 直接 play,交换 active。
  - fade > 0:备用设 stream、volume_db = -60 起播;单个 Tween 并行把新者拉到 0 dB、旧者压到 -60 dB,完成后旧者 `stop()`。**新的 play/stop 请求先 kill 既有 Tween** 再启动(快速连切不叠加)。
  - 同资源判断:`_active_music.playing and _active_music.stream == stream` → 空操作。
- **SFX 轮转池**:`_ready` 建 `sfx_pool_size` 个 `AudioStreamPlayer`(bus=SFX)子节点;`play_sfx` 从游标起找 `not playing` 的空闲者,全忙则直接用游标位(抢占最早启用的),设 stream/volume_db/pitch_scale 后 play,游标 +1 取模。

## Key decisions

| # | 维度 | 结论 | 理由 |
|---|---|---|---|
| 1 | 总线 | 运行时按需创建 Music/SFX | 消费方零配置可用;已有布局则尊重 |
| 2 | 音量存储 | 线性 0~1(settings 与 API 同域),写 AudioServer 时转 dB | 玩家滑条天然是线性;dB 只是引擎内部表示 |
| 3 | BGM 淡切 | 双播放器 + Tween 交叉 | 唯一能"旧曲尾与新曲头重叠"的结构;单播放器只能先淡出再进,断感明显 |
| 4 | 池满策略 | 抢占最早启用的(用户拍板方向:不拒绝新音效) | 新音效通常与当下操作强相关,旧的最可牺牲 |
| 5 | SFX 池 | 自管常驻播放器,不走 ObjectPool | ObjectPool 面向 PackedScene;音频池无"场景实例"概念 |
| 6 | 2D 位置音效 | 不做 | 用户拍板标准档;将来可加 `play_sfx_at` 不破坏现有 API |

## Web-export considerations

- 全同步、零线程;Tween 走 SceneTree,Web 一致。
- 浏览器自动播放策略:首次用户手势前 AudioContext 可能被挂起(Godot 引擎层处理恢复),`play_music` 提前调用不报错、手势后出声——引擎行为,文档注明即可,不做特殊处理。

## Testable seams + test plan

headless 下 `AudioServer` 总线 API 完全可用(无声卡也能建总线、设音量);`play` 不出声但状态(`playing`/`stream`)可断言。Tween 需要树内驱动——淡切的中间态不做帧级断言,只断言终态与结构(测试驱动:把实例挂到测试 SceneTree root 下,手动步进或直接断言 Tween 存在 + kill 语义)。

`test/test_audio_manager.gd`(headless,直接实例化 + 挂树):

1. `_ready` 后 Music/SFX 总线存在且 send 到 Master;已存在同名总线时不重复创建(总线数不变)。
2. `_bus_key_to_index`:三个合法 key 正确,未知 key → -1;`get_volume` 未知 key 返回 1.0。
3. `set_volume`:AudioServer 对应总线 `volume_db == linear_to_db(x)`;clamp(-0.5→0.0、1.5→1.0)。
4. 持久化:bind 真 Settings 实例,set_volume 写入 settings;重建 + bind 同一 Settings → 音量恢复到 AudioServer。
5. `play_music` 硬切:active 播放器 stream 正确且 playing;`music_changed` 广播;同 stream 二次调用空操作(信号不重发)。
6. `play_music` 淡切:调用后两个播放器都 playing(交叉期);连续两次快速淡切不崩、最终 active 是第二首(kill 旧 Tween 语义)。
7. `stop_music`:播放器停止,`music_changed(null)` 广播。
8. SFX 轮转:pool_size=2 时连播 3 个,断言第 3 个复用了第 1 个播放器(抢占);各播放器 stream/pitch 设置正确。

音量→出声、淡切听感属 demo 冒烟(编辑器里人耳验证)。

## 版本

AudioManager v0.4.0 起:Music/SFX 总线保障、线性音量 + Settings 持久化、双播放器交叉淡切 BGM、SFX 轮转池(满则抢占)。依赖:log(运行期)、settings(注入)。
