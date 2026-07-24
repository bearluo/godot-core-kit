# CoreKit.updater(PackUpdater)设计 —— 第一轮:仅机制

> 日期:2026-07-23 ｜ 分支:`feat/kit-updater` ｜ 版本:0.22.0 → **0.23.0**(新子系统 = minor)
> 依据:[`docs/research/2026-07-23-godot-hot-update-feasibility.md`](../research/2026-07-23-godot-hot-update-feasibility.md)(逐条一手源 + §4b 实测)
> 实测存证分支:`proto/pack-cache-probe`

## 1. 目标与本轮边界

给 godot-core-kit 加**第 15 个子系统** `CoreKit.updater`:把「远程内容包的下载、校验、落盘、按序挂载」做成一个可复用机制。

**本轮只做机制**,交付一个能跑通 `run_all.ps1` 的完整子系统。**明确不做**(后续轮次):

- 「薄壳 base + 内容包」的**导出管线**(两套 preset / `--export-pack` / manifest 生成 / UID 预检)
- fortune-mill 接入与真机 OTA
- Web 端验证
- Android 自重启的真机验证(接口留好,平台能力待验)

## 2. 架构的核心:两相,中间隔着一次重启

这不是风格选择,是被 §4b 实测**逼出来**的结构。实测结论:GDScript 一旦在本进程加载过就被 `GDScriptCache` 钉死,`remove_script()`/`clear()` 均未经 ClassDB 暴露,**脚本层无法在运行时逐出**。因此含脚本的内容包,换逻辑**必须重启进程**。

于是热更的生命周期天然裂成两半,而且两半发生在**不同的进程里**:

```
相 A ── 启动期 / 同步 / 无网络 / 游戏侧零调用
   CoreKit._init()
     └─ updater 读 user:// 本地安装状态
        → 校验目标引擎版本
        → 按记录顺序 load_resource_pack()
   结果:只能查询(见 §4 的陷阱),不能用信号

════════ 进程边界(重启屏障)════════

相 B ── 运行期 / 异步 / 联网 / 显式三动词
   check(manifest_url) → download(plan) → restart_to_apply()
   下载完成只是「暂存好了」,不改变本进程的任何行为
```

调用方心智模型只有三个词:**check → download → restart**。启动期那一整套(读状态、校验引擎版本、按序挂载、失败降级)**完全不需要调用方知道**——这就是这个模块的深度所在。

## 3. 放门面,不放 off-facade

`load_resource_pack` 必须在 autoload `_init()`、任何游戏内容加载**之前**执行(研究 §4 的时机 Note)。做成门面子系统,`CoreKit._init()` 天然就是那个时刻——**约束被编码进结构里,接入方没有搞错顺序的入口**。

做成 off-facade 类(如 `KitOffline`)则要求接入方自己在某个 autoload 的 `_init()` 里 `new`,顺序一错就静默失效,且失效表现是「更新没生效」,极难排查。这是本设计里最重要的一次「用结构消灭错误」。

**代价(须写进文档)**:接入方必须保证 `CoreKit` 注册在任何加载游戏内容的 autoload **之前**。

命名随门面惯例(子系统不带 `class_name`):

| 项 | 值 |
|---|---|
| 脚本 | `addons/godot-core-kit/systems/pack_updater.gd` |
| 节点名 | `PackUpdater` |
| 门面属性 | `CoreKit.updater` |
| living doc | `addons/godot-core-kit/docs/systems/pack-updater.md` |

## 4. ⚠️ 陷阱:相 A 不能用信号

最初设计给相 A 配了 `mounted(pack_id)` / `mount_failed(pack_id, reason)` 信号。**这是错的**:挂载发生在 `CoreKit._init()`,此时游戏代码一行都还没跑,**没有任何对象能连上这些信号**,它们永远无人接收。

→ **相 A 的结果一律做成可查询状态**,相 B 才用信号(那时游戏已在运行,连得上)。

## 5. 公开接口

```gdscript
# ── 相 A:启动期自动执行,结果只能查询 ──────────────────────
func mounted_packs() -> Array[String]      ## 本次启动成功挂载的 pack id,按挂载序
func mount_errors() -> Dictionary          ## pack_id -> reason,启动期挂载失败记录
func local_version(pack_id: String) -> int ## 已安装版本;未安装返回 0

# ── 相 B:运行期,异步 ──────────────────────────────────
signal update_available(plan: Dictionary)  ## 有更新;plan 可直接喂给 download()
signal up_to_date()                        ## 已是最新
signal check_failed(reason: String)
signal progress(pack_id: String, done_bytes: int, total_bytes: int)
signal downloaded(pack_id: String)
signal download_failed(pack_id: String, reason: String)
signal ready_to_apply()                    ## 全部包已校验落盘并写入暂存状态

func check(manifest_url: String) -> void
func download(plan: Dictionary) -> void
func restart_to_apply() -> bool            ## 平台不支持自重启时返回 false

# ── 接缝 ────────────────────────────────────────────
func set_transport(t) -> void              ## 默认 HttpPackTransport
func set_mounter(m) -> void                ## 默认真实 ProjectSettings 挂载
```

