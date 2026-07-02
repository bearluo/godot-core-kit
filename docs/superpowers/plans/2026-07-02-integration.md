# v0.4.0 集成 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把波 1/波 2 的六个新子系统接进 CoreKit 门面,交付 demo/README/版本号,v0.4.0 定稿。

**Architecture:** 见总纲 spec `docs/superpowers/specs/2026-07-02-corekit-facade-design.md`"执行编排"一节。前置:门面迁移 + 波 1(Settings/FrameScheduler/KitStateMachine)+ 波 2(Input/Audio/Resource)已全部合入 `feat/framework-v0.4`。

**Tech Stack:** Godot 4.7 / 纯 GDScript / headless `-s` 断言测试

## Global Constraints

- 分支:全部工作在 `feat/framework-v0.4` 上;线性历史,不得产生 merge commit。
- 纯 GDScript、Tab 缩进;无 C#、无 GDExtension、无第三方依赖;命令行 `godot` 已在 PATH。
- 依赖纪律:CoreKit._ready 是唯一的跨子系统接线点(`bind_settings`/`bind_ticker`)。
- 测试纪律(`-s` 避坑手册):测试无论成败必须到达 `quit()`;test_core_kit 例外地直接使用 `/root/CoreKit`(测的就是接线本身)。
- 运行测试用硬超时模板(PowerShell,单测 60s、resource_manager 120s 上限):

```powershell
$p = Start-Process godot -ArgumentList '--headless','--path','.','-s','res://test/<file>.gd' -RedirectStandardOutput "$env:TEMP\gck-out.txt" -RedirectStandardError "$env:TEMP\gck-err.txt" -PassThru -NoNewWindow; if (-not $p.WaitForExit(60000)) { $p.Kill(); 'TIMEOUT(疑似测试报错未达 quit)' }; Get-Content "$env:TEMP\gck-out.txt"
```

- git 提交消息不得含英文双引号(PowerShell here-string 坑)。

---

### Task 1: 门面接线 + demo + README + 版本落地

**Files:**
- Modify: `addons/godot-core-kit/core_kit.gd`(整文件重写为最终版)
- Modify: `addons/godot-core-kit/plugin.cfg`(version 行 `0.3.0` → `0.4.0`)
- Modify: `demo/demo.gd`(整文件重写为最终版)
- Modify: `README.md`(整文件重写)
- Create: `test/test_core_kit.gd`
- Test: 全部 12 份测试 + demo headless 冒烟

**Interfaces:**
- Consumes: 波 1/波 2 六个子系统脚本及其 `bind_settings(settings)`/`bind_ticker(ticker)`;老五件(门面迁移任务)。
- Produces: 最终 `CoreKit` 门面(10 属性)+ `VERSION == "0.4.0"`。

- [ ] **Step 1: 重写 core_kit.gd 为最终版**

```gdscript
extends Node
## CoreKit —— godot-core-kit 门面根节点,唯一 autoload。
## 各子系统经短属性名访问:CoreKit.log / .bus / .scenes / .pool / .saves /
## .settings / .ticker / .input / .audio / .res。
## 子系统仍是各自独立的脚本与 Node(保留各自 _process 与信号),由本节点在
## _init 按依赖序构造并 add_child;子节点树顺序 = _ready 触发顺序(子先于父),
## 因此各子系统的自身初始化按构造序完成,消费方没有弄乱顺序的入口。
## _ready(全部子系统 _ready 完毕后)是唯一的跨子系统接线点(bind_*)。
##
## 命名坑:属性 log 会遮蔽全局函数 log()(与旧 Log autoload 同款遮蔽);本脚本
## 内部不需要数学 log(),不受影响。

const VERSION := "0.4.0"

const LogScript := preload("res://addons/godot-core-kit/log.gd")
const SettingsScript := preload("res://addons/godot-core-kit/settings.gd")
const EventBusScript := preload("res://addons/godot-core-kit/event_bus.gd")
const SceneManagerScript := preload("res://addons/godot-core-kit/scene_manager.gd")
const ObjectPoolScript := preload("res://addons/godot-core-kit/object_pool.gd")
const SaveManagerScript := preload("res://addons/godot-core-kit/save_manager.gd")
const FrameSchedulerScript := preload("res://addons/godot-core-kit/frame_scheduler.gd")
const InputManagerScript := preload("res://addons/godot-core-kit/input_manager.gd")
const AudioManagerScript := preload("res://addons/godot-core-kit/audio_manager.gd")
const ResourceManagerScript := preload("res://addons/godot-core-kit/resource_manager.gd")

var log: LogScript
var settings: SettingsScript
var bus: EventBusScript
var scenes: SceneManagerScript
var pool: ObjectPoolScript
var saves: SaveManagerScript
var ticker: FrameSchedulerScript
var input: InputManagerScript
var audio: AudioManagerScript
var res: ResourceManagerScript


func _init() -> void:
	log = LogScript.new()
	log.name = "Log"
	add_child(log)

	settings = SettingsScript.new()
	settings.name = "Settings"
	add_child(settings)

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

	ticker = FrameSchedulerScript.new()
	ticker.name = "FrameScheduler"
	add_child(ticker)

	input = InputManagerScript.new()
	input.name = "InputManager"
	add_child(input)

	audio = AudioManagerScript.new()
	audio.name = "AudioManager"
	add_child(audio)

	res = ResourceManagerScript.new()
	res.name = "ResourceManager"
	add_child(res)


func _ready() -> void:
	# 唯一的跨子系统接线点:此时全部子系统已各自 _ready 完毕。
	input.bind_settings(settings)
	audio.bind_settings(settings)
	res.bind_ticker(ticker)
	log.info("CoreKit v%s ready" % VERSION)
```

