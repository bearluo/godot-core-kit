# 单线程 Web / 微信小游戏下的资源预载能力（GitLab #2）

- 日期：2026-10-12
- 关联：GitLab #2（Part of #1）
- 版本基线：Godot `4.7-stable`（tag 指向 `5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88`），kit `main@00f93bc`
- 来源原则：只用 Godot 源码、官方文档、kit 代码。本文所有引擎行为结论均来自**读源码**，未在 Web/微信运行时实测的部分单独标注「未实测」。

源码链接前缀：`https://github.com/godotengine/godot/blob/4.7-stable/`（下文简写为 `G/`）。

## 一句话结论

在不带线程的构建（`threads=no`，Web nothreads 模板，也是微信小游戏所用的模板）里，`ResourceLoader.load_threaded_request` **不报错，也不分帧，而是在调用当场同步把整个资源（含全部依赖）加载完再返回**；之后 `load_threaded_get_status` 立刻是 `THREAD_LOAD_LOADED`（或 `FAILED`），`progress` 直接为 `1.0`。也就是说**拿不到单个资源内部的进度**，能拿到的进度粒度只有「按资源个数」。kit 现有 `CoreKit.res` 在 Web 上本来就不走这套 API，而是「每帧在预算内同步 `load()` 一个资源」，效果与引擎行为等价、但更可控，方向是对的。

## 1. 「没有线程」在引擎里是怎么落地的

