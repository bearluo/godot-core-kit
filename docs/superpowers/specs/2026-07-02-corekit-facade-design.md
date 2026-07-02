# godot-core-kit v0.4.0 总纲:CoreKit 门面架构与老系统迁移

- 日期:2026-07-02
- 状态:已确认,待实现
- 版本目标:0.4.0
- 前置:v0.3.0 全部既有 spec(scaffold / logger / event-bus / scene-manager / object-pool / save-manager)
- 定位:本文档是 v0.4.0 六份子系统 spec 的**总纲**,定义全局架构决策(门面、分层、命名纪律、迁移、执行编排);各子系统的 API 细节见配套 spec:
  - `2026-07-02-settings-design.md`
  - `2026-07-02-frame-scheduler-design.md`
  - `2026-07-02-state-machine-design.md`
  - `2026-07-02-input-manager-design.md`
  - `2026-07-02-audio-manager-design.md`
  - `2026-07-02-resource-manager-design.md`

---

## 核心架构决策:CoreKit 门面(greenfield 拍板)

v0.4.0 起,插件**只注册一个 autoload:`CoreKit`**。`core_kit.gd` 从版本元数据升格为门面根节点,构造全部子系统并 `add_child`;子系统仍是各自独立的脚本文件与 Node(保留各自 `_process` 与信号),但不再各自注册 autoload。

拍板理由(相对"每系统一个 autoload"的多 autoload 方案):

1. **全局命名空间只占 1 个名字**。`Settings`/`InputManager`/`AudioManager` 都是大众名,公司多项目复用 + 与第三方 addon 共存时撞名概率不低,且撞了不能简单改名(子系统内部互引写死全局名)。
2. **初始化顺序完全内控**。多 autoload 方案下顺序靠消费方项目设置自觉维护;门面方案下构造顺序写死在 `core_kit.gd` 里,消费方没有弄乱的入口。
3. 命名空间自带出处标识(`CoreKit.audio.play_music(...)` 一眼可知是框架调用);安装说明收敛为一句"启用插件"。
4. 成熟先例:Dialogic(单 `Dialogic` 门面挂全部子系统)。

已知代价(接受):调用比全局短名长一截(用短属性名缓解,游戏层还可自建 `@onready var audio := CoreKit.audio` 别名);门面为类型补全 preload 全部子系统脚本,**"删文件式裁剪"不再可行**(裁剪=不实例化,文件保留);v0.3.0 API 破坏性变更(0.x 阶段正当,见迁移节)。

### 通用性准入标准

**换一个游戏不用改一行的才进 kit。** 状态机/音频/输入/资源/帧分频器/设置全部满足;战斗数值、buff、任务等游戏特定逻辑永远不进。

---

## 门面 Public API(core_kit.gd)

```gdscript
extends Node
## CoreKit —— godot-core-kit 门面根节点,唯一 autoload。

const VERSION := "0.4.0"

const LogScript := preload("res://addons/godot-core-kit/log.gd")
const EventBusScript := preload("res://addons/godot-core-kit/event_bus.gd")
const SceneManagerScript := preload("res://addons/godot-core-kit/scene_manager.gd")
const ObjectPoolScript := preload("res://addons/godot-core-kit/object_pool.gd")
const SaveManagerScript := preload("res://addons/godot-core-kit/save_manager.gd")
const SettingsScript := preload("res://addons/godot-core-kit/settings.gd")
const FrameSchedulerScript := preload("res://addons/godot-core-kit/frame_scheduler.gd")
const InputManagerScript := preload("res://addons/godot-core-kit/input_manager.gd")
const AudioManagerScript := preload("res://addons/godot-core-kit/audio_manager.gd")
const ResourceManagerScript := preload("res://addons/godot-core-kit/resource_manager.gd")

var log: LogScript              ## CoreKit.log.info("...")
var bus: EventBusScript         ## CoreKit.bus.publish("hit", dmg)
var scenes: SceneManagerScript  ## CoreKit.scenes.change_scene(path)
var pool: ObjectPoolScript      ## CoreKit.pool.acquire("bullet")
var saves: SaveManagerScript    ## CoreKit.saves.save("hero1", data)
var settings: SettingsScript    ## CoreKit.settings.set_value("audio", "music", 0.8)
var ticker: FrameSchedulerScript    ## CoreKit.ticker.every_n(cb, 10)
var input: InputManagerScript   ## CoreKit.input.is_action_buffered("jump", 0.15)
var audio: AudioManagerScript   ## CoreKit.audio.play_music(stream, 1.0)
var res: ResourceManagerScript  ## CoreKit.res.preload_batch(paths)
```

### 构造与初始化顺序

- `_init()`:按 **log → settings → bus → scenes → pool → saves → ticker → input → audio → res** 的顺序 `new()` 各子系统、赋给属性、`add_child`。子节点树顺序 = `_ready` 触发顺序(Godot 子先于父),因此各子系统的自身初始化(如 Settings 读盘)按此序完成。
- `_ready()`(父节点最后触发,此时全部子系统已各自 `_ready` 完毕)是**唯一的跨子系统接线点**,依次调用:
  - `input.bind_settings(settings)` —— 恢复键位覆盖并持有引用(后续 rebind 写回)
  - `audio.bind_settings(settings)` —— 恢复音量并持有引用
  - `res.bind_ticker(ticker)` —— Web/无线程平台的分帧加载通道

### 依赖表(唯一允许的子系统间依赖)

