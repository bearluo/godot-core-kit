# KitContext 订阅式解析 + scope 语义 设计(v0.6.0)

> 阶段 2「直接借鉴纳入」子项目 1/3。借鉴 CSLocator(订阅式解析)与 di-godot(生命周期 scope)。
> 现状文件:`addons/godot-core-kit/di/kit_context.gd`(`class_name KitContext extends Node`)。
> 原则:纯叠加,**现有 API 语义与签名一律不动**,全程 TDD。

---

## 1. 目标 & 动机

`KitContext` 当前只有**一次性 pull 解析**(`service`/`has`/`service_or`)。两个真实痛点:

1. **时序坑**:Godot 中子节点 `_ready` 早于父节点,所以「祖先容器在自己 `_ready` 里 provide、后代消费者更早就绪」是常态——后代此刻解析必然 miss。需要**订阅式**解析:先订阅,等祖先 provide 时被回调。
2. **只能存值**:容器只能存现成引用,无法表达「按需创建」「每次新建 vs 单例」。需要**工厂式 scope 语义**。

本子项目为两者各加一条能力,叠加在既有解析之上。

---

## 2. 现状(保持不变、向后兼容)

- `provide(key, svc)` —— 存引用(ref-only),等价 VALUE / 单例引用。
- `provide_child(key, node)` —— 收养无父 Node 为子节点,随容器释放。
- `service(key)` / `has(key)` / `service_or(key, fallback)` —— 解析:`_local` → `_parent_ctx` → CoreKit 全局根。
- 静态 `of(node)`(含自身向上找最近容器)、`resolve(node, key)`。
- `_local`、`_parent_ctx`;`_enter_tree` 重算 `_parent_ctx`;`NOTIFICATION_PREDELETE` 清 `_local`。

**这些方法的签名与语义在本子项目中零改动**,新增测试不得回归它们。

---

## 3. 新增能力 A:订阅式解析

### 3.1 API

```gdscript
## 订阅某 key 的解析结果。订阅时若已可解析 → 立即回调一次;
## 之后该 key 在【本容器或任一祖先容器】被 provide/provide_child/provide_factory 时,
## 只要本容器沿链解析到的值会因此变化,即再次回调。
func subscribe(key: String, cb: Callable) -> void

## 取消订阅。cb 未注册则空操作。
func unsubscribe(key: String, cb: Callable) -> void
```

消费者通常经静态入口拿到容器再订阅:`KitContext.of(self).subscribe("player", _on_player)`。

### 3.2 数据结构(新增字段)

```gdscript
var _subscribers: Dictionary = {}   # key:String -> Array[Callable]
var _child_ctxs: Array = []         # 直接子容器(KitContext),用于向下传播;不标类型避免自引用
```

### 3.3 子容器注册(向下传播的前提)

- `_enter_tree()`:重算 `_parent_ctx` 后,若非空且未登记,则 `_parent_ctx._child_ctxs.append(self)`。
- `_notification(PREDELETE)`:若 `_parent_ctx` 仍有效,`_parent_ctx._child_ctxs.erase(self)`;并清 `_subscribers`(连同 §4 的 `_factories`/`_singletons`)。

> 祖先必先于后代进入场景树,故后代 `_enter_tree` 时其 `_parent_ctx` 必已在 `_child_ctxs` 可登记——链路成立。

### 3.4 通知算法(核心)

任一容器**成为某 key 的 owner**(即在本层 `provide` / `provide_child` / `provide_factory`)后调用 `_notify(key)`:

```
_notify(key):                       # self 是本次 owner
    _deliver(key, self)

_deliver(key, owner):               # 在 self 及其未 shadow 的后代上投递
    for cb in _subscribers.get(key, []):
        cb.call(owner._owner_value(key))
    for child in _child_ctxs:
        if child._owns(key):        # 后代自己 shadow 了该 key → 整个子树跳过
            continue
        child._deliver(key, owner)

_owns(key)  -> bool:  return _local.has(key) or _factories.has(key)
_owner_value(key):    # owner 本层的解析值;懒:无订阅者时永不调用 → 单例不被提前创建
    if _local.has(key): return _local[key]
    return _resolve_factory(key)    # 见 §4.3(SINGLETON 缓存 / TRANSIENT 每次新建)
```

