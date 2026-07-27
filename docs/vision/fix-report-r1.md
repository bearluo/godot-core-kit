# 修复报告 R1 ·《晶核防线 Crystal Line》

日期: 2026-07-27  
分支: `crystal-line-fix-grok`  
对照: `TASK-R1.md` · `docs/vision/vision-one-pager.md`

---

## 硬性规则自检

| 规则 | 状态 |
|---|---|
| `test/run_all.ps1` → `FAILS=0` | ✅ 见文末 SUMMARY |
| 截图用引擎内非 headless 脚本 | ✅ `test/tools/screenshot.gd` |
| 未碰 `addons/godot-core-kit/` | ✅ |
| 未 push / 未合 main | ✅ |
| 本报告 + commit | ✅ |

---

## CL-001 竖屏与 HUD 可见

**做了什么**

- `project.godot` 增加 `[display]`: viewport **720×1280**、`canvas_items` stretch、`aspect=expand`、handheld **portrait**。
- `main.tscn` 改为 `MarginContainer` + 可伸缩 `Board`(去掉硬编码 480×768 最小高度),标题 / Info / 棋盘 / 底栏 / Hint 同屏共存;格子尺寸按 Board 可用区域自适应。

**证据**

| 分辨率 | 截图 |
|---|---|
| 540×960 | `docs/vision/fix-r1-evidence/hud-540x960.png` |
| 720×1280 | `docs/vision/fix-r1-evidence/hud-720x1280.png` |
| 1152×648 | `docs/vision/fix-r1-evidence/hud-1152x648.png` |

三图均可同时看见:标题「晶核防线」、晶核 HP / 金 / 波次、完整 5×8 蜿蜒棋盘、全部底栏按钮。

**复跑**

```text
godot --path . -s res://test/tools/screenshot.gd -- --out=docs/vision/fix-r1-evidence/hud-720x1280.png --size=720x1280 --scenario=boot
```

---

## CL-002 体验检查点基于真实画面

**做了什么**

- 重写 `docs/vision/experience-checkpoint.md`:每条检查附截图路径 + 可复跑 `screenshot.gd` 命令。

**证据**:见该文件表格与命令块。

---

## CL-003 一局闭环(胜/负 + 再来一局)

**做了什么**

- `CrystalLineSim`: `WIN_WAVES = 8`;清完 = `outcome=victory`;核破 = `outcome=defeat`。
- UI: `ResultOverlay` 结算(击杀/漏怪/赚金/波次)+ **「再来一局」**。
- headless: 通关路径 + 无塔失败路径断言。

**证据**

- 测试输出: `OK victory_path waves=8` / `OK defeat_path outcome=defeat`
- 截图: `docs/vision/fix-r1-evidence/result-defeat.png`(晶核 0 · 已结束 · 再来一局)
- 局时长估算: `estimate_session_seconds()` → **约 5.24 分钟**(构筑 20s×8 + 波内刷怪/行进);落在 5–8 分钟量级。依据写在 `sim.estimate_session_seconds()` 与测试 FAIL 11 旁证。

---

## CL-004 交火因果链 + hit 音效

**做了什么**

- 开火写入 `shots[]` 短时射线;主场景按塔类型着色绘制塔→敌连线。
- 敌人绘制 **HP 条**(红底条)。
- `hits_this_tick > 0` 时播放 `hit`(`CoreKit.audio.play_sfx` 优先,否则本地 `AudioStreamPlayer`)。

**证据**

- `docs/vision/fix-r1-evidence/combat-shots.png`:左下火塔橙线指向路径敌;敌上红血条。
- 测试: `OK combat_shots hits=1 shots=1`

---

## CL-005 蜿蜒路径 · 站位决策

**做了什么**

- 直线 `PATH_COL` 改为 16 格 **S 形 PATH**(spawn 底 → 晶核顶)。
- 塔射程对敌人连续路径坐标计算;不同摆法覆盖路径长度不同。

**证据(可测对照)**

```text
OK placement_matters good_leaks=0 bad_leaks=13 delta=13
```

同 2 座火塔、跑 2 波:贴长弯外侧漏 0;右下死角落漏 13。

---

## CL-006 零 dogfood CoreKit(可选)

**做了什么(轻量)**

- 音效优先 `CoreKit.audio.play_sfx(stream)`,无 CoreKit 时回退本地播放器。
- **未**做跨局 `CoreKit.saves` 持久化(可选范围;报告声明即可)。

---

## CL-007 开局经济 · 双塔体验

**做了什么**

- `START_GOLD = 100`(火 40 + 冰 45 = 85,余 15)。
- 首波敌 HP 微调 + 双塔合理站位:测试断言 **能清波且 leaks ≤ 3**。

**证据**

- `placed-dual.png`:塔 2、金 15(同时拥有火+冰)。
- 测试: `OK first_wave_dual_tower leaks=0 hp=10`

---

## CL-008 晶核与愿景一致(顶部)

**做了什么**

- 实现: `CORE_CELL = (2,0)` 路径终点 = **顶部**晶核;敌人自底部涌入。
- 愿景:一页纸「从上往下冲」→「沿蜿蜒裂隙涌向顶部晶核」(显式演进,见 checkpoint)。

**证据**:所有 `hud-*.png` / `combat-shots.png` 顶部红晶核。

---

## 主要改动文件

| 路径 | 说明 |
|---|---|
| `project.godot` | display 竖屏 + stretch |
| `game/crystal_line/sim/crystal_line_sim.gd` | 路径/胜负/经济/shots |
| `game/crystal_line/main.gd` / `main.tscn` | 布局/结算/交火绘制/音效 |
| `test/test_crystal_line_sim.gd` | 新断言 |
| `test/tools/screenshot.gd` | 引擎内截图工具 |
| `docs/vision/vision-one-pager.md` | CL-008 显式演进 |
| `docs/vision/experience-checkpoint.md` | 画面证据版 |
| `docs/vision/fix-r1-evidence/*.png` | 截图落盘 |

---

## `run_all.ps1` 摘要

```text
test_crystal_line_sim    exit=0 pass=True OK
test_crystal_line_art_bank exit=0 pass=True OK
test_crystal_line_sound_bank exit=0 pass=True OK
test_crystal_line_smoke  exit=0 pass=True OK
...
=== SUMMARY FAILS=0 ===
```

(完整跑于本 worktree: `powershell -File test/run_all.ps1`,exit 0。)