| 子系统 | 依赖 | 方式 |
|---|---|---|
| log / bus | 无 | — |
| scenes / pool / saves | log | 运行时经 `CoreKit.log` 全局链 |
| settings / ticker | log | 运行时经 `CoreKit.log` 全局链 |
| input / audio | log, settings | log 经全局链;settings 经 `bind_settings()` 注入 |
| res | log, ticker | log 经全局链;ticker 经 `bind_ticker()` 注入 |
| KitStateMachine / KitState | **无(零依赖类库)** | — |

两条纪律:

1. **诊断日志分两级**:初始化期(自身 `_ready` 内)只用引擎原生 `push_warning`/`push_error`(不依赖 CoreKit 全局绑定时序);运行期(公开 API 被调用时)用 `CoreKit.log.*`。
2. **跨子系统引用只能走上表**,新增依赖必须先改本表。`bind_*` 注入使子系统可脱离 CoreKit 单测(未 bind 时相关能力静默降级:不持久化/无分帧通道,用 `if _settings != null` 类守卫)。

---

## 老系统迁移(v0.3.0 → v0.4.0 破坏性变更)

五个老系统**文件原地不动**,迁移只改三处:

1. **内部互引**:`scene_manager.gd` / `object_pool.gd` / `save_manager.gd` 里的 `Log.xxx(...)` 全部改为 `CoreKit.log.xxx(...)`(log.gd / event_bus.gd 零依赖,无需改)。
2. **注册**:`plugin.gd` 的 `AUTOLOADS` 从 6 项缩为 1 项 `["CoreKit", "res://addons/godot-core-kit/core_kit.gd"]`;`project.godot` `[autoload]` 同步只留 `CoreKit`(`_mcp_game_helper` 是 godot-ai 开发工具,不动)。
3. **调用方**:五份既有测试(`test_log` / `test_event_bus` / `test_scene_manager` / `test_object_pool` / `test_save_manager`)与 `demo/demo.gd` 里的全局名调用改门面调用。测试仍沿用"运行时 `load()` 直接实例化脚本"的模式(不经门面拿实例),只有原先依赖 `Log` autoload 的路径改为依赖 `CoreKit` autoload(dev 工程已注册,`-s` 模式下可用,与 v0.3.0 机制相同)。

**迁移完成标准:老五件测试 5/5 全绿 + demo 冒烟无报错。** README 加"0.3.x → 0.4.0 迁移"一节(全局名 → 门面属性对照表;消费方需手动从项目设置删除旧的 6 项 autoload、只留插件注册的 `CoreKit`)。

裁剪策略:v0.4.0 全部构造(每个子系统空载开销可忽略);按模块禁用留待有真实需求再做(YAGNI)。

---

## Web-export considerations(全局)

- 全部子系统维持既有约束:纯 GDScript、无 GDExtension、无桌面专属 API;唯一的平台分叉在 ResourceManager(线程可用性探测,见其 spec)。
- 门面本身零平台分叉:构造 + 属性 + 两个 `bind_*` 调用,全同步。

---

## 测试计划(门面与迁移部分)

`test/test_core_kit.gd`(headless 断言,新增):

1. `CoreKit` autoload 存在且 `VERSION == "0.4.0"`。
2. 十个门面属性全部非 null 且类型正确(`log is LogScript` 等,逐一断言)。
3. 子节点顺序与构造顺序一致(`get_child(0)` 是 log 实例……以此保证 `_ready` 触发序可复现)。
4. 接线生效:`CoreKit.input._settings == CoreKit.settings`、`CoreKit.audio._settings == CoreKit.settings`、`CoreKit.res._ticker == CoreKit.ticker`。
5. 老 API 经门面可用冒烟:`CoreKit.bus.publish` / `CoreKit.saves._decode` 各一条最小断言。

注意:本测试依赖 `CoreKit` autoload 本身(而非直接实例化脚本)——它测的就是接线。沿用 `-s` 避坑手册:`_initialize()` 内运行时取 `root.get_node("/root/CoreKit")` 或直接引用 `CoreKit` 全局(autoload 此时已注册)。

---

## 执行编排(一个分支一次 v0.4.0)

```
串行 Task 1   门面迁移(core_kit.gd 门面化 + 老五件互引/注册/测试/demo 迁移)
              ↓ 迁移完成标准达成后
并行 波 1     Settings ∥ FrameScheduler ∥ KitStateMachine   (互不依赖,只依赖已迁移的门面)
              ↓ 三者合入后
并行 波 2     InputManager ∥ AudioManager ∥ ResourceManager (依赖波 1 的 settings/ticker)
              ↓ 三者合入后
串行 集成     core_kit.gd 补 6 个 preload/属性/构造/bind + demo 重写 + README + plugin.cfg 0.4.0
              ↓
opus 终审 → 修复 → 复验(10 份测试全绿 + demo 冒烟)→ ff 合入 main
```

波 1/波 2 的每个子系统任务交付:子系统 `.gd` 文件 + 独立 headless 测试(直接实例化,不等门面接线)。门面属性接线统一留给集成任务——避免三个并行 implementer 同时改 `core_kit.gd` 冲突。

---

## 版本

v0.4.0:CoreKit 门面(唯一 autoload,10 个子系统短属性名);新增 Settings / FrameScheduler / KitStateMachine / InputManager / AudioManager / ResourceManager;老五件 API 迁移至门面(破坏性变更,README 含迁移表)。
