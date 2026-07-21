# Fortune Mill P3 实施计划 · 柏青哥 + 寿司(4 房可通关)

> **执行方式**:主会话内联 TDD(model-first)。全部工作留 `example/fortune-mill` 分支,不并 main。
> 分两阶段:**3A 柏青哥**(本轮)→ **3B 寿司**(下一轮)。每房 model 先行 headless TDD,表现层随后。

**目标**:加第 3 房柏青哥(tickets / Rimmington)+ 第 4 房寿司(ribbons / Hivemind),达成 spec §9 P3「4 房可通关」。两处新架构:柏青哥**真物理与数据分离**、骰子 **DICE 临时全局乘数**;寿司**制作时长 + KitInventory + 解锁式开关协同**。

**验收**(spec §9 P3):4 房各自可攒够 100 万专属货币贿赂守卫;DICE/SUSHI 协同生效;FORTUNE_SMOKE 端到端 PASS;kit 门 run_all FAILS=0。

## 阶段 3A · 柏青哥 Pachinko(tickets / 守卫 Rimmington)

### 架构决策 1:真物理 vs headless 数据分离

spec 要 RigidBody2D 落球(全作唯一真物理),但经济逻辑须 headless 可测。分离:

- **PachinkoRoom model(纯 RefCounted,权威经济)**:槽值表 `SLOT_VALUES` + 加权 RNG `drop_ball()`(落槽→`award_slot`);`auto_ticket_rate()` 用期望值(自动/离线,保在线=离线);`award_slot(slot)` 是权威入账,供物理层落槽回调 **或** `drop_ball` 内部调用。全 headless 可测。
- **物理表现层(juice,仅非 smoke 路径)**:RigidBody2D 球从 `CoreKit.pool` 取、碰钉子、落进底部 Area2D 槽 → 回调 `FortuneMill.pachinko_land(k)` → `award_slot(k)`;碰撞 SFX 走 audio。手动落球走真物理;自动/离线/headless smoke 走 model RNG。在场球数封顶 + 到底即回收。

### 架构决策 2:DICE 临时全局乘数

KitModifiers 是**永久**层,临时 buff 需过期机制,放 model 内:

- PachinkoRoom 持 `_dice_seconds_left`。`roll_dice()`(需 `_dice_meter` 攒够,drops 累积)→ 置 `_dice_seconds_left = DICE_DURATION` + `set_modifier(&"global_mul", &"pachinko_dice", &"mul", DICE_MUL)`。
- `update(dt)`(FortuneMill.tick 调)倒计时,`_dice_seconds_left<=0` → `remove_source(&"global_mul", &"pachinko_dice")`。
- DICE 临时 mul 与 JACKPOT 永久 mul **同 target(global_mul)不同 source_id**,Πmul 里乘性叠加,一起放大全房间。DICE 不持久化(live buff,存档不存)。

### 文件(3A)

| 文件 | 动作 | 责任 |
|---|---|---|
| `defs/pachinko_upgrade_def.gd` | 建 | 升级 schema(镜像) |
| `data/pachinko_balls/*.tres` | 建 | 球值(mul tickets_per_ball)/多球(add balls_per_drop)/自动(add drops_per_sec)/骰子频率(unlock) |
| `systems/pachinko_room.gd` | 建 | slots/加权 drop_ball/award_slot/DICE(roll_dice/update/过期)/升级/auto_ticket_rate/produce/bribe Rimmington/to·from_dict/seed_rng |
| `systems/fortune_state.gd` | 改 | 装配 tickets+pachinko;命令 drop_ball/pachinko_land/roll_dice/bribe_rimmington;存档;离线三房;tick 调 pachinko.produce+update |
| `scenes/world.gd` | 改 | 柏青哥列 UI(落球/骰子 meter/升级/贿赂 Rimmington)+ RigidBody2D 物理 juice(pool+SFX,非 smoke);smoke 扩柏青哥闭环+DICE 跨房断言+Rimmington 过关+三房离线 |
| `test/test_fortune_pachinko.gd` | 建 | drop/升级/DICE 临时 buff 施加+过期+跨房+与 jackpot 乘性叠加/auto 率确定性/bribe/持久化 |
| `test/run_all.ps1` | 改 | 登记 test_fortune_pachinko |
| `examples/fortune-mill/docs/README.md` | 改 | 加 P3 段 |

### 数值(自定)

- `SLOT_VALUES = [50, 5, 1, 5, 50]`,权重 `[1, 4, 10, 4, 1]`(中间常见小值、边缘稀有大值,plinko 式);E[值]=7.5 tickets/球(base)。
- `DICE_MUL = 3.0`,`DICE_DURATION = 10.0` 秒,`DICE_METER_PER_ROLL`(攒够可掷,骰子频率升级降门槛)。
- `BRIBE_COST = 1_000_000.0`(Rimmington)。

### 任务(3A,TDD)

- **T2 数据**:PachinkoUpgradeDef + 4 张 .tres。随 T3 验证。
- **T3 model + 测试**:先写 test_fortune_pachinko → 红 → 实现 pachinko_room.gd → 绿 → commit。断言:①drop_ball 产 tickets 入账 ②球值升级后 auto 率增 ③无自动化 auto 率 0 ④DICE:roll_dice 后 global_mul×DICE_MUL,update 过 DICE_DURATION 后回落 ⑤DICE 与 jackpot 乘性叠加(同 global_mul 两源)⑥跨房:DICE 期间飞镖 auto 率 ×DICE_MUL ⑦auto_ticket_rate 确定性 ⑧bribe Rimmington ⑨持久化 levels(DICE 不持久)。
- **T4 装配+UI+物理**:FortuneMill 接线;world 柏青哥列 + 物理 juice;handle offline 三房。
- **T5 smoke+run_all+提交**:smoke 扩 P3;登记;FAILS=0;FORTUNE_SMOKE PASS(pachinko + dice_boost + rimmington);分批 commit。

## 阶段 3B · 寿司 Sushi(ribbons / 守卫 Hivemind)——下一轮

- **SushiRoom model**:配方 `SushiRecipeDef`(craft_time/ribbon_value/解锁协同效果);`start_craft`/`collect`(制作时长)或自动厨师连续产;食材容器 `KitInventory` 轻量 dogfood;auto_ribbon_rate。
- **解锁式开关协同(SUSHI 型)**:高级配方解锁 → 永久「规则开关」modifier 到别房(如 `throws_per_sec ×2` 或刮刮乐保底),经 KitModifiers 声明式注册,一次性永久。
- 升级:配方解锁/制作速度/自动厨师/ribbon 价值。bribe Hivemind 1M ribbons。
- 测试 test_fortune_sushi + smoke 扩 + UI。达成「4 房可通关」。

## 纪律

headless-first 数据/表现分离(经济纯 RefCounted,物理层只做表现回调 award_slot);UI 只读模型发命令;跨房协同只经 KitModifiers 唯一求值点(DICE/JACKPOT 同 global_mul 乘性叠加);货币全走 Currency;5 货币独立;临时 buff(DICE)不持久化;物理层仅非 smoke 路径实例化(headless 不跑物理);指数层保留不实现。
