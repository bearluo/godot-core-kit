# 关卡作用域示例(KitContext level scope)

用 `KitContext` 给一关建一个作用域:关卡专属服务只在这一关可见,关卡卸载时随之自动回收;实体解析时命中本关服务,拿不到就向上回退到 `CoreKit` 全局根。

## 文件

| 文件 | 作用 |
|---|---|
| `level.gd` | 关卡根,`extends KitContext` —— 关卡即作用域。`_ready` 注册关卡专属服务并 spawn 实体。 |
| `enemy.gd` | 关卡内实体。`_ready` 用 `KitContext.resolve(self, key)` 解析服务(命中本关 + 回退全局)。 |
| `level_spawner.gd` | 一个关卡专属服务(Node),经 `provide_child` 收养 → 随关卡回收。 |
| `game.gd` / `game.tscn` | 驱动:注册全局默认 → 加载关卡(shadow)→ 卸载看自动回收。整条故事的入口。 |
| `level.tscn` | 关卡场景(根 `Level` 挂 `level.gd`)。 |

## 跑法

- **编辑器**:把 `game.tscn` 设为主场景运行,看输出面板。
- **Headless**:
  ```
  godot --headless --path . res://examples/level_scope/game.tscn --quit-after 120
  ```
  (首次需先 `godot --headless --path . --import` 生成 `KitContext` 类缓存。)

## 预期输出

```
[Game] global difficulty = global-default
[Level1] scoped services registered (difficulty=hard)
[Enemy1] resolved scoped: difficulty=hard wave_count=3 | fallback: audio_is_builtin=true
[LevelSpawner] spawning wave of 3
[Game] outside level, global difficulty still = global-default
[Game] before unload: spawner valid = true
[Game] after unload:  spawner valid = false (作用域已随关卡回收)
```

逐行对应五个要点:
1. `global difficulty = global-default` —— 全局根注册的默认值。
2. `Enemy1 ... difficulty=hard` —— 实体解析命中**本关** difficulty,**shadow** 了全局默认。
3. `audio_is_builtin=true` —— `audio` 本关没有,**向上回退**到 CoreKit 内置。
4. `outside level ... still = global-default` —— shadow 只在关卡子树内生效,不污染全局。
5. `after unload: spawner valid = false` —— 关卡 `free()` → 作用域 + `provide_child` 的服务**自动回收**(树驱动,无手动清理)。

## 要点

- **关卡根即作用域**:根 `extends KitContext`,关卡内任意后代经 `KitContext.resolve(self, key)` 都能向上命中。
- **Node vs Node2D**:`KitContext` 继承自 `Node`,所以关卡根是普通 `Node`。要 `Node2D` 关卡,就别让根 `extends KitContext`,改为在 `Node2D` 根下挂一个 `KitContext` 子节点、把游戏内容 parent 到它下面。
- **注册顺序**:关卡在 `_ready` 里**先注册服务再 spawn 实体**——实体 `_ready` 早于父节点,先 spawn 会 miss。
- **归属**:`provide_child`(收养 Node,随关卡回收) vs `provide`(只存引用,生命周期归你)。
- 完整 API 见 [`../../addons/godot-core-kit/docs/di/kit-context.md`](../../addons/godot-core-kit/docs/di/kit-context.md)。
