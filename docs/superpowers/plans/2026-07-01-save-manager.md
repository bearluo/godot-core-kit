# SaveManager 子系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 godot-core-kit 实现 `SaveManager` 存档子系统(全局 autoload 脚本),把任意 Dictionary 状态以具名"存档位"落盘到 `user://saves/`,JSON 格式、`{_version, data}` 信封包裹。

**范围边界(务必遵守):** 本计划**只**产出两个文件——`addons/godot-core-kit/save_manager.gd` 与 `test/test_save_manager.gd`。autoload 注册(`project.godot`/`plugin.gd` 接线)、版本号升级(`plugin.cfg` 的 `version`、`core_kit.gd` 的 `VERSION`)、README、demo 更新均**不属于**本计划,是后续独立的集成计划(参照 Logger 的 Task 2 模式,单独立项)。本计划完成后 `SaveManager` 脚本存在且自测通过,但**尚未接入工程**,`SaveManager.xxx` 在 demo/其它脚本里还不可用——这是预期状态,不是遗漏。

**Architecture:** 单文件(`save_manager.gd`,`extends Node`)。公开 API(`save`/`load`/`has_slot`/`delete_slot`/`list_slots`)+ 五个信号(`saved`/`save_failed`/`loaded`/`load_failed`/`slot_deleted`)+ 四个纯函数可测接缝(`_sanitize_slot_name`/`_slot_path`/`_encode`/`_decode`,不碰磁盘、不依赖 autoload)。`save`/`load`/`has_slot`/`delete_slot` 内部复用这四个接缝;`list_slots` 直接扫描 `SAVE_DIR`。仅在 `_version` 不匹配时依赖 `Log.warn`,除此之外零依赖(不依赖 EventBus/SceneManager/ObjectPool)。

**Tech Stack:** Godot 4.7,纯 GDScript,Compatibility 渲染器。无第三方测试框架,headless 断言脚本直接实例化脚本(不依赖 autoload),与 `test/test_log.gd` 同构。

## Global Constraints

以下为全计划约束,每个任务隐含遵守:

- 引擎 Godot 4.7,`config_version=5`;纯 GDScript,**不含 C#**。
- **Web 导出兼容**:`FileAccess`/`DirAccess`/`JSON` 在 GDScript 里全平台同步,不需要 `await`/异步变体。`user://` 在 HTML5 导出由 IndexedDB 支持的虚拟文件系统承载,API 与桌面一致。**Durability 警告**:HTML5 导出向 IndexedDB 的同步是异步的,`save()` 调用与下一次引擎驱动同步之间崩溃/强制关闭标签页可能丢失该次写入——本计划不实现原子写(temp+rename)加固,这是已确认的 v1 决定,不是遗漏;游戏侧应在检查点调用 `save()`。
- 存档格式:JSON,`JSON.stringify(envelope, "\t")` 美化输出;信封 `{"_version": SCHEMA_VERSION, "data": <caller dict>}`。`SAVE_DIR := "user://saves"`,`SCHEMA_VERSION := 1`。
- 存档位路径:`user://saves/<清洗后的 slot>.json`。清洗规则:正则 `[^A-Za-z0-9_-]+` 命中的字符**删除**(不是替换);清洗后为空(原始输入为空/纯空白/全部字符非法)一律拒绝,返回 `""`,调用方看到 `*_failed(slot, "invalid_slot_name")`(信号带*原始*未清洗字符串)。
- 失败 reason 字符串(逐字,供测试断言,不要改写):`"invalid_slot_name"`、`"not_found"`、`"open_error:<code>"`(`<code>` 为 `FileAccess.get_open_error()` 的整数值,如 `"open_error:7"`)、`"corrupt"`。`delete_slot` 无专属失败信号,只用返回值表达失败。
- 版本不匹配处理:`load()` 解出 envelope 后若 `envelope["_version"] != SCHEMA_VERSION`,调用 `Log.warn(...)` 并**照常继续**返回数据——v1 **没有**迁移引擎,这是唯一允许的外部依赖(`Log`)。
- **命名坑(需实机验证)**:`func load(...)` 在脚本自身作用域内遮蔽 GDScript 内置全局函数 `load(path) -> Resource`,与 `Log` 遮蔽全局 `log()` 同一类问题。`SaveManager` 内部从不调用全局 `load()`,外部 `SaveManager.load("slot")` 调用不受影响。本计划的 headless 测试运行(Task 1 Step 4)本身就是这条的实机验证——若这会导致解析错误而非仅仅是警告,测试运行会直接失败,须据此调整。
- Autoload 名 `SaveManager`(`extends Node`),文件路径 `addons/godot-core-kit/save_manager.gd`——但**本计划不做 autoload 注册**,只是约定文件放在这个路径以配合后续集成计划。
- 独立性:只用自己的信号;不依赖 EventBus/SceneManager/ObjectPool。可以依赖 `Log`(仅用于版本不匹配警告)。
- 本机 Godot(验证用),下文命令记作 `$godot`:
  `D:\Program Files\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe`
  PowerShell 里先设 `$godot = "D:\Program Files\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe"`,再 `& $godot ...`。

