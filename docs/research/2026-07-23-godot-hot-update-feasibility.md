# Godot 4.7 分包瘦身 + 热更（KitUpdater）技术可行性调研

> 日期:2026-07-23 ｜ 目的:为 `godot-core-kit` 的 `KitUpdater`(先在 `fortune-mill` 落地)论证「真·分包瘦身 + 远程内容包 + 含 GDScript 逻辑热更」的技术可行性,逐条对齐**一手来源**(docs.godotengine.org / godotengine/godot 源码与 issue / Google Play & Android 官方文档)。
> 目标引擎:**Godot 4.7 stable,非 mono(纯 GDScript),GL Compatibility 渲染器**;优先 Android,其次 Web。
> 文档版本核对:调研当日 `docs.godotengine.org/en/stable` 已指向 **Godot 4.7**(下文所有 `…/en/stable/…` 链接页头均标注 "Godot Engine 4.7");源码引用统一取 `godotengine/godot` 的 `4.7` 分支。

---

## 0. TL;DR

- **Android:可行**。薄壳 APK/AAB + 自建 HTTP 下载内容包到 `user://` + 在 autoload `_init()` 里 `ProjectSettings.load_resource_pack()`。GDScript 覆盖可用;`class_name` 全局类与 `uid://` 映射在挂载时**会自动并入缓存**(4.3 起,源码实证)。
- **Web:可行但风险显著更高**。`load_resource_pack` 走「HTTPRequest 下载 → 写 `user://`(IDBFS)→ 挂载」路径上讲得通,但官方文档**未正面记载 Web 下的分包**,且历史上有平台 bug(#58013);叠加 IDBFS 持久化被浏览器回收、内存、以及多线程构建的 COOP/COEP 硬约束。判定为「须尽早实测验证的 best-effort」。
- **GDScript 热更的真相(关键结论)**:能从挂载的包里**覆盖并执行**新脚本,但**已经 `load()` 过的脚本 / 正在运行的实例不会热替换**——引擎按路径缓存资源;唯一可靠的「换逻辑」姿势是 **在这些脚本/场景被加载之前**先挂好包(autoload `_init()`),然后**新实例化场景 / 重载当前场景 / 重启**。没有对运行中对象做活体打补丁的机制。
- **两条会打脸原计划的一手证据**:① **引擎版本锁死**——包头会拒绝「由更新版引擎导出的包」,意味着每次升 Godot 版本都得**重新导出全部内容包**(源码 `file_access_pack.cpp`)。② **Google Play 自更新条款**——GDScript 属解释型语言、不算被禁的「dex/native 可执行代码」,但「App 不得以 Google Play 更新机制以外的方式修改/替换/更新自身」这条,让「远程下发 GDScript 逻辑」落在**政策灰区**(Device and Network Abuse policy)。

---

## 1. 运行时挂载语义:`load_resource_pack(pack, replace_files, offset)`

方法签名与描述(逐字取自一手 class XML,`doc/classes/ProjectSettings.xml @ 4.7`):

```xml
<method name="load_resource_pack">
  <return type="bool" />
  <param index="0" name="pack" type="String" />
  <param index="1" name="replace_files" type="bool" default="true" />
  <param index="2" name="offset" type="int" default="0" />
  <description>
    Loads the contents of the .pck or .zip file specified by [param pack] into the resource filesystem ([code]res://[/code]). Returns [code]true[/code] on success.
    [b]Note:[/b] If a file from [param pack] shares the same path as a file already in the resource filesystem, any attempts to load that file will use the file from [param pack] unless [param replace_files] is set to [code]false[/code].
    [b]Note:[/b] The optional [param offset] parameter can be used to specify the offset in bytes to the start of the resource pack. This is only supported for .pck files.
    [b]Note:[/b] [DirAccess] will not show changes made to the contents of [code]res://[/code] after calling this function.
  </description>
</method>
```
来源:[godotengine/godot `4.7:doc/classes/ProjectSettings.xml`](https://raw.githubusercontent.com/godotengine/godot/4.7/doc/classes/ProjectSettings.xml)、渲染页 [ProjectSettings — Godot 4.7](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html)。

要点拆解:
- **挂载什么**:把 `.pck`/`.zip` 内容并入虚拟文件系统 `res://`。挂载后按**路径**命中。
- **`replace_files` 如何决定覆盖**:默认 `true` —— 同路径文件后挂的包**覆盖**先前(base)版本;传 `false` 则保留原文件(用于「只补新增、不动旧文件」的场景)。这是「补丁/热更覆盖 base 脚本」的机制核心。来源:上引 XML 第 1 条 Note + [Exporting packs, patches, and mods — 4.7](https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html):"By default, if you import a file with the same file path/name as one you already have in your project, the imported one will replace it… To opt out of this behavior, pass `false` as the second argument"。
- **`offset` 干嘛用**:仅 `.pck` 支持,指定「资源包在文件里的起始字节偏移」——用于**把 PCK 追加嵌入到可执行文件尾部**的嵌入式包(embedded pack)场景。对我们「独立远程包」用不到,置 0。来源:上引 XML 第 2 条 Note。
- **`.pck` vs `.zip` 取舍**(取自 [Exporting projects — 4.7](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html) "PCK versus ZIP pack file formats" 节):
  - PCK:"Uncompressed format. Larger file size, but faster to read/write." + "Not readable and writable using tools normally present on the user's operating system"(不易被玩家用系统自带工具打开/改)。
  - ZIP:"Compressed format. Smaller file size, but slower to read/write." + 可被系统工具读写。
  - 官方结论:"PCK is the default and recommended format for most use cases"。**注意 ZIP 主包的坑**:同页记载 ZIP 作主包时导出的二进制不会自动使用它,需要启动脚本用 `--main-pack` 参数指定。对**热更内容包**(非主包)这条不影响,但选型上:传输走 CDN 想省流量可 ZIP,想解压快、想防玩家轻易改动可 PCK。
- **可同时挂多个 + 加载顺序**:[exporting_pcks 4.7](https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html) "It is possible to load both PCK and ZIP files as additional packs at the same time." 同路径冲突时**后挂的胜出**(在 `replace_files=true` 下)。**补丁包对顺序敏感**:"the packs you list under Base Packs in the Patching tab must be the exact same files that are loaded by the game at runtime, in the exact order they are loaded in."(同页 Patching 节)——即 base + 各补丁的**挂载顺序必须与导出补丁时声明的一致**。

---

## 2. 如何单独产出「包」,以及「薄壳 + 内容包」是否一等公民

**产出方式**:
- 编辑器:`Project > Export`,选 preset,点 **Export PCK/ZIP**。"This is not a playable build, it only exports the project data without a Godot executable."(仅数据,无引擎二进制)——来源:[Exporting projects — 4.7](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html)。
- CLI:`godot --export-pack "<PresetName>" out.pck`。"export from the command line with `--export-pack`. The output file must … a `.pck` or `.zip` file extension."(preset 名必填)——来源:[exporting_pcks 4.7](https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html) + [exporting_projects 4.7](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html)。可配 `--path /proj` 免 cd、`--headless` 无窗口跑(本仓库出 APK 已用类似 CLI 姿势)。

**控制"哪些资源进包 / 哪些留 base"**(一手来源:[exporting_projects 4.7](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html) "Resource options" 节):导出模式有五种——导出全部资源 / 仅选中场景及其依赖 / 仅选中资源及其依赖 / 全部除勾除项 / 专用服务器;另有两个 filter:一个把 `.txt/.json/.csv` 等**非资源文件**也带进去,一个用来**按类型排除**。

**"薄壳 base + 内容包"是不是一等公民?——不是,必须手搓**。官方一等支持的是两类:
1. **Patch(补丁)**:导出菜单 Patching 页,勾 "Export as Patch" 后"only resources that have changed will be exported"——这是**在完整 base 之上叠增量**的模型,不是「base 本来就空」。
2. **Mod/DLC**:运行时 `load_resource_pack` 挂第三方包。

我们要的「base 只装启动壳、绝大多数内容在远程包」并没有一个「拆成 base+content」的按钮。**落地做法(手搓)**:给 base 用一个「仅选中场景及其依赖」的 preset,只圈进启动/loading 场景 + KitUpdater autoload + 最小依赖;把其余内容用**另一个 preset** `--export-pack` 单独导成内容包。二者**必须同一工程、同一引擎、同一渲染器**导出(见 §3)。因为补丁 base-packs 顺序强约束(§1),多包拆分时要固定「base → content-A → content-B」的稳定挂载序。

---

## 3. 包与引擎的兼容性:格式版本 + 引擎版本闸门

一手源码(`godotengine/godot 4.7`):
- 包头魔数与格式版本:`#define PACK_HEADER_MAGIC 0x43504447`(即 ASCII "GDPC")、`#define PACK_FORMAT_VERSION PACK_FORMAT_VERSION_V4`(当前 **V4 = 4**;并存 V2/V3 常量)。来源:[`core/io/file_access_pack.h @ 4.7`](https://raw.githubusercontent.com/godotengine/godot/4.7/core/io/file_access_pack.h)。
- 打开包时的校验(`PackedSourcePCK::try_open_pack`,`core/io/file_access_pack.cpp @ 4.7`):
  - **格式版本闸门**:`ERR_FAIL_COND_V_MSG(version != PACK_FORMAT_VERSION_V4 && version != PACK_FORMAT_VERSION_V3 && version != PACK_FORMAT_VERSION_V2, false, vformat("Pack version unsupported: %d.", version));` —— 只认 V2/V3/V4,其它直接拒。
  - **引擎版本闸门**:`ERR_FAIL_COND_V_MSG(ver_major > GODOT_VERSION_MAJOR || (ver_major == GODOT_VERSION_MAJOR && ver_minor > GODOT_VERSION_MINOR), false, vformat("Pack created with a newer version of the engine: %d.%d.%d.", ver_major, ver_minor, ver_patch));`
  - 来源:[`core/io/file_access_pack.cpp @ 4.7`](https://raw.githubusercontent.com/godotengine/godot/4.7/core/io/file_access_pack.cpp)。

**结论(对设计的硬约束)**:
- 包会**拒绝「用比当前运行引擎更新的版本导出的包」**;由**更旧**引擎导出的包在格式层面仍可挂(V2/V3/V4 都收)。
- 但这只是**容器层**的闸门。**资源层**(`.import` 产物、shader、着色管线)与**渲染器**强相关:GL Compatibility 与 Forward+/Mobile 导出的贴图/材质产物不同,跨渲染器混用会在加载/渲染期出问题。**务必:内容包与 base 用同一 Godot 4.7.x + 同一 GL Compatibility 工程设置导出。**(此段渲染器/资源层结论为工程推断,非单条文档明文;容器版本闸门为源码实证。)
- **运维含义**:一旦把游戏引擎从 4.7.x 升到 4.8,**所有历史内容包都要重导**——否则新引擎能读旧包(向下兼容),但你无法用旧引擎读新包做增量,且资源产物可能已变。KitUpdater 的 manifest 必须带「目标引擎版本」字段并在挂载前校验,避免踩上面的 `ERR_FAIL`。

---

## 4. 从挂载包做 GDScript 热更(关键)

**能覆盖并执行吗?——能,但有严格前提。**
- 包"usually contain"脚本(scripts)在内——[exporting_pcks 4.7](https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html) 明列 PCK/ZIP 内容含 scripts;`replace_files=true` 时同路径 `.gd`/`.gdc` 由包覆盖 base(§1 的 Note)。
- **`class_name` 全局类注册**:历史上「挂 PCK 后全局脚本类缓存与 UID 缓存不更新,导致用 `class_name` 的脚本解析不了」是个真 bug——[PR #82084 "Merge `uid_cache.bin` and `global_script_class_cache.cfg` after mounting PCKs"](https://github.com/godotengine/godot/pull/82084):"The global script and UID caches were not getting updated after PCK files mount. This resulted in scripts using global `class_name` not being able to resolve properly…"。该 PR 已合并、**4.3 起生效**。源码实证:`ProjectSettings::_load_resource_pack`(`core/config/project_settings.cpp @ 4.7`)在 `PackedData::add_pack()` 之后调用 `ResourceUID::get_singleton()->load_from_cache(false)` 与 `refresh_global_class_list()`,把包里的 UID 映射与全局类并入当前进程。来源:[`core/config/project_settings.cpp @ 4.7`](https://raw.githubusercontent.com/godotengine/godot/4.7/core/config/project_settings.cpp)。**前提**:内容包导出时得带上 `.godot/uid_cache.bin` 与全局类缓存(正常整包/补丁导出会带)。PR 也注明合并语义是「merge 而非 replace」以支持多 DLC/mod 各自独立信息。

- **已加载脚本 / 运行中实例不会热替换**(反复确认,务必内化):
  - `load_resource_pack` 自带 Note:"[DirAccess] will not show changes made to the contents of `res://` after calling this function."(§1 XML)——挂载后目录视图都不刷新。
  - 时机 Note(逐字,[exporting_pcks 4.7](https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html)):"If you are loading a resource pack and are not noticing any changes, it may be due to the pack being loaded too late. This is particularly the case with menu scenes that may preload other scenes using `preload()`. … To avoid this, you need to load the pack as early as possible. To do so, create a new autoload script and call `ProjectSettings.load_resource_pack()` in the autoload script's `_init()` function, rather than `_enter_tree()` or `_ready()`."
  - 机理:`ResourceLoader` 按路径缓存资源;已 `load()`/`preload()` 的脚本会返回**缓存里的旧对象**,挂新包也不会替换已实例化对象的 class。
- **支持的"换逻辑"姿势**:① 在 autoload `_init()` 里**尽早挂包**(先于任何相关脚本/场景被 preload);② ~~之后新实例化目标场景 / `reload_current_scene()` / `change_scene_to_*` 加载新场景~~ **⚠️ 已被实测证伪,见 §4b**——只有当该脚本**本进程从未加载过**时才成立;③ **重启进程**读新包(含脚本更新时的唯一可靠手段)。没有对活体对象打补丁的官方机制。KitUpdater 的现实形态 = 「下载 → 重启 → 在 autoload `_init()` 挂载」,而非「运行中静默替换某个正在跑的 node 脚本」,也不是「重载场景」。

- **脚本导出模式(Text vs Binary tokens)**:4.3 起可选「二进制令牌化(binary tokenization)」导出。[Godot 4.3 release notes](https://godotengine.org/releases/4.3/):"you can reduce the size of your GDScript exports drastically … in technical terms this is called binary tokenization. As a side effect, this effectively obfuscates your code … it can still be decompiled … prevents your code from being available in plaintext at least." 无论 Text 还是 Binary tokens,脚本都能从包里正常执行;但**内容包与 base 的脚本导出模式建议一致**,避免混用带来的怪异。

- **脚本加密(重要耦合)**:若对 PCK 开启加密,则**加密包必须用与运行二进制里编译进去的同一把 256-bit AES key 才能被读取**。[Compiling with PCK encryption key — 4.7](https://docs.godotengine.org/en/stable/engine_details/development/compiling/compiling_with_script_encryption_key.html):key "needs to be stored in the binary",需在编译**自定义导出模板**时设 `SCRIPT_AES256_ENCRYPTION_KEY` 环境变量,**官方预编译模板用不了加密**。设计含义:要么 base 与所有内容包都用同一 key 且**必须自编译模板**(不能用官方模板,当前本仓库出 APK 用的就是官方标准模板),要么**全程不加密**。想加密就得改整条构建链;起步阶段建议**不加密**,把加密留作后续可选项。

---

## 4b. 实测:「退出子场景 → 中途挂包 → 重进」到底行不行(2026-07-23 headless 探针)

**动机**:§4 第 ② 条("挂包后新实例化目标场景即可换逻辑")读起来像是「玩家退出子游戏后下新包、再进去就生效」,这是产品侧最想要的形态。**实测证伪**:该条只在「**该脚本本进程从未被加载过**」时成立。

**实验**:Godot **4.7.stable.official (5b4e0cb0f)**,headless。base 含 `room.gd`(返 `"V1"`)+ `room.tscn` + `data.txt`;内容包(zip)只含 `room.gd`(返 `"V2"`)与 `data.txt`,**故意不含 `.tscn`**,以精确测「场景不变、只热修脚本逻辑」。每个测量各跑**一个干净进程**(第一轮把 5 个测量塞进同一进程,前序 `load` 污染了缓存、得出过假阳性 V2——隔离后消失)。

| 模式 | 序列 | 结果 |
|---|---|---|
| `early`(对照组) | 挂包 → 首次加载 | **V2** ✅ |
| `iso-scene` | 进过一次 → 全部释放 → 挂包 → 走 `.tscn` 重进 | **V1** ❌ |
| `iso-script` | 同上,改用 `load("res://room.gd")` | **V1** ❌ |
| `iso-replace` | 同上,`CACHE_MODE_REPLACE` | **V1** ❌ |
| `iso-ignore` | 同上,`CACHE_MODE_IGNORE` | **V2** ✅(但对象游离,见下) |
| `held` | hub 攥着 `PackedScene` 引用不放 → 挂包 → 重进 | **V1** ❌ |

**关键观测**:在实例 `free()`、`PackedScene` 引用置空之后——
- `ResourceLoader.has_cached("res://room.tscn")` = **false**(`.tscn` 被正常逐出)
- `ResourceLoader.has_cached("res://room.gd")` = **true**(`.gd` **不被逐出**,与引用计数无关)
- `FileAccess.get_file_as_string("res://data.txt")` = **V2**(证明包确实已挂载生效,排除「包没生效」的干扰解释)

即:**包挂上了、`.tscn` 也重新读了,但它的脚本依赖仍解析到缓存里的旧 GDScript。**

**源码机理**(一手):GDScript 有**独立于 `ResourceCache` 的第二层缓存**——`GDScriptCache` 单例持有 `shallow_gdscript_cache` 与 `full_gdscript_cache`,均以路径为 key。来源:[`4.7:modules/gdscript/gdscript_cache.cpp`](https://raw.githubusercontent.com/godotengine/godot/4.7/modules/gdscript/gdscript_cache.cpp)。
- 该文件里确有 `GDScriptCache::remove_script(const String &p_path)` 与 `GDScriptCache::clear()`,但**均未经 ClassDB 暴露到脚本层**,`clear()` 只在单例析构(引擎关闭)时执行。→ **GDScript 侧不存在任何正规 API,能在运行时逐出或重载单个已缓存脚本。**
- `CACHE_MODE_REPLACE` 在 `ResourceLoader` 层本应「重读磁盘 + `old_res->copy_from(new_res)`」以保持对象标识([`4.7:core/io/resource_loader.cpp`](https://raw.githubusercontent.com/godotengine/godot/4.7/core/io/resource_loader.cpp)),但 GDScript 的格式加载器先经 `GDScriptCache::get_full_script()` 命中自有缓存,故 REPLACE 对 `.gd` **无效**(实测 V1 佐证)。
- `CACHE_MODE_IGNORE` 能读到 V2,但返回的是**不入缓存的游离脚本对象**,并不修正 `.tscn` 的依赖解析(`iso-scene` 已证),只能手工往节点上 `set_script()`——不构成通用方案。

**对设计的硬结论**:
1. **含 GDScript 的逻辑包 ⇒ 换逻辑必须重启进程。** KitUpdater 的"重载屏障" = **进程重启**,`reload_current_scene()` 不够。
2. **纯资源/数据/场景包**在会话中途挂载**有可能**即时生效,但前提是无活引用(`held` 组证明:hub 攥着 `preload` 引用就拿旧的)。只能作为**受控的可选优化**,不能作为默认承诺。
3. 「玩家本次会话恰好没进过那个子游戏 → 挂包后首进拿到新版」属**碰巧生效**(等价 `early`),不可预测,**不得作为设计依据**。

**遗留待验证**:Android 上能否**自重启**(`OS.set_restart_on_exit()` + `quit()`)?若不可行,更新后的用户体验退化为「提示玩家手动重开 App」,需在设计里明确。

探针源码:scratchpad 的 `packprobe/`(一次性,未入库)。

---

## 5. ResourceUID 的坑(Godot 4 特有)

- 基本盘:`ResourceUID` 是管理全工程资源唯一标识的单例;`uid://` 方案让「文件改名/移动后引用不断"。来源:[ResourceUID — 4.7](https://docs.godotengine.org/en/stable/classes/class_resourceuid.html)、[`doc/classes/ResourceUID.xml @ 4.7`](https://raw.githubusercontent.com/godotengine/godot/4.7/doc/classes/ResourceUID.xml)("Resource UIDs … allow the engine to keep references between resources intact, even if files are renamed or moved.")。可用 API:`add_id / set_id / remove_id / get_id_path / has_id / create_id / create_id_for_path / id_to_text / text_to_id` 等(注意:4.7 的公开 API **没有**暴露专门的「merge pack cache」方法——并入是在 `load_resource_pack` 内部自动做的,见 §4)。
- **挂包时 UID 自动并入**:如 §4 所述,`_load_resource_pack` 会 `ResourceUID::load_from_cache(false)` 把包内 `uid_cache` 合并进来(4.3 起,PR #82084)。所以**只要内容包带了自己的 uid_cache,`load("uid://…")` 就能解析到包里的新资源**。
- **风险点**:
  - **UID 碰撞真实存在**。相关已知 issue:[#54774 Duplicated files or resources retains the same UID](https://github.com/godotengine/godot/issues/54774)、[#57220 Duplicating a resource (CTRL+D) also duplicates the resource UID](https://github.com/godotengine/godot/issues/57220)、[#102490 No fix is offered for existing duplicate UIDs](https://github.com/godotengine/godot/issues/102490)。当两份资源共享同一 UID,运行时可能**只用到其中一个**、或引用解析到错误文件。
  - 对分包/DLC 的含义:若内容包里某资源的 UID 与 base 某资源**UID 相同但路径不同**,合并后 `uid://` 解析会指向其中一个,行为不确定。
  - PR #82084 的合并**只在 `replace_files` 启用时**才按预期工作(该 PR 亦注明非替换场景遗留问题)。
- **设计规避**:① **覆盖 base 用「同路径 + `replace_files=true`」**(按路径覆盖是最稳的通道),不要依赖「靠 UID 让新资源顶替旧资源」;② 内容包**新增**资源时,保证其 UID 在全工程唯一(同一工程内导出一般 OK;跨工程/复制资产时用 `create_id_for_path` 重新生成,避免撞库);③ KitUpdater 打包脚本可加一步「UID 唯一性自检」。

---

## 6. Android 专项

- **下载到可写位置并挂载**:`user://` 在移动端是**每工程独立、始终可写**的持久目录;`res://` 导出后**只读**。来源:[File paths in Godot projects — 4.7](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html)("On some devices (for example, mobile and consoles), this path is unique to the project";"when the game is running, the project's file system will likely be read-only … use `user://` for persistent data")。流程:HTTPRequest 下载 → `FileAccess` 写 `user://packs/xxx.pck` → `ProjectSettings.load_resource_pack("user://packs/xxx.pck")`。`load_resource_pack` 接受任意 `FileAccess` 能打开的路径,`user://` 合法,Android 内部存储可用。
- **作用域存储 / 权限**:Android 上 `user://` 落到应用**内部专属存储**(getFilesDir 语义),在 scoped storage 模型下**读写自身内部存储无需任何运行时权限**。因此把下载包写进 `user://` 不触发存储权限申请——这是最省事、最合规的落盘方式(不要往共享外部存储写)。
- **Google Play 体积上限与大内容投递**:
  - AAB 政策:新 App **大于 200 MB** 必须借 Play Feature Delivery 或 Play Asset Delivery;单次下载(base + config APK)压缩体积上限 **4 GB**;"Asset packs don't contribute to this size limit"。来源:[Android App Bundle — developer.android.com](https://developer.android.com/guide/app-bundle)。**薄壳恰好受益**:base APK/AAB 极小,内容走我们自建 CDN → `user://`,完全绕开 Play 的投递体系,不受其大小与投递机制约束。
  - **OBB 扩展文件:Godot 4.7 已移除**。[PR #118283 "Android: Remove deprecated Google Play OBB support"](https://github.com/godotengine/godot/pull/118283)("The current obb support was specific to the Google Play store which has deprecated the format"),已合入 **4.7 里程碑**,废弃逻辑迁到独立插件 [m4gr3d/godot-obb-plugin](https://github.com/m4gr3d/godot-obb-plugin)。**结论:不要指望内建 OBB。**
  - **Play Asset Delivery:仅半支持**。Godot 3.x [PR #52526](https://github.com/godotengine/godot/pull/52526) 只加了「单个 install-time asset pack」,**不支持动态下载的 asset pack**;4.x 也无一等的动态 PAD。→ 我们的方案**不依赖 PAD**,用自建 HTTP 下载 + `load_resource_pack`,规避这块缺失。
- **Play 政策:下载可执行代码(GDScript-in-pack 的合规性)**——这是**政策而非技术**的最大不确定项。[Device and Network Abuse — Play Console Help](https://support.google.com/googleplay/android-developer/answer/16559646) / [policy 页](https://play.google.com/about/privacy-security-deception/device-network-abuse/):
  - 禁止条款:"Apps or third party code … that download executable code, such as dex files or native code, from a source other than Google Play are prohibited."——针对 **dex / native(.so)**。
  - 解释器豁免:"This restriction does not apply to code that runs in a virtual machine or an interpreter where either provides indirect access to Android APIs (such as JavaScript in a webview or browser)."——且明列 "interpreted languages (JavaScript, Python, Lua, etc.)"。**GDScript 属解释型**,与 Lua/JS 同类,不算被禁的 dex/native「可执行代码」。
  - **但**两条约束仍悬:①"interpreted languages … loaded at run time … must not allow potential violations of Google Play policies."(下发的脚本不能借机违反其它政策);②**自更新条款**:"An app distributed via Google Play may not modify, replace, or update itself using any method other than Google Play's update mechanism."——「远程下发 GDScript 逻辑替换 App 行为」在字面上与此条**存在张力**。业内惯例:下发**游戏内容/关卡/mod 脚本**通常被接受(等同 Lua 脚本游戏),但「用远程包整体改写 App 核心行为」有被判 self-update 违规的风险。→ **建议**:把热更定位为「游戏内容与玩法数据/脚本」,避免宣称/实现「绕过商店更新客户端本身」;高风险 Bug 修复仍走商店发版;将该合规判断显式记入 KitUpdater 文档并让接入方知情。

---

## 7. Web 专项

- **`load_resource_pack` 在 Web 能不能用?**:官方文档**未正面记载** Web 下用 `load_resource_pack` 分包;历史上有平台 bug [issue #58013 "Exporting packs, patches, and mods did not work on HTML5 exports"](https://github.com/godotengine/godot/issues/58013)(报告于 3.4.2,标 `platform:web`/`needs testing`,长期未闭环)。另有 [proposal #5389](https://github.com/godotengine/godot-proposals/issues/5389) 请求「让 `load_resource_pack` 能从数据流而非文件路径加载」——侧证**当前只能从路径加载**,即必须先把整包写进虚拟 FS 再挂。→ 技术路径讲得通,但**属官方文档空白 + 历史不稳区,必须尽早实测。**
- **落盘流程**:HTTPRequest 下载 → 写 `user://`(Web 上 `user://` 是 IndexedDB 虚拟文件系统)→ `load_resource_pack("user://…")`。来源:[data_paths 4.7](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html)("On HTML5 exports, `user://` will refer to a virtual filesystem stored on the device via IndexedDB")。
- **IDBFS 持久化坑**([Exporting for the Web — 4.7](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)):"Users must allow cookies (specifically IndexedDB) if persistence of the `user://` file system is desired.";浏览器可能回收缓存("web browsers can choose to evict the cached data if the user runs low on disk space, or if the user hasn't opened the project for a while.");`OS.is_userfs_persistent()` 可查但"can give false positives"。→ **下载的包不保证长期留存**,KitUpdater 需容忍「重进后包丢失 → 重新下载」。
- **网络限制**:Web 端 "only HTTP client, HTTP requests, WebSocket (client)" 等被支持,且受**同源策略**约束(同上文档)。CDN 需正确 CORS。
- **线程 / SharedArrayBuffer / 跨源隔离**:仅当以 "Use Threads" 导出才需 `SharedArrayBuffer`,而这**要求 secure context + 两个响应头**:"`Cross-Origin-Opener-Policy: same-origin`" 与 "`Cross-Origin-Embedder-Policy: require-corp`"(同上)。GL Compatibility 单线程构建可以不开线程从而**规避 COOP/COEP 硬约束**,但托管方仍需能设这些头才走得了多线程路线。
- **内存**:Web 运行整个游戏在浏览器内存里,包也需读入 VFS(内存);大包在低端设备/移动浏览器有 OOM 风险(此点官方 Web 页未给具体数值,属工程注意项,结合 proposal #5389「只能整包入 VFS」推断)。
- **Web 小结**:可行性成立但**脆**——文档空白 + 历史 bug + 持久化被回收 + 内存 + 多线程需 COOP/COEP。**建议**:Web 上把分包做**保守**(少切、切大块内容而非核心逻辑),核心可玩循环尽量留在初始主包里;把「重进后重下」当常态设计;上线前用真 4.7 Web 导出端到端验证 `user://` 挂载。

---

## 8. 版本清单 / 增量更新(我们自建层,引擎能力点到为止)

- 引擎可复用的一手能力:
  - 哈希:`FileAccess.get_sha256(path)` / `get_md5(path)` 与 `HashingContext`(流式哈希大文件)——用于 manifest 里逐包校验完整性。来源:[FileAccess — 4.7](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html)。
  - 存在性/加载:`ResourceLoader`(判断/异步加载),`ProjectSettings.load_resource_pack` 返回 `bool` 成功位(失败无异常,须显式判)。
  - 包级增量:官方 Patching「Export as Patch」只导变更资源(§2),可作为「大版本增量」的一手手段;更细的按需下载靠我们自己的 manifest。
- 约定做法(自建):`manifest.json` = { 目标引擎版本(见 §3 校验)、每个 pack 的 { url, size, sha256, 依赖/挂载顺序 } }。客户端拉 manifest → 比对本地已装版本 → 下缺失/变更包 → 校验 sha256 → 按固定顺序挂载。保持「少而重」:一个内容域一个包,别切太碎。

---

## 9. 分平台判定 & 风险

### Android —— 可行(推荐先落地)
薄壳 APK/AAB + 自建 CDN 下载内容包到 `user://` + autoload `_init()` 尽早 `load_resource_pack` + 新场景/重载/重启换逻辑。UID 与 `class_name` 挂载时自动并入(4.3+ 源码实证)。
- **Top 风险**:
  1. **引擎版本锁死**:包拒收「更新引擎导出的包」,升 Godot 版本须重导全部内容包并在 manifest 校验目标版本(源码 `file_access_pack.cpp @4.7`)。
  2. **运行中不热替换**:必须「先挂包再加载」,已实例化对象不变——KitUpdater = 下载→挂载→重启/重载,而非活体打补丁(`load_resource_pack` Note + exporting_pcks 时机 Note)。
  3. **Play 自更新政策灰区**:GDScript 属解释语言(过 dex/native 禁令),但「远程改写 App 自身行为」与 self-update 条款有张力——定位成"游戏内容"而非"绕过商店更新客户端"(Device and Network Abuse policy)。
  4. **加密 key 耦合**:开 PCK 加密就得自编译模板并全链同 key,否则不加密(compiling_with_script_encryption_key 4.7)。
  5. **UID 碰撞**:靠同路径 `replace_files` 覆盖,别靠 UID 顶替;新增资源保证 UID 唯一(issues #54774/#57220/#102490)。
- **Showstopper**:无绝对技术阻断项;第 3 条是**政策**风险(可能影响上架),需产品侧决策,不是引擎能力缺失。

### Web —— 可行但脆(best-effort,须实测)
路径成立(HTTPRequest→`user://`/IDBFS→`load_resource_pack`),但官方**未记载 Web 分包**、历史有 bug(#58013)、持久化会被浏览器回收、内存/多线程 COOP/COEP 约束叠加。
- **Top 风险**:
  1. **官方文档空白 + 历史 bug**:Web 下 `load_resource_pack` 未被文档背书,#58013 长期挂起——**上线前必须端到端实测 4.7 Web**(issue #58013、proposal #5389)。
  2. **IDBFS 持久化不保证**:下载包可能被回收/需用户允许 IndexedDB——按「随时可能重下」设计(exporting_for_web 4.7)。
  3. **多线程需 COOP/COEP**:走 Use Threads 就得托管方能设两个跨源隔离头(exporting_for_web 4.7);GL Compatibility 单线程可规避,但仍受同源/CORS 约束。
  4. **内存**:整包入 VFS,大包在移动浏览器有 OOM 风险(proposal #5389 推断)。
- **Showstopper**:无硬阻断,但综合脆弱度高——**建议 Web 分包保守化**(核心循环留主包,只切大块非关键内容),把 Web 当次要平台。

---

## 10. 留给设计阶段的开放问题(Open questions)

1. **换逻辑的触发形态**:KitUpdater 采用「下载→挂载→重启进入入口场景」还是「重载当前场景」?两者都不能活体替换正在跑的实例——需定义一个「更新后必须经过的重载屏障」。
2. **引擎版本策略**:manifest 是否强制 `目标引擎版本 == 运行引擎版本`(而非仅"≤")?升 Godot 时的内容包重导与灰度回滚流程怎么定?
3. **加密取舍**:起步是否**明确不加密**(用官方模板、绕开自编译)?若未来要加密,是否接受「自编译导出模板 + 全链同 key」的构建复杂度?
4. **Play 合规边界**:与产品/发行确认「远程下发 GDScript 逻辑」的红线——哪些算「游戏内容」(可下发),哪些算「客户端自更新」(必须走商店)?是否需要给热更范围加白名单(只允许特定目录/特定资源类型进包)?
5. **UID 打包自检**:KitUpdater 的构建脚本是否加「跨包 UID 唯一性 + 目标引擎版本」预检,把 §3/§5 的坑挡在导出期?
6. **Web 是否纳入首版**:鉴于 §7 的脆弱度,Web 分包是 P0 还是延后?若做,先写一个「4.7 Web + `user://` 挂载」最小验证 demo 再决定。
7. **回滚与断点续传**:内容包下载中断/校验失败/挂载 `false` 时的降级(回退到旧包 / 提示重下)——`load_resource_pack` 失败无异常,须显式设计失败路径。

---

### 附:一手来源清单(便于复核)
- ProjectSettings.load_resource_pack:[class 页 4.7](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html) / [`4.7:doc/classes/ProjectSettings.xml`](https://raw.githubusercontent.com/godotengine/godot/4.7/doc/classes/ProjectSettings.xml)
- Exporting packs/patches/mods:[4.7](https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html)
- Exporting projects(CLI/filters/PCK vs ZIP):[4.7](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html)
- 包格式/版本闸门源码:[`4.7:core/io/file_access_pack.h`](https://raw.githubusercontent.com/godotengine/godot/4.7/core/io/file_access_pack.h) / [`4.7:core/io/file_access_pack.cpp`](https://raw.githubusercontent.com/godotengine/godot/4.7/core/io/file_access_pack.cpp)
- 挂载后并入 UID/全局类缓存:[`4.7:core/config/project_settings.cpp`](https://raw.githubusercontent.com/godotengine/godot/4.7/core/config/project_settings.cpp) / [PR #82084](https://github.com/godotengine/godot/pull/82084)
- ResourceUID:[class 4.7](https://docs.godotengine.org/en/stable/classes/class_resourceuid.html) / [`4.7:doc/classes/ResourceUID.xml`](https://raw.githubusercontent.com/godotengine/godot/4.7/doc/classes/ResourceUID.xml) / issues [#54774](https://github.com/godotengine/godot/issues/54774) [#57220](https://github.com/godotengine/godot/issues/57220) [#102490](https://github.com/godotengine/godot/issues/102490)
- 脚本二进制令牌化:[Godot 4.3 release notes](https://godotengine.org/releases/4.3/)
- 脚本/PCK 加密:[Compiling with PCK encryption key 4.7](https://docs.godotengine.org/en/stable/engine_details/development/compiling/compiling_with_script_encryption_key.html)
- 数据路径 user://:[data_paths 4.7](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html)
- Android:[export_for_android 4.7](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html) / OBB 移除 [PR #118283](https://github.com/godotengine/godot/pull/118283) + [godot-obb-plugin](https://github.com/m4gr3d/godot-obb-plugin) / PAD [PR #52526](https://github.com/godotengine/godot/pull/52526) / [Android App Bundle](https://developer.android.com/guide/app-bundle) / [Device and Network Abuse policy](https://support.google.com/googleplay/android-developer/answer/16559646)
- Web:[exporting_for_web 4.7](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html) / [issue #58013](https://github.com/godotengine/godot/issues/58013) / [proposal #5389](https://github.com/godotengine/godot-proposals/issues/5389)
- 哈希/完整性:[FileAccess 4.7](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html)
