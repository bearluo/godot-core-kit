# 微信小游戏官方开发指南 · 本地摘要与索引

> 快照日期:**2026-07-28**。来源:<https://developers.weixin.qq.com/minigame/dev/guide/>
> 目的:把「每次去翻网页」变成「查本地一篇」。**数字与结论会随基础库版本漂移,上线前对着原文复核。**
>
> 与已有调研的分工(都在 `docs/research/`):
> - `2026-07-27-godot-wechat-minigame-feasibility.md` —— Godot 上微信的**可行性**结论
> - `2026-07-27b-godot-wechat-integration-recon.md` —— 本仓库**接入路径**侦察
> - `2026-07-27c-wechat-official-common-adaptation.md` —— **通用引擎适配方案**(官方 SDK)专题
> - `2026-07-27d-godot-wechat-community-plugin-mechanism.md` —— 社区导出插件**原理**
> - `2026-07-27-kit-wechat-spike-report.md` —— kit 在小游戏下的**实测报告**
> - **本篇** —— 官方指南的**平台侧事实底座**(限制、机制、API 契约),不重复上面五篇

---

## 0. 一分钟速查:硬限制表

高频要用的数字全在这。带 ⚠️ 的是最容易撞的。

| 项 | 限制 | 出处 |
|---|---|---|
| ⚠️ 主包体积 | **≤ 4 MB** | 代码包 |
| ⚠️ 总包体积(主包 + 全部分包) | **≤ 30 MB** | 代码包 |
| 普通分包体积 | 无单独上限(受总包 30 MB 约束) | 分包加载 |
| 独立分包体积 | **≤ 4 MB** | 分包加载 |
| ⚠️ 用户数据目录(本地缓存文件 + 本地用户文件) | **200 MB**,满足条件可申请提升到 1 GB | 文件系统 |
| 本地临时文件 | 不限大小,但**生命周期内有效,关闭后可能被清** | 文件系统 |
| ⚠️ `wx.setStorage` 本地缓存 | **10 MB**(用户 × 小游戏维度) | 本地缓存 |
| HTTP 并发(`request`/`uploadFile`/`downloadFile` 合计) | **10** | 网络 |
| WebSocket 并发(`connectSocket`) | **5** | 网络 |
| 网络默认超时 | **60 s**(`game.json` 可配,调用处优先) | 网络 |
| DNS 预解析域名 | 最多 **5** 个 | 网络 |
| Android 同时播放音频数 | **10**,超出做有损处理 | 音频 |
| ⚠️ Worker 并发数 | **1**(要新的先 `terminate()`) | 多线程 Worker |
| 上屏 canvas | **1 个**(首次 `wx.createCanvas` 得到),其余全是离屏 | 渲染 |
| 高性能模式内存上限 | 2 GB 机型 **1 GB**;3 GB+ 机型 **1.4~1.5 GB** | 高性能模式 |
| 代码包更新下发时延 | 最差 **24 小时**内覆盖全量用户 | 更新机制 |
| 版本回退可选范围 | 最近 **5** 个版本 | 更新机制 |
| 官方隐私弹窗拒绝后再弹间隔 | 默认/最小 **10 s** | 用户隐私保护 |

> 官方建议(在《通用引擎适配方案》里,不在本表来源页):**单文件控制在 1~2 MB、避免超过 10 MB**。这条比 200 MB 的硬上限更该当规划依据。

---

## 1. 运行时

### 1.1 运行环境

- JS 引擎:**iOS = JavaScriptCore,Android = V8**,**开发者工具 = NW.js**(所以工具里的表现不算数,「最终表现以客户端为准」是官方原话)。
- **没有全局 `document` / `window`**。这是小游戏与浏览器最根本的差异,也是 Adapter 存在的全部理由。
- 基础库内置 Polyfill 补 API 差异,但**语法差异要靠 ES6→ES5 转译**解决。

### 1.2 JS 支持情况

- ⚠️ **禁止动态执行代码**:`eval()`、`new Function()` 都不可用(安全策略)。
- 内置 `core-js` Polyfill 补标准 API。
- ⚠️ **`Proxy` 在低版本客户端无法 Polyfill**,应避免。
- ⚠️ **iOS 15 及以下的 Promise 时序不标准**:JavaScriptCore 限制导致 Promise 用 `setTimeout` 模拟,**微任务退化成宏任务**。iOS 16+ 正常。依赖微任务顺序的代码在低版本 iOS 上会错。
- 兼容性可查开源库 `wechat-miniprogram/miniprogram-compat`。

