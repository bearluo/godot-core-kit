# SaveManager 可插拔序列化 + 原子写 + 资源守卫 实现计划(v0.7.0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 `SaveManager` 叠加三条能力——可插拔序列化策略(`SaveSerializer` 基类 + 默认 `JsonSaveSerializer`)、原子写(temp+rename)、资源引用安全守卫——纯叠加,现有公开 API 与默认 `.json` 存档逐字节兼容。

**Architecture:** 序列化职责从 `SaveManager` 私有 `_encode`/`_decode` 抽出为 off-facade `class_name` 策略类(`systems/` 目录,与 `KitContext`/`KitStateMachine` 同层,不挂门面、不新增 autoload)。`SaveManager` 持有一个 `_serializer` 引用,`save`/`load` 走字节 I/O,信封 `{_version, data}` 与版本校验仍留在 `SaveManager`(新增 `_is_valid_envelope` 接缝)。落盘改为先写 `.tmp` 再 `rename`。`save` 落盘前递归守卫拒 `Object/Callable/Signal/RID`。

**Tech Stack:** Godot 4.7 GDScript,`FileAccess`/`DirAccess`/`JSON`/`var_to_bytes` 全平台同步 API,无第三方依赖。headless 断言测试(`extends SceneTree`)。

## Global Constraints

以下为全项目约束,每个 Task 的要求都隐含包含本节(值逐字来自 spec `docs/superpowers/specs/2026-07-10-savemanager-serializer-atomic-resource-design.md`):

- **公开 API 零改动**:`save(slot, data) -> bool`、`load(slot) -> Dictionary`、`has_slot(slot) -> bool`、`delete_slot(slot) -> bool`、`list_slots() -> Array[String]` 的签名与语义在本项目中不变。
- **默认 JSON 逐字节兼容**:`JsonSaveSerializer.encode(env)` 必须等于 `JSON.stringify(env, "\t").to_utf8_buffer()`(旧 `store_string(JSON.stringify(env,"\t"))` 的同一 UTF-8 字节序列);读回等价。现有 `.json` 存档双向兼容。
- **私有接缝迁移**:`_encode`/`_decode` 迁入序列化器,其现有直测随之迁移(不保留死方法)。
- **零新依赖**:不新增第三方依赖;仅 `CoreKit.log` 依赖不变(版本不匹配 warn)。
- **off-facade 类库**:`SaveSerializer`/`JsonSaveSerializer` 为 `class_name` 类(放 `addons/godot-core-kit/systems/`),不挂门面、不新增 autoload。
- **版本**:`0.6.0` -> `0.7.0`,`core_kit.gd` 的 `const VERSION` 与 `plugin.cfg` 的 `version` 同源。
- **新增 save_failed reason**:`unserializable`、`encode_error`、`rename_error`(现有 `invalid_slot_name`、`open_error:%d` 不变)。`corrupt` 现覆盖 serializer.decode 返回 `{}` 或信封校验不过。
- **rename 覆盖行为(已实测 Godot 4.7 win64)**:`DirAccess.rename_absolute` 原子覆盖已存在目标(源消失、目标为新内容、返回 `OK`);`_atomic_replace` 的"先删再 rename"回退分支为跨平台防御(桌面永不触发)。
- **全程 TDD**:先写失败测试 -> 跑到红 -> 最小实现 -> 跑到绿 -> commit。测试文件 `test/test_save_manager.gd`(`extends SceneTree`),打印 `test_save_manager: ALL PASS` + `quit(0)`,失败 `quit(1)`。
- **Godot 只经 PowerShell 工具跑**(Git Bash `godot` = exit 127;`pwsh` 本机没有)。运行命令(在仓库根,PowerShell 工具内执行)——解析 godot .exe(run_all.ps1 同款):`$g = (Get-Command godot).Source; if ($g -match '\.(cmd|bat)$') { $g = (Select-String -Path $g -Pattern '"([^"]+\.exe)"').Matches[0].Groups[1].Value }`。import(新增/改名 class_name 文件后必跑一次):`& $g --headless --path . --import 2>&1 | Select-String -Pattern 'ERROR|SCRIPT'`。跑单测:`& $g --headless --path . -s res://test/test_save_manager.gd 2>&1 | Select-String -Pattern 'PASS|FAIL|SCRIPT ERROR|Nonexistent|Parse'`。下文「运行单测」即最后一条,「先 import」即 import 那条;只有新增/改名 class_name 文件的 Task(T1、T2 建 bin 序列化器)在首次跑测前需 import。
- **全量绿**:收尾用 `& .\test\run_all.ps1`(import -> 13 测试 -> demo 冒烟),末行 `=== SUMMARY FAILS=0 ===` 为全绿。
- **提交纪律**:每个 Task 独立 commit;提交信息末行必须是 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`。不 push(用户自己 push)。

---

## 文件结构

| 文件 | 动作 | 职责 |
|---|---|---|
| `addons/godot-core-kit/systems/save_serializer.gd` | 新建(T1) | `class_name SaveSerializer` 抽象基类:`encode`/`decode`/`extension` 三个必覆写方法 |
| `addons/godot-core-kit/systems/json_save_serializer.gd` | 新建(T1) | `class_name JsonSaveSerializer extends SaveSerializer`:默认 JSON 实现,逐字节兼容旧路径 |
| `test/bin_test_serializer.gd` | 新建(T2) | 测试专用二进制序列化器(`var_to_bytes`/`extension()=="bin"`),验证 serializer 可替换 |
| `addons/godot-core-kit/systems/save_manager.gd` | 改(T2/T3/T4) | 集成 `_serializer`、`set_serializer`、扩展名驱动路径、字节 I/O、`_is_valid_envelope`、原子写、资源守卫;删除 `_encode`/`_decode` |
| `test/test_save_manager.gd` | 改(T1-T4) | 迁移 `_encode`/`_decode` 直测到序列化器直测;新增信封接缝/swap/原子写/守卫测试段 |
| `addons/godot-core-kit/core_kit.gd` | 改(T5) | `VERSION` 0.6.0 -> 0.7.0 |
| `addons/godot-core-kit/plugin.cfg` | 改(T5) | `version` 0.6.0 -> 0.7.0 + description 追加本次能力 |
| `addons/godot-core-kit/docs/systems/save-manager.md` | 改(T5) | 新增三节 + `set_serializer` API + 注意事项更新 |
| `addons/godot-core-kit/docs/architecture.md` | 改(T5) | 「## 版本」追加 0.7.0 条目 |
| `README.md` | 改(T5) | changelog 追加 0.7.0 条目 |
| `demo/demo.gd` | 改(T5) | SaveManager 段追加资源守卫拒 Object 冒烟 |

---

## Task 1: SaveSerializer 基类 + JsonSaveSerializer 默认实现

**Files:**
- Create: `addons/godot-core-kit/systems/save_serializer.gd`
- Create: `addons/godot-core-kit/systems/json_save_serializer.gd`
- Test: `test/test_save_manager.gd`(新增 `_test_serializer()`,不动 `save_manager.gd`)

**Interfaces:**
- Consumes:无(纯新增两个独立类)。
- Produces:
  - `SaveSerializer`(`class_name`,`extends RefCounted`):`encode(dict: Dictionary) -> PackedByteArray`(基类 push_error + 返回空)、`decode(bytes: PackedByteArray) -> Dictionary`(基类 push_error + 返回 `{}`)、`extension() -> String`(基类 push_error + 返回 `""`)。
  - `JsonSaveSerializer`(`class_name`,`extends SaveSerializer`):`encode` = `JSON.stringify(dict, "\t").to_utf8_buffer()`;`decode` = 解析 UTF-8->JSON,根非 Dictionary 返回 `{}`;`extension()` = `"json"`。
  - T2 依赖:`SaveManager` 将 `var _serializer: SaveSerializer = JsonSaveSerializer.new()` 并调 `_serializer.encode/decode/extension`。

- [ ] **Step 1: 写基类 save_serializer.gd**

创建 `addons/godot-core-kit/systems/save_serializer.gd`:

```gdscript
class_name SaveSerializer
extends RefCounted
## 存档序列化策略抽象基类(off-facade 类库,不挂门面)。只负责 Dictionary <-> 字节的
## 转换;信封 {_version, data} 与版本校验由 SaveManager 负责,序列化器不感知其结构。
## 子类必须覆写全部三个方法。