- [ ] **Step 2: plugin.cfg 版本号**

把 `version="0.3.0"` 改为 `version="0.4.0"`(其余行不动)。

- [ ] **Step 3: 写 test/test_core_kit.gd**

```gdscript
extends SceneTree
## CoreKit 门面接线 headless 断言测试——测的就是 autoload 接线本身,
## 因此例外地直接使用 /root/CoreKit(-s 模式下 autoload 已注册、_ready 已跑完,
## 与其余测试"直接实例化脚本"的模式不同)。
## 运行:godot --headless --path . -s res://test/test_core_kit.gd


func _initialize() -> void:
	var failures := 0
	var kit = root.get_node_or_null("CoreKit")
	if kit == null:
		print("FAIL 0: /root/CoreKit autoload 缺失")
		print("test_core_kit: 1 FAILURE(S)")
		quit(1)
		return

	# 1. 版本
	if kit.VERSION != "0.4.0":
		print("FAIL 1: VERSION 应为 0.4.0,实际 %s" % kit.VERSION)
		failures += 1

	# 2. 十个门面属性非 null 且脚本路径正确
	var expected := [
		["log", "res://addons/godot-core-kit/log.gd"],
		["settings", "res://addons/godot-core-kit/settings.gd"],
		["bus", "res://addons/godot-core-kit/event_bus.gd"],
		["scenes", "res://addons/godot-core-kit/scene_manager.gd"],
		["pool", "res://addons/godot-core-kit/object_pool.gd"],
		["saves", "res://addons/godot-core-kit/save_manager.gd"],
		["ticker", "res://addons/godot-core-kit/frame_scheduler.gd"],
		["input", "res://addons/godot-core-kit/input_manager.gd"],
		["audio", "res://addons/godot-core-kit/audio_manager.gd"],
		["res", "res://addons/godot-core-kit/resource_manager.gd"],
	]
	for pair in expected:
		var sub = kit.get(pair[0])
		if sub == null:
			print("FAIL 2: CoreKit.%s 为 null" % pair[0])
			failures += 1
			continue
		var script: Resource = sub.get_script()
		if script == null or script.resource_path != pair[1]:
			print("FAIL 2: CoreKit.%s 的脚本不是 %s" % [pair[0], pair[1]])
			failures += 1

	# 3. 子节点顺序 = 构造顺序(_ready 触发序可复现)
	var order := ["Log", "Settings", "EventBus", "SceneManager", "ObjectPool",
		"SaveManager", "FrameScheduler", "InputManager", "AudioManager", "ResourceManager"]
	if kit.get_child_count() != order.size():
		print("FAIL 3: 子节点数应为 %d,实际 %d" % [order.size(), kit.get_child_count()])
		failures += 1
	else:
		for i in order.size():
			if String(kit.get_child(i).name) != order[i]:
				print("FAIL 3: 第 %d 个子节点应为 %s,实际 %s" % [i, order[i], kit.get_child(i).name])
				failures += 1

	# 4. 接线:bind_settings / bind_ticker 已生效
	if kit.input._settings != kit.settings:
		print("FAIL 4: input 未绑定 settings")
		failures += 1
	if kit.audio._settings != kit.settings:
		print("FAIL 4: audio 未绑定 settings")
		failures += 1
	if kit.res._ticker != kit.ticker:
		print("FAIL 4: res 未绑定 ticker")
		failures += 1

	# 5. 老 API 经门面冒烟
	var box := {"payload": null}
	kit.bus.subscribe("__facade_smoke__", func(payload) -> void: box["payload"] = payload)
	kit.bus.publish("__facade_smoke__", 42)
	if box["payload"] != 42:
		print("FAIL 5: EventBus 经门面发布订阅失败")
		failures += 1
	if kit.saves._decode("{}") != {}:
		print("FAIL 5: SaveManager._decode 经门面调用失败")
		failures += 1

	if failures == 0:
		print("test_core_kit: ALL PASS")
		quit(0)
	else:
		print("test_core_kit: %d FAILURE(S)" % failures)
		quit(1)
```