### 1.3 生命周期与销毁

- **冷启动**:首次打开,或被销毁后重新打开 → 完整加载。
- **热启动**:后台未被销毁,直接回前台。
- 进入后台后**还能跑一小段时间**(官方未写明确秒数),这段时间内没回前台就会被销毁。
- 其它销毁触发:系统资源紧张被回收;**iOS 上连续收到系统内存告警,微信会主动销毁小游戏**。
- `wx.onMemoryWarning` 可监听内存告警,应在此主动释放。
- 重新打开时会依据「上次场景 vs 当前场景」决定是否清空页面栈(等价 reLaunch)。

### 1.4 Adapter(weapp-adapter)

- 作用:在无 DOM/BOM 的环境里**模拟浏览器 API**,让基于浏览器的引擎能跑。
- ⚠️ **`weapp-adapter` 不是基础库的一部分**,是第三方适配层,要自己引入;官方明说「对浏览器环境的模拟远不完整」。
- 已模拟:`document.createElement`(转 `wx.createCanvas`/`wx.createImage`)、`canvas.addEventListener`、`localStorage`、`Audio`、`Image`、`WebSocket`、`XMLHttpRequest`。
- 这之外的浏览器 API **全要自己补**。

> **对本仓库的含义**:Godot 小游戏模板的 `user://` 走的正是这层 FS shim,而**不是**标准浏览器的 IDBFS。v0.24.3 那个「`rename_absolute` 返回 OK 但目标文件为空」的坑就长在这里——见 `addons/godot-core-kit/docs/systems/save-manager.md`。凡是 Web 上验过的行为,**在微信下必须重验一遍**。

---

## 2. 存储

### 2.1 文件系统

四类文件,权限差别很大:

| 类型 | 读 | 写 | 生命周期 |
|---|---|---|---|
| 代码包文件 | ✓ | ✗ | 随代码包,运行后不可改不可删 |
| 本地临时文件 | ✓ | ✗ | 仅当前生命周期,关闭后可能被清 |
| 本地缓存文件 | ✓ | ✗ | 同代码包 |
| **本地用户文件** | ✓ | **✓** | 同代码包 |

- **只有本地用户文件可写**,目录取自 `wx.env.USER_DATA_PATH`,「开发者对这个目录有完全自由的读写权限」。
- 本地文件路径形如 `{{协议名}}://文件路径`:真机是 `wxfile`,开发者工具是 `http`。
- 代码包文件用 `/a/b/c` 或 `a/b/c` 访问,**不支持相对路径**。
- ⚠️ **不可把本地临时文件路径存下来下次用**。
- 清理时机:本地缓存与用户文件**只在代码包被清理时才清**。
- 存储按**用户维度隔离**,不同微信号互不可见。
- 主要 API:`wx.getFileSystemManager()`、`saveFile()`(临时 → 缓存/用户)、`copyFile()`、`writeFileSync()`。

### 2.2 本地缓存(Storage)

- 上限 **10 MB**,用户 × 小游戏维度隔离(官方未写明单 key 上限)。
- 异步:`wx.setStorage` / `getStorage` / `removeStorage` / `clearStorage`;同步版加 `Sync`。
- 清理时机同代码包,**不会自动过期**。

> **对本仓库的含义**:10 MB 的 Storage 只够放轻量键值;kit 的 `SaveManager` 写 `user://saves/`,落的是**本地用户文件**(200 MB 池),这个选型是对的。跨重启持久性已实测确认(见 save-manager.md)。

---

## 3. 代码包与分包

### 3.1 代码包

- 主包 ≤ 4 MB,总包 ≤ 30 MB。
- 组成:编译后的 `*.js` + `game.json`,以及**白名单内的资源文件**(png/jpg/mp3/mp4/wasm 等 69 种格式)。
- ⚠️ `*.js` 与 `game.json` 上传后会被编译,**无法直接访问原文件**。
- 白名单外的文件**传不上去**。

### 3.2 分包加载

`game.json` 配置:

```json
{
  "subpackages": [
    { "name": "stage1", "root": "stage1/" },
    { "name": "stage2", "root": "stage2.js" }
  ]
}
```