## Dictionary -> 字节。子类必须覆写。
func encode(dict: Dictionary) -> PackedByteArray:
	push_error("SaveSerializer.encode 未覆写(抽象基类)")
	return PackedByteArray()

## 字节 -> Dictionary。格式解析失败(非法字节 / 根非字典)返回 {}(损坏契约)。子类必须覆写。
func decode(bytes: PackedByteArray) -> Dictionary:
	push_error("SaveSerializer.decode 未覆写(抽象基类)")
	return {}

## 该格式的文件扩展名(不含点,如 "json" / "bin")。子类必须覆写。
func extension() -> String:
	push_error("SaveSerializer.extension 未覆写(抽象基类)")
	return ""
```

- [ ] **Step 2: 写默认实现 json_save_serializer.gd**

创建 `addons/godot-core-kit/systems/json_save_serializer.gd`:

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

- [ ] **Step 3: 写失败测试 _test_serializer()**

在 `test/test_save_manager.gd` 顶部 `var SaveManagerScript` 之后新增两个脚本句柄变量:

```gdscript
var SaveManagerScript
var SaveSerializerScript
var JsonSaveSerializerScript
```

在 `_initialize()` 里,`SaveManagerScript = load(...)` 之后追加两行 load,并把 `_test_serializer()` 接入 failures 累加链:

```gdscript
func _initialize() -> void:
	SaveManagerScript = load("res://addons/godot-core-kit/systems/save_manager.gd")
	SaveSerializerScript = load("res://addons/godot-core-kit/systems/save_serializer.gd")
	JsonSaveSerializerScript = load("res://addons/godot-core-kit/systems/json_save_serializer.gd")

	var failures := 0
	failures += _test_pure_seams()
	failures += _test_serializer()
	failures += _test_disk_roundtrip()

	if failures == 0:
		print("test_save_manager: ALL PASS")
		quit(0)
	else:
		print("test_save_manager: %d FAILURE(S)" % failures)
		quit(1)
```

在文件末尾(`_test_disk_roundtrip` 之后)新增测试函数:

```gdscript
## ============================================================
## T1: SaveSerializer 基类 + JsonSaveSerializer 直测(承接旧 _encode/_decode 段)。
## 序列化器信封无关:encode/decode 直接吞吐任意 Dictionary,不再包 {_version,data}。
## ============================================================
func _test_serializer() -> int:
	var failures := 0
	var json = JsonSaveSerializerScript.new()

	# 1. 任意纯数据 dict 往返一致(_values_equal 容忍 JSON int->float)
	var sample := {
		"level": 3,
		"hp": 87.5,
		"name": "hero",
		"alive": true,
		"inventory": ["sword", "shield", 42],
		"stats": {"str": 10, "dex": 7},
	}
	if not _values_equal(json.decode(json.encode(sample)), sample):
		print("FAIL JsonSaveSerializer 往返不一致,得到 %s" % [json.decode(json.encode(sample))])
		failures += 1

	# 2. 空 dict:encode 非空字节、decode 回空 dict(不再包信封)
	if json.encode({}).is_empty():
		print("FAIL JsonSaveSerializer.encode({}) 不应为空字节")
		failures += 1
	if json.decode(json.encode({})) != {}:
		print("FAIL JsonSaveSerializer.decode(encode({})) 应为 {}")
		failures += 1

	# 3. 非法字节 -> {}
	if json.decode("not valid json {{{".to_utf8_buffer()) != {}:
		print("FAIL JsonSaveSerializer.decode(非法字节) 应为 {}")
		failures += 1

	# 4. 合法 JSON 但根非字典 -> {}
	if json.decode("42".to_utf8_buffer()) != {}:
		print("FAIL JsonSaveSerializer.decode('42') 应为 {}")
		failures += 1

	# 5. extension
	if json.extension() != "json":
		print("FAIL JsonSaveSerializer.extension() 应为 'json',得到 '%s'" % json.extension())
		failures += 1

	# 6. 字节兼容:encode(信封) 逐字节 == 旧 store_string 路径的 UTF-8 字节(锁 back-compat)
	var env := {"_version": 1, "data": {"a": 1}}
	if json.encode(env) != JSON.stringify(env, "\t").to_utf8_buffer():
		print("FAIL JsonSaveSerializer.encode 应等价 JSON.stringify(env, tab).to_utf8_buffer()")
		failures += 1

	# 7. 抽象基类:未覆写返回空/默认(不崩溃)
	var base = SaveSerializerScript.new()
	if not base.encode({}).is_empty():
		print("FAIL SaveSerializer.encode 抽象基类应返回空字节")
		failures += 1
	if base.decode(PackedByteArray()) != {}:
		print("FAIL SaveSerializer.decode 抽象基类应返回 {}")
		failures += 1
	if base.extension() != "":
		print("FAIL SaveSerializer.extension 抽象基类应返回 ''")
		failures += 1

	return failures
