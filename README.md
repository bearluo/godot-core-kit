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
├── project.godot                 # 开发工程配置（Compatibility 渲染器；启用插件；autoload Log 与 CoreKit）
├── icon.svg                      # 工程图标
├── addons/
│   └── godot-core-kit/           # ← 复用给游戏项目的就是这个目录
│       ├── plugin.cfg            # 插件元信息
│       ├── plugin.gd             # EditorPlugin：启用插件时注册 autoload Log、CoreKit
│       ├── log.gd                # Log 单例：分级日志（DEBUG/INFO/WARN/ERROR）
│       └── core_kit.gd           # 运行时全局单例（骨架，后续挂各子系统）
├── demo/
│   ├── demo.tscn                 # 冒烟测试场景（工程主场景）
│   └── demo.gd
├── test/
│   └── test_log.gd               # headless 断言测试
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

引入后，在游戏项目「项目设置 > 插件」里启用 **godot-core-kit**。启用时插件会自动注册
`Log` 与 `CoreKit` 两个 autoload，之后任意脚本可直接使用：

```gdscript
Log.info("hello from game")      # 分级日志：Log.debug/info/warn/error
Log.set_level(Log.Level.WARN)    # 运行时收紧阈值
print(CoreKit.VERSION)
```

## 版本

0.2.0 — 新增 `Log` 日志子系统：全局单例，四级分级（DEBUG/INFO/WARN/ERROR）、
统一格式 `[时间][级别] 消息`、全局阈值过滤、彩色输出、WARN/ERROR 接入编辑器
调试器面板。后续子系统（事件总线、场景管理、对象池、存档等）另行设计与实现。
