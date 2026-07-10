# SaveManager 可插拔序列化 + 原子写 + 资源守卫 设计(v0.7.0)

> 阶段 2「直接借鉴纳入」子项目 2/3。借鉴 godot-savekit 的轻量子集(可插拔序列化 / 资源存引用避 ResourceLoader 注入)。
> 现状文件:`addons/godot-core-kit/systems/save_manager.gd`(autoload,门面为 `CoreKit.saves`)。
> 原则:纯叠加,**现有公开 API 语义与签名一律不动、默认 JSON 逐字节兼容**,全程 TDD。

---

## 1. 目标 & 动机

`SaveManager` 现状:只吃 `Dictionary`,`{_version, data}` JSON 信封,slot 化,白名单消毒,失败信号;`_encode`/`_decode` 为可测纯函数接缝。三个真实缺口(godot-savekit 已解):

1. **序列化写死 JSON**:无法换二进制 / 压缩 / 自定义格式。需**可插拔序列化策略**。
2. **直写目标文件**:`save()` 直接 `FileAccess.WRITE` 目标文件(save_manager.gd:41-47),写一半崩溃 → 存档损坏。需**原子写**(temp + rename)。
3. **资源整存风险无拦截**:现状只吃 Dictionary 天然规避,但把 `Resource`/`Object` 塞进 dict 时 `JSON.stringify` 静默产 `null`(数据丢失),且「整存 Resource + load 时重建」正是 `ResourceLoader` 代码注入面。需**运行时守卫 + 文档约定**固化「存 `resource_path` 引用而非整个 Resource」。

本子项目为三者各加一条,叠加在既有落盘之上。版本 **0.6.0 → 0.7.0**。

---

## 2. 现状(保持不变、向后兼容)

- 公开:`save(slot, data) -> bool`、`load(slot) -> Dictionary`、`has_slot(slot) -> bool`、`delete_slot(slot) -> bool`、`list_slots() -> Array[String]`。
- 信号:`saved(slot)`、`save_failed(slot, reason)`、`loaded(slot)`、`load_failed(slot, reason)`、`slot_deleted(slot)`。
- 常量:`SAVE_DIR := "user://saves"`、`SCHEMA_VERSION := 1`。
- 私有接缝:`_sanitize_slot_name`、`_slot_path`、`_encode`、`_decode`。
- 依赖:仅 `CoreKit.log`(版本不匹配 warn),无其它子系统依赖。

**这些公开方法的签名与语义在本子项目中零改动**;默认 JSON 序列化器保证写出/读回**逐字节等同**现有 `.json` 存档。私有接缝 `_encode`/`_decode` 迁入序列化器(见 §5.4),其现有直测随之迁移。

---

## 3. 新增能力 A:可插拔序列化(SaveSerializer 基类)

### 3.1 接口(字节化,以支持二进制/压缩)

新增 `addons/godot-core-kit/systems/save_serializer.gd`:

```gdscript
class_name SaveSerializer
extends RefCounted
## 存档序列化策略抽象基类(off-facade 类库)。只负责 Dictionary ↔ 字节的转换;
## 信封 {_version, data} 与版本校验由 SaveManager 负责,序列化器不感知其结构。

## Dictionary → 字节。子类必须覆写。
func encode(dict: Dictionary) -> PackedByteArray:
    push_error("SaveSerializer.encode 未覆写(抽象基类)")
    return PackedByteArray()

## 字节 → Dictionary。格式解析失败(非法字节 / 根非字典)返回 {}(损坏契约)。子类必须覆写。
func decode(bytes: PackedByteArray) -> Dictionary:
    push_error("SaveSerializer.decode 未覆写(抽象基类)")
    return {}

## 该格式的文件扩展名(不含点,如 "json" / "bin")。子类必须覆写。
func extension() -> String:
    push_error("SaveSerializer.extension 未覆写(抽象基类)")
    return ""
```

### 3.2 默认实现:JsonSaveSerializer

新增 `addons/godot-core-kit/systems/json_save_serializer.gd`:

```gdscript
class_name JsonSaveSerializer
extends SaveSerializer
## 默认 JSON 序列化器。与旧 _encode/_decode 逐字节兼容:缩进 "\t"、UTF-8、扩展名 "json"。

func encode(dict: Dictionary) -> PackedByteArray:
    return JSON.stringify(dict, "\t").to_utf8_buffer()

func decode(bytes: PackedByteArray) -> Dictionary:
    var parsed = JSON.parse_string(bytes.get_string_from_utf8())
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed

func extension() -> String:
    return "json"
```

> **字节兼容论证**:旧 `save()` 走 `file.store_string(JSON.stringify(env, "\t"))`(UTF-8 写、无 BOM、无长度前缀);新走 `store_buffer(JSON.stringify(env, "\t").to_utf8_buffer())` —— 同一 UTF-8 字节序列,逐字节一致。旧 `load()` 走 `get_as_text()`(UTF-8 解码),新走 `get_buffer(len).get_string_from_utf8()` —— 同结果。现有 `.json` 存档双向兼容。

### 3.3 SaveManager 集成

```gdscript
var _serializer: SaveSerializer = JsonSaveSerializer.new()

## 替换序列化策略。null 忽略并 push_error;换后影响后续 save/load(不改动已落盘文件)。
func set_serializer(s: SaveSerializer) -> void:
    if s == null:
        push_error("SaveManager.set_serializer: 拒绝 null")
        return
    _serializer = s
```

- `_slot_path(slot)` 扩展名改由 `_serializer.extension()` 驱动:`"%s/%s.%s" % [SAVE_DIR, slot, _serializer.extension()]`。
- `list_slots()` 扩展名过滤改为 `_serializer.extension()`(而非硬编码 `"json"`);basename 剥离逻辑不变。
- **语义**:换 serializer 后,`list_slots`/`has_slot`/`load`/`delete_slot` 只见当前格式的文件(各 serializer 管自己的扩展名)。默认 JSON 保持 `.json`,存量存档不受影响。此约定写入文档。

---

## 4. 新增能力 B:原子写(temp + rename)

### 4.1 算法(改写 `save()` 落盘段)

```
save(slot, data):
    safe = _sanitize_slot_name(slot);  空 → save_failed("invalid_slot_name"); return false
    if _has_unserializable(data):       save_failed("unserializable"); return false     # §5
    envelope = {"_version": SCHEMA_VERSION, "data": data}
    bytes = _serializer.encode(envelope)
    if bytes.is_empty():                save_failed("encode_error"); return false
    DirAccess.make_dir_recursive_absolute(SAVE_DIR)
    target = _slot_path(safe);  tmp = target + ".tmp"
    f = FileAccess.open(tmp, WRITE)
    if f == null:                       save_failed("open_error:%d" % get_open_error()); return false
    f.store_buffer(bytes);  f.close()
    if not _atomic_replace(tmp, target):
        DirAccess.remove_absolute(tmp)  # 清理残留 tmp(best-effort)
        save_failed("rename_error");    return false
    saved.emit(safe);  return true
```

### 4.2 `_atomic_replace(tmp, target) -> bool`

```
_atomic_replace(tmp, target):
    if DirAccess.rename_absolute(tmp, target) == OK: return true
    # 兜底:部分平台 rename 不覆盖已存在目标 → 先删目标再 rename
    if FileAccess.file_exists(target):
        DirAccess.remove_absolute(target)
        return DirAccess.rename_absolute(tmp, target) == OK
    return false
```

- **平台核实(writing-plans 阶段)**:确认 Godot 4 `DirAccess.rename_absolute` 覆盖已存在目标的行为;若原生覆盖(POSIX rename 原子替换)则兜底分支永不触发。文档标注:Web(IndexedDB)上 rename 非严格原子,但 tmp 始终是完整文件,**消除了目标被写一半的窗口**(核心收益)。
- tmp 文件扩展名为 `.tmp`(非 serializer 扩展名),故即便残留也**不被 `list_slots` 计入**。

---

## 5. 新增能力 C:资源引用安全守卫

### 5.1 运行时守卫

`save()` 在建信封前递归扫描 `data`,凡值类型属**不可持久化集** `{TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID}`(含 `Resource`/`Node`/自定义 `Object`)即拒写:

```gdscript
## data 中是否存在不可序列化的值(递归 Dictionary 值 + Array 元素)。
func _has_unserializable(v: Variant) -> bool:
    match typeof(v):
        TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
            return true
        TYPE_DICTIONARY:
            for k in v:
                if _has_unserializable(v[k]):
                    return true
            return false
        TYPE_ARRAY:
            for e in v:
                if _has_unserializable(e):
                    return true
            return false
        _:
            return false
```

- 命中 → `save_failed(slot, "unserializable")`,返回 false,**不落盘**。
- **不拒** `Vector2`/`Color` 等值类型:那是 JSON 格式局限而非注入面,且二进制 serializer 可原生存(`var_to_bytes`)。守卫只挡「永不该持久化的句柄/对象类型」,与 serializer 无关(通用安全原则)。

### 5.2 文档固化

`save_manager.gd` 脚本头 + `docs/systems/save-manager.md` 明确:

- **存 `resource_path` 字符串而非整个 `Resource`**;load 回来后自行 `load(path)` 重建(由消费方在受控点做,而非存档系统盲目反序列化任意 Resource)。
- **为何**:整存 Resource → load 时 `ResourceLoader` 重建任意资源 = 代码注入面(`.tres` 可携带脚本)。SaveManager 只吃纯数据(JSON-native 类型),守卫在运行期强制该边界。
- **自定义 serializer 警示**(文档):解码不可信存档的 serializer **不得启用对象反序列化**(如用 `bytes_to_var` 须传 `allow_objects=false`,勿用会执行 `ResourceLoader` 的通道)——否则绕过上述边界。默认 `JsonSaveSerializer` 天然只产 JSON-native 类型,无此风险。

---

## 6. 数据流

- **save**:消毒 slot → `_has_unserializable` 守卫 → 建信封 → `_serializer.encode` → 原子写(tmp→rename)→ `saved`。
- **load**:消毒 slot → 存在性检查 → 读字节(`get_buffer`)→ `_serializer.decode` → SaveManager `_is_valid_envelope` 校验(`_version`/`data` 存在、`_version` 标量、`data` 是 Dictionary)→ 版本不匹配 warn(现有逻辑)→ 返回 `envelope["data"]`;任一失败 `load_failed` + 返回 `{}`。

信封校验 `_is_valid_envelope(env: Dictionary) -> bool` 为 SaveManager 私有可测接缝(承接旧 `_decode` 的 has/类型检查那段):

```gdscript
func _is_valid_envelope(env: Dictionary) -> bool:
    if not env.has("_version") or not env.has("data"):
        return false
    if typeof(env["_version"]) not in [TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
        return false
    return typeof(env["data"]) == TYPE_DICTIONARY
```

---

## 7. 错误处理 & 信号

复用现有 5 信号。`save_failed` 的 `reason` 新增三种,现有不变:

| reason | 触发 |
|---|---|
| `invalid_slot_name` | 消毒后空(现有) |
| `unserializable` | **新**:守卫命中 Object/Callable/Signal/RID |
| `encode_error` | **新**:`_serializer.encode` 返回空 `PackedByteArray` |
| `open_error:%d` | tmp 文件打开失败(现有格式,对象改为 tmp) |
| `rename_error` | **新**:原子交换(含兜底)失败 |

`load_failed` reason(`invalid_slot_name`/`not_found`/`open_error:%d`/`corrupt`)不变。`corrupt` 现覆盖:serializer.decode 返回 {} **或** 信封校验不过。

---

## 8. 不变式 / 向后兼容

1. `save`/`load`/`has_slot`/`delete_slot`/`list_slots` 签名与语义不变;默认 JSON 下**逐字节兼容**现有 `.json` 存档。
2. 未调 `set_serializer` 时,行为等价现状(默认 `JsonSaveSerializer`)。
3. 信封 `{_version, data}` 结构与 `SCHEMA_VERSION`、版本不匹配 warn 逻辑不变。
4. 资源守卫**只新增拒绝路径**:合法纯数据 dict 的 save 行为不变(守卫对其恒 false)。
5. 无新第三方依赖;仅 `CoreKit.log` 依赖不变;两个新类为 off-facade `class_name` 类库(与 `KitContext`/`KitStateMachine` 同层),不挂门面、不新增 autoload。

---

## 9. 边界 & 坑

