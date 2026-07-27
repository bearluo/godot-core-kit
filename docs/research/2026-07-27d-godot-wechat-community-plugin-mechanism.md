# 社区方案(godothub `godot_subpack` + `godot_subpack_runtime`)原理与流程

- 日期:2026-07-27
- 依据:直接读了 kit-wechat-spike worktree 里的插件源码与 `C:\toolkit\kit-demo-minigame` 的实际导出产物。
- 诚实标记:【据源码】=读了 GDScript 源码;【据产物实测】=读了实际导出文件;【据产物推断】=C++ 插件无源码,由其产出的标记/清单反推。

---

## 0. 一句话原理

社区方案**不改造 Godot、不引入外部 SDK**:① 桥接 **Godot 自己的 Web 导出**(Godot 自带 emscripten 引擎 + `godot-sdk.js` + `weapp-adapter.js`),同步成一份合法微信工程;② 叠一层 **Godot 原生的分包运行时**(`ProjectSettings.load_resource_pack` 挂 `.bin` 包),让引擎 wasm 进微信分包、避开 4MB 主包限制,并支持微信原生分包 / CDN 按需下载。官方通用适配缺的"浏览器 API→微信 API"那层,社区用 Godot 原生机制补上了——所以天然吃 Godot 4.7,不存在官方方案的 emscripten 版本错配。

---

## 1. 两层架构

| 层 | 载体 | 何时运行 | 进不进出厂包 |
|---|---|---|---|
| **导出层** `godot_subpack` | C++ GDExtension 编辑器插件 | 仅编辑器,导出时 | ❌ `editor.single`,不进包 |
| **运行时层** `godot_subpack_runtime` | 纯 GDScript `SubpackRuntime`(`RefCounted`) | 游戏运行时 | ✅ 进包(被 protected) |

【据源码】`godot_subpack.gdextension`:`entry_symbol=godot_subpack_library_init`、`compatibility_minimum=4.4`、`reloadable=false`,所有 library 均为 `windows/macos/linux ... editor.single ...` 变体。`plugin.gd` 仅 `@tool EditorPlugin` 壳,`_enter_tree()` 里 `GodotSubpackEditorPlugin.new()` 拉起原生插件。→ **出厂游戏纯 GDScript,C++ 只在本机导出时运行,绝不进微信包。**

---

## 2. 流程 A:导出(编辑器侧,一次)【据产物推断 + 已跑通配方】

1. 工程装两个 addon;`export_presets.cfg` 的 Web 预设开:`subpack/enabled=true`、`subpack/minigame_mode=true`、`subpack/minigame_template_path=<微信模板目录>`、`subpack/wechat_native_audio_enabled=false`(本机无 ffmpeg 时必须关,否则 native audio 转码挂)。
2. 非 mono Godot 4.7 无头:先 `--import`,再 `--export-release "Web"`。C++ 插件接管:把 Godot 标准 Web 导出**拆成主包 + 分包**(按 `subpacks/subpack_profile.tres` 的 `SubpackProfile`;kit 此处 `packs=[]` = 内容全进主包),**引擎 wasm 自动进 `engine` 分包**。
3. 把结果**同步进微信模板目录** → 一份完整微信工程;写下 `.godot-subpack-managed.json` 标记 + `subpacks/subpack_manifest.json`(运行时清单)。成功标志 stdout:`Subpack: 已同步微信小游戏工程: <path>`。
4. `未找到 wasm32 库` 的 GDExtension 警告无害(插件 `.editor.single` + `variant/extensions_support=false`)。

### 关键:哪些文件必须进首包【据产物实测】
`subpack_manifest.json` 的 `main_pack_policy.protected_files`(kit demo 是 **44 个**)自动决策了"必须留主包"的集合:CoreKit autoload、**所有 `class_name` 脚本**(全局类在启动前就要可解析)、主场景 `demo.tscn`、两个 addon 本身。清单还记 `mode:minigame`、`main_pack.wechat_subpackage_name:engine`、`main_pack.wechat_pack_path:/engine/kit-demo.bin`、`pack_file_extension:.bin`、`pack_path_base:manifest_dir`。

---

## 3. 流程 B:产物结构 + JS 引导链【据产物实测,读了两个 game.js】

```
kit-demo-minigame/
├─ game.json          # subpackages:[{name:"engine", root:"engine/"}]  ← 只有 engine 一个分包
├─ game.js            # 微信入口(见下)
├─ weapp-adapter.js   # 60KB:把 window/document/canvas/WebGL/XMLHttpRequest 垫到 wx.* 上
├─ godot-loader.js    # GodotLoader,带加载进度 UI
├─ subpacks/subpack_manifest.json
├─ engine/            # engine 分包(大头都在这,主包才 ~68KB)
│  ├─ godot.wasm.br   # 8,405,811 B brotli 引擎
│  ├─ godot.js        # 引擎胶水
│  ├─ godot-sdk.js    # GODOTSDK JS 层
│  ├─ kit-demo.bin    # 153,448 B 游戏内容包
│  └─ game.js         # GODOTSDK.startGame('/engine/godot','/engine/kit-demo.bin')
├─ project.config.json / project.private.config.json
└─ images/
```

