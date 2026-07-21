# fortune-mill —— godot-core-kit 的 incremental 放置游戏示例

复刻 Steam《财富磨坊 / Fortune Mill》风格的房间闯关式放置游戏,建在
[godot-core-kit](../../addons/godot-core-kit/) 上,用真实玩法 dogfood 验证框架并反哺
四个缺口子系统(KitModifiers/KitOffline/KitStats/存档迁移)。

**当前进度:P0 飞镖竖切片** —— 手动投镖 → 买升级 → 攒 100 万 gold 贿赂守卫 Verminous 过关。

## 快速开始

- **编辑器里玩**:运行工程(主场景 `scenes/world.tscn`)。点「投镖」赚 gold,买升级,攒够 100 万点「贿赂」过关。
- **headless 自测**:`FORTUNE_SMOKE=1 godot --headless --path . res://examples/fortune-mill/scenes/world.tscn --quit-after 600` → `[Fortune][SMOKE] PASS`。
- 首次跑先 `godot --headless --path . --import` 生成 class_name 缓存。

## 设计

见 [docs/superpowers/specs/2026-07-20-fortune-mill-incremental-design.md](../../docs/superpowers/specs/2026-07-20-fortune-mill-incremental-design.md)。
