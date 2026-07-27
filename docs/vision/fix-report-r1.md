# 修复报告 R1 ·《晶核防线 Crystal Line》

日期: 2026-07-27
分支: `crystal-line-fix-claude`(example,**不合 main、不 push**)
输入: `TASK-R1.md` 的 8 条缺陷(CL-001 ~ CL-008)
对照: `docs/vision/vision-one-pager.md`(含本轮新增的「愿景演进记录」)

**一句话**: 从「测试全绿但打开没法玩」修到「打开就能打完一局 5–8 分钟的塔防,
每一条修复都有截图或可复跑的数值证据顶着」。

---

## 0. 怎么取证(方法先说清楚)

| 轨 | 做法 | 用来证明什么 |
|---|---|---|
| **截图轨** | 新增 `test/tools/screenshot.gd`:**非 headless** 启动 Godot + `-s` 跑 SceneTree 脚本,进程内 `Viewport.get_texture().get_image().save_png()` 落盘;`test/tools/shots_r1.ps1` 一键批量出 8 张 | 「画面上确实有 / 确实连得上」 |
| **断言轨** | `test_crystal_line_sim.gd`(重写)、`test_crystal_line_layout.gd`(新增)、`test_crystal_line_smoke.gd`(扩写)进 `run_all.ps1` | 「以后改坏了会报警」 |
| **数值轨** | `test/tools/balance_probe.gd`:模拟玩家跑完整局,打印覆盖表 / 时长 / 首波压力 / 站位对照 | 「5–8 分钟 / 有把握的紧张 是数,不是形容词」 |

**没有用** computer-use、没有动真实鼠标键盘、没有用系统截屏工具。
`--headless` 无渲染后端截不到画面,所以截图一律走非 headless 引擎内脚本。

一键复跑:

```powershell
powershell -File test\run_all.ps1            # 正确性门,期望 FAILS=0
powershell -File test\tools\shots_r1.ps1     # 8 张验收截图
godot --headless --path . -s res://test/tools/balance_probe.gd   # 数值探针
```

> 截图工具的两种取景模式:桌面装得下就直接设窗口(`mode=window`);装不下时
> (本机屏幕可用区 1920×1032,放不下 1280 高的窗口)按 `project.godot` 的 stretch 规则
> 算出等价 viewport 尺寸渲染后再缩到目标物理尺寸(`mode=viewport`)——与窗口管线同一条路径。
> 每张图产出时都会打印 `SHOT ... mode=...`,模式是可核对的,不是隐瞒。

---

## CL-001 【严重】竖屏未配置,顶部 HUD 被挤出屏幕 —— 已修

**做了什么**

1. `project.godot` 补 `[display]` 段:基准视口 `720×1280`、`stretch/mode="canvas_items"`、
   `stretch/aspect="expand"`、`handheld/orientation=1`(竖屏)、窗口默认 `540×960`。
2. `main.tscn` 重做布局:根 `VBoxContainer` 只放**可伸缩**内容,棋盘 `Board` 改成
   `size_flags_vertical = EXPAND_FILL` 的空 Control,不再 `custom_minimum_size = 480×768` 硬撑;
   底栏四个按钮改 `size_flags_horizontal = EXPAND_FILL` + 只保留高度下限,窄屏能收、宽屏能撑。
3. `main.gd` 删掉 `custom_minimum_size = Vector2(720, 1280)`,新增 `board_metrics()`:
   **格边长 = min(Board 宽/5, Board 高/8)**,绘制与点击命中共用同一份度量 —— 分辨率变了自动跟随。
4. HUD 从一个 Label 拆成四个带色 Label(晶核 / 金币 / 波次 / 塔数),各自颜色对齐一页纸配色。

**证据(三档分辨率各一张,标题 + 晶核 HP + 金币 + 波次 + 完整 5×8 棋盘 + 全部底部按钮同时可见且不被裁)**

| 分辨率 | 截图 | 模式 |
|---|---|---|
| 720×1280 | `docs/vision/evidence-r1/01-boot-720x1280.png` | viewport |
| 540×960 | `docs/vision/evidence-r1/02-boot-540x960.png` | window |
| 1152×648 | `docs/vision/evidence-r1/03-boot-1152x648.png` | window |

复跑:

```powershell
godot --path . -s res://test/tools/screenshot.gd -- --w=540 --h=960 --out=docs/vision/evidence-r1/02-boot-540x960.png --steps=wait:30
```

