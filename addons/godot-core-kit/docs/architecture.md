# godot-core-kit 架构总纲

面向 2D 游戏的 Godot 4 GDScript 底层框架。一个 autoload 门面 `CoreKit` 统管 11 个子系统,外加状态机与服务容器(KitContext)两套 off-facade 类库。

## 门面模式(CoreKit facade)

`core_kit.gd`(`extends Node`)是**唯一注册的 autoload**,名为 `CoreKit`。它在 `_init` 里按依赖序 `new()` + `add_child()` 构造全部 11 个子系统,并以短属性名暴露:

| 属性 | 子系统 | 目录 |
|---|---|---|
| `CoreKit.log` | Log 日志 | `core/log.gd` |
| `CoreKit.settings` | Settings 偏好 | `core/settings.gd` |
| `CoreKit.bus` | EventBus 事件总线 | `core/event_bus.gd` |
| `CoreKit.scenes` | SceneManager 场景切换 | `systems/scene_manager.gd` |
| `CoreKit.pool` | ObjectPool 对象池 | `systems/object_pool.gd` |
| `CoreKit.saves` | SaveManager 存档 | `systems/save_manager.gd` |
| `CoreKit.ticker` | FrameScheduler 帧分频器 | `systems/frame_scheduler.gd` |
| `CoreKit.input` | InputManager 输入 | `systems/input_manager.gd` |
| `CoreKit.audio` | AudioManager 音频 | `systems/audio_manager.gd` |
| `CoreKit.res` | ResourceManager 资源 | `systems/resource_manager.gd` |
| `CoreKit.console` | DevConsole 调试控制台(UI,dev 门控) | `console/dev_console.gd` |

各子系统仍是各自独立的脚本与 `Node`(保留自己的 `_process` 与信号),门面只负责构造、编排顺序、暴露引用。消费方永远经 `CoreKit.<x>` 访问,没有单独的全局单例名。

`KitStateMachine` / `KitState` **不在门面上**——它们是 `class_name` 类库,每个实体自己 `new()` 一台,见 [state-machine.md](state-machine.md)。

## 目录布局

```
addons/godot-core-kit/
  core_kit.gd            门面 = autoload 根节点
  plugin.gd / plugin.cfg 编辑器插件(注册 CoreKit autoload)
  core/                  根基设施(被 systems 依赖)
  systems/               面向玩法的业务子系统
  state_machine/         class_name 状态机类库
  di/                    class_name 服务容器类库(KitContext)
  console/               DevConsole 调试控制台(CanvasLayer 子系统)
  docs/                  本文档目录
```

分层原则:`core/` 是低层设施(日志、事件、偏好),`systems/` 依赖 `core/` 但 `core/` 不反向依赖 `systems/`。

## 构造顺序与生命周期

`_init` 里的构造序(= 子节点树顺序 = `_ready` 触发顺序,子先于父):

```
log → settings → bus → scenes → pool → saves → ticker → input → audio → res → console
```

`log` 最先构造,故任何子系统在自己的生命周期里都能用 `CoreKit.log`。子节点全部 `_ready` 完毕后,门面自己的 `_ready` 执行**唯一的跨子系统接线点**:

```gdscript
func _ready() -> void:
    input.bind_settings(settings)   # 输入重绑定持久化到 Settings
    audio.bind_settings(settings)   # 音量持久化到 Settings
    res.bind_ticker(ticker)         # 资源分帧通道复用 FrameScheduler
    console.bind_core(self)         # 注入门面:求值 base + 日志 overlay 源
    log.info("CoreKit v%s ready" % VERSION)
```

## 依赖纪律

- **子系统间不得互相 `preload`/按名硬引用**。跨子系统协作只有两条合法通道:
  1. 门面在 `_ready` 里的 `bind_*(...)` 注入(依赖方持有被依赖方的引用)。
  2. `CoreKit.log` 全局日志链(所有子系统都可用)。
