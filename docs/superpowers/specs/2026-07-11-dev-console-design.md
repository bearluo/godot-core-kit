# DevConsole(运行时调试控制台)设计 — godot-core-kit v0.9.0

> 日期:2026-07-11 ｜ 阶段:Phase 4「补缺库」子项 1/4(调试控制台,对标 PankuConsole)。
> 前置:阶段2 借鉴纳入已收官(KitContext v0.6 / SaveManager v0.7 / KitStateMachine v0.8)。
> 定位:core-kit 首个**面向前端的 UI 子系统**;纯 GDScript、可 Web 导出、TDD、向后兼容。

---

## 0. 目标 & 非目标

**目标(v1 完整四件套)**:
1. **日志 overlay** —— 运行时把 `CoreKit.log` 的输出实时显示在屏上覆盖层,开启时可见历史 + 后续实时行。
2. **命令 / 作弊注册** —— 游戏代码 `register_command(name, callable, desc)` 注册命名命令(作弊、跳关等),控制台输入行调用。
3. **表达式执行** —— 输入任意 GDScript 表达式,基于 `Expression` 求值,可读写运行时状态(绑定上下文对象)。
4. **变量 watch** —— 登记表达式,控制台可见时每帧(节流)求值并显示 `expr = 值`。

**非目标(明确 YAGNI,留待后续)**:
- 无远程/网络调试、无面板停靠拖拽、无多标签页、无图表/曲线可视化。
- 无自定义主题系统(用引擎默认 Control 主题即可)。
- 无命令自动补全(up/down 历史回溯是唯一 UX 糖;补全留 v2)。
- watch 不做「每帧」硬求值,固定节流 ~10Hz。

---

## 1. 架构 / 接入

- 新子系统 `CoreKit.console`,脚本 `addons/godot-core-kit/console/dev_console.gd`,**`extends CanvasLayer`**(`layer = 128` 保证覆盖最上层;`process_mode = Node.PROCESS_MODE_ALWAYS`,游戏暂停也可用)。
- 在 `core_kit.gd` `_init()` 里作**第 11 个子系统**构造(`ConsoleScript.new()` → `name = "DevConsole"` → `add_child`),强类型属性 `var console: ConsoleScript`,`const ConsoleScript := preload("res://addons/godot-core-kit/console/dev_console.gd")`。
- `RESERVED_KEYS` 增补 `"console"`(→ 共 11 键);`core_kit.gd` `_ready()` 里 `_services["console"] = console` 预注册。
- **跨子系统接线**:`core_kit.gd` `_ready()` 新增一行 `console.bind_core(self)` —— 把 CoreKit 门面注入控制台(设为 `Expression` 求值 base + 连接 `log.line_logged` 信号 + 灌入既有 `log.history()`)。与现有 `input.bind_settings(settings)` / `res.bind_ticker(ticker)` 同款显式接线,不用 `get_parent()`。

### 门控(release 零开销)
- `_ready()` 里 `_enabled = OS.is_debug_build()`。
- 门控只关 **UI 构建 / `~` 输入捕获 / 每帧 watch tick / log 信号接线**。「激活」动作统一走内部 `_activate()`:构建 UI(若未建)+ `set_process(true)` + `set_process_input(true)` + 连 `_core.log.line_logged`(若 `_core` 已注入且未连)+ 灌入 `_core.log.history()`。「停用」走 `_deactivate()`:`close()` + `set_process(false)` + `set_process_input(false)` + 断开 log 信号(若已连)。
  - `_ready`:`_enabled` 真 → `_activate()`(此刻 `_core` 尚未注入,故只建 UI + 开 process,log 接线延后);假 → `set_process(false)` + `set_process_input(false)`,不建 UI。
  - `bind_core(core)`:`_core = core`;`_evaluator.set_base(core)`(始终,廉价);`_enabled` 真才连 log 信号 + 灌历史(即 `_activate` 的 log 接线部分),假则**完全不连**——发行版字面零开销。
  - `force_enable()`:已启用则返回;`_enabled = true` → `_activate()`(含 log 接线,若 `_core` 已有)。
  - `set_enabled(v)`:`v` 真等价 `force_enable()`;`v` 假 → `_deactivate()` + `_enabled = false`。
