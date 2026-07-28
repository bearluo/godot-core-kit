---
name: asset-bank
description: Use when a Godot game needs placeholder or baseline art/audio without hand-made assets — set up a deterministic asset "bank" with a drop-in seam, bake real .png/.wav files via a headless Godot tool, and add an AI/real-asset upgrade path per key. The productionize-side companion to vision-first-slice's "placeholders that carry intent."
---

# 资源银行 · 确定性烘焙 + AI 通道

游戏没有手做美术/音效时,用「资源银行」拿到**真的**占位资源文件(不是 runtime 内存兜底,而是能看、能提交、能迭代、能被真/AI 素材按 key 顶替的 `.png`/`.wav`)。

两条腿:

1. **确定性基线**(永远可跑、离线、CI 绿):用 Godot headless 当工具,把 bank 的程序化生成器逐 key 烘焙成真文件写进 `assets/generated/`。
2. **AI/真素材通道**(承载愿景):按 key 把真/AI 素材丢进 `assets/`,自动顶替基线;bank 每 key 产一份 brief(尺寸/调色/参数 + 一句 prompt)当生成简报。

配 `vision-first-slice`:那 skill 说「占位要承载意图」,这 skill 是它的落地工具。

## 核心:三级接缝(取资源的唯一入口)

游戏所有取图/取音都经 bank 的 `texture_for(key)` / `stream_for(key)`,按优先级解析:

| 优先级 | 位置 | 谁产的 | 提交? |
|---|---|---|---|
| 1 | `assets/<key>.png` \| `.wav`/`.ogg` | 手做 / AI 生成的真素材 | 是 |
| 2 | `assets/generated/<key>.png` \| `.wav` | 烘焙器确定性产出(基线) | 是 |
| 3 | 运行时 `_make_image()` / `_make_stream()` | 没烘焙过的新 key 也不崩 | — |

**关键**:生成逻辑集中在 `_make_image()` / `_make_stream()` 一份代码,**烘焙(第 2 级)与运行时兜底(第 3 级)共用同一份 → 零漂移**。`source_for(key)` 返回 `asset` / `baked` / `procedural`,可断言接缝走向(进 kit 门)。

## 一、接入 bank(照模板)

把 `templates/art_bank.gd` / `templates/sound_bank.gd` 复制进你游戏(如 `<game>/gfx/`、`<game>/sfx/`),然后:

- 改 `class_name`(如 `FooArtBank`)、`ASSET_DIR`(指向你游戏的 assets 路径)。
- 填 `PALETTE`(art:key→强调色)/ `VOICES`(sound:key→合成参数),key 对齐你游戏里的动作/对象。
- 游戏里取资源只走 `bank.texture_for(key)` / `bank.stream_for(key)`,别再各处硬 `load`。

bank 是 off-facade `class_name` 类(游戏直接 `new`),不挂 CoreKit 门面,符合 core-kit 依赖纪律。

## 二、烘焙确定性基线(工具:Godot headless)

`bake_assets.gd` 是通用烘焙器,吃 bank 脚本路径,逐 key `Image.save_png()` / `AudioStreamWAV.save_to_wav()` 到各 bank 的 `generated_dir()`,并写 `BRIEF-*.md` 生成简报。在**游戏项目根**跑(从源码跑,不是导出包——`res://` 才可写):

```
godot --headless --path . -s res://.claude/skills/asset-bank/bake_assets.gd -- \
    --art res://<game>/gfx/art_bank.gd \
    --sound res://<game>/sfx/sound_bank.gd
```

(`--art` / `--sound` 各自可选;只烘一种就只给一个。路径按你游戏实际改。)

跑完 `assets/generated/` 下就是真 png/wav + `BRIEF-art.md` / `BRIEF-sound.md`。**把 `generated/` 连同 png 的 `.import` 边车一起提交**(先 `godot --headless --path . --import` 让 Godot 生成 `.import`)。改了 `PALETTE`/`VOICES`/生成算法后,重跑烘焙器刷新基线。

## 三、AI / 真素材通道(承载愿景)

要让某个 key 从「程序化基线」升级成「像成品」:

1. 看 `assets/generated/BRIEF-*.md` 里该 key 的简报(尺寸、主色、波形参数 + 一句 prompt)。
2. 用你的生成工具(图像/音频模型)或找美术,按简报产出该 key 的真素材;**没有工具时,可让 agent 按简报手搓 SVG/像素图或更丰富的程序化图**。
3. 命名成 `<key>.png` / `<key>.wav` 丢进 `assets/`(**不是** `generated/`),连 `.import` 一起提交。
4. 完成——第 1 级自动顶替第 2 级,零改代码。`source_for(key)` 会从 `baked` 变 `asset`。

逐 key 增量升级:今天先升核心瞬间那几个,其余留基线,游戏始终完整可跑。

## 四、进门(gate)

- bank 可 headless 实例化 + 纯 `Image`/样本运算 → 写 `test_<game>_art_bank.gd` / `_sound_bank.gd` 断言 `source_for` 三级走向、`bake_image`/`bake_stream` 非空、尺寸对。
- 可选:烘焙器冒烟——烘到临时 `user://` 目录,断言文件存在且非空。
- **必做**:死资源 / 幽灵 key 检查(见下节)。
- 按 `developing-core-kit`:测试加进 `run_all.ps1`,更新计数。

## 五、死资源 / 幽灵 key 检查(两个方向都要查)

三级接缝有个副作用:**登记与使用是解耦的,两边都能悄悄不一致**。实测踩过:
某游戏的 `sound_bank` 定义并烘焙了 `hit` 音效,产品代码里**从未调用播放**——
全仓 grep 只在 `sound_bank.gd` 自己出现。烘焙产物齐全、测试全绿、
`BRIEF-sound.md` 里有它,看起来「打击音效做好了」,实际游戏全程静音。

