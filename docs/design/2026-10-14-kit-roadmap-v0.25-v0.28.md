# godot-core-kit 补强路线图（v0.25 – v0.28）

来源：GitLab 地图「地图：kit 补强路线图（插件调研后续）」(#1) 的全部决策工单。本文只规定**顺序、版本和每个 cycle 的范围**，具体规格以各工单里的决议评论为准，这里不重复。

输入材料：

- `docs/research/2026-10-12-godot-plugin-survey.md`：17 个插件调研，以「对 kit 的结论」一节为准
- `docs/research/2026-10-12-single-thread-resource-preload.md`：单线程预载（#2）
- `docs/research/2026-10-12-joypad-brand-and-vibration.md`：手柄品牌与震动（#3）

## 硬约束（所有 cycle 通用）

- 不用线程，不用 GDExtension；新功能必须能在微信小游戏和单线程 Web 上运行。
- 公开 API 和存档、设置格式只做向后兼容的扩展。确实需要改行为的，必须写进版本说明，并提供回退开关。
- 每个 cycle 的流程：先读 `developing-core-kit` skill，在 `feat/<名字>` worktree 分支上用 `/tdd` 开发，`run_all` 全绿后在本地 ff-merge 到 main，同步更新版本号、`plugin.cfg` description 和 docs。push 由用户负责。

## 排序原则

1. **先修现存 bug**：输入（改一个键会把另一个设备的绑定清掉、多手柄时只认 0 号手柄）和音频（游戏暂停时 BGM 也停了）都是已上线的问题，排在最前。
2. **按子系统合并**：同一个子系统的工单放进同一个 cycle，避免同一个文件被连着改两轮。
3. **需要在微信上实测的放中间**：场景转场的 shader 要在微信里验证。放在它前面的 cycle 能先把 CDP 验证流程跑熟。
4. **风险最低的类库小改动放最后**：它们和其他 cycle 之间没有依赖。

几个 cycle 改的是不同文件，可以在不同 worktree 里并行开发，但**版本号按合并到 main 的先后顺序分配**。如果实际合并顺序和下表不同，就按实际顺序顺延。

## 版本表

| 版本 | cycle | 包含工单 | 涉及文件 | 行为变更 | 微信实测 |
|---|---|---|---|---|---|
| **v0.25.0** | 输入：按设备分槽 + 手柄品牌 + 震动 | #4、#5 | `systems/input_manager.gd`、`ui/rebind_button.gd`、`ui/rebind_list.gd` | 无。`rebind_action` 改为只替换同类设备的槽，属于 bug 修复；设置格式向后兼容读取 | `rumble` 是否映射到 `wx.vibrateShort` |
| **v0.26.0** | 音频：UI 通道、环境音、句柄 | #8 | `systems/audio_manager.gd` | **有**：暂停时 Music 继续播放。用 `pause_music_with_tree = true` 可恢复旧行为 | 无。总线和 process_mode 与平台无关 |
| **v0.27.0** | 场景：黑屏钩子、预载加载屏、reload、MASK 转场 | #6、#7 | `systems/scene_manager.gd`、`transitions/kit_transition.gd`，新增 `.gdshader` | 无。新能力全部放在新增的第 3 个参数和新增的枚举值上 | MASK 转场中间帧截图；带 preload 的切换在微信里能跑通 |
| **v0.28.0** | 类库小增量 + 文档收尾 | #9、#10、文档补强 | `data/kit_data_registry.gd`、`state_machine/kit_state_machine.gd`、docs | 无 | 无 |

## 各 cycle 的验收要点

每个 cycle 的测试清单见对应工单决议里的「测试要点」一节。下面只列跨工单、需要额外注意的事。

### v0.25.0 输入

- 两张工单一起实现：#4 的分槽决定了设置格式，#5 的 `rumble_enabled` 也存在同一个 `input` 段里，保留 key 是 `_rumble_enabled`。
- #4 有两份并发写出的决议，**以「最终决议（合并版）」为准**。
- 需要回归验证：fortune-mill 和 farm-sim 两个示范游戏在各自的 `example/*` 分支上，接入这一版后旧的键位设置要能正常读取。只验证，不改它们的代码。

### v0.26.0 音频

- 版本说明里单独写一段「行为变更」，说明暂停时 BGM 会继续播放，以及如何回退。
- fortune-mill 的 `sound_bank` 会调用 `play_sfx`。改动只是新增返回值，不影响调用方，但要在 smoke 里确认一次。

### v0.27.0 场景

- `before_swap` / `after_swap` 钩子、`cover` / `reveal`、预载、`reload_scene` 都在 #6；MASK 转场在 #7。两者都要改 `_play_transition` 和遮罩节点，所以合在一个 cycle。
- 预载依赖现有的 `CoreKit.res.preload_batch`，不要改 `ResourceManager` 的公开 API。
- 用 `wechat-minigame-cdp` 截图，验证这两件事：MASK 中间帧的显示效果，以及 `preload = true` 时 `scene_load_progress` 有没有在控制台按预期推进。

### v0.28.0 类库 + 文档

- #9 `register_records` 和 #10 的状态机扩展互相独立，可以分两个 commit，合并为一个版本号。
- 文档补强原本列在地图的「待定」里，在本版落地：
  1. kit docs 新增一节「推荐搭配插件」：相机用 Phantom Camera，对话用 Dialogue Manager，表格数据用 CSV Data Importer（配合 `register_records`），层级状态机用 Godot State Charts，Steam 用 GodotSteam（注明只支持桌面）。依据是插件调研报告。
  2. 在成就文档里补一个 GodotSteam 接入 `KitAchievements.set_steam_sink` 的示例。
  3. 在 `asset-bank` skill 里注明：gdfxr 生成的 `.sfxr` 文件可以作为真素材直接放进对应位置使用（只写通用说法，遵守 skill 不写项目细节的约定）。
  4. 在 `register_records` 的文档里写 CSV、JSON、远端配置三种接入方式（#9 第 3 节）。

## 明确不做（汇总，来源见各工单）

多玩家按手柄分别路由、组合键、多个副槽、触屏键重绑、kit 自带按键图标或加载屏 UI、Web 上通过 JS 识别手柄品牌、双马达分别控制、位置音效、ducking、播放列表、场景栈和场景参数、线程加载、CSV 解析和 schema 校验、层级和并行状态。这些都不属于本路线图。真有需要时另开地图。