## File Structure

| 文件 | 责任 | 动作 |
|---|---|---|
| `addons/godot-core-kit/save_manager.gd` | `SaveManager` 脚本:`save`/`load`/`has_slot`/`delete_slot`/`list_slots` + 五个信号 + 四个纯函数接缝 | Create |
| `test/test_save_manager.gd` | headless 断言:11 条纯函数断言(disk-free)+ 可选磁盘往返区块(自清理) | Create |

本计划**没有** Modify 项——不改 `project.godot`、`plugin.gd`、`plugin.cfg`、`core_kit.gd`、`demo/demo.gd`、`README.md`。这些属于后续独立的集成计划,不在本计划范围内。

---

## Task 1: SaveManager 核心 —— save/load/has_slot/delete_slot/list_slots + 纯函数接缝

**Files:**
- Create: `addons/godot-core-kit/save_manager.gd`
- Test: `test/test_save_manager.gd`

**Interfaces:**
- Consumes: `Log`(仅 `Log.warn(message)`,用于 `_version` 不匹配警告;`Log` 已存在于 `addons/godot-core-kit/log.gd`,直接按全局 autoload 标识符引用即可,不需要额外 `preload`)。
- Produces:
  - `SaveManager` 脚本(`extends Node`),供未来 autoload 注册与本计划内直接实例化测试使用。
  - `signal saved(slot: String)` / `signal save_failed(slot: String, reason: String)` / `signal loaded(slot: String)` / `signal load_failed(slot: String, reason: String)` / `signal slot_deleted(slot: String)`
  - `const SAVE_DIR := "user://saves"` / `const SCHEMA_VERSION := 1`
  - `func save(slot: String, data: Dictionary) -> bool`
  - `func load(slot: String) -> Dictionary`
  - `func has_slot(slot: String) -> bool`
  - `func delete_slot(slot: String) -> bool`
  - `func list_slots() -> Array[String]`
  - `func _sanitize_slot_name(slot: String) -> String`(可测)
  - `func _slot_path(slot: String) -> String`(可测)
  - `func _encode(data: Dictionary) -> String`(可测)
  - `func _decode(text: String) -> Dictionary`(可测)

- [ ] **Step 1: 写失败测试** `test/test_save_manager.gd`