**回归护栏**: 新增 `test/test_crystal_line_layout.gd` —— 在 4 种视口尺寸
(720×1280 / 2276×1280 / 540×960 / 1152×648)下把 main.tscn 挂进 SubViewport,断言
11 个必看控件全在视口内、尺寸非零、纵向不重叠,且 5×8 棋盘不被裁、格边长 > 4px。
输出:

```
LAYOUT ok @720x1280 cell=129.0 grid=645x1032
LAYOUT ok @2276x1280 cell=129.0 grid=645x1032
LAYOUT ok @540x960 cell=89.0 grid=445x712
LAYOUT ok @1152x648 cell=50.0 grid=250x400
```

> 顺带修掉一个真实缺陷:底栏按钮原本用固定 `custom_minimum_size = 150` 宽,
> 在 540 宽的裸视口下会把整个根控件撑到 622 宽再居中,把内容推出屏幕两侧——
> 这正是 CL-001 的同款病根(固定像素 + `grow both`),一起换成弹性布局。

---

## CL-002 【严重·流程】体验检查点基于代码自评 —— 已修

**做了什么**: 重写 `docs/vision/experience-checkpoint.md`。新版的规矩写在开头:
**每一条回答必须挂一张 `evidence-r1/` 截图 + 一条任何人可复跑的截图命令**,读代码得出的结论一律作废。
旧版的「体验门通过」结论在文中被显式标记为**已作废**(当时画面连 HUD 都是缺的)。

新版 7 问全部带图:①头 30 秒情绪曲线 ②核心瞬间因果链 ③是否滑向反例 ④再玩一次的钩子
⑤站位小棋感(带可测对照表)⑥三档分辨率可读性 ⑦占位是否承载意图。

**证据**: `docs/vision/experience-checkpoint.md` 本身;它引用的 8 张图都在 `docs/vision/evidence-r1/`。

**诚实标注的边界**(写在新版结论里,没有藏):音频只证明了「被调用播放」没有录音听感;
「5–8 分钟」用的是模拟时钟不是真人秒表;截图是脚本摆拍的确定性状态,不替代真人连玩一局。

---

## CL-003 【中】没有「一局」,再玩一次的钩子未实现 —— 已修

**做了什么**

1. **一局有明确终点**: `CrystalLineSim` 引入 `phase ∈ {prep, wave, victory, defeat}`。
   `WAVES_TO_WIN = 14`,**清完 14 波 = 胜利**;晶核 10 点扣光 = 失败。局终后 `start_wave()` / `place_tower()` 一律拒绝。
2. **一局能自己往前走**: 波间 `prep` 备战倒计时(首波 `PREP_FIRST = 8s`,波间 `PREP_BETWEEN = 6s`),
   到点自动开下一波;玩家可点「立即开波 N」抢时间。这就是一页纸「波间松、波内紧」的节奏。
3. **胜负都有结算展示 + 再来一局**: `main.tscn` 新增 `Result` 覆盖层
   (标题 / 本局统计 / 历史记录 / 「再来一局」按钮),`_finish_round()` 在 phase 变化时弹出。
   本局统计 = 波次、晶核、击杀、漏怪、塔数、赚取金币、用时。
4. **跨局记录**: 历史最好波数 / 通关次数 / 第几局经 `CoreKit.saves` 持久化(见 CL-006)。

**证据**

| 结局 | 截图 | 图上写着 |
|---|---|---|
| 胜利 | `docs/vision/evidence-r1/06-victory-720x1280.png` | 「守住了!」 波次 14/14 晶核 10 击杀 280 漏怪 0 塔 16 座 赚取 4438 金 **用时 5:19** + 「再来一局」 |
| 失败 | `docs/vision/evidence-r1/07-defeat-720x1280.png` | 「晶核破碎」 波次 1/14 晶核 0 漏怪 10 **用时 0:57** + 「再来一局」 |

**headless 断言(验收标准 3)** —— `test_crystal_line_sim.gd`:

- `_victory_path_cl003`:16 塔固定构筑 → `is_victory() == true`,`waves_cleared == 14`。
  输出 `CL-003 通关 waves=14/14 hp=10 kills=280 用时=319s (5:19)`。
- `_defeat_path_cl003`:不建塔 → `is_game_over() == true`、`core_hp == 0`。
  输出 `CL-003 失败路径 wave=2 用时=58s`。
