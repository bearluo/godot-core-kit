# 成就 drop-in 覆盖目录

51 条成就默认由 `systems/achievement_catalog.gd` 代码构建后注册进 `KitDataRegistry`
(见 `fortune_state.gd` `_ready`)。此目录用于 **drop-in 覆盖 / 新增**:

- 往这里丢一个 `AchievementDef` 的 `.tres`(`id` 与目录内某条相同 → 覆盖;不同 → 新增),
  `registry.load_dir(&"achievement", ...)` 在代码目录注册之后扫描,后注册者覆盖同 id。
- 不改任何代码即可调整成就标题/描述/阈值,或加自定义成就。

目录留空时 `load_dir` 扫到 0 条,行为 = 纯代码目录(51 条)。`.md` 不会被 `load_dir` 加载。
