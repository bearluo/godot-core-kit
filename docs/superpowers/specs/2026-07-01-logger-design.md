# godot-core-kit Logger 子系统设计

- 日期：2026-07-01
- 状态：已确认，待写实现计划
- 前置：`2026-07-01-godot-core-kit-scaffold-design.md`（脚手架），本子系统替换脚手架里 `core_kit.gd` 的 `info()` 占位

## 目标与定位

为 godot-core-kit 提供正式的日志子系统，替换脚手架阶段 `CoreKit.info()` 那个只会 `print("[CoreKit] ...")` 的占位。首版范围严格限定为**分级 + 格式化**，YAGNI；文件落盘、按分类设级、多输出目标等留待后续版本。

## 关键决定

| 维度 | 结论 | 理由 |
|---|---|---|
| 首版范围 | 分级 + 格式化 + 全局阈值过滤 + 彩色输出 | YAGNI；文件落盘/分类过滤后续再做 |
| API 形态 | 独立全局 autoload `Log` | 最短最顺手，Godot 社区惯例；`Log.info("msg")` |
| 内部结构 | 单文件 autoload（方案 A） | 精确匹配首版范围；加 sink 时再演进，避免只有一种实现时的空抽象 |
| 级别 | `enum Level { DEBUG, INFO, WARN, ERROR }`（有序） | 用序值做阈值比较 |
| 默认阈值 | `Level.DEBUG`（全打），运行时 `set_level()` 可改 | 不分 build，由游戏项目自行收紧 |
| 日志格式 | `[HH:MM:SS.mmm][LEVEL] message` | 零开销、Web 兼容；不自动拓栈 |
| 来源定位 | 不做（不 `get_stack()`） | `get_stack()` 在 release 返回空且每条有开销 |
| 调试器集成 | `WARN`→`push_warning`、`ERROR`→`push_error`（额外） | 进编辑器"错误"面板、红黄高亮、带调用栈，Godot 惯例 |
| 彩色输出 | `print_rich` BBCode | 编辑器面板渲染颜色，终端/Web 优雅降级 |
| 测试 | 轻量 headless 断言脚本 | 不引入 GUT 等第三方框架（YAGNI） |

### 被否决的选项（存档）

- **挂在 CoreKit 下**（`CoreKit.log.info()`）：调用更长；独立 `Log` 更顺手。
- **可实例化 `Logger` 类 + `Log` 单例**：首版不做 per-category 实例，过度设计。
- **门面 + Sink 抽象**（方案 B）：首版只有 console 一种 sink，抽象无法被第二种实现验证，违背首版 YAGNI；将来加文件落盘时再从方案 A 平滑演进。
- **按 build 自动切阈值 / 从 project settings 读**：首版固定默认 `DEBUG` 更简单，够用。
- **自动来源定位（`get_stack()`）**：release 失效 + 每条开销。

## 架构与文件

```
addons/godot-core-kit/
├── core_kit.gd      # 修改：移除 info() 占位；_ready() 改调 Log.info(...)
├── log.gd           # 新增：Log autoload 单例（extends Node）
└── plugin.gd        # 修改：先注册 Log，再注册 CoreKit（均幂等）
project.godot        # 修改：autoload 段 Log 声明在 CoreKit 之前
demo/demo.gd         # 修改：CoreKit.info(...) 改为 Log.info(...)
test/test_log.gd     # 新增：headless 断言脚本
```

随功能一并把版本从 `0.1.0` 升到 `0.2.0`（`plugin.cfg` 的 `version`、`core_kit.gd` 的 `VERSION`、`README.md` 版本段），保持语义化版本一致——加子系统属 minor 升级。

### autoload 顺序（关键）

autoload 按 `project.godot` 声明顺序初始化。`CoreKit._ready()` 会调用 `Log.info(...)`，故 **`Log` 必须先于 `CoreKit` 就绪**。因此：

- `project.godot` 的 `[autoload]` 段 `Log` 在 `CoreKit` 之前。
- `plugin.gd._enter_tree()` 里**先** `add_autoload_singleton("Log", ...)`、**后** `add_autoload_singleton("CoreKit", ...)`。
- 分层关系：`Log` 最底层、零依赖；`CoreKit` 依赖 `Log`。

### `Log` 命名坑（需实机验证）

GDScript 有内置 `@GlobalScope` 数学函数 `log()`（自然对数）。标识符大小写敏感，autoload 名 `Log`（大写）与 `log()`（小写）不冲突。实现阶段用 Godot 4.7 headless 实机验证 `Log` autoload 可正常解析、无遮蔽/报错，以防万一。

## 公开 API

```gdscript
extends Node
## Log —— godot-core-kit 全局日志单例。

enum Level { DEBUG, INFO, WARN, ERROR }

func debug(message) -> void
func info(message) -> void
func warn(message) -> void
func error(message) -> void

func set_level(level: Level) -> void   # 运行时调阈值
func get_level() -> Level
```

