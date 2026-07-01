# godot-core-kit 脚手架设计

- 日期：2026-07-01
- 状态：已确认，直接建 + Godot 4.7 验证

## 目标与定位

一套复用给**多个游戏项目**的 Godot 4 **纯 GDScript 通用基础库**，以 Godot **addon** 形式存在。
本身**不含具体游戏**——游戏各自另开项目。本仓库是承载该 addon 的「开发工程」，可独立打开、
运行、测试框架本身。

## 关键决定

| 维度 | 结论 | 理由 |
|---|---|---|
| 引擎 | Godot 4.x（`config_version=5`），本机 4.7.stable.mono | 用户环境即 4.7 mono 版 |
| 语言 | 纯 GDScript（不含 C#） | C# 在 Godot 4 无法可靠导出 Web，与“可 Web 导出”冲突 |
| 渲染器 | Compatibility（`gl_compatibility`） | Web / HTML5 导出的唯一可用渲染方式 |
| 复用方式 | Godot addon + git 分发（gd-plug / 复制） | GDScript 是源码分发；addon 是生态标准，编辑器集成完整、可 Web 导出 |
| 仓库布局 | ① 开发工程托管 addon（框架在 `addons/<名>/`，含 demo 测试场景） | 框架能独立跑测，开发体验最好 |
| 首版范围 | 纯骨架 | YAGNI；具体子系统后续各自 brainstorm |
| 名称 | `godot-core-kit` | — |

### 被否决的选项（存档）

- **C# 补性能热点**：与 Web 导出冲突，放弃；将来某游戏只面向桌面时可在该游戏侧单独加。
- **运行时 .pck 资源包**：开发期无跨项目类型补全 / `class_name` 解析，适合内容而非开发库。
- **GDExtension 编译二进制**：需 C++/Rust、按平台各编一份，破坏 Web 导出。
- **仓库根即 addon（布局②）**：submodule 一行引入很干净，但框架不能独立跑测；不选。

## 目录结构

```
E:\work\godot-core-kit\
├── project.godot                 # name="godot-core-kit (dev)"；主场景=demo；
│                                 #   渲染器=gl_compatibility；启用插件；预声明 autoload CoreKit
├── icon.svg                      # 工程图标
├── .gitignore                    # Godot 官方（.godot/ 等）
├── .gitattributes                # 文本/二进制 + eol=lf
├── README.md                     # 定位 + 消费方引入方式
├── addons/
│   └── godot-core-kit/           # ← 复用给游戏项目的就是这个目录
│       ├── plugin.cfg            # 插件元信息 version=0.1.0
│       ├── plugin.gd             # @tool EditorPlugin：启用时注册 autoload CoreKit（幂等），禁用时移除
│       └── core_kit.gd           # 示例 autoload 单例：VERSION + info() 占位
└── demo/
    ├── demo.tscn                 # 主场景，根节点 Node，挂 demo.gd
    └── demo.gd                   # 冒烟测试：_ready 里调 CoreKit.info(...)
```

## 接线要点

- `plugin.gd` 用 `add_autoload_singleton("CoreKit", …)` 注册，带 `ProjectSettings.has_setting`
  幂等判断，避免与开发工程 `project.godot` 的预声明重复注册报错。这正是消费方启用插件时的
  体验，开发工程顺带自测。
- 消费方引入见 README：gd-plug 只拉 `addons/godot-core-kit` 子目录；或直接复制该目录。

## 验证方式

本机 Godot：`D:\Program Files\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe`

1. `--headless --import`：导入工程，生成 `.godot/` 与 `.import` 边车文件。
2. 以 `--headless res://demo/demo.tscn --quit-after N`：运行 demo，输出应含
   `[CoreKit] v0.1.0 ready` 与 `[CoreKit] demo scene loaded — ...`，且无报错。

## git

`git init` + 首次提交。`.godot/` 缓存不入库；`icon.svg.import` 等边车文件入库。
