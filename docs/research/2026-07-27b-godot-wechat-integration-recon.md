# Godot 4 → 微信小游戏「接入」实测侦察（补 2026-07-27 研究 §3/§6）

> 日期: 2026-07-27（同日续）
> 分支: `wechat-minigame-research`（不并 main、不 push）
> 关系: 本文是 [`2026-07-27-godot-wechat-minigame-feasibility.md`](./2026-07-27-godot-wechat-minigame-feasibility.md) 的**实测续篇**。研究篇是保守的一手/二手推断；本篇用**本机实测 + 拆 godothub 4.7 模板 + 微信官方《通用适配》文档**把研究篇的多条【需实测/联网核实】收敛为【实测】，并据此**上调可行性**。
> 方法: ① 量 Godot 4.7 官方 Web 模板 wasm 实际字节；② 下载并拆解 `godothub/godot-minigame` 的 `minigame4.7.tpz`（2026-07-22 发布，Godot 4.7.2-rc）；③ 读微信官方 game-engine 通用适配文档。

## 证据标注
- **【实测】** 本机字节数 / 拆包所见，可复核。
- **【godothub 文档】** 模板内自带 .md 说明所述。
- **【微信文档】** 微信官方文档所述。
- **【需微信开发者工具实测】** 端到端「能不能真跑起来」，本机无微信开发者工具（GUI，须用户装）未验。

---

## 1. 一句话更新结论

研究篇给的是 **②「可行但成本高、不推荐」**，其判据是「官方零支持 + 主包 4MB 硬冲突 + love-wechat 停更 = 要养 fork」。

**实测把三条主要成本项基本打掉：**
- **主包 4MB 不是阻断**：godothub 用**微信分包**把引擎 wasm 放进 `engine/` 分包，**主包只剩 ~68KB**。【实测】
- **不用养 fork**：`godothub/godot-minigame` **活跃**，`4.7` 模板 **2026-07-22（5 天前）** 发布，支持 4.7.2-rc；自带 weapp-adapter、音频/文件系统/HTTP 适配、iOS 高性能、分包运行时。【实测 + godothub 文档】
- **不只是社区 shim**：微信**官方**就吃「WASM+WebGL 的 H5 引擎」，有通用适配工具链（Emscripten 3.1.51）。【微信文档】

**修正判定：仍是 ②（非 ①），但从「不推荐」上调为「机械阻断项已基本被 godothub 4.7 + 微信官方适配解决，成本远低于从零养 fork，值得先做一次 V0 spike 再定；端到端尚未验证」。** 不上调到 ① 的原因见 §5 的剩余真实风险。

---

## 2. 体积实测（收敛研究篇 §3.4 / 未验证 #6 #7）

### 2.1 官方 Godot 4.7 Web 模板 wasm（`web_nothreads_release.zip` 内）【实测】

| 文件 | raw | gzip | brotli |
|---|---|---|---|
| `godot.wasm`（默认含 3D、未裁剪） | **39,509,339 B ≈ 37.7 MB** | 10,082,564 B ≈ 9.6 MB | 6,900,136 B ≈ 6.58 MB |
| `godot.js` | 279,815 B ≈ 273 KB | — | — |

结论：**光官方引擎 wasm 原始 37.7MB，单文件就爆穿微信 30MB 代码包总限；brotli 6.58MB 也塞不进 4MB 主包。** 直接上传官方 Web 产物 = 硬爆。（研究篇 §3.4 推断坐实。）

### 2.2 godothub `minigame4.7.tpz` 拆解【实测】

`.tpz`（=zip）10,507,449 B ≈ 10.0 MB（≈ 官方 nothreads zip 9.77MB），解开后：

```
主包（微信主包，合计 ≈ 68 KB）
  game.js            1,985 B     微信入口
  weapp-adapter.js  60,774 B     DOM shim（document/window/canvas…）
  godot-loader.js    6,863 B     引擎加载器
  game.json / project.config.json / native-audio-manifest.* / images/
engine/  分包(subpackage) ← 引擎在这
  godot.wasm.br  8,405,811 B ≈ 8.0 MB   引擎 wasm(brotli 形态直接发)
  godot.js         435,267 B ≈ 425 KB
  godot-sdk.js      51,322 B              适配微信的 SDK
  empty-tips.bin   732,876 B ≈ 715 KB    空示例的 .pck(改名 .bin)
subpackages/subpack/  分包(subpackage)
  subpack.bin       17,888 B              二级内容分包示例
  game.js(空)                            微信要求每分包根有 game.js
```

