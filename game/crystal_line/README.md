# 晶核防线 (Crystal Line)

Green TD / Element TD 系路径塔防的手游竖屏 example。验证 `vision-first-slice` + `asset-bank`。

## 玩法一分钟版

- 竖屏 5×8 棋盘,一条**蜿蜒**裂隙路径从顶部裂口折返而下,终点是**底部晶核**(10 点血)。
- 选火塔(40)/ 冰塔(45)→ 点路径旁的空格落塔。开局 100 金,够同时买下火 + 冰各一座。
- 备战倒计时归零自动开波(首波 8 秒,波间 6 秒),也可点「立即开波」抢时间。
- **清完 14 波 = 守住;晶核扣光 = 破核。** 两种结局都进结算,结算上是「再来一局」。
- 备战阶段格子上的**亮点越大 = 该格覆盖的路径越长**——站位是真决策(见 `docs/vision/fix-report-r1.md` CL-005 对照)。

## 运行

```
godot --path . res://game/crystal_line/main.tscn
```

## 截图 / 数值自查

```powershell
powershell -File test\tools\shots_r1.ps1                              # 批量出验收截图(引擎内 save_png)
godot --headless --path . -s res://test/tools/balance_probe.gd        # 数值探针:覆盖表 / 整局时长 / 站位对照
```

## 目录

| 路径 | 作用 |
|---|---|
| `sim/crystal_line_sim.gd` | 纯逻辑(headless 可测) |
| `gfx/art_bank.gd` | 美术三级接缝 |
| `sfx/sound_bank.gd` | 音效三级接缝 |
| `assets/generated/` | bake_assets.gd 烘焙基线 |
| `main.tscn` | 生产场景(HUD / 棋盘 / 底栏 / 结算面板) |
| `../../test/tools/screenshot.gd` | 引擎内截图工具(非 headless,进程内 save_png) |
| `../../test/tools/balance_probe.gd` | 数值探针(整局时长、首波压力、站位对照) |

## 烘焙资源

```
godot --headless --path . -s res://.claude/skills/asset-bank/bake_assets.gd -- \
  --art res://game/crystal_line/gfx/art_bank.gd \
  --sound res://game/crystal_line/sfx/sound_bank.gd
```

## 愿景

见 `docs/vision/vision-one-pager.md`。
