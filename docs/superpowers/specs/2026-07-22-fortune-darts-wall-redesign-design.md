# 飞镖房「墙面 + 全屏进入房」重构设计（Fortune Grinder v2: Wall）

> 分支：`example/fortune-mill`（**永不并 main / 不 push**）。范围：仅 Room 1 飞镖房。其余 4 房、跨房协同、经济内核、成就/统计一律不动。

## 背景与目标

上一版把飞镖房做成「横版命运转盘」：`model` 自持 `wheel_angle` 匀速旋转，飞镖扎上即按指针落点结算。用户反馈落点**忽前忽后**（旋转带来的时序不确定），且希望：

- 玩家**控制发射角**→ 确定命中哪一档（落点确定，不再忽前忽后）。
- 飞镖走**抛物线**扎进墙面奖区。
- 金币**落地堆积** + **间隔批量收集**（不是立刻飞计数器，也不卷走空中金币）。
- 从世界**进入式全屏房**玩（`CoreKit.scenes` + 转场切场景），退出回世界。

核心认知不变：这仍是 incremental，真交互只是金币复利循环的**点火 + 油门**，不是独立手速小游戏。**换皮不换核**：经济/升级/贿赂/离线/存档/成就全保。

## 关键洞察：模型层只改两行

现有 `FortuneWheelLayout.landing(aim,power)` 已返回 `{r, a_off}`，`DartsRoom.throw` 已算 `hit_angle = wheel_angle + a_off + fans[i]` → `segment_at(hit_angle, win_bonus)`。把「转盘」换成「墙」只需：

1. **`landing()` 的 `a_off` 铺满整圈**：原 `a_off = (aim-0.5)*AIM_ARC`（仅 ±60°）。冻结旋转后 ±60° 只够得到 4 档、够不到 vermin/x100 → 必须让 `aim∈[0,1]` 线性铺满 `[0,360)`：`a_off = clampf(aim,0,1) * (360.0 - EPS)`。`r`（`power` → 径向）**不变**。
2. **冻结旋转**：`DartsRoom.update()` 变为 no-op，`wheel_angle` 恒 0 → `hit_angle = a_off + fans[i]`，命中档**只由发射角决定** = 落点确定。

其余全部**原样保留**：`segment_at` / `radial_bonus` / `expected_mult` / `fan_offsets` / `throw` / `auto_gold_rate` / `produce` / `buy_upgrade` / `bribe*` / `to_dict/from_dict`。8 档的 `name/mult/vermin` 不变 → `dart_seg_*` 统计键、51 条成就、升级 id、`SCHEMA_VERSION=4` 全不动，**无需存档迁移**。

### 8 档保留 + 重排为竖直墙栈

保留全部 8 档（churn 最小）。仅把 `SEGMENTS` **数组顺序**重排成一面自上而下的墙（`segment_at` 按累加 span 判定，与顺序无关；`jackpot_center/vermin_center` 自动重算；`expected_mult` 求和与顺序无关）。建议墙栈（top→bottom，实现时可在实时编辑器内微调，和≡360）：

| # | name | span | mult | 语义 |
|---|------|------|------|------|
| 1 | x20a | 40 | 20 | 蓝·较易 |
| 2 | x2a | 72 | 2 | 绿·最易（最宽） |
| 3 | x100 | 30 | 100 | 橙·较难 |
| 4 | jackpot | 18 | 500 | 金·最难（最窄，居中上） |
| 5 | vermin | 40 | 0 | 红·劫（没收，紧邻头奖=风险/回报相邻） |
| 6 | x5 | 58 | 5 | 紫 |
| 7 | x2b | 62 | 2 | 绿 |
| 8 | x20b | 40 | 20 | 蓝 |

难度来自**档窄**（jackpot 18°/360°≈5% 的 aim 容差），与位置无关；vermin 是离散没收带。

### 新增静态辅助 `aim_for(name) -> float`

`aim_for(n)` = 该档中心角 / 360，返回能确定命中该档的 `aim` 值。用于 smoke / 测试 / view 预览。满足 `segment_at(aim_for(n)*360, 0)["name"] == n`。

### steady_hand / aim_steady（顺手接线，view 手感）

`steady_hand` 升级现写入 `aim_steady`（模型不读=悬空）。本轮在 **view** 接上：`aim_steady` 越高 → 抛物线落点散布越小、力度甜区越宽（纯表现，模型结算不受影响，保持确定性）。可选任务。

## 视图层：全屏墙面房（新场景）

新场景 `examples/fortune-mill/scenes/darts_room.tscn` + `darts_room_view.gd`（`Control`，全屏 1152×648）。**读 `FortuneMill.darts` / `FortuneMill` 命令层**，把此前几轮迭代的原型表现（`proto_boss_stage.gd`）接到真 model：

