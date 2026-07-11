# DevConsole 调试控制台(`CoreKit.console`)

> 版本 0.9.0 新增。core-kit 首个面向前端的 UI 子系统。纯 GDScript、可 Web 导出。

## 职责

运行时调试控制台(对标 PankuConsole 核心),四件套:

1. **日志 overlay** —— 实时显示 `CoreKit.log` 输出(开启时先灌历史、后续实时追加)。
2. **命令 / 作弊注册** —— 游戏代码注册命名命令,控制台输入行调用。
3. **表达式执行** —— 输入任意 GDScript 表达式,基于 `Expression` 求值,可读写运行时状态。
4. **变量 watch** —— 登记表达式,控制台可见时每帧(节流 ~10Hz)求值并显示。

## 门控与安全

- 默认仅 `OS.is_debug_build()` 下启用。发行版整体 no-op、零开销(不建 UI、不连日志信号、`set_process(false)`)。
- `force_enable()` / `set_enabled(true)` 可在发行版强开(自负其责)。
- **安全**:表达式执行会运行**任意 GDScript**。这是开发调试工具,勿在不可信输入或发行版随意开放;绑定的上下文对象会被暴露给求值。

## 公开 API

| 方法 | 说明 |
|---|---|
| `register_command(name, callable, description := "")` | 注册命令。callable 契约:`func(args: PackedStringArray) -> Variant`,返回值 `str()` 回显 |
| `unregister_command(name)` | 注销命令 |
| `execute(text) -> String` | 程序化提交一行,返回输出串(命中命令则派发,否则整行走表达式求值);UI 未建也可用 |
| `bind_context(name, object)` | 绑定求值上下文对象,之后 `name.member` 可在表达式里访问 |
| `unbind_context(name)` | 解绑 |
| `watch(expr)` / `unwatch(expr)` | 增删 watch 表达式(去重) |
| `toggle()` / `open()` / `close()` / `is_open()` | 显隐控制(未启用为 no-op) |
| `set_enabled(v)` / `is_enabled()` / `force_enable()` | 门控开关 |
| `set_toggle_key(keycode)` | 改切换键(默认 `KEY_QUOTELEFT` / ~) |
| `set_pause_on_open(v)` | 开启时是否暂停 `get_tree()`(默认 false,便于运行中实时 watch/作弊) |

## 依赖

- 由 `CoreKit._ready` 调 `console.bind_core(self)` 注入门面:设为表达式求值 base(裸标识符可达门面成员,如 `audio`、`saves`、`VERSION`)+ 订阅 `CoreKit.log.line_logged` 喂 overlay。
- 内部逻辑拆三个纯逻辑单元:`console_command_registry.gd` / `console_evaluator.gd` / `console_watch_list.gd`。

## 用法示例

```gdscript
# 注册作弊命令(args 是空格分隔的其余 token)
CoreKit.console.register_command("god", func(args): 
	player.invincible = true
	return "godmode on")

CoreKit.console.register_command("give", func(args):
	var n := int(args[1]) if args.size() > 1 else 1
	inventory.add(args[0], n)
	return "gave %d %s" % [n, args[0]])

# 绑定上下文 + watch
CoreKit.console.bind_context("player", $Player)
CoreKit.console.watch("player.hp")
CoreKit.console.watch("Engine.get_frames_per_second()")

# 程序化执行(也可玩家在控制台输入行手打)
CoreKit.console.execute("player.hp = 999")   # 表达式:直接改状态
CoreKit.console.execute("give sword 3")       # 命令:派发
```

按 `~`(反引号)开合控制台;输入行支持 up/down 历史回溯。

## 注意事项

- **命令 vs 表达式**:输入行首 token 命中已注册命令则按命令派发(其余 token 作 `PackedStringArray`),否则整行按 GDScript 表达式求值。故 `2 + 2` 不会被误判为「未知命令 2」。
- **求值错误**不崩:parse/execute 失败以 `ERROR: <text>` 回显。
- **日志 overlay** 仅镜像经阈值放行(实际打印)的行;`CoreKit.log.set_level(WARN)` 后 DEBUG/INFO 既不打印也不进 overlay。
- **watch 开销**:仅在启用且可见时按 `WATCH_INTERVAL`(0.1s)节流求值,隐藏/禁用零开销。
- **UI 全代码建**,无 `.tscn` 依赖;`layer = 128` 覆盖最上层,`process_mode = ALWAYS` 暂停也可用。
