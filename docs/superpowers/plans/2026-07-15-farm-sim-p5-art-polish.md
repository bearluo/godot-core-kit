# farm-sim P5 · 美术替换 + 数值平衡 + 手感抛光 实现计划

> **执行方式:** 主会话 inline 执行。每 Task 独立可测,结尾一次 headless 断言 + 一个 F5 检查点;
> 做完 1-2 个停下让需求方 F5。设计见 `docs/superpowers/specs/2026-07-15-farm-sim-p5-art-polish-design.md`。

**Goal:** 把 farm-sim 从色块占位升级到程序化像素观感 + 粒子/动画手感 + 有节奏的经济,真素材可无缝换入。

**Architecture:** 美术接缝 `art_bank.gd`(程序化贴图 + `assets/` 真素材覆盖),renderer 从 draw_rect 换贴图;
逻辑/表现分离不变(model 一行不改)。平面俯视。

## Global Constraints(每 Task 隐含遵守)

- **分支纪律**:改动留 `example/farm-sim`,不升版本、不合 main、push 留用户。不碰 kit 内部、不动旧 game.gd/tscn。
- **GDScript 坑**:RHS 来自无类型注入对象用 `var x =`,不用 `:=`。缩进 Tab。
- **零二进制资产**:P5 仍不引入二进制素材;贴图全程程序化,真素材接缝先搭好、先空着。
- **验收门**:每 Task 结尾 `run_all` FAILS=0;`FARM_SMOKE=1` 跑 world.tscn 打印 `[Farm][SMOKE] PASS`。
- **git**:每 Task 一 commit,message 结尾 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`,
  Bash heredoc。

## 美术接缝 API(Task 1 建立,全局契约)

`examples/farm-sim/art_bank.gd`(extends RefCounted,静态方法 + `static var _cache`):

```
const TILE := 32
const ASSETS_DIR := "res://examples/farm-sim/assets/"
static func tex(key: StringName) -> Texture2D   # 先查 assets/<key>.png(真素材优先),否则程序化 + 缓存
static func clear_cache() -> void
```

逻辑 key:`tile_grass`/`tile_tilled`/`tile_watered`、`crop`(通用作物贴图,view 按 ratio 缩放+着色)、
`player_<dir>_<frame>`(dir∈down/up/left/right,frame∈0/1)、`npc`、`bed`/`shop_sign`/`door_h`/`door_v`、
`fx_star`/`fx_drop`/`fx_dust`/`fx_gold`(粒子点纹理)。

## 文件结构

| 文件 | 责任 | Task |
|---|---|---|
| `examples/farm-sim/art_bank.gd` | 程序化贴图 + 真素材接缝 | 1 |
| `examples/farm-sim/assets/README.md` | 真素材摆放约定(key→文件名→尺寸) | 1 |
| `examples/farm-sim/farm_grid_view.gd` | 地块/作物换贴图 | 1 |
| `examples/farm-sim/player.gd` | 精灵 + 走路动画 | 2 |
| `examples/farm-sim/npc.gd` / `door.gd` / `house_area.gd` / `town_area.gd` | 物件换贴图 | 2 |
| `examples/farm-sim/fx.gd` | 粒子反馈 helper | 3 |
| `examples/farm-sim/farm_state.gd` | 玩法动作发粒子信号 + 转场缓动 | 3 |
| `examples/farm-sim/data/{crops,items}/*.tres` | 数值平衡 | 4 |
| `test/test_art_bank.gd` | art_bank 逻辑测(非 run_all) | 1 |

---

### Task 1: 美术接缝 + 地块/作物贴图化

- [ ] **Step 1:** 写 `art_bank.gd`:`tex(key)` 接缝(assets/ 优先 + 缓存);程序化生成器画 `tile_grass`/
  `tile_tilled`/`tile_watered`(32² 底色 + 网格边 + 噪点/描边)、`crop`(带叶片形状的绿色小株)。
  用 `Image`+`ImageTexture`。headless 安全(已探针验)。
- [ ] **Step 2:** 写 `assets/README.md`:key→文件名(`<key>.png`)→尺寸(瓦片 32²、作物 32²、玩家 24² 等)
  约定;说明"放进来即覆盖程序化贴图,零改代码"。
- [ ] **Step 3:** `farm_grid_view.gd`:`_draw` 从 `draw_rect(tile_color)` 改 `draw_texture_rect(ArtBank.tex(tile_key), rect, false)`;
  作物从 `draw_rect` 改 `draw_texture_rect(ArtBank.tex(&"crop"), crop_rect)` + `modulate`(绿→金)保留 ratio 缩放。
- [ ] **Step 4:** 写 `test/test_art_bank.gd`(SceneTree,运行时 load):断言各 key `tex()` 返回非空 Texture2D +
  尺寸正确 + 缓存命中(两次同 key 返回同实例)+ 未知 key 回退不崩。ALL PASS(不进 run_all $tests)。
- [ ] **Step 5:** import + test_art_bank ALL PASS + `FARM_SMOKE` PASS + `run_all` FAILS=0。
- [ ] **Step 6:** commit `feat(farm-sim P5): 美术接缝 art_bank + 地块/作物贴图化（程序化,真素材可换入）`。

---

### Task 2: 玩家/NPC/物件精灵化 + 走路动画

- [ ] **Step 1:** `art_bank.gd` 加生成器:`player_<dir>_<frame>`(4 向 × 2 帧,身体 + 朝向 + 踏步差异)、
  `npc`(带轮廓小人)、`bed`/`shop_sign`/`door_h`/`door_v`。
- [ ] **Step 2:** `player.gd`:`_draw` 改画 `ArtBank.tex(player_<dir>_<frame>)`;`_physics_process` 里按移动
  距离累加切 frame(0/1)+ 轻微上下 bob;静止回 frame 0、bob 归零。朝向由 facing 定 dir。
- [ ] **Step 3:** `npc.gd`:色块 `_draw` 换 `ArtBank.tex(&"npc")`(名字 Label 保留)。`door.gd`:换 door_h/door_v 贴图。
- [ ] **Step 4:** `house_area.gd`/`town_area.gd`:床/商店牌 `_draw` 换 `bed`/`shop_sign` 贴图(地板/地面可保留纯色或轻纹理)。
- [ ] **Step 5:** import + `FARM_SMOKE` PASS + `run_all` FAILS=0;**F5**(与 Task1 合并批次):地块/作物/玩家/NPC/物件都是贴图,
  走路有踏步动画。
- [ ] **Step 6:** commit `feat(farm-sim P5): 玩家/NPC/物件精灵化 + 走路踏步动画`。

---

### Task 3: 粒子 + 交互反馈 + 转场缓动

- [ ] **Step 1:** `art_bank.gd` 加粒子点纹理 `fx_star`/`fx_drop`/`fx_dust`/`fx_gold`(小圆/星点)。
- [ ] **Step 2:** 写 `fx.gd`:`static func burst(parent, world_pos, kind)`——按 kind(harvest/water/till/gift)建
  一次性 `CPUParticles2D`(设 texture/颜色/数量/lifetime/one_shot/emitting),挂 parent、`finished` 或定时自 free。
- [ ] **Step 3:** 粒子触发接线:农田 view 或 world 订阅 model 动作。做法——`Farm` 新增 signal `fx_requested(kind, cell)`,
  `use_tool_on` 成功时 emit(harvest/water/till);农田场景连该信号 → `Fx.burst(self, grid.cell_to_world(cell)+中心, kind)`。
  送礼/解锁在对话/世界层触发 gift 粒子(可选,时间紧可略)。
- [ ] **Step 4:** 交互反馈:用工具时目标格 tween scale/描边"顿一下"(TargetHighlight 或 view 短 tween)。
- [ ] **Step 5:** 转场缓动:`Farm.fade()`/`slide()` 加 `t.ease_type = Tween.EASE_IN_OUT`、
  `t.trans_type = Tween.TRANS_CUBIC`。
- [ ] **Step 6:** import + `FARM_SMOKE` PASS(粒子/信号不崩)+ `run_all` FAILS=0;**F5**:收获爆星、浇水水花、
  耕地尘土,用工具有顿挫,转场更顺。
- [ ] **Step 7:** commit `feat(farm-sim P5): 粒子反馈 + 交互顿挫 + 转场缓动`。

---

### Task 4: 数值平衡

- [ ] **Step 1:** 重调作物 `.tres`(白萝卜→土豆→防风草→南瓜→星之果)的 grow_days/harvest_amount +
  对应 seed item buy_price / produce sell_price,成一条日均利润递增、回本周期拉长的曲线。
- [ ] **Step 2:** 重估 `Farm.ACTION_COST`(体力)、`WATER_UPGRADE_COST`、shop 起始金币(现 500)、起始种子配给,
  与新作物价匹配。
- [ ] **Step 3:** 在 spec §5 或 README 记一版数值表。
- [ ] **Step 4:** import + `FARM_SMOKE` PASS(smoke 里数量/价格断言若写死,同步更新)+ `run_all` FAILS=0;
  **F5**:玩一日循环,经济节奏合理(不太快暴富、不太肝)。
- [ ] **Step 5:** commit `feat(farm-sim P5): 作物经济曲线重平衡（数值调优）`。

---

### 收尾(全部 Task 后)

- [ ] `world.gd`/`farm_state.gd`/renderer 顶部 docstring 更新(贴图/动画/粒子)。
- [ ] spec `2026-07-14-farm-sim-game-design.md` 的 **P5 checklist** 勾 `[x]`(美术替换 + 数值平衡 + 手感抛光三项;
  2.5D 那项留 `[ ]` 标注后置)+ 标题按完成度标注。
- [ ] 更新 memory `farm-sim-trio-plan.md` / `MEMORY.md`:记 P5 完成 + 美术接缝架构。
- [ ] F5 总验收;提示需求方在 `example/farm-sim` 自行 push。

## Self-Review 记录

- **Spec 覆盖**:§2 接缝→Task1;§3 美术→Task1/2;§4 抛光→Task2(动画)/Task3(粒子/反馈/缓动);§5 数值→Task4;
  §6 测试(test_art_bank + FARM_SMOKE)贯穿。无遗漏。
- **风险**:headless 贴图/粒子已探针验证不崩(2026-07-15);renderer 换贴图不碰 model,smoke 逻辑断言照旧;
  真实观感留 F5。真素材接缝先空着,不阻塞。
- **类型一致**:`ArtBank.tex(key)->Texture2D`、`Fx.burst(parent,pos,kind)`、`Farm.fx_requested(kind,cell)` 各 Task 引用一致。
