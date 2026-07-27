# 微信小游戏「官方通用引擎适配方案」调研(相对 Godot / godot-core-kit 的定位)

- 日期:2026-07-27
- 来源:微信官方文档 `游戏引擎 > 通用引擎适配` 入口页及其 Design 子页
  - 入口:https://developers.weixin.qq.com/minigame/dev/guide/game-engine/common-adaptation.html
  - 技术原理:`.../common-adaptation/Design/TechPrinciple.html`
  - 快速开始:`.../common-adaptation/Design/QuickStart.html`
- 诚实标记:【据官方文档】=文档明写;【据知识/交叉推断】=由公开事实推断;【需实测/需查证】=文档未披露或本机未验。

---

## 0. 一句话结论

**官方「通用适配」是一条与我们已跑通的 godothub/godot-minigame 社区插件路线并行、但面向 Cocos/Unreal 的 Emscripten 转换管线;它对 Godot 4.7 不是 drop-in——存在硬性 Emscripten 版本错配(官方仅 3.1.10/3.1.51,Godot 4.7 用 4.0.0+),且其能力 SDK 是围绕 SDL/浏览器-shim 语义构建、与 Godot 自带的 Web 平台层重叠。** 但它非常有价值地**从官方口径交叉印证了我们 spike 得到的整套约束边界**(单线程 / 手势音频 / 1–4MB 分包 / CDN 分离)。→ 对 Godot,仍走 godothub 社区插件;官方方案作参照与兜底,不作 Godot 的导出工具。

---

## 1. 官方通用适配是什么【据官方文档】

- **定位**:"只要能编译导出 WASM + WebGL 的 H5 版本,就可以转换为微信小游戏"的**引擎无关**自动化转换方案,号称"分钟级完成 H5 游戏包到微信小游戏格式的转换"。
- **已验证引擎**:Cocos2d-x、Unreal Engine。**Godot 不在官方已验证名单内。**
- **两个独立组件**:
  1. **转换工具** `wx-transformer`(Win/macOS/Linux,v1.0.33):吃 Emscripten 产物,吐微信工程。
  2. **能力 SDK**(C++,v1.0.3):提供 HTTP / Socket / 文件系统等底层能力,需集成进被转换的引擎。
- **编译工具链硬约束**:Emscripten **仅支持 3.1.10 和 3.1.51**;推荐微信基础库 2.19.0+。

### 分层架构【据官方文档】
```
Emscripten 工具链 → WebAssembly 运行时
      ↓
JS 胶水代码(加载/实例化 WASM)
      ↓
适配层 Adapter(浏览器 API → 微信 API)
      ↓
能力 SDK(C++:HTTP / Socket / 文件系统)
      ↓
微信小游戏 Runtime
```

### 输入 / 输出形态【据官方文档】
- **输入**(Emscripten H5 产物):`game.js`(胶水,必需)+ `game.wasm`(必需)+ `game.data`(资源,可选)+ `index.html`。
- **输出**:`wechat-build/minigame/`,含 `game.json`、`project.config.json`、`framework.js`、`game.js`、`data-package/`、`wasmcode/`、`wx-game-kit/config.json`、`workers/`。
- **命令行示例**:
  ```
  ./wx-transformer -j build/game.js -w build/game.wasm -d build/game.data \
    -c https://cdn-url/game/ --app-id wx... --app-name "游戏名" \
    --engine-name "Cocos2dx" --device-orientation landscape
  ```

---

## 2. 各系统 API 怎么被承接【据官方文档】

| 类别 | 微信承接 | 备注 |
|---|---|---|
| HTTP | `wx.request` | 自动转换 |
| WebSocket | `wx.connectSocket` | 封装适配 |
| 本地缓存 | `wx.setStorage`(同步) | |
| TCP/UDP | 能力 SDK 模块 | 需专项集成 |
| 文件系统 `user://` | 适配层 | 具体映射规则**文档未明写**,指向专项《文件系统适配》【需查证】 |
| 音频(SDL) | 拦截 `window.AudioContext` 构造→返回微信 `WebAudioContext` | 监听 onHide/onShow 自动暂停恢复;**首次播放需用户交互触发**;iOS 17.5+ onShow 时重建音频上下文 |
| 触摸 | 监听 `wx.onTouchStart/Move/End/Cancel`→标准触摸/鼠标事件;支持 GLFW / `emscripten_set_mouse*` | 坐标换算 `x=(pageX-rect.left)×(canvas.width/rect.width)`,y 同理 |
| 键盘 | 虚拟键盘 / 文本输入适配 | |
| 微信开放接口 | 登录 / 分享 / 支付 / 广告 | |
| 渲染 | 自动重定向 Canvas / WebGL 上下文到微信 Canvas | WebGL 1.0/2.0(2.0 需基础库 2.24.0+) |

---

## 3. 约束边界(与我们 spike 结论交叉印证)【据官方文档 + 交叉推断】