启动链:
1. 微信跑顶层 `game.js`:`import './native-audio-manifest'` + `import './weapp-adapter'`(装浏览器 API 垫片)+ `import './godot-loader'` → `checkUpdate()`(用微信 `wx.getUpdateManager` 做**整包 OTA**:onUpdateReady 弹窗 applyUpdate 重启)→ `GameGlobal.godotLoader = new GodotLoader(canvas, config)`(config 配首屏文案/进度条/背景图)。
2. GodotLoader 触发**微信分包加载器**下 `engine` 分包。**8.4MB wasm.br 在分包不在主包** → 主包过 4MB 门槛。
3. `engine/game.js`:`import './godot-sdk'` + `import './godot'` → `GODOTSDK.startGame('/engine/godot', '/engine/kit-demo.bin')` 启动引擎 wasm + 挂游戏包。
4. Godot 起,CoreKit autoload 引导 15 子系统;游戏代码可再用 `SubpackRuntime` 按需加载更多分包。

---

## 4. 流程 C:运行时分包加载 `SubpackRuntime`【据源码,读全 30KB】

`load_manifest()` 读 `subpack_manifest.json` 建 `_packs_by_name`。`ensure_subpack_with_dependencies(name)` 递归解依赖(`PackedStringArray` 栈做**环检测**),每包走 `_ensure_single_subpack` 的**四级优先链**:

1. **本地文件**(工程内已导出) → `ProjectSettings.load_resource_pack(path, true, 0)` 挂载。
2. **微信原生分包** `_ensure_wechat_subpackage_pack`:当 `OS.get_name()=="Web"` + 清单 `mode=="minigame"` + JS 侧 `JavaScriptBridge.get_interface("GODOTSDK")!=null` → 调 `sdk.load_pack(package_name, js_path, progress_cb, done_cb)` = **微信自己的分包下载器**(经 `JavaScriptBridge.create_callback` 收进度/完成),done 后挂载。
3. **本地缓存命中**(`user://godot_subpack_cache`)+ **SHA-256 校验**(`_verify_pack_file` 用 `HashingContext`)。
4. **远端 CDN 下载**:`HTTPRequest`(`download_file=temp`、`use_threads = not OS.has_feature("web")`、`timeout=30s`)→ SHA-256 校验 → 原子 `rename_absolute` 进缓存 → 按 `cache_budget_mb`(默认 45MB)**LRU 淘汰**(`_evict_lru_cache` 按 `last_access` 排序,跳过已挂载与豁免包)。挂载仍是 `load_resource_pack`。

挂载语义 = Godot 原生运行时 pack:把 `.bin/.pck` 的文件**覆盖进 `res://`**。全过程记结构化事件(`drain_runtime_events`),失败诊断直指微信门槛——下载失败会附:"如果当前是 Web/小游戏运行环境,优先检查远端域名 CORS、HTTPS 证书和平台合法域名白名单"。

包扩展名策略【据源码 `_pack_cache_extension`】:清单 `mode==minigame` → `.bin`,否则 `.pck`。

---

## 5. 与官方方案、与 kit `CoreKit.updater` 的关系

- **vs 官方通用适配**(见 `2026-07-27c`):官方把外部引擎经 SDL 取向 SDK + `wx-transformer` 塞进微信、锁死 emscripten 3.1.x;社区用 **Godot 自己的** emscripten 产物 + Godot 原生 `load_resource_pack`,天然吃 Godot 4.7。这是"Godot 走社区插件"的底层原因。
- **vs kit `PackUpdater`(v0.23–0.24)**:两者高度**同构**——CDN 下载 + SHA-256 校验 + `user://` 缓存 + `load_resource_pack` 挂载,连"web 下 `use_threads=false`""失败提示查合法域名"都一致。差别:**`SubpackRuntime` 多一条"微信原生分包 `GODOTSDK.load_pack`"路**(第 2 级),`PackUpdater` 没有。→ 若将来要把 kit 热更打通微信原生分包,这是明确的**借鉴/融合点**:给 `HttpPackTransport` 增一个"Web+minigame 时优先走 `GODOTSDK.load_pack`"的分支即可,其余(校验/缓存/挂载)kit 已具备。

---

## 6. 结论

社区方案是一套**"Godot 原生 + 微信分包"双层桥**:导出层(C++,仅编辑器)产出合法微信工程并把引擎 wasm 塞进 `engine` 分包过 4MB 门;运行时层(GDScript)用 `load_resource_pack` + 四级优先链(本地/微信原生分包/缓存/CDN)做按需加载与热更。它与 kit 自身的 `PackUpdater` 机制同源,唯一 kit 尚缺的是微信原生分包这条路——**故 Godot 上微信用社区插件是正解,且未来可低成本融合进 kit 的 updater 子系统。**
