# godot-core-kit 架构总纲

面向 2D 游戏的 Godot 4 GDScript 底层框架。一个 autoload 门面 `CoreKit` 统管 15 个子系统,外加状态机与服务容器(KitContext)两套 off-facade 类库。

## 门面模式(CoreKit facade)

`core_kit.gd`(`extends Node`)是**唯一注册的 autoload**,名为 `CoreKit`。它在 `_init` 里按依赖序 `new()` + `add_child()` 构造全部 15 个子系统,并以短属性名暴露:

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
| `CoreKit.i18n` | LocaleManager 本地化 | `systems/locale_manager.gd` |
| `CoreKit.layers` | LayerManager 层级(跨场景常驻具名 CanvasLayer) | `systems/layer_manager.gd` |
| `CoreKit.clock` | GameClock 游戏时钟/日历 | `systems/game_clock.gd` |
| `CoreKit.updater` | PackUpdater 内容包下载/校验/挂载(分包瘦身+热更) | `systems/pack_updater.gd` |

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
  ui/                    class_name 可复用 UI 组件(重绑定 + 栈导航,off-facade)
  transitions/           class_name 可复用转场资源(KitTransition,off-facade)
  inventory/             class_name 槽位制物品容器(KitInventory,off-facade)
  data/                  class_name 定义数据表(KitDataRegistry,off-facade)
  offline/               class_name 离线结算器(KitOffline,off-facade)
  modifiers/             class_name 数值修正器栈(KitModifiers,off-facade)
  stats/                 class_name 统计计数器(KitStats,off-facade)
  achievements/          class_name 成就引擎 + AchievementDef schema(KitAchievements,off-facade)
  tools/                 构建期工具(KitPackManifest 导出管线 + build_manifest CLI,非运行时)
  docs/                  本文档目录
```

分层原则:`core/` 是低层设施(日志、事件、偏好),`systems/` 依赖 `core/` 但 `core/` 不反向依赖 `systems/`。

## 构造顺序与生命周期

`_init` 里的构造序(= 子节点树顺序 = `_ready` 触发顺序,子先于父):

```
log → settings → bus → scenes → pool → saves → ticker → input → audio → res → console → i18n → layers → clock → updater
```

`log` 最先构造,故任何子系统在自己的生命周期里都能用 `CoreKit.log`。

**例外:`updater`(PackUpdater)是唯一在 `_init` 就执行工作的子系统**——它在构造后立即调用 `mount_installed()`(相 A),把已下载的内容包 `load_resource_pack` 挂进 `res://`。这必须先于任何游戏内容被 `preload`/`load`(引擎缓存一旦命中就拿不到新包),而 `CoreKit._init()`(早于其它 autoload 与主场景)正是那个时刻——「尽早挂包」的时机由此被编码进结构,接入方无从搞错。**代价:`CoreKit` autoload 必须注册在任何加载游戏内容的 autoload 之前。**

子节点全部 `_ready` 完毕后,门面自己的 `_ready` 执行**唯一的跨子系统接线点**:

```gdscript
func _ready() -> void:
    input.bind_settings(settings)   # 输入重绑定持久化到 Settings
    audio.bind_settings(settings)   # 音量持久化到 Settings
    res.bind_ticker(ticker)         # 资源分帧通道复用 FrameScheduler
    scenes.bind_resources(res)      # 场景切换 preload 选项经 ResourceManager 预载
    console.bind_core(self)         # 注入门面:求值 base + 日志 overlay 源
    i18n.bind_settings(settings)    # 本地化:恢复并持久化 locale
    log.info("CoreKit v%s ready" % VERSION)
```

## 依赖纪律

- **子系统间不得互相 `preload`/按名硬引用**。跨子系统协作只有两条合法通道:
  1. 门面在 `_ready` 里的 `bind_*(...)` 注入(依赖方持有被依赖方的引用)。
  2. `CoreKit.log` 全局日志链(所有子系统都可用)。
