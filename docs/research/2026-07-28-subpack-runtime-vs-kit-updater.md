# `SubpackRuntime` vs `CoreKit.updater` —— 委托可行性评估

> 日期:2026-07-28  
> 起因:微信导出管线自带 `addons/godot_subpack_runtime/subpack_runtime.gd`(纯 GDScript,885 行),表面上覆盖了 `CoreKit.updater` 的大部分职责,且**自带微信分包通道**。评估是否应让 kit 在 Web/微信上委托给它。  
> 结论先行:**不委托。但借鉴三点,并新增一条投递通道。**  
> 证据等级沿用 spike 报告惯例:【实测】本机跑出来的;【据码】读源码确知;【推断】由已有实测结论外推,未直接验证。

## 0. 一句话结论

两者名字像、API 像,**更新模型根本不同**:`CoreKit.updater` 是**版本化更新**(有「有没有新版本」的概念,跨包事务性提交),`SubpackRuntime` 是**按需加载**(只有「这个包在不在」,逐包独立)。委托会丢掉 kit 的核心契约,并且**把 kit 已经修好的两个 Web/微信 落盘 bug 请回来**(§3)。

## 1. 职责对照

| 维度 | `CoreKit.updater`(PackUpdater) | `SubpackRuntime` |
|---|---|---|
| 形态 | 门面子系统 `CoreKit.updater`,`extends Node` | `class_name SubpackRuntime extends RefCounted`,游戏自己 `new()` |
| **更新模型** | **版本化**:manifest 带 `version`,与本地 `state.json` 比对算 plan;有 `update_available` / `up_to_date` | **按需加载**:无版本比对,只问「本地有没有 / 缓存有没有 / 远端拉得到不」 |
| 启动行为 | `mount_installed()` 按 `order` 把已安装集合全挂上 | 不自动挂,游戏显式 `ensure_subpack("level_02")` |
| 持久状态 | `state.json` 记**已安装什么**(id/version/file/sha256/order) | `cache_index.json` 只记 **LRU 元数据**(path/sha/size/last_access),不记"装了什么" |
| **原子性** | **全有或全无**:全部包下完并校验通过才一次性改写 `state.json`;任一失败丢弃暂存、`state.json` 逐字节不变 | **逐包独立**:每包各自下载→校验→进缓存→挂载,无跨包事务 |
| **引擎版本守卫** | ✅ manifest 与 state 带 `engine`,不符则一个都不挂/不下(包头会拒收更新引擎导出的包) | ❌ 无 |
| 依赖图 | ❌ 只有 `order` 线性序 | ✅ `dependencies` 递归解析 + 环检测 |
| 缓存预算 | ❌ 下了就一直在 | ✅ `cache_budget_mb` + LRU 淘汰(默认 45 MB) |
| **微信分包通道** | ❌ | ✅ `GODOTSDK.load_pack(分包名, pck路径, onProgress, onDone)` |
| 事件面 | Godot signal(`progress`/`downloaded`/`ready_to_apply`/…) | `drain_runtime_events()` 拉数组,无 signal |
| 重启屏障 | ✅ `restart_to_apply()` 有明确契约与降级 | ❌ 不涉及 |
| 测试 | 进 kit 门 `run_all.ps1` | 无(第三方组件) |

**交集只有中间那段**:下载 → sha256 校验 → `ProjectSettings.load_resource_pack`。两头(版本决策 / 重启落地)`SubpackRuntime` 都不管。

## 2. 关键前提已实测:挂载不需要适配

【实测】`ProjectSettings.load_resource_pack("user://…")` 在微信小游戏上**原生可用**(探针 `kit-wechat-spike@0f29c5b`):

```
① zip 落盘 size=256                                    ZIPPacker 能往 user:// 写非空文件
② GODOTSDK=true  wx 真实路径=http://usr/user/probe_pack.zip
③ load_resource_pack=true  before=false  after=true  content=hello-from-pack
```

所以 `_mount_one` 那行原样可用。**「委托是为了拿到微信挂载能力」这个动机不成立** —— kit 本来就能挂。

## 3. 决定性反对理由:委托会请回两个已修的 bug

`SubpackRuntime` 的下载路径踩着 kit 在 0.24.1 / 0.24.3 已经实测并修掉的两个坑:

**① `download_file` 在 Web/微信 上不落盘**(kit v0.24.1 修)

```gdscript
# subpack_runtime.gd:560-563  【据码】
var request := HTTPRequest.new()
request.use_threads = not OS.has_feature("web")
request.download_file = target_path        # ← kit 实测:浏览器里报 200 但字节不真正落盘
```