- **命令 / 求值 / watch 三个纯逻辑单元始终在线**(即便未启用),故 `execute()`、`register_command()`、`watch()`、`bind_context()` 永远可调用 —— 这是 headless 可测的关键;停用只关 UI/输入/watch tick/log 接线,不触碰逻辑层。
- headless 测试(`godot --headless -s ...`)跑 debug 模板,`OS.is_debug_build()` 为真,天然启用。

---

## 2. 组件与文件结构(拆分为可独立 headless 测的单元)

```
addons/godot-core-kit/console/
  dev_console.gd               # CanvasLayer:代码建 UI + ~ 切换 + 编排 + 全部公共 API
  console_command_registry.gd  # 纯逻辑 RefCounted:命令表
  console_evaluator.gd         # 纯逻辑 RefCounted:包 GDScript Expression
  console_watch_list.gd        # 纯逻辑 RefCounted:watch 表
addons/godot-core-kit/core/log.gd   # 增补 line_logged 信号 + 有界环形缓冲(向后兼容)
addons/godot-core-kit/core_kit.gd   # 第 11 子系统 + RESERVED_KEYS + _services + bind_core
```

设计原则:UI/输入/暂停等**难 headless 测**的部分尽量薄,集中在 `dev_console.gd` 编排层;命令派发、表达式求值、watch 求值三块**纯逻辑**下沉到 RefCounted 单元,各自单测。`dev_console.execute(text) -> String` 作为不依赖渲染的程序化提交入口,把编排层也拉进可测范围。

---

## 3. `console_command_registry.gd`(extends RefCounted)

命令契约:命令 callable 签名固定为 `func(args: PackedStringArray) -> Variant`(单参 = 其余 token 数组;返回值由控制台 `str()` 回显)。

```gdscript
var _commands: Dictionary = {}   # name(String) -> {callable: Callable, description: String}

## 登记命令。name 为空 → push_warning 忽略;callable 无效 → push_warning 忽略;
## 同名重复 → push_warning 覆盖。
func register(name: String, callable: Callable, description: String = "") -> void

func unregister(name: String) -> void

func has(name: String) -> bool

## 已注册命令名,升序。
func names() -> PackedStringArray

func description_of(name: String) -> String   # 未注册 → ""

## 派发:前置条件 has(name)。以单参形式调用 callable.call(args) 并返回其返回值;
## 未注册 → push_warning + 返回 null。
func dispatch(name: String, args: PackedStringArray) -> Variant
```

---

## 4. `console_evaluator.gd`(extends RefCounted)

包 `Expression`,把 parse/execute 错误全折成 result 字典,永不抛到 UI。

```gdscript
var _base: Object = null          # 求值 base instance(= CoreKit 门面),裸标识符对它解析
var _contexts: Dictionary = {}    # name(String) -> object(作为 Expression input 变量注入)

func set_base(base: Object) -> void

func bind_context(name: String, object) -> void     # name 为空 → push_warning 忽略
func unbind_context(name: String) -> void

## 求值。返回 {ok: bool, value: Variant, error: String}。
##   parse 失败 → {false, null, expr.get_error_text()}
##   execute 失败(has_execute_failed) → {false, null, expr.get_error_text()}
##   否则 → {true, <结果>, ""}
func evaluate(text: String) -> Dictionary
```

实现要点:
```gdscript
func evaluate(text: String) -> Dictionary:
    var expr := Expression.new()
    var names := PackedStringArray(_contexts.keys())
    var err := expr.parse(text, names)
    if err != OK:
        return {"ok": false, "value": null, "error": expr.get_error_text()}
    var inputs: Array = []
    for n in names:               # 与 names 同序(Dictionary 保插入序)
        inputs.append(_contexts[n])
    var result = expr.execute(inputs, _base, false)   # show_error=false,避免重复灌编辑器错误面板
    if expr.has_execute_failed():
        return {"ok": false, "value": null, "error": expr.get_error_text()}
    return {"ok": true, "value": result, "error": ""}
```
`_base = CoreKit` 门面后,裸引用可达门面成员:`saves`、`audio`、`VERSION`、`service("x")` 等;`bind_context("player", node)` 后 `player.health = 100` 可用。

---

## 5. `console_watch_list.gd`(extends RefCounted)

