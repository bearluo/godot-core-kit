# godot-core-kit DI 容器设计:KitContext —— 节点绑定的层级服务定位器

- 日期:2026-07-09
- 状态:已批准,待实现
- 目标版本:**0.5.0**(新增能力 → minor;`plugin.cfg` / `CoreKit.VERSION` / `test_core_kit` 断言三处同步)
- 相关既有设计:`2026-07-09-corekit-dir-restructure-design.md`(core / systems / state_machine 分层)

## 1. 背景与目标

core-kit 现有的跨子系统协作靠 `core_kit.gd:_ready()` 里手写的 `bind_*(dep)` 注入,配上"子系统之间禁止互相 `preload`"的硬纪律——这本身就是一套写死、闭合的轻量 DI(10 个子系统固定、3 条依赖边固定,门面知道每一条边)。

本设计**不改这套内部接线**,而是**新增一个对外开放的扩展容器**:让使用 core-kit 的游戏代码把自己的服务注册进来、按 key 解析,并支持随场景树层级作用域化。把 CoreKit 从"10 个写死的子系统"扩成"游戏可扩展的服务容器"。

核心决策(经交互式头脑风暴逐条锁定):

1. **形态 = 服务定位器**(注册 + 按 key 取,pull-based,零魔法),不是自动装配 / 完整 IoC 容器。GDScript 无反射,越自动越靠字符串硬凑、失败态越多。
2. **容器绑定到节点**:容器就是场景树上的节点,容器树 = 场景树的投影(只有挂了容器的节点参与),复用 `get_parent()` 链,不另造平行树。
3. **解析 = 层级回退 + shadow**:从解析发起节点向上找最近容器,逐层 miss 向上回退,树顶兜底到 CoreKit 全局根;子层同名 key 自动覆盖(shadow)父层。
4. **生命周期 = 树驱动**:容器随节点销毁自动回收,无手动 `dispose` 失败态。
5. **内置强类型属性一字不动**:`CoreKit.log/.audio/...` 保留(补全 + 类型);内置额外按 key 预注册进全局根,使 `service("audio")` 及任意作用域向上可达(层级语义在树顶自洽)。
6. **Node 服务归属**:`provide` 只存引用不动树;`provide_child` 显式收养为子节点、归容器管生命周期。

## 2. 非目标(YAGNI 边界)

- **不做自动装配**:容器不解析服务间依赖、不做拓扑排序注入。消费方 pull(自己 `service(key)` 取)。
- **不做完整 IoC**:无接口→实现绑定、无 singleton/transient 作用域枚举、无构造期自动解析。
- **不做类型/Script 键**:v1 只支持 `String` 键。Script/class_name 键留作将来可选增量,不在本轮。
- **不做密封容器(C 语义)**:默认全部层级回退;"某容器可标记密封、截断向上"是 A 之上的可选增量,将来按需再加,本轮不做。
- **不内建解析缓存**:`resolve` 每次向上走 `get_parent()` 链。热路径由游戏代码在 `_ready` 里 pull-and-cache(取一次存成员),容器不代劳。
- **不引入 autoload / 不改 `plugin.gd`**:KitContext 是 `class_name` 类库(off-facade),不注册 autoload。

## 3. 术语

- **全局根(global root)**:CoreKit 门面自身持有的一张服务表 `_services`。作用域 = 整个进程。内置子系统预注册于此。
- **作用域容器(KitContext)**:`class_name KitContext extends Node`,挂在场景树任意子树根。作用域 = 该子树,生命周期 = 该节点。
- **shadow(遮蔽)**:子容器注册了与祖先/全局同名的 key 时,子树内解析优先命中子容器的版本。

## 4. 架构总览

```
addons/godot-core-kit/
  di/
    kit_context.gd        新增:class_name KitContext extends Node —— 作用域容器 + 向上解析
  core_kit.gd             改:新增全局根 _services + provide/service/has/service_or;_ready 预注册内置
```