- `_round_guards_cl003`:备战可开波 / 战斗中不可重复开波 / 备战到点自动开波(且首波备战确为 8.0s)/
  局终拒绝开波与建造 / `reset()` 把一局状态清干净。
- `test_crystal_line_layout.gd::_check_result_panel`:开局面板隐藏 → 破核后弹出且含「波次」统计 →
  点「再来一局」面板关闭且回到 `wave=0 / hp=10` 可玩状态。

**验收标准 4 —— 一局时长 5–8 分钟,估算依据**

用 `test/tools/balance_probe.gd` 实测(模拟时钟,`elapsed` 由 sim 自己累加,备战 + 战斗都算):

```
PROBE_BUILD 16 塔固定构筑(截图用)   victory=true waves=14/14 hp=10 towers=16 leaks=0 seconds=319 (5:19)
PROBE_ROUND 贪心站位(每次挑覆盖最大的空格) victory=true waves=14/14 hp=9 towers=20 kills=279 leaks=1 seconds=366 (6:05)
```

拆开看:14 波 × 波间备战(8 + 13×6 = 86s)+ 14 波战斗(≈ 233~280s)= **5:19 ~ 6:05**。
`test_crystal_line_sim.gd` 把这条写成断言:通关局 `300s ≤ elapsed ≤ 480s`,
数值再被人调偏出 5–8 分钟区间就会红。

> 注:这是**模拟时钟**,不是真人秒表——真人还要花时间思考落点,只会更长不会更短,
> 所以 5:19 是这一局时长的**下界**。

---

## CL-004 【中】因果链在画面上是断的;`hit.wav` 是死资源 —— 已修

**做了什么**

1. **谁在打谁**: sim 每 tick 为每座塔**独立锁定当前目标**(不受冷却影响),
   写进 `tower.has_aim / tower.aim`;表现层据此画一条**己方颜色的持续瞄准线** + 目标身上的**同色准心圈**。
   开火瞬间另外记进 `sim.shots`(`from / to / kill / type`),表现层画 0.16s 的**弹道闪光 + 枪口闪**,击杀处加一圈亮闪。
   —— 持续瞄准线保证「随手截一张图都看得出是哪座塔打哪只怪」,不依赖恰好截到开火那一帧。
2. **还差多少**: 每只怪头顶一条血条(宽 = 0.62 格),颜色按 `hp/max_hp` 由绿渐红。
3. **`hit` 不再是死资源**: 命中时经 `_play(&"hit")` 播放(0.09s 节流,避免高频刷屏),
   走 `CoreKit.audio.play_sfx`。`hit` 保留在 `sound_bank.bake_keys()` 里且**确实被用**。
4. 顺带修一个残留 bug:清波 / 局终后塔的 `has_aim` 会残留,画面上出现「对着空气瞄准」的线——
   `_clear_aims()` 在非战斗阶段清掉。

**证据**

- `docs/vision/evidence-r1/04-crossfire-720x1280.png` —— 第 7 波交火:**5 座塔各自一条瞄准线指向被套准心圈的那只怪**,
  15 只怪每只头顶血条(绿→黄→红各不相同),底栏显示「作战中 15」。
- `docs/vision/evidence-r1/05-crossfire-540x960.png` —— 同一状态在小屏下同样可读。
- `docs/vision/evidence-r1/08-prep-1152x648.png` —— 横屏下冰塔的蓝色瞄准线 + 目标血条。

复跑:

```powershell
godot --path . -s res://test/tools/screenshot.gd -- --w=720 --h=1280 --out=docs/vision/evidence-r1/04-crossfire-720x1280.png --steps="gold:9999;place:1,0,fire;place:1,4,fire;place:2,4,fire;place:3,4,ice;place:1,2,fire;place:1,6,fire;sim:130;wave;run:6"
```

**headless 断言**

- `test_crystal_line_sim.gd::_combat_telemetry_cl004`:`shots` 非空、每条弹道起点必须落在某座真实塔上、
  出现过击杀、出现过 `hp < max_hp` 的怪(血量可读)、`hits` 计数增长、清波后不残留 `has_aim`。
- `test_crystal_line_smoke.gd`:在**真实帧**里跑完整流程后断言
  `sfx_plays` 同时含 `ui / place / hit`,且 `hit` 仍在 `bake_keys()` 内。
  实测输出:`smoke towers=2 enemies=0 wave=1 gold=226 hits=3 sfx={ &"ui": 3, &"place": 2, &"hit": 2 } route=corekit art=baked`。