- **诊断分层**:初始化期(`_init`/`_ready`,此时 `CoreKit.log` 未必就绪)用引擎原生 `push_warning`/`push_error`;运行期用 `CoreKit.log.*`。
- 当前经 `bind_*` 建立的依赖:`input → settings`、`audio → settings`、`res → ticker`、`console → core`(门面自身,注入求值 base + 日志源)、`i18n → settings`(持久化 locale)。其余子系统零跨系统依赖。
- `ui/`(`KitRebindButton`/`KitRebindList`)是 off-facade 可复用 UI 组件(如 `state_machine/`、`di/`),消费 `CoreKit.input`(默认,可注入),不接门面、不计入 15 子系统。
- `transitions/`(`KitTransition`)是 off-facade 可复用转场资源(`extends Resource`,零依赖),由 `SceneManager` 消费驱动遮罩;不接门面、不计入 15 子系统。
- `ui/` 另有 `KitUiStack`/`KitUiScreen`(UI 栈导航,零依赖);`KitUiScreen.stack` 不标注 `KitUiStack` 类型(单向类型引用,破 `class_name` 循环引用),被盖屏 `process_mode=DISABLED` 停用;不接门面、不计入 15 子系统。

- `CoreKit.layers`(`LayerManager`,第 13 子系统)零跨系统依赖;它把 `console`(128)/`transition`(4096)层号定义为权威保留带常量,但 **document-only**——DevConsole/SceneManager 保留字面量、仅注释交叉引用,不反向依赖本管理器。
- `CoreKit.clock`(`GameClock`,第 14 子系统)仅依赖 EventBus,经 `bind_bus` 注入(在 `_ready` 接线);未绑定 bus 时只发原生 signal、`clock:*` 广播静默跳过(降级)。事件遵全 kit 的 `namespace:event` 命名约定(见 core/event-bus.md)。
- `CoreKit.updater`(`PackUpdater`,第 15 子系统)零跨系统依赖;两个可注入接缝(传输 `HttpPackTransport` / 挂载 `ProjectSettings.load_resource_pack`)是**子系统内部**的适配点,不违反子系统间依赖纪律。相 A 的 `mount_installed()` 在 `_init` 执行(见构造顺序节的例外),故其结果只能查询(`mounted_packs`/`mount_errors`/`local_version`),不用信号——挂载发生时游戏代码尚未运行,信号无人接收。相 B(`check`/`download`/`restart_to_apply`)在运行期才用信号。状态文件 `user://kit_updater/state.json` 由本子系统自读写(不走 `CoreKit.saves`:跨子系统接线只能在 `_ready`,对 `_init` 的挂载太晚)。含 GDScript 逻辑的包换逻辑**必须重启进程**(实测:`GDScriptCache` 不可运行时逐出),故 `restart_to_apply()` 是唯一的「生效屏障」;详见 [systems/pack-updater.md](systems/pack-updater.md)。

## 扩展容器(KitContext / DI)

`CoreKit` 除 15 个内置子系统外,还提供一个**对外开放的服务定位器**,让游戏代码注册自己的服务:

- **全局根**:`CoreKit.provide(key, svc)` / `service(key)` / `has(key)` / `service_or(key, fallback)`。15 个内置已按属性名预注册(`service("audio") == CoreKit.audio`),但内置首选仍走强类型属性。`provide` 拒绝覆盖内置保留键。
- **作用域容器** `KitContext`(`class_name`,挂在场景树节点上):`provide` / `provide_child` / `service`。解析沿祖先链向上回退、树顶兜底全局根;子层可 shadow;生命周期随节点(`NOTIFICATION_PREDELETE` 清表,`provide_child` 的子节点连带释放)。静态 `KitContext.of(node)` / `resolve(node, key)` 供非容器节点解析。
- 依赖方向:`KitContext → CoreKit` 单向(仅树顶兜底 duck-typed 调用),属"全局链"合法通道,不违反子系统依赖纪律。
- 详见 [di/kit-context.md](di/kit-context.md)。

## 已知引擎坑

- **命名遮蔽**:属性 `CoreKit.log` 遮蔽全局函数 `log()`(数学对数)。门面与子系统内部不需要 `log()`,无影响;若你在自己脚本里既要日志又要 `log()`,注意作用域。
- **headless `-s` 时序**:自定义 `SceneTree` 脚本的 `_initialize()` 在主循环开始前执行,此时 `root` 尚未真正入树,`root.add_child()` 不会同步触发子树 `NOTIFICATION_READY`。测试里每次 `add_child` 后需 `await process_frame` 补一帧。详见 `test/test_state_machine.gd` 头注释。
- **`class_name` 缓存**:引用 `KitStateMachine`/`KitState` 的脚本,首次须先跑一次 `godot --headless --path . --import` 生成全局类缓存,否则编译解析不到。
- **JSON int→float**:Settings/SaveManager 经 JSON 落盘,int 往返会变 float,取整用 `int(...)`。

## 测试

