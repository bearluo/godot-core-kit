# KitContext —— 节点绑定的层级服务容器

> `class_name KitContext` · `di/kit_context.gd` · off-facade 类库(不挂门面)

## 职责

给使用 core-kit 的游戏代码一个**开放的服务定位器**:把自己的服务按字符串 key 注册进来、按 key 取。容器是场景树上的节点,解析沿祖先链向上回退、树顶兜底到 CoreKit 全局根,生命周期随节点。用于关卡级 / 实体级作用域服务,以及全局服务(经 `CoreKit.provide/service`)。

不是自动装配 / IoC 容器:不解析服务间依赖,消费方 pull(自己 `service(key)` 取)。

## 公开 API

### 全局根(CoreKit,整局作用域)

| 成员 | 说明 |
|---|---|
| `CoreKit.provide(key, svc) -> void` | 注册全局服务。保留键(10 个内置)拒绝;重复键覆盖告警。 |
| `CoreKit.service(key) -> Variant` | 取;未注册 → push_error + null。 |
| `CoreKit.has(key) -> bool` | 存在性,不报错。 |
| `CoreKit.service_or(key, fallback) -> Variant` | 未注册返回 fallback。 |

10 个内置子系统已按属性名预注册(`service("audio") == CoreKit.audio`),但内置首选仍走强类型属性(有补全 + 类型)。

### 作用域容器(KitContext,挂节点)

| 成员 | 说明 |
|---|---|
| `provide(key, svc) -> void` | 注册到本层,只存引用,绝不动树。重复键覆盖告警。可 shadow 祖先/全局同名键。 |
| `provide_child(key, node) -> void` | 收养:node 须无父(否则 push_error 跳过),`add_child` 后注册,随本容器释放。 |
| `service(key) -> Variant` | 本层 → 最近祖先容器 → CoreKit 全局根,逐层解析。 |
| `has(key) -> bool` / `service_or(key, fallback)` | 沿同一条链,不报错。 |
| `static of(node) -> KitContext` | node 自身或最近祖先容器;无 → null。 |
| `static resolve(node, key) -> Variant` | `of(node)` 命中即取,否则兜底全局根。非容器节点解析用它。 |

## 依赖

- 单向依赖 CoreKit autoload:仅"树顶兜底"经 `get_tree().root.get_node_or_null("CoreKit")` duck-typed 调用其 `service`/`has`。不引入类型耦合,与"人人可用 `CoreKit.log`"的全局链一致。
- 不被 `core/`、`systems/` 依赖;与 `state_machine/` 同为 off-facade 类库层。

## 用法示例

全局服务(整局可见):
```gdscript
CoreKit.provide("analytics", AnalyticsClient.new())
CoreKit.service("analytics").track("level_start")
CoreKit.service("audio").play_bgm("theme")   # 内置也可按 key 取
```

关卡作用域(随关卡卸载回收):
```gdscript
func _ready() -> void:
    var ctx := KitContext.new(); ctx.name = "LevelCtx"
    add_child(ctx)
    ctx.provide("spawner", BossSpawner.new())      # 只在本关可见
    ctx.provide_child("music", LevelMusic.new())   # 归 ctx,切关自动释放

# 关卡内任意节点
var spawner = KitContext.resolve(self, "spawner")   # 命中 LevelCtx
var save = KitContext.resolve(self, "save_cloud")   # LevelCtx miss → 兜底全局
```

实体作用域(配合状态机):
```gdscript
# enemy 根做成 / 挂一个 KitContext,provide("blackboard", bb)
# 该敌人子树内 resolve("blackboard") 命中本体,resolve("spawner") 向上命中 LevelCtx
# —— 与 per-entity KitStateMachine 同一心智。
```

## 注意事项

- **shadow**:子容器 `provide` 同名 key 即在子树内覆盖父层/全局(含内置)。
- **归属**:`provide` 只存引用、绝不 reparent;要随作用域释放用 `provide_child`(或自己 add_child 到该容器后再 provide)。
- **生命周期**:disposal 走 `NOTIFICATION_PREDELETE`(非 `_exit_tree`,后者 reparent 也触发);`provide_child` 的子节点随容器 free 连带释放。
- **class_name 缓存**:首次引用 `KitContext` 的脚本须先 `godot --headless --path . --import`。
- **热路径**:`resolve` 每次向上走 `get_parent()` 链;高频访问在 `_ready` 里 pull 一次存成员,别每帧解析。
- **autoload 非祖先**:树顶兜底是显式定位 CoreKit(它是当前场景的兄弟),不靠向上 `get_parent()` 走到它。
