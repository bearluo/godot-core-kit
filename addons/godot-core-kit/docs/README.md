# godot-core-kit 文档

面向 2D 游戏的 Godot 4 GDScript 底层框架。一个 autoload 门面 `CoreKit` 统管 15 个子系统,外加状态机与服务容器两套 off-facade 类库。

## 从这里开始

- **[architecture.md](architecture.md)** —— 架构总纲:门面模式、目录布局、构造/初始化顺序、依赖纪律、已知引擎坑。第一次读框架先看这篇。

## 子系统

### core/ —— 根基设施

| 文档 | 访问 | 一句话 |
|---|---|---|
| [log](core/log.md) | `CoreKit.log` | 分级日志 + 阈值过滤 + 彩色输出 |
| [event-bus](core/event-bus.md) | `CoreKit.bus` | 字符串事件名的发布/订阅总线 |
| [settings](core/settings.md) | `CoreKit.settings` | 玩家偏好,写透 `user://settings.json` |

### systems/ —— 业务子系统

| 文档 | 访问 | 一句话 |
|---|---|---|
| [scene-manager](systems/scene-manager.md) | `CoreKit.scenes` | 场景切换 |
| [object-pool](systems/object-pool.md) | `CoreKit.pool` | 对象池复用 |
| [save-manager](systems/save-manager.md) | `CoreKit.saves` | 存档槽读写 |
| [frame-scheduler](systems/frame-scheduler.md) | `CoreKit.ticker` | 帧分频器:降频 tick + 预算队列 |
| [input-manager](systems/input-manager.md) | `CoreKit.input` | 键位重绑定 + 设备检测 + 输入缓冲 |
| [audio-manager](systems/audio-manager.md) | `CoreKit.audio` | 总线音量 + BGM 交叉淡切 + SFX 池 |
| [resource-manager](systems/resource-manager.md) | `CoreKit.res` | 异步预加载 + 缓存 |
| [i18n](systems/i18n.md) | `CoreKit.i18n` | 本地化:运行时切语言 + 字体回退 + 缺翻译告警 |
| [layer-manager](systems/layer-manager.md) | `CoreKit.layers` | 跨场景常驻具名 CanvasLayer(z 序表 + 保留带) |
| [game-clock](systems/game-clock.md) | `CoreKit.clock` | 游戏时钟/日历:混合推进 + bus 广播 clock:* |
| [pack-updater](systems/pack-updater.md) | `CoreKit.updater` | 内容包下载/校验/挂载(分包瘦身 + 热更):check→download→restart 三动词 + 启动期尽早挂包 |

### console/ —— 运行时调试

| 文档 | 访问 | 一句话 |
|---|---|---|
| [console](console.md) | `CoreKit.console` | 运行时调试控制台(dev 门控):日志 overlay + 命令/作弊注册 + 表达式执行 + 变量 watch |

### 类库(off-facade,不挂门面)

| 文档 | 访问 | 一句话 |
|---|---|---|
| [state-machine](state-machine.md) | `class_name KitStateMachine` | Node 型有限状态机,每个实体自己一台 |
| [kit-context](di/kit-context.md) | `class_name KitContext` | 节点绑定的层级服务容器(DI):游戏代码注册自己的服务 |
| [rebind](ui/rebind.md) | `class_name KitRebindButton` / `KitRebindList` | 键位重绑定 UI 组件(点击捕获 + 冲突拦截 + 复位) |
| [kit-transition](transitions/kit-transition.md) | `class_name KitTransition` | 可复用场景转场资源(FADE/SLIDE,由 `CoreKit.scenes` 消费) |
| [ui-stack](ui/ui-stack.md) | `class_name KitUiStack` / `KitUiScreen` | UI 屏栈导航(push/pop/replace + 被盖屏停用 + 模态挡层 + 返回键兜底) |
| [kit-inventory](inventory/kit-inventory.md) | `class_name KitInventory` | 槽位制物品容器(自动堆叠/溢出/拖拽合并,游戏多实例) |
| [kit-data-registry](data/kit-data-registry.md) | `class_name KitDataRegistry` | 定义数据表:type→{id→def} 存 Resource,register + load_dir |
| [kit-offline](offline/kit-offline.md) | `class_name KitOffline` | 离线结算器:墙钟差×产率、封顶 8h、时间回拨按 0 防作弊(放置游戏读档补收益) |
| [kit-modifiers](modifiers/kit-modifiers.md) | `class_name KitModifiers` | 数值修正器栈:(base+Σadd)×Πmul 分层聚合、每条带 source_id、脏标缓存、breakdown 明细(incremental 产出心脏) |
| [kit-stats](stats/kit-stats.md) | `class_name KitStats` | 统计计数器:add 累加 / record_max 峰值 / set_value 快照 / get_value,to_dict 存档(生涯计数) |
| [kit-achievements](achievements/kit-achievements.md) | `class_name KitAchievements` / `AchievementDef` | 成就引擎:数据驱动阈值判定 evaluate(stats)、触发去重返回新解锁、set_steam_sink 平台抽象层 |

## 约定

- 所有门面子系统经 `CoreKit.<属性>` 访问,无单独全局单例名。
- 每篇子系统文档为五段式:**职责 / 公开 API / 依赖 / 用法示例 / 注意事项**。
- 本目录随插件分发,是"怎么用"的说明;`docs/superpowers/` 在仓库根、是开发过程产物(设计规格 + 实现计划),两者不同。