```

- [ ] **Step 4: 先 import,再运行单测确认失败(RED)**

先 import(新增了两个 class_name 文件),再运行单测(命令见 Global Constraints)。
Expected: import 之前 `load("json_save_serializer.gd")` 因 `SaveSerializer` 未注册而失败,单测报 `Parse`/`Nonexistent` -> RED。先确认该失败成因是"新类尚未被 import 注册"。

> TDD 说明:本 Task 两个类是全新文件,没有"实现前"中间态可跑红。RED 体现为「import 之前类不可解析」;Step 1-3 文件写好并 import 后即绿(spec §9 已述 class_name 缓存前提)。

- [ ] **Step 5: import 后运行单测确认通过(GREEN)**

先 import,再运行单测。
Expected: `test_save_manager: ALL PASS`,退出码 0。(此时 `save_manager.gd` 未改,旧 `_test_pure_seams`/`_test_disk_roundtrip` 仍全绿。)

- [ ] **Step 6: 提交**

```
git add addons/godot-core-kit/systems/save_serializer.gd addons/godot-core-kit/systems/json_save_serializer.gd test/test_save_manager.gd
```
提交信息(here-string,末行 Co-Authored-By 必带):
```
feat(save): add SaveSerializer strategy base + default JsonSaveSerializer

字节化序列化策略抽象基类(off-facade class_name),默认 JSON 实现与旧
_encode/_decode 逐字节兼容(缩进 tab、UTF-8、扩展名 json)。含直测:往返、
非法字节、根非字典、extension、字节兼容、抽象基类默认返回。SaveManager
尚未集成(下个 Task)。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```

---

## Task 2: SaveManager 集成序列化器(字节 I/O + 扩展名驱动路径 + 信封接缝)

**Files:**
- Modify: `addons/godot-core-kit/systems/save_manager.gd`
- Create: `test/bin_test_serializer.gd`
- Modify: `test/test_save_manager.gd`

**Interfaces:**
- Consumes(来自 T1):`SaveSerializer`、`JsonSaveSerializer`(`encode(dict)->PackedByteArray`、`decode(bytes)->Dictionary`、`extension()->String`)。
- Produces:
  - `SaveManager.set_serializer(s: SaveSerializer) -> void`(null 忽略 + push_error)。
  - `SaveManager._is_valid_envelope(env: Dictionary) -> bool`(私有接缝:有 `_version`/`data`、`_version` in {int,float,string}、`data` 是 Dictionary)。
  - `SaveManager._slot_path(slot)` 扩展名改由 `_serializer.extension()` 驱动。
  - `save` 走 `_serializer.encode` + `store_buffer`(本 Task 仍直写目标文件,原子写在 T3);新 reason `encode_error`。
  - `load` 走 `get_buffer` + `_serializer.decode` + `_is_valid_envelope`;`corrupt` 覆盖 decode-`{}` 或信封不过。
  - `save_manager.gd` 不再有 `_encode`/`_decode`。

- [ ] **Step 1: 写测试专用 .bin 序列化器 + 两个新测试段**

创建 `test/bin_test_serializer.gd`(路径式 `extends`,不依赖全局类缓存):

```gdscript
extends "res://addons/godot-core-kit/systems/save_serializer.gd"
## 测试专用:二进制序列化器,证明 SaveManager 的 serializer 可替换、扩展名随之切换。
## var_to_bytes 保留 int 类型(不像 JSON 会 int->float),allow_objects 默认 false。

func encode(dict: Dictionary) -> PackedByteArray:
	return var_to_bytes(dict)

func decode(bytes: PackedByteArray) -> Dictionary:
	var v = bytes_to_var(bytes)
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	return v

func extension() -> String:
	return "bin"
```

在 `test/test_save_manager.gd` 的 `_initialize()` failures 链中接入两个新段(顺序放在 `_test_serializer()` 之后、`_test_disk_roundtrip()` 之前):

```gdscript
	var failures := 0
	failures += _test_pure_seams()
	failures += _test_serializer()
	failures += _test_envelope_seam()
	failures += _test_serializer_swap()
	failures += _test_disk_roundtrip()
```

文件末尾新增两个函数:

```gdscript
## ============================================================
## T2: 信封校验接缝 _is_valid_envelope(承接旧 _decode 的 has/类型检查那段)。
## ============================================================
func _test_envelope_seam() -> int:
	var failures := 0
	var sm = SaveManagerScript.new()

	if not sm._is_valid_envelope({"_version": 1, "data": {}}):
		print("FAIL _is_valid_envelope 合法信封应为 true")
		failures += 1
	if sm._is_valid_envelope({}):
		print("FAIL _is_valid_envelope 缺键应为 false")
		failures += 1
	if sm._is_valid_envelope({"_version": 1}):
		print("FAIL _is_valid_envelope 缺 data 应为 false")
		failures += 1
	if sm._is_valid_envelope({"_version": {}, "data": {}}):
		print("FAIL _is_valid_envelope 非标量 _version 应为 false")
		failures += 1
	if sm._is_valid_envelope({"_version": 1, "data": "not a dict"}):
		print("FAIL _is_valid_envelope 非字典 data 应为 false")
		failures += 1

	sm.free()
	return failures