- [ ] **Step 4: 重写 demo/demo.gd 为最终版(冒烟全部 10 个子系统 + 状态机)**

```gdscript
extends Node
## 冒烟测试场景:证明 CoreKit 门面与全部子系统已就绪且可调用。
## 用 Godot 4 打开工程直接运行(或 headless --quit-after 60)即可,
## 输出应看到各子系统按预期响应、无报错。

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

	# Settings 冒烟:写 → 读 → 清(user://settings.json 写透)
	CoreKit.settings.set_value("demo", "flag", true)
	CoreKit.log.info("Settings demo.flag = %s" % CoreKit.settings.get_value("demo", "flag"))
	CoreKit.settings.erase_section("demo")

	# FrameScheduler 冒烟:降频心跳 + 预算任务(输出在后续帧出现)
	CoreKit.ticker.every_n(func() -> void: CoreKit.log.info("FrameScheduler: 每 30 帧心跳"), 30)
	CoreKit.ticker.queue_task(func() -> void: CoreKit.log.info("FrameScheduler: 预算任务已执行"))

	# InputManager 冒烟:设备与缓冲查询
	CoreKit.log.info("InputManager current_device = %d, jump buffered = %s" % [
		CoreKit.input.current_device, CoreKit.input.is_action_buffered("ui_accept", 0.2)])

	# AudioManager 冒烟:音量设置(经 Settings 持久化)
	CoreKit.audio.set_volume("music", 0.8)
	CoreKit.log.info("AudioManager music volume = %.2f" % CoreKit.audio.get_volume("music"))

	# ResourceManager 冒烟:异步预热(completed 在后续帧广播,验证 deferred 投递)
	CoreKit.res.batch_completed.connect(func() -> void: CoreKit.log.info("ResourceManager: 预热批完成"))
	CoreKit.res.preload_batch(["res://addons/godot-core-kit/log.gd"])

	# KitStateMachine 冒烟:代码组一台两态状态机(类库,不经门面)
	var machine := KitStateMachine.new()
	var idle := KitState.new()
	idle.name = "Idle"
	machine.add_child(idle)
	var run := KitState.new()
	run.name = "Run"
	machine.add_child(run)
	machine.state_changed.connect(func(from: String, to: String) -> void:
		CoreKit.log.info("KitStateMachine: [%s] -> [%s]" % [from, to]))
	add_child(machine)          # 触发 _ready:进 Idle
	machine.transition_to("Run")

	CoreKit.log.info("CoreKit v%s — all subsystems smoke-tested" % CoreKit.VERSION)


func _on_demo_event(payload) -> void:
	CoreKit.log.info("EventBus delivered: %s" % payload)


func _make_dummy_scene() -> PackedScene:
	var scene := PackedScene.new()
	var root := Node.new()
	scene.pack(root)
	root.free()
	return scene
```

- [ ] **Step 5: 重写 README.md**

(下方 README 全文用四反引号围栏包裹:README 自身含三反引号代码块)

````markdown
# godot-core-kit

通用 2D 游戏开发底层框架(Godot 4.7,纯 GDScript,Web 导出兼容)。
单一 autoload 门面 `CoreKit` 暴露全部子系统;`KitStateMachine`/`KitState`
以 class_name 类库随插件分发。

## 安装

1. 把 `addons/godot-core-kit/` 复制进目标工程;
2. 项目设置 → 插件 → 启用 godot-core-kit(自动注册唯一 autoload `CoreKit`)。

## 子系统一览

| 门面属性 | 子系统 | 一句话 |
|---|---|---|
| `CoreKit.log` | Log | 分级日志(debug/info/warn/error,运行时可调级) |
| `CoreKit.bus` | EventBus | 字符串事件 pub/sub,失效监听自动清理,重入安全 |
| `CoreKit.scenes` | SceneManager | 统一切场景入口,可选淡入淡出,重入拒绝 |
| `CoreKit.pool` | ObjectPool | 具名对象池,预热/上限/`_pool_reset` 钩子 |
| `CoreKit.saves` | SaveManager | JSON 信封存档槽(`user://saves/`) |
| `CoreKit.settings` | Settings | 玩家偏好分区键值,写透 `user://settings.json` |
| `CoreKit.ticker` | FrameScheduler | every_n 降频错峰 tick + 每帧预算任务队列 |
| `CoreKit.input` | InputManager | 键位重绑定持久化、设备检测、输入前缓冲 |
| `CoreKit.audio` | AudioManager | 总线音量持久化、BGM 交叉淡切、SFX 轮转池 |
| `CoreKit.res` | ResourceManager | 异步批量预热(桌面线程/Web 分帧双通道)+ 缓存 |