`root` 可以是目录(其下 `game.js` 作入口)或单个 JS 文件。**没配进 `subpackages` 的一律进主包。**

```javascript
const loadTask = wx.loadSubpackage({
  name: 'stage1',
  success: res => {},
  fail: res => {},
})
loadTask.onProgressUpdate(res => {
  // res.progress / res.totalBytesWritten / res.totalBytesExpectedToWrite
})
```

- 基础库 **2.1.0** 起才有 `wx.loadSubpackage`。
- 基础库 **3.4.9+** 有 `wx.preDownloadSubpackage`:**只下载不执行**,之后仍需 `loadSubpackage` 才生效。
- ⚠️ 开放数据域目录**不能**设为分包、也不能放在分包下。

### 3.3 独立分包

- `subPackages` 项加 `"independent": true`。
- **≤ 4 MB**,且「普通分包的所有限制都对独立分包有效」。
- ⚠️ **不能依赖主包和其他分包的任何内容**,js 与资源都不行。
- 价值:从分享卡片进入时**只下独立分包即可启动**,不必先下主包。微信 7.0.13+ 支持,低版本按主包启动兜底。

### 3.4 WXWebAssembly

- `WXWebAssembly.instantiate(path, imports)`,**第一个参数只接受代码包内路径字符串**(不是 ArrayBuffer)。
- 允许传 brotli 压缩的 `.wasm.br`(基础库 v2.14.0+)。
- 基础库:v2.13.0+ 全局可用;v2.14.0+ 支持 brotli 与 Global;v2.15.0+ 可在 Worker 内用;v2.18.1+ 插件可用。
- 差异:支持导出函数 / Memory / Table;**iOS 暂不支持 Global 导出**。
- ⚠️ 在 Worker 里用时,`.wasm` 要放**在 worker 目录之外**——worker 目录只打包 `.js`。
- 体积超限的办法:拆多个 wasm 走分包,或用 brotli。

> **对本仓库的含义**:Godot 导出的 `godot.wasm.br` 正是走这条路;`empty-tips.bin`(主包)+ `subpackages/<名>/` 的布局对应上面的 `subpackages` 配置。
> **和 kit updater 的关系要分清**:官方分包是**平台侧代码包**,受 30 MB 总量与审核约束、必须随版本发布;kit 的 `CoreKit.updater` 是**自建 CDN 内容包**,落 `user://`、走 200 MB 池、不受总包限制、可绕开发版审核节奏。两者不冲突,选哪条取决于「内容要不要过审 / 要不要免更新下发」。

### 3.5 多线程 Worker

```json
{ "workers": "workers" }
```

分包形态(基础库 v2.27.3+),避免占首包:

```json
{ "workers": { "path": "workers", "isSubpackage": true } }
```

- `wx.createWorker('workers/request/index.js')`;通信 `postMessage` / `onMessage` / `terminate`。
- ⚠️ **最多 1 个 Worker**;⚠️ Worker 内**不能用 `wx` API、不能渲染、不能跨 Worker 通信、不能引用目录外文件**;数据是**复制**不是共享。
- Worker 目录**只打包 `.js`**。
- 分包形态需先 `wx.preDownloadSubpackage({ packageType: "workers" })` 再初始化。

---

## 4. 网络

- `wx.request` / `uploadFile` / `downloadFile` → 配 **HTTPS** 域名;`wx.connectSocket` → 配 **WSS** 域名。
- ⚠️ 域名必须 **ICP 备案**;**不支持父域名通配**,只认配置的子域名;**不能配 `api.weixin.qq.com`**。
- TLS **≥ 1.2**;**iOS 不支持自签名证书**。
- `wx.createUDPSocket` / `createTCPSocket` 可与局域网通信,但不允许本机 IP。
- 并发:HTTP 系 **10**、WebSocket **5**;默认超时 **60 s**。
- 开发者工具的「不校验合法域名 / TLS / HTTPS 证书」**只在工具与调试模式生效**,正式环境照样卡。

> **对本仓库的含义**:kit updater 的 CDN 域名必须提前进白名单并备案,否则真机上 `HTTPPackTransport` 直接失败——开发者工具里「能下」不代表真机能下。这是当前微信线上**尚未验证**的一项。

---

## 5. 渲染与音频