`game.json`【实测】：
```json
{ "deviceOrientation": "portrait",
  "iOSHighPerformance": true, "iOSHighPerformance+": true,
  "subpackages": [ {"name":"engine","root":"engine/"},
                   {"name":"subpack","root":"subpackages/subpack/"} ] }
```

**关键**：引擎 wasm.br（8MB）在 `engine/` **分包**，主包 ~68KB。小游戏「普通分包不单独限大小、主+分包合计 ≤30MB」→ **空示例总量 ~9MB，30MB 里还剩 ~21MB 给内容**。小型 2D 游戏**不需要远程 CDN 就能进 30MB**；超了再用远程（见 §3）。这把研究篇「wasm 必须远程 + 极致裁剪」放宽为「小项目分包即可，中大型才远程」。

> 注：godothub 的 `godot.wasm.br` 8.0MB 略大于官方裁 brotli 6.58MB（构建/优化项不同），同量级，不影响结论。真实裁剪下限（未验证 #7）仍需自定义 Emscripten 构建才能压更小，但**在分包模型下已非必须**。

---

## 3. godothub 的分包/投递机制（与 kit PackUpdater 惊人趋同）

`subpacks/subpack_manifest.json`【实测】节选：
```json
{ "cache_budget_mb": 45.0,
  "delivery": "local_remote",
  "main_pack": { "name":"__main__", "relative_pack_path":"../empty-tips.bin",
                 "remote_path":"../empty-tips.bin",
                 "sha256":"d5a1379…", "size_bytes":732876,
                 "wechat_subpackage_name":"engine" } }
```

- **`delivery: local_remote`** = 每个 pack 可本地(进微信分包)或远程(CDN)投递；`cache_budget_mb: 45` 本地缓存预算。
- 每 pack 带 **sha256 + size + remote_path** —— **这跟 kit `KitPackManifest` / `PackUpdater` 是同一套设计**（清单驱动、校验、本地/远程双投递）。
- 运行时【godothub 文档】：游戏内**不要**再手写 `JavaScriptBridge + ProjectSettings.load_resource_pack`，改用
  ```gdscript
  var runtime := SubpackRuntime.new()      # addons/godot_subpack_runtime/
  runtime.load_manifest()
  await runtime.ensure_subpack_with_dependencies("subpack")
  ```
  微信侧它先 `GODOTSDK.load_pack()` 加载同名微信分包，再 `ProjectSettings.load_resource_pack()` 挂 `.bin`。
- PCK 内存管理【godothub 文档】：`JavaScriptBridge.get_interface("GODOTSDK").releasePck(pck)` 卸载（收敛研究篇未验证 #13 的 OOM 顾虑——有显式释放接口）。

**对 kit 的接入含义**：微信路径上 `CoreKit.updater` 的**挂载步**必须走 godothub `SubpackRuntime` / `GODOTSDK.load_pack()`，不能直调 `load_resource_pack`；但**清单语义（sha256/size/remote）与 kit 一致**，`WxPackTransport` + 一个「挂载适配器」即可对接，工作量比研究篇 §4.3 估计的小。

---

## 4. 微信官方《通用适配》与 godothub 已解决项

| 研究篇障碍 | 现状（实测/文档坐实） | 标注 |
|---|---|---|
| §3.1 无 DOM / shim | godothub 自带 `weapp-adapter.js`(59KB)；微信官方也吃 WASM+WebGL H5 | 【实测+微信文档】已解决 |
| §3.2 iOS WebGL2 / 高性能+ | `game.json` 默认 `iOSHighPerformance+: true`；后台开通路径:功能→游戏能力地图→研发能力→生成提效包→高性能模式 | 【实测+godothub文档】已给方案 |
| §3.4 主包 4MB / 30MB | 分包塞引擎，主包 ~68KB；空示例总 ~9MB | 【实测】已解决(小项目) |
| §3.5 音频 | 4.5 起 filesystem 重优化；长背景音设 `[Playback Type]=sample` 走 wx InnerAudioContext(避免掉帧断音);微信官方 SDL audio→WebAudioContext | 【godothub+微信文档】已解决 |
| §3.7 文件系统 | 4.5「原始各种文件访问都能正确实现」；标准 C 文件 API→微信 FS | 【godothub+微信文档】已解决 |
| §3.9 网络白名单 | godothub「httpclient 完成适配」；域名白名单仍是配置项 | 【godothub文档】已适配 |
| 工具链 | 微信推荐 **Emscripten 3.1.51**；微信开发者工具 RC 2.01.2510241 + 设置→通用→浏览器实验性→Experimental WebAssembly(Enabled)→重启 | 【微信+godothub文档】 |
| GDExtension/C# | 仍受多线程/体积限制，纯 GDScript 方向不变 | 研究篇结论不变 |