- **构图**：左侧投掷者小人 / 中部 8 档奖墙（带纵深/透视感，非纯平面）/ 右侧守卫 Verminous 铁门。顶部金币计数、贿赂价签。
- **投掷**：复用 `FortuneDartsInput`（双端）+ `KitStateMachine` 投掷态机（Idle/Aim/Charge/Resolve）。玩家控**发射角**（aim）+ **蓄力**（power）→ `FortuneMill.do_throw(aim, power)`。
- **命中确定性**：view 用 `hits[i].seg` 决定飞镖扎进**哪条带**的屏幕 Y；抛物线是表现，落点由 model 权威档决定（视觉必与结算一致）。
- **金币**：命中处迸射金币 → 重力落地 → 堆积（`rest`）→ **每 `COLLECT_INTERVAL` 秒批量收集地上金币飞向计数器**（`seek`）；**空中金币不被卷走**（原型已修正的 rest-only 收集）。
- **升级/贿赂**：升级按钮 → `FortuneMill.buy_dart_upgrade(id)`（真扣真升，读 `level_of/cost_of`）；贿赂按钮 → `FortuneMill.bribe_guard()`（真 1M 过关，发 `fortune:room_cleared`）。升级技能树（`proto_upgrade.gd` 那套）读真等级/花费。
- **返回**：返回按钮 → 切回 `world.tscn`。

### 进入 / 退出（fortune-mill 首次场景切换）

`world.gd` 飞镖房那一列不再内联转盘+投掷控件，改为：金币/状态摘要 + 一个「进入飞镖房」按钮。点击：

```gdscript
await CoreKit.scenes.change_scene(
    "res://examples/fortune-mill/scenes/darts_room.tscn",
    {"transition": CoreKit.scenes.Transition.FADE})
```

墙面房返回：`change_scene("res://examples/fortune-mill/scenes/world.tscn", {"transition": FADE})`。

- **状态存活**：全部状态在 `FortuneMill` autoload，跨 `current_scene` 替换天然存活（farm-sim 农场/农舍/小镇切场景已验此模式），无需传参。
- **`_WheelView` + 投掷 FSM + `FortuneDartsInput`** 从 `world.gd` **迁入** `darts_room_view.gd`；`world.gd` 只保留其余 4 房 + 飞镖摘要 + 进入按钮。迁移时确保其余 4 房的 `_process`/刷新/bus 订阅不受影响。
- **风险点（须验）**：切回 `world.tscn` 会重建 hub 并重跑 `_ready`（重新 `CoreKit.bus.subscribe` + 可能重弹离线弹窗）。旧 world 节点被 `queue_free`，其订阅回调随之失效——须确认 `CoreKit.bus` 对失效 callable 的处理（farm-sim 场景切换已在用 bus，视为先例；实施时以 run 验证无重复订阅/无脏引用）。

## 测试与冒烟

改了几何/旋转语义，必须同步（`test/` 在仓库根，非 example 目录）：

- **`test/test_fortune_wheel.gd`**：
  - FAIL7（landing）：`a_off` 现铺满整圈——`aim=0.5 → a_off≈180`（不再 ≈0）；`aim=0 → a_off≈0`；`r` 断言（甜点 power → r≈0、偏离更大）不变。
  - 新增：`aim_for(n)` 往返——对若干档 `segment_at(aim_for(n)*360, 0)["name"] == n`。
  - 新增：冻结旋转——`wheel_angle` 恒 0（`update(dt)` 后仍 0）；同 `(aim,power)` 两次 `landing` 全等（确定性）。
  - FAIL2/3/4（jackpot/win_bonus/vermin，用 `jackpot_center/vermin_center`）、FAIL5/6/8（expected/radial/fan）**不变**。
- **`test/test_fortune_darts.gd`**：把依赖 `wheel_angle` 的断言改为 aim 驱动（`throw(aim_for(jackpot), POWER_SWEET)` 单镖 = base1×500×radial2 = 1000；`throw(aim_for(vermin), …)` = 0）。经济断言（升级、多镖、AI 期望、离线=在线）不变。
- **`world.gd` `_run_smoke`**：`wheel_ok/vermin_ok` 及 P0 爬 1M 段——把「设 `wheel_angle`」换成「设 aim」：`fm.do_throw(FortuneWheelLayout.aim_for(&"jackpot"), POWER_SWEET)` 期望 gold=1000/seg=jackpot；vermin 同理 =0。P1 自动/离线段不变。
- **run_all**：无新增测试文件，仅重写 → 断言总数保持 **39**，`=== SUMMARY FAILS=0 ===`。冒烟新标记可加 `wall=jackpot1000/vermin0`（替代旧 `wheel=...`）。

## 验收

1. `powershell -File test\run_all.ps1` → `=== SUMMARY FAILS=0 ===`（39 测 + demo 冒烟 stderr 干净）。
2. `FORTUNE_SMOKE=1` 世界启动 → PASS，含 `wall=jackpot1000/vermin0`。
3. 实时编辑器 run：世界点「进入飞镖房」→ 淡入全屏墙房 → 控发射角+蓄力投抛物线 → 扎进 model 判定的档 → 金币落地间隔收集 → 升级真扣、贿赂真过关 → 返回淡出回世界，其余 4 房状态无损。

## 约束（不变）

headless-first / 数据表现分离 / 不用大数库（float + Currency）/ 在线=离线 / example 只在本分支不并 main / 提交署名用 example 惯例。