- `message` 为任意类型，内部 `str(message)` 转换（与 `print` 一致），故 `Log.info(some_object)`、`Log.info("x=%d" % x)` 均可。
- 默认阈值 `Level.DEBUG`（成员 `_level`）。

## 行为与数据流

### 阈值过滤

每个日志方法首行 `if not _should_log(level): return`。`_should_log(level) -> bool` 即 `return level >= _level`。低于阈值只花一次整数比较，基本零开销。

### 格式化

`format_line(level, message) -> String` 返回 `[HH:MM:SS.mmm][LEVEL] <str(message)>`：

- `HH:MM:SS` 取自 `Time.get_time_string_from_system()`（本地时间）。
- `mmm` 毫秒取自 `Time.get_unix_time_from_system()` 的小数部分：`int(fmod(unix, 1.0) * 1000.0)`，零填充 3 位。时区只差整/半小时，不影响秒内毫秒对齐。
- `LEVEL` 为 `DEBUG`/`INFO`/`WARN`/`ERROR`。

### 输出目标

每条通过阈值的日志：

| 级别 | 输出面板（`print_rich`，stdout） | 调试器"错误"面板 |
|---|---|---|
| DEBUG | 灰色 | — |
| INFO | 默认色 | — |
| WARN | 黄色 | 额外 `push_warning(纯文本行)` |
| ERROR | 红色 | 额外 `push_error(纯文本行)` |

- 所有级别都 `print_rich` 一条统一格式的彩色行到输出面板。
- `WARN`/`ERROR` **额外**再 `push_warning`/`push_error`，从而也进调试器"错误"标签页并带调用栈。
- **有意的轻微重复**：`WARN`/`ERROR` 会在"输出"面板（彩色行）与"错误"面板/stderr（`push_*` 那条）各出现一次——两个不同面板，是特性不是 bug。
- 颜色通过 BBCode（如 `[color=gray]...[/color]`）；`push_*` 传入的是**不含 BBCode** 的纯文本行。

### 优雅降级与 Web 兼容

- `print_rich` 的 BBCode 颜色：编辑器面板渲染；外部终端转 ANSI 或去标记；Web 导出到浏览器 console 去标记。文字内容始终完整。
- 全程无文件 IO；`print_rich`/`push_error`/`push_warning`/`Time.*` 均支持 Web 导出。

## 测试与验证

### 可测接缝

将两处纯逻辑抽成不打印、可断言的方法，供公开 API 内部复用：

- `_should_log(level: Level) -> bool`
- `format_line(level: Level, message) -> String`

### `test/test_log.gd`（headless 断言）

**不依赖 autoload**：测试直接实例化脚本（`const LogScript := preload("res://addons/godot-core-kit/log.gd")`，`var log := LogScript.new()`），对实例调用 `_should_log`/`format_line`/`set_level`。纯方法测试无需 `Log` 全局就绪，避免自定义主循环下 autoload 是否加载的不确定性。（GDScript 无真正私有，跨脚本调 `_` 前缀方法可行。）

harness 形态：`test_log.gd` `extends SceneTree`，在 `_initialize()` 里跑断言，结束时 `quit(exit_code)`；以 `godot --headless -s res://test/test_log.gd` 运行。

断言：

1. `format_line(Level.INFO, "hello")` 结构匹配正则 `^\[\d\d:\d\d:\d\d\.\d\d\d\]\[INFO\] hello$`（校验时间戳、级别、消息）。
2. `set_level(Level.WARN)` 后：`_should_log(DEBUG)`、`_should_log(INFO)` 为 `false`；`_should_log(WARN)`、`_should_log(ERROR)` 为 `true`。
3. 默认阈值（`DEBUG`）下 `_should_log(DEBUG)` 为 `true`。

任一断言失败 → 打印失败详情并 `quit(1)`；全部通过 `quit(0)`。

### 冒烟

headless 跑一遍：默认阈值下四个级别各打一条，再 `set_level(Level.WARN)` 后重打，肉眼确认彩色行与 `push_error`/`push_warning` 入面板、`DEBUG`/`INFO` 被过滤，退出码 0。

### 验证工具

本机 Godot 4.7：
`D:\Program Files\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe`

1. `--headless --import` 导入工程。
2. `--headless -s test/test_log.gd`（或作为主场景/脚本运行）跑断言，检查退出码。
3. `--headless res://demo/demo.tscn --quit-after N` 跑冒烟，确认 `Log` 接线正常、无报错。

## 版本

Logger v0.2.0 起：`Log` 全局单例，四级分级、统一格式、阈值过滤、彩色输出、`push_error`/`push_warning` 集成。后续版本再加文件落盘、按分类设级、多 sink 等。