---

## CL-005 【中】路径退化成直线,站位决策名存实亡 —— 已修

**做了什么**

1. 敌人状态从「`row_pos` 单标量沿 `PATH_COL` 直下」改成**沿路点数组行进**:
   `PATH` 是 20 个正交相邻的格子,`enemy.t` 是路程(格),`path_point(t)` 插值出格坐标,
   塔的射程判定改用这个二维坐标。
2. 路径形状(`#` = 路径,`.` = 可建造,晶核在 `(2,7)`):

   ```
   . . # . .
   # # # . .
   # . . . .
   # # # # #      ← 长廊 A
   . . . . #
   # # # # #      ← 长廊 B
   # . . . .
   # # C . .
   ```

   中段两条横向长廊夹住 row4 的四个可建造格:站那儿的一座火塔能**同时覆盖两条长廊共 ~6.4 格路径**;
   而右上角 `(4,0)/(4,1)` 覆盖 **0.0 格**。「放哪一格」不再等价于「放第几行」。
3. **把代价变成可读信息**: 备战阶段在每个空格上画一个**亮点,大小/亮度正比于该格覆盖的路径长度**
   (`sim.coverage_at(col,row,range)`),右上角几乎无亮点。落塔后提示行直接报
   「这一格覆盖 X.X 格路径」。玩家不需要靠踩坑学地图。

**证据(验收标准要的「同数量同类型塔,两种摆法结果显著不同」)**

`test_crystal_line_sim.gd::_placement_contrast_cl005` —— **同样 4 座火塔**,同一套波次:

| 摆法 | 撑过波数 | 漏怪 |
|---|---|---|
| 中路长廊 (0,4)(1,4)(2,4)(3,4) | **4 波全清** | **0** |
| 右上角 (3,0)(4,0)(4,1)(4,2) | 第 2 波破核 | **10** |

测试输出:`CL-005 对照 好站位 waves=4 leaks=0 | 坏站位 waves=2 leaks=10`。
断言:塔数必须相同、坏站位漏怪 ≥ 好站位 + 5、好站位撑过的波数 > 坏站位。

覆盖表(`balance_probe.gd`,火塔射程 1.6,单位 = 格):

```
PROBE_COV row0   1.8   3.2   ##    1.3   0.0
PROBE_COV row1   ##    ##    ##    1.6   0.0
PROBE_COV row2   ##    6.4   4.2   2.9   1.9
PROBE_COV row3   ##    ##    ##    ##    ##
PROBE_COV row4   3.7   4.9   4.9   6.4   ##
PROBE_COV row5   ##    ##    ##    ##    ##
PROBE_COV row6   ##    6.2   3.6   2.6   1.9
PROBE_COV row7   ##    ##    ##    0.5   0.0
```

另有路径自检断言:相邻路点必须正交相邻、不重复、不越界、**转向次数 ≥ 4**(直线化会立刻红)、
最好格与最差格的覆盖差 ≥ 3.0 格。

**画面证据**: `docs/vision/evidence-r1/01-boot-720x1280.png`(蜿蜒路径 + 站位亮点大小差异一眼可见)。

---

## CL-006 【轻·可选】零 dogfood CoreKit —— **做了**

**做了什么**

1. **音效经 `CoreKit.audio.play_sfx`**: `main.gd::_play()` 优先走 `/root/CoreKit` 的 AudioManager
   轮转播放器池;没有 autoload 时回退场景内 `AudioStreamPlayer`(纯离线可跑)。
   当前路由由 `sfx_route` 暴露,启动日志打印 `route=corekit`。
2. **跨局进度经 `CoreKit.saves` 持久化**: slot `crystal_line`,存 `{best_wave, wins, plays}`,
   开局 `_load_record()` 读回,局终 `_finish_round()` 更新并 `save()`。结算面板第三行就是它:
   「历史最好 第 14 波 通关 3 次 第 12 局」。

**证据**

- `docs/vision/evidence-r1/06-victory-720x1280.png` 结算面板第三行(跨局记录已经在画面上)。
- `test_crystal_line_smoke.gd` 断言 `sfx_route == "corekit"`、`CoreKit.saves.has_slot("crystal_line")`、
  存档里 `plays ≥ 1` 且含 `best_wave`。实测 `smoke record={ "best_wave": 12.0, "plays": 5.0, "wins": 0.0 }`。

