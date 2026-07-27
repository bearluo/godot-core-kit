# 交付报告 · 用 vision-first-slice + asset-bank 从零做《晶核防线》

分支: `rpg-mobile-game`(example,**不并 main、不 push**)

## ④ 一句结论(为什么适合手游)

**Green TD / Element TD 系塔防最适合迁移进手游:单指点格子即完成全部操作、波次天然切成 5–8 分钟短局、竖屏「上进下核」路径几乎零改造,且决策在构筑不在微操——与 Warlock/Pudge/MOBA 等吃瞄准与走位的图形成对照。**

## 验收物对照

| # | 交付 | 路径 |
|---|---|---|
| ① | 愿景一页纸 | `docs/vision/vision-one-pager.md` |
| ①b | 调研与选型 | `docs/vision/wc3-dota-mobile-fit.md` |
| ② | 手感切片(抛弃式) | `game/slice/feel_slice.tscn` |
| ②b | 生产可玩场景 | `game/crystal_line/main.tscn` |
| ②c | headless 冒烟 FAILS=0 | `test/test_crystal_line_*.gd` |
| ③ | 烘焙占位 + BRIEF | `game/crystal_line/assets/generated/`(7 png + 6 wav + BRIEF-*.md) |
| ④ | 手游适配结论 | 见上 + `wc3-dota-mobile-fit.md` |
| 体验门 | 检查点 | `docs/vision/experience-checkpoint.md` |

## 四阶段走查

1. **阶段 0 愿景** — 选定路径塔防;填 X-statement/头30秒/核心瞬间/反例/再玩理由。
2. **阶段 1 手感切片** — `game/slice/` 只做「点格放塔→反馈→清波」;判定核心瞬间成立。
3. **阶段 2 productionize** — `CrystalLineSim` 纯逻辑 + `CrystalArtBank`/`CrystalSoundBank` 三级接缝 + `bake_assets.gd` 真文件基线。
4. **阶段 3 体验检查点** — 对照愿景纸,非仅 FAILS=0;见 experience-checkpoint.md。

## 自测命令

```
godot --headless --path . -s res://test/test_crystal_line_sim.gd
godot --headless --path . -s res://test/test_crystal_line_art_bank.gd
godot --headless --path . -s res://test/test_crystal_line_sound_bank.gd
godot --headless --path . -s res://test/test_crystal_line_smoke.gd
# 烘焙
godot --headless --path . -s res://.claude/skills/asset-bank/bake_assets.gd -- \
  --art res://game/crystal_line/gfx/art_bank.gd \
  --sound res://game/crystal_line/sfx/sound_bank.gd
```

最近一次: **4/4 ALL PASS, FAILS=0**; bake DONE baked=13; `source_for` 显示 `baked`。

## Skill 有效性观察

- **vision-first-slice**: 强制 Phase 0 避免一上来建「完整 TD 系统」却不知好玩点;核心瞬间收窄切片范围极有效。
- **asset-bank**: 同一 `_make_*` 供 bake/runtime,BRIEF 给 AI 升级通道;测试可断言 `source_for` 走向。
- 配套:生产逻辑与表现分离(`sim/`)使 headless 不依赖场景树。