| 约束 | 官方口径 | 与我们 CoreKit spike 的关系 |
|---|---|---|
| **线程** | "已知限制:不支持多线程(pthread)" | ✅ 完全印证。我们 `ResourceManager` 已 `use_threads = not web and threads`,web 下退单线程;这是官方级确认,不是我们保守。 |
| **内存增长** | **强烈建议 `-s ALLOW_MEMORY_GROWTH=0`**,预设合理初值;开 =1 频繁重分配、性能明显下降"不建议" | 【需实测】Godot Web 模板默认是否开 memory growth,及能否关。属引擎导出侧,非 kit 子系统。 |
| **音频手势门** | 首次播放音频需用户交互触发 | ✅ 印证。我们既有认知一致(AudioManager 首次播放需手势),留作接入侧适配,非硬阻断。 |
| **分包/体积** | 建议 **1–4MB 合理拆分**,首包与 CDN 资源分离;进关卡及时关资源;批量资源打 TAR 载入内存批量访问 | ✅ 印证 4MB 主包约束。我们 godothub 管线把引擎 wasm.br 放 `engine` 分包、主包 ~68KB,方向一致。 |
| **热更/版本部署** | `game.json` 配置分包与预下载;资源走 CDN,见《版本更新与资源部署》 | 对应我们 `PackUpdater` 的内容包 CDN 下载模型;域名白名单/`restart_to_apply` web 退化仍属接入侧【需实测】。 |

---

## 4. 为什么官方方案对 Godot **不是 drop-in**(核心分析)

1. **Emscripten 版本硬错配【据知识/交叉推断,决定性】**
   - 官方转换工具**仅支持 Emscripten 3.1.10 / 3.1.51**。
   - **Godot 4.7 的 Web 导出使用 Emscripten 4.0.0+**(官方 4.7 编译文档要求 emscripten 4.0.0+;4.4 曾要求 3.1.62+,持续上移)。
   - 3.1.x 与 4.0 的胶水/ABI、内存布局、`Module` 约定不同;官方工具是针对 3.1.x 产物构建与验证的,**几乎不可能直接吃 Godot 4.7 的 web 产物**。降级 Godot 到 emsdk 3.1.51 = 自编引擎模板的重活,得不偿失。

2. **能力 SDK 与 Godot 平台层重叠【据知识/交叉推断】**
   - 官方 SDK 假设引擎走**浏览器 API / SDL** 语义(如"拦截 `window.AudioContext`"、GLFW 鼠标回调),再由 SDK 把这些桥到微信。
   - **Godot 的 Web 导出自带一整套 platform/web 层**(它自己直接对接浏览器 API,不经 SDL)。把官方 SDK 叠上去 = 二次适配 / 冲突,而非补齐。Godot 缺的那层"浏览器 API→微信 API"正是 **godothub/godot-minigame 社区插件**已经做掉的事(我们 V0/spike 已端到端验过)。

3. **已验证引擎不含 Godot**:官方只背书 Cocos2d-x / Unreal;Godot 属"理论可转、无官方保证"。

**结论**:对 Godot,正确路线是桥接 **Godot 自己的** Web 导出(godothub 社区插件),而非把 Godot 硬塞进面向 Cocos/Unreal 的官方 Emscripten 转换器。官方方案的价值在**参照系**与**约束权威确认**,不在充当 Godot 的导出工具。

---

## 5. 官方方案唯一可能反超社区插件的点【需实测,暂不投入】

官方 SDK 的 TCP/UDP Socket、微信开放接口(登录/分享/支付/广告)是**社区插件通常不覆盖**的。若未来 kit 上的游戏要做微信登录/支付/激励广告,这些能力得**在接入侧另接**微信 JS API(`wx.login` / `wx.requestMidasPayment` / 激励视频),与用哪条导出管线**正交**——即便走 godothub 管线,也能在 weapp-adapter 层直接调 `wx.*` 接开放接口,无需引入整套官方 SDK。故官方 SDK 的开放接口能力**不构成切换管线的理由**。

---

## 6. 待验证清单(承接前两篇,标注归属)

- 【需查证】官方"文件系统适配"专项页对 `user://` 的精确映射(FileSystemManager / 本地缓存目录 / 临时目录),用于比对 Godot Web 的 IDBFS 落盘行为。
- 【需实测】Godot 4.7 Web 模板的 `ALLOW_MEMORY_GROWTH` 默认值与可否关闭(引擎导出侧)。
- 【需实测】godothub 产物在微信真机/开发者工具下:`user://` 存档往返、手势后音频、触摸、CDN 域名白名单、`PackUpdater` 热更链路——**均属用户在微信开发者工具实机验证的范畴,无头环境无法覆盖**(见 kit-wechat-spike 报告)。

---

## 7. 对既有研究的接续

- 承接 `2026-07-27-godot-wechat-minigame-feasibility.md`(可行性,结论②可行但成本高)与 `2026-07-27b-godot-wechat-integration-recon.md`(本机侦察,wasm 尺寸/godothub 分包)。
- 本篇新增的净结论:**官方"通用适配"经调研可排除为 Godot 的导出路线(Emscripten 版本锁 + SDL 取向 SDK + 仅 Cocos/Unreal 背书),但从官方口径确认了单线程/手势音频/1–4MB 分包/CDN 分离这套约束——与我们 kit-wechat-spike 的实测诊断一致。godothub 社区插件仍是 Godot 上微信的正解。**