## ============================================================
## T2: 注入非默认 serializer(.bin)后 save/load 往返 + list_slots 只见当前扩展名。
## ============================================================
func _test_serializer_swap() -> int:
	var failures := 0
	var sm = SaveManagerScript.new()
	var slot := "__test_swap__"

	# 先用默认(json)存一个同名槽,稍后证明换到 .bin 后 list_slots 不再列它
	var json_path: String = sm._slot_path(slot)   # user://saves/<slot>.json
	if FileAccess.file_exists(json_path):
		DirAccess.remove_absolute(json_path)
	sm.save(slot, {"fmt": "json"})

	# 换到 .bin serializer
	var bin = load("res://test/bin_test_serializer.gd").new()
	sm.set_serializer(bin)

	# 换后 _slot_path 扩展名随之变化
	var bin_path: String = sm._slot_path(slot)
	if not bin_path.ends_with(".bin"):
		print("FAIL 换 serializer 后 _slot_path 应以 .bin 结尾,得到 '%s'" % bin_path)
		failures += 1

	# save->load 往返数据一致
	var payload := {"score": 7, "tag": "bin"}
	if not sm.save(slot, payload):
		print("FAIL 换 serializer 后 save 应为 true")
		failures += 1
	if not _values_equal(sm.load(slot), payload):
		print("FAIL 换 serializer 后 load 往返不一致,得到 %s" % [sm.load(slot)])
		failures += 1

	# list_slots 现按 .bin 过滤:含本槽(各 serializer 管自己扩展名)
	if not sm.list_slots().has(slot):
		print("FAIL 换 serializer 后 list_slots 应含 '%s'(.bin)" % slot)
		failures += 1

	# 换回默认 json:list_slots 又能看见 .json 槽(证明按扩展名隔离,而非删了文件)
	sm.set_serializer(JsonSaveSerializerScript.new())
	if not sm.list_slots().has(slot):
		print("FAIL 换回 json 后 list_slots 应重新含 '%s'(.json)" % slot)
		failures += 1

	# set_serializer(null) 被拒:_slot_path 仍是 .json
	sm.set_serializer(null)
	if not sm._slot_path(slot).ends_with(".json"):
		print("FAIL set_serializer(null) 应被拒,_slot_path 仍应 .json")
		failures += 1

	# 清理两个格式的文件
	if FileAccess.file_exists(json_path):
		DirAccess.remove_absolute(json_path)
	if FileAccess.file_exists(bin_path):
		DirAccess.remove_absolute(bin_path)
	sm.free()
	return failures
```

- [ ] **Step 2: 运行单测确认失败(RED)**

先 import(新增了 `bin_test_serializer.gd`),再运行单测。
Expected: RED——`_test_envelope_seam` 调 `sm._is_valid_envelope`、`_test_serializer_swap` 调 `sm.set_serializer` 均为不存在方法,报 `Nonexistent function` 运行时错误(测试中断,不打印 ALL PASS)。

- [ ] **Step 3: 改 save_manager.gd 集成序列化器**

3a. 在 `const SCHEMA_VERSION := 1` 下方新增序列化器字段与 setter:

```gdscript
const SAVE_DIR := "user://saves"
const SCHEMA_VERSION := 1

## 当前序列化策略(默认 JSON,逐字节兼容旧 .json 存档)。经 set_serializer 替换。
var _serializer: SaveSerializer = JsonSaveSerializer.new()


## 替换序列化策略。null 忽略并 push_error;换后影响后续 save/load(不改动已落盘文件)。
func set_serializer(s: SaveSerializer) -> void:
	if s == null:
		push_error("SaveManager.set_serializer: 拒绝 null")
		return
	_serializer = s
```

3b. 用字节路径替换 `save()`(本 Task 仍直写目标,原子写留给 T3):

```gdscript
func save(slot: String, data: Dictionary) -> bool:
	var safe_slot := _sanitize_slot_name(slot)
	if safe_slot.is_empty():
		save_failed.emit(slot, "invalid_slot_name")
		return false

	var envelope := {"_version": SCHEMA_VERSION, "data": data}
	var bytes := _serializer.encode(envelope)
	if bytes.is_empty():
		save_failed.emit(slot, "encode_error")
		return false

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var file := FileAccess.open(_slot_path(safe_slot), FileAccess.WRITE)
	if file == null:
		save_failed.emit(slot, "open_error:%d" % FileAccess.get_open_error())
		return false

	file.store_buffer(bytes)
	file.close()

	saved.emit(safe_slot)
	return true
```

3c. 用字节路径替换 `load()`(docstring 里对 `_decode` 的引用一并改为 serializer/信封校验):

```gdscript
## 把 slot 读回一个 Dictionary。任何错误(文件不存在、字节损坏/信封非法)都返回 {}
## 并 emit load_failed;存档位本身合法地存了 {} 时同样返回 {},但 emit 的是 loaded。
func load(slot: String) -> Dictionary:
	var safe_slot := _sanitize_slot_name(slot)
	if safe_slot.is_empty():
		load_failed.emit(slot, "invalid_slot_name")
		return {}

	var path := _slot_path(safe_slot)
	if not FileAccess.file_exists(path):
		load_failed.emit(safe_slot, "not_found")
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		load_failed.emit(safe_slot, "open_error:%d" % FileAccess.get_open_error())
		return {}
	var bytes := file.get_buffer(file.get_length())
	file.close()

	var envelope := _serializer.decode(bytes)
	if envelope.is_empty() or not _is_valid_envelope(envelope):
		load_failed.emit(safe_slot, "corrupt")
		return {}

	if int(envelope["_version"]) != SCHEMA_VERSION:
		CoreKit.log.warn("SaveManager: slot '%s' 版本 %s 与当前 SCHEMA_VERSION %d 不一致,v1 无迁移逻辑,按原样加载" % [safe_slot, str(envelope["_version"]), SCHEMA_VERSION])

	loaded.emit(safe_slot)
	return envelope["data"]
```

3d. `_slot_path` 扩展名改由序列化器驱动:

```gdscript
## 纯路径拼接;不做清洗——调用方需先自行清洗。扩展名由当前序列化器决定。
func _slot_path(slot: String) -> String:
	return "%s/%s.%s" % [SAVE_DIR, slot, _serializer.extension()]
```

3e. `list_slots` 的扩展名过滤改为 `_serializer.extension()`(仅改 `while` 里那一行判断):

```gdscript
		if not dir.current_is_dir() and file_name.get_extension() == _serializer.extension():
			result.append(file_name.get_basename())