### 5.1 渲染

- ⚠️ **首次 `wx.createCanvas()` 得到的是上屏画布,之后创建的全是离屏画布**;上屏画布只有一个。
- `Canvas.getContext` 拿 `RenderingContext`。
- 支持 WebGL 2.0(另有 EmscriptenGLX 渲染模式)。
- 压缩纹理(基础库 2.5.0+):**iOS = PVR,Android = ETC1**。
- `wx.setPreferredFramesPerSecond` 锁帧。

### 5.2 音频

两套方案,选型看时长与频次:

| | InnerAudio | WebAudio |
|---|---|---|
| 创建 | `wx.createInnerAudioContext()` | `wx.createWebAudioContext()`,或 InnerAudio 传 `useWebAudioImplement: true` |
| 特点 | 简便、**支持流式播放**、性能较低 | 性能好、能力丰富、**占内存大** |
| 适合 | 背景音乐等大文件 | 短音效、高频播放 |

- Android **同时最多 10 个音频**,超出做有损处理。
- iOS / Android 支持格式有差异,查 API 文档。
- ⚠️ iOS 高性能模式**不支持** `useWebAudioImplement`;iOS 长音频**不支持** `playbackRate`。
- ⚠️ iOS 17.5+ 高性能模式下,WebAudio **退后台后无法恢复,需销毁重建**;基础库 2.25.3+ 的旧客户端创建后要主动 `resume()`。
- 实践:复用实例、不用就 `destroy()`、回前台调 `play()`/`resume()`。

> **对本仓库的含义**:kit 的 `AudioManager` 在微信下会落到哪一套、退后台能不能恢复,是当前**尚未验证**的一项。Godot 模板文档建议对背景音把 Playback Type 设成 sample 走微信原生 InnerAudio,避免帧率抖动时音频断续(见模板自带《使用前阅读.md》)。

---

## 6. 性能

### 6.1 启动

- 两大阶段:**代码包加载**(环境加载 → 下载代码包)、**首屏渲染**(框架注入 → 业务代码注入 → 首屏渲染)。
- 首屏留存 Android 整体约 **80%**,首次启动用户明显更低。
- 官方口径:**所有用户 4 秒内完成加载,可减少约 30% 的玩家流失**。
- 分析维度:系统、机型分档、网络类型、是否需要下载代码包。

### 6.2 内存

- ⚠️ **iOS 上小游戏与微信客户端同进程**,两者合计到 OOM 阈值就很容易被系统 KILL。
- Android 低内存(<1 GB)设备已极少;**iOS 低档机型仍占约 10%~15%**。
- `wx.onMemoryWarning` 告警;**连续多次告警会触发销毁**。
- 手段:开发期内存调优、云测检测、纹理压缩、GC 调优。
- 官方未给各机型内存上限的具体数值(高性能模式下有,见下)。

### 6.3 高性能模式(iOS)

- 条件:微信 ≥ 8.0.18、**iOS ≥ 14**;截至 2024-01 满足条件用户约 **96%**。
- 开通:MP 后台 → 游戏能力地图 → 研发能力 → 生产提效包 → 开通;再在 `game.json` 配 `iOSHighPerformance: true`。
- 收益(官方水族馆用例,iPhone 11 Pro Max,12000 条鱼):普通模式 10~15 帧 → **48~50 帧**。
- ⚠️ 内存上限:2 GB 机型 **1 GB**;3 GB+ 机型 **1.4~1.5 GB**。
- ⚠️ 不支持:`GameServerManager`、`VideoDecoder`(`RecorderManager` 支持中)。
- ⚠️ 渲染:**不支持 ETC / PVRTC 压缩纹理**;iOS 14~15.3 有共享 buffer 性能问题;**WebGL2 仅 iOS 15.5+**。
- 另有「高性能+模式」,Godot 模板文档建议 iOS 开它(MP 后台 → 游戏能力地图 → 研发能力 → 生成提效包 → 高性能模式)。

---

## 7. 更新机制(平台侧)

- **每次冷启动都检查更新**,发现新版**异步下载**,**下次冷启动才生效**。
- 微信 6.6.3+ 还会在未启动时定期检查最近用过的小游戏,下次打开时同步更新。
- ⚠️ 最差 **24 小时**内下发到全量用户——**开发者无法立刻影响所有现网用户**。
- 强更:

```javascript
const um = wx.getUpdateManager()
um.onCheckForUpdate(res => {})   // 检查完成
um.onUpdateReady(() => um.applyUpdate())  // 下载好 → 强制重启生效
um.onUpdateFailed(() => {})
```

- 另可在 MP 后台设「最低可用版本」强制用户升级。
- ⚠️ 部分客户端(Mac、低版本 PC)的 `onCheckForUpdate` **可能不触发**,所以更新检测 API 要一直挂着。
- 版本回退可选最近 5 个,注意插件版本变化。

> **对本仓库的含义**:这是**代码包**的更新,和 kit updater 的**内容包**热更是两条独立通道。GDScript 逻辑热更仍受「必须重启进程」约束(见 `2026-07-23-godot-hot-update-feasibility.md` §4b),而小游戏没有 `OS.restart`,重启屏障 = 用户手动重开或 `applyUpdate()`。

---

## 8. 调试

| 手段 | 用途 | 入口 |
|---|---|---|
| 开发者工具模拟器 | 日常开发 | NW.js 环境,**表现不等于真机** |
| **vConsole** | 真机看 `console` 日志 | 真机右上角菜单 →「打开调试」→ 右下角 vConsole 按钮 |
| 真机远程调试 | 用工具通过网络调真机 | `/minigame/dev/devtools/remote-debug` |
| Source Map | 还原压缩后堆栈 | `/minigame/dev/guide/runtime/debug/SourceMap.html` |
| 实时日志 | 线上问题排查 | `/minigame/dev/guide/runtime/debug/realtimelog/` |
| Errno 错误码 | 错误诊断 | `/minigame/dev/guide/runtime/debug/PublicErrno.html` |
| 游戏日志分析 | `GameLogManager` | `/minigame/dev/guide/runtime/debug/gamelogmanager.html` |

⚠️ **vConsole 的显示是有损的**:日志转成 JSON 字符串再传,除 Number / String / Boolean / null 外都按 Object 展示,`Infinity` 与 `NaN` 显示成 `null`,`undefined` / `ArrayBuffer` / `Function` 显示不出来。基础库 2.3.1+ 改用 `<>` 包裹改善。

> **自动化的边界(本仓库 2026-07-28 实测)**:`miniprogram-automator`(以及基于它的 `wechat-devtools-mcp`)**驱动不了 `compileType: "game"` 的小游戏**。同一套探针、同一台机器:小程序对照工程 `screenshot`/`pageStack` 正常返回;小游戏工程 WebSocket 能连上、`checkVersion` 有响应,但 `systemInfo`/`evaluate`/`screenshot`/`pageStack` **全部无限挂起**,`console` 事件也收不到。结论:小游戏的验证目前**只能靠人肉看 DevTools 控制台**。
> 附带一坑:`automator.launch()` 在 Node **18.20+/20.12+** 上必挂——它 `spawn('cli.bat')`,而这些版本对 `.bat` 收紧后需要 `shell: true`(CVE-2024-27980)。绕法:自己先跑 `cli.bat auto --project <路径> --auto-port <端口>`,再用 `automator.connect({ wsEndpoint })`。

---

## 9. 合规:用户隐私保护

- MP 后台「设置 → 基本设置 → 用户隐私保护指引」必须配置。处理任何用户信息都要披露目的与方式;不处理也要**声明承诺未处理**。
- 隐私接口范围:昵称头像、位置、运动步数、媒体文件、麦克风、摄像头、蓝牙、相册、关系链、游戏社区数据、传感器、剪切板等。自定义表单收集需自行适配。
- 两条实现路径:
  - **自定义弹窗**:注册 `wx.onNeedPrivacyAuthorization`,需上报三事件 `exposureAuthorization` / `agree` / `disagree`,每个都要真实点击触发。
  - **官方组件**:MP 后台开「隐私授权弹窗」;`game.json` 的 `officialPrivacyAuthorizationShowingGap` 配拒绝后间隔(默认/最小 10 s)。**一旦启用无法关闭**。
- 两种方式都可用 `wx.requirePrivacyAuthorize` 主动拉起。
- ⚠️ 未配置的后果:调隐私接口报 errno **104 / 112 / 1025**;未实现弹窗报「未实现隐私弹窗功能」;未声明信息类型报「api scope is not declared」。
- 用户拒绝后要做兼容,别阻断游戏流程。

