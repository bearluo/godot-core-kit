# PackUpdater(`CoreKit.updater`)

## 职责

内容包(`.pck`/`.zip`)的**下载、校验、落盘、按序挂载**机制,支撑「分包瘦身 + 热更」:基础包只装启动壳,其余内容做成远程包,首启/按需下载到 `user://`,运行时经 `ProjectSettings.load_resource_pack` 挂进 `res://`。

热更的生命周期天然裂成两相,且两相发生在**不同进程里**(这是被引擎行为逼出来的结构,不是风格选择):

- **相 A —— 启动期**:在 `CoreKit._init()` 里(早于任何游戏内容 `preload`/`load`)自动挂载已安装的包。结果**只能查询**,不用信号——挂载发生时游戏代码尚未运行,信号无人接收。
- **相 B —— 运行期**:联网的三动词流程 `check → download → restart`。下载完成只是「暂存好了」,**不改变当前进程的任何行为**;必须过一道**进程重启**屏障才生效。

> ⚠️ **含 GDScript 逻辑的包,换逻辑必须重启进程。** 实测(`docs/research/2026-07-23-godot-hot-update-feasibility.md` §4b)证明:GDScript 有独立于 `ResourceCache` 的第二层缓存 `GDScriptCache`,一旦在本进程加载过就被钉死,且脚本层没有任何 API 能运行时逐出它。哪怕「退出子场景、释放全部引用、再挂新包、重进」也拿不到新逻辑。`reload_current_scene()` **不够**。纯资源/数据包在无活引用时**可能**中途生效,但不能作为默认承诺。

## 公开 API

### 相 A —— 启动期(自动执行,只可查询)

| 成员 | 说明 |
|---|---|
| `mount_installed() -> void` | 由 `CoreKit._init()` 调用;读 `state.json`,校验目标引擎版本,按 `order` 依次挂载。一般不需手调。 |
| `mounted_packs() -> Array[String]` | 本次启动成功挂载的 pack id,按挂载序。 |
| `mount_errors() -> Dictionary` | `pack_id -> reason`,启动期挂载失败记录(单包失败不影响其余)。 |
| `local_version(pack_id: String) -> int` | 已安装版本;未安装返回 `0`。 |

### 相 B —— 运行期(异步,信号驱动)

| 成员 | 说明 |
|---|---|
| `check(manifest_url: String) -> void` | 拉 manifest,与本地比对。 |
| `download(plan: Dictionary) -> void` | 按 plan 串行下载 + sha256 校验 + 原子落盘。 |
| `restart_to_apply() -> bool` | 触发自重启使更新生效;平台不支持(Web/headless)返回 `false`,由接入方降级为「提示玩家手动重开」。 |
| signal `update_available(plan)` | 有更新;`plan` 可直接喂给 `download()`。 |
| signal `up_to_date()` | 已是最新。 |
| signal `check_failed(reason)` | `transport` / `malformed` / `engine_mismatch:x.y`。 |
| signal `progress(pack_id, done, total)` | 下载进度。 |
| signal `downloaded(pack_id)` | 单包下载 + 校验通过。 |
| signal `download_failed(pack_id, reason)` | `checksum` / `network` 等;暂存丢弃,已安装集合不变。 |
| signal `ready_to_apply()` | 全部包已校验落盘并原子写入暂存状态,可 `restart_to_apply()`。 |

### 可注入接缝(默认即生产实现)

| 成员 | 默认 | 用途 |
|---|---|---|
| `set_transport(t)` | `HttpPackTransport`(`HTTPRequest`) | 换传输实现;单测注入内存假件(headless 无网络)。 |
| `set_mounter(m)` | 真 `ProjectSettings.load_resource_pack` | 换挂载实现;单测注入记录调用的假件以纯测顺序/失败路径。 |
| `set_base_dir(dir)` | `user://kit_updater` | 换数据根目录(状态、暂存、已装包)。 |

## 依赖

零跨子系统依赖(不经 `bind_*`)。两个接缝是**子系统内部**的适配点。状态文件 `user://kit_updater/state.json` 由本子系统**自读写**,不走 `CoreKit.saves`——因为跨子系统接线只能在 `_ready`,而相 A 的挂载在 `_init`,`_ready` 对它太晚。这是依赖纪律的一个有意例外。

## 用法示例

```gdscript
# 相 B:运行期检查并更新(通常挂在「检查更新」按钮或启动后台)
func _check_for_updates() -> void:
    CoreKit.updater.update_available.connect(_on_update_available)
    CoreKit.updater.up_to_date.connect(func(): print("已是最新"))
    CoreKit.updater.check_failed.connect(func(r): push_warning("检查失败: %s" % r))
    CoreKit.updater.check("https://cdn.example.com/manifest.json")

func _on_update_available(plan: Dictionary) -> void:
    # 真实产品几乎总要在此插一句「这次更新 XX MB,现在下载吗?」
    CoreKit.updater.ready_to_apply.connect(_on_ready)
    CoreKit.updater.download_failed.connect(func(id, r): push_warning("下载 %s 失败: %s" % [id, r]))
    CoreKit.updater.download(plan)

func _on_ready() -> void:
    # 含逻辑的更新必须重启才生效
    if not CoreKit.updater.restart_to_apply():
        # Web/headless 等不支持自重启:提示玩家手动重开
        show_toast("更新已就绪,请重启游戏")
```

`manifest.json` 由导出管线 [`KitPackManifest`](../tools/export-pipeline.md) 生成;`manifest.json` /
本地 `state.json` 结构见设计文档 `docs/design/2026-07-23-kit-updater-design.md` §7。

## 注意事项

- **`CoreKit` 必须注册在任何加载游戏内容的 autoload 之前**。相 A 靠「在 `_init` 尽早挂包」成立;若别的 autoload 先于 `CoreKit` 加载了内容,那些内容就锁定在旧包上。
- **引擎版本锁死**:包头会拒收「用比运行引擎更新的版本导出的包」。manifest 与 `state.json` 都带 `engine` 字段并在挂载/检查前严格校验(不匹配 → 不挂/不下)。**升级 Godot 版本时,所有历史内容包都要重新导出。**
- **原子性**:下载走「暂存区 → 全部 sha256 校验通过 → temp+rename 改写 `state.json`」。任何中途失败都不会让已安装集合处于半更新状态。
- **加密**:起步**不加密**(用官方标准模板)。PCK 加密要求自编译导出模板并全链同 key,会改动整条构建链,留作后续可选项。
- **导出管线已交付**:产出「薄壳 base + 内容包 + manifest.json」的工具见 [export-pipeline](../tools/export-pipeline.md)(`KitPackManifest` + `build_manifest.gd`,manifest 格式与本子系统 `check()` 逐字咬合)。fortune-mill 真机 OTA、Web 端验证、Android 自重启真机验证仍在后续轮次;`restart_to_apply()` 在 Android 上的自重启能力**尚未真机验证**。
- **测试边界**:`HttpPackTransport`(真网络)不被 headless 门覆盖;`test_pack_updater.gd` 经注入假件覆盖 `check`/`download` 行为,另有一个真 zip → 真 `load_resource_pack` 的端到端集成测。
