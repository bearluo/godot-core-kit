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
| `KitStateMachine`(类库) | Node 型状态机 | [state-machine](addons/godot-core-kit/docs/state-machine.md) |
| `KitContext`(类库) | 节点绑定的层级服务容器(DI) | [kit-context](addons/godot-core-kit/docs/di/kit-context.md) |

## 从 0.3.x 升级(破坏性)

v0.4.0 起只保留一个 autoload `CoreKit`,老全局单例名全部下线:`Log.` → `CoreKit.log.`、`EventBus.` → `CoreKit.bus.`、`SceneManager.` → `CoreKit.scenes.`、`ObjectPool.` → `CoreKit.pool.`、`SaveManager.` → `CoreKit.saves.`。升级步骤:项目设置里删掉这五个旧 autoload、只留 `CoreKit`,再按上表全局替换调用点。

## 测试

```
godot --headless --path . --import      # 首次:生成 class_name 缓存
powershell -File test\run_all.ps1       # 一键全量,末行 FAILS=0 为全绿
```

细节见 [架构总纲的「测试」段](addons/godot-core-kit/docs/architecture.md)。

## 版本

- **0.5.0** — 新增 `KitContext` 节点绑定层级服务容器(DI)+ `CoreKit` 全局根 `provide/service`;纯增量,API 无破坏。
- **0.4.1** — 子系统按角色归入 `core/` 与 `systems/`;新增 `addons/godot-core-kit/docs/` 架构文档。纯结构调整,API 无破坏。
- **0.4.0** — CoreKit 门面(唯一 autoload);新增 Settings / FrameScheduler / KitStateMachine / InputManager / AudioManager / ResourceManager;老五件迁入门面(破坏性,见上「升级」)。
- 0.3.0 — EventBus / SceneManager / ObjectPool / SaveManager。
- 0.2.0 — Log。
- 0.1.0 — addon 脚手架。
