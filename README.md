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
| `KitStateMachine`(类库) | Node 型状态机 | [state-machine](addons/godot-core-kit/docs/state-machine.md) |
| `KitContext`(类库) | 节点绑定的层级服务容器(DI) | [kit-context](addons/godot-core-kit/docs/di/kit-context.md) |
| `KitRebindButton`/`KitRebindList`(类库) | 键位重绑定 UI 组件 | [rebind](addons/godot-core-kit/docs/ui/rebind.md) |

## 从 0.3.x 升级(破坏性)

v0.4.0 起只保留一个 autoload `CoreKit`,老全局单例名全部下线:`Log.` → `CoreKit.log.`、`EventBus.` → `CoreKit.bus.`、`SceneManager.` → `CoreKit.scenes.`、`ObjectPool.` → `CoreKit.pool.`、`SaveManager.` → `CoreKit.saves.`。升级步骤:项目设置里删掉这五个旧 autoload、只留 `CoreKit`,再按上表全局替换调用点。

## 测试

```
godot --headless --path . --import      # 首次:生成 class_name 缓存
powershell -File test\run_all.ps1       # 一键全量,末行 FAILS=0 为全绿
```

细节见 [架构总纲的「测试」段](addons/godot-core-kit/docs/architecture.md)。

## 版本

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
