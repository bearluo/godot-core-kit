# 数据表 (KitDataRegistry) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 godot-core-kit 增加 off-facade 类库 `KitDataRegistry`——按 `type` 分组存放游戏自定义 `Resource` 定义(作物/物品/配方),`register` 显式登记 + `load_dir` 扫目录批量,按 `type/id` 查。

**Architecture:** `data/kit_data_registry.gd`(`class_name KitDataRegistry extends RefCounted`,游戏 `new` 并持有,可 `CoreKit.provide("data", reg)` 挂全局)。定义 = 游戏自定义 `Resource` 子类的 `.tres`。查询方法命名为 `get_def`/`has_def`(避开 `Object.get` 冲突)。零跨系统依赖(仅引擎 `DirAccess`/`ResourceLoader`),不参与存档。

**Tech Stack:** Godot 4.7,纯 GDScript,Web 导出兼容。headless `SceneTree` 测试(运行时 `ResourceSaver` 造临时 `.tres`)。

## Global Constraints

- 版本 **0.17.0**(承 inventory v0.16.0)。三处一致:`plugin.cfg`、`core_kit.gd VERSION`、`test_core_kit.gd` 版本断言。
- **off-facade 类库**:`class_name KitDataRegistry`,置于新目录 `data/`,`extends RefCounted`。**不改** `core_kit.gd` 门面接线,仅 `VERSION` 常量随升;**不进** `test_core_kit.gd` 子系统清单(仅版本断言随升)。
- **零依赖**:仅用引擎 `DirAccess`/`ResourceLoader`;诊断走 `push_warning`。
- **命名坑**:查询用 `get_def`/`has_def`,**不叫** `get`/`has`——`Object.get(property)` 是引擎原生方法,重定义 `get` 会冲突(且 `_derive_id` 内部要用原生 `res.get(id_property)`)。
- **导出坑**:`load_dir` 遇 `xxx.tres.remap` 自动剥 `.remap` 再 load。
- `class_name` 首次运行需 `godot --headless --path . --import` 生成类缓存;demo 经 `KitDataRegistry` 引用,测试用运行时 `load()`。fixture 定义脚本 `test/fixtures/test_data_def.gd` 亦需 import 生成 `.uid`。
- 用 **Tab** 缩进。纯 GDScript,无 shader,Web 安全。
- 测试:`extends SceneTree` + `_initialize()`,顶层运行时 `load(...)`;末行 `ALL PASS` + `quit(0/1)`。`run_all.ps1` 测试文件数 21→22。

## File Structure

- **Create** `addons/godot-core-kit/data/kit_data_registry.gd` — 定义数据表类库。
- **Create** `test/fixtures/test_data_def.gd` — load_dir 测试用最小 Resource 定义(带 `id`/`max_stack`)。
- **Create** `test/test_kit_data_registry.gd` — 9 条 headless 断言。
- **Modify** `test/run_all.ps1`(tests 加 `test_kit_data_registry`;demo marker;`:1` 注释 21→22)。
- **Modify** `test/test_core_kit.gd`(仅版本断言 → 0.17.0)、`addons/godot-core-kit/core_kit.gd`(仅 `VERSION` → 0.17.0)。
- **Modify** `addons/godot-core-kit/plugin.cfg`、`demo/demo.gd`、`README.md`、`addons/godot-core-kit/docs/README.md`、`addons/godot-core-kit/docs/architecture.md`。
- **Create** `addons/godot-core-kit/docs/data/kit-data-registry.md`。

---

### Task 1: KitDataRegistry 类库 + fixture + headless 测试

**Files:**
- Create: `addons/godot-core-kit/data/kit_data_registry.gd`
- Create: `test/fixtures/test_data_def.gd`
- Create: `test/test_kit_data_registry.gd`
- Modify: `test/run_all.ps1`(tests 数组末尾加 `test_kit_data_registry`;`:1` 注释 21→22)