```gdscript
extends SceneTree
## SaveManager headless 断言测试。
##
## 第一部分(必需、disk-free):sanitize/path/encode/decode 纯函数 ——
## 直接实例化脚本,不依赖 autoload、不碰磁盘。
## 第二部分(可选、清晰分区):save/load/has_slot/delete_slot/list_slots
## 的真实磁盘往返,使用一次性 slot 名,结束前清理,不污染上面的纯函数测试。
##
## 运行:godot --headless -s res://test/test_save_manager.gd

const SaveManagerScript := preload("res://addons/godot-core-kit/save_manager.gd")


func _initialize() -> void:
	var failures := 0
	failures += _test_pure_seams()
	failures += _test_disk_roundtrip()

	if failures == 0:
		print("test_save_manager: ALL PASS")
		quit(0)
	else:
		print("test_save_manager: %d FAILURE(S)" % failures)
		quit(1)


## ============================================================
## 第一部分:纯函数测试(disk-free,不依赖 autoload)
## ============================================================
func _test_pure_seams() -> int:
	var failures := 0
	var sm = SaveManagerScript.new()  # 变量名避开内置 load() 函数关联联想

	# 1. 合法输入原样通过
	if sm._sanitize_slot_name("hero1") != "hero1":
		print("FAIL _sanitize_slot_name('hero1') 应原样返回,得到 '%s'" % sm._sanitize_slot_name("hero1"))
		failures += 1

	# 2. 路径穿越字符被清洗掉,结果只含白名单字符
	var traversal := sm._sanitize_slot_name("../../etc/passwd")
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

	# 4. _slot_path 是纯字符串拼接,不清洗
	if sm._slot_path("hero1") != "user://saves/hero1.json":
		print("FAIL _slot_path('hero1') 得到 '%s'" % sm._slot_path("hero1"))
		failures += 1

	# 5. 往返:嵌套 dict/array/int/float/string/bool
	var sample := {
		"level": 3,
		"hp": 87.5,
		"name": "hero",
		"alive": true,
		"inventory": ["sword", "shield", 42],
		"stats": {"str": 10, "dex": 7},
	}
	var round_tripped: Dictionary = sm._decode(sm._encode(sample))
	if round_tripped.get("data") != sample:
		print("FAIL 往返不一致,得到 %s" % [round_tripped.get("data")])
		failures += 1

	# 6. 编码空 dict 后解码,信封非空({} 语义与损坏 sentinel 不冲突)
	var empty_envelope: Dictionary = sm._decode(sm._encode({}))
	if empty_envelope.is_empty():
		print("FAIL _decode(_encode({})) 不应为空信封")
		failures += 1
	if not empty_envelope.has("_version") or not empty_envelope.has("data"):
		print("FAIL _decode(_encode({})) 信封应含 _version 与 data 键")
		failures += 1
	if empty_envelope.get("data") != {}:
		print("FAIL _decode(_encode({})).data 应为 {}")
		failures += 1

	# 7. 非法 JSON 不崩溃,返回 {}
	if sm._decode("not valid json {{{") != {}:
		print("FAIL _decode 对非法 JSON 应返回 {}")
		failures += 1

	# 8. 合法 JSON 但根不是 Dictionary
	if sm._decode("42") != {}:
		print("FAIL _decode('42') 应返回 {}")
		failures += 1

	# 9. 合法 JSON object 但缺少信封键
	if sm._decode("{}") != {}:
		print("FAIL _decode('{}') 应返回 {}(缺少 _version/data)")
		failures += 1

	# 10. data 字段类型不对
	if sm._decode('{"_version":1,"data":"not a dict"}') != {}:
		print("FAIL _decode 对非 Dictionary 的 data 字段应返回 {}")
		failures += 1

	# 11. _encode 输出本身是合法 JSON
	var encoded := sm._encode({"a": 1})
	var parsed = JSON.parse_string(encoded)
	if typeof(parsed) != TYPE_DICTIONARY:
		print("FAIL _encode 输出不是合法 JSON: '%s'" % encoded)
		failures += 1

	sm.free()
	return failures


## ============================================================
## 第二部分(可选、磁盘往返,清晰分区,用完清理):save/load/has_slot/
## delete_slot/list_slots 真实走 FileAccess/DirAccess I/O。
## 使用一次性 slot 名,结束前清理,不污染上面的纯函数测试,也不在真实
## 存档目录里留下垃圾文件。
## ============================================================
func _test_disk_roundtrip() -> int:
	var failures := 0
	var sm = SaveManagerScript.new()
	var slot := "__test_save_manager__"
	var path := sm._slot_path(slot)

	# 保证起点干净(万一上次异常退出留下文件)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	# save -> has_slot -> load -> list_slots
	var payload := {"score": 42, "name": "tester"}
	if not sm.save(slot, payload):
		print("FAIL save() 应返回 true")
		failures += 1
	if not sm.has_slot(slot):
		print("FAIL has_slot() 保存后应为 true")
		failures += 1
	var loaded_data := sm.load(slot)
	if loaded_data != payload:
		print("FAIL load() 应返回保存时写入的数据,得到 %s" % [loaded_data])
		failures += 1
	if not sm.list_slots().has(slot):
		print("FAIL list_slots() 应包含 '%s'" % slot)
		failures += 1

	# delete_slot -> 清理后应消失
	if not sm.delete_slot(slot):
		print("FAIL delete_slot() 应返回 true")
		failures += 1
	if sm.has_slot(slot):
		print("FAIL delete_slot() 后 has_slot() 应为 false")
		failures += 1

	# 损坏文件 -> load_failed(reason="corrupt")
	var captured := {"reason": ""}  # 用 Dictionary 当可变"盒子",绕开 lambda 捕获局部量的坑
	var on_load_failed := func(_slot: String, reason: String) -> void:
		captured["reason"] = reason
	sm.load_failed.connect(on_load_failed)
	DirAccess.make_dir_recursive_absolute(SaveManagerScript.SAVE_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not valid json {{{")
	f.close()
	var corrupt_result := sm.load(slot)
	if corrupt_result != {}:
		print("FAIL load() 对损坏文件应返回 {}")
		failures += 1
	if captured["reason"] != "corrupt":
		print("FAIL load_failed reason 应为 'corrupt',得到 '%s'" % captured["reason"])
		failures += 1

	# 清理
	DirAccess.remove_absolute(path)
	sm.free()
	return failures
```