**没做的**:`KitStats` 统计未接。本 example 的立项目的不是 dogfood kit,
接了音频 + 存档两条已经够证明门面可用;再往上堆会喧宾夺主。

---

## CL-007 【中】开局经济与「2–3 种塔」的承诺打架 —— 已修

**做了什么**

- 起始金 **80 → 100**。火塔 40 + 冰塔 45 = 85,**第一波开始前就能同时拥有火 + 冰各一座**(剩 15 金)。
- 首波压力重调:蜿蜒路径让双塔覆盖更长,首波怪量 7 只 / 每只 23 HP。

**证据**

`balance_probe.gd`:

```
PROBE_FIRST_WAVE fire=true ice=true gold_left=15 leaks=0 hp=10 kills=7 wave_seconds=15.9
```

即:开局标准双塔(火 (1,4) + 冰 (2,4))→ **首波漏怪 0、晶核 10/10 满血、15.9 秒清波**。
对比 R1 之前:1 座火塔清首波 **晶核 10→5(漏 5 只)**。
「有把握的紧张」现在是「稳住但要盯着看」,不是「几乎破核的惊吓」——而且核血就在屏幕最上面(CL-001)。

**headless 断言**(`test_crystal_line_sim.gd`)

- `_economy_cl007`:`START_GOLD ≥ 火 + 冰`,且两座塔都能在 `wave == 0` 时落地。
- `_first_wave_pressure_cl007`:双塔打完第一波必须 `leaks == 0 && core_hp == 10 && waves_cleared == 1`。

> 张力靠后段给,不靠开局劝退:第 9 波起怪血二次加压(`hp = 16 + 7w + (w-8)²×1.2`),
> 贪心站位的参考局也会在末尾掉 1 血(`hp=9 leaks=1`)——「差一格就破核」发生在该发生的地方。

---

## CL-008 【中】晶核位置与愿景文字自相矛盾 —— 已修(**显式愿景演进**)

**判断**: 改**一页纸**,保留「底部晶核」的实现。

理由写在 `docs/vision/vision-one-pager.md` 新增的「愿景演进记录」里,摘要:

- 一页纸同一段里既写「顶部血红晶核」又写「看第一波小怪**从上往下冲**」——**自相矛盾的是文字**。
- 竖屏手游的通行读法是敌人自上而下推进、己方基地在下方靠近拇指,「防线越来越靠近我」的压迫感才成立。
- 代价:放弃「要守的东西在视线最上方」的构图;改由**晶核血环 + 顶部 HUD「晶核 N」**承担同一职责。

**这是一次显式的愿景演进,不是悄悄漂移**:先改一页纸(含日期、原因、代价、不改的部分),再对齐实现与文档。
同一节还记了第二条演进:**路径从中央直线改为蜿蜒折返**(CL-005 的愿景侧)。

**证据**

- 一页纸: `docs/vision/vision-one-pager.md` §愿景演进记录。
- 画面: `docs/vision/evidence-r1/01-boot-720x1280.png` —— 入口在顶行 `(2,0)`,晶核在底行 `(2,7)`,与文字一致。
- 断言: `test_crystal_line_sim.gd::_basics` —— `core_cell() == PATH.back()`、`core_cell().y == ROWS-1`、`PATH[0].y == 0`。

---

## 正确性门 `test/run_all.ps1` —— FAILS=0

新增 `test_crystal_line_layout`,测试总数 33 → **34**。最后几行:

```
test_crystal_line_sim    exit=0 pass=True OK
test_crystal_line_art_bank exit=0 pass=True OK
test_crystal_line_sound_bank exit=0 pass=True OK
test_crystal_line_layout exit=0 pass=True OK
test_crystal_line_smoke  exit=0 pass=True OK

=== demo smoke (--quit-after 60) ===
demo exit=0
demo marker 'all subsystems smoke-tested' : present
...(22 个 demo marker 全部 present)
demo stderr has ERROR: no

=== SUMMARY FAILS=0 ===
```

> 复跑提示:`run_all.ps1` 用 PATH 上的 `godot`。本机 PATH 指向的是可用的标准版;
> 若你的 PATH 上是 mono 版或包装脚本,直接用非 mono 标准版 exe 跑同样的参数即可。

---

## 改动清单

