# godot-core-kit 目录重排 + 架构文档 —— 设计

- 日期:2026-07-09
- 分支:`feat/dir-restructure-docs`
- 起点版本:0.4.0 → 目标 0.4.1(纯结构调整,对使用者 API 无破坏)
- 类型:内部目录重排(机械) + 新增功能架构文档目录

## 背景

`addons/godot-core-kit/` 当前把 10 个子系统 `.gd` **平铺**在 addon 根,唯一被分组的是 `state_machine/`(class_name 类库)。随 v0.4.0 子系统从 5 个增到 10 个,平铺已难以一眼看出分层与依赖方向。同时项目缺少面向**使用者**的架构文档(现有 `docs/superpowers/` 是开发过程产物:specs + plans,不是 API/架构说明)。

本次做两件事:
1. 把平铺的 10 个子系统按角色归入 `core/` 与 `systems/` 子目录。
2. 在 addon 内新增 `docs/` 功能架构文档目录,随插件分发。

## 关键约束(Godot 路径耦合)

门面 `core_kit.gd` 用 `preload("res://addons/godot-core-kit/<x>.gd")` **按路径**引用全部子系统;`plugin.gd` 的 autoload、`plugin.cfg`、`project.godot`、测试里的 `load()` 也都是硬路径 + 每个 `.gd` 带 `.gd.uid` 边车。**物理挪文件必须同步改所有路径引用,并重建导入缓存**,否则编译/加载失败。

已核实的前提(决定 blast radius 完整):
- 10 个待移文件**均无 `class_name`** → 纯路径耦合,不存在按名引用的隐藏面。
- 门面 `core_kit.gd`、`plugin.gd`、`plugin.cfg` **留在 addon 根不动** → autoload 注册、插件脚本路径、`project.godot` 全部**无需改动**。
- `state_machine/`(kit_state.gd / kit_state_machine.gd,class_name 类库)已在子目录,**不动**。

## 目标目录树

```
addons/godot-core-kit/
  plugin.cfg                  # 根(Godot 硬性要求);顺手刷新 stale description + 版本 0.4.1
  plugin.gd                   # 根,编辑器插件入口(autoload 指 core_kit.gd,路径不变)
  core_kit.gd                 # 根,门面 = autoload 根节点
  core/                       # 根基设施(被 systems 依赖)
    log.gd
    event_bus.gd
    settings.gd
  systems/                    # 业务子系统
    scene_manager.gd
    object_pool.gd
    save_manager.gd
    frame_scheduler.gd
    input_manager.gd
    audio_manager.gd
    resource_manager.gd
  state_machine/              # class_name 类库(不动)
    kit_state.gd
    kit_state_machine.gd
  docs/                       # ★新增:功能架构文档(随插件分发)
    README.md                 # 文档索引/导航
    architecture.md           # 总纲:门面模式 + 依赖图 + 构造/初始化顺序 + 已知时序坑
    core/
      log.md
      event-bus.md
      settings.md
    systems/
      scene-manager.md
      object-pool.md
      save-manager.md
      frame-scheduler.md
      input-manager.md
      audio-manager.md
      resource-manager.md
    state-machine.md
```

### 分组归属

| 目录 | 文件 | 理由 |
|---|---|---|
| `core/` | log, event_bus, settings | 根基设施,被 systems 依赖;门面构造顺序里排在前 |
| `systems/` | scene_manager, object_pool, save_manager, frame_scheduler, input_manager, audio_manager, resource_manager | 面向玩法的业务子系统 |
| `state_machine/` | kit_state, kit_state_machine | class_name 类库,per-entity 使用,不挂门面 |

## 文档设计

共 **13 个 markdown**:1 索引(README.md) + 1 总纲(architecture.md) + 11 子系统篇。目录**镜像代码分层**(`docs/core/`、`docs/systems/`、`docs/state-machine.md`),便于从源码定位到文档。命名:kebab-case `.md` 对应 snake_case `.gd`。

每篇子系统文档统一五段式:

1. **职责** —— 一句话定位 + 解决什么问题。
2. **公开 API** —— signal / 方法签名 / 关键导出属性,带简短说明。
3. **依赖** —— 依赖哪些其它子系统、如何注入(bind_* 或门面 log 链)。
4. **用法示例** —— 通过门面 `CoreKit.<x>` 的最小可跑片段。
5. **注意事项** —— 引擎坑、生命周期、线程/帧时序等踩过的点。

`architecture.md` 总纲覆盖:门面模式与 autoload 根、10 子系统构造顺序(log → settings → bus → scenes → pool → saves → ticker → input → audio → res)、`_ready` 里的三处 bind_* 交叉接线、依赖方向表、以及 headless `-s` 已知时序坑(root 未入树需 `await process_frame` 等)。文档内容照代码**实读后写实**,不留占位符。

## 变更清单(精确 blast radius)

### 移动(`git mv`,gd 与 uid 成对)
- → `core/`:log, event_bus, settings(3 gd + 3 uid)
- → `systems/`:scene_manager, object_pool, save_manager, frame_scheduler, input_manager, audio_manager, resource_manager(7 gd + 7 uid)

### 引用更新
- `addons/godot-core-kit/core_kit.gd`:10 条 `preload` 路径加 `core/` 或 `systems/` 前缀。
- `demo/demo.gd`:1 条 `log.gd` → `core/log.gd`。
- 11 个测试文件约 25 条路径串:
  `test_core_kit.gd`(10 项期望表)、`test_log`、`test_event_bus`、`test_settings`、`test_scene_manager`、`test_object_pool`、`test_save_manager`、`test_frame_scheduler`、`test_input_manager`、`test_audio_manager`、`test_resource_manager`。
- `plugin.cfg`:version `0.4.0 → 0.4.1`,description 补上 5 个新子系统。

### 刻意不碰
`.superpowers/sdd/*` 与 `docs/superpowers/{specs,plans}/*` 中的旧路径串是**带日期的历史过程快照**(实现报告、计划),记录当时事实,重写会篡改历史。全部保留原样,不做无关重构。`test_state_machine.gd` 引用 `state_machine/`(不动),无需改。

## 迁移机制与验收门

1. `git mv` 逐个搬(gd + uid 成对,保 git 历史)。
2. 改上述三处引用。
3. `godot --headless --path . --import` 重建 `.godot/` 导入缓存 + class_name 注册表(**移动后必跑**,否则缓存指向旧路径)。
4. **跑全套 `test\run_all.ps1` → 必须 `FAILS=0`**(12 测试 ALL PASS + demo 冒烟五 marker 齐、stderr 无 ERROR)。这是唯一验收标准,任一挂即路径未接对。

## 执行方式

机械重排 + 文档撰写,非相互独立的并行任务,且有全套测试当安全网。**不套 SDD 多子agent流程,在本会话直接执行,以全绿测试为门**。

提交结构(线性):
1. `test:` 补 `run_all.ps1` 全套验证脚本(已存在,未跟踪)。
2. `docs:` 本设计文档。
3. `refactor:` 目录重排(git mv + 引用更新 + plugin.cfg bump)—— 原子功能变更,提交前测试须全绿。
4. `docs:` 13 篇架构文档。

## 非目标(YAGNI)

- 不改任何子系统的运行时行为 / 公开 API。
- 不把每个子系统拆成独立文件夹(当前一子系统一文件,`systems/` 平铺足够)。
- 不重写历史过程文档里的旧路径。
- 不动 `state_machine/`、门面、插件注册、autoload。