> **对本仓库的含义**:kit 与两个 example 目前**不碰任何隐私接口**,所以只需在 MP 后台做「承诺未处理用户信息」的声明。一旦接排行榜/关系链/登录,这条立刻变成上线阻塞项。

---

## 10. 导航索引

按官方左侧树整理,点标题直达。**Unity 专章已折叠**(与 Godot 无关),需要时去官网展开。

前缀统一为 `https://developers.weixin.qq.com`。

### 指南
- 开发指南 `/minigame/dev/guide/`
- 学习新手教程 `/minigame/dev/guide/develop/start.html`
- 学习进阶指南 `/minigame/dev/guide/develop/develop.html`

### 游戏引擎
- 引擎适配概述 `/minigame/dev/guide/game-engine/engine-overview.html`
- Cocos/Laya/Egret 适配 `/minigame/dev/guide/game-engine/cocos-laya-egret.html`
- Unity/团结引擎适配 `/minigame/dev/guide/game-engine/unity-webgl-transform.html` —— 下辖「基本 / 方案概述与兼容性 / 性能优化(启动·运行) / 版本更新与资源部署 / 能力适配 / 调试与异常处理」共 60+ 页,**与 Godot 无关,不展开**。其中少数几页有通用参考价值:压缩纹理 `.../Design/CompressedTexture.html`、iOS 高性能 `.../Design/iOSOptimization.html`、多线程 `.../Design/Multithread.html`、资源部署 `.../Design/DataCDN.html`、资源缓存 `.../Design/FileCache.html`、版本更新 `.../Design/Update.html`
- **通用引擎适配方案** `/minigame/dev/guide/game-engine/common-adaptation.html` ← **Godot 走的就是这条**
  - 快速开始 `.../common-adaptation/Design/QuickStart.html`
  - 技术原理 `.../common-adaptation/Design/TechPrinciple.html`
  - Cocos2d-x 导出 `.../common-adaptation/Design/Cocos2dxExport.html`
  - UE4 导出 `.../common-adaptation/Design/UE4Export.html`
  - 自研引擎导出 `.../common-adaptation/Design/CustomEngineExport.html`
  - 转换工具使用 `.../common-adaptation/Design/TransformTool.html`
  - 启动流程说明 `.../common-adaptation/Design/LaunchProcess.html`
  - SDK 集成指南 `.../common-adaptation/Design/SDKBuild.html`
  - **HTTP 适配** `.../common-adaptation/Design/HttpAdapter.html`
  - **文件系统适配** `.../common-adaptation/Design/FileSystemAdapter.html`(`/CustomWritablePath` 那条在这)
  - TCP/UDP Socket 适配 `.../common-adaptation/Design/SocketAdapter.html`
  - WebSocket 适配 `.../common-adaptation/Design/WebSocketAdapter.html`
  - 键盘适配 `.../common-adaptation/Design/KeyboardAdapter.html`
  - 微信开放接口 `.../common-adaptation/Design/WXOpenAPI.html`
  - UE 引擎 HTTP 集成 `.../common-adaptation/Design/UEHttpIntegration.html`
  - 常见问题 `.../common-adaptation/Design/FAQ.html` / 更新日志 `.../common-adaptation/CHANGELOG.html`

### 运行时
- 运行环境 `/minigame/dev/guide/runtime/env.html`
- JS 支持情况 `/minigame/dev/guide/runtime/js-support.html`
- 运行机制 `/minigame/dev/guide/runtime/operating-mechanism.html`
- 更新机制 `/minigame/dev/guide/runtime/update-mechanism.html`
- 基础库版本分布 `/minigame/dev/guide/runtime/client-lib/version.html` · 低版本兼容 `/minigame/dev/guide/runtime/client-lib/compatibility.html`
- 调试:vConsole `/minigame/dev/guide/runtime/debug/vConsole.html` · Source Map `.../SourceMap.html` · 真机调试 `.../remote-debug.html` · 实时日志 `.../realtimelog/` · Errno `.../PublicErrno.html` · 游戏日志分析 `.../gamelogmanager.html`
- Adapter `/minigame/dev/guide/runtime/adapter.html`

