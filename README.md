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
| `KitStateMachine`(类库) | Node 型状态机 | [state-machine](addons/godot-core-kit/docs/state-machine.md) |
| `KitContext`(类库) | 节点绑定的层级服务容器(DI) | [kit-context](addons/godot-core-kit/docs/di/kit-context.md) |
| `KitRebindButton`/`KitRebindList`(类库) | 键位重绑定 UI 组件 | [rebind](addons/godot-core-kit/docs/ui/rebind.md) |
| `KitTransition`(类库) | 可复用场景转场资源 | [kit-transition](addons/godot-core-kit/docs/transitions/kit-transition.md) |
| `KitUiStack`/`KitUiScreen`(类库) | UI 屏栈导航 | [ui-stack](addons/godot-core-kit/docs/ui/ui-stack.md) |
| `KitInventory`(类库) | 槽位制物品容器 | [kit-inventory](addons/godot-core-kit/docs/inventory/kit-inventory.md) |
| `KitDataRegistry`(类库) | 定义数据表(作物/物品/配方) | [kit-data-registry](addons/godot-core-kit/docs/data/kit-data-registry.md) |

## 从 0.3.x 升级(破坏性)

v0.4.0 起只保留一个 autoload `CoreKit`,老全局单例名全部下线:`Log.` → `CoreKit.log.`、`EventBus.` → `CoreKit.bus.`、`SceneManager.` → `CoreKit.scenes.`、`ObjectPool.` → `CoreKit.pool.`、`SaveManager.` → `CoreKit.saves.`。升级步骤:项目设置里删掉这五个旧 autoload、只留 `CoreKit`,再按上表全局替换调用点。

## 测试

```
godot --headless --path . --import      # 首次:生成 class_name 缓存
powershell -File test\run_all.ps1       # 一键全量,末行 FAILS=0 为全绿
```

细节见 [架构总纲的「测试」段](addons/godot-core-kit/docs/architecture.md)。

## 版本

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