```

3f. 删除 `_encode`/`_decode` 两个函数(连同其 docstring),在原「可测接缝」区新增 `_is_valid_envelope`:

```gdscript
## 信封结构校验(承接旧 _decode 的 has/类型检查):有 _version/data 键、_version 为标量、
## data 是 Dictionary。非标量 _version 会让 load() 里的 int(...) 抛错,故当作损坏。
func _is_valid_envelope(env: Dictionary) -> bool:
	if not env.has("_version") or not env.has("data"):
		return false
	if typeof(env["_version"]) not in [TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
		return false
	return typeof(env["data"]) == TYPE_DICTIONARY
```

- [ ] **Step 4: 裁剪 _test_pure_seams 里已迁移的 _encode/_decode 项**

`_encode`/`_decode` 已删除,`_test_pure_seams` 中调用它们的断言(原第 5-11 项)必须移除——覆盖已迁至 `_test_serializer`(T1)与 `_test_envelope_seam`(T2)。把 `_test_pure_seams` 整体替换为只保留 sanitize/slot_path 四项:

```gdscript
## ============================================================
## 第一部分:纯函数测试(disk-free,不依赖 autoload)——sanitize / slot_path。
## encode/decode 的直测已迁至 _test_serializer;信封校验迁至 _test_envelope_seam。
## ============================================================
func _test_pure_seams() -> int:
	var failures := 0
	var sm = SaveManagerScript.new()  # 变量名避开内置 load() 函数关联联想

	# 1. 合法输入原样通过
	if sm._sanitize_slot_name("hero1") != "hero1":
		print("FAIL _sanitize_slot_name('hero1') 应原样返回,得到 '%s'" % sm._sanitize_slot_name("hero1"))
		failures += 1

	# 2. 路径穿越字符被清洗掉,结果只含白名单字符
	var traversal: String = sm._sanitize_slot_name("../../etc/passwd")
	var re_whitelist := RegEx.new()
	re_whitelist.compile("^[A-Za-z0-9_-]+$")
	if traversal.contains("/") or traversal.contains("\\") or traversal.contains("..") or re_whitelist.search(traversal) == null:
		print("FAIL _sanitize_slot_name 路径穿越未清洗干净,得到 '%s'" % traversal)
		failures += 1

	# 3. 空/纯空白输入被拒绝为 "",不回退默认值
	if sm._sanitize_slot_name("") != "":
		print("FAIL _sanitize_slot_name('') 应为 ''")
		failures += 1
	if sm._sanitize_slot_name("   ") != "":
		print("FAIL _sanitize_slot_name('   ') 应为 ''")
		failures += 1

	# 4. _slot_path 默认(json serializer)为纯字符串拼接,不清洗
	if sm._slot_path("hero1") != "user://saves/hero1.json":
		print("FAIL _slot_path('hero1') 得到 '%s'" % sm._slot_path("hero1"))
		failures += 1

	sm.free()
	return failures
```

- [ ] **Step 5: 运行单测确认通过(GREEN)**

运行单测。
Expected: `test_save_manager: ALL PASS`,退出码 0。特别确认 `_test_disk_roundtrip` 里"损坏文件 -> corrupt"仍绿(字节路径下 `decode` 返回 `{}` -> `is_empty` -> corrupt)。

- [ ] **Step 6: 提交**

```
git add addons/godot-core-kit/systems/save_manager.gd test/bin_test_serializer.gd test/test_save_manager.gd
```
提交信息:
```
feat(save): integrate SaveSerializer into SaveManager (byte I/O, ext-driven path)

_serializer(默认 JsonSaveSerializer)+ set_serializer;save/load 改走字节
(store_buffer/get_buffer);_slot_path 与 list_slots 扩展名由序列化器驱动;
新增 _is_valid_envelope 信封接缝;删除已迁移的 _encode/_decode。新增
encode_error reason。公开 API 与默认 .json 行为不变。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```

---

## Task 3: 原子写(temp + rename)

**Files:**
- Modify: `addons/godot-core-kit/systems/save_manager.gd`(`save()` 落盘段改 temp+rename;新增 `_atomic_replace`)
- Modify: `test/test_save_manager.gd`(新增 `_test_atomic_write()`)

**Interfaces:**
- Consumes(来自 T2):`save()` 字节路径、`_slot_path`。
- Produces:
  - `SaveManager._atomic_replace(tmp: String, target: String) -> bool`(rename 优先;个别平台不覆盖时"先删目标再 rename"回退)。
  - `save()` 落盘改为写 `<target>.tmp` -> `_atomic_replace(tmp, target)`;失败清理 tmp + `save_failed(slot, "rename_error")`。

- [ ] **Step 1: 写失败测试 _test_atomic_write()**

在 `_initialize()` failures 链接入(放在 `_test_serializer_swap()` 之后):

```gdscript
	failures += _test_serializer_swap()
	failures += _test_atomic_write()
	failures += _test_disk_roundtrip()
```

文件末尾新增:

```gdscript
## ============================================================
## T3: 原子写——成功不留 tmp;_atomic_replace 成功/覆盖两路径;rename 失败清理 + rename_error。
## rename 失败用"目标名被非空目录占位"确定性构造(已实测:rename 到目录失败,
## FileAccess.file_exists(目录)=false -> 回退分支不触发 -> _atomic_replace 返回 false)。
## ============================================================
func _test_atomic_write() -> int:
	var failures := 0
	var sm = SaveManagerScript.new()
	var slot := "__test_atomic__"
	var target: String = sm._slot_path(slot)
	var tmp := target + ".tmp"

	# 起点干净
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)

	# 成功路径:save 后 tmp 不残留、目标存在且可完整 load、list_slots 含本槽
	if not sm.save(slot, {"n": 1}):
		print("FAIL 原子写 save 应为 true")
		failures += 1
	if FileAccess.file_exists(tmp):
		print("FAIL save 成功后不应残留 tmp 文件")
		failures += 1
	if not FileAccess.file_exists(target):
		print("FAIL save 成功后目标文件应存在")
		failures += 1
	if not _values_equal(sm.load(slot), {"n": 1}):
		print("FAIL 原子写后 load 应完整")
		failures += 1
	if not sm.list_slots().has(slot):
		print("FAIL 原子写后 list_slots 应含 '%s'" % slot)
		failures += 1
	DirAccess.remove_absolute(target)

	# _atomic_replace 直测——目标不存在 -> true、tmp 消失、目标为源内容
	var a_src: String = SaveManagerScript.SAVE_DIR + "/__ar_src__.tmp"
	var a_dst: String = SaveManagerScript.SAVE_DIR + "/__ar_dst__.dat"
	DirAccess.make_dir_recursive_absolute(SaveManagerScript.SAVE_DIR)
	var wf := FileAccess.open(a_src, FileAccess.WRITE)
	wf.store_string("NEW")
	wf.close()
	if not sm._atomic_replace(a_src, a_dst):
		print("FAIL _atomic_replace 目标不存在应为 true")
		failures += 1
	if FileAccess.file_exists(a_src) or not FileAccess.file_exists(a_dst):
		print("FAIL _atomic_replace 后 tmp 应消失、目标应存在")
		failures += 1

	# _atomic_replace 覆盖——目标已存在(旧)-> true 且内容为新
	var wf2 := FileAccess.open(a_src, FileAccess.WRITE)
	wf2.store_string("NEWER")
	wf2.close()
	if not sm._atomic_replace(a_src, a_dst):
		print("FAIL _atomic_replace 覆盖应为 true")
		failures += 1
	var rf := FileAccess.open(a_dst, FileAccess.READ)
	var got := rf.get_as_text()
	rf.close()
	if got != "NEWER":
		print("FAIL _atomic_replace 覆盖后内容应为 'NEWER',得到 '%s'" % got)
		failures += 1
	DirAccess.remove_absolute(a_dst)

	# rename 失败:目标名被非空目录占位 -> save_failed('rename_error')、false、tmp 清理
	var slot2 := "__test_rename_fail__"
	var target2: String = sm._slot_path(slot2)   # user://saves/<slot2>.json
	var tmp2 := target2 + ".tmp"
	DirAccess.make_dir_recursive_absolute(target2)          # 用目标名建目录
	var inner := FileAccess.open(target2 + "/inner.txt", FileAccess.WRITE)
	inner.store_string("x")                                  # 让目录非空
	inner.close()
	var captured := {"reason": ""}
	var on_fail := func(_s: String, reason: String) -> void: captured["reason"] = reason
	sm.save_failed.connect(on_fail)
	var ok2: bool = sm.save(slot2, {"n": 2})
	sm.save_failed.disconnect(on_fail)
	if ok2:
		print("FAIL 目标被目录占位时 save 应返回 false")
		failures += 1
	if captured["reason"] != "rename_error":
		print("FAIL save_failed reason 应为 'rename_error',得到 '%s'" % captured["reason"])
		failures += 1
	if FileAccess.file_exists(tmp2):
		print("FAIL rename 失败后应清理 tmp")
		failures += 1
	# 清理占位目录
	if FileAccess.file_exists(target2 + "/inner.txt"):
		DirAccess.remove_absolute(target2 + "/inner.txt")
	DirAccess.remove_absolute(target2)
	sm.free()
	return failures
