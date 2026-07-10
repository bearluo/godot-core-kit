# SaveManager —— 全局存档

> `CoreKit.saves` · `systems/save_manager.gd`

## 职责

把任意 Dictionary 状态以具名"存档位"(slot)形式,经可插拔 `SaveSerializer`(默认 `JsonSaveSerializer`,`.json`)序列化、原子写(temp+rename)落盘到 `user://saves/<slot>.<ext>`,`{_version, data}` 信封包裹。桌面与 Web 导出行为一致(`user://` 在 HTML5 由 IndexedDB 支持,`FileAccess`/`DirAccess`/`JSON` 全平台同步 API,无需 await)。纯 GDScript、无第三方依赖。

范围之外(YAGNI):无自动收集存档的 registry、无加密/校验和(可由自定义 serializer 承载)、无迁移引擎(仅保留版本号字段)、无自动存档调度、无存档位元数据(缩略图/时长)。

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

# 替换序列化策略(默认 JsonSaveSerializer)。null 忽略并 push_error;换后影响后续 save/load。
func set_serializer(s: SaveSerializer) -> void
```

## 依赖

零跨子系统依赖,除 `CoreKit.log`(仅用于版本不匹配警告)外不依赖其它子系统。

## 用法示例

```gdscript
CoreKit.saves.save("hero1", {"hp": 100})

var data := CoreKit.saves.load("hero1")

CoreKit.saves.save_failed.connect(func(slot, reason): CoreKit.log.error("存档失败 %s: %s" % [slot, reason]))
```

## 可插拔序列化(SaveSerializer)

存档的 Dictionary <-> 字节转换由可替换的序列化策略 `SaveSerializer` 承担(`class_name`,off-facade 类库,与 `KitContext`/`KitStateMachine` 同层)。默认 `JsonSaveSerializer` 与旧行为逐字节兼容(缩进 `"\t"`、UTF-8、扩展名 `json`)。

    # 换用自定义序列化器(影响后续 save/load,不改动已落盘文件)
    CoreKit.saves.set_serializer(MyBinarySerializer.new())

`SaveSerializer` 三个必覆写方法:`encode(dict) -> PackedByteArray`、`decode(bytes) -> Dictionary`(格式解析失败返回 `{}`)、`extension() -> String`(不含点)。信封 `{_version, data}` 与版本校验仍由 SaveManager 负责,序列化器不感知信封结构。

换 serializer 后存量可见性:`list_slots`/`has_slot`/`load`/`delete_slot` 只见当前序列化器扩展名的文件(各 serializer 管自己的扩展名)。默认 JSON 保持 `.json`,存量存档不受影响;换到二进制序列化器后不再列出旧 `.json`(设计取舍)。

## 原子写(temp + rename)

`save()` 先写临时文件 `<slot>.<ext>.tmp`,`close` 后再 `rename` 到目标(`_atomic_replace`)。写入过程崩溃只会留下不完整的 `.tmp`(扩展名 `.tmp`,不被 `list_slots` 计入),目标文件永不出现"写一半"的中间态。桌面平台 `DirAccess.rename_absolute` 原子覆盖已存在目标;个别平台 rename 不覆盖时回退"先删目标再 rename"。Web(IndexedDB)上 rename 非严格原子,但 tmp 始终是完整文件,仍消除了目标被写一半的窗口。rename(含回退)失败 -> `save_failed(slot, "rename_error")`、清理 tmp、返回 false。

## 资源引用安全约定

SaveManager 只吃纯数据(JSON-native 类型)。`save()` 落盘前递归扫描 `data`,凡含 `Object`/`Resource`/`Node`/`Callable`/`Signal`/`RID` 即拒写并 `save_failed(slot, "unserializable")`、返回 false、不落盘。

约定:存 `resource_path` 字符串而非整个 `Resource`;load 回来后由消费方在受控点自行 `load(path)` 重建。整存 Resource -> load 时 `ResourceLoader` 重建任意资源 = 代码注入面(`.tres` 可携带脚本),守卫在运行期强制该边界。

自定义 serializer 警示:解码不可信存档的 serializer 不得启用对象反序列化(如用 `bytes_to_var` 须传 `allow_objects=false`,勿用会触发 `ResourceLoader` 的通道),否则绕过上述边界。默认 `JsonSaveSerializer` 天然只产 JSON-native 类型,无此风险。

## 注意事项

- **命名坑**:`load()` 在本脚本体内会遮蔽 GDScript 内置全局函数 `load(path)`(与 `CoreKit.log` 遮蔽全局 `log()` 同理);脚本内部从不需要调用全局 `load()`,外部通过 `CoreKit.saves.load(...)` 调用不受影响。
- **存档位名称白名单清洗**:只保留 `[A-Za-z0-9_-]`,清洗后为空(原始输入为空/纯空白/全部字符非法)一律拒绝(视为失败),不回退到某个默认存档位。
- **版本号仅记录、不迁移**:`_version` 与当前 `SCHEMA_VERSION` 不一致时按原样加载并 `CoreKit.log.warn`,v1 无迁移逻辑。
- **JSON int→float**:与 Settings 同理,数据经 JSON 落盘往返后 int 会变 float,取整用 `int(...)`。
- 原子写:`save()` 走 temp+rename,写入中断只留不完整的 `.tmp`(不被 `list_slots` 计入),目标不出现写一半态。损坏内容(序列化器 `decode` 返回 `{}` 或信封校验不过)一律触发 `load_failed(slot, "corrupt")`,不删除原文件。