- [ ] **Step 2: 运行,确认失败**

```powershell
$godot = "D:\Program Files\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe"
& $godot --headless --path . -s res://test/test_save_manager.gd
```
Expected: 失败。`save_manager.gd` 尚不存在,`preload` 报错 `Could not preload resource file res://addons/godot-core-kit/save_manager.gd`,脚本无法加载,退出码非 0。

- [ ] **Step 3: 写实现** `addons/godot-core-kit/save_manager.gd`

```gdscript
extends Node
## SaveManager —— godot-core-kit 全局存档单例。
##
## 以 autoload "SaveManager" 注册。把任意 Dictionary 状态以具名"存档位"(slot)
## 形式落盘到 user://saves/<slot>.json,JSON 格式、{_version, data} 信封包裹。
## 桌面与 Web 导出行为一致(user:// 在 HTML5 由 IndexedDB 支持,FileAccess/
## DirAccess/JSON 全平台同步 API,无需 await)。纯 GDScript、无第三方依赖;
## 除 Log(仅用于版本不匹配警告)外不依赖其它子系统。
##
## 用法:SaveManager.save("hero1", {"hp": 100})
##       var data := SaveManager.load("hero1")
##
## v1 范围之外(YAGNI):无自动收集存档的 registry、无加密、无迁移引擎
## (仅保留版本号字段)、无自动存档调度、无存档位元数据(缩略图/时长)、
## 无原子写(temp+rename)。
##
## 命名坑:load() 在本脚本体内会遮蔽 GDScript 内置全局函数 load(path)
## (与 Log 遮蔽全局 log() 同理);本脚本内部从不需要调用全局 load(),
## 外部通过 SaveManager.load(...) 调用不受影响。

signal saved(slot: String)
signal save_failed(slot: String, reason: String)
signal loaded(slot: String)
signal load_failed(slot: String, reason: String)
signal slot_deleted(slot: String)

const SAVE_DIR := "user://saves"
const SCHEMA_VERSION := 1


## 把 data 写入 slot,若该存档位已存在则覆盖。
## 成功返回 true;失败返回 false 并 emit save_failed(slot, reason)。
func save(slot: String, data: Dictionary) -> bool:
	var safe_slot := _sanitize_slot_name(slot)
	if safe_slot.is_empty():
		save_failed.emit(slot, "invalid_slot_name")
		return false

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var file := FileAccess.open(_slot_path(safe_slot), FileAccess.WRITE)
	if file == null:
		save_failed.emit(slot, "open_error:%d" % FileAccess.get_open_error())
		return false

	file.store_string(_encode(data))
	file.close()

	saved.emit(safe_slot)
	return true


## 把 slot 读回一个 Dictionary。任何错误(文件不存在、JSON 损坏/非法)都
## 返回 {} 并 emit load_failed;存档位本身合法地存了 {} 时同样返回 {},
## 但 emit 的是 loaded —— 见 _decode 的信封,可用于区分"空"与"损坏"。
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
	var text := file.get_as_text()
	file.close()

	var envelope := _decode(text)
	if envelope.is_empty():
		load_failed.emit(safe_slot, "corrupt")
		return {}

	if int(envelope["_version"]) != SCHEMA_VERSION:
		Log.warn("SaveManager: slot '%s' 版本 %s 与当前 SCHEMA_VERSION %d 不一致,v1 无迁移逻辑,按原样加载" % [safe_slot, str(envelope["_version"]), SCHEMA_VERSION])

	loaded.emit(safe_slot)
	return envelope["data"]


## 存档位对应的文件是否存在。
func has_slot(slot: String) -> bool:
	var safe_slot := _sanitize_slot_name(slot)
	if safe_slot.is_empty():
		return false
	return FileAccess.file_exists(_slot_path(safe_slot))


## 删除存档位对应文件。成功返回 true 并 emit slot_deleted;不存在或删除
## 失败返回 false。无专属失败信号——返回值已足够表达失败。
func delete_slot(slot: String) -> bool:
	var safe_slot := _sanitize_slot_name(slot)
	if safe_slot.is_empty():
		return false
	var path := _slot_path(safe_slot)
	if not FileAccess.file_exists(path):
		return false
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return false
	slot_deleted.emit(safe_slot)
	return true


## 列出所有存档位名称(不含扩展名),升序排列,仅名称、无元数据。
## 存档目录尚不存在时返回 []。
func list_slots() -> Array[String]:
	var result: Array[String] = []
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return result
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension() == "json":
			result.append(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


## --- 可测接缝(纯函数,不碰磁盘/autoload) ---

## 白名单方式清洗存档位名称:删除所有不在 [A-Za-z0-9_-] 内的字符;
## 若清洗后为空(原始输入为空/纯空白/全部字符都不合法),返回 ""(拒绝,
## 不回退到某个默认存档位)。
func _sanitize_slot_name(slot: String) -> String:
	var re := RegEx.new()
	re.compile("[^A-Za-z0-9_-]+")
	return re.sub(slot, "", true)


## 纯路径拼接;不做清洗——调用方需先自行清洗。
func _slot_path(slot: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, slot]


## Dictionary -> JSON 字符串,包裹为 {_version, data} 信封,缩进美化输出。
func _encode(data: Dictionary) -> String:
	var envelope := {"_version": SCHEMA_VERSION, "data": data}
	return JSON.stringify(envelope, "\t")


## JSON 字符串 -> 信封 Dictionary({_version:int, data:Dictionary});
## 任何失败(JSON 非法、根不是 Dictionary、信封键缺失、data 类型不对)
## 都返回 {}。
func _decode(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var envelope: Dictionary = parsed
	if not envelope.has("_version") or not envelope.has("data"):
		return {}
	if typeof(envelope["data"]) != TYPE_DICTIONARY:
		return {}
	return envelope
```