- **class_name 缓存**:新增 `SaveSerializer`/`JsonSaveSerializer` 后,headless `-s` 测试前若报类解析错误,先 `godot --headless --path . --import`。二者为 `class_name` 类型(非 autoload),不受「autoload 注册晚于 -s preload」限制;但 `test_save_manager.gd` 用 `load(save_manager.gd).new()`,而 save_manager `var _serializer := JsonSaveSerializer.new()` 依赖全局类表 → 测试前须 `--import`(现有测试已有此前提)。
- **换 serializer 后存量不可见**:换到二进制 serializer 后 `list_slots` 不列旧 `.json`(各管自己扩展名)——设计取舍,文档标注。
- **rename 覆盖语义**:见 §4.2,writing-plans 核实平台行为。
- **守卫递归深度**:极深/自引用 dict 理论上可栈溢出;存档数据结构本就要求 JSON-native(无环),不额外加环检测(YAGNI,文档提示存 plain data)。

---

## 10. 测试(TDD,`test/test_save_manager.gd`,`extends SceneTree`)

新增 / 迁移段落(沿用现有 `SaveManagerScript.new()` 惯例):

1. **JsonSaveSerializer 直测**(承接旧 `_encode`/`_decode` 段):`encode(env)` 输出即合法 JSON;`decode(encode(x)) == x`;非法字节 → `{}`;`decode` 根非字典 → `{}`;`extension() == "json"`。
2. **JSON 字节兼容**:`JsonSaveSerializer.new().encode({"_version":1,"data":{"a":1}})` 的字节 == 旧 `store_string` 路径字节(`JSON.stringify(env,"\t").to_utf8_buffer()`)——逐字节相等,锁 back-compat。
3. **信封校验接缝**:`_is_valid_envelope` 对缺键 / 非标量 `_version` / 非字典 `data` 返回 false,对合法信封 true。
4. **serializer swap 往返**:注入一个测试用 serializer(如 upper-case 包裹或 `var_to_bytes` 二进制,`extension()=="bin"`);`save`→`load` 往返数据一致;`list_slots` 按 `.bin` 列出、不列 `.json`。
5. **原子写成功**:`save` 后 `<slot>.<ext>.tmp` 不残留、目标文件存在且 `load` 完整;`list_slots` 不含 tmp。
6. **原子写失败清理**:构造 rename 失败场景(如目标路径被目录占位)→ `save_failed("rename_error")`、返回 false、tmp 已清理。(若难以在 headless 稳定构造,退化为对 `_atomic_replace` 纯逻辑的直测。)
7. **资源守卫**:`save(slot, {"res": Resource.new()})` 与嵌套 `{"bag": [Resource.new()]}` → `save_failed("unserializable")`、返回 false、目标文件未创建;`_has_unserializable` 对纯数据 dict 返回 false、对含 Callable/Object 返回 true。
8. **回归**:现有全部公开断言(save/load 往返、覆盖、not_found、corrupt、invalid_slot_name、delete、list_slots 排序、sanitize)保持通过。

`demo/demo.gd` 的 SaveManager 段落追加:守卫拒 Object 冒烟(`save` 含 `Resource.new()` → false)+ 一次 `set_serializer` 往返冒烟(可选,注入极简 serializer);现有 save/load/delete 冒烟保留。

---

## 11. 版本 & 文档

- `core_kit.gd` `VERSION` 与 `plugin.cfg` `version`:`0.6.0` → **`0.7.0`**;`plugin.cfg` description 末尾追加本次能力。
- `docs/systems/save-manager.md`:新增「可插拔序列化(SaveSerializer)」「原子写」「资源引用安全约定」三节 + API 补 `set_serializer`;`architecture.md`「## 版本」与 `README.md` changelog 补 0.7.0 条目。

---

## 12. 明确不做(YAGNI,留待有真实需求)

- 迁移引擎(仅保留 `_version` 字段 + 不匹配 warn)。
- 加密 / 校验和(可由自定义 serializer 承载,核心不内建)。
- 存档 registry / 自动收集、存档位元数据(缩略图 / 时长 / 时间戳)。
- godot-savekit 的反射自动序列化通道(SaveManager 只吃 Dictionary,不做对象反射)。
- 多 serializer 并存索引(同一时刻单一 `_serializer`)。
- 异步 / 线程化存档(现有同步 API 在 Web 亦同步)。
- `_has_unserializable` 的循环引用检测。
