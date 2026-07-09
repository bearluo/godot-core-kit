# ObjectPool —— 对象池

> `CoreKit.pool` · `systems/object_pool.gd`

## 职责

按字符串 key 管理若干个具名节点池,复用子弹、敌人、粒子等高频 spawn/despawn 的 Node 实例,避免反复 `instantiate()`/`free()` 造成的实例化开销与内存抖动(尤其在 Web/WASM 导出下更明显)。`register()` 注册池、`acquire()` 借出、`release()` 归还、`clear()` 回收当前空闲实例。纯内存操作、无文件 IO、无线程,支持 Web 导出。

## 公开 API

```gdscript
const META_POOL_KEY := "__object_pool_key"  # release() 靠这个元数据判定节点归属哪个池

# scene 的根节点类型会被反复 instantiate() 复用。prewarm:立即创建的空闲实例数(默认 0)。
# max_count:实例总数上限(in_use+available),0=不限。manage_visibility:是否对称管理
# visible。key 已存在且 scene 相同则幂等忽略;scene 不同则保留原池并 warn。
func register(key: String, scene: PackedScene, prewarm: int = 0, max_count: int = 0, manage_visibility: bool = true) -> void

func has_pool(key: String) -> bool

# 优先复用空闲队列(LIFO);为空则按 max_count 决定新建或返回 null。
# 返回的节点处于游离态,是否/何时 add_child 由调用方决定。
func acquire(key: String) -> Node

# 归还借出的节点。node 为 null/失效/非本系统创建/重复 release 均静默 no-op(附 warn)。
func release(node) -> void

# 释放指定 key 当前空闲实例(queue_free)并清空空闲队列;in_use 中的实例不受影响。
func clear(key: String) -> void

func available_count(key: String) -> int
func in_use_count(key: String) -> int
func total_count(key: String) -> int
```

被池化场景可选实现的复用钩子(约定,非本类方法):`func _pool_reset() -> void`——`release()` 用 `has_method("_pool_reset")` 探测,存在则归还时调用一次,用于清空本轮使用留下的状态。调用时机保证节点已至少完整经历过一次 `_ready()`;prewarm 阶段创建的实例不触发该钩子。

## 依赖

零跨子系统依赖(不依赖 EventBus/SceneManager/SaveManager),可选用 `CoreKit.log` 记录告警/错误。

## 用法示例

```gdscript
CoreKit.pool.register("bullet", preload("res://bullets/bullet.tscn"), 20, 200)

var b := CoreKit.pool.acquire("bullet")
if b != null:
    add_child(b)
# ... 子弹逻辑自行决定何时释放 ...
CoreKit.pool.release(b)
```

## 注意事项

- **僵尸引用兜底**:若节点被外部绕过 `release()` 直接 `free()`,`acquire()` 会在弹出空闲队列时探测到失效实例、丢弃并扣减记账,继续找下一个可用实例。
- **`release()` 用 `call_deferred` 摘除父节点**:因为 `release()` 常从节点自身碰撞回调(`area_entered`/`body_entered`)里同步触发,物理体在自己碰撞回调里同步改树有 "flushing queries" 报错风险;记账、隐藏、`_pool_reset()` 都是纯属性/字典操作,不受影响,仍同步执行。
- **`acquire()` 同步兜底摘父节点**:若上一次 `release()` 的 `call_deferred` 尚未执行到,`acquire()` 会同步摘掉父节点,避免把仍挂着旧父节点的实例交给调用方。
- `clear(key)` 不等于 unregister:池的注册信息(scene/max_count/manage_visibility)保留,之后仍可 `acquire()`(空闲队列为空时重新 `instantiate()`)。
- `manage_visibility=true`(默认)时仅对 `CanvasItem`/`Node3D` 对称管理 `visible`;`false` 时完全交给调用方(如自定义淡入淡出)。