```

- [ ] **Step 2: 运行单测确认失败(RED)**

运行单测。
Expected: RED——`sm._atomic_replace(...)` 不存在(`Nonexistent function`);且此时 `save()` 直写目标,rename 失败场景下 `FileAccess.open(target2, WRITE)`(target2 是目录)返回 null -> emit `open_error:...` 而非 `rename_error` -> reason 断言失败。

- [ ] **Step 3: 在 save_manager.gd 实现原子写**

3a. 把 `save()` 落盘段(`DirAccess.make_dir_recursive_absolute(SAVE_DIR)` 到 `saved.emit`)替换为 temp+rename:

```gdscript
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var target := _slot_path(safe_slot)
	var tmp := target + ".tmp"

	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		save_failed.emit(slot, "open_error:%d" % FileAccess.get_open_error())
		return false
	file.store_buffer(bytes)
	file.close()

	if not _atomic_replace(tmp, target):
		DirAccess.remove_absolute(tmp)
		save_failed.emit(slot, "rename_error")
		return false

	saved.emit(safe_slot)
	return true
```

3b. 在可测接缝区新增 `_atomic_replace`:

```gdscript
## 原子替换:优先 rename(桌面平台原子覆盖已存在目标);个别平台 rename 不覆盖时,
## 回退"先删目标再 rename"。整个过程 tmp 始终是完整文件,消除目标被写一半的窗口。
func _atomic_replace(tmp: String, target: String) -> bool:
	if DirAccess.rename_absolute(tmp, target) == OK:
		return true
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
		return DirAccess.rename_absolute(tmp, target) == OK
	return false
```

- [ ] **Step 4: 运行单测确认通过(GREEN)**

运行单测。
Expected: `test_save_manager: ALL PASS`,退出码 0。

- [ ] **Step 5: 提交**

```
git add addons/godot-core-kit/systems/save_manager.gd test/test_save_manager.gd
```
提交信息:
```
feat(save): atomic write via temp + rename (_atomic_replace)

save() 先写 <slot>.<ext>.tmp,close 后 rename 到目标,消除目标被写一半的
窗口;rename(含"先删再 rename"回退)失败 -> 清理 tmp + save_failed
rename_error。tmp 扩展名 .tmp,不被 list_slots 计入。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```

---

## Task 4: 资源引用安全守卫

**Files:**
- Modify: `addons/godot-core-kit/systems/save_manager.gd`(`save()` 头部插入守卫;新增 `_has_unserializable`)
- Modify: `test/test_save_manager.gd`(新增 `_test_resource_guard()`)

**Interfaces:**
- Consumes(来自 T2/T3):`save()` 字节+原子路径。
- Produces:
  - `SaveManager._has_unserializable(v: Variant) -> bool`(递归:`typeof` in {OBJECT,CALLABLE,SIGNAL,RID} -> true;DICTIONARY/ARRAY 递归;其余 false)。
  - `save()` 在建信封前调守卫,命中 -> `save_failed(slot, "unserializable")`、返回 false、不落盘。

- [ ] **Step 1: 写失败测试 _test_resource_guard()**

在 `_initialize()` failures 链接入(放在 `_test_atomic_write()` 之后):

```gdscript
	failures += _test_atomic_write()
	failures += _test_resource_guard()
	failures += _test_disk_roundtrip()
