---
name: using-core-kit
description: Use when calling or looking up the godot-core-kit API from a Godot game — playing audio/BGM, saving/loading, scene changes, input rebinding or jump-buffering, player settings, event bus pub/sub, object pools, frame-divided ticks, async resource preloading, or the KitStateMachine; or to find which subsystem provides a feature.
---

# 使用 core-kit

`godot-core-kit` 通过唯一一个 autoload 门面 `CoreKit` 暴露全部子系统(插件位于 `addons/godot-core-kit/`)。

> 如果项目里同时有 `addons/godot_ai/`,那是无关的 MCP 编辑器插件——忽略它。这里讲的都是 `CoreKit`。

## 答案在随插件分发的 docs 里 —— 先去那查

权威、与源码保持 1:1 的 API 文档随插件分发。优先查文档,而不是读源码:

- `addons/godot-core-kit/docs/README.md` —— 全部子系统的索引。
- `addons/godot-core-kit/docs/architecture.md` —— 门面、初始化顺序、引擎坑。
- `addons/godot-core-kit/docs/core/<x>.md` 与 `docs/systems/<x>.md` —— 每个子系统:职责 / 公开 API / 依赖 / 用法示例 / 注意事项。
- `addons/godot-core-kit/docs/state-machine.md` —— KitStateMachine 类库。
- `addons/godot-core-kit/docs/di/kit-context.md` —— KitContext 服务容器 + CoreKit 全局 provide/service。

## 门面映射(属性 → 子系统)

| 访问 | 作用 |
|---|---|
| `CoreKit.log` | 分级日志(debug/info/warn/error) |
| `CoreKit.bus` | 字符串事件名的 pub/sub 总线 |
| `CoreKit.settings` | 玩家偏好,落盘 `user://settings.json` |
| `CoreKit.scenes` | 场景切换(可选淡入淡出) |
| `CoreKit.pool` | 对象池 |
| `CoreKit.saves` | 存档槽(`user://saves/`) |
| `CoreKit.ticker` | 帧分频 tick + 每帧预算队列 |
| `CoreKit.input` | 键位重绑定 + 设备检测 + 输入缓冲 |
| `CoreKit.audio` | 总线音量 + BGM 交叉淡切 + SFX 池 |
| `CoreKit.res` | 异步批量预加载 + 缓存 |

`KitStateMachine` / `KitState` 是 per-entity 的 `class_name` 类库,**不在门面上**——每个实体自己 `new()` 一台。见 `docs/state-machine.md`。

`KitContext` 同为 off-facade `class_name` 类库:游戏代码注册自己服务的**层级服务容器**(挂节点、随树回退)。全局服务用 `CoreKit.provide/service`;作用域服务用 `KitContext`。见 `docs/di/kit-context.md`。

## 怎么回答"我要做 X?"

1. 在上面的映射表里找到对应子系统。
2. 打开 `addons/godot-core-kit/docs/README.md` —— 索引直接链到每个子系统的文档页(文件名是 **kebab-case**:`audio-manager.md`,不是 `audio.md`)。文档页的 **公开 API** 段有确切签名,**用法示例** 段有可跑片段。
3. 经 `CoreKit.<prop>...` 调用。

## 新手最先踩的坑

- **音量**:用 `CoreKit.audio.set_volume("music", 0.8)`——它立刻写 `AudioServer` 并同时落盘。单独 `CoreKit.settings.set_value("audio","music",...)` 在下次启动前是不生效的,所以 README 开头那行只是 Settings 演示,不是实时改音量的方式。
- **JSON int→float**:settings/saves 经 JSON 往返,int 取回会变 float——读取时用 `int(...)` 包一下。
- **状态机首次运行**:任何引用 `KitStateMachine`/`KitState` 的脚本,首次需跑一次 `godot --headless --path . --import` 以生成 `class_name` 缓存。
