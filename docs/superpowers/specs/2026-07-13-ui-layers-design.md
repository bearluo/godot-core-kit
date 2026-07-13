# UI 层级管理器设计(LayerManager / CoreKit.layers)

> 承 UI 栈导航 v0.13.0 的另一半。给用 core-kit 的游戏一组**跨场景常驻的具名 CanvasLayer**,z 序写死成一张权威表;`change_scene` 时这些层及挂在上面的东西全部存活。收编现有两个魔法层号(DevConsole=128、SceneManager 淡入淡出=4096)为**保留带常量**(只登记、不重构那两个子系统)。

**版本:** v0.14.0(承 ui-stack v0.13.0)

## 目标

新增第 13 个门面子系统 **`CoreKit.layers`**(`systems/layer_manager.gd`,`extends Node`):在自己节点下按需(懒建)一组具名 `CanvasLayer`,z 序由一张常量表定义(`HUD=10`/`WINDOW=20`/`POPUP=30`/`MODAL=40`/`NOTIFY=50`/`SYSTEM=60`,另 `BACKGROUND=-10`)。因宿主是 CoreKit autoload 的子节点,这些 `CanvasLayer` **独立于当前场景渲染、跨 `change_scene` 存活**——正是"跨场景 HUD/Toast/Loading overlay"要的。`layer(name)` 取层、`mount(node, name)` 把节点搬进层、`clear(name)` 清层、`register_layer(name, z)` 扩自定义层。并把 `CONSOLE=128`/`TRANSITION=4096` 定义为**权威保留带常量**,让游戏引用而非猜数字,新层安全落在保留带之下。

## 非目标(YAGNI v1)

- **重构 DevConsole / SceneManager**:那两个的层号字面量**不动**(保留 `128`/`4096`),只各加一行注释指向本管理器的常量表。管理器**不创建** `console`/`transition` 层(它们由那两个子系统各自拥有)。收编=建立单一权威 + 让新层落在保留带下,不是把工作代码翻一遍。
- **层的动画 / 转场**:具名层是静态容器,进出动画是挂上去的内容(如 `KitUiStack`/`KitTransition`)自己的事。
- **焦点 / 输入路由**:管理器只管"节点挂哪层、z 多少",不碰输入(那是 `KitUiStack` 的职责)。
- **自动塞 KitUiStack**:管理器不认识栈;组合由游戏显式 `CoreKit.layers.mount(stack, "menu")` 完成。
- **重排现有 z 序**:`console(128)` 与 `transition(4096)` 的相对高低保持现状(transition 盖 console),不借机改。
- **每层单例 UI / 具名路由**:管理器给"层"不给"屏";屏的栈语义在 `KitUiStack`。

## 架构 / 定位

**上门面**,第 13 个子系统 `CoreKit.layers`,与其余门面子系统同为 `systems/` 下**无 `class_name`** 的预加载脚本(经门面属性访问,不做全局类)。这是与 off-facade 的 `KitUiStack`(可选类库)的本质区别:**跨场景常驻必须活在 autoload 宿主上**,只有挂在 CoreKit 子树才免于被 `change_scene` 替换。

**打破"12 子系统"不变量 → 13**:`core_kit.gd` 新增 preload/属性/构造/`_services` 注册/`RESERVED_KEYS` 一项;`test_core_kit.gd` 的属性表(12→13)、节点序数组(加 `LayerManager`)、保留键表同步。这是本子系统唯一的"侵入性"改动,但都在门面自身接线范围内、纯增量。

依赖纪律:`LayerManager` **零跨系统依赖**(诊断走 `push_warning`/`push_error`,不引其他子系统,无 `bind_*`)。`DevConsole`/`SceneManager` **不反向依赖**本管理器(document-only)——它们保留字面量,仅注释交叉引用,故无初始化顺序风险。构造序把 `LayerManager` append 在末位(第 13,`LocaleManager` 之后)。

## 组件

### a. `LayerManager`(`systems/layer_manager.gd`,`extends Node`)