**Interfaces:**
- Produces:`KitDataRegistry`(`class_name`,`extends RefCounted`)。方法 `register(type:StringName, id:StringName, def:Variant)`、`load_dir(type, dir_path:String, id_property:=&"id")->int`、`get_def(type, id)->Variant`、`get_def_or(type, id, fallback:=null)->Variant`、`has_def(type, id)->bool`、`all(type)->Array`、`ids(type)->Array`、`types()->Array`、`count(type)->int`、`clear(type:=&"")`。
- fixture `test/fixtures/test_data_def.gd`(`extends Resource`)导出 `id:StringName`、`max_stack:int=99`。

- [ ] **Step 1: 写 `addons/godot-core-kit/data/kit_data_registry.gd`**

```gdscript
class_name KitDataRegistry
extends RefCounted
## KitDataRegistry —— 定义数据表(off-facade 类库,游戏 new 并持有,通常
## CoreKit.provide("data", reg) 挂全局服务)。按 type 分组:type(StringName) ->
## { id(StringName) -> def(Resource,游戏自定义子类) }。定义 = 游戏自定义 Resource
## 子类的 .tres(Inspector 可编、类型安全)。register 显式登记;load_dir 扫目录批量。
## 只读目录,不参与存档。零依赖(仅引擎 DirAccess/ResourceLoader)。
##
## 命名:查询用 get_def/has_def(避开引擎原生 Object.get 冲突)。
##
## 用法:
##   var reg := KitDataRegistry.new()
##   reg.load_dir(&"crop", "res://data/crops")      # 扫 *.tres,id 取 def.id 或文件名
##   reg.register(&"item", &"wood", wood_def)
##   var c = reg.get_def(&"crop", &"turnip")
##   CoreKit.provide("data", reg)                    # 挂全局服务(可选)

var _store: Dictionary = {}   # StringName(type) -> Dictionary( StringName(id) -> Variant(def) )


## 显式登记一条定义。已存在同 (type,id) → push_warning 覆盖。
func register(type: StringName, id: StringName, def: Variant) -> void:
	if not _store.has(type):
		_store[type] = {}
	var bucket: Dictionary = _store[type]
	if bucket.has(id):
		push_warning("KitDataRegistry: 覆盖已存在定义 [%s/%s]" % [type, id])
	bucket[id] = def


## 扫 dir_path 下 *.tres / *.res 逐个 load 并按 type 登记。id 取 def 的 id_property 属性
## (存在且非空则用),否则文件名 stem。返回成功登记数。目录打不开 → push_warning + 0。
## 导出坑:导出包里 .tres 可能呈现为 "xxx.tres.remap",自动剥 .remap 再 load。
func load_dir(type: StringName, dir_path: String, id_property: StringName = &"id") -> int:
	var da := DirAccess.open(dir_path)
	if da == null:
		push_warning("KitDataRegistry.load_dir: 无法打开目录 '%s'" % dir_path)
		return 0
	var loaded := 0
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if not da.current_is_dir():
			var fname := entry
			if fname.ends_with(".remap"):
				fname = fname.trim_suffix(".remap")     # 导出包:剥 .remap
			if fname.ends_with(".tres") or fname.ends_with(".res"):
				var res = ResourceLoader.load(dir_path.path_join(fname))
				if res != null:
					register(type, _derive_id(res, fname, id_property), res)
					loaded += 1
				else:
					push_warning("KitDataRegistry.load_dir: 加载失败 '%s'" % fname)
		entry = da.get_next()
	da.list_dir_end()
	return loaded


## 取 (type,id) 定义;缺 → push_warning + null。
func get_def(type: StringName, id: StringName) -> Variant:
	if _store.has(type) and (_store[type] as Dictionary).has(id):
		return _store[type][id]
	push_warning("KitDataRegistry.get_def: 未登记 [%s/%s]" % [type, id])
	return null


## 取 (type,id) 定义;缺 → 返回 fallback,不报错。
func get_def_or(type: StringName, id: StringName, fallback: Variant = null) -> Variant:
	if _store.has(type) and (_store[type] as Dictionary).has(id):
		return _store[type][id]
	return fallback


func has_def(type: StringName, id: StringName) -> bool:
	return _store.has(type) and (_store[type] as Dictionary).has(id)


## 某 type 的全部定义(顺序为插入序);未知 type → []。
func all(type: StringName) -> Array:
	return (_store[type] as Dictionary).values() if _store.has(type) else []


func ids(type: StringName) -> Array:
	return (_store[type] as Dictionary).keys() if _store.has(type) else []


func types() -> Array:
	return _store.keys()


func count(type: StringName) -> int:
	return (_store[type] as Dictionary).size() if _store.has(type) else 0


## 清空某 type(空 type → 清空全部)。
func clear(type: StringName = &"") -> void:
	if String(type).is_empty():
		_store.clear()
	else:
		_store.erase(type)


## 取 def 的 id:res 有 id_property 属性且非空 → StringName(该值);否则文件名 stem。
## 用引擎原生 Object.get(故本类查询方法叫 get_def,不占用 get)。
func _derive_id(res: Variant, fname: String, id_property: StringName) -> StringName:
	if res is Object:
		var v = (res as Object).get(id_property)
		if v != null and String(v) != "":
			return StringName(v)
	return StringName(fname.get_file().get_basename())
```

