# godot-core-kit

通用 2D 游戏开发底层框架(Godot 4.7,纯 GDScript,Web 导出兼容)。单一 autoload 门面 `CoreKit` 暴露全部子系统;`KitStateMachine`/`KitState`、`KitContext` 以 class_name 类库随插件分发。

## 安装

1. 把 `addons/godot-core-kit/` 复制进目标工程;
2. 项目设置 → 插件 → 启用 godot-core-kit(自动注册唯一 autoload `CoreKit`)。

## 文档

详细架构、每个子系统的 API 与用法示例都在 **[`addons/godot-core-kit/docs/`](addons/godot-core-kit/docs/README.md)**(随插件分发)。第一次接触先读 [架构总纲](addons/godot-core-kit/docs/architecture.md) —— 门面模式、初始化顺序、依赖纪律、引擎坑。

按子系统查(每篇五段式:职责 / 公开 API / 依赖 / 用法示例 / 注意事项):

| 门面属性 | 子系统 | 文档 |
|---|---|---|
| `CoreKit.log` | 分级日志 | [log](addons/godot-core-kit/docs/core/log.md) |
| `CoreKit.bus` | 事件总线 pub/sub | [event-bus](addons/godot-core-kit/docs/core/event-bus.md) |
| `CoreKit.settings` | 玩家偏好落盘 | [settings](addons/godot-core-kit/docs/core/settings.md) |
| `CoreKit.scenes` | 场景切换 | [scene-manager](addons/godot-core-kit/docs/systems/scene-manager.md) |
| `CoreKit.pool` | 对象池 | [object-pool](addons/godot-core-kit/docs/systems/object-pool.md) |
| `CoreKit.saves` | 存档槽 | [save-manager](addons/godot-core-kit/docs/systems/save-manager.md) |
| `CoreKit.ticker` | 帧分频 tick + 预算队列 | [frame-scheduler](addons/godot-core-kit/docs/systems/frame-scheduler.md) |
| `CoreKit.input` | 键位重绑定 + 输入缓冲 | [input-manager](addons/godot-core-kit/docs/systems/input-manager.md) |
| `CoreKit.audio` | 音量 + BGM 淡切 + SFX 池 | [audio-manager](addons/godot-core-kit/docs/systems/audio-manager.md) |
| `CoreKit.res` | 异步预加载 + 缓存 | [resource-manager](addons/godot-core-kit/docs/systems/resource-manager.md) |
| `CoreKit.console` | 运行时调试控制台(dev) | [console](addons/godot-core-kit/docs/console.md) |
| `CoreKit.i18n` | 本地化(i18n) | [i18n](addons/godot-core-kit/docs/systems/i18n.md) |
| `CoreKit.layers` | 跨场景常驻具名层 | [layer-manager](addons/godot-core-kit/docs/systems/layer-manager.md) |
| `CoreKit.clock` | 游戏时钟/日历(混合推进 + bus 广播) | [game-clock](addons/godot-core-kit/docs/systems/game-clock.md) |
| `CoreKit.updater` | 内容包下载/校验/挂载(分包瘦身 + 热更) | [pack-updater](addons/godot-core-kit/docs/systems/pack-updater.md) |
| `KitStateMachine`(类库) | Node 型状态机 | [state-machine](addons/godot-core-kit/docs/state-machine.md) |
| `KitContext`(类库) | 节点绑定的层级服务容器(DI) | [kit-context](addons/godot-core-kit/docs/di/kit-context.md) |
| `KitRebindButton`/`KitRebindList`(类库) | 键位重绑定 UI 组件 | [rebind](addons/godot-core-kit/docs/ui/rebind.md) |
| `KitTransition`(类库) | 可复用场景转场资源 | [kit-transition](addons/godot-core-kit/docs/transitions/kit-transition.md) |
| `KitUiStack`/`KitUiScreen`(类库) | UI 屏栈导航 | [ui-stack](addons/godot-core-kit/docs/ui/ui-stack.md) |
| `KitInventory`(类库) | 槽位制物品容器 | [kit-inventory](addons/godot-core-kit/docs/inventory/kit-inventory.md) |
| `KitDataRegistry`(类库) | 定义数据表(作物/物品/配方) | [kit-data-registry](addons/godot-core-kit/docs/data/kit-data-registry.md) |
| `KitOffline`(类库) | 离线结算(墙钟差×产率,封顶+防回拨) | [kit-offline](addons/godot-core-kit/docs/offline/kit-offline.md) |
| `KitModifiers`(类库) | 数值修正器栈((base+Σadd)×Πmul) | [kit-modifiers](addons/godot-core-kit/docs/modifiers/kit-modifiers.md) |
| `KitStats`(类库) | 统计计数器(生涯计数,存档) | [kit-stats](addons/godot-core-kit/docs/stats/kit-stats.md) |
| `KitAchievements`/`AchievementDef`(类库) | 成就引擎(数据驱动阈值判定 + 去重) | [kit-achievements](addons/godot-core-kit/docs/achievements/kit-achievements.md) |