`di/` 与 `state_machine/` 平级——都是 `class_name` 类库,游戏代码直接 `new()` / 挂节点使用,不经门面属性。分层上属于 off-facade 的第三类(`core/` < `systems/` < 类库 `state_machine/` `di/`)。

容器树与场景树的关系(容器树 = 加粗节点):

```
/root
├── CoreKit (autoload)         ← 全局根 _services(内置 + 全局 provide)
└── CurrentScene
    └── **LevelCtx (KitContext)**   ← 关卡作用域
        ├── Enemy
        │   └── **EnemyCtx (KitContext)**  ← 实体作用域,parent_ctx = LevelCtx
        └── Hud
```

`EnemyCtx.service(k)`:本层 miss → `LevelCtx` → 仍 miss → CoreKit 全局根。注意 **CoreKit 是 CurrentScene 的兄弟、不是游戏节点的祖先**,故树顶兜底是显式调用 CoreKit,不靠字面祖先链。

## 5. API 规格

### 5.1 CoreKit 全局根(`core_kit.gd`,纯增量)

```gdscript
const RESERVED_KEYS := ["log","settings","bus","scenes","pool","saves","ticker","input","audio","res"]
var _services: Dictionary = {}   # key:String -> service:Variant

func provide(key: String, svc: Variant) -> void
# 注册到全局根。key 属 RESERVED_KEYS → push_error 拒绝(保护内置);
# 重复 key → push_warning 后覆盖。

func service(key: String) -> Variant
# _services 命中返回;miss → push_error("CoreKit.service('%s'): 未注册") + 返回 null。
# 这是整条解析链唯一的"未找到"报错点。

func has(key: String) -> bool          # 不报错的存在性检查
func service_or(key: String, fallback: Variant) -> Variant   # miss 返回 fallback,不报错
```

`_ready()` 现有 `bind_*` 之后、`log.info` ready 横幅之前,预注册内置(直接写 `_services`,不走 `provide`,避免保留键自拒):

```gdscript
_services["log"] = log
_services["settings"] = settings
# ... 其余 8 个,顺序同 RESERVED_KEYS
```

### 5.2 KitContext(`di/kit_context.gd`,新增)

```gdscript
class_name KitContext
extends Node

var _local: Dictionary = {}          # key:String -> service:Variant
var _parent_ctx: KitContext = null   # 最近的严格祖先容器,_enter_tree 重算

func provide(key: String, svc: Variant) -> void
# 只存引用,绝不 reparent。重复 key → push_warning 后覆盖。
# 允许 shadow 任意祖先/全局 key(含内置),这是作用域覆盖的用途。

func provide_child(key: String, node: Node) -> void
# 显式收养:node 必须无父(否则 push_error 且不注册);add_child(node) 后 _local[key]=node。
# node 随本容器 free 而被 Godot 连带释放。

func service(key: String) -> Variant
# 解析:_local 命中→返回;否则 _parent_ctx 存在→委托父容器;否则→全局根兜底。见 §6。

func has(key: String) -> bool                                # 沿链(本层→父→全局)存在性,不报错
func service_or(key: String, fallback: Variant) -> Variant   # 沿链 miss 返回 fallback,不报错
```

生命周期回调:

```gdscript
func _enter_tree() -> void
# 重算 _parent_ctx = 从 get_parent() 向上第一个 is KitContext 的节点(严格祖先,不含自己)。
# reparent 也触发 _enter_tree,故依赖关系自动跟随。

func _notification(what: int) -> void
# what == NOTIFICATION_PREDELETE 时 _local.clear()。
# 关键:用 PREDELETE 不用 _exit_tree —— _exit_tree 在 reparent 时也触发,会误清注册表。
# provide_child 的子节点无需手动 free,Godot 释放本节点时连带释放。
```

### 5.3 静态助手(供非容器节点解析)

```gdscript
static func of(node: Node) -> KitContext
# node 自身是 KitContext 则返回自身,否则向上找最近祖先容器;树中无容器 → null。
# 注意与 _parent_ctx 的区别:of() 含自身,_parent_ctx 是严格祖先。

static func resolve(node: Node, key: String) -> Variant
# c := of(node);c 存在→c.service(key);否则→全局根兜底(经 node.get_tree() 定位 CoreKit)。
```