| 文件 | 改动 |
|---|---|
| `project.godot` | 新增 `[display]`:720×1280 基准 / canvas_items+expand / 竖屏 / 窗口 540×960 |
| `game/crystal_line/sim/crystal_line_sim.gd` | **重写核心**:蜿蜒 `PATH` + 路点行进、`phase` 一局流程(备战/波次/胜/负)、`shots`/`has_aim` 开火遥测、`coverage_at()`、`summary()`、起始金 100、14 波胜利条件、后段二次加压 |
| `game/crystal_line/main.gd` | 响应式 `board_metrics()`、四段 HUD、结算面板与再来一局、瞄准线/弹道/枪口闪/敌人血条、站位亮点提示、`hit` 音效节流播放、`CoreKit.audio` 路由 + `CoreKit.saves` 跨局记录、`sfx_plays` 测试接缝 |
| `game/crystal_line/main.tscn` | 布局重做(弹性棋盘 + 弹性底栏)、HUD 拆四段、新增 `Result` 结算覆盖层 |
| `game/crystal_line/README.md` | 补玩法一分钟版与自查命令 |
| `test/tools/screenshot.gd` | **新增** 引擎内截图工具(window / viewport 双模式 + steps 脚本) |
| `test/tools/shots_r1.ps1` | **新增** 8 张验收截图的一键批量脚本 |
| `test/tools/balance_probe.gd` | **新增** 数值探针(覆盖表 / 整局时长 / 首波压力 / 站位对照) |
| `test/test_crystal_line_sim.gd` | 重写,覆盖 CL-003/004/005/007/008 |
| `test/test_crystal_line_layout.gd` | **新增**,守 CL-001 与结算闭环 |
| `test/test_crystal_line_smoke.gd` | 扩写,守 CL-004(hit 真被播)与 CL-006(CoreKit 路由 / 存档) |
| `test/run_all.ps1` | 测试清单 +1(`test_crystal_line_layout`) |
| `test/playtest_crystal_line_session_log.gd` | 跟进新几何与新流程,补 `SESSION_VICTORY` 胜利侧闭环 |
| `docs/vision/vision-one-pager.md` | 底部晶核 / 蜿蜒路径 / 一局的形状 + **愿景演进记录** |
| `docs/vision/experience-checkpoint.md` | 按 CL-002 重写:每条答案挂截图 + 可复跑命令 |
| `docs/vision/fix-report-r1.md` | 本文件 |
| `docs/vision/evidence-r1/*.png` | 8 张验收截图 |

**没碰** `addons/godot-core-kit/`(kit 本体归主线维护)。**未 push、未合 main**。

---

## 截图索引

| 文件 | 拍到什么 |
|---|---|
| `evidence-r1/01-boot-720x1280.png` | 竖屏基准开局:HUD 四段 + 蜿蜒路径 + 站位亮点 + 备战倒计时 + 底栏 |
| `evidence-r1/02-boot-540x960.png` | 小屏竖屏开局,同样全可见 |
| `evidence-r1/03-boot-1152x648.png` | 横屏/桌面,同样全可见不被裁 |
| `evidence-r1/04-crossfire-720x1280.png` | 第 7 波交火:5 条瞄准线 + 准心圈 + 15 条敌人血条 |
| `evidence-r1/05-crossfire-540x960.png` | 同一交火状态的小屏版 |
| `evidence-r1/06-victory-720x1280.png` | 胜利结算:14/14、用时 5:19、历史记录、再来一局 |
| `evidence-r1/07-defeat-720x1280.png` | 失败结算:破核 0:57、再来一局 |
| `evidence-r1/08-prep-1152x648.png` | 横屏交火:冰塔瞄准线 + 敌人血条 |

---

## 仍然没解决 / 明确留下的边界

1. **没有音频听感证据**。只证明了 `hit / place / ui / clear / leak` 在流程中被调用播放,没录音。
2. **没有真人连玩一局的主观验收**。截图是脚本摆拍的确定性状态;5:19 是模拟时钟,不是秒表。
3. **右上角 `(4,0)/(4,1)/(4,7)` 是覆盖 0 的死格**。用站位亮点提示把它变成了可读信息,
   但没有从规则上禁止在那里建塔——保留「玩家可以浪费一座塔」的空间是有意的(复盘欲的一部分)。
4. **`KitStats` 未接**(CL-006 只做了音频与存档两条)。
5. **未做真机 / Android 验证**。本轮只在桌面 Godot 4.7 标准版上取证。
