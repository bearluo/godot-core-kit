# UI 层级管理器(CoreKit.layers / LayerManager)

> `CoreKit.layers` · `systems/layer_manager.gd`(`extends Node`,无 class_name)· 第 13 门面子系统

## 职责

给游戏一组**跨场景常驻的具名 CanvasLayer**,z 序由一张权威常量表定义。因宿主是 CoreKit autoload 的子节点,这些 `CanvasLayer` 及挂在其上的内容**独立于当前场景渲染、跨 `change_scene` 存活**——这正是"跨场景 HUD / Toast / Loading / 全局对话框"需要的(挂在关卡场景里的 UI 会随换场景一起销毁,挂在具名层上则常驻)。同时把 DevConsole(128)、SceneManager 转场遮罩(4096)两个既有魔法层号收编为**保留带常量**,让游戏引用而非猜数字,新层安全落在保留带之下。与 `KitUiStack` 正交:层管理器只管"节点挂哪层、z 多少",栈语义/输入在 `KitUiStack`。

## 公开 API

| 成员 | 说明 |
|---|---|
| `layer(name: StringName) -> CanvasLayer` | 取(懒建)具名层。首次创建并按 z 表设 `.layer`、挂到管理器下、缓存。未知名(未内置且未 `register_layer`)→ `push_error` + `null`。 |
| `mount(node: Node, name: StringName) -> void` | 把节点从原父摘下、挂进具名层(常驻)。未知层名 → `push_error` + no-op。 |
| `clear(name: StringName) -> void` | `queue_free` 某层全部子节点。未建的层 → no-op。 |
| `register_layer(name: StringName, z: int) -> void` | 登记自定义层名→z(懒建在下次 `layer()`)。重名 → `push_warning` + 拒;`z >= CONSOLE(128)` → `push_warning` 但仍登记。 |
| `has_layer(name: StringName) -> bool` | 是否已登记该层名(内置或 register 过);不创建。 |

**z 序常量表**(权威单一数据源):

| 常量 | z | 用途 | 管理器创建 |
|---|---|---|---|
| `BACKGROUND` | -10 | 世界底下(视差/天幕) | ✓(名 `"background"`) |
| `HUD` | 10 | 常驻血条/小地图 | ✓(`"hud"`) |
| `WINDOW` | 20 | 游戏内面板 | ✓(`"window"`) |
| `POPUP` | 30 | 弹窗 | ✓(`"popup"`) |
| `MODAL` | 40 | 模态 | ✓(`"modal"`) |
| `NOTIFY` | 50 | Toast/成就弹 | ✓(`"notify"`) |
| `SYSTEM` | 60 | Loading/暂停幕 | ✓(`"system"`) |
| `CONSOLE` | 128 | DevConsole 现值 | ✗ 保留带,DevConsole 自持 |
| `TRANSITION` | 4096 | SceneManager 转场遮罩现值 | ✗ 保留带,SceneManager 自持 |

## 依赖

**零跨系统依赖**:只用 `push_warning`/`push_error` 诊断,无 `bind_*`,不引其他子系统,可脱离门面 headless 断言(`.new()` + `add_child` 即用)。`DevConsole`/`SceneManager` **不反向依赖**本管理器——它们保留各自的层号字面量(128/4096),仅加一行交叉引用注释,故无初始化顺序耦合。

## 用法示例

```gdscript
# 跨场景常驻 HUD(挂进 hud 层,换场景不丢)
var hud := preload("res://ui/hud.tscn").instantiate()
CoreKit.layers.mount(hud, "hud")

# 全局 Toast:notify 层
CoreKit.layers.mount(toast, "notify")

# 与 KitUiStack 组合:把一个栈挂进 modal 层,栈在这层里管 push/pop
var menu_stack := KitUiStack.new()
CoreKit.layers.mount(menu_stack, "modal")
menu_stack.push(preload("res://ui/pause_menu.tscn"))

# 自定义层(z 应 < 128 以免盖过控制台/转场)
CoreKit.layers.register_layer("weather", 55)
CoreKit.layers.mount(rain_overlay, "weather")

# 引用权威常量,不猜数字:想"在一切之上、但在控制台之下"→ 取 60~128 之间
```

## 注意事项

- **跨场景常驻靠挂 autoload 子树**:具名层是 `CoreKit.layers`(autoload 子节点)的子节点,故 `SceneManager.change_scene` 替换 current_scene 时不受影响。你挂上去的节点由你(或 `clear`)负责释放。
- **保留带不创建**:`console`/`transition` 不是可 `mount` 的层名(它们由 DevConsole/SceneManager 各自拥有);`CONSOLE`/`TRANSITION` 常量仅供你判断 z 高低。
- **自定义层 z 选值**:落在 `SYSTEM(60)` 与 `CONSOLE(128)` 之间最安全;`>= 128` 会告警并可能盖过控制台/转场。
- **渲染叠放**:转场遮罩(4096)与控制台(128)渲染时盖在所有具名层(≤60)之上——一次场景淡入淡出会覆盖 HUD/模态,符合预期。
- **mount 摘旧父**:`mount` 会先把节点从当前父节点 `remove_child` 再挂入目标层,可安全地在层间搬动。
- **层是静态容器**:管理器不给层做进出动画;动画是挂上去的内容(`KitUiStack`/`KitTransition`/你自己的 Tween)的事。
- **v1 范围外**:重构 console/transition(document-only)、层动画、焦点管理、自动塞 KitUiStack、具名路由。