```

文件末尾新增:

```gdscript
## ============================================================
## T4: 资源引用安全守卫 _has_unserializable + save 拒 Object/Callable/嵌套。
## Resource.new() 为 TYPE_OBJECT;func():pass 为 TYPE_CALLABLE。
## ============================================================
func _test_resource_guard() -> int:
	var failures := 0
	var sm = SaveManagerScript.new()

	# 纯函数:纯数据 false;含 Object/Callable/嵌套 true
	if sm._has_unserializable({"a": 1, "b": ["x", 2, {"c": true}]}):
		print("FAIL _has_unserializable 纯数据应为 false")
		failures += 1
	if not sm._has_unserializable({"res": Resource.new()}):
		print("FAIL _has_unserializable 含 Resource 应为 true")
		failures += 1
	if not sm._has_unserializable({"bag": [Resource.new()]}):
		print("FAIL _has_unserializable 嵌套 Array 中 Resource 应为 true")
		failures += 1
	if not sm._has_unserializable({"cb": func() -> void: pass}):
		print("FAIL _has_unserializable 含 Callable 应为 true")
		failures += 1

	# save 拒:命中守卫 -> false、save_failed('unserializable')、不落盘
	var slot := "__test_guard__"
	var path: String = sm._slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var captured := {"reason": ""}
	var on_fail := func(_s: String, reason: String) -> void: captured["reason"] = reason
	sm.save_failed.connect(on_fail)
	var ok: bool = sm.save(slot, {"res": Resource.new()})
	sm.save_failed.disconnect(on_fail)
	if ok:
		print("FAIL 含 Resource 的 save 应返回 false")
		failures += 1
	if captured["reason"] != "unserializable":
		print("FAIL save_failed reason 应为 'unserializable',得到 '%s'" % captured["reason"])
		failures += 1
	if FileAccess.file_exists(path):
		print("FAIL 守卫命中时不应落盘")
		failures += 1

	sm.free()
	return failures
```

- [ ] **Step 2: 运行单测确认失败(RED)**

运行单测。
Expected: RED——`sm._has_unserializable(...)` 不存在(`Nonexistent function`);且此时 `save()` 无守卫,`JSON.stringify({...Resource...})` 把 Resource 静默转 null -> save 成功返回 true -> `ok` 断言失败。

- [ ] **Step 3: 在 save_manager.gd 实现守卫**

3a. 在 `save()` 的 `invalid_slot_name` 检查之后、建信封之前插入守卫块:

```gdscript
	var safe_slot := _sanitize_slot_name(slot)
	if safe_slot.is_empty():
		save_failed.emit(slot, "invalid_slot_name")
		return false

	if _has_unserializable(data):
		save_failed.emit(slot, "unserializable")
		return false

	var envelope := {"_version": SCHEMA_VERSION, "data": data}
```

3b. 在可测接缝区新增 `_has_unserializable`:

```gdscript
## data 中是否存在不可持久化的值(递归 Dictionary 值 + Array 元素)。挡"永不该落盘"的
## 句柄/对象类型(Object/Resource/Node/Callable/Signal/RID);不拒 Vector2/Color 等值类型
## (那是 JSON 格式局限而非注入面,二进制 serializer 可原生存)。
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

- [ ] **Step 4: 运行单测确认通过(GREEN)**

运行单测。
Expected: `test_save_manager: ALL PASS`,退出码 0。

- [ ] **Step 5: 提交**

```
git add addons/godot-core-kit/systems/save_manager.gd test/test_save_manager.gd
```
提交信息:
```
feat(save): resource-reference safety guard (reject Object/Callable/Signal/RID)

save() 落盘前递归扫描 data,含 Object/Resource/Node/Callable/Signal/RID 即
拒写 + save_failed unserializable + 不落盘,固化"存 resource_path 引用而非
整个 Resource"边界(避 ResourceLoader 注入面)。纯数据 dict 行为不变。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```

---

## Task 5: 版本 0.7.0 + 文档 + demo 冒烟

