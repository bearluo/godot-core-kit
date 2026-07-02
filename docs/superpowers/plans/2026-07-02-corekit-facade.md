# CoreKit 门面化 + 老系统迁移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 core_kit.gd 升格为门面根节点(唯一 autoload),五个老子系统迁入 `CoreKit.log/.bus/.scenes/.pool/.saves` 短属性访问。

**Architecture:** 见 spec `docs/superpowers/specs/2026-07-02-corekit-facade-design.md`。本任务是 v0.4.0 全部后续任务的串行前置:老系统内部互引从全局名 `Log` 改为 `CoreKit.log`,plugin/project 只注册一个 autoload。

**Tech Stack:** Godot 4.7 / 纯 GDScript / headless `-s` 断言测试

## Global Constraints

- 分支:全部工作在 `feat/framework-v0.4` 上(从 main 切出);线性历史,不得产生 merge commit。
- 纯 GDScript、Tab 缩进;无 C#、无 GDExtension、无第三方依赖;命令行 `godot` 已在 PATH。
- Web 导出兼容:禁用线程/平台专属 API。
- 依赖纪律:子系统间引用仅限总纲 spec 依赖表;初始化期诊断用 `push_warning`/`push_error`,运行期用 `CoreKit.log.*`。
- 测试纪律(`-s` 避坑手册):`-s` 主脚本不得在类作用域 preload 任何引用 `CoreKit` 全局的脚本(`_initialize()` 内运行时 `load()`);可能接住已 free 实例的变量/形参不标注类型;untyped 值的下游变量显式标注类型(不用 `:=`);测试无论成败必须到达 `quit()`。
- 运行测试用硬超时模板(PowerShell,单测 60s 上限):

```powershell
$p = Start-Process godot -ArgumentList '--headless','--path','.','-s','res://test/<file>.gd' -RedirectStandardOutput "$env:TEMP\gck-out.txt" -RedirectStandardError "$env:TEMP\gck-err.txt" -PassThru -NoNewWindow; if (-not $p.WaitForExit(60000)) { $p.Kill(); 'TIMEOUT(疑似测试报错未达 quit)' }; Get-Content "$env:TEMP\gck-out.txt"
```

- git 提交消息不得含英文双引号(PowerShell here-string 坑)。

---

### Task 1: CoreKit 门面化 + 老五件迁移

**Files:**
- Modify: `addons/godot-core-kit/core_kit.gd`(整文件重写)
- Modify: `addons/godot-core-kit/plugin.gd`(整文件重写)
- Modify: `addons/godot-core-kit/scene_manager.gd:45,51,68`(`Log.` → `CoreKit.log.`)
- Modify: `addons/godot-core-kit/object_pool.gd:52,55,61,72,88,92,108,127,135,139,144,150,169,178`(同上,含注释里的 `Log.warn`/`Log.error` 措辞)
- Modify: `addons/godot-core-kit/save_manager.gd:8,80`(同上,含第 8 行注释)
- Modify: `addons/godot-core-kit/log.gd:9`(用法注释改为 `CoreKit.log.info(...)` 等)
- Modify: `project.godot`(`[autoload]` 删 5 行)
- Modify: `demo/demo.gd`(整文件重写)
- Modify: `test/test_scene_manager.gd`、`test/test_save_manager.gd`、`test/test_object_pool.gd`(仅头部注释措辞)
- Test: 既有五份 `test/test_*.gd` 全绿即为验收(本任务不新增测试文件;门面接线测试在集成任务统一交付)

**Interfaces:**
- Consumes: 既有五个子系统脚本的公开 API(不变)。
- Produces: `CoreKit` autoload,属性 `log: LogScript`、`bus: EventBusScript`、`scenes: SceneManagerScript`、`pool: ObjectPoolScript`、`saves: SaveManagerScript`(类型即各脚本 preload 常量);子节点名依序 `Log/EventBus/SceneManager/ObjectPool/SaveManager`。后续全部波次任务的代码经 `CoreKit.log.warn(...)` 等调用日志。

- [ ] **Step 1: 重写 core_kit.gd 为门面(迁移版,只含老五件;VERSION 暂留 0.3.0,集成任务统一 bump)**

