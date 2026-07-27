# CoreKit 微信小游戏导出 Spike 报告

**日期**: 2026-07-27  
**分支**: `kit-wechat-spike`（不对齐 main / 不 push）  
**引擎**: Godot 4.7.stable.official.5b4e0cb0f（非 mono）  
**kit 版本**: CoreKit v0.24.1  

---

## 1. 导出是否成功

### 【据实测】成功

命令：

```text
Godot_v4.7-stable_win64_console.exe --headless --path <kit-wechat-spike> --import
Godot_v4.7-stable_win64_console.exe --headless --path <kit-wechat-spike> --export-release "Web" .../dist/kit-demo.html
```

关键 stdout 行：

```text
Subpack: 已同步微信小游戏工程: C:/toolkit/kit-demo-minigame
WARNING: Project export for preset "Web" completed with warnings.
```

### 警告清单（均判定为可接受）

| 消息 | 判定 |
|------|------|
| `WARNING: Subpack: 当前配置尚未定义任何分包` | 【据实测】profile `packs=[]` 故意空分包；主包 + engine 分包足够 |
| `WARNING: GDExtension: 未找到"wasm32"库 ... godot_subpack.gdextension` | 【确知】editor-only 扩展 + `variant/extensions_support=false`；任务说明无害 |
| PowerShell exit code 1 | 【据实测】WARNING 写 stderr 导致 NativeCommandError；打包流程已 `DONE savepack` 并同步模板 |

### 无 SCRIPT ERROR / push_error

导出过程 **未出现** `SCRIPT ERROR`、`ERROR:`、`push_error` 类致命输出。【据实测】

### 产物校验【据实测】

| 路径 | 状态 |
|------|------|
| `C:/toolkit/kit-demo-minigame/game.json` | 有；`subpackages: [{name:engine, root:engine/}]` |
| `C:/toolkit/kit-demo-minigame/project.config.json` | 有；`compileType: game`，libVersion 3.15.2 |
| `C:/toolkit/kit-demo-minigame/weapp-adapter.js` | 有（60774 B） |
| `C:/toolkit/kit-demo-minigame/engine/godot.wasm.br` | 有（8405811 B） |
| `C:/toolkit/kit-demo-minigame/engine/kit-demo.bin` | 有（153448 B） |
| `C:/toolkit/kit-demo-minigame/engine/godot.js` / `godot-sdk.js` / `game.js` | 有 |
| `dist/kit-demo.bin` / `dist/kit-demo.html` 等 | 有（Godot Web 中间产物） |
| `godot_ai` / `_mcp_game_helper` 进包 | **未检出**（对 `kit-demo.bin` ASCII 扫描） |
| `CoreKit` 字符串在 bin 中 | **检出** |

### 导出前工程改动【确知】

1. `project.godot`：删除 `_mcp_game_helper` autoload 与 `godot_ai` 插件；启用 `godot_subpack`
2. 新增 `export_presets.cfg`：Web + `subpack/*` + `minigame_template_path=C:/toolkit/kit-demo-minigame` + `wechat_native_audio_enabled=false` + `variant/thread_support=false` + `variant/extensions_support=false`
3. 新增 `subpacks/subpack_profile.tres`：`packs=[]`（全量主包）
4. 复制模板：`C:/toolkit/导出模板demo项目/minigame4.7` → `C:/toolkit/kit-demo-minigame`（不污染 empty-tips 对照）

---

## 2. 15 子系统存活诊断（核心）

### 2.1 实测环境边界

| 项 | 值 | 诚实标记 |
|----|-----|----------|
| 运行方式 | 非 mono Godot **headless** 源工程 `demo/demo.tscn` | 【据实测】 |
| 渲染器 | `gl_compatibility`（project.godot） | 【确知】 |
| 帧数 | `--quit-after 90` | 【据实测】 |
| 是否微信模拟器 / wasm 真跑 | **否**（本 worker 无头无法开微信开发者工具） | 【确知】 |
| 是否 `OS.has_feature("web")` | headless 桌面路径 **无** web feature | 【确知】 |
| 导出变体 nothreads | 导出预设 `variant/thread_support=false` 已写入 | 【确知】；运行时行为在微信侧【需实测】 |