全部子系统有 headless 断言测试(`test/test_*.gd`,`extends SceneTree`,打印 `ALL PASS` + `quit(0/1)`)。一键全量:`powershell -File test\run_all.ps1`(import → 31 测试 → demo 冒烟,末行 `FAILS=0` 为全绿)。

## 版本

当前 `0.27.0`(`plugin.cfg` 与 `CoreKit.VERSION` 同源)。0.26.0→0.27.0 场景补强:`change_scene` 增第 3 参 `options`(`preload` 经 `CoreKit.res` 预载直接依赖 + `scene_load_progress` + `loading_screen` 插槽 + `before_swap`/`after_swap` 黑屏钩子)、`reload_scene`、同场景黑屏 `cover`/`reveal`;`SceneManager` 新增 `bind_resources(res)` 接线;`KitTransition` 新增 MASK 灰度遮罩转场(`transitions/kit_mask.gdshader`);MASK 与带预载的切换已在微信开发者工具实测;新增 `test_scene_flow`,run_all 30→31。0.25.0→0.26.0 音频补强:UI 通道 `play_ui_sfx` + 单层环境音 `play_ambient`(UI/Ambient 总线 send 到 SFX)、`play_sfx` 返回句柄 + `stop_sfx`/`stop_all_sfx`、音乐查询与 `from_position`;**行为变更**:暂停时 BGM 继续播,`pause_music_with_tree = true` 恢复旧行为;run_all 测数不变,仍 30。0.24.4→0.25.0 输入补强:`InputManager` 绑定按设备分槽(修复改键盘键清掉手柄绑定、改过的手柄键只认 0 号手柄两个 bug)+ 手柄品牌识别 / 按键图标键名 / 统一震动,`KitRebindButton` 按槽 + `SWAP`,`KitRebindList` 两列;新增 `test_input_joypad`,run_all 29→30。0.24.3→0.24.4 内容包下载失败原因中文化(`HttpPackTransport.describe_failure`)。0.24.2→0.24.3 修复 **web/微信小游戏下 temp+rename 原子写丢内容**(纯 bugfix、桌面路径逐字节不变):微信小游戏的 `user://` 是 weapp-adapter FS shim,`DirAccess.rename_absolute` **返回 `OK` 且目标文件 `file_exists` 为真,但内容是空的**——DevTools 探针实测(直写 11 字节 `get_length`/静态整读都是 11 且文本正确;经 rename 后同一内容变 0 字节),于是 `SaveManager.save()` 一路成功返回 `true` 而存进去的字节全丢,表现为 `save=true` 但 `load={}`。修法:`SaveManager.save` 与 `PackUpdater._write_state_atomic` 在 `OS.has_feature("web")` 时直写目标(web 无多进程并发写,原子替换本就没有对手),`PackUpdater._commit_staged` 改整读整写复制暂存包(保留「全部下载校验通过才提交」的暂存语义)。**同一根因波及热更**:内容包也经 rename 落地,微信下会静默产出空 `.pck`,故一并修。构建期 `tools/pack_manifest.gd` 只在桌面跑,不改。web 分支无法被 headless 门覆盖(`OS.has_feature` 不可伪造),证据是微信 DevTools 探针日志;run_all 测数不变,仍 29。0.24.1→0.24.2 健壮性修复(纯 bugfix、向后兼容):`JsonSaveSerializer.decode` 与 `Settings._decode` 改用实例式 `JSON.new().parse()` + 空/空白输入守卫,不再对空或畸形数据调静态 `JSON.parse_string`(后者失败会 `push_error` 刷引擎级 ERROR)。微信小游戏(kit spike DevTools 实测)下 `user://` 读回空存档文件时,原会刷 `JSON.parse_string("")` 的红色 `Error at line 0` console.error;修后 `load`/Settings 静默返回 `{}` 降级、无引擎报错。`test_save_manager` 增真·空字节断言(run_all 测数不变,仍 29)。0.24.0→0.24.1 修复 `HttpPackTransport` 在 **Web/HTML5** 上的内容包下载缺陷:`HTTPRequest.download_file` 在浏览器里 request 报成功/200 但字节不真正落进 `user://`(IDBFS)→ 随后 sha256 校验失败、永远到不了 `ready_to_apply`;Web 改「`body` 收内存 → `FileAccess.store_buffer` 落盘」(桌面/移动仍走 `download_file` 流式落盘,大包省内存),抽出 `_store_body_to_file` 由新增 `test_http_pack_transport` 覆盖(run_all 28→29),fortune-mill 真实扭蛋内容包的 Web OTA 已 headless 浏览器端到端实测通过(研究文档 §7c)。纯 bugfix、向后兼容。0.23.0→0.24.0 新增**导出管线**构建工具 `KitPackManifest`(`tools/pack_manifest.gd`,`class_name` / `RefCounted`,构建期工具、不接门面、不进构造链、运行时不实例化):读 `--export-pack` 导出的 `.pck` 算 `size`+`sha256` + 戳引擎版本,产出 `CoreKit.updater.check()` 逐字消费的 `manifest.json`(`build`/`validate`/`write_manifest`);配 headless CLI `tools/build_manifest.gd`(读 `spec.json` 组装 url)+ 编排脚本模板 `tools/export_packs.example.ps1` + 文档 `docs/tools/export-pipeline.md`。prototype 实测坐实 `--export-pack` 可手搓「薄壳 base(`scenes` filter)+ 内容包(`exclude` filter)」、内容包挂进空进程即可执行(`proto/export-pipeline` 存证)。测试 `test_pack_manifest`(含 `sha256("abc")` 已知向量 + 与 `updater` 的握手测),run_all 27→28。纯增量、向后兼容。0.22.0→0.23.0 新增门面第 15 子系统 `CoreKit.updater`(`systems/pack_updater.gd`,`extends Node`):内容包下载/校验/挂载机制(分包瘦身 + 热更)。**相 A**(启动期)在 `_init` 调 `mount_installed()` 尽早 `load_resource_pack` 挂载已安装包——按 `order`、引擎版本闸门、失败隔离进 `mount_errors`,结果只可查询(`mounted_packs`/`local_version`)不用信号。**相 B**(运行期)三动词 `check(manifest_url)` → `download(plan)` → `restart_to_apply()`,配 `update_available`/`ready_to_apply`/`download_failed` 等信号;原子暂存(全部 sha256 校验通过才 temp+rename 改写 `state.json`)+ 引擎版本严格校验。两个可注入接缝:传输(`HttpPackTransport`)与挂载。实测证明含 GDScript 逻辑的包换逻辑**必须重启进程**(`GDScriptCache` 独立于 `ResourceCache` 且不可运行时逐出,`docs/research/2026-07-23-godot-hot-update-feasibility.md` §4b)。首轮仅机制;导出管线、fortune-mill 真机 OTA、Web 验证、Android 自重启真机验证排后续轮次。纯增量、向后兼容。0.21.0→0.22.0 给 SaveManager 叠加版本迁移链(`save_manager.gd` 增量):信封 `_version` 记写档数据版本,`set_data_version` 声明当前版本 + `register_migration(from,fn)` 注册 `v(n)→v(n+1)` 迁移函数,`load` 时低版本存档按序跑迁移链逐级升级,缺迁移函数/迁移返回非字典/未来版本 → `load_failed`+`migration_failed` 返回 `{}`(保底新档不静默覆盖旧文件),默认 `data_version=1` 无注册时逐字节向后兼容,纯增量、向后兼容。0.20.0→0.21.0 新增两个 off-facade 类库 `KitStats`(`stats/`)+ `KitAchievements`(`achievements/`)+ `AchievementDef`(`achievements/`,`extends Resource`):统计计数器 + 数据驱动阈值成就(`evaluate` 达阈值即解锁 + 去重 + Steam sink 预留),零依赖不接门面,纯增量、向后兼容。0.19.0→0.20.0 新增 off-facade 数值修正器栈 `KitModifiers`(`modifiers/`,`extends RefCounted`):每量=一个 target,升级/道具/协同=带 `source_id` 的加法/乘法层修正,脏标缓存惰性重算 + `breakdown` 明细,取代散落的 `total*=x`,零依赖不接门面,纯增量、向后兼容。0.18.0→0.19.0 新增 off-facade 离线结算器 `KitOffline`(`offline/`,`extends RefCounted` 纯静态 settle):墙钟差×产率、封顶 8h、时间回拨按 0 防作弊,零依赖不接门面,纯增量、向后兼容。0.17.0→0.18.0 dogfood(examples/farm-sim 消费者视角)驱动的向后兼容便利方法,不接门面、纯增量:`KitDataRegistry.ids/types` 加 `sorted` 可选参数(按字符串字典序,规避 StringName 数组原生 sort 按指针地址的坑)、`KitInventory.totals()`(跨格按 id 聚合为 `{id:总数}`,免手动遍历 slot)、`KitStateMachine.state_name()`/`is_in(query)`(当前态查询,null 安全,免写 `String(current_state.name)`+守卫)。0.16.0→0.17.0 新增 off-facade 定义数据表 `KitDataRegistry`(`data/`,`extends RefCounted`):type→{id→def} 分组存放游戏自定义 Resource,register + load_dir(扫目录,id 取属性或文件名,剥 .remap),get_def/has_def/all/ids/types/count/clear,零依赖不参与存档,纯增量、向后兼容。0.15.0→0.16.0 新增 off-facade 槽位制物品容器 `KitInventory`(`inventory/`,`extends RefCounted`):固定 capacity 格,add 自动堆叠+填空+溢出返余量,move 空移/合并/交换,per-slot data 分品质,`changed` 信号,to_dict/from_dict,零依赖不接门面,纯增量、向后兼容。0.14.0→0.15.0 新增门面第 14 子系统 `CoreKit.clock`(`systems/game_clock.gd`,`extends Node`):年/季/日/时/分 世界时钟,混合推进(time_scale 自动走时 + advance_minutes/day + sleep_to_next_day)+ 原生 signal + `CoreKit.bus` 广播 `clock:*`(bind_bus 注入,未绑定降级)+ to_dict/from_dict,确立全 kit 事件命名约定 `namespace:event`(冒号),打破 13→14 子系统,纯增量、向后兼容。0.13.0→0.14.0 新增门面第 13 子系统 `CoreKit.layers`(`systems/layer_manager.gd`,`extends Node`):跨场景常驻具名 `CanvasLayer` + z 序权威表(`HUD=10`..`SYSTEM=60` + 保留带 `CONSOLE=128`/`TRANSITION=4096`),`layer`/`mount`/`clear`/`register_layer`;console/transition 只登记不重构(各加一行交叉引用注释),打破 12→13 子系统,纯增量、向后兼容。0.12.0→0.13.0 新增 off-facade UI 栈导航 `KitUiStack` + `KitUiScreen`(`ui/`):push/pop/replace/clear、被盖屏 `process_mode=DISABLED` 停用、模态自动挡层、返回键 `_unhandled_input` 兜底,不接门面、纯增量、向后兼容。0.11.0→0.12.0 新增 off-facade 可复用转场资源 `KitTransition`(`transitions/`,`extends Resource`):数据驱动的 FADE/SLIDE 转场,`SceneManager.change_scene` 兼容接收 `KitTransition` 或 legacy 字典,`_merge_options`/`enum Transition` 保留,纯增量、向后兼容。0.10.0→0.11.0 新增 off-facade 重绑定 UI 组件(`KitRebindButton`/`KitRebindList`,`ui/`):点击捕获 + 检测拦截冲突 + 复位;`InputManager` 增 `action_for_event` 冲突查询;不接门面、纯增量、向后兼容。0.9.0→0.10.0 新增 LocaleManager 本地化托管层(`CoreKit.i18n` 第 12 子系统):运行时切语言 + 持久化(Settings section `locale`)+ 按 locale 换绑定 Theme 字体 + 缺翻译 `push_warning` 告警 + 运行时翻译加载,零门面耦合、纯增量、向后兼容;0.8.0→0.9.0 新增 DevConsole 调试控制台(`CoreKit.console` 第 11 子系统,CanvasLayer,debug 门控:日志 overlay + 命令/作弊注册 + GDScript 表达式执行 + 变量 watch),纯增量、向后兼容;0.7.0→0.8.0 给 KitStateMachine 叠加事件 dispatch 解耦(`add_transition`/`dispatch` + `ANYSTATE` 通配,与 `transition_to` 并存)与 pushdown 栈(`push_state`/`pop_state`,暂停语义 + `KitState.pause`/`resume` 钩子),纯增量、向后兼容;0.6.0→0.7.0 给 SaveManager 叠加可插拔序列化(`SaveSerializer` 基类 + 默认 `JsonSaveSerializer`,逐字节兼容旧 `.json`)、原子写(temp+rename)、资源引用安全守卫(拒 Object/Callable/Signal/RID),纯增量、向后兼容;0.5.0→0.6.0 给 KitContext 叠加订阅式解析(`subscribe`)与工厂式 scope(`provide_factory`,SINGLETON/TRANSIENT),纯增量、向后兼容;0.4.1→0.5.0 新增 KitContext 服务容器(纯增量,对既有 API 无破坏);0.3.x→0.4.0 是破坏性变更(五个老全局单例名下线,统一走 `CoreKit` 门面);0.4.1 为纯目录重排。
