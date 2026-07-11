# KitContext —— 节点绑定的层级服务容器

> `class_name KitContext` · `di/kit_context.gd` · off-facade 类库(不挂门面)

## 职责

给使用 core-kit 的游戏代码一个**开放的服务定位器**:把自己的服务按字符串 key 注册进来、按 key 取。容器是场景树上的节点,解析沿祖先链向上回退、树顶兜底到 CoreKit 全局根,生命周期随节点。用于关卡级 / 实体级作用域服务,以及全局服务(经 `CoreKit.provide/service`)。

不是自动装配 / IoC 容器:不解析服务间依赖,消费方 pull(自己 `service(key)` 取)。

## 公开 API

### 全局根(CoreKit,整局作用域)

| 成员 | 说明 |
|---|---|
| `CoreKit.provide(key, svc) -> void` | 注册全局服务。保留键(12 个内置)拒绝;重复键覆盖告警。 |
| `CoreKit.service(key) -> Variant` | 取;未注册 → push_error + null。 |
| `CoreKit.has(key) -> bool` | 存在性,不报错。 |
| `CoreKit.service_or(key, fallback) -> Variant` | 未注册返回 fallback。 |

12 个内置子系统已按属性名预注册(`service("audio") == CoreKit.audio`),但内置首选仍走强类型属性(有补全 + 类型)。

### 作用域容器(KitContext,挂节点)

| 成员 | 说明 |
|---|---|
| `provide(key, svc) -> void` | 注册到本层,只存引用,绝不动树。重复键覆盖告警。可 shadow 祖先/全局同名键。 |
| `provide_child(key, node) -> void` | 收养:node 须无父(否则 push_error 跳过),`add_child` 后注册,随本容器释放。 |
| `service(key) -> Variant` | 本层 → 最近祖先容器 → CoreKit 全局根,逐层解析。 |
| `has(key) -> bool` / `service_or(key, fallback)` | 沿同一条链,不报错。 |
| `static of(node) -> KitContext` | node 自身或最近祖先容器;无 → null。 |
| `static resolve(node, key) -> Variant` | `of(node)` 命中即取,否则兜底全局根。非容器节点解析用它。 |
| `subscribe(key, cb) -> void` | 订阅某 key 的解析结果:订阅时可解析即立即回调一次;之后本层或任一祖先(有更近或同层 owner)provide 该 key 时再回调。取消需用同一 Callable。 |
| `unsubscribe(key, cb) -> void` | 取消订阅;key 或 cb 未注册则空操作。 |
| `provide_factory(key, factory, scope=Scope.SINGLETON) -> void` | 以工厂注册。SINGLETON 首次 service() 创建并缓存(懒);TRANSIENT 每次 service() 新建。同层覆盖 value/其它工厂并告警。 |

## 订阅式解析(subscribe)

`ctx.subscribe(key, callable)` 订阅某 key 的解析结果:订阅时若已可解析立即回调一次,
之后该 key 在**本容器或任一祖先容器**被 provide 时再次回调(投递按结构剪枝——更近/同层
owner 覆盖更远祖先;不比较新旧值,故对同 owner 幂等 provide 相同值仍会回调)。
用于化解 Godot「后代 `_ready` 早于祖先」的时序坑——后代先订阅,祖先稍后 provide 时被回调。
`unsubscribe(key, callable)` 取消(需用同一 Callable)。

```gdscript
# 后代消费者(在其 _ready 里)
KitContext.of(self).subscribe("player", func(p): _player = p)
# 祖先容器(在其更晚的 _ready 里)provide → 上面回调被触发
ctx.provide("player", player_node)
```

传播只在 KitContext 链内;shadow 分支自动剪枝(更近祖先的值优先,更远祖先不覆盖)。
不追溯 reparent(容器换链后不重投既有订阅)。

## 工厂式 scope(provide_factory)

`ctx.provide_factory(key, factory: Callable, scope)` 以工厂注册,`scope ∈ {KitContext.Scope.SINGLETON, KitContext.Scope.TRANSIENT}`:

- `SINGLETON`(默认):首次 `service(key)` 调一次工厂并缓存,后续复用同一实例;无人取用则不创建(懒)。
- `TRANSIENT`:每次 `service(key)` 都调工厂返新实例。

```gdscript
ctx.provide_factory("rng", func(): return RandomNumberGenerator.new(), KitContext.Scope.TRANSIENT)
```

**边界**:工厂面向普通值 / `RefCounted`;**Node 型服务用 `provide_child`**(容器负责其生命周期)。
TRANSIENT 工厂若返回 Node,其生命周期归调用方。同层对同 key 的 `provide` / `provide_child` /
`provide_factory` 互相覆盖(并清另两种表示)。

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
- **provide_child 覆盖**:用已存在的 key 再次 `provide_child` 会重指 `_local`,但**不释放**上一个收养的子节点——它仍作为容器子节点存在,直到容器自身 free。需替换请先自行 `remove_child`/`free` 旧节点,或避免同 key 重复 `provide_child`。
- **生命周期**:`_exit_tree` 确实存在,但只做 `_child_ctxs` 树成员簿记(reparent 时从旧父反登记,避免旧父继续向已移走的子树投递订阅);服务表的 disposal 仍只走 `NOTIFICATION_PREDELETE`。`provide_child` 的子节点随容器 free 连带释放。
- **class_name 缓存**:首次引用 `KitContext` 的脚本须先 `godot --headless --path . --import`。
- **热路径**:`resolve` 每次向上走 `get_parent()` 链;高频访问在 `_ready` 里 pull 一次存成员,别每帧解析。
- **autoload 非祖先**:树顶兜底是显式定位 CoreKit(它是当前场景的兄弟),不靠向上 `get_parent()` 走到它。
