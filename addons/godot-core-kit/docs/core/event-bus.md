# EventBus —— 事件总线

> `CoreKit.bus` · `core/event_bus.gd`

## 职责

全局发布/订阅事件总线。用字符串事件名解耦发布方与订阅方,**补充而非取代** Godot 原生 signal:两节点有直接引用关系时优先用原生 signal;EventBus 只用于没有引用关系、订阅方不确定的广播场景。

核心语义:单个 `Variant` payload;`publish()` 对当前订阅做快照后按 FIFO 同步派发,派发期间的 subscribe/unsubscribe 只影响下一次 publish(重入安全);查询/派发时惰性剔除已被 `free()` 的监听者。

## 公开 API

```gdscript
signal event_published(event_name: String, payload: Variant)  # 每次 publish 旁路广播

func subscribe(event_name: String, listener: Callable, once := false) -> void
func subscribe_once(event_name: String, listener: Callable) -> void
func unsubscribe(event_name: String, listener: Callable) -> void
func unsubscribe_all(target: Object) -> void   # 移除 target 的全部订阅
func publish(event_name: String, payload: Variant = null) -> void
func has_listeners(event_name: String) -> bool
func get_listener_count(event_name: String) -> int
func clear(event_name := "") -> void           # 空名清空全部
```

`listener` 形如 `func(payload: Variant) -> void`。同一 `(event_name, listener)` 重复订阅是幂等空操作。

## 依赖

零依赖(不依赖 Log/SceneManager 等)。

## 用法示例

```gdscript
func _ready() -> void:
    CoreKit.bus.subscribe("player_died", _on_player_died)

func _on_player_died(payload) -> void:
    show_game_over(payload["score"])

# 发布方(与订阅方无引用关系)
CoreKit.bus.publish("player_died", {"score": 1200})
```

## 注意事项

- **RefCounted 监听者不会自动剔除**:Callable 绑定到 `RefCounted`(普通 class、Resource 等)时,Callable 持其一份强引用,对象不会自然归零。纯 RefCounted 监听者必须显式 `unsubscribe()`/`unsubscribe_all()`;自动剔除只覆盖 Node/Object(非引用计数)监听者。
- 惯例:节点在 `_exit_tree()` 前对自己 `unsubscribe_all(self)`,别依赖自动剔除的时机。
- payload 是单个 Variant;要传多值就包一个 Dictionary。
