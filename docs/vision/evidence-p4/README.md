# 阶段 4 画面证据(2026-07-28)

按 `vision-first-slice` 3.1 的规矩:每条结论挂一张图 + 一条任何人可复跑的命令。
读代码得出的结论一律作废。

引擎:`Godot_v4.7-stable_win64_console.exe`(**非 mono 标准版**),`--path .` 从源码跑,
`test/tools/screenshot.gd` 进程内 `save_png`,不动系统截屏与外设。

⚠️ 本机屏幕装不下 720x1280 窗口,四张图都是 `mode=viewport`(按 project.godot 的 stretch
规则渲染后缩到目标尺寸,与窗口管线同一条路径)。SHOT 输出行记了模式。

⚠️ `--steps` 里的 `place:` 走的是 **`_try_place`(玩家点格子那条路)**,不是直接调
`sim.place_tower`。摆拍走后门就证明不了前门能用——直接调 sim 会绕过「点已有塔 = 升级」
的分支,升级效果永远进不了截图,而那正是本轮要取证的东西。

## 01-upgrade-levels.png — 升级可见、造价递增

同一格连点即升级:(1,4) 三个金点 = Lv4,(2,4) 两点 = Lv3,(0,4) 一点 = Lv2;
射程圈随等级变大。底栏「火塔 114 / 冰塔 128」= 造价随已有塔数递增(基础价 40/45)。

```
godot --path . -s res://test/tools/screenshot.gd -- --w=720 --h=1280 \
  --out=docs/vision/evidence-p4/01-upgrade-levels.png \
  "--steps=gold:6000;select:fire;place:1,4;place:2,4;place:0,4;place:3,4;place:1,2;place:2,2;place:1,4;place:1,4;place:1,4;place:2,4;place:2,4;place:0,4;sim:6;wave;sim:22;wait:8"
```

## 02-boss-warning.png — 重潮预警(备战窗口)

状态行:「备战 4.8s → ⚠ 第 4 波是【重潮】(6 只厚甲)。攒钱升塔,别硬扛。」
这是「波间松」里那个**有得选**的决策点:现在买,还是攒钱扛下一波。

```
godot --path . -s res://test/tools/screenshot.gd -- --w=720 --h=1280 \
  --out=docs/vision/evidence-p4/02-boss-warning.png \
  "--steps=gold:3000;select:fire;place:1,4;place:2,4;place:0,4;place:3,4;place:1,4;place:2,4;sim:52;wait:6"
```

## 03-boss-combat.png — 重潮交火(数量减半、单只厚甲)

「第 4 波【重潮】作战中 — 场上 2 只,还剩 4 只未出」:全波仅 6 只(普通波同期 12 只),
血条明显更长。瞄准线指出哪座塔在打哪只怪(因果链)。

```
godot --path . -s res://test/tools/screenshot.gd -- --w=720 --h=1280 \
  --out=docs/vision/evidence-p4/03-boss-combat.png \
  "--steps=gold:3000;select:fire;place:1,4;place:2,4;place:0,4;place:3,4;place:1,4;place:2,4;sim:58;wait:6"
```

## 04-result-attribution.png — 结算归因

结算面板第三行:「**第 1 波开始漏怪 —— 下一局在那之前就要补火力。**」
改前这里只有「漏怪 10」,玩家知道输了但不知道该改什么,「再来一局」只是重开、不是复盘。

```
godot --path . -s res://test/tools/screenshot.gd -- --w=720 --h=1280 \
  --out=docs/vision/evidence-p4/04-result-attribution.png \
  "--steps=select:fire;place:4,0;place:4,1;sim:120;wait:10"
```

> 图里「历史最好 / 通关次数 / 第 N 局」来自本机累积的 `CoreKit.saves` 存档,
> 跨机复跑这三个数会不同,不是回归。

## 这几张图证明不了什么

- **不能替代真人连玩一局**:摆拍的是确定性状态,证明的是「该有的东西都在、因果链连得上」。
- 数值手感的取证在 headless 侧:`test/test_crystal_line_feel.gd`(回归门)
  与 `test/tools/feel_probe.gd`(量数据、`--sweep` 扫参数网格)。
- 音频仍无听感证据,只断言了播放调用。
