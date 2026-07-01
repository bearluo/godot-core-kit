# godot-core-kit SceneManager 子系统设计

- 日期：2026-07-01
- 状态：已确认，待实现
- 版本目标：0.3.0
- 前置：`.superpowers/sdd/proposals/scene-manager.md`（设计提案，本文档据此定稿）、
  `2026-07-01-logger-design.md`（Logger，已实现，接缝设计模式沿用）
- 范围边界：本文档仅覆盖 `addons/godot-core-kit/scene_manager.gd` 与
  `test/test_scene_manager.gd` 两个文件的设计。**autoload 注册（`project.godot` /
  `plugin.gd`）、版本号升级（`plugin.cfg`/`core_kit.gd`/`README.md`）、demo 场景新增第二
  占位场景与冒烟接线，均为后续独立集成步骤，不在本文档与对应实现计划范围内**（对齐
  Logger 子系统 Task 1 / Task 2 的拆分方式，本文档只对应 Task 1 那一层）。

## 目标与定位

`SceneManager` 是 godot-core-kit 的全局场景切换单例：把"替换当前活动场景"这件事从零散的
`get_tree().change_scene_to_*()` 调用收敛成一个统一入口 `change_scene(target, options)`，
可选内建淡入淡出过渡、带完整切换生命周期信号。首版范围严格限定为**同步加载 + 替换当前
场景**，YAGNI：不做场景栈 push/pop、不做异步/带进度条加载、不做全局过渡默认值配置入口——
这些留给后续版本按真实需求再加。

遵守项目"独立性原则"：只使用自有 Godot `signal`（`scene_changing`/`scene_changed`/
`scene_change_failed`），不依赖 EventBus / ObjectPool / SaveManager 三个子系统；允许依赖已
上线的 `Log`（`extends Node` autoload，同 Logger 子系统惯例，`project.godot` 中已注册，
`scene_manager.gd` 引用全局标识符 `Log` 可正常解析编译，即便 `SceneManager` 自身尚未注册
为 autoload）。

## 架构与文件（本文档范围内）

```
addons/godot-core-kit/
└── scene_manager.gd        # 新增：SceneManager 单例脚本（extends Node）
test/
└── test_scene_manager.gd   # 新增：headless 断言脚本
```

不改动 `project.godot`、`plugin.gd`、`plugin.cfg`、`core_kit.gd`、`README.md`、`demo/`。
`scene_manager.gd` 写成后即可被 `preload()` 编译通过并跑纯逻辑断言，但**尚未**作为
autoload 生效——`SceneManager.change_scene(...)` 这类全局调用要等后续集成步骤把它注册进
`project.godot`（顺序追加在 `CoreKit` 之后，因为它依赖 `Log` 而不被 `CoreKit` 依赖）后才可用。

## Public API

签名如下（行为见下节"Behavior & Data Flow"）：

```gdscript
extends Node
## SceneManager —— godot-core-kit 全局场景切换单例（首版：仅替换，无场景栈）。

signal scene_changing(target_path: String)
signal scene_changed(scene_path: String, scene: Node)
signal scene_change_failed(target_path: String, error: int)  # error 取值为 Error 枚举

enum Transition { NONE, FADE }

const DEFAULT_TRANSITION := Transition.NONE
const DEFAULT_FADE_DURATION := 0.3
const DEFAULT_FADE_COLOR := Color.BLACK

# --- 公开运行时 API ---

func change_scene(target, options: Dictionary = {}) -> void

func is_changing() -> bool

func get_current_scene() -> Node

func get_current_scene_path() -> String

# --- 可测纯逻辑接缝（不碰场景树、不调 Log）---

func _validate_target(target) -> int          # 返回 Error 枚举值：OK / ERR_INVALID_PARAMETER
func _resolve_target_path(target) -> String
func _merge_options(options: Dictionary) -> Dictionary
```

- `target`：`String`（`res://...tscn|scn` 路径）或 `PackedScene`，二选一，内部按类型分派。
- `options`：可选字典，支持键 `transition`（`Transition`，默认 `NONE`）、`duration`（秒，
  默认 `0.3`，仅 `FADE` 时生效）、`color`（`Color`，默认黑，仅 `FADE` 时生效）。未识别/
  类型不对的键静默回退默认值。
