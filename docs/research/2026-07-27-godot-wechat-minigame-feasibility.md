# Godot 4 上架微信小游戏（WeChat Mini Game）可行性调研

> 日期: 2026-07-27  
> 分支: `wechat-minigame-research`（不并 main、不 push）  
> 目的: 判断 **Godot 4.x / 4.7 + godot-core-kit** 能否、是否值得导出并运行在微信小游戏；为后续产品决策提供可核对的技术论据。  
> 衔接: 本文**接着** [`2026-07-23-godot-hot-update-feasibility.md`](./2026-07-23-godot-hot-update-feasibility.md) 的 §7 / §7b / §7c（Web 分包/热更实测）写；不重复「标准浏览器 Web 导出 + `load_resource_pack`」已坐实结论，只写**微信小游戏运行时与包规**带来的额外约束，并交叉引用 kit 的 `PackUpdater`。  
> 也可参考: [`2026-07-10-godot-ecosystem-survey-and-roadmap.md`](./2026-07-10-godot-ecosystem-survey-and-roadmap.md)、[`addons/godot-core-kit/docs/systems/pack-updater.md`](../../addons/godot-core-kit/docs/systems/pack-updater.md)。

### 证据标注约定（诚实纪律）

文中每条关键判断尽量标一类：

| 标记 | 含义 |
|---|---|
| **【确知】** | 有官方文档 / 仓库 README / 本仓库既有实测 / 一手源码可核对 |
| **【据知识推断】** | 由公开信息合理外推，非一手实测 |
| **【需实测/联网核实】** | 版本号、体积分位数、API 行为、成功上架案例等记不准或可能过时；集中列于文末清单 |

**不要把社区 demo 视频等同于「可上架生产」；不要把浏览器 Web 通过等同于微信小游戏通过。**

---

## 1. 摘要结论

| 维度 | 判定 |
|---|---|
| **官方支持** | **【确知】** Godot 官方**无**「微信小游戏」导出平台；引擎侧是 HTML5/Web（Wasm + WebGL2）。社区有 proposal 讨论（如 #7681、#10947 等），**未见**官方承诺交付时间表。 |
| **技术路径是否存在** | **【确知/据知识推断】** 存在：**Godot Web 导出 → 运行时 adapter/shim → 微信小游戏工程结构（`game.js` / `game.json`）**。主流商业路径是 Cocos / Laya / 团结引擎（Tuanjie）/ Unity 官方微信 WebGL 转换；Godot 只有**社区工具 + B 站/GitHub 零星案例**。 |
| **对本 kit 的综合判定** | **② 可行但成本高 / 性能与体积风险大，不建议作为 kit 默认目标平台**。  
| **相对原生微信方案** | **不推荐**用 Godot 硬上微信当主发行通道；若微信是硬需求，优先 **Cocos Creator / 团结引擎** 等一等公民支持。Godot 路径仅适合「已有 Godot 内容 + 强实验意愿 + 接受高度裁剪与自建工具链」。 |
| **与既有 Web 结论的关系** | kit 在**标准浏览器**上的 Web 分包/OTA 已坐实（§7b/§7c）；微信侧**额外**要解：无 DOM、无 IndexedDB 同构、主包 4MB / 主+分包总量 30MB、wasm 体积、音频驱动、文件系统同步。PackUpdater 的「下载→落盘→挂包→重启屏障」**概念可复用**，但传输/落盘实现必须换成 `wx` API，不能直接当浏览器跑。 |

一句话：**不是「引擎做不到」，而是「官方不养、胶水重、体积紧、生产级成熟度低」——对 kit 而言属于高投入实验项，不是短期可承诺交付面。**

---

## 2. 现状判定

### 2.1 官方