| 事实 | 出处 |
|---|---|
| `threads` 是 SCons 构建选项，默认 `True`；关掉时产物后缀加 `.nothreads` | [G/SConstruct#L187](https://github.com/godotengine/godot/blob/4.7-stable/SConstruct#L187)、[#L1048-L1049](https://github.com/godotengine/godot/blob/4.7-stable/SConstruct#L1048-L1049) |
| 只有 `threads=yes` 才定义宏 `THREADS_ENABLED` | [G/SConstruct#L1207-L1209](https://github.com/godotengine/godot/blob/4.7-stable/SConstruct#L1207-L1209) |
| Web 平台 `threads=yes` 时才加 `-sUSE_PTHREADS=1`（依赖 SharedArrayBuffer）；`threads=no` 时强制关 `proxy_to_pthread` | [G/platform/web/detect.py#L273-L288](https://github.com/godotengine/godot/blob/4.7-stable/platform/web/detect.py#L273-L288) |
| 无 `THREADS_ENABLED` 时 `Thread` 是空壳：`start()` 什么都不做，`is_main_thread()` 恒为 `true`，`get_caller_id()` 恒为主线程 ID | [G/core/os/thread.h#L180-L204](https://github.com/godotengine/godot/blob/4.7-stable/core/os/thread.h#L180-L204) |
| 无 `THREADS_ENABLED` 时，`Main` 以 `init(0, 0)` 初始化 `WorkerThreadPool`，即**线程数为 0** | [G/main/main.cpp#L2133-L2146](https://github.com/godotengine/godot/blob/4.7-stable/main/main.cpp#L2133-L2146) |
| GDScript 侧可用 `OS.has_feature("threads")` / `"nothreads"` 判别，二者直接取决于 `THREADS_ENABLED` | [G/core/os/os.cpp#L618-L631](https://github.com/godotengine/godot/blob/4.7-stable/core/os/os.cpp#L618-L631) |
| 官方文档：4.3 起支持单线程 Web 导出，「不能使用线程，性能不如多线程导出」；开 Thread Support 才能用多线程，且需要跨域隔离响应头 | [exporting_for_the_web.rst#L41-L43、#L169-L178](https://github.com/godotengine/godot-docs/blob/stable/tutorials/export/exporting_for_the_web.rst#L169-L178)（docs `stable` 分支，`conf.py` 版本号为 4.7） |

微信小游戏：kit 的微信 spike 导出预设用 `variant/thread_support=false`（[docs/research/2026-07-27-kit-wechat-spike-report.md#L57](2026-07-27-kit-wechat-spike-report.md)），微信官方也写明「不支持多线程(pthread)」（[docs/research/2026-07-27c-wechat-official-common-adaptation.md#L73](2026-07-27c-wechat-official-common-adaptation.md)）。所以微信侧跑的就是上面这个 nothreads 构建，下面的结论同样适用。**微信运行时里实际调用 `load_threaded_*` 的表现：未实测**（只由源码推出）。

## 2. `load_threaded_request` 在线程数为 0 时的实际路径

1. `load_threaded_request` → `_load_start(..., LOAD_THREAD_SPAWN_SINGLE 或 LOAD_THREAD_DISTRIBUTE, ..., p_for_user=true)`，返回 `OK`/`FAILED` 只看 token 是否有效。
   [G/core/io/resource_loader.cpp#L700-L703](https://github.com/godotengine/godot/blob/4.7-stable/core/io/resource_loader.cpp#L700-L703)
2. 在 `_load_start` 里，非 `LOAD_THREAD_FROM_CURRENT` 模式一律调用 `WorkerThreadPool::add_native_task(&ResourceLoader::_run_load_task, ...)`。这里**没有任何针对无线程的分支**，也没有报错路径。
   [G/core/io/resource_loader.cpp#L836-L851](https://github.com/godotengine/godot/blob/4.7-stable/core/io/resource_loader.cpp#L836-L851)
3. `add_native_task` → `_add_task` → `_post_tasks`。`_post_tasks` 开头：`threads.is_empty()` 且不是 pump task 时，**直接在调用线程上逐个 `_process_task` 执行完再返回**（源码注释："Fall back to processing on the calling thread if there are no worker threads"）。
   [G/core/object/worker_thread_pool.cpp#L224-L237](https://github.com/godotengine/godot/blob/4.7-stable/core/object/worker_thread_pool.cpp#L224-L237)、[#L343-L381](https://github.com/godotengine/godot/blob/4.7-stable/core/object/worker_thread_pool.cpp#L343-L381)
4. `_run_load_task` 里调用 `_load(...)` 完整加载，结束时强制 `load_task.progress = 1.0`。
   [G/core/io/resource_loader.cpp#L541-L556](https://github.com/godotengine/godot/blob/4.7-stable/core/io/resource_loader.cpp#L541-L556)
5. `use_sub_threads=true`（`LOAD_THREAD_DISTRIBUTE`）同样会经过 `add_native_task`，也就同样在主线程上同步执行，**无法因此获得并行或分帧**（依据第 3 条推出，子资源加载路径未逐行追踪）。

**结论：同步阻塞。** `load_threaded_request` 返回时资源已经加载完毕（或已失败）。期间主线程卡住，加载屏动画不会刷新。

### 关于 `load_threaded_get_status` 和进度

- `load_threaded_get_status` 读的是 task 的 `status`；进度来自 `_dependency_get_progress`：有子任务时按「子任务平均 ×0.5 + 自身 ×0.5」计算，并取历史最大值。
  [G/core/io/resource_loader.cpp#L856-L884](https://github.com/godotengine/godot/blob/4.7-stable/core/io/resource_loader.cpp#L856-L884)、[#L887-L929](https://github.com/godotengine/godot/blob/4.7-stable/core/io/resource_loader.cpp#L887-L929)
- 无线程时，第一次调用 `get_status` 前任务已经跑完，因此**第一次查询就是 `THREAD_LOAD_LOADED`/`FAILED`，progress = 1.0**。不会看到 0→1 的中间值。
- 资源 loader 在加载过程中会写 `r_progress`（`_load(..., &load_task.progress)`），但写的时候主线程正在执行这段同步加载，GDScript 没有机会读到。
- 「同一帧内在主线程反复轮询」时，`get_status` 会调用 `_ensure_load_progress()`，后者只做 `RenderingServer::sync()`，**不会推进加载本身**，也不会让出一帧。
  [G/core/io/resource_loader.cpp#L914-L927](https://github.com/godotengine/godot/blob/4.7-stable/core/io/resource_loader.cpp#L914-L927)、[#L1156-L1165](https://github.com/godotengine/godot/blob/4.7-stable/core/io/resource_loader.cpp#L1156-L1165)
- `load_threaded_get` 在主线程、状态仍为进行中时，会 `delay_usec(1000)` 循环等待；无线程时这个循环不会进入（状态已完成）。
  [G/core/io/resource_loader.cpp#L953-L976](https://github.com/godotengine/godot/blob/4.7-stable/core/io/resource_loader.cpp#L953-L976)
- 官方文档对 `load_threaded_get_status` 的描述是返回 0.0–1.0 的完成比例，并建议在不同帧里调用；**文档没有说明无线程构建下的行为**。
  [G/doc/classes/ResourceLoader.xml#L119-L139](https://github.com/godotengine/godot/blob/4.7-stable/doc/classes/ResourceLoader.xml#L119-L139)
- 4.7 的 `ResourceLoader` 没有分步加载 API（Godot 3 的 `ResourceInteractiveLoader` 已不存在）；公开方法只有 `load` / `load_threaded_*` / `exists` / `get_dependencies` 等。
  [G/doc/classes/ResourceLoader.xml](https://github.com/godotengine/godot/blob/4.7-stable/doc/classes/ResourceLoader.xml)

### 附：带线程的构建，但线程池为 0

`threads=yes` 的构建如果把 `threading/worker_pool/max_threads` 设为 0，`init(0, …)` 后 `threads` 同样为空，`_post_tasks` 也会走同一条「在调用线程上同步执行」的分支（[G/main/main.cpp#L2139-L2141](https://github.com/godotengine/godot/blob/4.7-stable/main/main.cpp#L2139-L2141) + [worker_thread_pool.cpp#L811-L836](https://github.com/godotengine/godot/blob/4.7-stable/core/object/worker_thread_pool.cpp#L811-L836)）。不过这种配置与本问题无关，**也未实测**。

## 3. kit 现状：`CoreKit.res`（ResourceManager）

文件：`addons/godot-core-kit/systems/resource_manager.gd`，文档：`addons/godot-core-kit/docs/systems/resource-manager.md`。

- **双通道**，对外 API 和信号一致（`preload_batch(paths)` / `batch_progress(loaded, total)` / `batch_completed` / `get_resource`）。`resource_manager.gd#L4-L10`、`#L15-L21`
- **通道选择**：`use_threads = not OS.has_feature("web") and OS.has_feature("threads")`。`resource_manager.gd#L36`
  - 线程通道（桌面）：`load_threaded_request` + `_process` 里轮询 `load_threaded_get_status`。`#L65-L68`、`#L116-L127`
  - 分帧通道（Web/无线程）：每个路径包装成 `_frame_load`（同步 `load()`），塞进 `CoreKit.ticker`（FrameScheduler）的预算队列；默认每帧 2 ms 预算，且「每帧至少执行 1 个」。`resource_manager.gd#L69-L75`、`#L131-L139`；`frame_scheduler.gd#L6-L15`
- **进度只到资源个数**：两条通道都只在「一个资源完成」时发出 `batch_progress`，线程通道也**没有读取** `get_status` 的 `progress` 参数。`#L142-L147`
- **已知边界**（文档已写明）：分帧粒度是一整个资源，单个大资源会在它被加载的那一帧超出预算。`resource-manager.md#L58`
- `CoreKit.scenes.change_scene` **没有使用** `CoreKit.res`：它在遮罩盖住后直接同步 `load()` 目标场景（`scene_manager.gd#L8`、`#L70`、`#L193-L201`）。目前没有加载屏，也没有进度。

与第 2 节对照：在 nothreads 构建上，假如让 kit 走线程通道，每次 `load_threaded_request` 都会同步加载完整资源，`preload_batch` 一次排入 N 个就等于当帧卡住 N 个资源的加载时间。分帧通道每帧只加载一个（或在预算内加载几个），所以 **kit 的 Web 降级是必要且正确的**。

## 4. 对场景切换加载屏的建议

**可行的预载方案（单线程 Web / 微信）**

1. **把场景拆成依赖清单，再分帧逐个加载。** 用 `ResourceLoader.get_dependencies(scene_path)` 取出依赖（格式为 `uid::::path` 或纯路径，取第三段作为 fallback 路径；[ResourceLoader.xml#L44-L58](https://github.com/godotengine/godot/blob/4.7-stable/doc/classes/ResourceLoader.xml#L44-L58)），把这些依赖加上场景本身交给 `CoreKit.res.preload_batch`，在分帧通道里每帧加载一个。依赖都进了引擎的 ResourceCache 后，最后 `load(scene)` 只剩场景本体，耗时很短。
   - `get_dependencies` 只返回直接依赖；需要更细粒度时可以递归展开。是否值得递归，要看实际场景的依赖深度。**依赖进入缓存后能缩短最终 `load` 的时间，这一点是源码推断，Web 上的实际耗时未实测。**
   - kit 把加载结果放进自己的 `_cache` 并一直持有引用，直到调用 `CoreKit.res.release`/`clear`（`resource_manager.gd#L99-L104`），所以依赖不会在最终 `load` 之前被回收，引擎缓存能够命中。
2. **加载屏本身必须是已经加载好的轻量资源。** 在开始预载之前先显示加载屏，并至少等一帧让它画出来，否则第一个同步 `load` 会让它在出现之前就被卡住。
3. **大资源要拆开。** 任何单个资源（大纹理图集、大音频、大 `.tscn`）在单线程上都是一次不可分割的卡顿，只能靠拆小资源或提前在空闲时预载来解决。

**进度能不能拿到**

- **能拿到「已完成资源数 / 总数」**：用 `batch_progress(loaded, total)`，单线程和多线程表现一致。
- **拿不到单个资源内部的进度**：单线程下 `load_threaded_get_status` 的 progress 只会出现 1.0；4.x 也没有分步加载 API。
- 因此进度条要以「资源个数」为单位。依赖清单拆得越细，进度条越平滑。如果需要按大小加权，可以在 kit 外部用文件大小估算权重；**这只是可选优化，不在本研究范围内，也未验证**。

**kit 应该暴露什么（建议，最小改动）**

1. `CoreKit.scenes.change_scene` 增加一个可选的「预载后再切换」模式：盖上遮罩 → 显示加载屏 → `CoreKit.res.preload_batch(依赖 + 场景)` → 等待 `batch_completed` → 实例化。期间把 `batch_progress` 转发为场景层信号（例如 `scene_load_progress(loaded, total)`），加载屏 UI 直接订阅即可。
2. `CoreKit.res` 增加一个辅助函数：把一个路径展开成「依赖路径 + 自身」，解析 `::` 格式。这样上层不需要了解 `get_dependencies` 的字符串格式。
3. **继续保持 Web 恒走分帧通道**，不要尝试在 nothreads 下调用 `load_threaded_*`：它既拿不到进度，又会把一批资源集中卡在同一帧。
4. 桌面线程通道可以选择读取 `get_status` 的 `progress`，让进度条更平滑；但这会让两个平台的进度语义不同（小数和整数），**建议保持现在「按个数」的统一语义**，不做这项改动。

## 未确认 / 待实测

- 微信小游戏运行时（真机和开发者工具）中实际调用 `load_threaded_request` 的表现：只由源码推出，未实测。
- 分帧预载后最终 `load(scene)` 能节省多少时间，以及 2 ms 预算在低端机上是否合适：未实测。
- `use_sub_threads=true` 时子资源在无线程下的具体执行顺序：只追到 `add_native_task` 层面，未逐行追踪。