## 6. 解析语义(完整算法)

`KitContext.service(key)`:

```
1. _local.has(key)        → 返回 _local[key]
2. _parent_ctx != null    → 返回 _parent_ctx.service(key)      # 递归向上,逐层可 shadow
3. 否则                    → 返回 _global(key)                  # 树顶兜底
```

`_global(key)`(KitContext 私有,**duck-typed、零类型耦合**):

```
t := get_tree()
t == null            → 返回 null            # 容器未入树时,仅本层可用
ck := t.root.get_node_or_null("CoreKit")
ck == null           → 返回 null            # 隔离单测场景无 autoload,优雅降级
否则                  → 返回 ck.service(key) # 命中内置/全局 provide;真 miss 由此处 push_error
```

要点:

- **单一报错点**:整条链只有 `CoreKit.service` 在真 miss 时 `push_error`;中间层 miss 静默向上,不刷屏。
- **shadow**:子容器 `provide` 同名 key 即在子树内覆盖父层/全局(含内置,如 boss 房覆盖默认 `"spawner"`)。
- **保留键仅约束全局根**:`CoreKit.provide` 拒绝写 10 个内置 key;`KitContext.provide` **不**受此限——子层 shadow 内置正是特性。
- **KitContext → CoreKit 依赖**:仅树顶兜底经节点查找 duck-typed 调用 CoreKit,单向、不引入类型耦合,与"人人可用 `CoreKit.log`"的全局链一致,不违反子系统依赖纪律。

## 7. 生命周期与节点归属

| 入口 | 是否动树 | 生命周期归属 | 容器销毁时 |
|---|---|---|---|
| `provide(key, obj)` | 否,只存引用 | 归游戏(obj 的父/释放是游戏的事) | 仅从 `_local` 丢引用,不 free obj |
| `provide_child(key, node)` | 是,`add_child` 收养(要求无父) | 归容器 | node 作为子节点被 Godot 连带 free |

想让作用域服务随容器释放:要么用 `provide_child`,要么自己把 Node `add_child` 到该 KitContext 后再 `provide`(ref-only)。容器绝不"偷偷" reparent 已在树上别处的节点——保持框架"显式"气质。

## 8. 关键引擎坑与对策

1. **PREDELETE vs `_exit_tree`**:disposal 走 `NOTIFICATION_PREDELETE`;`_exit_tree` 在 reparent 时也触发,不能用来清注册表。
2. **`class_name` 缓存**:首次引用 `KitContext` 的脚本须先跑一次 `godot --headless --path . --import` 生成全局类缓存(同 `KitStateMachine`)。
3. **headless `-s` 时序**:测试里每次 `add_child` 后 `await process_frame` 补一帧,`_enter_tree`/`_ready` 才落定(见 `test/test_state_machine.gd` 头注释)。
4. **autoload 非祖先**:CoreKit 在 `/root` 下是当前场景的兄弟,树顶兜底须经 `get_tree().root.get_node_or_null("CoreKit")` 显式定位,不能靠向上 `get_parent()` 走到它。
5. **`of()` 含自身、`_parent_ctx` 严格祖先**:两处向上走法不同,勿混。

## 9. 与现有架构的关系

- **内置子系统**:强类型属性 `CoreKit.<x>` 全保留;新增的全局 key 解析是并行可选路径。`bind_*` 内部接线不动。
- **依赖纪律**:子系统之间仍禁止互相 `preload`。KitContext → CoreKit 的单向全局兜底属"全局链"合法通道。
- **目录分层**:`di/` 属 off-facade 类库层,与 `state_machine/` 并列;不被 `core/`、`systems/` 依赖。

## 10. 连带改动清单(实现时逐条核对)