## 从 0.3.x 升级(破坏性)

v0.4.0 起只保留一个 autoload `CoreKit`,老全局单例名全部下线:`Log.` → `CoreKit.log.`、`EventBus.` → `CoreKit.bus.`、`SceneManager.` → `CoreKit.scenes.`、`ObjectPool.` → `CoreKit.pool.`、`SaveManager.` → `CoreKit.saves.`。升级步骤:项目设置里删掉这五个旧 autoload、只留 `CoreKit`,再按上表全局替换调用点。

## 测试

```
godot --headless --path . --import      # 首次:生成 class_name 缓存
powershell -File test\run_all.ps1       # 一键全量,末行 FAILS=0 为全绿
```

细节见 [架构总纲的「测试」段](addons/godot-core-kit/docs/architecture.md)。

## 版本

- **0.25.0** — 输入补强。**修复两个已上线的 bug**:改键盘键会把同一动作的手柄绑定一起清掉;改过的手柄键重启后只认 0 号手柄。`InputManager` 绑定改为按设备分槽(键盘鼠标 / 手柄各一槽):`rebind_action` 只替换同槽,新增 `slot_of`、`unbind_action`,`get_action_event` / `reset_action` 可按槽;存档改为按槽格式(只存改过的槽,`null` 表示显式清空),旧格式照常读取、下次写入时转换;事件统一规范化成 `device=-1`。新增手柄品牌识别(`JoypadBrand` / `brand_from` / `get_joypad_brand` / `current_joypad` / `joypad_changed`)、按键图标键名 `glyph_key` / `glyph_text`(kit 不带图)、统一震动 `rumble` / `stop_rumble`(手柄优先、回退机身,`rumble_enabled` 开关持久化)。`KitRebindButton` 的 `setup` 增 `device` 按槽、增 `conflict_mode`(`BLOCK` 默认 / `SWAP` 互换),显示改用 `glyph_text`;`KitRebindList` 改键盘 / 手柄两列。新增 `test_input_joypad`(run_all 29→30)。API 向后兼容,唯一可见变化是重绑键盘键不再清掉手柄绑定。
- **0.24.3** — 修复 **web/微信小游戏下 temp+rename 原子写丢内容**:微信 `user://`(weapp-adapter FS shim)上 `DirAccess.rename_absolute` 返回 `OK`、目标文件也存在,**但字节是空的**(DevTools 探针实测:直写 11 字节可完整读回,经 rename 后变 0 字节)。后果是 `SaveManager.save()` 返回 `true` 却等于没存(`save=true` 但 `load={}`);同一根因也让 `PackUpdater` 在微信下静默产出空内容包。修法:`SaveManager.save` 与 `PackUpdater._write_state_atomic` 在 web 上直写目标(web 无多进程并发写,原子替换无对手),`PackUpdater._commit_staged` 改整读整写复制(保留暂存语义)。桌面/移动路径逐字节不变。纯 bugfix,API 无破坏。
- **0.24.2** — SaveManager/Settings 健壮性修复:`JsonSaveSerializer.decode` 与 `Settings._decode` 改用实例式 `JSON.new().parse()` + 空/空白字节守卫,不再对空或畸形输入调静态 `JSON.parse_string`(失败会 `push_error` 刷引擎级 ERROR)。微信小游戏 spike 的 DevTools 实测暴露:`user://` 读回空存档文件时原会刷红色 `Error at line 0` console.error,修后 `load` 静默返回 `{}` 降级(损坏存档本就走 `load_failed(slot,"corrupt")`)。`test_save_manager` 增真·空字节断言。纯 bugfix,API 无破坏。
- **0.24.1** — 修复 `HttpPackTransport` 在 **Web/HTML5** 上的内容包下载缺陷:`HTTPRequest.download_file` 在浏览器里 request 报成功/200 但字节不真正落进 `user://`(IDBFS)→ 随后 sha256 校验失败、永远到不了 `ready_to_apply`。Web 改「`body` 收内存 → `FileAccess.store_buffer` 落盘」(桌面/移动仍走 `download_file` 流式落盘,大包省内存);抽出 `_store_body_to_file` 由新增 `test_http_pack_transport` 覆盖。fortune-mill 真实扭蛋内容包的 Web OTA 已 headless 浏览器端到端实测通过(见 `docs/research/2026-07-23-godot-hot-update-feasibility.md` §7c)。纯 bugfix,API 无破坏。
- **0.24.0** — 新增**导出管线**构建工具 `KitPackManifest`(`tools/pack_manifest.gd`,`class_name` / `RefCounted`,构建期工具、不接门面、运行时不实例化):读 `--export-pack` 导出的 `.pck` 算 `size`+`sha256` + 戳引擎版本,产出 `CoreKit.updater.check()` 能逐字消费的 `manifest.json`(`build` / `validate` / `write_manifest`)。配 headless CLI `tools/build_manifest.gd`(读 `spec.json` 组装 url 生成 manifest)+ 编排脚本模板 `tools/export_packs.example.ps1` + 文档 [export-pipeline](addons/godot-core-kit/docs/tools/export-pipeline.md)。prototype 实测坐实 `--export-pack` 可手搓「薄壳 base(`scenes` filter)+ 内容包(`exclude` filter)」、内容包挂进空进程即可执行。纯增量,API 无破坏。
- **0.23.0** — 新增门面第 15 子系统 `CoreKit.updater`(`systems/pack_updater.gd`,`extends Node`):内容包(`.pck`/`.zip`)下载 / 校验 / 挂载机制,支撑「分包瘦身 + 热更」。两相结构:相 A 启动期在 `_init` 自动挂载已装包(按 `order` + 引擎版本闸门 + 单包失败隔离,只可查询不用信号);相 B 运行期 `check → download → restart_to_apply` 三动词 + 信号,原子暂存(全 sha256 校验通过才 temp+rename 改 `state.json`)。两个可注入接缝(传输 `HttpPackTransport` / 挂载 `ProjectSettings.load_resource_pack`),单测注入假件。含 GDScript 逻辑的包换逻辑必须重启进程(实测约束,见 `docs/research/2026-07-23-godot-hot-update-feasibility.md` §4b)。打破 14→15 子系统。纯增量,API 无破坏。
- **0.22.0** — `SaveManager` 叠加存档版本迁移链:信封 `_version` 从写死改为盖 `_data_version`(默认 1),`set_data_version`/`data_version` + `register_migration(from, fn)` 注册 v(n)→v(n+1) 迁移函数;`load()` 版本不符时按序自动迁移,缺步 `migration_missing:N` / 非字典 `migration_error:N` / 未来版本 `future_version` 三者 emit `migration_failed` + 返 `{}` 保底(不静默覆盖旧文件),成功 emit `migrated`。默认版本 1 + 无迁移注册 → 逐字节兼容既有 v1 存档。纯增量,API 无破坏。
- **0.21.0** — 新增两个 off-facade 类库 `KitStats`(`stats/`,`extends RefCounted`)与 `KitAchievements` + `AchievementDef`(`achievements/`)。`KitStats`:统计计数器,`add` 累加 / `record_max` 单调取大 / `set_value` 快照 / `get_value` + `to_dict`/`from_dict`,放置/成就的生涯计数心脏。`KitAchievements`:数据驱动阈值判定 `evaluate(stats)` 解锁「已达阈值且未解锁」者、返回新解锁 id 列表、已解锁绝不重触(去重)、`set_steam_sink` 平台抽象层(默认空,不绑 SDK)。零依赖、不接门面。纯增量,API 无破坏。
- **0.20.0** — 新增 off-facade 数值修正器栈 `KitModifiers`(`modifiers/`,`extends RefCounted`):`(base+Σadd)×Πmul` 分层聚合,每条带 `source_id`,脏标缓存,`breakdown`/`sources` 明细。incremental/数值成长的产出心脏(Fortune Mill 跨房协同定型后反哺)。零依赖、不接门面。纯增量,API 无破坏。
- **0.19.0** — 新增 off-facade 离线结算器 `KitOffline`(`offline/`,`extends RefCounted`,纯静态 `settle`):墙钟差 × 产率、封顶 8h、时间回拨(`now < last`)按 0 防作弊,离线补偿与在线同率。零依赖、不参与存档(调用方持久化 `last_seen`)。放置/挂机游戏读档补收益。纯增量,API 无破坏。
- **0.18.0** — dogfood(farm-sim 消费者视角)驱动的三处向后兼容便利方法:`KitDataRegistry.ids`/`types` 加 `sorted` 可选参数(字典序,规避 StringName 数组按指针地址排的坑);`KitInventory.totals()` 跨格按 id 聚合为 `{id:总数}`;`KitStateMachine.state_name()`/`is_in(query)` null 安全的当前态查询。纯增量,API 无破坏。
- **0.17.0** — 新增 off-facade 定义数据表 `KitDataRegistry`(`data/`,`extends RefCounted`):按 `type` 分组存放游戏自定义 `Resource` 定义(作物/物品/配方),`register` 显式登记 + `load_dir` 扫目录批量(id 取属性或文件名,剥 `.remap` 导出坑),`get_def`/`has_def`/`all`/`ids`/`types`/`count`/`clear`。零依赖、不接门面、不参与存档。纯增量,API 无破坏。
- **0.16.0** — 新增 off-facade 槽位制物品容器 `KitInventory`(`inventory/`,`extends RefCounted`):固定 capacity 格,`add` 自动堆叠+填空+溢出返余量("背包满"),`move` 空移/合并/交换,per-slot `data` 分品质,`changed` 信号,`to_dict`/`from_dict`。游戏每个容器(背包/箱子/商店)各 `new` 一个,零依赖、不接门面。纯增量,API 无破坏。
- **0.15.0** — 新增门面第 14 子系统 `CoreKit.clock`(`systems/game_clock.gd`,`extends Node`):年/季/日/时/分 世界时钟,混合推进(`time_scale` 自动走时 + `advance_minutes`/`advance_day`/`sleep_to_next_day` 显式跳时)+ 原生 signal + `CoreKit.bus` 广播 `clock:*`(`bind_bus` 注入,未绑定降级)+ `to_dict`/`from_dict` 持久化。顺带确立全 kit 事件命名约定 `namespace:event`(冒号)。打破 13→14 子系统(门面接线 + `test_core_kit` 同步)。纯增量,API 无破坏。
- **0.14.0** — 新增门面第 13 子系统 `CoreKit.layers`(`systems/layer_manager.gd`,`extends Node`):跨场景常驻的具名 `CanvasLayer`,z 序权威表(`BACKGROUND=-10`/`HUD=10`/`WINDOW=20`/`POPUP=30`/`MODAL=40`/`NOTIFY=50`/`SYSTEM=60`)+ 保留带常量(`CONSOLE=128`/`TRANSITION=4096`,收编 DevConsole/SceneManager 现值,**只登记不重构**、各加一行交叉引用注释);`layer`/`mount`/`clear`/`register_layer`/`has_layer`,零跨系统依赖。因宿主是 CoreKit autoload 子节点,具名层跨 `change_scene` 存活。打破 12→13 子系统(门面接线 + `test_core_kit` 同步)。纯增量,API 无破坏。
- **0.13.0** — 新增 off-facade UI 栈导航 `KitUiStack` + `KitUiScreen`(`ui/`):`push`/`pop`/`replace`/`clear` 管一叠 UI 屏(LIFO,push 进来的屏为宿主子节点=只管加进来的);被盖屏 `process_mode=DISABLED` 一刀切停用(键鼠/动作/tick 全惰性),`hide_below=false` 模态自动插 `ColorRect` 挡层,返回键经 `_unhandled_input` 兜底弹顶;`KitUiScreen` 组件挂子节点承载生命周期信号(entered/exited/covered/revealed)+ 转发方法 + 静态 `of()`;组合非继承、零门面耦合。纯增量,API 无破坏。
- **0.12.0** — 新增 off-facade 可复用转场资源 `KitTransition`(`transitions/`,`extends Resource`):数据驱动的 FADE + SLIDE 场景转场(方向 + 缓动曲线,可存 `.tres`);`SceneManager.change_scene` 第 2 参兼容接收 `KitTransition` 或 legacy 字典,`_merge_options`/`enum Transition` 保留。纯增量,API 无破坏。
- **0.11.0** — 新增 off-facade 重绑定 UI 组件 `KitRebindButton` / `KitRebindList`(`ui/`):点击捕获 + 检测拦截冲突(`InputManager` 增 `action_for_event`)+ 复位;代码建 UI、`.new()`+`add_child` 即用;audio/locale 接线为一行调用(见 demo)。纯增量,API 无破坏。
- **0.10.0** — 新增 `LocaleManager` 本地化托管层(`CoreKit.i18n` 第 12 子系统):运行时切语言 + 持久化(Settings section `locale`)+ 按 locale 换绑定 Theme 字体 + 缺翻译 `push_warning` 告警 + 运行时翻译加载(`load_translation`/`load_translations`);零门面耦合(`push_warning` 而非 `CoreKit.log`),纯增量,API 无破坏。
- **0.9.0** — 新增 `DevConsole` 调试控制台(`CoreKit.console` 第 11 子系统,CanvasLayer,`OS.is_debug_build()` 门控):日志 overlay + 命令/作弊注册 + GDScript 表达式执行(`Expression`)+ 变量 watch;`core/log.gd` 增补 `line_logged` 信号 + 有界历史缓冲(向后兼容);纯增量,API 无破坏。
- **0.8.0** — `KitStateMachine` 叠加事件 dispatch 解耦(`add_transition`/`dispatch` + `ANYSTATE` 通配,与 `transition_to` 并存)与 pushdown 栈(`push_state`/`pop_state`,暂停语义 + `KitState.pause`/`resume` 钩子);纯增量,API 无破坏。
- **0.7.0** — `SaveManager` 叠加可插拔序列化(`SaveSerializer` 基类 + 默认 `JsonSaveSerializer`,逐字节兼容旧 `.json`)、原子写(temp+rename)、资源引用安全守卫(拒 Object/Callable/Signal/RID);纯增量,API 无破坏。
- **0.6.0** — `KitContext` 叠加订阅式解析 `subscribe`(向下传播,化解「后代 `_ready` 早于祖先」时序坑)+ 工厂式 scope `provide_factory`(SINGLETON/TRANSIENT);纯增量,API 无破坏。
- **0.5.0** — 新增 `KitContext` 节点绑定层级服务容器(DI)+ `CoreKit` 全局根 `provide/service`;纯增量,API 无破坏。
- **0.4.1** — 子系统按角色归入 `core/` 与 `systems/`;新增 `addons/godot-core-kit/docs/` 架构文档。纯结构调整,API 无破坏。
- **0.4.0** — CoreKit 门面(唯一 autoload);新增 Settings / FrameScheduler / KitStateMachine / InputManager / AudioManager / ResourceManager;老五件迁入门面(破坏性,见上「升级」)。
- 0.3.0 — EventBus / SceneManager / ObjectPool / SaveManager。
- 0.2.0 — Log。
- 0.1.0 — addon 脚手架。
