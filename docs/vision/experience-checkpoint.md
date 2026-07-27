# 体验检查点 · 晶核防线(阶段 3 · R1 画面证据版)

对照 `vision-one-pager.md`。**每一条回答附引擎内截图路径 + 可复跑命令**；不凭读代码自评。

截图工具: `test/tools/screenshot.gd`（**非 headless**，进程内 `root.get_texture().get_image().save_png`）。

通用命令模板:

```text
godot --path . -s res://test/tools/screenshot.gd -- --out=<path> --size=<WxH> --scenario=<boot|placed|combat|result_defeat>
```

---

## 检查问题

| # | 问题 | 答案 | 画面证据 |
|---|---|---|---|
| 1 | 头 30 秒是否感到「有把握的紧张 → 笃定 → 松一口气」? | **是**:开局金 100 可同时落火+冰;放塔 juice 闪白+召唤音;清波白闪+琶音;首波双塔漏怪 0(headless 断言)。 | `docs/vision/fix-r1-evidence/placed-dual.png`(火+冰同场,金 15);`combat-shots.png`(交火) |
| 2 | 核心瞬间是否就是最好玩的部分? | **是**:点格放塔有反馈;波内可见**哪座塔在打哪只怪**(射线)+血条。 | `combat-shots.png`:底部火塔橙线连向路径上敌,敌上红血条 |
| 3 | 有没有滑向反例(微操/沙盒/纯放置)? | **没有**:无走位无技能;蜿蜒路径使站位影响漏怪;仅火/冰。 | `hud-720x1280.png` 蜿蜒裂隙;测试 `placement_matters good_leaks=0 bad_leaks=13` |
| 4 | 会不会想再玩一次? | **会**:胜/负均有结算面板 +「再来一局」;失败文案对齐「差一格/一种塔」。 | `result-defeat.png` |
| 5 | 占位是否承载意图? | **是**:配色/火三角/冰菱形/顶部血红晶核与一页纸一致;HUD 三分辨率均完整。 | `hud-540x960.png` / `hud-720x1280.png` / `hud-1152x648.png` |

### 复跑命令(与上表证据一一对应)

```text
# CL-001 HUD 三分辨率
godot --path . -s res://test/tools/screenshot.gd -- --out=docs/vision/fix-r1-evidence/hud-540x960.png --size=540x960 --scenario=boot
godot --path . -s res://test/tools/screenshot.gd -- --out=docs/vision/fix-r1-evidence/hud-720x1280.png --size=720x1280 --scenario=boot
godot --path . -s res://test/tools/screenshot.gd -- --out=docs/vision/fix-r1-evidence/hud-1152x648.png --size=1152x648 --scenario=boot

# 双塔开局 + 交火因果 + 失败结算
godot --path . -s res://test/tools/screenshot.gd -- --out=docs/vision/fix-r1-evidence/placed-dual.png --size=720x1280 --scenario=placed
godot --path . -s res://test/tools/screenshot.gd -- --out=docs/vision/fix-r1-evidence/combat-shots.png --size=720x1280 --scenario=combat
godot --path . -s res://test/tools/screenshot.gd -- --out=docs/vision/fix-r1-evidence/result-defeat.png --size=720x1280 --scenario=result_defeat
```

---

## 显式愿景演进

1. **晶核在顶部**(与一页纸一致);敌人自路径底部 spawn 沿蜿蜒裂隙涌向顶部晶核。将「小怪从上往下冲」改为「沿蜿蜒裂隙涌向顶部晶核」(见 `vision-one-pager.md` 头 30 秒)。这是显式对齐 CL-008,不是悄悄漂移。
2. **一局 8 波通关**作为胜利终点,支撑「5–8 分钟」与「再来一局」钩子。

---

## 结论

**体验门通过(example 深度 · 有画面证据)。** 正确性门: `powershell -File test/run_all.ps1` → `SUMMARY FAILS=0`。