```gdscript
extends Node
## CoreKit.layers —— 具名 CanvasLayer 管理器(第 13 子系统)。在本节点下懒建一组
## 具名 CanvasLayer,z 序由常量表定义;因本节点是 CoreKit autoload 子节点,这些层
## 及挂在其上的内容独立于当前场景渲染、跨 change_scene 存活。零跨系统依赖。
##
## 保留带(本管理器不创建,仅登记常量供引用):
##   CONSOLE=128   —— DevConsole 自建自持(console/dev_console.gd)
##   TRANSITION=4096 —— SceneManager 淡入淡出遮罩自建自持(systems/scene_manager.gd)
## 新增自定义层的 z 应落在 SYSTEM(60)与 CONSOLE(128)之间以免盖过控制台/转场。

## --- z 序常量(权威单一数据源;游戏引用而非猜数字)---
const BACKGROUND := -10   ## 世界底下(视差/天幕)
const HUD := 10           ## 常驻血条/小地图
const WINDOW := 20        ## 游戏内面板
const POPUP := 30         ## 弹窗
const MODAL := 40         ## 模态
const NOTIFY := 50        ## Toast/成就弹
const SYSTEM := 60        ## Loading/暂停幕
const CONSOLE := 128      ## 保留带:DevConsole 现值(不创建)
const TRANSITION := 4096  ## 保留带:SceneManager 转场遮罩现值(不创建)

## 内置具名层 → z。register_layer 往这里加自定义项;console/transition 故意不在内。
var _z_map: Dictionary = {
	&"background": BACKGROUND, &"hud": HUD, &"window": WINDOW, &"popup": POPUP,
	&"modal": MODAL, &"notify": NOTIFY, &"system": SYSTEM,
}
var _layers: Dictionary = {}   # StringName -> CanvasLayer(已懒建缓存)


## 取(懒建)具名层。未知名(未内置且未 register)→ push_error + null。
func layer(name: StringName) -> CanvasLayer:
	if _layers.has(name):
		return _layers[name]
	if not _z_map.has(name):
		push_error("CoreKit.layers: 未知层名 '%s'(需内置名或先 register_layer)" % name)
		return null
	var cl := CanvasLayer.new()
	cl.name = "Layer_%s" % name
	cl.layer = _z_map[name]
	add_child(cl)
	_layers[name] = cl
	return cl


## 把节点搬进具名层(从原父摘下再挂)。未知层名 → push_error + no-op。
func mount(node: Node, name: StringName) -> void:
	var cl := layer(name)
	if cl == null:
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	cl.add_child(node)


## 清空某层(queue_free 全部子节点)。未建的层 → no-op。
func clear(name: StringName) -> void:
	if not _layers.has(name):
		return
	for c in (_layers[name] as CanvasLayer).get_children():
		c.queue_free()


## 登记自定义层名→z(懒建在下次 layer() 时)。重名 → push_warning + 拒;
## z 落入保留带(>= CONSOLE)→ push_warning 但仍登记(进阶用途)。
func register_layer(name: StringName, z: int) -> void:
	if _z_map.has(name):
		push_warning("CoreKit.layers: 层名 '%s' 已存在,拒绝重复登记" % name)
		return
	if z >= CONSOLE:
		push_warning("CoreKit.layers: 自定义层 '%s' z=%d 落入保留带(>=%d),可能盖过控制台/转场" % [name, z, CONSOLE])
	_z_map[name] = z


## 是否已登记该层名(内置或 register 过);不创建。
func has_layer(name: StringName) -> bool:
	return _z_map.has(name)
```

### b. `core_kit.gd` 门面接线(第 13 子系统)

- 新增 `const LayerManagerScript := preload("res://addons/godot-core-kit/systems/layer_manager.gd")`。
- 新增属性 `var layers: LayerManagerScript`。
- `_init` 末尾(`i18n` 之后)construct + add_child:
  ```gdscript
  layers = LayerManagerScript.new()
  layers.name = "LayerManager"
  add_child(layers)
  ```
- `_ready` 里 `_services["layers"] = layers`(无 `bind_*`,零依赖)。
- `RESERVED_KEYS` 末尾加 `"layers"`(12→13 项)。
- `VERSION` → `"0.14.0"`。

### c. 交叉引用注释(document-only,不改行为)

- `console/dev_console.gd` 的 `layer = 128` 处加一行注释:`# = CoreKit.layers.CONSOLE(权威保留带常量,见 systems/layer_manager.gd)`。
- `systems/scene_manager.gd` 的 `const _FADE_LAYER := 4096` 处加一行注释:`# = CoreKit.layers.TRANSITION(权威保留带常量,见 systems/layer_manager.gd)`。

## 数据流

`CoreKit.layers.mount(hud, "hud")` → `layer("hud")` 懒建 `CanvasLayer(layer=10)` 挂到 LayerManager 下(首次)→ `hud` 从原父摘下、挂进该层。此后 `change_scene` 替换 current_scene,LayerManager(CoreKit 子节点)与其 CanvasLayer 子树不受影响,`hud` 常驻。转场遮罩(4096)/控制台(128)渲染时盖在这些层之上,符合预期。

## 错误处理

- `layer`/`mount` 未知层名 → `push_error` + `null`/no-op,不崩。
- `register_layer` 重名 → `push_warning` + 拒(原 z 不变);z 落保留带 → `push_warning` 但登记。
- `clear` 未建层 → no-op。
- `mount` 传已在树中的节点 → 先 `remove_child` 再挂,不重复父。