- **诊断分层**:初始化期(`_init`/`_ready`,此时 `CoreKit.log` 未必就绪)用引擎原生 `push_warning`/`push_error`;运行期用 `CoreKit.log.*`。
- 当前经 `bind_*` 建立的依赖:`input → settings`、`audio → settings`、`res → ticker`、`console → core`(门面自身,注入求值 base + 日志源)。其余子系统零跨系统依赖。

## 扩展容器(KitContext / DI)

`CoreKit` 除 11 个内置子系统外,还提供一个**对外开放的服务定位器**,让游戏代码注册自己的服务:

- **全局根**:`CoreKit.provide(key, svc)` / `service(key)` / `has(key)` / `service_or(key, fallback)`。11 个内置已按属性名预注册(`service("audio") == CoreKit.audio`),但内置首选仍走强类型属性。`provide` 拒绝覆盖内置保留键。
- **作用域容器** `KitContext`(`class_name`,挂在场景树节点上):`provide` / `provide_child` / `service`。解析沿祖先链向上回退、树顶兜底全局根;子层可 shadow;生命周期随节点(`NOTIFICATION_PREDELETE` 清表,`provide_child` 的子节点连带释放)。静态 `KitContext.of(node)` / `resolve(node, key)` 供非容器节点解析。
- 依赖方向:`KitContext → CoreKit` 单向(仅树顶兜底 duck-typed 调用),属"全局链"合法通道,不违反子系统依赖纪律。
- 详见 [di/kit-context.md](di/kit-context.md)。

## 已知引擎坑

- **命名遮蔽**:属性 `CoreKit.log` 遮蔽全局函数 `log()`(数学对数)。门面与子系统内部不需要 `log()`,无影响;若你在自己脚本里既要日志又要 `log()`,注意作用域。
- **headless `-s` 时序**:自定义 `SceneTree` 脚本的 `_initialize()` 在主循环开始前执行,此时 `root` 尚未真正入树,`root.add_child()` 不会同步触发子树 `NOTIFICATION_READY`。测试里每次 `add_child` 后需 `await process_frame` 补一帧。详见 `test/test_state_machine.gd` 头注释。
- **`class_name` 缓存**:引用 `KitStateMachine`/`KitState` 的脚本,首次须先跑一次 `godot --headless --path . --import` 生成全局类缓存,否则编译解析不到。
- **JSON int→float**:Settings/SaveManager 经 JSON 落盘,int 往返会变 float,取整用 `int(...)`。

## 测试

全部子系统有 headless 断言测试(`test/test_*.gd`,`extends SceneTree`,打印 `ALL PASS` + `quit(0/1)`)。一键全量:`powershell -File test\run_all.ps1`(import → 14 测试 → demo 冒烟,末行 `FAILS=0` 为全绿)。

## 版本

当前 `0.9.0`(`plugin.cfg` 与 `CoreKit.VERSION` 同源)。0.8.0→0.9.0 新增 DevConsole 调试控制台(`CoreKit.console` 第 11 子系统,CanvasLayer,debug 门控:日志 overlay + 命令/作弊注册 + GDScript 表达式执行 + 变量 watch),纯增量、向后兼容;0.7.0→0.8.0 给 KitStateMachine 叠加事件 dispatch 解耦(`add_transition`/`dispatch` + `ANYSTATE` 通配,与 `transition_to` 并存)与 pushdown 栈(`push_state`/`pop_state`,暂停语义 + `KitState.pause`/`resume` 钩子),纯增量、向后兼容;0.6.0→0.7.0 给 SaveManager 叠加可插拔序列化(`SaveSerializer` 基类 + 默认 `JsonSaveSerializer`,逐字节兼容旧 `.json`)、原子写(temp+rename)、资源引用安全守卫(拒 Object/Callable/Signal/RID),纯增量、向后兼容;0.5.0→0.6.0 给 KitContext 叠加订阅式解析(`subscribe`)与工厂式 scope(`provide_factory`,SINGLETON/TRANSIENT),纯增量、向后兼容;0.4.1→0.5.0 新增 KitContext 服务容器(纯增量,对既有 API 无破坏);0.3.x→0.4.0 是破坏性变更(五个老全局单例名下线,统一走 `CoreKit` 门面);0.4.1 为纯目录重排。
