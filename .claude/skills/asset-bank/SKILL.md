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

**音效可以用 gdfxr 调**:[gdfxr](https://github.com/timothyqiu/gdfxr)(纯 GDScript 编辑器插件,MIT)在编辑器里像 sfxr 一样随机、调参生成复古音效,存成 `.sfxr`,导入后就是标准的 `AudioStreamWAV`,运行时不依赖插件。两种接法:在 gdfxr 面板里导出成 `<key>.wav` 放进 `assets/`(零改代码);或者直接把 `<key>.sfxr` 放进 `assets/`,在 sound bank 第 1 级的真素材查找里加上 `.sfxr` 扩展名。

## 四、进门(gate)

- bank 可 headless 实例化 + 纯 `Image`/样本运算 → 写 `test_<game>_art_bank.gd` / `_sound_bank.gd` 断言 `source_for` 三级走向、`bake_image`/`bake_stream` 非空、尺寸对。
- 可选:烘焙器冒烟——烘到临时 `user://` 目录,断言文件存在且非空。
- 按 `developing-core-kit`:测试加进 `run_all.ps1`,更新计数。

## 常见错误

| 错误 | 修法 |
|---|---|
| 烘焙器写不出文件(err) | 必须从**源码**跑(`--path .`),导出包里 `res://` 只读 |
| png 没 `.import` 提交,别处 `load` 失败 | 先 `--import` 生成边车,png + `.import` 一起提交 |
| 真素材丢进 `generated/` | 真/AI 素材丢 `assets/` 根;`generated/` 只放烘焙基线 |
| 生成逻辑在 bake 和 runtime 各写一份 | 只写 `_make_*` 一份,两级共用 |
| bank 里各处硬 `load` 绕过接缝 | 取资源只经 `texture_for`/`stream_for` |