**为什么正确**:后代订阅者沿链解析到「自 self 向上最近的 owner」。当 owner=self 新 provide 时,凡从某后代到 self 之间无更近 owner 的分支,其订阅者的解析值都变为 self 的值 → 恰好被 `_deliver` 命中;有更近 owner 的分支被 `_owns` 剪枝。祖先 `_ready` 顺序(深者先)天然保证「更近的 owner 先 provide、先占位」,后到的远祖 provide 被剪枝,不会覆盖。

### 3.5 订阅时的立即回调

```
subscribe(key, cb):
    if has(key):
        cb.call(service(key))       # 立即用当前解析值回调一次
    _subscribers.getor_add(key,[]).append(cb)   # GDScript: 无 key 则先建 []
```

### 3.6 语义约定(写入文档)

- **立即 + 变更**:订阅=立即回调(若可解析)+ 后续 owner 变更回调。不是一次性。
- **不追溯 reparent**:容器被 reparent 到新链后,不主动重投既有订阅(YAGNI);主用例(`_ready` 内订阅、祖先稍后 provide)由 §3.4 覆盖。
- **TRANSIENT + 订阅**:投递时对每个订阅者调一次工厂(各得新实例),属边界用法,文档标注。

---

## 4. 新增能力 B:scope 语义(工厂式)

### 4.1 API

```gdscript
enum Scope { SINGLETON, TRANSIENT }

## 以工厂注册服务。SINGLETON:首次 service() 调一次工厂并缓存;
## TRANSIENT:每次 service() 都调工厂返新实例。
## 面向普通值 / RefCounted;Node 型服务请用 provide_child(容器负责其生命周期)。
func provide_factory(key: String, factory: Callable, scope: int = Scope.SINGLETON) -> void
```

### 4.2 数据结构(新增字段)

```gdscript
var _factories: Dictionary = {}     # key:String -> {"factory": Callable, "scope": int}
var _singletons: Dictionary = {}    # key:String -> 已实例化的 SINGLETON 缓存
```

### 4.3 解析改动

`service(key)` 本层解析顺序改为:**先 `_local`,再 `_factories`**,然后才向上/兜底:

```
service(key):
    if _local.has(key):      return _local[key]
    if _factories.has(key):  return _resolve_factory(key)
    if _parent_ctx != null:  return _parent_ctx.service(key)
    return _global(key)

_resolve_factory(key):
    var e = _factories[key]
    if e.scope == Scope.TRANSIENT:
        return e.factory.call()
    if not _singletons.has(key):
        _singletons[key] = e.factory.call()
    return _singletons[key]
```

`has(key)` 本层条件改为 `_local.has(key) or _factories.has(key)`(其余向上/兜底不变)。`service_or` 无需改(基于 `has`/`service`)。

### 4.4 三种注册互斥(同层同 key)

同一容器对同一 key 的三种注册**互相覆盖**,注册时清掉另两种表示 + 告警(沿用现有「覆盖同层告警」):

- `provide(key,svc)`:`_local[key]=svc`;`_factories.erase(key)`;`_singletons.erase(key)`;`_notify(key)`。
- `provide_child(key,node)`:收养后 `_local[key]=node`;`_factories.erase(key)`;`_singletons.erase(key)`;`_notify(key)`。
- `provide_factory(key,f,scope)`:`_factories[key]={...}`;`_local.erase(key)`;`_singletons.erase(key)`;`_notify(key)`。

---

## 5. 不变式 / 向后兼容

