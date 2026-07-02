# godot-core-kit Settings 子系统设计

- 日期:2026-07-02
- 状态:已确认,待实现
- 版本目标:0.4.0
- 前置:`2026-07-02-corekit-facade-design.md`(总纲;门面属性 `CoreKit.settings`)

---

## 目标与定位

`Settings` 是玩家偏好设置的分区读写 + 落盘单元:音频音量、键位重绑定、语言、画质开关这类"跨存档、装完游戏就该记住"的键值。

定位边界:

- **设置 ≠ 存档**:落盘 `user://settings.json`,**不走 SaveManager**——设置不该出现在 `saves.list_slots()` 里,也不该被"删除存档"误删。
- 服务对象是框架内的 InputManager/AudioManager(经 `bind_settings()` 注入)与游戏层任意代码(经 `CoreKit.settings`)。
- 首版 YAGNI:不做类型 schema 校验、不做默认值注册表、不做多配置档(profile)、不做云同步。

## Public API(GDScript 精确签名)

```gdscript
extends Node
## Settings —— 玩家偏好分区键值,写透落盘 user://settings.json。

## 任何 set_value/erase_* 实际改变了值之后广播(值未变化的 set 不广播)。
signal value_changed(section: String, key: String, value: Variant)

const SETTINGS_PATH := "user://settings.json"

func get_value(section: String, key: String, default: Variant = null) -> Variant
func set_value(section: String, key: String, value: Variant) -> void
func has_value(section: String, key: String) -> bool
func erase_value(section: String, key: String) -> void   ## 不存在则空操作
func erase_section(section: String) -> void              ## 不存在则空操作
```

## Behavior & data flow

- 内存态:`var _data: Dictionary = {}`,形状 `{section: {key: value}}`,两层都是 String key。
- **构造时读盘**(`_ready`):文件不存在 → 空配置;JSON 损坏/根不是 Dictionary → `push_warning`(初始化期,依总纲纪律不走 CoreKit.log)并从空配置开始,**不删坏文件**(下次成功 set 时才覆盖)。非 Dictionary 的 section 值在载入时丢弃。
- **写透**:`set_value`/`erase_*` 改变内存后立即整文件重写落盘(文件极小;Web 无可靠退出时机,写透最稳)。落盘失败 → `CoreKit.log.error`(运行期),内存态保留。
- `set_value` 用 `_values_equal` 语义(直接 `==`)判断"值未变化"以决定是否广播与落盘;value 限 JSON 可表达类型(bool/int/float/String/Array/Dictionary),调用方自律,spec 不做运行时校验。
- `erase_value` 清空 section 后顺手删空 section;`value_changed` 对 erase 广播 `value = null`。

## Key decisions

| # | 维度 | 结论 | 理由 |
|---|---|---|---|
| 1 | 存储介质 | 独立 `user://settings.json`,不走 SaveManager | 设置≠存档;隔离误删与 list_slots 污染 |
| 2 | 落盘时机 | set 即写透 | 文件极小;Web 无可靠退出钩子;免去 dirty/flush 状态机 |
| 3 | 变更通知 | 单个 `value_changed(section, key, value)` 信号 | UI 设置页/子系统联动够用;分 section 信号是 YAGNI |
| 4 | JSON int→float | 接受(文档声明),与 SaveManager 同款注意事项 | JSON 规范决定;消费方取整用 `int(get_value(...))` |
| 5 | 损坏文件 | 警告 + 空配置降级,不崩、不删 | 玩家手改文件是常见事故,框架要兜住 |

## Web-export considerations

`user://` 在 HTML5 由 IndexedDB 支持,FileAccess/JSON 全平台同步 API;无线程、无轮询、无桌面专属 API。与 SaveManager 完全同款约束,无新增风险面。

## Testable seams + test plan

接缝:`_encode(data) -> String` / `_decode(text) -> Dictionary`(纯函数,与 SaveManager 同款形态:损坏输入返回 `{}`);读写盘路径走真实 `user://` 一次性文件,测试后清理。

`test/test_settings.gd`(headless,直接实例化,运行时 `load()`):

1. get 未设值返回 default(含 default 缺省 null)。
2. set → get 往返(bool/int/float/String/嵌套 Dictionary;数值比较容忍 int/float)。
3. set 相同值不广播、set 新值广播一次且参数正确(Dictionary 盒子捕获)。
4. `has_value` / `erase_value` / `erase_section` 语义与空操作安全。
5. `_decode` 损坏 JSON / 根非 Dictionary → `{}`;`_decode(_encode(x))` 往返。
6. 磁盘往返:set → 重建实例读盘 → get 一致;结束清理测试文件。
7. 坏文件降级:预写非法 JSON → 构造后为空配置且可正常 set(覆盖坏文件)。

## 版本

Settings v0.4.0 起:分区键值、写透落盘、变更信号、损坏降级。依赖:log(仅运行期错误);被 input/audio 经 `bind_settings()` 依赖。