- **【确知】** Godot 4 官方导出目标包含 Web（HTML5），文档明确要求浏览器支持 **WebAssembly + WebGL 2.0**（见 [Exporting for the Web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)）。  
- **【确知】** 官方导出平台列表中**没有** WeChat / 微信小游戏 / 抖音小游戏等国内小游戏 target。  
- **【确知】** 社区在 godot-proposals 中多次请求小游戏支持，例如：
  - [Discussion #7681 — Does godot have a plan to support Minigame?](https://github.com/godotengine/godot-proposals/discussions/7681)（2023 起，关注度高，**无官方「会做」承诺**）
  - [Discussion #10947 / Issue #10934 — hope support WeChat/Douyin/…](https://github.com/godotengine/godot-proposals/discussions/10947)（反馈「只能出 h5，与微信小游戏包格式不合；`fetch` 等 API 在微信不可用」；被合并进 #7681 讨论线）
- **【据知识推断】** 在可预见的官方 roadmap 中，微信小游戏**不会**成为 Godot 一等导出目标；国内小游戏适配更可能长期停留在社区 / 第三方商业工具层。

### 2.2 业界主流（对照）

| 方案 | 与微信关系 | 备注 |
|---|---|---|
| **Cocos Creator** | **一等支持** | 官方文档直接「发布到微信小游戏」；主包 4MB、远程资源/分包成熟。【确知：Cocos 文档与微信生态事实】 |
| **Laya** | **一等支持** | 国内小游戏历史主力之一。【确知：市场事实；具体版本能力需产品侧再核】 |
| **团结引擎 / Unity 微信 WebGL 转换** | **官方/半官方转换链** | 微信开放文档有 Unity WebGL 转换专题；Android 端 WebGL2 覆盖、Worker/SAB 限制均有说明。【确知：微信文档存在该专题】 |
| **Godot 4** | **无官方；社区移植** | 见下节 |

### 2.3 社区 Godot → 微信路径（存在，但不等于生产就绪）

以下为调研期间可检索到的**代表性**项目/讨论（非穷尽）。**可信度**指「作为技术路线参考」而非「可直接上线」：

| 名称 | 说明 | 可信度 | 标注 |
|---|---|---|---|
| [yuchenyang1994/godot-love-wechat](https://github.com/yuchenyang1994/godot-love-wechat) | Godot **4.3** Web → 微信小游戏转换工具；自编译 WASM；恢复 ScriptProcessor 音频；内存 FS ↔ 微信 FS 定时同步；裁剪 webrtc/webxr/`javascript_eval` 等。作者声明**已不再研究微信小游戏、无力维护**。 | **中高（历史可行证据）/ 维护低** | 【确知：README 自述】 |
| [yuchenyang1994/godot-minigame-template](https://github.com/yuchenyang1994/godot-minigame-template) | 上项配套导出模板 | 同上 | 【确知：love-wechat README 链接】 |
| [godothub/godot-minigame](https://github.com/godothub/godot-minigame) | 面向 Godot **4.4+** 的 C++ 编辑器插件：小游戏模板下载/缓存/解压/导出；Release 分发 `*.tpz`；含 `skills/` 适配移植目录。仓库较新、仍在演进。 | **中（活跃方向，成熟度需实测）** | 【确知：README】 |
| B 站演示（如「盒子里的卡比巴拉」「习惯安静点」等） | 4.3/4.4 导出微信小游戏演示、工具开源声明、分包相关视频 | **低～中（演示≠上架）** | 【确知：存在公开视频；成功上架与性能未核】 |
| Agent Skill「Godot WeChat Mini Game Adapter」等 | 第三方 skill 声称适配 Godot 4.6.x 级 checkout | **低（未在本环境验证）** | 【需实测/联网核实】 |
| weapp-adapter 类（如 finscn/weapp-adapter、JetLua/wechat-adapter） | 给 **Web 库** 补 `window`/`document`/`canvas` 的通用思路；Cocos/Laya/melonJS 等用过 | **高（适配范式）**；对 Godot glue **不能直接套** | 【确知：范式；Godot 需专用 shim】 |

### 2.4 「成功上架案例」

- **【需实测/联网核实】** 公开渠道可见「开发者工具预览 / 真机预览 demo」多于可核对的**微信正式版上架 + 长期运营**案例。  
- **【据知识推断】** 存在个人/小团队用社区工具跑通 demo 的可能；**不应**在无审核通过证据时宣称「已有成熟上架生态」。  
- 本文**不编造**具体上架 AppID、DAU 或商用收入案例。

---

## 3. 技术障碍逐项拆解

统一结构：**障碍 → Godot Web 导出现状 → 微信小游戏侧限制 → 适配手段 / 是否阻断**。

### 3.1 无 DOM 的 JS 运行时（最大胶水面）

| 层 | 内容 |
|---|---|
| **障碍** | 微信小游戏 = 类浏览器 **JS 引擎 + 自绘 canvas**，**没有**完整 `document` / `window` / 部分 Web API；入口是 `game.js`，不是 `index.html`。 |
| **Godot Web 现状**【确知】 | HTML5 导出依赖 Emscripten glue + `godot.js`：创建 canvas、处理输入、fetch/XHR、音频 worklet/script processor、文件系统挂钩等，设计目标是**浏览器 DOM 环境**。 |
| **微信侧**【确知/据知识推断】 | 提供 `wx` API + canvas；社区用 **weapp-adapter** 类 shim 模拟 DOM。Godot 的 glue **比一般 canvas 游戏库更重**，通用 adapter 往往不够，需要**针对 Godot 的 loader/adapter**（love-wechat、godot-minigame 即此方向）。 |
| **适配手段** | ① 自定义 `game.js` 引导 + 替换/补丁 `godot.js` 的 DOM 访问；② 关闭/裁剪 `javascript_eval`、WebRTC、WebXR 等小游戏禁用或无用模块（love-wechat 已裁）；③ 用 `JavaScriptBridge` 调 `wx.*`。 |
| **是否阻断** | **非原理阻断，工程量大。**【据知识推断】适配面覆盖 canvas 创建、事件、定时器、网络、音频、存储后才能启动；**每个 Godot 小版本 glue 变更都可能破坏 adapter**。 |

### 3.2 图形（WebGL1 / WebGL2）

| 层 | 内容 |
|---|---|
| **障碍** | Godot 4 的 Web 目标以 **WebGL 2.0** 为硬要求（Compatibility 渲染后端对应 WebGL2）。 |
| **Godot Web 现状**【确知】 | 官方文档：HTML5 导出需要 WebGL 2.0；Godot 4 已不再以 WebGL1 为主路径。本仓库 Web 实测（§7b）使用 **GL Compatibility + nothreads**。 |
| **微信侧**【确知：微信 Unity 转换文档有 WebGL2 说明】 | Android：较早基础库版本起支持 WebGL2，覆盖率文档曾给出「用户占比 >85%」量级（**具体当前占比【需核实】**）。iOS：**需开启「高性能+」等模式才有 WebGL2**——love-wechat FAQ 亦写明 *「iOS 需在微信开放平台打开高性能+ 才能开 WEBGL2；Godot4 最低 WEBGL2」*。 |
| **适配手段** | 强制 Compatibility；真机矩阵覆盖「高性能+ / 非高性能+」；UI/特效避免强依赖高阶 GL 扩展。 |
| **是否阻断** | **条件性阻断**：**无 WebGL2 的机型/模式直接不可用**。不是全平台硬死，但是**发行覆盖与审核体验**风险点。 |

### 3.3 线程 / SharedArrayBuffer

| 层 | 内容 |
|---|---|
| **障碍** | 多线程 Wasm / `SharedArrayBuffer` 在小游戏环境支持不完整或与 Worker 模型不一致。 |
| **Godot Web 现状**【确知：本仓库 §7】 | 「Use Threads」导出依赖 SAB + COOP/COEP；**单线程（nothreads）可规避**。kit Web 路径与 fortune-mill Web OTA **刻意用 nothreads**。`ResourceManager` 在 `OS.has_feature("web")` 时也会关线程加载。 |
| **微信侧**【确知/部分需核实】 | 存在 `wx.createWorker`、新版 Worker V2 与 `SharedArrayBuffer` 相关能力文档；Unity 转换文档多处仍写 **多线程不支持 / 需删 Job 等**（生态结论不一致，**以当前微信文档版本为准，需核实**）。love-wechat 明确：**小游戏不能开 wasm 多线程** → C++/GDExtension 动态链接 wasm 基本不可用。 |
| **适配手段** | **固定单线程 Web 导出**；不用依赖线程的 GDExtension；重计算走分帧（kit `FrameScheduler`）而非 Worker。 |
| **是否阻断** | **对单线程路径：不阻断。** 性能代价：加载、物理、解析等无后台线程，低端机掉帧风险上升。【据知识推断】 |

### 3.4 包体积（主包 4MB / 主+分包 30MB）——与 Godot wasm 的矛盾

| 层 | 内容 |
|---|---|
| **障碍** | 微信小游戏**代码包**体积硬限制。 |
| **微信规则**【确知：微信官方分包文档](https://developers.weixin.qq.com/minigame/dev/guide/base-ability/subPackage/useSubPackage.html)】 | - 主包 ≤ **4MB**  <br> - 主包 + 所有分包 ≤ **30MB**  <br> - 单个普通分包不限制大小（但仍受总 30MB 约束）  <br> - 单个独立分包 ≤ 4MB  <br> 另有远程资源下载（不计入代码包 30MB，但受下载体验、域名白名单、本地缓存上限约束）。 |
| **Godot Web 产物**【确知量级 / 具体 MB 随版本与裁剪变化】 | 典型导出：`*.wasm` + `*.pck` + `godot.js` + html/js 辅助。公开社区报告中，**未极致裁剪的 wasm 常在十余 MB～三十余 MB 量级**（例如模板 release wasm 约 30MB 量级的讨论/博客多次出现）。即使用 `optimize=size`、裁 3D/模块、Brotli/gzip，**把「引擎 + 最小壳」压进 4MB 主包几乎不现实**。【据知识推断 + 公开二手体积讨论；本仓库未在本机量微信包】 |
| **与 kit 分包结论对接** | 见 **§4**。浏览器侧「薄壳 base + 远程 `.pck`」已通；微信侧必须同时解决：**① 引擎 wasm 本身放哪 ② 内容包怎么下 ③ 本地 FS 如何持久**。 |
| **适配手段** | 主包只放 `game.js` + adapter + 启动图；wasm/引擎放**分包**和/或**CDN 远程下载**；游戏资源尽量**远程**（不占 30MB 代码包）；极致裁剪自定义导出模板（关 3D、关模块）。love-wechat 自述总包 ≤30M、本地存储 ≤100M 量级限制（**【需核实】是否与当前微信文档数字完全一致**）。 |
| **是否阻断** | **对「默认官方 Web 模板直接上传」= 硬阻断（主包必爆）。**  <br> **对「分包 + 远程资源 + 裁剪模板」= 高难度但非原理不可能。** 总 30MB 代码包对完整 Godot 4 引擎仍极紧；生产上几乎必然 **wasm 走远程 + 强裁剪**。【据知识推断】 |

### 3.5 音频

| 层 | 内容 |
|---|---|
| **障碍** | 浏览器 Web Audio / AudioWorklet 路径与微信音频策略不一致；后台静音、自动播放策略、解码格式限制。 |
| **Godot Web 现状**【确知】 | 使用 Web Audio 相关路径；历史上有 ScriptProcessor 等演进。 |
| **微信侧**【确知：love-wechat README】 | 作者**自行把 ScriptProcessor 相关代码加回**自定义 WASM，才在小游戏里受控于 Godot 音频总线；说明**默认 4.x Web 音频路径不能开箱即用**。 |
| **适配手段** | 自定义模板修音频；或经 `wx` 音频 API 做旁路（失去总线一致性）。kit `AudioManager` 需在微信路径做探测/降级。【据知识推断】 |
| **是否阻断** | **默认模板可能阻断可玩音频；自定义模板后可解。** 属高优先适配项，不是理论死局。 |

### 3.6 输入 / 触摸

| 层 | 内容 |
|---|---|
| **障碍** | 无 DOM 事件冒泡模型；触摸、安全区、异形屏、键盘（若有）走 `wx` 事件。 |
| **Godot Web 现状**【确知】 | 输入绑定在浏览器 pointer/touch/keyboard 事件。 |
| **微信侧** | adapter 把 touch 映射为浏览器事件；需处理 `wx.onTouch*` 与 canvas 坐标。 |
| **适配手段** | 成熟 adapter 通常覆盖基础触摸；多点触控、手势、IME 输入框需专项测。kit `InputManager` / 重绑定 UI **【需实测】**。 |
| **是否阻断** | **基础触摸：一般不阻断（adapter 范畴）。** 复杂输入【需实测】。 |

### 3.7 文件系统

| 层 | 内容 |
|---|---|
| **障碍** | 浏览器 `user://` → **IndexedDB/IDBFS**（§7 已述）；微信**无同构 IDBFS**。 |
| **Godot Web 现状**【确知：§7b】 | 写 `user://` + 跨 reload 在 Chromium 即时场景可用；长期驱逐仍是风险。 |
| **微信侧**【确知：love-wechat】 | 方案：定时把 wasm 内存 FS 同步到 **微信 `FileSystemManager` 用户目录**，启动时再灌回内存 FS；存档后可能要**手动强制 sync**。 |
| **适配手段** | ① 沿用社区 sync 层；② PackUpdater 传输层改 `wx.downloadFile` / 本地用户文件路径；③ 不假设 IDBFS 语义。 |
| **是否阻断** | **对「直接复用浏览器 PackUpdater」= 阻断（落盘语义不同）。** 对「换传输与 FS 适配」= 可解，工程成本中高。 |

### 3.8 字体 / IME

| 层 | 内容 |
|---|---|
| **障碍** | 中文字体体积大（轻松超过主包）；系统字体接口与浏览器不同；输入法弹层与 canvas 游戏冲突。 |
| **Godot Web 现状** | 常嵌入字体或依赖系统；Web 上字体子集化。 |
| **微信侧** | 字体应远程或分包；IME 多用原生输入组件而非 DOM input。 |
| **适配手段** | 字体走远程；UI 文本尽量 bitmap/少量字形；输入用 `wx` 键盘 API 桥接。【据知识推断】 |
| **是否阻断** | **嵌入完整中文字体进主包 = 实质阻断。** 设计规避后不阻断。 |

### 3.9 网络请求白名单

| 层 | 内容 |
|---|---|
| **障碍** | 微信要求服务器域名在小程序/小游戏后台配置合法域名；部分协议/端口受限。 |
| **Godot Web 现状**【确知：§7】 | 浏览器同源/CORS；Godot `HTTPRequest` 需绝对 URL（§7b 坑）。 |
| **微信侧**【确知：平台常识】 | `request` / `downloadFile` / `connectSocket` 等域名白名单；开发阶段可关校验，正式版强制。 |
| **适配手段** | CDN/API 域名报备；PackUpdater manifest/pack URL 全部落在白名单；必要时用 `wx` 下载替代 Godot HTTP。 |
| **是否阻断** | **配置问题，非技术死局；漏配则线上全挂。** |

### 3.10 其它（简表）

| 项 | 要点 | 阻断？ |
|---|---|---|
| **开放数据域 / 好友排行** | 独立 JS 上下文，Godot 难直接嵌；通常原生 canvas 子域 | 社交能力需另做，非主循环阻断 |
| **GDExtension / C#** | love-wechat：动态 wasm 链接要多线程 → 小游戏基本不行；C# 运行时放不进体积预算 | **扩展与 C#：实质阻断**；纯 GDScript 可行方向 |
| **隐私/登录/支付/分享** | 必须 `wx` 官方能力，Godot 无封装 | 产品功能层必做 bridge，非渲染阻断 |
| **审核与类目** | 软著、版号、类目资质等政策 | 发行阻断可能来自政策而非引擎 |

---

## 4. 包体积与 kit 分包（PackUpdater）对接

### 4.1 既有 kit Web 结论（不重复论证，只引用）

摘自 [`2026-07-23-godot-hot-update-feasibility.md`](./2026-07-23-godot-hot-update-feasibility.md)：

| 结论 | 状态 |
|---|---|
| `load_resource_pack` 在 Godot **4.7 Web（nothreads）** 可用 | **【确知：§7b 实测】** |
| HTTP → 写 `user://` → 挂包 → 执行包内 GDScript；reload = Web 重启屏障 | **【确知：§7b】** |
| fortune-mill 真实 `gacha-v1.pck` Web OTA 端到端 PASS | **【确知：§7c】** |
| Web 上 `HTTPRequest.download_file` 不可靠；kit 0.24.1 改为 body→`store_buffer` | **【确知：§7c / pack-updater 文档】** |
| IDBFS 长期回收、大包内存、跨浏览器 | 运营注意项，非机制死 |

### 4.2 微信场景下「两层分包」模型

必须区分 **微信代码分包** 与 **Godot 内容包**，二者不是同一层：

```
┌─────────────────────────────────────────────────────────┐
│ 微信代码包（主包≤4MB，主+分包≤30MB）                      │
│  · game.js / adapter / 启动资源                          │
│  · （可选）引擎 wasm 分包片段                            │
└─────────────────────────────────────────────────────────┘
              │ 启动后
              ▼
┌─────────────────────────────────────────────────────────┐
│ 远程 CDN（不计入 30MB 代码包）                            │
│  · godot.*.wasm（常见落点）                              │
│  · base.pck / 内容 pck（对齐 PackUpdater manifest）      │
│  · 贴图音频字体等                                        │
└─────────────────────────────────────────────────────────┘
              │ wx.downloadFile / 自建传输
              ▼
┌─────────────────────────────────────────────────────────┐
│ 微信用户文件目录 ↔（同步层）↔ Godot user:// 内存 FS       │
│  · mount_installed / load_resource_pack                  │
│  · 含 GDScript 的更新仍需「重启/重进」屏障               │
└─────────────────────────────────────────────────────────┘
```

### 4.3 PackUpdater 可复用 vs 必须改写

| 能力 | 浏览器 Web | 微信小游戏 | 动作 |
|---|---|---|---|
| manifest `check` / sha256 / 原子 state | 可用 | 概念可用 | 保留协议 |
| `HttpPackTransport`（Godot HTTPRequest） | 已修 Web 落盘 | **可能不够**（域名、API、证书） | **新 transport：`WxPackTransport`**【据知识推断】 |
| `user://` 持久 | IDBFS | 需 **FS sync 层** | 依赖 adapter；存档/包下载后 `syncfs` |
| `restart_to_apply` | 页面 reload；API 返回 false | 可能是「杀进程重进小游戏」或 `wx.restartMiniProgram` 类能力 | **需核实**可用 API |
| 薄壳 base + `--export-pack` 内容包 | 已通 | 同样需要；**引擎 wasm 不在 pck 体系内** | 导出管线加「微信工程生成」步骤 |
| 主包 4MB | 浏览器无此限 | **硬限** | 启动壳必须极瘦；wasm/pck 默认远程 |

### 4.4 体积策略建议（对本 kit）

1. **不要**试图把官方完整 Web 模板塞进微信主包。  
2. **引擎**：自定义 size 裁剪模板（2D-only、关无用模块）+ 远程加载 wasm。  
3. **内容**：继续 PackUpdater 模型——base 仅 loading + CoreKit + 最小场景；玩法/资源远程 pck。  
4. **微信代码分包**：只放「必须随代码审核分发」的 JS/adapter/极小资源；能远程的绝不进 30MB。  
5. **与 §7 一致**：含 GDScript 的包换逻辑 = 下载完成后**重进**再 `mount_installed()`，不幻想热替换。

### 4.5 关键矛盾一句话

**【据知识推断】**  
浏览器 Web 的矛盾是「持久化脆 + 内存」；微信小游戏的矛盾是「**代码包 4MB/30MB 与 Godot wasm 体量冲突 + 无 DOM/无 IDBFS**」。kit 已解决前者的机制问题，**几乎尚未开始**后者。

---

## 5. 社区 / 工具链清单（汇总）

| 资源 | 类型 | 备注 | 可信度 |
|---|---|---|---|
| [godot-love-wechat](https://github.com/yuchenyang1994/godot-love-wechat) | 转换工具 + 思路 | 4.3；作者停更；音频/FS/裁剪经验价值高 | 中高（历史） |
| [godot-minigame-template](https://github.com/yuchenyang1994/godot-minigame-template) | 导出模板 | 上项配套 | 中 |
| [godothub/godot-minigame](https://github.com/godothub/godot-minigame) | 编辑器插件 4.4+ | 模板 Release 分发；较新 | 中（需实测） |
| godot-proposals #7681 / #10947 | 官方社区诉求 | 证明需求真实、官方未承诺 | 高（作为「无官方支持」证据） |
| 微信文档：分包 / Unity WebGL 转换 / WebGL2 | 平台硬约束 | 规则源 | 高 |
| Cocos 发布微信文档 | 对照「正确姿势」 | 主包 4MB、远程资源 | 高（对照） |
| B 站 Godot→微信工具视频 | 演示 | 跟版本快过文档；需当线索非证据 | 低～中 |
| weapp-adapter 生态 | DOM shim 范式 | 不直接等于 Godot 方案 | 中（范式） |

---

## 6. 可行性判定与推荐路线

### 6.1 对本 kit 的明确结论

**判定：② 可行但成本高 / 性能与体积风险大，当前不建议作为 kit 默认支持平台。**

理由：

1. **官方零支持** → 所有 glue、模板、音频、FS 由社区或自建长期背锅。  
2. **体积**：主包 4MB / 总代码包 30MB 与 Godot 4 wasm 默认体量冲突；必须远程引擎 + 极致裁剪，首包体验与失败面显著。  
3. **运行时**：无 DOM + 单线程 + WebGL2 覆盖缺口（尤其 iOS 高性能+）→ 真机矩阵贵。  
4. **kit 现状**：Android / 浏览器 Web 的 PackUpdater 已投入并验证；微信需要**新平台适配层**，工作量接近「半个导出后端」，不是加一个 export preset。  
5. **机会成本**：同样人力在 Cocos/团结上微信是「跟官方文档」，在 Godot 上是「养 fork」。

**不选 ①** 的原因：成本与风险对「可接受」阈值过高。  
**不选 ③** 的原因：社区已证明「能跑 demo」路径存在；原理上不是「Wasm 不能在小游戏跑」。

### 6.2 相对其它引擎的推荐

| 目标 | 推荐 |
|---|---|
| **必须上微信小游戏，且要可控工期** | **Cocos Creator 或 团结/Unity 微信转换**（一等或半官方链） |
| **Godot 已是主技术栈，微信只是想试** | 可开 **spike**，用社区工具 + 最小场景；**不要**承诺生产档期 |
| **kit 默认跨端（Android 优先）** | **维持现状**；微信标为 out-of-scope 或 experimental backlog |

### 6.3 若要推进：最小验证路径（建议顺序）

目标：用最少时间回答「我们能不能在开发者工具里稳定跑起来」，而不是先做完整 PackUpdater 微信版。

| 步 | 验证问题 | 做法草案 | 通过标准 |
|---|---|---|---|
| **V0** | 社区工具能否在本机出包？ | 选一条：`godot-love-wechat`（4.3 历史）或 `godothub/godot-minigame`（4.4+）；空项目/官方 2D 模板 | 微信开发者工具**无报错启动**到 Godot 主循环 |
| **V1** | WebGL2 + 渲染 | 彩色 sprite + 简单 UI | 模拟器 + 1 台 Android + 1 台 iOS（含/不含高性能+）出画 |
| **V2** | 音频 | 播 BGM + SFX | 可听、切后台策略可接受 |
| **V3** | 体积 | 量主包/分包/远程 wasm 实际 KB | 主包 ≤4MB；总代码包 ≤30MB **或**明确 wasm 全远程且首启可接受 |
| **V4** | 持久化 | `user://` 写档 → 杀进程 → 重进 | 档还在（验证 FS sync） |
| **V5** | 内容包 | 移植 §7b 级最小 pck：远程下载 → 挂载 → 执行包内 GDScript | 对齐浏览器 §7b 哨兵逻辑 |
| **V6** | kit 薄集成 | CoreKit autoload + PackUpdater 换 Wx transport（可先假） | 不崩溃；列出 API 缺口清单 |

**未通过 V0–V2 则停止**，避免在 PackUpdater 上过度设计。  
**V3 失败且无法接受远程 wasm 首启** → 对 kit 产品应标 **③ 实质不可行**。

### 6.4 若 V 系列通过后的工程路线（仅规划，非本任务实施）

1. 冻结 Godot 小版本 + 自定义微信导出模板（与引擎版本锁死，同 PackUpdater §3 精神）。  
2. 维护 `godot-wechat-adapter`（或跟踪 godothub）为独立仓库。  
3. `WxPackTransport` + FS sync 钩子接入 `CoreKit.updater`。  
4. 导出管线：`export_packs` +「生成微信工程目录」一步。  
5. 真机 CI 无法完整自动化时，至少固定人工回归清单（iOS 高性能+、音频、热更重进）。

---

## 7. 未验证项清单（供协调者 / 后续联网与实测）

下列条目**故意不给假确定性**，建议按优先级核验：

### 平台规则与能力

1. 微信小游戏当前**主包 / 总分包 / 独立分包 / 本地用户文件 / 缓存**准确数字与是否有「高性能模式」额外额度。  
2. 微信对 **远程下载并 instantiate Wasm** 的最新政策与性能实践（是否必须进代码分包）。  
3. **WebGL2** 在 Android / iOS 当前覆盖率；iOS「高性能+」开通条件与审核影响。  
4. **Worker V2 / SharedArrayBuffer** 是否已足以支撑 Godot 多线程导出（预期仍否）。  
5. `wx.restartMiniProgram`（或等价）是否可作为 PackUpdater 的重启屏障。

### 引擎与体积

6. Godot **4.7 / 4.7.1** 官方 web release 模板 wasm **未压缩 / gzip / brotli** 精确字节（本机导出一次即可）。  
7. 2D-only + `optimize=size_extra` + 模块裁剪后的 wasm 下限。  
8. `godothub/godot-minigame` 对 4.7 的模板是否存在、API 是否稳定。  
9. love-wechat 停更后，社区是否有活跃 fork 跟到 4.5+。

### 运行时行为

10. Godot glue 在微信中的 **DOM 依赖面**完整列表（应用静态扫描 `godot.js` + 启动 log）。  
11. 默认音频路径在无自定义补丁时是否**完全静音或崩溃**。  
12. `JavaScriptBridge` 调 `wx` 在 4.7 的稳定性与 GC 回调持有纪律（love-wechat 已提示须持有 callback 引用）。  
13. PackUpdater 大包（数 MB～数十 MB）在微信 FS + 内存双份下的 OOM 阈值。  
14. 字体、IME、安全区、刘海、横竖屏切换。

### 发行与案例

15. 可公开核对的 **Godot 微信小游戏正式上架** 案例（AppID / 名称 / 引擎版本）。  
16. 抖音小游戏对 Godot 的支持是否优于微信（有文章称抖音侧更开放——**【需核实】**，且涉及软著等门槛）。  
17. 微信审核对「自建热更 / 远程 GDScript」的政策态度（对标 Android 热更灰区，见 2026-07-23 文档 §6）。

### 本仓库未做

18. **未**在本机安装微信开发者工具跑 V0。  
19. **未**用本仓库 Godot 4.7 导出微信包或量 wasm 体积。  
20. **未**评审 godothub 源码与模板二进制内容。

---

## 8. 参考链接（便于复核）

### 本仓库

- [2026-07-23 Godot 分包/热更可行性（§7/§7b/§7c Web）](./2026-07-23-godot-hot-update-feasibility.md)  
- [PackUpdater 文档](../../addons/godot-core-kit/docs/systems/pack-updater.md)  
- [2026-07-10 生态调研](./2026-07-10-godot-ecosystem-survey-and-roadmap.md)

### Godot

- [Exporting for the Web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)  
- [godot-proposals #7681](https://github.com/godotengine/godot-proposals/discussions/7681)  
- [godot-proposals #10947](https://github.com/godotengine/godot-proposals/discussions/10947)

### 微信 / 对照引擎

- [微信小游戏 · 分包加载](https://developers.weixin.qq.com/minigame/dev/guide/base-ability/subPackage/useSubPackage.html)  
- [微信 · Unity WebGL 转换 / WebGL2 说明](https://developers.weixin.qq.com/minigame/dev/guide/game-engine/unity-webgl-transform/Design/WebGL2.html)  
- [Cocos · 发布到微信小游戏](https://docs.cocos.com/creator/3.7/manual/zh/editor/publish/publish-wechatgame.html)

### 社区 Godot 工具

- [yuchenyang1994/godot-love-wechat](https://github.com/yuchenyang1994/godot-love-wechat)  
- [godothub/godot-minigame](https://github.com/godothub/godot-minigame)

---

## 9. 收尾说明

- 文档路径: `docs/research/2026-07-27-godot-wechat-minigame-feasibility.md`  
- 分支: `wechat-minigame-research`；**不并 main、不 push**（由协调者决定后续）。  
- 本文为研究交付，**不含**代码改动或导出管线实现。  
- 核心可执行下一步：协调者排期 **V0 社区工具冒烟**（§6.3），用实测把「②」收敛为「可试点」或「③」。