```gdscript
extends Node
## CoreKit —— godot-core-kit 门面根节点,唯一 autoload。
## 各子系统经短属性名访问:CoreKit.log / .bus / .scenes / .pool / .saves。
## 子系统仍是各自独立的脚本与 Node(保留各自 _process 与信号),由本节点在
## _init 按依赖序构造并 add_child;子节点树顺序 = _ready 触发顺序(子先于父),
## 因此各子系统的自身初始化按构造序完成,消费方没有弄乱顺序的入口。
## _ready(全部子系统 _ready 完毕后)是唯一的跨子系统接线点。
##
## 命名坑:属性 log 会遮蔽全局函数 log()(与旧 Log autoload 同款遮蔽);本脚本
## 内部不需要数学 log(),不受影响。

const VERSION := "0.3.0"

const LogScript := preload("res://addons/godot-core-kit/log.gd")
const EventBusScript := preload("res://addons/godot-core-kit/event_bus.gd")
const SceneManagerScript := preload("res://addons/godot-core-kit/scene_manager.gd")
const ObjectPoolScript := preload("res://addons/godot-core-kit/object_pool.gd")
const SaveManagerScript := preload("res://addons/godot-core-kit/save_manager.gd")

var log: LogScript
var bus: EventBusScript
var scenes: SceneManagerScript
var pool: ObjectPoolScript
var saves: SaveManagerScript


func _init() -> void:
	log = LogScript.new()
	log.name = "Log"
	add_child(log)

	bus = EventBusScript.new()
	bus.name = "EventBus"
	add_child(bus)

	scenes = SceneManagerScript.new()
	scenes.name = "SceneManager"
	add_child(scenes)

	pool = ObjectPoolScript.new()
	pool.name = "ObjectPool"
	add_child(pool)

	saves = SaveManagerScript.new()
	saves.name = "SaveManager"
	add_child(saves)


func _ready() -> void:
	log.info("CoreKit v%s ready" % VERSION)
```

已知风险:core_kit.gd preload 子系统脚本、子系统脚本又引用 `CoreKit` 全局标识符,构成循环引用。Godot 4.7 支持这种"preload + autoload 标识符"环;若 Step 6 跑测试时出现 `Could not resolve script` / `Cyclic reference` 类编译错,**停下报 BLOCKED**,不要自行改架构。

- [ ] **Step 2: 老三件的 `Log.` 全部替换为 `CoreKit.log.`**

对 `scene_manager.gd`(3 处代码)、`object_pool.gd`(10 处代码 + 4 处注释)、`save_manager.gd`(1 处代码 + 第 8 行注释里的"除 Log")、`log.gd`(第 9 行用法注释)执行整词替换 `Log.` → `CoreKit.log.`;`save_manager.gd:8` 注释中的"除 Log(仅用于版本不匹配警告)"改为"除 CoreKit.log(仅用于版本不匹配警告)"。替换后验证:

```powershell
# 期望:零输出(addon 目录里不再有裸 Log. 引用)
Select-String -Path addons\godot-core-kit\*.gd -Pattern '(?<!CoreKit\.)\bLog\.' | Select-Object Path, LineNumber, Line
```

- [ ] **Step 3: 重写 plugin.gd(单 autoload 注册)**

```gdscript
@tool
extends EditorPlugin
## godot-core-kit 编辑器插件入口。
## v0.4.0 起只注册一个 autoload:CoreKit(门面),全部子系统由它内部构造,
## 初始化顺序完全内控。从 0.3.x 升级的工程需手动移除旧的 Log/EventBus/
## SceneManager/ObjectPool/SaveManager 五项 autoload 注册(见 README 迁移一节)。

const AUTOLOAD_NAME := "CoreKit"
const AUTOLOAD_PATH := "res://addons/godot-core-kit/core_kit.gd"


func _enter_tree() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _exit_tree() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)
```

- [ ] **Step 4: project.godot 的 `[autoload]` 只留两行**

删除 `Log=`、`EventBus=`、`SceneManager=`、`ObjectPool=`、`SaveManager=` 五行;保留 `CoreKit="*res://addons/godot-core-kit/core_kit.gd"` 与 `_mcp_game_helper=...`(godot-ai 开发工具,原样不动)。用 Edit 工具逐行删,不要整段重写(避免破坏其它段)。

- [ ] **Step 5: 重写 demo/demo.gd(门面调用,迁移版)**

