# farm-sim P5 · 美术替换 + 数值平衡 + 手感抛光 设计

> 状态:方向与范围已获需求方认可(2026-07-15)。承接 P0-P4(分支 `example/farm-sim` @fbf13e1)。
> 继续建在 core-kit 上;**保持平面俯视**(2.5D 留作后续独立项)。实现计划见
> `docs/superpowers/plans/2026-07-15-farm-sim-p5-art-polish.md`。

## 1. 目标

把 farm-sim 从"色块占位"升级到**有质感的像素观感 + 有反馈的手感 + 有节奏的经济**,三块并进:
①美术替换 ②手感抛光 ③数值平衡。**逻辑/表现严格分离的既有架构不动**——只升表现层与数据,
model(FarmGrid / KitInventory / shop / clock 等)一行不改。

## 2. 关键架构:美术接缝(art seam),真素材可无缝换入

farm-sim 至今**零二进制资产**(全程程序化占位),使 `run_all` 的 `--import` 扫全工程干净、
headless 可测。P5 要"换真像素素材"但**素材来源待定**,故采用**接缝方案**:

- **`art_bank.gd`**(RefCounted,静态,缓存;对标 `audio_bank.gd`):用 `Image` + `ImageTexture`
  **代码生成**全部贴图(瓦片/作物/角色/物件),零二进制资产。
- **取图接缝 `ArtBank.tex(key)`**:先查 `res://examples/farm-sim/assets/<key>.png`——**存在就用真素材**
  (`load` 进来),否则回退程序化贴图。renderer 只认逻辑 key,不认来源。
- **效果**:现在=程序化贴图(比色块好看、headless 全绿);以后=把 Sprout Lands 等 PNG 按约定命名
  丢进 `assets/`,**零改代码**自动生效。`assets/README.md` 记录 key→文件名→尺寸约定。
- **headless 安全性已验**(2026-07-15 探针):`ImageTexture.create_from_image` / `AtlasTexture` /
  `CPUParticles2D` / `Sprite2D` 在 headless dummy 驱动下均正常创建、不崩。

## 3. 美术替换(renderer 换贴图,平面俯视不变)

所有 renderer 从 `draw_rect` 改为经接缝拿 `Texture2D` 画。逻辑 key 一览:

| 对象 | key | 程序化生成 |
|---|---|---|
| 地块 | `tile_grass`/`tile_tilled`/`tile_watered` | 32² 底色 + 网格边 + 轻噪点/描边质感 |
| 作物 | `crop_<id>_<stage>` 或通用按 ratio 着色 | 小苗→成株,绿→金,成熟高亮(沿用现映射,改画贴图) |
| 玩家 | `player_<dir>_<frame>` | 24² 身体 + 朝向 + 走路 2 帧踏步 |
| NPC | `npc_<id>` 或通用 | 色块升级为带轮廓的小人贴图 + 名字 Label |
| 物件 | `bed`/`shop_sign`/`door` | 各自占位贴图 |

- **FarmGridView**:逐格 `draw_texture_rect(ArtBank.tex(tile_key), rect)`;作物同理叠一层作物贴图。
  仍是薄 renderer,读 model、零逻辑。
- **player.gd**:`_draw` 改挂/画贴图 + 走路帧(见 §4 动画)。TargetHighlight 保留描边(高亮语义清晰)。
- **npc.gd / door.gd / house/town `_draw`**:换贴图。

## 4. 手感抛光

- **玩家走路动画**:移动时 2 帧踏步(按 `_frame`/距离切帧)+ 轻微上下跳(offset);静止回 idle 帧。
  纯 offset/切帧,不引入 AnimationPlayer(占位阶段够用,真素材来了可换 AnimatedSprite2D)。
- **粒子反馈**(`CPUParticles2D`,程序化点纹理,one_shot):收获→爆"星星"、浇水→蓝水花、
  耕地→棕尘土、送礼/解锁→金光。挂在目标格/玩家位置,发一次自回收。
- **交互反馈**:用工具时目标格 tween 一下 scale/描边"顿一下";买卖/升级时 HUD 数字轻微跳动(可选)。
- **转场缓动**:门转场的 `KitTransition` 加 `ease_type`/`trans_type`(如 EASE_IN_OUT + TRANS_CUBIC),
  比线性顺滑。FADE/SLIDE 参数微调。

## 5. 数值平衡

纯数据(`.tres`)+ 少量常量,低风险。目标:一条"低门槛起步 → 逐级高投入高回报"的作物曲线,
让"卖钱→买更好种子→升级工具→解锁星之果"的经济循环有节奏。

- **作物曲线**(种子价 / 成熟天 / 售价 / 每株产量,给出粗值,F5 手感微调):
  白萝卜(便宜/2天/低/×3)→ 土豆(中/3天/中/×2)→ 防风草(中/4天/中高/×1)→ 南瓜(贵/秋限/5天/高/×1)
  → 星之果(解锁专属/4天/顶级/×1)。保证每级"日均利润"递增但回本周期拉长。
- **体力/工具**:动作耗体力(现 8)、水壶升级价(现 200)、起始金币(现 500)按新作物价重估。
- 调完在 spec/README 记一版数值表,便于后续再平衡。

## 6. 测试策略

- **headless 门不变**:`FARM_SMOKE` 仍 PASS(贴图/粒子生成不崩——已探针验证;renderer 换贴图不碰 model,
  smoke 断言照旧)。`run_all` FAILS=0(farm 测独立于 kit 门,Farm autoload 惰性)。
- **art_bank 逻辑测**(可选):新 headless 测断言 `ArtBank.tex(key)` 各 key 返回非空 `Texture2D`、
  尺寸正确、真素材覆盖优先级(assets/ 存在时用真素材)。
- **真实观感留 F5**:动画/粒子/贴图在 headless dummy 驱动不渲染,每批 F5 目测。

## 7. 分支与工作流

全部改动留 `example/farm-sim`,**不升版本、不合 main、push 留用户**。P5 若暴露 kit 缺口(如需要通用
精灵动画/粒子子系统),记"反哺候选"分支分流,不在 P5 改 kit。旧 dogfood game.gd/game.tscn 不动。

## 8. 范围与非目标(YAGNI)

- **做**:程序化贴图 + 真素材接缝、地块/作物/角色/物件贴图化、走路动画 + 粒子反馈 + 转场缓动、
  作物经济曲线重平衡。
- **不做(后置)**:2.5D 方格 3/4 视角(独立大改,后续单独立项);真实 AnimationPlayer 骨骼动画;
  昼夜光照(游戏内时钟恒 6:00);采矿/钓鱼等 P4 深水区。真素材本身由需求方后补(接缝已就位)。

## 9. 开放/待定(不阻塞开写)

- 程序化贴图的精细度 → 够"比色块明显好看"即可,不追像素艺术;真素材来了整体换掉。
- 数值具体数字 → 先给粗值,F5 手感微调后定表。
- 粒子密度/时长 → 占位值,抛光时调。
