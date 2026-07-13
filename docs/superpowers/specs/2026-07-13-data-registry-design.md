# 数据表设计(KitDataRegistry)

> 模拟经营农场三件套之三(3/3)。给用 core-kit 的游戏一个**定义数据表**:按 `type` 分组存放游戏自定义 `Resource`(作物/物品/配方 的 `.tres`),显式 `register` 或扫目录 `load_dir` 批量载入,按 `type/id` 查。off-facade `class_name`——游戏 `new` 并持有(可 `CoreKit.provide("data", reg)` 挂全局服务)。

**版本:** v0.17.0(承 inventory v0.16.0)

## 目标

新增 off-facade 类库 **`class_name KitDataRegistry`**(`data/kit_data_registry.gd`,`extends RefCounted`):

- **分组存储**:`type`(StringName)→ `{ id(StringName) → def(Resource) }`。定义 = 游戏自定义 `Resource` 子类的 `.tres`(Inspector 可编、类型安全)。
- **登记**:`register(type, id, def)` 显式;`load_dir(type, dir_path, id_property := &"id")` 扫目录下 `*.tres`/`*.res` 批量,id 取 def 的 `id_property` 属性(有则用)否则文件名 stem。
- **查询**:`get_def / get_def_or / has_def / all / ids / types / count`。
- **清理**:`clear(type := &"")`(空 type 清全部)。
- **导出坑处理**:导出包里 `.tres` 可能呈现为 `xxx.tres.remap`,`load_dir` 自动剥 `.remap` 再 `load`。
- **零依赖**:仅用引擎 `DirAccess`/`ResourceLoader`;只读目录,不参与存档。

## 非目标(YAGNI v1)

- **上门面**:数据表虽是全局单例语义,但**格式是游戏自定义 Resource(kit 无法预置 ItemDef 类)**,且游戏可能要多张表/自定加载时机 → 做成游戏 `new` 持有的类库,需要全局可达时游戏自行 `CoreKit.provide("data", reg)`。
- **JSON/Dictionary 定义格式**:v1 只支持 Godot `Resource`(用户选定);`register` 的 `def` 类型是 `Variant`,游戏若坚持可塞 Dictionary,但 kit 不提供 `load_json`。
- **Resource 基类/字段约定**:kit 不定义 `ItemDef`/`CropDef` 基类,不规定字段;只约定"可选 `id` 属性用作 key"。字段由游戏定。
- **热重载/文件监听**:`load_dir` 是一次性快照;改了 `.tres` 要重跑 `load_dir`。
- **递归子目录扫描**:`load_dir` 只扫一层(与 `LocaleManager.load_translations` 一致);要多层游戏多次调。
- **校验/schema**:不校验 def 字段完整性;缺字段是游戏读取时的事。
- **通配符命名空间订阅**:数据表是查询表,不发事件、不参与 bus。

## 架构 / 定位

**off-facade `class_name` 类库**,置于新目录 `data/`,`extends RefCounted`(游戏持有一份;不入树)。与 `KitInventory`/`KitStateMachine` 同类,**不挂门面、不进 `test_core_kit` 子系统清单**,仅升 plugin 版本。

`class_name` 首次运行需 `--import` 生成类缓存(demo 经 `KitDataRegistry` 引用;测试用运行时 `load()`)。

**依赖纪律**:零跨系统依赖。诊断(缺定义、目录打不开、加载失败)走引擎 `push_warning`(与 `LocaleManager.load_translations` 范式一致),不引 `CoreKit.log`。

> **命名坑**:查询方法叫 **`get_def`** 而非 `get`——`Object.get(property)` 是引擎原生方法,重定义 `get` 会与之冲突(且 `_derive_id` 内部还要用原生 `res.get(id_property)`)。同理保留 `has_def`。参见既往 member-vs-virtual 踩坑。

## 组件

### `KitDataRegistry`(`data/kit_data_registry.gd`,`class_name KitDataRegistry extends RefCounted`)

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

## 数据流

启动:`reg.load_dir(&"crop", "res://data/crops")` → `DirAccess` 遍历 `*.tres` → 每个 `ResourceLoader.load` → `_derive_id`(读 `def.id` 或文件名)→ `register`。
运行:作物系统收到 `clock:day_changed` → `var cd = reg.get_def(&"crop", plot.crop_id)` → 读 `cd.growth_days` 推进地块。
背包:`bag.add(id, n, {}, reg.get_def(&"item", id).max_stack)`。
全局可达:`CoreKit.provide("data", reg)`,别处 `CoreKit.service("data")`。

## 错误处理