```gdscript
var _exprs: Array[String] = []    # 去重、保序

func add(expr: String) -> void        # 空串忽略;已存在忽略(去重)
func remove(expr: String) -> void
func entries() -> Array[String]       # 副本
func clear() -> void

## 用传入的 evaluator 逐条求值。返回 [{expr, ok, value, error}, ...]。
func evaluate_all(evaluator) -> Array
```

---

## 6. `core/log.gd` 增补(向后兼容,不改既有打印/push 行为)

```gdscript
signal line_logged(level: int, text: String)   # level 为 Level 枚举整数,text 为已格式化整行

const HISTORY_MAX := 256
var _history: Array[String] = []

## 只读历史副本(供控制台开启时灌入积压)。
func history() -> Array[String]        # 返回 _history.duplicate()
func clear_history() -> void
```

在既有 `_log(level, message)` 内,**通过 `_should_log(level)` 后**(即与实际打印一致的门槛)追加:
```gdscript
# format_line 得到 line 之后、print_rich 之前或之后均可,顺序不敏感:
if _history.size() >= HISTORY_MAX:
    _history.pop_front()
_history.append(line)
line_logged.emit(level, line)
```
即:环形缓冲上限 `HISTORY_MAX`,超出丢最旧;每条已打印行同时广播 `line_logged`。既有测试(`test/test_log.gd` 若有)行为不变。

---

## 7. `dev_console.gd`(extends CanvasLayer)—— 编排 + UI + 公共 API

### 7.1 常量 / 成员
```gdscript
const TOGGLE_KEY_DEFAULT := KEY_QUOTELEFT   # ` / ~ 键
const WATCH_INTERVAL := 0.1                 # watch 节流秒数(~10Hz)
const INPUT_HISTORY_MAX := 64

var _registry                # ConsoleCommandRegistry
var _evaluator               # ConsoleEvaluator
var _watch                   # ConsoleWatchList
var _enabled: bool = false
var _toggle_key: int = TOGGLE_KEY_DEFAULT
var _pause_on_open: bool = false
var _ui_built: bool = false
var _watch_accum: float = 0.0
var _input_history: Array[String] = []
var _history_index: int = 0
# UI 节点(建后持有):_root:Control, _output:RichTextLabel, _input:LineEdit, _watch_label:RichTextLabel
```

### 7.2 生命周期
- `_init()` / `_ready()`:`new()` 三个逻辑单元;`_enabled = OS.is_debug_build()`;启用 → `_activate()`(此刻 `_core` 尚 null,只建 UI + 开 process);未启用 → `set_process(false)` + `set_process_input(false)`,不建 UI。
- `bind_core(core)`:`_core = core`;`_evaluator.set_base(core)`(始终);若 `_enabled` 则 `_connect_log_feed()`(连 `core.log.line_logged` → `_on_log_line`,去重防双连;`for line in core.log.history(): _append_output(line)` 灌积压)。
- `_activate()`:`if not _ui_built: _build_ui()`;`set_process(true)`;`set_process_input(true)`;若 `_core != null` 则 `_connect_log_feed()`。
- `_deactivate()`:`close()`;`set_process(false)`;`set_process_input(false)`;`_disconnect_log_feed()`(若已连)。
- `_build_ui()`:代码建 `Control`(full rect,`mouse_filter` 合理)→ 子 `RichTextLabel _output`(bbcode on、`scroll_following=true`,约上 60%)+ `LineEdit _input`(底部,`text_submitted` 连 `_on_submit`)+ `RichTextLabel _watch_label`(右上角);默认隐藏 `_root.visible = false`;`_ui_built = true`。
- `_append_output(text)`:`if not _ui_built: return`,否则按 bbcode 追加到 `_output`。`_on_log_line(level, text)` → 按 level 上色后 `_append_output`。

### 7.3 提交流程
```gdscript
## 程序化提交:回显 "> text",执行,返回输出串(UI 未建也可用 —— headless 命门)。
func execute(text: String) -> String:
    var out := _run(text)
    if _ui_built:
        _append_output("> " + text)
        if out != "":
            _append_output(out)
    return out

