# godot-core-kit ResourceManager 子系统设计

- 日期:2026-07-02
- 状态:已确认,待实现
- 版本目标:0.4.0
- 前置:`2026-07-02-corekit-facade-design.md`(总纲;门面属性 `CoreKit.res`)、`2026-07-02-frame-scheduler-design.md`(Web 分帧通道依赖)

---

## 目标与定位

`ResourceManager` 是资源的**异步批量预热 + 缓存 + 手动释放**:大关卡进场前把资源列表分帧/后台加载完(带进度信号,可做加载条),游戏中 `get_resource` 全部命中缓存零卡顿。

定位边界(用户拍板):不做引用计数(手动 release,YAGNI)、不做依赖分析/自动收集、不做加载优先级、不做资源热重载。

**平台双通道,对外 API 完全一致**(设计阶段已定):桌面走 `ResourceLoader.load_threaded_*`;Web/无线程平台退化为把逐个同步 `load()` 塞进 FrameScheduler 预算队列分帧消化。

## Public API(GDScript 精确签名)

```gdscript
extends Node
## ResourceManager —— 异步批量预热 + 缓存 + 手动释放。

## 批次内每完成一个资源广播一次。
signal batch_progress(loaded: int, total: int)

## 当前批次全部完成(含失败项)后广播一次。
signal batch_completed

## 双通道开关;_ready 时自动探测(非 Web 且线程可用 → true),测试可覆写。
var use_threads: bool

## 由 CoreKit._ready 注入 FrameScheduler(Web 通道用)。
## 未注入且 use_threads 为 false 时,preload_batch 退化为当帧同步全量加载(仍发信号)。
func bind_ticker(ticker) -> void

## 异步预热一批资源路径。已缓存/重复路径自动去重跳过(计入 total 与 progress)。
## 批次进行中再次调用 → 追加进当前批次(total 增长)。
## 空数组 → 下一帧(call_deferred)直接广播 batch_completed。
func preload_batch(paths: Array) -> void

## 命中缓存直接返回;未命中同步 load 并入缓存;加载失败返回 null 并 CoreKit.log.error。
func get_resource(path: String) -> Resource

## 从缓存移除;存在返回 true,不存在返回 false。
func release(path: String) -> bool

## 清空全部缓存。
func clear() -> void

func is_cached(path: String) -> bool
func cached_count() -> int
```

## Behavior & data flow

- 缓存:`var _cache: Dictionary = {}`(path → Resource)。Resource 是引用计数的,从 `_cache` 移除后由引擎在最后一个使用方释放后回收——`release` 的语义是"kit 不再钉住它",不是"立刻销毁"(文档注明)。
- **线程通道**(use_threads):`preload_batch` 对每个未缓存路径 `load_threaded_request(path)` 并登记 `_pending`;`_process` 逐个查 `load_threaded_get_status`:
  - `LOADED` → `load_threaded_get` 入缓存,progress+1;
  - `FAILED`/`INVALID_RESOURCE` → `CoreKit.log.error`,progress+1(失败也推进,不卡死加载条);
  - `IN_PROGRESS` → 下帧再查。
  `_pending` 清空 → `emit batch_completed`。
- **分帧通道**(not use_threads):对每个未缓存路径 `_ticker.queue_task(闭包)`,闭包体:同步 `load(path)`(失败同上打日志)→ 入缓存 → progress+1 → 若是批内最后一个则 `emit batch_completed`。粒度是整资源:单个超大资源仍会在其加载帧超预算——预算队列"至少执行 1 个"的语义保证不停摆,尖峰不可避免(文档注明:Web 上超大资源请拆分或进场景前加载)。
- 批次簿记:`_batch_total`/`_batch_loaded` 两个计数;`batch_completed` 后归零。追加调用只增 `_batch_total` 并入队新路径。
- `get_resource` 对**正在异步加载中的路径**:线程通道下改调 `load_threaded_get`(阻塞取回,引擎语义)入缓存返回;分帧通道下直接同步 `load`(ResourceLoader 内部缓存使其接近免费)入缓存返回——两通道都保证"要就立刻给",队列里的重复项完成时发现已缓存则只推进度。

## Key decisions

| # | 维度 | 结论 | 理由 |
|---|---|---|---|
| 1 | 释放模型 | 手动 release/clear,无引用计数 | 用户拍板;引用计数易用错(漏/多 release),测试面大 |
| 2 | 平台探测 | `not OS.has_feature("web") and OS.can_use_threads()`,var 可覆写 | Web 默认导出无线程;覆写既是测试接缝也是消费方逃生门 |
| 3 | 失败项 | 计入进度 + log.error,不中断批次 | 加载条不能因一个坏路径卡 99%;失败在 get_resource 时自然暴露为 null |
| 4 | 双通道分叉位置 | 只分叉在 preload_batch 的执行引擎 | API/信号/缓存/簿记全共享,分叉面最小 |
| 5 | 并发批次 | 追加进当前批次 | 多批并行簿记是 YAGNI;追加语义简单且覆盖"边走边预热"场景 |
| 6 | ticker 依赖 | `bind_ticker` 注入,未注入降级当帧同步 | 依赖表纪律;降级路径保证脱离门面仍可用 |

## Web-export considerations

- Web 通道零线程:同步 `load` 分帧执行,主循环让出由 FrameScheduler 预算控制。
- `OS.has_feature("web")` 优先于 `can_use_threads()` 判断:即使 Web 启用了线程支持(SharedArrayBuffer),v1 仍走分帧通道——避免跨浏览器 COOP/COEP 配置差异带来的行为分裂(保守选择,文档注明)。

## Testable seams + test plan

接缝:`use_threads` 强制指定通道;`bind_ticker` 注入真 FrameScheduler 实例并**手动驱动 `ticker._process()`** 确定性推进分帧加载;测试资源用仓库内既有文件(`.gd` 脚本即 GDScript Resource,天然可 load)。线程通道在 headless 桌面下真实可用,轮询用"手动 `_process` + `OS.delay_msec(10)` + 上限次数"防挂死(沿用硬超时取证纪律)。

`test/test_resource_manager.gd`(headless,直接实例化):

1. `get_resource` 未命中同步加载入缓存;二次调用返回同一实例;`is_cached`/`cached_count` 正确。
2. `get_resource` 坏路径 → null,不崩。
3. `release` 存在/不存在的返回值;`clear` 后 `cached_count == 0`。
4. 分帧通道:use_threads=false + bind 真 ticker,`preload_batch` 3 个路径,手动驱动 ticker 帧;断言 `batch_progress` 序列 (1,3)(2,3)(3,3)、`batch_completed` 恰一次、全部入缓存。
5. 分帧通道去重:含已缓存路径与重复路径的批次,progress 计数正确、不重复加载。
6. 坏路径混入批次:progress 仍推进到 total、completed 正常广播、坏路径不入缓存。
7. 空批次:下一帧收到 `batch_completed`(call_deferred 语义,手动 flush 或驱动一帧)。
8. 追加批次:批次进行中再 preload_batch,total 增长且 completed 只在全部完成后广播一次。
9. 线程通道冒烟:use_threads=true,`preload_batch` 2 个真实路径,轮询驱动至 completed,资源入缓存(上限轮次防挂死)。

## 版本

ResourceManager v0.4.0 起:preload_batch 双通道异步预热(进度/完成信号)、get_resource 缓存、release/clear 手动释放、失败不中断。依赖:log(运行期)、ticker(注入,Web 通道)。
