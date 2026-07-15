# 美术 · 手感 · 音效

P5 把 farm-sim 从色块占位升级到程序化像素观感 + 有反馈的手感,**逻辑一行没动**(model/view 分离,见 [architecture.md](architecture.md))。平面俯视,2.5D 明确后置为独立项目。

## 美术接缝 `gfx/art_bank.gd`

全部贴图**程序化生成**(`Image` + `ImageTexture`,确定性:坐标哈希非 RNG),零二进制资产——对标 `gfx/audio_bank.gd` 的程序化 SFX。取图接缝:

```gdscript
ArtBank.tex(key: StringName) -> Texture2D
# 先查 res://examples/farm-sim/assets/<key>.png(真素材优先),否则程序化生成,结果缓存
```

renderer 只认逻辑 `key`、不认来源。逻辑 key:`tile_grass`/`tile_tilled`/`tile_watered`、`crop`(view 按生长比例缩放 + `modulate` 绿→金)、`player_<dir>_<frame>`、`npc`、`bed`/`shop_sign`/`door`、`fx_star`/`fx_drop`/`fx_dust`/`fx_gold`。

headless 安全:`ImageTexture`/`AtlasTexture`/`CPUParticles2D` 在 dummy 驱动下均正常创建(已探针验)。测试 `test/test_art_bank.gd`。

### 真素材 drop-in(零改代码)

把真像素包(首选 **Sprout Lands**,免费可商用不可转售)的 PNG 按 `assets/README.md` 的 `key → 文件名 → 尺寸` 约定命名,丢进 `examples/farm-sim/assets/`,即覆盖对应程序化贴图,**无需改任何代码**。这就是"先搭骨架、后换真素材"的落地。

## 走路动画 `scenes/player.gd`

移动时按累计距离切**踏步 2 帧**(`_walk_frame` 交替)+ 轻微上下 `_bob`,静止回静止帧。朝向由 facing 定 `dir`(up/down/left/right)。`_draw` 画 `ArtBank.tex("player_<dir>_<frame>")`。

## 粒子 `gfx/fx.gd`

```gdscript
Fx.burst(parent, world_pos, kind)
# 按 kind 建一次性 CPUParticles2D(one_shot/emitting),finished 自 queue_free
```

kind → 效果:`harvest` 金星上迸 / `water` 蓝水花 / `plant` 浅绿碎屑 / `till` 褐色尘土。

**接线**:`Farm.use_tool_on` 成功时 emit `fx_requested(kind, cell)`;`scenes/world.gd` 连该信号 → `Fx.burst` 到格中心 + `TargetHighlight.punch(cell)`。依旧 model/view 分离——逻辑只发信号,表现层订阅。

## 交互顿挫 `scenes/target_highlight.gd`

用工具命中格:`punch(cell)` 触发白框向外扩散、约 0.25s 淡出的"顿一下",敲击有反馈。

## 转场缓动

`Farm.fade()` / `slide(dir)` 返回的 `KitTransition` 设 `ease_type = EASE_IN_OUT` + `trans_type = TRANS_CUBIC`(默认 `TRANS_LINEAR` 生硬)。`scene_manager` 用 `set_ease/set_trans` 应用。

## 音效 `gfx/audio_bank.gd`

静态函数**程序化合成** `AudioStreamWAV`(正弦 + 指数衰减包络 SFX、四音循环 BGM),零二进制资产,headless dummy 驱动不崩。各动作(耕/种/浇/收/买/卖/睡)点播,经 `CoreKit.audio`。设置面板 `ui/settings_panel.gd` 有音量 `HSlider`。

## 本地化 `gfx/i18n_strings.gd`

内存现建现加(`Translation.new` + `add_message` → `CoreKit.i18n.add_translation`,免 `.po` 导入),中/英切换。UI/作物/季节/天气名全 key 化。设置面板切语言,`locale` 落 `CoreKit.settings`("locale" 分区,跨存档偏好),`locale_changed` 延迟重建活动面板。键位重绑定同理走 `CoreKit.input` + `KitRebindList`。