# 内部:纯逻辑,产出输出串,不碰 UI
func _run(text: String) -> String:
    var trimmed := text.strip_edges()
    if trimmed == "":
        return ""
    var parts := trimmed.split(" ", false)   # 折叠空白
    var head := String(parts[0])
    if _registry.has(head):
        var args := PackedStringArray(parts.slice(1))
        var r = _registry.dispatch(head, args)
        return "" if r == null else str(r)    # 命令返回 null → 静默
    var res := _evaluator.evaluate(trimmed)
    return str(res["value"]) if res["ok"] else "ERROR: " + String(res["error"])
```
未命中命令则整行走表达式求值(故 `2 + 2` 不会被误判为「未知命令 2」)。错误统一 `"ERROR: <text>"` 前缀。

### 7.4 输入 / 切换
- `_input(event)`:`event is InputEventKey && event.pressed && event.keycode == _toggle_key` → `toggle()` + `accept_event()`(开/关都能触发)。
- `_on_submit(text)`(LineEdit `text_submitted`):`execute(text)`;push 进 `_input_history`(上限 `INPUT_HISTORY_MAX`);清空 `_input`;重置 `_history_index`。
- LineEdit up/down:回溯 `_input_history`(仅 UI 层,不进逻辑单元)。

### 7.5 显隐
```gdscript
func toggle() -> void          # 未启用 → no-op
func open() -> void            # 未启用/未建 UI → no-op;_root.visible=true;_input.grab_focus();若 _pause_on_open 则 get_tree().paused=true
func close() -> void           # _root.visible=false;若之前暂停则恢复
func is_open() -> bool         # _ui_built && _root.visible
```

### 7.6 每帧 watch
```gdscript
func _process(delta: float) -> void:
    if not _enabled or not is_open():
        return
    _watch_accum += delta
    if _watch_accum < WATCH_INTERVAL:
        return
    _watch_accum = 0.0
    _refresh_watch()   # _watch.evaluate_all(_evaluator) → 渲染 _watch_label:"expr = 值"(错误行标红)
```

### 7.7 公共 API 汇总(`CoreKit.console`)
```
register_command(name, callable, description := "") -> void
unregister_command(name) -> void
execute(text) -> String            # 程序化提交(测试/脚本命门)
bind_context(name, object) -> void
unbind_context(name) -> void
watch(expr) -> void
unwatch(expr) -> void
toggle() / open() / close() / is_open() -> bool
set_enabled(v) / is_enabled() -> bool / force_enable()
set_toggle_key(keycode) -> void
bind_core(core) -> void            # 由 CoreKit._ready 调用
```
`register_command/unregister_command/bind_context/unbind_context/watch/unwatch` 直接委托对应逻辑单元。

---

## 8. 数据流

```
Log._log ──(_should_log 通过)──> 追加环形缓冲 + emit line_logged(level, line)
                                        └─> DevConsole._on_log_line ─> _append_output(bbcode 上色)