---

## 5. 剩余真实风险（为何仍是 ②、不上 ①）

1. **端到端未验证**【需微信开发者工具实测】：以上全是「模板内含 + 文档声称」，**没有**在微信开发者工具里真跑起来一帧。本机无微信开发者工具（GUI，须用户装）。
2. **单人社区项目**：`godothub/godot-minigame` 仅 ~24 commit、单维护者；虽跟到 4.7 很勤，但长期可持续性是风险。love-wechat（4.3）已停更即前车。
3. **只拆了空模板**：真实游戏(大量资源、自定义 GDScript、大 pck、复杂 UI/输入/IME)可能撞 30MB / 内存 / 低端机性能墙，空 demo 照不出。
4. **审核与政策**：软著/版号/类目/自建热更条款（研究篇 §6 / 2026-07-23 文档 §6）不因技术可行而消失。

---

## 6. 建议的 V0（须用户本机微信开发者工具）

目标：用最小代价把「② 值得试」收敛成「可试点」或「就此打住」。

| 步 | 做法 | 通过标准 |
|---|---|---|
| **V0.1** | 装微信开发者工具(RC 2.01.2510241 级) + Godot 4.7；用 godothub `4.7` 模板 + `empty-tips4.7.zip` 示例 | 开发者工具**无报错**跑到 Godot 主循环出画 |
| **V0.2** | 换成本仓库一个**最小 2D 场景**(如晶核防线单关或 kit demo)按 godothub 流程导出 | 竖屏出画 + 触摸响应 + 有音 |
| **V0.3** | 量真实主包/分包/总包字节 | 主包 ≤4MB 且总 ≤30MB(或明确哪些走远程) |
| **V0.4** | 存档写 `user://` → 杀进程重进 | 档在(验 FS 同步) |
| **V0.5** | 一个内容 pck 走 godothub `SubpackRuntime` 挂载执行 | 对齐研究篇 §7b 哨兵 |
| **V0.6** | 评估 `CoreKit.updater` 挂载步接 `SubpackRuntime` 的缺口 | 产出 API 适配清单 |

**V0.1–V0.2 不过 → 回落研究篇 ②「不推荐」。过 → 可排 `WxPackTransport` + 挂载适配器的 kit 集成。**

---

## 7. 本轮已收敛的研究篇未验证项

- #6 官方模板 wasm 精确字节 → **【实测】37.7MB/9.6MB/6.58MB**。
- #7 裁剪下限 → 分包模型下**非必须**；godothub 发 8.0MB brotli；更小仍需自定义 Emscripten 构建（未做）。
- #8 godothub 对 4.7 模板是否存在/API 稳定 → **存在**(4.7.2-rc，2026-07-22)，机制见 §3。
- #3(部分) iOS 高性能+ → 有默认开启 + 后台开通路径。
- #11 默认音频是否可用 → godothub 已适配(sample→InnerAudioContext)。
- #13 大 pck 内存 → 有 `releasePck` 显式卸载接口。
- 仍开放：真机覆盖率数字、审核政策、真实大项目体积/性能、端到端跑通(V0)。

## 8. 产物与出处
- 本机测量与拆包在 scratchpad（`webtpl2/`=官方模板；`mg47/`=godothub 4.7 模板），一次性未入库。
- godothub: <https://github.com/godothub/godot-minigame>（releases/4.7，2026-07-22）。
- 微信《通用适配》: <https://developers.weixin.qq.com/minigame/dev/guide/game-engine/common-adaptation.html>。
