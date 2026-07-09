---
name: developing-core-kit
description: Use when adding a new subsystem to the godot-core-kit plugin or modifying an existing one — wiring a subsystem into the CoreKit facade, writing its headless test, keeping the version/docs/runner in sync, or extending subsystem behavior in a repo containing addons/godot-core-kit/.
---

# 开发 core-kit

如何在 **godot-core-kit** 这个 Godot 4 GDScript 插件(`addons/godot-core-kit/`)里新增或修改一个子系统。先读 `addons/godot-core-kit/docs/architecture.md`——它是门面、布局、规则的权威来源;本 skill 是操作流程。

> 仓库里可能还有 `addons/godot_ai/`——那是无关的 MCP 编辑器插件。本 skill 只关于 `addons/godot-core-kit/`。

## 写代码前:先锁定设计

先定下:公开 API(signal + 方法)、是否依赖其它子系统、门面属性名(用完整词如 `settings`/`audio`,不用缩写)、节点名(PascalCase)。凡非 trivial 的改动,走 superpowers 流程(brainstorming → writing-plans → subagent-driven-development);设计文档落 `docs/superpowers/specs/`。

## 文件放哪

- `core/` —— 根基设施,零依赖(`log`、`event_bus`、`settings`)。`systems/` 可依赖 `core/`,反之绝不可。
- `systems/` —— 面向玩法的业务子系统(其余全部)。新子系统几乎都放这。
- `state_machine/` / `di/` —— off-facade `class_name` 类库(`KitStateMachine`、`KitContext`),游戏代码直接 `new`/挂节点,不挂门面、不被 core/systems 依赖。新增"游戏侧直接用的可复用类"放这。
- `extends Node`,**不加 `class_name`**(子系统只经 `CoreKit.<prop>` 访问;仅 `state_machine/` 用 `class_name`)。用 **Tab** 缩进。开头写一段 `##` 头部 docstring,风格照 `systems/resource_manager.gd`。

## 依赖纪律(硬规则)

子系统之间**不得** `preload` 或按名硬引用彼此。合法的跨子系统通道只有两条:

1. **`bind_*(dep)` 注入**,只在 `core_kit.gd:_ready()` 里调用。引用存为无类型的 `_dep = null`,并守卫未绑定路径(`if _dep == null: return`)。
2. 全局 **`CoreKit.log`** 链。

初始化期诊断(`_init`/`_ready`,此时接线未必就绪)用引擎原生 `push_warning`/`push_error`;运行期用 `CoreKit.log.*`。

## 接进门面 —— `core_kit.gd`(4 处增量编辑,按序)

构造顺序 = 子节点顺序 = `_ready` 触发顺序。在当前最后一个子系统之后追加:

1. `const XScript := preload("res://addons/godot-core-kit/systems/x.gd")`
2. `var x: XScript`
3. 在 `_init()` 里:`x = XScript.new(); x.name = "X"; add_child(x)`
4. 若需依赖:在 `_ready()` 里、在末尾那行 `log.info(...)` "ready" 横幅之前加 `x.bind_settings(settings)`——这是唯一可做跨子系统接线的地方。

## 测试 —— `test/test_x.gd`

- `extends SceneTree`;在 `_initialize()` 里用**运行时 `load(...)`,不要顶层 `const preload`**。血泪坑:`-s` 脚本的顶层 preload 在 autoload 注册**之前**编译,所以任何引用全局 `CoreKit` 标识符的脚本都不能被测试顶层 preload。
- 直接实例化脚本(不经 `CoreKit` autoload——只有 `test_core_kit.gd` 测门面本身)。
- 用 `failures` 计数断言,每条失败 `print("FAIL n: ...")`,结尾 `print("test_x: ALL PASS"); quit(0)` 或 `... %d FAILURE(S); quit(1)`。
- 若子系统可注入,**同时**测已绑定和未绑定(`null`)降级路径两种情况。
- `.gd.uid` 边车是 Godot 真实生成的文件:跑 `godot --headless --path . --import` 生成;`.gd` 与其 `.gd.uid` 一起提交;绝不手写或复制 UID。

## 更新门面回归测试 —— `test/test_core_kit.gd`

它在多处硬编码了子系统清单:把你的条目加进 `expected`(prop + 脚本路径)数组**和** `order`(节点名)数组;若注入了依赖,加一条 `bind_*` 断言;并更新 VERSION 断言(见下)。

## 版本、文档、runner 保持同步

- **版本**(三处必须一致):`plugin.cfg` 的 `version=`(并扩充 `description=`)、`core_kit.gd` 的 `const VERSION`、`test_core_kit.gd` 的 VERSION 断言。新增子系统是新功能 → **minor** 升(如 `0.4.1` → `0.5.0`)。无 API 变更的结构性改动才是 patch——`0.4.0` → `0.4.1` 那次就是,别复用 patch 号。
- **Runner**:把 `'test_x'` 加进 `test/run_all.ps1` 的 `$tests` 数组,**放在 `'test_core_kit'` 之前**(它必须留最后——它断言整个门面)。runner 还会 grep demo 的 stdout 找固定 marker 列表,并在 stderr 命中 `ERROR:`/`SCRIPT ERROR:` 时判失败,所以新代码只要 push 出 error 就会挂门。
- **Demo**:在 `demo/demo.gd` 加一段冒烟块,含一行有辨识度的 `CoreKit.log.info(...)`。
- **文档**(living docs——绝不改 `docs/superpowers/*`,那是带日期的快照):新建 `addons/godot-core-kit/docs/systems/x.md`——**文档文件名是 kebab-case**,尽管脚本是 snake_case(`resource_manager.gd` → `resource-manager.md`)。用五段式模板(职责 / 公开 API / 依赖 / 用法示例 / 注意事项);给 `docs/README.md` 和 `docs/architecture.md`(门面表、构造链)加行。子系统数量与测试数量以散文硬编码在多处(`architecture.md`、仓库 `README.md`、`run_all.ps1` 头注释)——grep 旧数字,逐处更新。

## 验收 —— 门

```
powershell -File test\run_all.ps1
```

必须以 `=== SUMMARY FAILS=0 ===` 结尾(import → 每个测试 ALL PASS → demo 冒烟、stderr 干净)。这是唯一验收信号——不绿之前不要声称改完了。

## 常见错误

| 错误 | 修法 |
|---|---|
| `-s` 测试里顶层 `const XScript := preload(...)` | 改用 `_initialize()` 内的运行时 `load(...)` |
| system 脚本加了 `class_name` | 子系统只经门面访问;去掉 |
| 一个子系统 `preload` 另一个 | 用 `core_kit.gd:_ready()` 的 `bind_*` 注入,或 `CoreKit.log` |
| 只改了 `plugin.cfg` 没改 `VERSION`/测试断言 | 三处一起改 |
| 加了子系统但 `test_core_kit.gd` 挂了 | 更新它的 `expected` + `order` 清单 |
| 手写了 `.gd.uid` | 跑 `--import` 让它真正生成 |
| 用空格缩进 | 本仓库用 Tab |