**Files:**
- Modify: `addons/godot-core-kit/core_kit.gd`(VERSION 行)
- Modify: `addons/godot-core-kit/plugin.cfg`(version + description)
- Modify: `addons/godot-core-kit/docs/systems/save-manager.md`
- Modify: `addons/godot-core-kit/docs/architecture.md`(「## 版本」段)
- Modify: `README.md`(changelog)
- Modify: `demo/demo.gd`(SaveManager 冒烟段)

**Interfaces:**
- Consumes(来自 T1-T4):`set_serializer`、`SaveSerializer`、原子写、资源守卫的最终形态。
- Produces:无新代码接口,仅版本号 + 文档 + demo 冒烟。

- [ ] **Step 1: 升版本号**

`addons/godot-core-kit/core_kit.gd`——`const VERSION := "0.6.0"` 改为:

```gdscript
const VERSION := "0.7.0"
```

`addons/godot-core-kit/plugin.cfg`:`version="0.6.0"` 改为 `version="0.7.0"`;`description` 末尾(闭引号前)追加:`;0.7.0 SaveManager 增可插拔序列化 SaveSerializer + 原子写(temp+rename)+ 资源引用守卫`。

`addons/godot-core-kit/systems/save_manager.gd` **头部类级文档注释同步**(T3 review Minor):(1) 把"落盘到 user://saves/<slot>.json,JSON 格式、{_version, data} 信封包裹"更新为反映现状——经**可插拔 `SaveSerializer`(默认 `JsonSaveSerializer`,`.json`)**序列化、**原子写(temp+rename)**落盘、`{_version, data}` 信封;(2) 删掉 YAGNI 块里的"无原子写(temp+rename)"这一项(已实现);(3) 可补一句资源守卫约定(存 `resource_path` 引用而非整个 Resource)。仅改注释,不动任何代码。

- [ ] **Step 2: 更新 save-manager.md**

2a. 第 9 行(YAGNI 那句)整行替换——去掉"无原子写":

old:
```
v1 范围之外(YAGNI):无自动收集存档的 registry、无加密、无迁移引擎(仅保留版本号字段)、无自动存档调度、无存档位元数据(缩略图/时长)、无原子写(temp+rename)。
```
new:
```
范围之外(YAGNI):无自动收集存档的 registry、无加密/校验和(可由自定义 serializer 承载)、无迁移引擎(仅保留版本号字段)、无自动存档调度、无存档位元数据(缩略图/时长)。
```

2b. 在 API 代码块内 `func list_slots() -> Array[String]` 之后追加 `set_serializer`:

old:
```gdscript
# 列出所有存档位名称(不含扩展名),升序排列,仅名称、无元数据;目录不存在时返回 []。
func list_slots() -> Array[String]
```
new:
```gdscript
# 列出所有存档位名称(不含扩展名),升序排列,仅名称、无元数据;目录不存在时返回 []。
func list_slots() -> Array[String]

# 替换序列化策略(默认 JsonSaveSerializer)。null 忽略并 push_error;换后影响后续 save/load。
func set_serializer(s: SaveSerializer) -> void
```

2c. 在「## 用法示例」代码块结束之后、「## 注意事项」之前,插入三节(注意示例代码块的三反引号需闭合):

```markdown
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
```

2d. 第 58 行(注意事项最后一条,"无原子写…")整行替换:

old:
```
- 无原子写:写入过程中断电/崩溃可能导致该 slot 文件损坏;`_decode` 对损坏内容一律返回 `{}` 触发 `load_failed`,不删除原文件。
```
new:
```
- 原子写:`save()` 走 temp+rename,写入中断只留不完整的 `.tmp`(不被 `list_slots` 计入),目标不出现写一半态。损坏内容(序列化器 `decode` 返回 `{}` 或信封校验不过)一律触发 `load_failed(slot, "corrupt")`,不删除原文件。
```

- [ ] **Step 3: 更新 architecture.md 版本段**

「## 版本」段落正文整段替换:

old:
```
当前 `0.6.0`(`plugin.cfg` 与 `CoreKit.VERSION` 同源)。0.5.0→0.6.0 给 KitContext 叠加订阅式解析(`subscribe`)与工厂式 scope(`provide_factory`,SINGLETON/TRANSIENT),纯增量、向后兼容;0.4.1→0.5.0 新增 KitContext 服务容器(纯增量,对既有 API 无破坏);0.3.x→0.4.0 是破坏性变更(五个老全局单例名下线,统一走 `CoreKit` 门面);0.4.1 为纯目录重排。
```
new:
```
当前 `0.7.0`(`plugin.cfg` 与 `CoreKit.VERSION` 同源)。0.6.0→0.7.0 给 SaveManager 叠加可插拔序列化(`SaveSerializer` 基类 + 默认 `JsonSaveSerializer`,逐字节兼容旧 `.json`)、原子写(temp+rename)、资源引用安全守卫(拒 Object/Callable/Signal/RID),纯增量、向后兼容;0.5.0→0.6.0 给 KitContext 叠加订阅式解析(`subscribe`)与工厂式 scope(`provide_factory`,SINGLETON/TRANSIENT),纯增量、向后兼容;0.4.1→0.5.0 新增 KitContext 服务容器(纯增量,对既有 API 无破坏);0.3.x→0.4.0 是破坏性变更(五个老全局单例名下线,统一走 `CoreKit` 门面);0.4.1 为纯目录重排。
```

- [ ] **Step 4: 更新 README.md changelog**

在 `- **0.6.0** …` 那一行之前插入一行:

```
- **0.7.0** — `SaveManager` 叠加可插拔序列化(`SaveSerializer` 基类 + 默认 `JsonSaveSerializer`,逐字节兼容旧 `.json`)、原子写(temp+rename)、资源引用安全守卫(拒 Object/Callable/Signal/RID);纯增量,API 无破坏。
```

- [ ] **Step 5: demo 资源守卫冒烟**

`demo/demo.gd` 在 SaveManager 冒烟段(`CoreKit.saves.delete_slot("__demo_smoke__")`)之后追加(用 `log.info`,不经 `log.error`,以免污染 demo stderr 断言):

```gdscript
	CoreKit.saves.delete_slot("__demo_smoke__")

	# SaveManager 资源守卫冒烟:含 Object 的 save 被拒(返回 false,不落盘)
	var guard_ok := CoreKit.saves.save("__demo_guard__", {"bad": Resource.new()})
	CoreKit.log.info("SaveManager 资源守卫拒 Object save=%s (应为 false)" % guard_ok)
```

- [ ] **Step 6: 全量验证**

在 PowerShell 工具跑 `& .\test\run_all.ps1`。
Expected:`import exit=0`;13 个测试每行 `OK`(尤其 `test_save_manager exit=0 pass=True OK`);demo 各 marker `present`、`demo stderr has ERROR: no`;末行 `=== SUMMARY FAILS=0 ===`。

- [ ] **Step 7: 提交**

```
git add addons/godot-core-kit/core_kit.gd addons/godot-core-kit/plugin.cfg addons/godot-core-kit/docs/systems/save-manager.md addons/godot-core-kit/docs/architecture.md README.md demo/demo.gd
```
提交信息:
```
docs(save): bump 0.7.0; document serializer/atomic/guard; demo guard smoke

VERSION 与 plugin.cfg 0.6.0->0.7.0;save-manager.md 增可插拔序列化/原子写/
资源引用安全三节 + set_serializer API;architecture.md 与 README changelog
补 0.7.0;demo 追加资源守卫拒 Object 冒烟。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```

---

## 自审对照(spec 覆盖 / 占位符 / 类型一致)

**Spec 覆盖:**

| spec 节 | 对应 Task |
|---|---|
| §3.1 SaveSerializer 基类 | T1 Step 1 |
| §3.2 JsonSaveSerializer | T1 Step 2 |
| §3.3 SaveManager 集成 | T2 Step 3 |
| §4.1 原子写 save() | T3 Step 3a |
| §4.2 _atomic_replace(含平台核实) | T3 Step 3b(rename 覆盖行为已实测确认) |
| §5.1 _has_unserializable 守卫 | T4 Step 3 |
| §5.2 文档固化 | T5 Step 2c |
| §6 数据流 + _is_valid_envelope 接缝 | T2 Step 3c/3f |
| §7 新增 reason | T2(encode_error)/T3(rename_error)/T4(unserializable) |
| §10 测试(8 项) | T1-T4 各测试段 + demo(T5 Step 5) |
| §11 版本 + 文档 | T5 |
| §12 YAGNI | 全程不触及 |

**平台核实项(spec §4.2 / §9)**:已用探针实测 Godot 4.7-stable-mono win64——`DirAccess.rename_absolute` 原子覆盖已存在目标(源消失、目标为新、返回 OK);"目标被非空目录占位"确定性触发 rename 失败(返回非 OK、`FileAccess.file_exists(目录)`=false -> 回退分支不触发 -> `_atomic_replace` 返回 false、tmp 保留)。T3 成功/覆盖/失败三路径据此写死。

**占位符扫描**:无 TBD/TODO;每个代码步骤含完整可跑代码;每个测试步骤含完整断言;命令均给 expected 输出。

**类型一致**:`SaveSerializer.encode -> PackedByteArray` / `decode -> Dictionary` / `extension -> String` 三处签名 T1 定义、T2 消费一致;`set_serializer(s: SaveSerializer)`、`_is_valid_envelope(env: Dictionary) -> bool`、`_atomic_replace(tmp, target) -> bool`、`_has_unserializable(v) -> bool` 定义(T2/T3/T4)与测试调用签名一致;save_failed reason 字面量(`unserializable`/`encode_error`/`rename_error`)实现与测试断言逐字一致。
</parameter>
</invoke>