- `change_scene()` 返回 `void`，内部是 GDScript 协程（含 `await`）：调用方可 fire-and-forget
  （靠信号感知结果），也可 `await SceneManager.change_scene(...)` 原地等待切换完成。

## Behavior & Data Flow

### `change_scene(target, options)` 主流程

1. **重入保护**：`_is_changing == true` → `Log.warn(...)`，发
   `scene_change_failed(target_path, ERR_BUSY)`，直接返回，不做任何场景树改动、不改
   `_is_changing`。
2. **校验**：`_validate_target(target) != OK` → `Log.error(...)`，发
   `scene_change_failed(target_path, ERR_INVALID_PARAMETER)`，返回。
3. **归一化**：`_merge_options(options)` 得到规整后的 `{transition, duration, color}`。
4. 置 `_is_changing = true`，发 `scene_changing(target_path)`。
5. 若 `transition == FADE`：确保遮罩节点已就绪，`mouse_filter` 切到 `STOP`，淡入
   （alpha 0→1，`create_tween()` 驱动 `ColorRect.modulate:a`，`await tween.finished`）。
6. **加载**：
   - `target` 是 `PackedScene` → 直接用，不走 `load()`。
   - `target` 是 `String` → `ResourceLoader.exists(target)` 预检 + 同步 `load(target)`；
     失败（不存在，或 `load()` 返回非 `PackedScene`）→ `Log.error(...)`；若已淡入则先淡出
     复原、`mouse_filter` 切回 `IGNORE`；复位 `_is_changing = false`；发
     `scene_change_failed(target_path, ERR_CANT_OPEN)`；返回。
7. **等一帧再动树**：`await get_tree().process_frame`（`NONE` 过渡也统一走这一步），避免在
   触发调用的信号回调栈内（例如按钮 `pressed` 冒泡途中）直接冻结/移除仍在处理事件的旧场景
   节点。
8. **换场景**：`instantiate()` 新场景 → `get_tree().root.add_child(new_scene)` →
   `get_tree().current_scene = new_scene` → 旧场景 `queue_free()`（非 `free()`，避免立即释放
   触发树内错误）。
9. 若 `transition == FADE`：淡出遮罩（alpha 1→0，`await tween.finished`），`mouse_filter`
   切回 `IGNORE`。
10. 复位 `_is_changing = false`；发 `scene_changed(target_path, new_scene)`。

### Fade overlay 机制

`SceneManager` 是常驻 autoload 节点（不会随场景切换被卸载）。在 `_ready()` 中一次性创建子
节点结构并缓存：`CanvasLayer`（`layer = 4096`，尽量盖过游戏自身 UI）下挂一个铺满全屏的
`ColorRect`（`anchors_preset = PRESET_FULL_RECT`，锚点而非硬编码尺寸，随视口/浏览器 canvas
自适应），初始 `modulate.a = 0`、`mouse_filter = MOUSE_FILTER_IGNORE`。因为挂在
`SceneManager` 节点下而不是当前场景下，第 8 步的场景替换不会波及它，天然跨场景常驻。内部
辅助方法 `_ensure_fade_overlay()` 具备幂等性（已创建且节点仍有效则直接返回），`change_scene`
在真正需要淡入淡出前会防御性地再调用一次，覆盖极端情况下 `_ready()` 尚未跑到的时序。

`ColorRect.color` 的 RGB 分量取自 `options.color`、alpha 固定归一化为 `1.0`，可见度完全由
`modulate:a` 的 Tween 驱动——避免 `color.a` 与 `modulate.a` 两个 alpha 通道相乘导致的"淡入
淡出不到位"的观感问题（这是本设计相对提案原文的一处实现细化，提案本身未展开到这个粒度）。

切换期间把 `mouse_filter` 切到 `STOP`（挡输入穿透，防止过渡途中误触底层 UI），淡出完成后切回
`IGNORE`；无论正常完成还是加载失败中途退出，都保证 `mouse_filter` 被复位。

### 重入保护

`_is_changing` 是唯一的并发状态位。`change_scene()` 入口第一件事就检查它；只有在校验通过、
真正进入切换流程时才置 `true`，在流程的所有退出路径（成功 / 校验失败 / 加载失败）上都会在
发出对应终态信号前复位为 `false`（重入拒绝路径除外——它甚至不会触碰这个标志位，因为它本来
就还是"正在进行中"那一次切换的状态）。不做排队：连续调用只有第一次生效，其余在
`_is_changing` 为真期间的调用一律被拒绝，调用方按钮防抖/切换中禁用输入即可规避。