- **版本**:`0.4.1 → 0.5.0`。同步:`plugin.cfg` 的 `version=` 与 `description=`(提及 DI 容器)、`core_kit.gd` 的 `const VERSION`、`test_core_kit.gd` 的 VERSION 断言。
- **新增测试** `test/test_kit_context.gd`(`extends SceneTree`,运行时 `load`,`await process_frame`):
  - 本层 `provide`/`service` 命中;
  - 父子两层向上回退;
  - 子层 shadow 父层同名 key;
  - 树顶兜底命中 CoreKit 内置(`service("audio")` 拿到 AudioManager);
  - `provide_child` 收养的节点在容器 `free` 后被释放;`provide`(ref-only)的节点不被释放;
  - `provide_child` 传已有父节点 → 拒绝;
  - miss → `service` 返回 null、`service_or` 返回 fallback、`has` 为 false;
  - `of()` / `resolve()` 静态助手:非容器节点向上解析、无容器时兜底全局。
- **门面回归** `test/test_core_kit.gd`:补全局 `provide`/`service` 冒烟 + 10 个内置已预注册断言(`kit.service("log") == kit.log` 等);VERSION 断言改 `0.5.0`。
- **Runner** `test/run_all.ps1`:`$tests` 加 `'test_kit_context'`,放 `'test_core_kit'` **之前**(门面测试须最后);头注释测试数 12 → 13。
- **文档**:
  - 新增 `docs/di/kit-context.md`(五段式:职责 / 公开 API / 依赖 / 用法示例 / 注意事项)。
  - `docs/architecture.md`:加"扩展容器 / DI"节、目录布局补 `di/`、依赖纪律补 KitContext→CoreKit 单向兜底。
  - `docs/README.md` 索引加行。
  - 仓库 `README.md` 路由表加一行(`KitContext(类库) | 节点绑定的层级服务容器 | di/kit-context`)。
  - 散文里硬编码的"10 个子系统 / 12 测试"数字逐处核对(架构总纲、README、runner 注释)。
- **demo** `demo/demo.gd`:加作用域冒烟块(建 KitContext、`provide`/`provide_child`、`resolve`、`free` 看回收),含一行有辨识度的 `CoreKit.log.info(...)` marker 供 runner grep;必要时在 `run_all.ps1` 的 demo marker 列表补一项。
- **技能** `.claude/skills/using-core-kit`、`developing-core-kit`:各补一句 DI 容器指引(用法路由 / off-facade 类库放 `di/`)。

## 11. 用法示例

**全局服务(整局可见):**
```gdscript
CoreKit.provide("analytics", AnalyticsClient.new())
CoreKit.service("analytics").track("level_start")
CoreKit.service("audio").play_bgm("theme")     # 内置也可按 key 取
```

**关卡作用域(随关卡卸载回收):**
```gdscript
# level_3.tscn 的根脚本
func _ready() -> void:
    var ctx := KitContext.new(); ctx.name = "LevelCtx"
    add_child(ctx)
    ctx.provide("spawner", BossSpawner.new())            # 只在本关可见
    ctx.provide_child("music", LevelMusic.new())         # 归 ctx,切关自动释放

# 关卡内任意节点
var spawner = KitContext.resolve(self, "spawner")        # 命中 LevelCtx
var save = KitContext.resolve(self, "save_cloud")        # LevelCtx miss → 兜底全局
```

**实体作用域(配合状态机):**
```gdscript
# enemy.tscn 根做成 KitContext(或挂一个 KitContext 子节点)
# EnemyCtx.provide("blackboard", bb) 后,该敌人子树内 resolve("blackboard") 命中本体,
# resolve("spawner") 向上命中 LevelCtx —— 与 per-entity KitStateMachine 同一心智。
```

## 12. 验收标准

`powershell -File test\run_all.ps1` 以 `=== SUMMARY FAILS=0 ===` 结尾:import → 13 个测试各 ALL PASS(含新 `test_kit_context` 与更新后的 `test_core_kit`)→ demo 冒烟命中全部 marker、stderr 无 `ERROR:`/`SCRIPT ERROR:`。这是唯一验收信号。