- [ ] **Step 2: 写 `test/fixtures/test_data_def.gd`**

```gdscript
extends Resource
## KitDataRegistry load_dir 测试用最小定义(带 id + max_stack 两个 @export)。
## 无 class_name,经运行时 load 与 ResourceSaver 使用。
@export var id: StringName
@export var max_stack: int = 99
```

- [ ] **Step 3: 写 `test/test_kit_data_registry.gd`**

```gdscript
extends SceneTree
## KitDataRegistry headless 断言。RefCounted,直接 load().new()。register/查询用任意
## Variant def(免造 .tres);load_dir 用运行时 ResourceSaver 造临时 .tres 到 user://。
## 运行:godot --headless --path . -s res://test/test_kit_data_registry.gd

var Reg
var Def


func _initialize() -> void:
	Reg = load("res://addons/godot-core-kit/data/kit_data_registry.gd")
	Def = load("res://test/fixtures/test_data_def.gd")
	var failures := 0

	var r = Reg.new()

	# 1. register + get_def
	r.register(&"item", &"wood", {"n": 1})
	if r.get_def(&"item", &"wood") != {"n": 1}:
		print("FAIL 1: register/get_def 失败"); failures += 1

	# 2. has_def
	if not r.has_def(&"item", &"wood") or r.has_def(&"item", &"gold") or r.has_def(&"crop", &"x"):
		print("FAIL 2: has_def 判定错"); failures += 1

	# 3. 缺失 get_def -> null(push_warning)
	if r.get_def(&"item", &"gold") != null:
		print("FAIL 3: 缺失 get_def 应 null"); failures += 1

	# 4. get_def_or fallback
	if r.get_def_or(&"item", &"gold", 42) != 42:
		print("FAIL 4: get_def_or 应返回 fallback"); failures += 1

	# 5. 覆盖(push_warning)
	r.register(&"item", &"wood", {"n": 2})
	if r.get_def(&"item", &"wood") != {"n": 2}:
		print("FAIL 5: register 覆盖应更新值"); failures += 1

	# 6. all/ids/count/types
	r.register(&"item", &"stone", {"n": 3})
	if r.count(&"item") != 2 or r.ids(&"item").size() != 2 or r.all(&"item").size() != 2 or not (&"item" in r.types()):
		print("FAIL 6: all/ids/count/types 错"); failures += 1
	if not (&"wood" in r.ids(&"item")) or not (&"stone" in r.ids(&"item")):
		print("FAIL 6: ids 应含 wood/stone"); failures += 1

	# 7. clear(type) / clear()
	r.register(&"crop", &"turnip", {"g": 4})
	r.clear(&"item")
	if r.count(&"item") != 0 or r.count(&"crop") != 1:
		print("FAIL 7: clear(item) 应只清 item"); failures += 1
	r.clear()
	if r.types().size() != 0:
		print("FAIL 7: clear() 应清全部"); failures += 1

	# 8. load_dir 载入(造临时 .tres:turnip 带属性 id / potato 取文件名)
	var dir := "user://test_registry"
	DirAccess.make_dir_recursive_absolute(dir)
	var d1 = Def.new(); d1.id = &"turnip"; d1.max_stack = 99
	ResourceSaver.save(d1, dir + "/turnip.tres")
	var d2 = Def.new()  # 不设 id -> 取文件名 potato
	ResourceSaver.save(d2, dir + "/potato.tres")
	var r2 = Reg.new()
	var loaded = r2.load_dir(&"crop", dir)
	if loaded != 2 or not r2.has_def(&"crop", &"turnip") or not r2.has_def(&"crop", &"potato"):
		print("FAIL 8: load_dir 应载入 2 条,实际 %d" % loaded); failures += 1
	var cd = r2.get_def(&"crop", &"turnip")
	if cd == null or cd.max_stack != 99:
		print("FAIL 8: load_dir 载入的 def.max_stack 应 99"); failures += 1
	DirAccess.remove_absolute(dir + "/turnip.tres")
	DirAccess.remove_absolute(dir + "/potato.tres")
	DirAccess.remove_absolute(dir)

	# 9. load_dir 坏路径
	if Reg.new().load_dir(&"x", "res://__nope__") != 0:
		print("FAIL 9: 坏路径 load_dir 应返 0"); failures += 1

	if failures == 0:
		print("test_kit_data_registry: ALL PASS")
		quit(0)
	else:
		print("test_kit_data_registry: %d FAILURE(S)" % failures)
		quit(1)
```

