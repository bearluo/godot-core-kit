# KitDataRegistry —— 定义数据表

> `class_name KitDataRegistry`(off-facade 类库) · `data/kit_data_registry.gd` · `extends RefCounted`

## 职责

按 `type` 分组存放游戏的**定义**(作物/物品/配方等):`type → { id → def }`。定义 = 游戏自定义的 `Resource` 子类的 `.tres`(Inspector 可编、类型安全)。支持显式 `register` 一条,`load_dir` 扫一个目录批量载入(id 取定义的 `id` 属性,否则取文件名),或 `register_records` 一次登记一批字典记录(CSV / JSON / 远端配置)。按 `type/id` 查。**off-facade**——游戏 `new` 并持有一份(要全局可达可 `CoreKit.provide("data", reg)`)。只读数据目录,不参与存档。

## 公开 API

```gdscript
func register(type: StringName, id: StringName, def: Variant) -> void   # 显式登记(覆盖 push_warning)
func load_dir(type: StringName, dir_path: String, id_property := &"id") -> int  # 扫目录批量,返回登记数
func register_records(type: StringName, records: Variant, id_key := &"id", factory := Callable()) -> int  # 批量登记字典记录,返回成功数

func get_def(type: StringName, id: StringName) -> Variant        # 缺 → push_warning + null
func get_def_or(type: StringName, id: StringName, fallback := null) -> Variant   # 缺 → fallback,不报错
func has_def(type: StringName, id: StringName) -> bool

func all(type: StringName) -> Array        # 该 type 全部定义(插入序)
func ids(type: StringName, sorted := false) -> Array     # sorted=true 按字符串字典序
func types(sorted := false) -> Array                     # sorted=true 按字符串字典序
func count(type: StringName) -> int
func clear(type := &"") -> void            # 空 type 清全部
```

## 依赖

零依赖(仅用引擎 `DirAccess`/`ResourceLoader`,不挂门面、不 `preload` 任何子系统)。不参与存档——数据表从源资产载入,不 `to_dict`。

## 用法示例

```gdscript
# 游戏定义自己的 Resource 子类(在游戏工程里,不在 kit 里)
# res://game/crop_def.gd:
#   class_name CropDef extends Resource
#   @export var id: StringName
#   @export var growth_days: int
#   @export var sell_price: int

var reg := KitDataRegistry.new()

# 扫目录批量载入 res://data/crops/*.tres
reg.load_dir(&"crop", "res://data/crops")

# 或显式登记
reg.register(&"item", &"wood", wood_def)

# 挂全局服务,别处 CoreKit.service("data") 取
CoreKit.provide("data", reg)

# 集成缝:作物生长 = 订阅时钟 + 查数据表
CoreKit.bus.subscribe(CoreKit.clock.EV_DAY_CHANGED, func(_p):
    var cd = reg.get_def(&"crop", plot.crop_id)
    plot.grow(cd.growth_days))

# 集成缝:背包容量 = 查数据表的 max_stack
bag.add(id, n, {}, reg.get_def(&"item", id).max_stack)
```

## 字典记录:register_records(CSV / JSON / 远端配置)

`register_records(type, records, id_key, factory)` 逐条处理一个记录数组,返回成功登记的条数:

- id 取 `record[id_key]`(String 键和 StringName 键都认),统一转 `StringName`;CSV 里被识别成整数的 `101` 用 `&"101"` 查。
- 非字典、缺 id、id 为空或 null 的记录 → `push_warning` 跳过,不计数。`records` 本身不是 Array(比如 JSON 解析失败得到 null)→ 告警并返回 0。
- **默认存只读副本**:`record.duplicate(true)` 再 `make_read_only()`。改调用方手里的字典不影响已登记的数据;游戏逻辑误写定义会报错。注意 `make_read_only` 只锁顶层,嵌套的字典和数组仍可写。
- **传 `factory`**:存 `factory.call(record)` 的返回值(通常是游戏自己的 Resource 子类),返回 null 则跳过。传给 factory 的是原记录,kit 不复制。
- 重复 id(批内或与已有定义重复)和 `register` 一样:告警后覆盖。

三种数据源的接法,kit 都不新增解析代码:

```gdscript
# CSV:游戏层装 timothyqiu/godot-csv-data-importer,导入面板选「CSV Data」
reg.register_records(&"crop", preload("res://data/crops.csv").records)

# JSON:返回值不是 Array 时 register_records 会告警
reg.register_records(&"crop", JSON.parse_string(FileAccess.get_file_as_string("res://data/crops.json")))

# 远端配置:下载解析后整表替换
reg.clear(&"crop")
reg.register_records(&"crop", remote_rows)

# 想要强类型:用 factory 转成自己的 Resource(kit 不内置字段映射器)
reg.register_records(&"crop", rows, &"id", func(r):
    var d := CropDef.new()
    for k in r: d.set(k, r[k])
    return d)
```

字段类型由数据源决定(CSV Data Importer 会识别数字和布尔,JSON 有原生类型)。读取时字典定义和 Resource 定义都能写 `def.price`;区别是字典没有类型提示、字段不存在时点号访问会报错,需要容错的地方用 `def.get("price", 0)`。

## 注意事项

- **命名 `get_def`/`has_def`**,不叫 `get`/`has`——`Object.get(property)` 是引擎原生方法,重定义 `get` 会冲突(且内部 `_derive_id` 还要用原生 `res.get(id_property)`)。
- **`load_dir` 只扫一层**(不递归子目录);要多层各自 `load_dir`。
- **导出坑**:导出包里 `.tres` 可能呈现为 `xxx.tres.remap`,`load_dir` 会自动剥 `.remap` 再 `load`(编辑器/headless 下是普通 `.tres`,不受影响)。
- **id 派生规则**:定义有非空 `id_property`(默认 `id`)属性则用其值,否则用文件名 stem(`turnip.tres` → `&"turnip"`)。
- **缺定义**:`get_def` 报 `push_warning` 并返回 null(与 `CoreKit.service` 的"未找到即报错"范式一致);要静默探测用 `has_def` 或 `get_def_or`。
- **字典定义**:`register_records` 存的是只读字典(或 factory 的返回值);`load_dir` 只扫 `.tres`/`.res`。kit 不解析 CSV、不做类型/schema 校验,见上一节。
- **`ids`/`types` 的 `sorted` 参数**:默认返回插入序;`sorted=true` 按**字符串字典序**排(内部用 `String(x) < String(y)` 比较)。这是因为 `StringName` 数组的原生 `.sort()` 按**指针地址**排、非字典序——列 UI/日志需稳定字母序时务必用 `sorted=true`(或自己 `sort_custom`),别指望裸 `.sort()`。
