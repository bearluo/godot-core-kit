# Fortune Mill P2 实施计划 · 刮刮乐 + 跨房协同

> **执行方式**:主会话内联 TDD(CLAUDE.md「默认主会话直接做」),非 SDD subagent 分发。
> 每任务:写失败测试 → 实现 → 跑绿 → 提交。全部工作留 `example/fortune-mill` 分支,**不并 main**。

**目标**:在飞镖房之上加第 2 房刮刮乐(独立货币 money / 守卫 Gorgon),并用其 JACKPOT 逼定跨房协同的 modifier 形状——JACKPOT 命中永久放大**所有房间**产出,飞镖房经共享聚合器自动生效。

**验收**(spec §9 P2):刮刮乐 JACKPOT 给飞镖房加成生效;FORTUNE_SMOKE 端到端 PASS(飞镖过关 + 刮刮乐闭环 + jackpot 跨房加成断言 + Gorgon 过关);全 kit 门 run_all FAILS=0。

## 架构关键决策:`global_mul` 全局乘数通道

spec §5.6 要三层聚合 `产出_i = base_i(Σadd) × ∏mul [× 指数(预留)]`,全局唯一求值点 = KitModifiers。跨房协同「一个房间的来源放大另一个房间」有两种形状:

1. **枚举式**:JACKPOT 显式往每个房间的 target(`gold_per_dart`/`money_per_card`/…)各注册一条 mul。缺点:JACKPOT 须知道所有房间 target,加房要改 JACKPOT。
2. **全局通道式(采纳)**:新增 target `&"global_mul"`,每个房间产出 `× value_for(&"global_mul", 1.0)`。JACKPOT 只注册**一条** mul 到 `global_mul`,新房只需在自己产出公式里读 `global_mul` 即自动纳入。

采纳 2:更贴 spec「全房间永久乘法层」「全局唯一求值点」,可扩展到 5 房不改 JACKPOT。代价是飞镖房产出公式加 `× global_mul`(2 处,默认 1.0 → 零 jackpot 时完全向后兼容,P0/P1 测试与 smoke 不变)。

**JACKPOT 累积**:KitModifiers 按 `source_id` 覆盖式存(一源一条)。故 jackpot **不**用多源累加,而是 LottoRoom 持权威 `_jackpot_count`(存档),每命中 `set_modifier(&"global_mul", &"lotto_jackpot", &"mul", pow(JACKPOT_MUL, count))`——一条源,值随次数长。`from_dict` 重放(同飞镖升级重放 modifier 的先例)。`JACKPOT_MUL = 1.5`。

**自动化确定性**:`auto_money_rate()` 用中奖表**期望值**(含 jackpot 档的 money 赔付期望),但**不**触发离散 jackpot 副作用(不叠 global_mul)——同飞镖 `auto_gold_rate` 用期望靶心、不触发离散事件的先例,保证在线=离线。

## 文件结构

| 文件 | 动作 | 责任 |
|---|---|---|
| `systems/kit_modifiers.gd` | 改 | 定型:加 `breakdown(target,base)`/`sources(target)` 明细查询;exp 保留(未知 op 忽略) |
| `defs/lotto_upgrade_def.gd` | 建 | 刮刮乐升级 schema(镜像 DartUpgradeDef) |
| `data/lotto_cards/*.tres` | 建 | 5 条升级:卡值(mul money_per_card)/多卡(add cards_per_scratch)/自动刮(add scratches_per_sec)/幸运符(unlock jackpot 权重) |
| `systems/lotto_room.gd` | 建 | 刮刮乐 model:scratch/加权中奖表/JACKPOT→global_mul/升级/auto_money_rate/produce/bribe Gorgon/to·from_dict/seed_rng |
| `systems/darts_room.gd` | 改 | `throw()`/`auto_gold_rate()` × `global_mul`(2 行,默认 1.0) |
| `systems/fortune_state.gd` | 改 | 装配 money+lotto;命令 do_scratch/buy_lotto_upgrade/bribe_gorgon;存档含 lotto/money;离线双房结算(offline_report→per-room);bus money_changed/jackpot_hit |
| `scenes/world.gd` | 改 | 刮刮乐 UI + jackpot·global_mul 指示 + 贿赂 Gorgon;smoke 扩 lotto 闭环 + 跨房加成断言 + Gorgon 过关;offline 横幅改 per-room |
| `test/test_fortune_modifiers.gd` | 改 | 加 breakdown/sources/未知 op 断言 |
| `test/test_fortune_lotto.gd` | 建 | scratch/升级/JACKPOT→global_mul/**跨房放大飞镖 target**/jackpot 持久化/auto 率确定性/bribe/offline |
| `test/run_all.ps1` | 改 | 登记 test_fortune_lotto |
| `examples/fortune-mill/docs/README.md` | 改 | 加 P2 段 |

## 任务(TDD)

- **T13 KitModifiers 定型**:先扩 test_fortune_modifiers(breakdown 结构 / sources 列表 / 未知 op 被忽略)→ 跑红 → 实现 breakdown/sources → 跑绿 → commit。
- **T14 money+数据**:LottoUpgradeDef + 5 张 lotto_cards .tres(照 dart_upgrades 格式)。无独立测试,随 T15 验证。
- **T15 LottoRoom + 飞镖接入**:先写 test_fortune_lotto(见下断言) → 跑红 → 实现 lotto_room.gd + darts ×global_mul → 跑绿 → commit。
  - 断言:①scratch 产 money ②买卡值升级后产出增 ③循环 scratch 命中 jackpot(seed RNG,上限 50k)→ `_jackpot_count≥1` 且 `value_for(global_mul,1)>1` ④**跨房**:jackpot 后 `darts.auto_gold_rate()` 较前 ×JACKPOT_MUL ⑤jackpot 持久化:to_dict→新 LottoRoom.from_dict → global_mul 重放一致 ⑥auto_money_rate 确定性(两次相同)⑦bribe Gorgon 达 1M 阈值 ⑧未买自动化 auto_money_rate=0。
- **T16 FortuneMill 装配**:money/lotto 接线、命令、存档、离线双房。手验 + smoke 覆盖。
- **T17 view+smoke+docs**:world lotto UI;_run_smoke 扩:飞镖过关后 → seed lotto → 记飞镖 auto 率 → scratch 至 jackpot → 断言 global_mul>1 且飞镖率↑ → 买自动刮 + produce 大 dt 时移攒够 1M money → bribe Gorgon → 双房离线结算。PASS 行加 jackpots=/gorgon=。
- **T18 全量**:run_all 登记 + FAILS=0 + FORTUNE_SMOKE PASS + 分批 commit。
- **T19 反哺**(形状定型后,独立 kit cycle on main):KitModifiers → `addons/godot-core-kit/modifiers/` + kit 门 test_kit_modifiers + docs + 版本 0.19.0→0.20.0 + ff-merge main(push 留用户)。同 KitOffline 先例,**不在 example 分支做**。

## 纪律(spec)

headless-first 数据/表现分离(经济逻辑纯 RefCounted 不挂树);UI 只读模型发命令;bus 只广播脏标记不做数值求值;货币全走 Currency 无裸 float;跨房协同不走 bus 累加(避免顺序/重复),只经 KitModifiers 求值。指数层保留不实现(YAGNI,spec §11 待定)。
