# KitDataRegistry —— 定义数据表

> `class_name KitDataRegistry`(off-facade 类库) · `data/kit_data_registry.gd` · `extends RefCounted`

## 职责

按 `type` 分组存放游戏的**定义**(作物/物品/配方等):`type → { id → def }`。定义 = 游戏自定义的 `Resource` 子类的 `.tres`(Inspector 可编、类型安全)。支持显式 `register` 一条,或 `load_dir` 扫一个目录批量载入(id 取定义的 `id` 属性,否则取文件名)。按 `type/id` 查。**off-facade**——游戏 `new` 并持有一份(要全局可达可 `CoreKit.provide("data", reg)`)。只读数据目录,不参与存档。

## 公开 API

```gdscript
func register(type: StringName, id: StringName, def: Variant) -> void   # 显式登记(覆盖 push_warning)
func load_dir(type: StringName, dir_path: String, id_property := &"id") -> int  # 扫目录批量,返回登记数

func get_def(type: StringName, id: StringName) -> Variant        # 缺 → push_warning + null
func get_def_or(type: StringName, id: StringName, fallback := null) -> Variant   # 缺 → fallback,不报错
func has_def(type: StringName, id: StringName) -> bool

func all(type: StringName) -> Array        # 该 type 全部定义(插入序)
func ids(type: StringName) -> Array
func types() -> Array
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

## 注意事项

- **命名 `get_def`/`has_def`**,不叫 `get`/`has`——`Object.get(property)` 是引擎原生方法,重定义 `get` 会冲突(且内部 `_derive_id` 还要用原生 `res.get(id_property)`)。
- **`load_dir` 只扫一层**(不递归子目录);要多层各自 `load_dir`。
- **导出坑**:导出包里 `.tres` 可能呈现为 `xxx.tres.remap`,`load_dir` 会自动剥 `.remap` 再 `load`(编辑器/headless 下是普通 `.tres`,不受影响)。
- **id 派生规则**:定义有非空 `id_property`(默认 `id`)属性则用其值,否则用文件名 stem(`turnip.tres` → `&"turnip"`)。
- **缺定义**:`get_def` 报 `push_warning` 并返回 null(与 `CoreKit.service` 的"未找到即报错"范式一致);要静默探测用 `has_def` 或 `get_def_or`。
- **格式限 Resource**:v1 不提供 JSON 载入;`register` 的 `def` 是 `Variant`,游戏若坚持可塞 Dictionary,但目录扫描针对 `.tres`/`.res`。