## Key Design Decisions（已锁定）

| 维度 | 结论 | 理由 |
|---|---|---|
| 变更入口形态 | 单一 `change_scene(target, options)` 内部按类型分派 | 只有统一入口才能挂淡入淡出/信号广播/校验管线；调用方不用关心路径还是 PackedScene |
| 加载策略 | 同步 `load()`，不用线程 | Web 导出下多线程加载依赖 SharedArrayBuffer/跨源隔离头，支持不稳定；同步加载语义与 Godot 内置 `change_scene_to_file` 一致（本身也是先阻塞加载再延迟切换） |
| 过渡效果 | 内建可选 `Transition.FADE`，默认 `NONE` | 淡出淡入是消除场景跳变最基础的诉求，纯 2D 原语（CanvasLayer+ColorRect+Tween）成本低、兼容 Compatibility 渲染器与 Web；默认关闭保证不用它的调用方零视觉副作用、零额外开销 |
| 场景栈 push/pop | **v1 不做，仅 replace（单一当前场景）** | push/pop 隐含多场景共存、z-order、暂停态、输入穿透顺序一整套新语义；常见"暂停菜单覆盖层"诉求本质是 UI 层自己 `add_child`，不必然要 SceneManager 兜底，YAGNI 下不在首版引入 |
| 信号 payload | `scene_changed(scene_path: String, scene: Node)` | 节点名不唯一、依赖场景根节点命名，不适合做稳定判据；路径是唯一稳定标识，附带节点引用省一次 `get_tree().current_scene` 查询 |
| 并发保护 | 拒绝重入（`_is_changing` 守卫 + `scene_change_failed(ERR_BUSY)`），不排队 | 排队要引入队列状态机与"连续切 N 次如何处理"等边界情况，首版没必要；调用方按钮防抖/切换中禁用输入即可规避 |
| Fade 默认值配置面 | 硬编码 `const`（时长/颜色/CanvasLayer layer），仅支持按次调用 `options` 覆盖，v1 不提供全局配置入口（如 `set_default_transition(...)`） | 不同游戏想要不同默认色/时长可以每次传 `options`；全局配置入口属于"目前没有明确刚需就先不加"的 YAGNI 项，真出现多处硬编码同一套非默认参数的调用点时再演进 |
| 可测接缝范围 | `_validate_target` / `_resolve_target_path` / `_merge_options` / `is_changing()` | 与 Log 的 `_should_log`/`format_line` 接缝设计同一思路：把"决策逻辑"和"副作用执行"（真正切场景、Tween、Log 调用）切开，前者可 headless 断言，后者靠 demo 冒烟验证 |

## Web-Export Considerations

- 淡入淡出遮罩全部用 `CanvasLayer` + `ColorRect` + `create_tween()`，均为纯 2D/UI 原语、无
  自定义 shader、无线程，Compatibility 渲染器与 HTML5/Web 导出完全支持。
- **不使用任何线程**（不用 `Thread`、不用 `ResourceLoader.load_threaded_request`）。Godot 的
  Web 导出线程支持依赖浏览器 `SharedArrayBuffer` 与跨源隔离响应头（`COOP`/`COEP`），不是所有
  托管环境都能满足，v1 明确不碰这块。
- 同步 `load()` 会阻塞主线程：Web 导出单线程运行，加载期间会短暂卡住渲染/音频。对典型大小的
  场景可接受；素材很重的场景会有明显卡顿——这是已知且**已接受**的取舍（原提案的 Open
  Question 3，用户拍板：v1 不解决，后续版本如有实际卡顿反馈再评估"仅非 Web 平台启用
  threaded loading"之类的分支方案）。
- `ColorRect` 用锚点铺满（`PRESET_FULL_RECT`）而非读取一次性视口尺寸硬编码，适应浏览器
  canvas 运行时被响应式布局改变尺寸的情况。
- 全程无文件 IO、无 `OS.*` 平台特定调用，与 Log 子系统的 Web 兼容约束一致。

## Testable Seams & Test Plan

