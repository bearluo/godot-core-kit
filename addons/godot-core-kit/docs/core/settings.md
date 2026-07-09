# Settings —— 玩家偏好

> `CoreKit.settings` · `core/settings.gd`

## 职责

分区键值偏好,写透落盘 `user://settings.json`。**设置 ≠ 存档**:音量/键位/语言这类"跨存档、装完游戏就该记住"的键值落这里,不走 SaveManager(不出现在存档槽、不被删档误删)。任何实际改变值的写操作立即落盘并广播信号。

## 公开 API

```gdscript
signal value_changed(section: String, key: String, value: Variant)

func get_value(section: String, key: String, default: Variant = null) -> Variant
func set_value(section: String, key: String, value: Variant) -> void
func has_value(section: String, key: String) -> bool
func erase_value(section: String, key: String) -> void
func erase_section(section: String) -> void

var settings_path := "user://settings.json"   # 测试注入接缝
```

值限 JSON 可表达类型(bool/int/float/String/Array/Dictionary)。`value_changed` 仅在值**确实变化**时广播;`erase_value` 广播 `value=null`,`erase_section` 广播 `(section, "", null)`。

## 依赖

被 `InputManager`、`AudioManager` 经 `bind_settings(self)` 注入以做持久化。运行期落盘失败时用 `CoreKit.log.error`。

## 用法示例

```gdscript
# 读(带默认值)
var vol: float = CoreKit.settings.get_value("audio", "master", 1.0)

# 写(自动落盘 + 广播)
CoreKit.settings.set_value("audio", "master", 0.8)

# 监听变更(如实时联动 UI)
CoreKit.settings.value_changed.connect(func(s, k, v):
    if s == "audio": refresh_volume_sliders())
```

## 注意事项

- **JSON int→float**:往返后 int 变 float,取整用 `int(get_value(...))`。
- **容器已做深拷贝防别名**:`get_value` 返回容器的深拷贝,`set_value` 存入深拷贝——放心对读出的 Dictionary/Array 做 read-modify-write 再写回,不会别名到内部态导致"值未变"判等静默跳过落盘。
- 文件损坏时从空配置开始且**不删原文件**(留给人工排查),并 `push_warning`。