## 测试(headless)

### 新 `test/test_layer_manager.gd`(LayerManager 入树后断言)

`LayerManagerScript.new()` → `root.add_child` → `await process_frame`,末 `free`。

1. **懒建 + 缓存 + z 值**:`layer("hud")` 返回 `CanvasLayer` 且 `.layer==10`;二次 `layer("hud")` 返回**同一实例**;`layer("modal").layer==40`、`layer("background").layer==-10`。
2. **内置 z 序常量**:`HUD==10`、`WINDOW==20`、`POPUP==30`、`MODAL==40`、`NOTIFY==50`、`SYSTEM==60`、`BACKGROUND==-10`。
3. **保留带常量 + 不创建**:`CONSOLE==128`、`TRANSITION==4096`;`has_layer("console")==false`、`has_layer("transition")==false`;`layer("console")==null`(未知名 push_error)。
4. **mount 搬入 + 摘旧父**:`n` 先 `add_child` 到一个临时 Node;`mount(n, "popup")` 后 `n.get_parent()==layer("popup")`,临时 Node `get_child_count()==0`。
5. **clear**:`mount` 两个节点到 "notify" → `clear("notify")` → `await process_frame` → `layer("notify").get_child_count()==0`。
6. **register_layer + 懒建**:`register_layer("weather", -5)` → `has_layer("weather")` → `layer("weather").layer==-5`。
7. **register 重名拒**:`register_layer("hud", 999)` → `push_warning` + `layer("hud").layer` 仍 `10`(未被改)。
8. **层挂在管理器下(常驻结构佐证)**:`layer("hud").get_parent()==` 该 LayerManager 实例(故随 autoload 存活;跨场景存活为结构性质,不真切场景验证)。

### `test/test_core_kit.gd`(改 3 处)

- test 2 属性表加 `["layers", "res://addons/godot-core-kit/systems/layer_manager.gd"]`(12→13 项)。
- test 3 节点序数组末加 `"LayerManager"`,计数 12→13。
- test 6 `builtin_keys` 末加 `"layers"`;并加一条:`kit.provide("layers", 1)` 被拒、`kit.service("layers")==kit.layers`(保留键守卫)。
- 版本断言 → `"0.14.0"`。

## 收尾件

- 新 `systems/layer_manager.gd`(+`.uid`);新 `test/test_layer_manager.gd`(+`.uid`)。
- `core_kit.gd`:preload + 属性 + 构造 + `_services` + `RESERVED_KEYS` + `VERSION` 0.14.0。
- `console/dev_console.gd` / `systems/scene_manager.gd`:各加一行交叉引用注释(不改行为)。
- `test/test_core_kit.gd`:属性表/节点序/保留键/版本四处 + provide 守卫断言。
- 新 `docs/systems/layer-manager.md`(五段式:职责/公开 API/依赖/用法示例/注意事项),记 z 序表、保留带、跨场景常驻、与 KitUiStack 组合(`mount(stack, name)`)、mount 摘旧父语义。
- `docs/README.md`:门面子系统表加 `CoreKit.layers` 行;`docs/architecture.md`:子系统数 12→13(全文该处措辞更新)、目录布局 `systems/` 注、版本 0.14.0、测试文件数(18→19)、依赖纪律注(LayerManager 零依赖、console/transition document-only)。
- 根 `README.md`:门面属性表加 `CoreKit.layers` 行 + 版本 0.14.0 条目。
- `plugin.cfg`:version 0.14.0 + description 追加。
- `demo/demo.gd`:`CoreKit.layers` 冒烟——`mount` 一个 Control 到 "hud"、`layer("modal").layer` marker(如 `Layers: hud_z=10 modal_z=40 mounted=true`,不依赖渲染,headless 确定性);`test/run_all.ps1`:加 `test_layer_manager`(测试文件 18→19)+ demo marker `Layers: hud_z=10` + 计数。

## 我替你拍的默认(实现时若无异议即照此)

上门面第 13 子系统 `CoreKit.layers`(`systems/layer_manager.gd`,无 class_name)· z 表 BACKGROUND=-10/HUD=10/WINDOW=20/POPUP=30/MODAL=40/NOTIFY=50/SYSTEM=60 + 保留带 CONSOLE=128/TRANSITION=4096 · 懒建 + 缓存 · API `layer`/`mount`/`clear`/`register_layer`/`has_layer` · console/transition **只登记不重构**(各加一行注释)· 管理器不创建 console/transition 层 · 层名用小写 StringName · mount 摘旧父再挂 · 打破 12→13 子系统(门面接线 + test_core_kit 同步)· 版本 0.14.0。