kit 的 `HttpPackTransport` 在 web 上改走「`body` 收进内存 → `FileAccess.store_buffer` 落盘」正是因为这个。`SubpackRuntime` 只区分了 `use_threads`,下载路径没分叉。

它第 604 行只检查 `FileAccess.file_exists(target_path)` 就返回成功 —— 【推断】文件被创建但为空时这里会放行,随后 `_verify_pack_file` 的 sha256 对不上而失败。所以**不会静默损坏,但远程包在微信上会一直下不下来**。

**② `rename` 在微信 FS shim 上丢内容**(kit v0.24.3 修)

```gdscript
# subpack_runtime.gd:312  【据码】
var rename_error := DirAccess.rename_absolute(temp_path, cached_pack_path)
```

kit 的 `_replace_file` / `_write_state_atomic` 在 web 上改成整读整写复制,正是因为微信小游戏的 FS shim 上 `rename` **报成功但目标文件是空的**。

> 【推断】这两条都由 kit 已有实测结论外推,未在 `SubpackRuntime` 上直接复现。**可验证**:模拟器 `project.config.json` 里 `urlCheck: false`,不校验合法域名,可以起本地 HTTP server 喂 manifest + pck 实测(见 §6)。

## 4. 但有三点值得借鉴

| 借鉴点 | 说明 | 代价 |
|---|---|---|
| **依赖图** | `dependencies` 递归 + 环检测,比 kit 的 `order` 线性序表达力强 | 现有 `order` 够用时是过度设计,等真有互相依赖的内容包再说 |
| **缓存预算 + LRU** | 微信用户数据目录只有 200 MB,内容包越攒越多迟早顶上限。kit 现在**只增不减** | 需要「哪些包可淘汰」的语义 —— 但 kit 的包是**已安装**不是**缓存**,淘汰了 `state.json` 就对不上,不能照抄 |
| **错误信息本地化** | `_http_request_result_name` 把 14 种 `HTTPRequest.RESULT_*` 翻成中文,且 `response_code == 0` 时主动提示查 CORS / 合法域名白名单 | 无,纯收益 |

## 5. 最有价值的发现:微信分包是绕开备案的第二条投递通道

【据码】`SubpackRuntime._ensure_single_subpack` 的优先级是:

```
本地 res:// → 微信分包(GODOTSDK.load_pack) → user:// 缓存 → 远程 HTTP
```

中间那步是 kit 完全没有的通道:**内容包作为微信分包随代码包一起发布**,运行时按需 `wx.loadSubpackage` 拉下来再挂。

| | CDN 投递(kit 现有) | 微信分包投递 |
|---|---|---|
| 需要 ICP 备案 + 合法域名白名单 | **是**(当前阻塞点) | **否** |
| 受 30 MB 总包限制 | 否 | **是** |
| 需过审 | 否 | **是**(随版本发布) |
| 能否随时更新 | 能 | 不能(要发版) |

**当前备案没下来,微信分包是唯一真能跑通的通道。** 这不是"更新",是"瘦身+按需下载" —— 但对「首包小、内容按需」这个目标是有效的,且立刻可用。

## 6. 建议

**不委托**。理由按重要性:

1. 更新模型不同,委托等于把 kit 的**版本化更新 + 跨包事务 + 引擎版本守卫**三个核心契约丢掉,换回一个 kit 已经有的挂载能力(§2 已证明不需要换)。
2. 委托会请回两个已修的 Web/微信 落盘 bug(§3)。
3. kit 门面是**跨平台一致**的 API;委托会让微信/Web 的行为与桌面分叉,`state.json` 语义也无处安放。

**接下来做什么,按性价比排**:

| 优先级 | 事项 | 阻塞 |
|---|---|---|
| P0 | 【可立即做】起本地 HTTP server(模拟器 `urlCheck:false`)实测 kit `HttpPackTransport` 在微信上能否完整下载 + 校验 + 挂载,把 §3 的推断变成实测,顺带坐实 updater 端到端在微信可跑 | 无 |
| P1 | 借鉴 `_http_request_result_name` 的中文错误信息 + `response_code==0` 提示查域名白名单 | 无 |
| P2 | 微信分包投递通道(§5):给 `PackUpdater` 加「包已随分包发布」的来源,走 `GODOTSDK.load_pack` | 需先定 manifest 里怎么表达"这个包在哪个微信分包里" |
| P3 | `restart_to_apply()` 微信分支(`wx.restartMiniProgram`) | 【实测】模拟器里调用无效果,真机行为未验证 |
| — | 缓存预算/LRU、依赖图 | 现在都不需要,等真遇到再说 |

CDN 热更本身仍卡在 **ICP 备案 + 合法域名白名单**,那是流程不是代码。