### 2.2 CoreKit 启动横幅【据实测】

```text
[INFO] CoreKit v0.24.1 ready
[INFO] demo scene loaded — core-kit is wired up correctly
...
[INFO] CoreKit v0.24.1 — all subsystems smoke-tested
[INFO] FrameScheduler: 预算任务已执行
[INFO] ResourceManager: 预热批完成
[INFO] FrameScheduler: 每 30 帧心跳
```

**无** 子系统 `_ready` 报错、**无** SCRIPT ERROR。退出仅有：

```text
WARNING: 2 ObjectDB instances were leaked at exit
```

判定为 demo 场景 `free()` 路径遗留的轻量泄漏（非启动失败）。【据实测】

### 2.3 门面 15 子系统逐项

| # | 属性 | 子系统 | headless 冒烟 | gl_compat / nothreads / web 适配判断 | 适配需求 |
|---|------|--------|---------------|--------------------------------------|----------|
| 1 | `log` | Log | OK（全程 INFO） | 纯 print / push_* | 无 |
| 2 | `settings` | Settings | OK `demo.flag=true` 写读 | `user://settings.json`；Web/微信靠 IDBFS 映射 | 微信落盘【需实测】；代码已按 Web 设计【确知】 |
| 3 | `bus` | EventBus | OK 同步投递 | 纯 GDScript 信号表 | 无 |
| 4 | `scenes` | SceneManager | OK `is_changing=false` | 同步 `load()`，注释写明 Web 安全；Tween 转场 | 真切场景+转场【需实测】 |
| 5 | `pool` | ObjectPool | OK acquire/release | 节点池 | 无 |
| 6 | `saves` | SaveManager | OK save/load/delete + Object 守卫 | 注释：Web 与桌面 FileAccess 一致 | 微信 user://【需实测】 |
| 7 | `ticker` | FrameScheduler | OK 预算任务 + 每 30 帧 | `_process` 分帧，不依赖线程 | 无 |
| 8 | `input` | InputManager | OK device/buffer 查询 | 设备枚举含 TOUCH；重绑定键鼠事件 | 触屏手势路径【需实测】；键鼠 rebind 在小游戏意义有限【据知识推断】 |
| 9 | `audio` | AudioManager | OK volume 读写 | 代码注释：Web 自动播放策略到手势后出声 | 微信音频策略 / 可选 native audio【需实测】；本导出关了 ffmpeg native audio |
| 10 | `res` | ResourceManager | OK 预热批完成 | **已适配**：`use_threads = not web and threads`；Web 走 FrameScheduler 分帧同步 load | 超大单资源仍可能卡帧【据知识推断】 |
| 11 | `console` | DevConsole | OK execute/god | release 包 `OS.is_debug_build()=false` 整机关闭 | 发行微信包默认 no-op【确知】 |
| 12 | `i18n` | LocaleManager | OK en/zh 切换 | TranslationServer + Theme 字体 | 中文字体需游戏侧提供【据知识推断】 |
| 13 | `layers` | LayerManager | OK mount hud | CanvasLayer z 序 | 无 |
| 14 | `clock` | GameClock | OK advance_day + bus 事件 | 纯逻辑时钟 | 无 |
| 15 | `updater` | PackUpdater | OK mounted=0 | **已适配**：`restart_to_apply()` 在 web/headless 返回 false；HTTP 传输 Web 走内存落盘 | 热更下载在微信 CDN/域名白名单【需实测】；**重启屏障硬限制**见下 |

### 2.4 非门面类库（demo 一并冒烟）【据实测】

| 类 | 结果 |
|----|------|
| KitStateMachine | OK transition/dispatch/pushdown |
| KitContext | OK provide/resolve/factory/subscribe |
| KitRebindButton | OK capture + 冲突拦截 |
| KitTransition | OK SLIDE marker |
| KitUiStack | OK push/modal |
| KitInventory | OK 溢出/move |
| KitDataRegistry | OK register/get_def |

### 2.5 代码审查：线程 / Web 分支【确知】

