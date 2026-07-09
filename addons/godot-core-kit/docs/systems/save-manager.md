# SaveManager —— 全局存档

> `CoreKit.saves` · `systems/save_manager.gd`

## 职责

把任意 Dictionary 状态以具名"存档位"(slot)形式落盘到 `user://saves/<slot>.json`,JSON 格式、`{_version, data}` 信封包裹。桌面与 Web 导出行为一致(`user://` 在 HTML5 由 IndexedDB 支持,`FileAccess`/`DirAccess`/`JSON` 全平台同步 API,无需 await)。纯 GDScript、无第三方依赖。

v1 范围之外(YAGNI):无自动收集存档的 registry、无加密、无迁移引擎(仅保留版本号字段)、无自动存档调度、无存档位元数据(缩略图/时长)、无原子写(temp+rename)。

## 公开 API

```gdscript
signal saved(slot: String)
signal save_failed(slot: String, reason: String)
signal loaded(slot: String)
signal load_failed(slot: String, reason: String)
signal slot_deleted(slot: String)

const SCHEMA_VERSION := 1

# 写入 slot,若已存在则覆盖。成功 true;失败 false 并 emit save_failed(slot, reason)。
func save(slot: String, data: Dictionary) -> bool

# 读回 slot 的 Dictionary。任何错误(不存在/JSON 损坏)都返回 {} 并 emit load_failed;
# 存档位本身合法地存了 {} 时同样返回 {},但 emit 的是 loaded。
func load(slot: String) -> Dictionary

func has_slot(slot: String) -> bool

# 删除存档位文件。成功 true 并 emit slot_deleted;不存在或删除失败返回 false(无专属失败信号)。
func delete_slot(slot: String) -> bool

# 列出所有存档位名称(不含扩展名),升序排列,仅名称、无元数据;目录不存在时返回 []。
func list_slots() -> Array[String]
```

## 依赖

零跨子系统依赖,除 `CoreKit.log`(仅用于版本不匹配警告)外不依赖其它子系统。

## 用法示例

```gdscript
CoreKit.saves.save("hero1", {"hp": 100})

var data := CoreKit.saves.load("hero1")

CoreKit.saves.save_failed.connect(func(slot, reason): CoreKit.log.error("存档失败 %s: %s" % [slot, reason]))
```

## 注意事项

- **命名坑**:`load()` 在本脚本体内会遮蔽 GDScript 内置全局函数 `load(path)`(与 `CoreKit.log` 遮蔽全局 `log()` 同理);脚本内部从不需要调用全局 `load()`,外部通过 `CoreKit.saves.load(...)` 调用不受影响。
- **存档位名称白名单清洗**:只保留 `[A-Za-z0-9_-]`,清洗后为空(原始输入为空/纯空白/全部字符非法)一律拒绝(视为失败),不回退到某个默认存档位。
- **版本号仅记录、不迁移**:`_version` 与当前 `SCHEMA_VERSION` 不一致时按原样加载并 `CoreKit.log.warn`,v1 无迁移逻辑。
- **JSON int→float**:与 Settings 同理,数据经 JSON 落盘往返后 int 会变 float,取整用 `int(...)`。
- 无原子写:写入过程中断电/崩溃可能导致该 slot 文件损坏;`_decode` 对损坏内容一律返回 `{}` 触发 `load_failed`,不删除原文件。