```gdscript
extends Node
## 冒烟测试场景:证明 CoreKit 门面与全部子系统已就绪且可调用。
## 用 Godot 4 打开工程直接运行即可,输出应看到各子系统按预期响应、无报错。

func _ready() -> void:
	CoreKit.log.info("demo scene loaded — core-kit is wired up correctly")

	# EventBus 冒烟:订阅 → 发布 → 同步回调
	CoreKit.bus.subscribe("demo_event", _on_demo_event)
	CoreKit.bus.publish("demo_event", "hello from EventBus")

	# SceneManager 冒烟:查询状态(不真正切场景)
	CoreKit.log.info("SceneManager.is_changing = %s" % CoreKit.scenes.is_changing())

	# ObjectPool 冒烟:注册 → 借出 → 归还
	CoreKit.pool.register("demo_pool", _make_dummy_scene(), 2)
	var n: Node = CoreKit.pool.acquire("demo_pool")
	CoreKit.log.info("ObjectPool acquired=%s available=%d in_use=%d" % [
		n != null, CoreKit.pool.available_count("demo_pool"), CoreKit.pool.in_use_count("demo_pool")])
	CoreKit.pool.release(n)

	# SaveManager 冒烟:存 → 读 → 删(user:// 落盘往返)
	var ok := CoreKit.saves.save("__demo_smoke__", {"score": 42, "name": "hero"})
	var data := CoreKit.saves.load("__demo_smoke__")
	CoreKit.log.info("SaveManager save=%s load=%s" % [ok, data])
	CoreKit.saves.delete_slot("__demo_smoke__")

	CoreKit.log.info("CoreKit v%s — facade smoke-tested" % CoreKit.VERSION)


func _on_demo_event(payload) -> void:
	CoreKit.log.info("EventBus delivered: %s" % payload)


func _make_dummy_scene() -> PackedScene:
	var scene := PackedScene.new()
	var root := Node.new()
	scene.pack(root)
	root.free()
	return scene
```

- [ ] **Step 6: 更新三份测试文件的头部注释措辞(不改断言)**

`test_scene_manager.gd`、`test_save_manager.gd`、`test_object_pool.gd` 头部解释"为什么运行时 load()"的注释里,把"全局 autoload 标识符 Log"/"Log autoload"措辞改为"全局 autoload 标识符 CoreKit"/"CoreKit autoload"(机制不变:被测脚本引用 `CoreKit` 全局,`-s` 类作用域 preload 会在 autoload 注册前编译失败)。断言代码一行不动。

- [ ] **Step 7: 跑全部五份既有测试,全绿**

对 `test_log.gd`、`test_event_bus.gd`、`test_scene_manager.gd`、`test_object_pool.gd`、`test_save_manager.gd` 逐个套用 Global Constraints 的硬超时模板运行。
Expected: 每个都打印 `test_<name>: ALL PASS`,退出码 0。任何 TIMEOUT/FAIL 先查 stderr(`$env:TEMP\gck-err.txt`)。

- [ ] **Step 8: demo 冒烟(headless 跑几帧)**

```powershell
$p = Start-Process godot -ArgumentList '--headless','--path','.','res://demo/demo.tscn','--quit-after','10' -RedirectStandardOutput "$env:TEMP\gck-demo.txt" -RedirectStandardError "$env:TEMP\gck-demo-err.txt" -PassThru -NoNewWindow; if (-not $p.WaitForExit(60000)) { $p.Kill(); 'TIMEOUT' }; Get-Content "$env:TEMP\gck-demo.txt"
```

Expected: 依次出现 demo 各行日志(EventBus delivered / SceneManager.is_changing / ObjectPool acquired / SaveManager save=true / facade smoke-tested),无红色报错。

- [ ] **Step 9: 提交**

```powershell
git add addons/godot-core-kit/core_kit.gd addons/godot-core-kit/plugin.gd addons/godot-core-kit/scene_manager.gd addons/godot-core-kit/object_pool.gd addons/godot-core-kit/save_manager.gd addons/godot-core-kit/log.gd project.godot demo/demo.gd test/test_scene_manager.gd test/test_save_manager.gd test/test_object_pool.gd
git commit -m 'refactor: CoreKit facade as sole autoload, migrate five subsystems'
```