- 全 kit **无** `Thread` / `WorkerThreadPool` / `Mutex` 直接用法
- 唯一线程相关 API：`ResourceManager` 的 `load_threaded_*`，且 **仅在非 web 且 threads feature 时启用**
- `HttpPackTransport.fetch_file`：`OS.has_feature("web")` 时改内存 body + `FileAccess.store_buffer`（注释记载 download_file 在 Web 不可靠）
- `PackUpdater.restart_to_apply`：web 或 headless → `return false`，不调用 `OS.set_restart_on_exit`

### 2.6 需关注的降级 / 硬限制

1. **PackUpdater 重启屏障** — 【确知】代码行为  
   含 GDScript 逻辑的热更包在桌面靠自重启；**Web/微信无法 `set_restart_on_exit`**。接入方必须自行提示玩家重新进入小游戏。这不是崩溃阻断，是**产品流程适配**。

2. **ResourceManager 分帧通道** — 【确知】  
   nothreads / web 下自动降级，API 不变；大资源加载帧仍可能尖刺。

3. **Settings / Save 落盘** — 【据知识推断】+【需实测】  
   Godot HTML5 `user://` 通常经 IDBFS；微信小游戏适配层是否完整透传 FileAccess，**必须在开发者工具里验一轮** save/settings 往返。

4. **Audio 自动播放** — 【据知识推断】+【需实测】  
   微信/浏览器均有用户手势限制；kit 不额外处理，依赖引擎+适配层。

5. **DevConsole 发行关闭** — 【确知】  
   release 导出无调试开销；debug 模板另议。

6. **ObjectDB leak×2** — 【据实测】  
   headless demo 退出警告，未阻塞冒烟；建议后续清 demo 资源生命周期，**不构成上微信硬阻断**。

---

## 3. 最终微信工程路径

**供微信开发者工具打开：**

```text
C:\toolkit\kit-demo-minigame
```

中间 Web 导出产物（对照）：

```text
E:\orca\workspaces\godot-core-kit\kit-wechat-spike\dist\
```

打开后建议验证：

1. 模拟器能否加载 engine 分包 + 进主场景  
2. 控制台是否出现 `CoreKit v0.24.1 ready` 与 smoke 日志  
3. `user://` 存档/设置是否可写  
4. 音频在用户手势后是否可播  

---

## 4. 判定结论

### **基本可行，需少量接入侧适配（非子系统硬阻断）**

**依据：**

1. 【据实测】godothub/subpack 管线能把 **含完整 CoreKit demo 的工程** 导出并同步为微信小游戏目录（`Subpack: 已同步...` + wasm/bin/adapter 齐全）。  
2. 【据实测】`gl_compatibility` 下 CoreKit 门面启动成功，demo 对 15 门面子系统 + 附属类库冒烟全部通过，无 SCRIPT ERROR。  
3. 【确知】kit 纯 GDScript、无 GDExtension 运行时依赖；已有 web/nothreads 分支（ResourceManager / HttpPackTransport / PackUpdater.restart）。  
4. 【需实测】微信开发者工具实机：user://、音频、触控、热更域名、包体分包策略。  
5. **无发现**「某子系统 API 在 web 必然崩溃」的硬阻断；最接近硬限制的是 **PackUpdater 不能自重启**——已降级为返回 false，不是启动炸。

### 建议后续（非本 spike 范围）

| 优先级 | 项 |
|--------|-----|
| P0 | 用户/协调者用微信开发者工具打开 `C:\toolkit\kit-demo-minigame` 实机跑 demo |
| P1 | 验证 SaveManager / Settings 在微信 `user://` 往返 |
| P1 | 验证 AudioManager 手势后播放 |
| P2 | 游戏侧接入 PackUpdater 时实现「提示重进」代替 `restart_to_apply` |
| P2 | 内容变大时再填 `subpack_profile.tres` 拆包（当前空 packs 可接受） |

---

## 5. 诚实纪律汇总

| 标记 | 本报告中的用法 |
|------|----------------|
| 【确知】 | 文件/配置/源码白纸黑字 |
| 【据实测】 | 本 worker 本机命令真实输出 |
| 【据知识推断】 | 引擎/微信通用行为，未在本机微信模拟器复现 |
| 【需实测】 | 必须开发者工具/真机才能盖章 |

**禁止编造声明**：本报告所有「跑通/报错」均附命令输出原文；**未**声称微信模拟器内已运行成功。
