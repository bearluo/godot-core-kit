# godot-core-kit

面向游戏项目复用的 **Godot 4 纯 GDScript 通用基础库**，以 Godot **addon** 形式提供。
本仓库是该 addon 的**开发工程**：可直接用 Godot 4 打开、运行 `demo/` 场景来开发和验证框架本身；
真正复用给游戏项目的是 `addons/godot-core-kit/` 这个子目录。本库**不含具体游戏**。

- 引擎：Godot 4.7（mono/.NET 版可用；本库为纯 GDScript，不含 C#，不生成 `.csproj`）
- 渲染器：Compatibility（`gl_compatibility`），以支持 Web / HTML5 导出
- 语言：纯 GDScript

> 为什么不用 C# 补性能：Godot 4 的 C# 无法可靠导出到 Web，与本库“可 Web 导出”的目标冲突，
> 故首版为纯 GDScript。将来若某游戏只面向桌面且需要极致性能，可在该游戏侧单独引入 C# 模块，
> 不影响本库。

## 目录结构

```
godot-core-kit/
├── project.godot                 # 开发工程配置（Compatibility 渲染器；启用插件；6 个 autoload 预声明）
├── icon.svg                      # 工程图标
├── addons/
│   └── godot-core-kit/           # ← 复用给游戏项目的就是这个目录
│       ├── plugin.cfg            # 插件元信息
│       ├── plugin.gd             # EditorPlugin：启用插件时按序注册全部 autoload
│       ├── log.gd                # Log：分级日志（DEBUG/INFO/WARN/ERROR）
│       ├── event_bus.gd          # EventBus：字符串事件名的全局发布/订阅
│       ├── scene_manager.gd      # SceneManager：场景切换 + 可选淡入淡出
│       ├── object_pool.gd        # ObjectPool：具名节点池复用
│       ├── save_manager.gd       # SaveManager：JSON 槽位存档（user://）
│       └── core_kit.gd           # 运行时全局入口 + 版本标识
├── demo/
│   ├── demo.tscn                 # 冒烟测试场景（工程主场景）
│   └── demo.gd                   # 冒烟全部子系统
├── test/
│   ├── test_log.gd
│   ├── test_event_bus.gd
│   ├── test_scene_manager.gd
│   ├── test_object_pool.gd
│   ├── test_save_manager.gd      # headless 断言测试
│   └── fixtures/                 # 测试 fixture（object_pool_probe.gd）
└── docs/superpowers/             # 设计文档（specs）与实现计划（plans）
```

## 在游戏项目中引用

### 方式一：gd-plug（推荐）

在游戏项目的 `plug.gd` 里：

```gdscript
plug("<你的 GitLab 地址>/godot-core-kit", {"include": ["addons/godot-core-kit"]})
```

运行 `godot --headless -s plug.gd install` 拉取，只会把 `addons/godot-core-kit` 装进去。

### 方式二：直接复制

把本仓库的 `addons/godot-core-kit/` 整个目录复制到游戏项目的 `addons/` 下。

### 启用

引入后，在游戏项目「项目设置 > 插件」里启用 **godot-core-kit**。启用时插件会自动注册六个
autoload——`Log`、`EventBus`、`SceneManager`、`ObjectPool`、`SaveManager`、`CoreKit`——
之后任意脚本可直接使用：

```gdscript
# 日志（Log）
Log.info("hello from game")            # Log.debug/info/warn/error
Log.set_level(Log.Level.WARN)          # 运行时收紧阈值

# 事件总线（EventBus）—— 字符串事件名的全局发布/订阅
EventBus.subscribe("player_died", _on_player_died)
EventBus.publish("player_died", {"score": 42})

# 场景管理（SceneManager）—— 统一切换，可选淡入淡出
SceneManager.change_scene("res://levels/level_2.tscn", {"transition": SceneManager.Transition.FADE})

# 对象池（ObjectPool）—— 复用高频 spawn 的节点
ObjectPool.register("bullet", preload("res://bullet.tscn"), 64)
var b := ObjectPool.acquire("bullet"); add_child(b)   # 用完 ObjectPool.release(b)

# 存档（SaveManager）—— JSON 槽位存档
SaveManager.save("slot1", {"level": 3, "hp": 80})
var state := SaveManager.load("slot1")

print(CoreKit.VERSION)
```

## 版本

0.3.0 — 新增四个独立子系统（各自 autoload、互不依赖、均可 Web 导出）：
- **EventBus** 事件总线：字符串事件名全局发布/订阅，失效监听惰性自清、发布重入安全。
- **SceneManager** 场景管理：统一 `change_scene`、可选淡入淡出、切换生命周期信号（首版仅替换，不做场景栈）。
- **ObjectPool** 对象池：具名节点池复用，预热 / 上限 / `_pool_reset` 钩子，双重释放与僵尸引用安全。
- **SaveManager** 存档：JSON `{_version, data}` 信封、具名槽位、槽名消毒防穿越（首版无迁移 / 无加密）。

0.2.0 — `Log` 日志子系统：全局单例，四级分级（DEBUG/INFO/WARN/ERROR）、统一格式
`[时间][级别] 消息`、全局阈值过滤、彩色输出、WARN/ERROR 接入编辑器调试器面板。

0.1.0 — 脚手架骨架：`CoreKit` 全局入口占位。