沿用 Log 的接缝范式：纯逻辑方法不碰场景树、不调 `Log`，headless 测试直接
`preload("res://addons/godot-core-kit/scene_manager.gd").new()` 实例化后调用，不依赖
autoload 或运行中的场景树（脚本 `.new()` 出来的 `Node` 不 `add_child` 就不会触发
`_ready()`，同 Log 测试惯例——因此淡入淡出遮罩节点不会被创建，也不需要被创建，纯接缝测试
完全不碰它）。**真正动树的协程（`change_scene` 主体、淡入淡出）不在本测试文件的 headless
断言范围内**——它需要一棵运行中的场景树与真实的两个可切换场景，属于冒烟验证范畴，安排在
后续集成步骤里用 demo 工程验证（见"架构与文件"节的范围边界）。

### 纯函数接缝

- `_validate_target(target) -> int`：`target` 是 `PackedScene` 时检查 `can_instantiate()`；
  是 `String` 时检查非空、以 `res://` 开头、以 `.tscn`/`.scn` 结尾（不检查文件是否真实存在，
  存在性检查留给 `change_scene` 运行时的 `ResourceLoader.exists()`）；其余类型一律无效。
- `_resolve_target_path(target) -> String`：`String` 原样返回；`PackedScene` 返回其
  `resource_path`（可能为空字符串）；其余类型返回空字符串。
- `_merge_options(options: Dictionary) -> Dictionary`：`transition` 非 `int` 或超出
  `[Transition.NONE, Transition.FADE]` 范围回退 `NONE`；`duration` 非 `int`/`float` 回退默认值
  `0.3`，数值型统一 `max(0.0, float(...))` 夹到非负；`color` 非 `Color` 类型回退默认黑色。
  返回值始终包含全部三个键 `transition`/`duration`/`color`。
- `is_changing() -> bool`：读 `_is_changing`，新实例（未触发任何切换）默认 `false`。

### `test/test_scene_manager.gd`（headless 断言）

沿用 `extends SceneTree`、`_initialize()` 里跑断言、`quit(0|1)` 的 harness 形态，成功输出
`test_scene_manager: ALL PASS`，任一失败打印详情并 `quit(1)`。断言项（对应实现计划里的具体
代码，共 12 项）：

1. `_validate_target("res://demo/demo.tscn")` → `OK`（仓库里已存在的真实场景资源）。
2. `_validate_target("res://demo/demo.gd")` → 非 `OK`（扩展名不对）。
3. `_validate_target("")` → 非 `OK`（空字符串）。
4. `_validate_target("user://x.tscn")` → 非 `OK`（非 `res://` 开头）。
5. `_validate_target(123)` → 非 `OK`（类型不对）。
6. `_validate_target(preload("res://demo/demo.tscn"))` → `OK`（真实 `PackedScene`）。
7. `_resolve_target_path("res://a.tscn")` == `"res://a.tscn"`。
8. `_resolve_target_path(preload("res://demo/demo.tscn"))` == `"res://demo/demo.tscn"`。
9. `_merge_options({})` → `{transition: NONE, duration: 0.3, color: Color.BLACK}`。
10. `_merge_options({"transition": Transition.FADE, "duration": 1.5})` →
    transition/duration 按传入值，`color` 回退默认。
11. `_merge_options({"duration": -1})` → `duration` 夹到 `0.0`。
12. `_merge_options({"transition": 999})` → 回退 `NONE`。
13. 新实例 `is_changing()` 默认 `false`。

（编号沿用提案顺序并把第 3/4 条从提案中的合并断言拆成独立两条，故总数比提案文字描述的
"约 12 条"多一条，均为独立 `if` 断言，逐条计入 `failures` 计数。）

## 版本

SceneManager v0.3.0：新增 `SceneManager` autoload 单例（本文档范围内先实现脚本本体与纯
接缝测试）。`change_scene(target, options)` 统一入口、`Transition.NONE|FADE` 两种过渡、
`scene_changing`/`scene_changed`/`scene_change_failed` 三个生命周期信号、拒绝重入。autoload
注册、版本号在 `plugin.cfg`/`core_kit.gd`/`README.md` 的升级、demo 场景新增第二占位场景与
冒烟验证，是紧随其后的独立集成步骤，不在本文档与配套实现计划范围内。