1. `provide` / `provide_child` / `service` / `has` / `service_or` / `of` / `resolve` 签名不变;未用新能力时行为逐字不变。
2. 无订阅者时,SINGLETON 工厂**不被提前实例化**(懒创建);`_notify` 仅在有投递目标时才求值。
3. `PREDELETE` 仍释放 `provide_child` 收养的 Node(作为子节点连带释放);ref-only `provide` 的对象不被释放。
4. 兜底 CoreKit 全局根的 duck-typed 调用不变、无类型耦合。

---

## 6. 边界 & 坑

- **子容器双重登记**:`_enter_tree` 可能因 reparent 多次触发,`append` 前查重(`has`)。
- **PREDELETE 顺序**:Godot 释放父节点时先释放子节点,子容器 PREDELETE 先跑、此时父仍有效可 `erase`;仍以 `is_instance_valid(_parent_ctx)` 兜底。
- **工厂返回 Node**:SINGLETON 缓存的 Node 不会被自动 add_child / free —— 明确「Node 用 provide_child,工厂面向值/RefCounted」,文档警示。
- **Callable 相等**:`unsubscribe` / `_subscribers.erase` 依赖 Callable 值相等;文档提示订阅与取消需用同一 Callable(同对象同方法)。

---

## 7. 测试(TDD,`test/test_kit_context.gd`,`extends SceneTree`)

新增段落(沿用现有 `await process_frame`、`var x = KC.new()` 惯例):

1. **订阅-立即**:先 `provide("a",1)` 再 `subscribe("a")` → 立即回调值 1。
2. **订阅-本层延后**:先 `subscribe("a")`(不回调)→ 后 `provide("a",2)` → 回调值 2。
3. **订阅-祖先延后(核心时序)**:P 下挂 C,经 C 订阅 "svc"(未回调)→ P.provide("svc",obj) → C 的订阅者被回调 obj。
4. **shadow 剪枝**:GP-P-C 链,C 订阅 "k";P.provide 先命中 → C 得 P 值;随后 GP.provide 同 key **不再**回调 C。
5. **unsubscribe**:取消后再 provide 不回调。
6. **factory SINGLETON**:`provide_factory("s", f, SINGLETON)`;两次 `service("s")` 同一实例;且订阅前 `f` 未被调用(懒)。
7. **factory TRANSIENT**:两次 `service("t")` 不同实例。
8. **factory 向上 + shadow**:祖先 provide_factory,后代 service 命中;后代同 key provide 覆盖后取后代值。
9. **三注册互斥**:`provide_factory` 后再 `provide` 同 key → 取 value 且工厂表被清。
10. **PREDELETE 清理**:free 一个子容器后,父 `_child_ctxs` 不再含它(经「再 provide 不应触达已释放子容器」间接断言,不直接读私有);订阅表随之清空。
11. **回归**:现有全部断言(local hit / miss / provide_child 收养 / ref-only / 向上回退 / of/resolve / 兜底 built-ins / PREDELETE 释放收养)保持通过。

`demo/demo.gd` 的 KitContext 段落追加 subscribe + provide_factory 冒烟;`test/run_all.ps1` 无需改结构(已含 `test_kit_context`)。

---

## 8. 版本 & 文档

- `core_kit.gd` `VERSION` 与 `plugin.cfg` `version`:`0.5.0` → **`0.6.0`**。
- `addons/godot-core-kit/docs/di/kit-context.md`:新增「订阅式解析」「scope 工厂」两节 + 边界约定(Node 用 provide_child、TRANSIENT+订阅、Callable 相等、不追溯 reparent)。

---

## 9. 明确不做(YAGNI,留待有真实需求)

- scope 之 `VALUE` 之外的更多生命周期(如 per-scene、weak)。
- reparent 后自动重投订阅。
- 循环依赖检测(工厂互相 `service` 可能栈溢出——文档警示即可,不加检测)。
- `provide_factory` 对 Node 的自动 add_child / 生命周期托管。