- [ ] **Step 4: 运行,确认通过**

```powershell
& $godot --headless --path . --import
& $godot --headless --path . -s res://test/test_save_manager.gd
```
Expected: 输出含 `test_save_manager: ALL PASS`,退出码 0。(`--import` 顺带生成 `save_manager.gd.uid`、`test_save_manager.gd.uid` 边车文件。)同时这一步就是"命名坑"那条的实机验证:若 `func load(...)` 遮蔽全局 `load()` 只触发(如果有的话)一条非致命警告,测试应正常跑通并打印 `ALL PASS`;若 Godot 4.7 实际把它当解析错误,这一步会直接暴露,需要据此调整实现(例如给方法换一个不冲突的公开名——但这会破坏已锁定的公开 API,应先确认是否真的报错,而不是预防性改名)。

- [ ] **Step 5: 提交**

```powershell
git add addons/godot-core-kit/save_manager.gd addons/godot-core-kit/save_manager.gd.uid test/test_save_manager.gd test/test_save_manager.gd.uid
git commit -m @'
feat: add SaveManager save/load core (JSON envelope, slot sanitize)

SaveManager 单例:save/load/has_slot/delete_slot/list_slots,五个信号
(saved/save_failed/loaded/load_failed/slot_deleted),四个纯函数可测
接缝(_sanitize_slot_name/_slot_path/_encode/_decode)。JSON + {_version,
data} 信封,白名单清洗存档位名防路径穿越,_decode 返回整个信封以区分
"合法空存档"与"文件损坏"。headless 断言测试直接实例化脚本、不依赖
autoload,含 11 条 disk-free 纯函数断言 + 一段清晰分区、自清理的磁盘
往返测试。尚未接线到工程(autoload 注册留给后续集成计划)。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## 完成后

本任务完成后,`save_manager.gd` 与其测试即已就绪、自测通过,但**尚未接入工程**。后续需要一个独立的集成计划(镜像 Logger 的 Task 2)来:把 `SaveManager` 注册为 autoload(声明顺序需晚于 `Log`,因为 `SaveManager.load()` 里会调用 `Log.warn`)、`plugin.cfg`/`CoreKit.VERSION` 版本号升到 `0.3.0`、README 补充用法示例、可选在 demo 里加一段存档冒烟。该集成步骤走 `/rebase-merge`(rebase 到 `main` 后 fast-forward)提 MR 合入,保持线性历史。