### 基础能力
- 网络 `/minigame/dev/guide/base-ability/network.html` · HttpDNS `.../HTTPDNS.html`
- 消息推送 `/minigame/dev/guide/base-ability/message-push.html`
- 存储:文件系统 `.../file-system.html` · 本地缓存 `.../storage.html`
- 渲染 `.../render.html` · 权限 `.../authorize.html` · 模块化 `.../module.html` · 场景值 `.../scene.html`
- 游戏交互 `.../interaction.html` · 音频 `.../audio.html` · 视频 `.../video.html`
- 代码包 `.../code-package.html` · 分包加载 `.../subPackage/useSubPackage.html` · 独立分包 `.../independent-sub-packages.html` · 游戏灰度 `.../code-beta.html`
- Worker `.../workers.html` · Worker V2 `.../new-worker.html`
- 周期性更新 `.../background-fetch.html` · 数据预拉取 `.../pre-fetch.html`
- 服务端 API `.../backend-api.html`
- 小游戏插件 `.../plugins.html` · 游戏引擎插件 `.../game-engine-plugin.html`

### 开放能力
- 用户信息:登录态 `/minigame/dev/guide/open-ability/login.html` · **隐私保护** `.../privacy.html` · UnionID `.../union-id.html` · 用户信息 `.../user-info.html` · 手机号快验 `.../getPhoneNumber.html` / 实时验 `.../getRealtimePhoneNumber.html` · 开放数据校验解密 `.../signature.html`
- 虚拟支付:进件 `.../virtual-payment/virtual-payment2.html` · 技术手册 `.../virtual-payment/guide.html` · 游戏币 `.../virtual-payment/coins.html` · 道具直购 `.../virtual-payment/goods.html` · 消息推送 `.../virtual-payment/message-push.html` · 事件订阅 `.../virtual-payment/event.html`
- 广告:Banner `.../ad/banner-ad.html` · 激励视频 `.../ad/rewarded-video-ad.html` · 插屏 `.../ad/interstitialAd-ad.html` · 原生模板 `.../ad/custom-ad.html` · 数据接口 `.../ad/ad-data-interface.html` · 流量主广告金 `.../ad/adq.html` · IAA 预测 `.../ad/iaa.html`
- 数据分析 `.../data-analysis.html`
- 游戏服务:实时语音 `.../voip-chat.html` · 对局回放 `.../game-recorder.html` · 帧同步 `.../lock-step.html` · 房间服务 `.../roomservice.html` · 状态服务 `.../user-status.html` · 对局匹配 `.../gamematch.html` · 得分存储 `.../storage-server/storage-score.html`
- 社交互动:转发 `.../share/share.html` · 朋友圈 `.../share-timeline_game.html` · 海报 `.../share/share-image.html` · 动态消息 `.../share/updatable-message.html` · 定向分享 `.../share-to-specific-friend.html` · 私密消息 `.../share/private-message.html` · 关系链数据 `.../open-data.html` · 互动数据 `.../interactive-data.html` · **开放数据域** `.../opendata/basic.html` · 游戏互动信息 `.../game_Interaction_Information.html` · 擂台赛 `.../tournament.html` · 微信礼物 `.../WeChatGift.html` · 送道具 `.../share-gift.html` · 聊天工具 `.../chat-tool.html` · 排行榜 `.../ranklist.html` · 社交组件 `.../game-chat.html` · 社交玩法激励 `.../RewardSend.html`
- 游戏运营:客服消息 `.../customer-message/*.html` · 一次性订阅消息 `.../subscribe-message.html` · 关系链互动提醒 `.../subscribe-system-message.html` · 更新提醒 `.../subscribe-update-notification-message.html` · 评价与推荐 `.../game-evaluate.html` · 礼包道具 `.../game-gift.html` · 自定义任务 `.../custom-task.html` · CPS 推荐 `.../cps-recommend.html` · 流失召回 `.../commercialization/recall-user.html`
- 内容运营:游戏圈 `.../game-club.html` / 推送 `.../game-recommend.html` / 内容规范 `.../game-content.html` · 视频号主页 `.../channels-profile.html` / 视频 `.../channels-activity.html` / 直播 `.../channels-live.html` / 活动 `.../channels-event.html`
- 小游戏试玩:概览 `.../playable/guide.html` · 能力开通 `.../playable/manage.html` · 研发指南 `.../playable/dev.html` · 开放能力 `.../playable/api.html` · QA `.../playable/QA.html` · 试玩广告 `.../playable/ad.html`
- 获取链接:URL Scheme `.../url-scheme.html` · URL Link `.../url-link.html` · 二维码 `.../qr-code.html` · 添加到桌面 `.../add-desktop.html`
- 多平台:PC 接入 `.../pc-game.html` · PC 大屏适配 `.../pc-adapter.html` · PC 性能 `.../pc-performance.html` · 鸿蒙 OS `.../ohos.html`
- 硬件:蓝牙 `/minigame/dev/guide/device/bluetooth.html` · BLE `.../ble.html` · BLE Mesh `.../ble-mesh.html` · Beacon `.../beacon.html`