## 快速开始

```gdscript
CoreKit.log.info("hello")
CoreKit.bus.subscribe("player_died", _on_player_died)
CoreKit.bus.publish("player_died", {"by": "spike"})

CoreKit.settings.set_value("audio", "music", 0.8)
CoreKit.audio.play_music(preload("res://music/theme.ogg"), 1.5)  # 1.5s 交叉淡切
CoreKit.audio.play_sfx(preload("res://sfx/jump.wav"))

CoreKit.input.rebind_action("jump", my_key_event)   # 自动持久化,下次启动自动恢复
if CoreKit.input.is_action_buffered("jump", 0.15):  # 平台跳跃前缓冲
    CoreKit.input.consume_buffer("jump")
    _do_jump()

CoreKit.ticker.every_n(_slow_ai_think, 10)          # 每 10 帧,自动错峰
CoreKit.res.preload_batch(level_paths)              # 进度条接 batch_progress 信号

var save_ok := CoreKit.saves.save("slot1", {"hp": 100})
```

### 状态机(类库,不经门面)

```gdscript
# 场景树:Player → KitStateMachine → Idle/Run/Jump(各挂一个 KitState 子类脚本)
# 状态脚本里:
extends KitState

func update(delta: float) -> void:
    if CoreKit.input.is_action_buffered("jump", 0.15):
        transition_to("Jump")
```

## 0.3.x → 0.4.0 迁移(破坏性变更)

v0.4.0 起只注册一个 autoload `CoreKit`,老的全局单例名全部下线:

| 0.3.x | 0.4.0 |
|---|---|
| `Log.info(...)` | `CoreKit.log.info(...)` |
| `EventBus.publish(...)` | `CoreKit.bus.publish(...)` |
| `SceneManager.change_scene(...)` | `CoreKit.scenes.change_scene(...)` |
| `ObjectPool.acquire(...)` | `CoreKit.pool.acquire(...)` |
| `SaveManager.save(...)` | `CoreKit.saves.save(...)` |

升级步骤:更新 addon 目录后,在项目设置 → 全局(autoload)里**手动删除**
Log/EventBus/SceneManager/ObjectPool/SaveManager 五项旧注册,只保留 CoreKit;
然后按上表全局替换调用点。

## 测试

```
godot --headless --path . -s res://test/test_<subsystem>.gd
```

12 份 headless 断言测试覆盖全部子系统与门面接线;`demo/demo.tscn` 冒烟全家桶。

## 版本

- **0.4.0** — CoreKit 门面(唯一 autoload);新增 Settings / FrameScheduler /
  KitStateMachine / InputManager / AudioManager / ResourceManager;老五件迁入门面
  (破坏性变更,见迁移表)。
- 0.3.0 — EventBus / SceneManager / ObjectPool / SaveManager。
- 0.2.0 — Log。
- 0.1.0 — addon 脚手架。
````

- [ ] **Step 6: 刷新 class 缓存并跑全部 12 份测试**

先 `godot --headless --path . --import`(120s 超时),然后对以下文件逐个套用硬超时模板:
`test_log` `test_event_bus` `test_scene_manager` `test_object_pool` `test_save_manager` `test_settings` `test_frame_scheduler` `test_state_machine` `test_input_manager` `test_audio_manager` `test_resource_manager`(120s) `test_core_kit`。
Expected: 12 个 `ALL PASS`,退出码全 0。

- [ ] **Step 7: demo headless 冒烟**

```powershell
$p = Start-Process godot -ArgumentList '--headless','--path','.','res://demo/demo.tscn','--quit-after','60' -RedirectStandardOutput "$env:TEMP\gck-demo.txt" -RedirectStandardError "$env:TEMP\gck-demo-err.txt" -PassThru -NoNewWindow; if (-not $p.WaitForExit(90000)) { $p.Kill(); 'TIMEOUT' }; Get-Content "$env:TEMP\gck-demo.txt"
```

Expected: 出现全部子系统冒烟行,特别确认后续帧才出现的三行——`FrameScheduler: 预算任务已执行`、`FrameScheduler: 每 30 帧心跳`、`ResourceManager: 预热批完成`(验证 deferred/分帧投递),以及 `KitStateMachine: [] -> [Idle]` 与 `[Idle] -> [Run]`;结尾 `CoreKit v0.4.0 — all subsystems smoke-tested`;无红色报错。

- [ ] **Step 8: 提交**

```powershell
git add addons/godot-core-kit/core_kit.gd addons/godot-core-kit/plugin.cfg demo/demo.gd README.md test/test_core_kit.gd
git commit -m 'feat: wire six new subsystems into CoreKit facade, bump 0.4.0'
```