`check` 与 `download` 刻意**不合并**:真实产品几乎总要在两者之间插一句「这次更新 150MB,现在下载吗?」。

## 6. 接缝(两个适配器才算真接缝)

| 接缝 | 生产适配器 | 测试适配器 | 为什么是真接缝 |
|---|---|---|---|
| **传输** | `HttpPackTransport`(HTTPRequest) | 内存假件 | kit 的 headless 测试门**没有网络** |
| **挂载** | 真实 `ProjectSettings.load_resource_pack` | 记录调用的假件 | 要能纯测挂载顺序与失败路径 |

形状照抄 SaveManager 的 `SaveSerializer` / `set_serializer` 先例。

**纯函数内核**(照 `save_manager.gd` 的 `--- 可测接缝(纯函数,不碰磁盘/autoload) ---` 那节):

- `_plan(manifest, state) -> {ok, packs, reason}` —— 算出要下哪些包。字典进字典出,是最容易错也最该被穷举测试的部分。
- `_engine_ok(manifest_engine) -> bool` —— 引擎版本闸门(研究 §3:包头拒收更新版引擎导出的包)
- `_mount_order(installed) -> Array` —— 挂载顺序解析(研究 §1:同路径冲突后挂者胜,顺序敏感)

## 7. 数据格式

**服务器 manifest**:

```json
{
  "engine": "4.7",
  "packs": [
    {"id": "content", "version": 3, "url": "https://cdn/content-v3.pck",
     "size": 12345678, "sha256": "…", "order": 0}
  ]
}
```

**本地状态** `user://kit_updater/state.json`:

```json
{
  "engine": "4.7",
  "installed": [
    {"id": "content", "version": 3, "file": "user://kit_updater/packs/content-v3.pck",
     "sha256": "…", "order": 0}
  ]
}
```

**为什么不用 `CoreKit.saves`**:相 A 在 `_init()` 里读状态,而跨子系统接线只能在 `_ready()`(依赖纪律),`_ready()` 对挂载来说**太晚了**。故 updater 自己做这一份文件 I/O。这是依赖纪律的一个合理例外,须在 docstring 说明。

## 8. 失败路径(显式设计,不靠异常)

`load_resource_pack` 失败无异常、只返回 `false`(研究 §8),所有失败都必须显式处理:

| 失败 | 行为 |
|---|---|
| manifest 拉取失败 | `check_failed(reason)`;本地状态不变 |
| 引擎版本不匹配 | `check_failed("engine_mismatch:x.y")`;**不下载** |
| 下载中断 | `download_failed(pack, reason)`;暂存区丢弃,已安装集合不变 |
| sha256 不符 | `download_failed(pack, "checksum")`;同上 |
| 启动期挂载失败 | 记进 `mount_errors()`,**游戏继续跑**(用已挂上的部分),不崩 |

**原子暂存纪律**(照 SaveManager 的 temp+rename):新包先下到暂存区,**全部**校验通过后才原子改写 `state.json`。任何中途失败都不会让已安装集合处于半更新状态。

## 9. 本轮 YAGNI

断点续传、差分/增量包、包加密、并发下载(本轮串行)、下载调度/重试退避、UI。

## 10. 测试计划(`test/test_pack_updater.gd`)

- **纯函数**:已最新 / 有新包 / 有升级包 / 引擎不匹配 / manifest 畸形 / 挂载顺序
- **传输假件**:check 成功与失败、download 成功、sha256 不符
- **原子性**:下载失败后 `state.json` 逐字节未变
- **挂载假件**:按 order 挂载、单包失败被记进 `mount_errors()` 且不影响其余
- **真 zip 集成测**:运行时造一个真 zip → 真 `load_resource_pack` → `FileAccess` 读到包内文件(证明机制端到端成立,不只是假件自洽)

验收:`powershell -File test\run_all.ps1` 以 `=== SUMMARY FAILS=0 ===` 结尾。

## 11. 遗留

`restart_to_apply()` 在 Android 上是否真能自重启(`OS.set_restart_on_exit()` + `quit()`)**未验证**。接口返回 `bool`,平台不支持时返回 `false`,由接入方降级为「提示玩家手动重开」。真机验证排在后续轮次。
