# assets/ —— 真素材投放口(drop-in art seam)

本目录是 `gfx/art_bank.gd`(`FortuneArtBank`)的**真素材接缝**。仓库默认**不带任何美术**,
所有 UI 图标由 art_bank 按房间调色板**程序化生成**(确定性圆盘筹码,零素材可跑)。

## 零改代码替换程序化图

想用真美术,只需把 png 丢进本目录,**文件名 = key**,无需改任何代码:

| key | 用途 | 投放文件 |
|---|---|---|
| `darts` | 飞镖房图标/强调 | `assets/darts.png` |
| `lotto` | 刮刮乐房 | `assets/lotto.png` |
| `pachinko` | 柏青哥房 | `assets/pachinko.png` |
| `sushi` | 寿司房 | `assets/sushi.png` |
| `gacha` | 扭蛋房 | `assets/gacha.png` |
| `meta` | 元进度 (NG+) | `assets/meta.png` |
| `ach` | 成就 | `assets/ach.png` |

`FortuneArtBank.texture_for(key)` 先查 `ResourceLoader.exists(assets/<key>.png)`:命中即 `load` 真素材,
缺失才回退程序化图。`source_for(key)` 返回当前来源(`asset` / `procedural`)。

Godot 导入 png 会生成同名 `.import` 边车,连同 png 一并提交即可。

## 音效同理(`sfx/sound_bank.gd`)

`FortuneSoundBank`(P5 5B)是**音效接缝**,默认零音频,所有 SFX 由程序化 `AudioStreamWAV` 合成(确定性,
按 key 的 voice 参数)。想用真音效,把 `wav`/`ogg` 丢进本目录,**文件名 = key**(`wav` 优先):

| key | 用途 | 投放文件 |
|---|---|---|
| `throw` | 投镖 | `assets/throw.wav` |
| `scratch` | 刮刮乐 | `assets/scratch.wav` |
| `pull` | 抽扭蛋 | `assets/pull.wav` |
| `drop` | 落球发射 | `assets/drop.wav` |
| `jackpot` | JACKPOT 中奖 | `assets/jackpot.wav` |
| `clear` | 贿赂过关 | `assets/clear.wav` |

`stream_for(key)` 先查 `assets/<key>.wav` 再 `.ogg`,命中即 `load` 真音频,缺失才回退程序化合成。
播放统一经 `CoreKit.audio.play_sfx`(AudioManager 轮转池)。