- `load_dir` 目录打不开 → `push_warning` + 返回 0;单个文件加载失败 → `push_warning` 跳过,不中断整轮。
- `get_def` 缺定义 → `push_warning` + null(与 `CoreKit.service` 的"未找到即报错"范式一致);要静默用 `get_def_or`/`has_def`。
- `register` 覆盖同 (type,id) → `push_warning` 但仍覆盖(允许后加载覆盖)。
- `all/ids/count` 未知 type → 空 []/0,不报错。
- `.remap` 剥离容导出包;`_derive_id` 对无 `id` 属性的定义回退文件名,不崩。

## 测试(headless)

### 新 `test/test_kit_data_registry.gd`

`load(...)`.new()(RefCounted)。register/查询类断言用**任意 Variant def**(可塞 Dictionary,免造 .tres);`load_dir` 单独用**运行时 `ResourceSaver.save` 造临时 .tres**。

需一个 fixture 定义脚本 `test/fixtures/test_data_def.gd`:
```gdscript
extends Resource
## KitDataRegistry load_dir 测试用最小定义(带 id + max_stack 两个 @export)。
@export var id: StringName
@export var max_stack: int = 99
```

断言:
1. **register + get_def**:`register(&"item",&"wood",{"n":1})`→`get_def(&"item",&"wood")=={"n":1}`。
2. **has_def**:`has_def(&"item",&"wood")`true、`has_def(&"item",&"gold")`false、`has_def(&"crop",&"x")`false。
3. **缺失 get_def**:`get_def(&"item",&"gold")==null`(push_warning)。
4. **get_def_or**:`get_def_or(&"item",&"gold",42)==42`。
5. **覆盖**:`register(&"item",&"wood",{"n":2})`(push_warning)→`get_def` 值为 `{"n":2}`。
6. **all/ids/count**:`register` 两条 item → `count(&"item")==2`、`ids(&"item")` 含两 id、`all(&"item")` 长度 2;`types()` 含 `&"item"`。
7. **clear(type)/clear()**:`clear(&"item")`→`count(&"item")==0`、其它 type 留存;`clear()`→`types()` 空。
8. **load_dir 载入**:`ResourceSaver.save` 两个 fixture 到 `user://test_registry_XXXX/`:一个 `id=&"turnip"` 存为 `turnip.tres`、一个不设 id 存为 `potato.tres`;`load_dir(&"crop", 该目录)`→返回 2、`has_def(&"crop",&"turnip")`(取属性 id)、`has_def(&"crop",&"potato")`(取文件名)、`get_def(&"crop",&"turnip").max_stack==99`。测试后清目录。
9. **load_dir 坏路径**:`load_dir(&"x","res://__nope__")==0`(push_warning)。

### `test/test_core_kit.gd`

仅版本断言(2 行)`"0.16.0"` → `"0.17.0"`。

## 收尾件

- 新 `data/kit_data_registry.gd`(+`.uid`);新 `test/fixtures/test_data_def.gd`(+`.uid`);新 `test/test_kit_data_registry.gd`(+`.uid`)。
- `test/test_core_kit.gd`:版本断言 → 0.17.0。
- 新 `docs/data/kit-data-registry.md`(五段式),记分组模型、register/load_dir、id 派生规则、`.remap` 导出坑、get_def 命名由来、集成缝(作物/背包)、`CoreKit.provide("data", reg)` 挂全局。
- `docs/README.md`:类库表加 `KitDataRegistry` 行(指 `data/kit-data-registry.md`)。
- `docs/architecture.md`:目录布局加 `data/`、版本 0.17.0、测试文件数(21→22)、类库清单加 KitDataRegistry、依赖纪律注(零依赖)。
- 根 `README.md`:加 `KitDataRegistry` 条目 + 版本 0.17.0。
- `plugin.cfg`:version 0.17.0 + description 追加。
- `demo/demo.gd`:`KitDataRegistry` 冒烟——`new()` + `register` 两条 + `get_def`/`count`,打 marker(如 `DataRegistry: crops=2 turnip_ok=true`);`test/run_all.ps1`:加 `test_kit_data_registry`(21→22)+ demo marker `DataRegistry: ` + 计数。

## 我替你拍的默认(实现时若无异议即照此)

off-facade `class_name KitDataRegistry`(`data/kit_data_registry.gd`,`extends RefCounted`)· 分组 type→{id→def} · 定义用游戏自定义 Godot Resource(.tres)· `register` + `load_dir`(扫一层,id 取属性或文件名,剥 `.remap`)· 查询 `get_def`/`get_def_or`/`has_def`/`all`/`ids`/`types`/`count`/`clear`(避 Object.get 命名冲突)· push_warning 诊断 · 不参与存档 · 不上门面、不进 test_core_kit 子系统清单(仅升版本)· fixture 脚本 `test/fixtures/test_data_def.gd` 供 load_dir 测试 · 版本 0.17.0。