⚠️ **死资源最常见的来源:拿调色板当烘焙清单。** `bake_keys()` 图省事写成 `PALETTE.keys()`,
于是**只用来取色**的 key 也被烘成了图。实测:某游戏 7 个 PALETTE key 里,`path` / `cell`
只经 `color_for()` 画 `draw_rect` 根本不需要图,`gold` 连颜色都没人取——3 张 png 照样烘出来、
提交进仓库、写进 BRIEF,一次都没显示过。**调色板与烘焙清单是两个职责**,分成
`PALETTE`(取色)和 `TEXTURE_KEYS`(出图)两份,`bake_keys()` 只返回后者。

| 方向 | 症状 | 为什么危险 |
|---|---|---|
| **烘焙了没人用**(死资源) | key 在 `bake_keys()`,产品代码零引用 | 产出物冒充功能存在;白占仓库与烘焙时间 |
| **用了没登记**(幽灵 key) | 代码 `texture_for(&"typo")`,bank 里没这个 key | 静默落到第 3 级程序化兜底,**不报错**;拼错永远不暴露,也拿不到 AI 升级通道 |

幽灵 key 尤其阴——第 3 级兜底的设计目的是「新 key 也不崩」,代价就是**拼写错误没有任何反馈**。

**做法:让 bank 记录被请求过的 key,在冒烟测试里跑一遍真实流程再对账。**

```gdscript
# bank 侧加两行接缝
var _requested: Dictionary = {}
func texture_for(key: StringName) -> Texture2D:
    _requested[key] = true          # stream_for 同理
    ...
func requested_keys() -> Array: return _requested.keys()
```

```gdscript
# test_<game>_smoke.gd:跑完一段真实游戏流程后对账
var used := bank.requested_keys()
for k in bank.bake_keys():
    if not (k in used) and not (k in ALLOW_UNUSED):
        fail("死资源: %s 烘焙了但流程中从未被取用" % k)
for k in used:
    if not (k in bank.bake_keys()):
        fail("幽灵 key: %s 被取用但未登记,正在吃程序化兜底" % k)
```

- `ALLOW_UNUSED` 是**显式**豁免名单(如只在失败结局才响的音),写进去要附一句理由——
  豁免必须是主动决定,不是默认。
- 冒烟跑不到的分支,补一条静态兜底:全仓 grep 该 key,只在 bank 自身出现即判死。
- 删死资源时**连 `bake_keys()` 登记、`generated/` 产物、`.import` 边车一起删**,
  否则下次烘焙又长回来。
- ⚠️ **别在启动时预热全部资源**(`for k in bake_keys(): stream_for(k)`)——
  那会让 `requested_keys()` 恒等于 `bake_keys()`,这套对账**直接失效**。
  要预热就把预热路径排除在记录之外。
- ⚠️ **取到 ≠ 播出去 / 画出来**。`stream_for(&"hit")` 拿到流,不代表它被 `play` 了;
  `texture_for(&"core")` 拿到图,不代表它被 `draw_texture` 了。要在冒烟里再断一层
  **实际输出记录**,否则死资源会换个姿势活下来:

  | 侧 | 记什么 | 断言 |
  |---|---|---|
  | 音效 | 播放入口累加 `sfx_plays[key] += 1` | 跑完流程后必含 `ui / place / hit` 等关键 key |
  | 美术 | 绘制入口累加 `drawn[key] += 1` | 同上,每个 `bake_keys()` 里的图 key 都要出现过 |

  ⚠️ **两侧要一起做,别只做音效侧。** 实测踩过:音效侧断言得很扎实(`sfx_plays` 三个 key),
  美术侧一条断言都没有——7 个图 key 只在日志里 print 了其中**一个**的 `source_for`,
  剩下 6 个到底有没有画出来无人知晓。音效因为「静音」很扎眼所以先被想到,
  图形的「没画出来」反而更容易被别的元素盖过去。

> 这条同时是 `vision-first-slice` 体验门的一部分:
> 「烘焙了」≠「玩家听得到/看得到」,别拿产出物当体验证据。

## 常见错误

| 错误 | 修法 |
|---|---|
| 烘焙器写不出文件(err) | 必须从**源码**跑(`--path .`),导出包里 `res://` 只读 |
| png 没 `.import` 提交,别处 `load` 失败 | 先 `--import` 生成边车,png + `.import` 一起提交 |
| 真素材丢进 `generated/` | 真/AI 素材丢 `assets/` 根;`generated/` 只放烘焙基线 |
| 生成逻辑在 bake 和 runtime 各写一份 | 只写 `_make_*` 一份,两级共用 |
| bank 里各处硬 `load` 绕过接缝 | 取资源只经 `texture_for`/`stream_for` |
| **`bake_keys()` 写成 `PALETTE.keys()`** | 拆成 `PALETTE`(取色)+ `TEXTURE_KEYS`(出图);只取色的 key 别烘成图 |
| **烘焙了却没人调用(死资源)** | 冒烟对账 `bake_keys()` vs `requested_keys()`;删就删干净 |
| 对账把某个 key 报成死资源,但它其实会用到 | 先查是不是**冒烟流程没走到**(如只放了火塔),补流程比加豁免对 |
| **key 拼错静默吃兜底(幽灵 key)** | 反向对账;第 3 级兜底不报错是设计,不是许可 |
| **拿「已烘焙」当体验做完了的证据** | 烘焙只证明文件在;要证明玩家真听见/看见 |
| **只给音效做了播放对账,美术侧没有** | 两侧都要记实际输出(`sfx_plays` / `drawn`),图形「没画出来」更难察觉 |