### 安全指南
- 安全原则 / 代码加固 2.0(混淆·水印·动态保护) / 游戏内容安全(文本·图片·音频) / 反外挂 —— 全在同一页锚点 `/minigame/dev/guide/security/security.html`
- 激励广告反作弊 `/minigame/dev/guide/security/antiadcheat.html`
- 安全风控 `/minigame/dev/guide/open-ability/security.html`

### 性能优化
- 概述 `/minigame/dev/guide/performance/perf-overview.html` · 技术手册 `.../perf-technical-manual.html` · 评测标准 `.../perf-mesure.html`
- 研发工具箱:性能监控系统 `.../perf-audit/perf-system-overview.html` / 评分方法 `.../perf-audit/perf-system-rating-rule.html` · 诊断工具 `.../perf-audit/perf-audit-tool.html` / 评分 `.../perf-audit/perf-audit-rating-rule.html` · 告警 `.../perf-audit/perf-audit-alarm.html`
- 启动性能:时序与指标 `.../perf-action-start.html` · 提升启动速度 `.../perf-action-start2.html` · 封面图插件 `.../perf-action-start-loading-plugin.html` · 并行下载 `.../perf-action-start-parallel-download.html` · 启动场景上报 `.../perf-action-start-reportScene.html`
- 运行性能:概述 `.../perf-action-runtime-overview.html` · 内存调优 `.../perf-action-memory-overview.html` / 开发阶段 `.../perf-action-memory-dev-profile.html` / 云测 `.../perf-action-memory-cloud-profile.html` / GC `.../perf-action-memory-gc.html` / 管理机制 `.../perf-action-memory-management.html` · 纹理压缩 `.../perf-action-texture-compression.html` · 混合渲染 `.../perf-action-render-bind.html` · Worker 异步计算 `.../perf-action-cpu-worker.html` · 设备档型分布 `.../perf-benchmarkLevel.html` · **WXWebAssembly** `.../perf-webassembly.html` · 高性能模式 `.../perf-high-performance.html` / 高性能+ `.../perf-high-performance-plus.html` · EmscriptenGLX `.../perf-emscriptenglx.html` · 空间提升 `.../diskspace.html` · iOS Metal `.../perf-ios-metal.html` · 温控模式 `.../power-saving-mode.html`
- 调优工具:线上异常排查 `.../debug.html` · 真机性能监控 `.../perf-action-device-monitor.html` · 云测试 `.../perf-tools-cloudtest.html` · 异常分析与监控 `.../monitor.html`
- 网络调优 `.../perf-network.html` · 弱网体验 `.../weak-network.html`

---

## 11. 本文档未覆盖 / 官方未写明

摘要时明确遇到的空白,免得下次重找:

- 后台运行到被销毁的**具体秒数** —— 官方只说「一小段时间」。
- 本地缓存**单个 key** 的上限 —— 官方只给了 10 MB 总量。
- 各机型的**内存上限数值**(非高性能模式) —— 官方只给示意图与 iOS 低端机 10%~15% 的占比。
- 真机调试的功能矩阵与 2.0/1.0 差异 —— 指南页只有一句话,细节在开发者工具文档 `/minigame/dev/devtools/remote-debug`。
- 超过 30 MB 总包后的**具体表现** —— 官方未明写,推断是上传被拒。
- 「高性能模式」与「高性能+模式」的**逐项对比** —— 官方未并排给出。
- 发布/审核流程 —— 不在本指南树内,在开发者工具与运营文档。
- **Godot 专属**:官方指南只覆盖到「通用引擎适配方案」,Godot 的导出插件是社区实现,见 `2026-07-27d`。