LineEdit.text_submitted ─> execute(text) ─> _run ─> registry.has? dispatch : evaluator.evaluate ─> 输出
_process(启用且可见, 节流) ─> watch.evaluate_all(evaluator) ─> 渲染 watch 面板
_input(~ 键) ─> toggle()
```

---

## 9. 错误处理

- **求值**:parse/execute 错误折成 `{ok=false, error}`,UI 显示 `ERROR: <text>`,不抛、不崩。
- **命令**:未命中 → 落表达式求值(非「未知命令」硬报错);`register` 空名/无效 callable → push_warning 忽略;`dispatch` 前置 `has`。命令 callable 自身运行期错误由 Godot 常规报错(文档提示命令实现应自保)。
- **watch**:某条表达式求值出错 → 该行显示错误、标红,不影响其它行、不停 tick。
- **Log 缓冲**:上限 `HISTORY_MAX` 环形,永不无界增长。
- **门控**:release/未启用下 UI 未建,`open/toggle` no-op、`_process`/`_input` 已 `set_process(false)` 关闭 → 零开销、不误触发。

---

## 10. 测试计划(headless,套现有 `test/test_*.gd` + `test/run_all.ps1` marker;断言 ASCII)

新 `test/test_dev_console.gd`,覆盖:

**命令注册(直接测 RefCounted 单元)**
- `register` + `has` + `names()` 升序;`dispatch("cmd", ["a","b"])` 收到 `PackedStringArray(["a","b"])` 并返回其返回值;`unregister` 后 `has` 假;同名重复 → 覆盖(可选断言 description 更新)。

**表达式求值(直接测单元)**
- `evaluate("1 + 2")` → `{ok=true, value=3}`;
- `set_base(obj)` 后裸引用 obj 成员可解析;`bind_context("p", obj)` 后 `evaluate("p.hp")` 得值;
- parse 错误(如 `1 +`)→ `ok=false` 且 `error` 非空;execute 错误(如 `no_such.member`)→ `ok=false`。

**watch(直接测单元)**
- `add` 去重(加两次同串 → `entries()` 一条);`remove`;`evaluate_all(evaluator)` 返回逐条 `{expr, ok, value/error}`,含一条错误项验证不中断。

**Log 增补**
- `CoreKit.log`(或新 Log 实例)`info("x")` 后 `history()` 含该行;`line_logged` 被触发(连信号收计数);push `HISTORY_MAX + N` 条后 `history().size() == HISTORY_MAX`(截断最旧)。

**编排层 / 门控(经 console 实例 + execute)**
- 实例化 `dev_console.gd` → `add_child` → `await process_frame` → `bind_core(<最小 base>)`;
- `execute("1 + 2")` → `"3"`;注册命令 `god` 返回 `"godmode on"` → `execute("god")` → `"godmode on"`;错误表达式 → 返回以 `"ERROR:"` 开头;
- 门控:`set_enabled(false)` 后 `is_open()` 假、`toggle()` 后仍 `is_open()` 假,而 `execute("1+1")` 仍返回 `"2"`(逻辑层不受门控影响)。

**UI 冒烟**
- 启用实例 `open()` → `is_open()` 真、`_root.visible` 真;`close()` → 假。(headless 无渲染,只验节点状态翻转。)

`test/run_all.ps1` 增补 ASCII marker(demo 里控制台演示打印的固定串,如 `console.execute(1+2)=3`、`cheat god fired`),并确认 stderr 干净。

---

## 11. 收尾件 & 版本

- `core_kit.gd`:`const VERSION := "0.9.0"`(由 0.8.0 升);第 11 子系统构造 + `RESERVED_KEYS` + `_services` + `bind_core`。
- `plugin.cfg`:`version="0.9.0"` + description 追加 0.9.0 说明(DevConsole)。
- `test/test_core_kit.gd`:版本断言改 `"0.9.0"`;可加 `CoreKit.console != null` 与 `RESERVED_KEYS` 含 `"console"` 断言。
- 新 `addons/godot-core-kit/docs/console.md`:API + 用法 + 门控/安全约定(dev-only、求值执行任意 GDScript 的风险)+ 注意事项。
- `addons/godot-core-kit/docs/architecture.md` / `README.md`:版本 0.9.0 + 子系统清单加 DevConsole。
- `demo/demo.gd`:注册一个作弊命令、`bind_context` 一个对象、`watch` 一个表达式、`execute` 几行并打印 ASCII marker;不要求可视,只跑通逻辑路径。

---

## 12. 全局约束(Global Constraints,供 writing-plans 逐字沿用)

- **版本**:三处一致 `0.9.0`(`core_kit.gd VERSION` / `plugin.cfg version` / `test_core_kit` 断言)。
- **向后兼容**:`core/log.gd` 只增不改,既有打印/push_warning/push_error/format_line 行为与签名不变。
- **纯 GDScript、零重依赖、可 Web 导出**:不引入 .tscn、不引入 C#、不做文件 IO(控制台不落盘)。
- **门控**:发行版默认整体 no-op、零开销(`set_process(false)`+`set_process_input(false)`+不建 UI+**不连 `log.line_logged` 信号**);逻辑层(命令/求值/watch)始终可调用。
- **命令契约**:命令 callable 恒为 `func(args: PackedStringArray) -> Variant`。
- **求值错误**:evaluator 永不抛异常到 UI,一律折成 `{ok, value, error}`。
- **TDD**:每单元先写失败测试;全绿判据 = `test/run_all.ps1` 末行 `=== SUMMARY FAILS=0 ===` 且 stderr 干净。
- **marker 用 ASCII**:PowerShell 5.1 误读非 BOM UTF-8 中文,`run_all.ps1` 断言串保持 ASCII。
- **Godot 运行**:仅经 PowerShell 前台跑,不后台化。