- [ ] **Step 4: run_all 注册**

`test/run_all.ps1` 的 `$tests` 数组末尾(`'test_kit_inventory'` 后)加 `,'test_kit_data_registry'`;`:1` 注释 `21 个断言测试` → `22 个断言测试`。

- [ ] **Step 5: import + 单跑测试**

```
godot --headless --path . --import
godot --headless --path . -s res://test/test_kit_data_registry.gd
```
Expected: `test_kit_data_registry: ALL PASS`,退出码 0。FAIL 则按打印修 `kit_data_registry.gd`;若 load_dir(test 8)失败,先确认 `test/fixtures/test_data_def.gd` 已 import(`.uid` 生成)。

- [ ] **Step 6: Commit**

```bash
git add addons/godot-core-kit/data/kit_data_registry.gd test/fixtures/test_data_def.gd test/test_kit_data_registry.gd test/run_all.ps1
git commit -m "feat: KitDataRegistry 定义数据表 + 9 条 headless 断言"
```

---

### Task 2: 版本 / 文档 / demo / 全量收尾

**Files:**
- Modify: `addons/godot-core-kit/plugin.cfg`、`addons/godot-core-kit/core_kit.gd`(仅 VERSION)、`test/test_core_kit.gd`(仅版本断言)、`demo/demo.gd`、`test/run_all.ps1`(demo marker)
- Modify: `README.md`、`addons/godot-core-kit/docs/README.md`、`addons/godot-core-kit/docs/architecture.md`
- Create: `addons/godot-core-kit/docs/data/kit-data-registry.md`

- [ ] **Step 1: 三处版本 → 0.17.0**

- `addons/godot-core-kit/plugin.cfg`:`version="0.16.0"` → `"0.17.0"`;description 末尾追加 `;0.17.0 新增 off-facade 定义数据表 KitDataRegistry(data/,extends RefCounted):type→{id→def} 分组存放游戏自定义 Resource,register + load_dir(扫目录,id 取属性或文件名,剥 .remap),get_def/has_def/all/ids/types/count/clear,零依赖不参与存档`。
- `addons/godot-core-kit/core_kit.gd`:`const VERSION := "0.16.0"` → `"0.17.0"`。
- `test/test_core_kit.gd`:版本断言(2 行)`"0.16.0"` → `"0.17.0"`。

- [ ] **Step 2: demo 加 DataRegistry 冒烟 marker**

`demo/demo.gd` 的 Inventory 段之后、末尾 `CoreKit.log.info("CoreKit v%s ..."` 之前插入:

```gdscript
	# 数据表 冒烟:register 两条 + count/get_def(经 off-facade KitDataRegistry)
	var reg := KitDataRegistry.new()
	reg.register(&"crop", &"turnip", {"growth_days": 4})
	reg.register(&"crop", &"potato", {"growth_days": 6})
	CoreKit.log.info("DataRegistry: crops=%d turnip_ok=%s" % [
		reg.count(&"crop"), reg.get_def(&"crop", &"turnip") != null])
```

- [ ] **Step 3: run_all demo marker**

`test/run_all.ps1` 的 demo marker 数组里,`'Inventory: wood=120 used=3 moved=true'` 后加 `,'DataRegistry: crops=2 turnip_ok=true'`。

- [ ] **Step 4: 写 `addons/godot-core-kit/docs/data/kit-data-registry.md`(五段式)**

涵盖:**职责**(按 type 分组的定义数据表,off-facade,游戏持有);**公开 API**(`register`/`load_dir`/`get_def`/`get_def_or`/`has_def`/`all`/`ids`/`types`/`count`/`clear`);**依赖**(零依赖,仅引擎 DirAccess/ResourceLoader,不参与存档);**用法示例**(定义自定义 `Resource` 子类 → `load_dir` 批量 → `get_def` 查;`register` 显式;`CoreKit.provide("data", reg)` 挂全局;与作物/背包的集成缝);**注意事项**(`get_def`/`has_def` 命名由来——避 `Object.get` 冲突;`load_dir` 只扫一层;`.remap` 导出坑;id 派生规则:属性 `id` 优先否则文件名;缺定义 `get_def` 报 warning、静默用 `get_def_or`/`has_def`)。

- [ ] **Step 5: 更新索引文档**

- 根 `README.md`:类库段加 `KitDataRegistry` 条目(指 `addons/godot-core-kit/docs/data/kit-data-registry.md`)+ 版本 0.17.0 条目。
- `docs/README.md`:类库(off-facade)表加 `KitDataRegistry` 行(指 `data/kit-data-registry.md`)。
- `docs/architecture.md`:目录布局加 `data/`(off-facade 类库);版本 → 0.17.0;测试文件数(21→22);类库清单加 KitDataRegistry;依赖纪律注(KitDataRegistry 零依赖)。

- [ ] **Step 6: 全量验证**

Run: `powershell -File test\run_all.ps1`
Expected: 末行 `=== SUMMARY FAILS=0 ===`。22 个测试全 `OK`,demo marker `DataRegistry: crops=2 turnip_ok=true` present,demo stderr 无 ERROR。

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "docs+demo: KitDataRegistry into version/docs/demo/run_all, bump 0.17.0"
```

---

## Self-Review

**Spec coverage:** register/get_def(test 1)、has_def(test 2)、缺失 get_def(test 3)、get_def_or(test 4)、覆盖(test 5)、all/ids/count/types(test 6)、clear(test 7)、load_dir 属性 id/文件名 id + max_stack(test 8)、坏路径(test 9);版本三处同步(Task 2 Step 1);docs/demo/runner(Task 2)——全覆盖。非目标(上门面、JSON 格式、Resource 基类、热重载、递归扫描、schema 校验、bus)均未纳入。`.remap` 分支为导出防御性代码,headless 无法模拟,由 spec/文档注明覆盖。

**Placeholder scan:** 无 TBD/TODO;每步含实际代码或精确编辑位置。

**Type consistency:** 查询方法全程 `get_def`/`has_def`(非 `get`/`has`);`register/load_dir/get_def/get_def_or/has_def/all/ids/types/count/clear` 在 Task 1 定义、Task 2 demo(`register/count/get_def`)一致;fixture `test/fixtures/test_data_def.gd` 的 `id`/`max_stack` 在 test 8 使用;`class_name KitDataRegistry`、脚本路径 `data/kit_data_registry.gd`、版本 0.17.0 全程一致;**不**改 test_core_kit 子系统清单(仅版本断言)。
