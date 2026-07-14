# KitInventory —— 槽位制物品容器

> `class_name KitInventory`(off-facade 类库) · `inventory/kit_inventory.gd` · `extends RefCounted`

## 职责

槽位制物品容器:固定 `capacity` 格,每格空或装「某物 ×N + 附加数据」。`add` 自动堆叠进已有格、再填空格、按单格上限溢出到多格,**返回没塞下的余量**(用于"背包满了"提示);`move` 支持拖拽的空移/合并/交换;per-slot `data` 承载品质/耐久,`data` 不同的同 id 视为不可堆叠异物。**off-facade**——游戏每个容器(背包、箱子、商店库存、机器进出料)各 `new` 一个,不挂门面。

## 公开 API

```gdscript
signal changed                            # 任何变更后发一次,UI 连此重绘

func _init(capacity: int, default_max_stack: int = 99)
func capacity() -> int

# 增删查
func add(id: StringName, amount: int, data := {}, max_stack := -1) -> int   # 返回没塞下的余量(0=全进)
func remove(id: StringName, amount: int) -> int                            # 返回实际移除数
func count(id: StringName) -> int                                          # 跨格总数(忽略 data)
func totals() -> Dictionary                                                # 全部物品 {id:总数}(跨格聚合;空包 {})
func has(id: StringName, amount := 1) -> bool
func can_add(id: StringName, amount: int, data := {}, max_stack := -1) -> int  # 预判能塞几个(不改状态)

# 槽位读写
func slot(i: int) -> Dictionary                          # 只读快照 {id,count,data};空/越界返回 {}
func set_slot(i: int, id: StringName, amount: int, data := {})  # 直接置位(载档/编辑器);amount<=0 清格
func clear_slot(i: int) -> void
func move(from: int, to: int) -> void                    # 拖拽:空移/同 id 合并/否则交换
func swap(a: int, b: int) -> void
func is_full() -> bool                                   # 无空格
func first_empty() -> int                                # 无空格返回 -1
func used_slots() -> int
func clear() -> void

# 持久化
func to_dict() -> Dictionary
func from_dict(d: Dictionary) -> void
```

## 依赖

零依赖(不 `preload` 任何子系统,不挂门面)。单格上限 `max_stack` 若要按物品区分,由**游戏侧粘合**——从 `KitDataRegistry` 读该物品定义的 `max_stack` 传入 `add`:

```gdscript
var def = registry.get_def(&"item", id)
bag.add(id, n, {}, def.max_stack)
```

## 用法示例

```gdscript
# 玩家背包(游戏自己持有;要全局可达可 CoreKit.provide("bag", bag))
var bag := KitInventory.new(30)
bag.changed.connect(_refresh_ui)

# 采集:塞不下的返回余量
var overflow := bag.add(&"wood", 120)
if overflow > 0:
    show_toast("背包已满,%d 个木头没装下" % overflow)

# 箱子是另一个实例
var chest := KitInventory.new(50)

# 拖拽整理(格 3 拖到格 5)
bag.move(3, 5)

# 存/读档
save["bag"] = bag.to_dict()
bag.from_dict(save["bag"])   # 恢复后自动发 changed
```

## 注意事项

- **数量参数名 `amount`**,不叫 `count`——避与方法 `count(id)` 同名遮蔽(GDScript 名字冲突坑)。
- **`move` 合并按 `default_max_stack`**:`move` 不知道 per-item 的 `max_stack`,同 id 合并时用容器的默认单格上限。绝大多数游戏堆叠上限全局统一,默认正确;若某物品单格上限特殊,用 `add`/`remove` 组合而非 `move`。
- **per-slot `data` 深比较**:堆叠/合并只在 `id` 相同**且** `data` 相等时发生(Godot 4 Dictionary `==` 是按值深比较)。金星萝卜 `{q:2}` 与普通萝卜 `{}` 因此自动分格。
- **JSON int→float**:经 `CoreKit.saves`(JSON)往返后 `count` 会变 float,`from_dict` 已用 `int()` 包回;自定义 `data` 里的数值需游戏自己按需 `int()`。
- **`totals()` 按 id 聚合**:跨格合并同 id(忽略 `data` 分堆),返回 `{id: 总数}`。背包 UI/存量查询列全部物品时用它,免手动遍历 `capacity()`×`slot(i)`。要按字母序展示,注意 `StringName` 键的排序坑(见 `KitDataRegistry` 文档)。
- **`slot()` 返回深拷快照**:改返回的 Dictionary 不影响容器,要改内容用 `set_slot`。
- 纯数据容器(RefCounted),不入场景树;`changed` 是原生 signal,连 `RefCounted` 方法无自动断连问题(与 EventBus 的 RefCounted 监听者坑无关)。
