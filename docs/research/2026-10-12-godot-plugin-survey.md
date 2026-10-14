# 「Godot 必装插件」16 款逐个调研 & 与 godot-core-kit 的关系

> 日期:2026-10-12
> 起因:一支「Godot 必装插件」视频给出 16 款插件清单,逐个定位到真仓库,核实 license / Godot 4.x(尤其 4.4+、4.7)支持 / 维护状态 / 形态 / 已知限制,并判断与 kit(v0.24.4)的重叠与借鉴价值。
> 证据等级:【据源】仓库 README / plugin.cfg / release / issue / Asset Library API / 官方文档一手可查;【据码】读插件源码确知;【推断】由一手资料外推,未实测;**未确认**=一手资料里查不到。
> 星数、日期为 2026-10-12 通过 GitHub API / Codeberg API / Asset Library API 取得的快照。
> 背景:Godot 4.7 起上线新的 **Asset Store**(store.godotengine.org),多个插件 issue 在讨论「4.7 Asset Store 里没上架」——见 [state-charts#223](https://github.com/derkork/godot-statecharts/issues/223)、[TODO_Manager#62](https://github.com/OrigamiDev-Pete/TODO_Manager/issues/62)、glass-brick 安装说明「Asset Store (or AssetLib, if you're on Godot version 4.6 or earlier)」([wiki](https://github.com/glass-brick/Scene-Manager/wiki/Getting-started))。所以下文「Asset Library 标注版本」只代表旧 AssetLib 的最低版本标签,不等于 4.7 兼容声明。

---

## 0. 总表

| # | 插件 | 仓库 | license | Godot 4 支持 | 最近更新 | 形态 | 与 kit 关系 | 建议 |
|---|---|---|---|---|---|---|---|---|
| 1 | AS2P(AnimatedSprite→AnimationPlayer) | [poohcom1/godot-animated-sprite-2-player](https://github.com/poohcom1/godot-animated-sprite-2-player) | MIT | ✅ 4.x(master 已升 4.4 工程);4.7 有 inspector 布局 bug(有绕法) | 提交 2026-03-31;无 GitHub release,AssetLib v1.4(2023-09) | 纯 GDScript 编辑器插件 | 无关 | 不用 / 有需要的游戏自用;**作者在找接手人** |
| 2 | Importality | [nklbdev/godot-4-importality](https://github.com/nklbdev/godot-4-importality) | MIT | ✅ AssetLib 标 4.1+;4.7 未确认 | release 0.4.0(2026-03-21) | 纯 GDScript 编辑器导入器(部分格式调外部 CLI) | 无关(资产管线,可衔接 asset-bank) | 游戏层按需用 |
| 3 | spine-godot(官方) | [EsotericSoftware/spine-runtimes](https://github.com/EsotericSoftware/spine-runtimes/tree/4.3/spine-godot) | Spine Runtimes License(**非开源,需 Spine 授权**) | ✅ 4.3 分支 CI 构建 4.6.3 / 4.7.2 | 提交 2026-09-25(spine-godot 目录) | **GDExtension 或自定义引擎编译(C++ module)** | 无关 | 不用(除非美术管线定了 Spine);**永不进 kit** |
| 4 | Phantom Camera | [ramokz/phantom-camera](https://github.com/ramokz/phantom-camera) | MIT | ✅ AssetLib 标 4.4;v0.11.0.3 专门修了 4.7.1 问题 | v0.11.0.3(2026-07-19),提交 2026-10-07 | 纯 GDScript 运行时 + 编辑器插件(带 autoload) | 互补(kit 无相机) | 游戏层直接用 |
| 5 | Script-IDE | [Maran23/script-ide](https://github.com/Maran23/script-ide) | MIT | ✅ 开发工程即 4.7,2.2.4 已适配 4.8.dev4 | 2.2.5(2026-09-02) | 纯 GDScript 编辑器插件 | 无关 | 开发者个人可装,不进游戏/kit |
| 6 | Dialogue Manager | [nathanhoad/godot_dialogue_manager](https://github.com/nathanhoad/godot_dialogue_manager) | MIT | ✅ v4 要求 **4.6+**;v3.10 给 4.4/4.5 | v4.1.0(2026-09-04),提交 2026-10-08 | 纯 GDScript 编辑器 + 运行时(可选 C# 包装) | 互补(kit 无对话) | 游戏层直接用 |
| 7 | Scene Manager | 首选 [glass-brick/Scene-Manager](https://github.com/glass-brick/Scene-Manager);候选 [maktoobgar/scene_manager](https://github.com/maktoobgar/scene_manager) | MIT / MIT | glass-brick ✅ AssetLib 4.4、v2.1.0;maktoobgar AssetLib 4.0,4.7 未确认 | glass-brick v2.1.0(2026-08-20);maktoobgar 3.10.0(2024-07-06,已停更两年) | 纯 GDScript 运行时(autoload)+ 编辑器 | **重叠** `CoreKit.scenes` + `KitTransition` | **借鉴纳入**(加载屏/预载、fade_out/fade_in 拆分、遮罩图案转场) |
| 8 | Godot State Charts | [derkork/godot-statecharts](https://github.com/derkork/godot-statecharts) | MIT | ✅ 要求 4.0.3+,4.7 用户在用 | v0.22.5(2026-06-26) | 纯 GDScript 运行时节点 + 编辑器检查(可选 C# 包装) | **重叠** `KitStateMachine` | 复杂行为游戏层直接用;kit 小幅借鉴(延时转移、序列化) |
| 9 | TODO Manager | [OrigamiDev-Pete/TODO_Manager](https://github.com/OrigamiDev-Pete/TODO_Manager) | MIT | ✅ AssetLib 标 4.0;4.7 有用户在用 | v2.7.0(2026-04-03) | 纯 GDScript 编辑器插件 | 无关 | 开发者个人可装 |
| 10 | Sound Manager | [nathanhoad/godot_sound_manager](https://github.com/nathanhoad/godot_sound_manager) | MIT | ✅ main 分支 README 写 **4.6+**;最新 tag 仍是 2024 年的 v2.6.2 | tag v2.6.2(2024-04-18);main 提交 2026-03-29 | 纯 GDScript 运行时(autoload) | **重叠** `CoreKit.audio` | **借鉴纳入**(UI 音效独立通道、环境音层、查询/停止 API);不并装 |
| 11 | gdfxr(Godot Sfxr) | [timothyqiu/gdfxr](https://github.com/timothyqiu/gdfxr) | MIT | ✅ 默认分支 godot-4,AssetLib 标 4.1;4.7 未确认 | 2.1(2024-08-21) | 纯 GDScript 编辑器插件 + 导入器(运行时零生成) | 互补(asset-bank 的 sound_bank) | 游戏层(编辑器)直接用;asset-bank 可加一级 `.sfxr` 接缝 |
| 12 | CSV Data Importer | [timothyqiu/godot-csv-data-importer](https://github.com/timothyqiu/godot-csv-data-importer) | MIT | ✅ AssetLib 标 4.0;4.6 编辑器双击变纯文本(数据可用),**4.7 已修** | tag 2.1(2026-01-03,plugin.cfg 仍写 2.0) | 纯 GDScript 导入器(编辑器期) | 互补 `KitDataRegistry` | 游戏层直接用;kit 补一个吃「记录数组」的入口 |
| 13 | Input Helper | [nathanhoad/godot_input_helper](https://github.com/nathanhoad/godot_input_helper) | MIT | ✅ Godot 4;4.7 未确认 | v4.7.0(2025-06-08) | 纯 GDScript 运行时(autoload) | **重叠** `CoreKit.input` + `KitRebind*` | **借鉴纳入**(分设备绑定槽、手柄品牌识别、冲突互换、震动) |
| 14 | Blender 3D Shortcuts | [imjp94/gd-blender-3d-shortcuts](https://github.com/imjp94/gd-blender-3d-shortcuts) | MIT | ✅ 0.4.0 要求 4.6+;`godot4.5` 分支给 4.0–4.5 | 0.4.0(2026-01-31) | 纯 GDScript 编辑器插件(3D 视口) | 无关(kit 面向 2D) | 不用(做 3D 的开发者个人可装) |
| 15 | GodotSize | [snibk/godotsize](https://github.com/snibk/godotsize)(原 the-sink/godotsize,已重定向) | MIT | ✅ AssetLib 标 4.5,release tag「4.6.stable」;4.7 未确认 | 1.4.0(2026-03-14) | 纯 GDScript 编辑器插件 | 无关(但对微信包体审计有用) | 开发期直接用来查包体 |
| 16 | GodotSteam | [codeberg.org/godotsteam/godotsteam](https://codeberg.org/godotsteam/godotsteam)(GitHub 仓库已 archived) | MIT | ✅ GDExtension 版要求 4.4+;module 版需预编译自定义编辑器 | GDExtension v4.23.1(2026-10-07) | **GDExtension 或自定义引擎编译** | 互补 `KitAchievements.set_steam_sink` | 游戏层直接用(仅桌面 Steam 版);kit 只给 sink 适配示例 |

**一句话分组**:
- **与 kit 重叠、值得借鉴**:7 Scene Manager、10 Sound Manager、13 Input Helper、8 State Charts(小幅)。
- **与 kit 互补、游戏层直接用**:4 Phantom Camera、6 Dialogue Manager、12 CSV Data Importer、16 GodotSteam、11 gdfxr。
- **与 kit 无关的编辑器工具**:1 AS2P、2 Importality、5 Script-IDE、9 TODO Manager、14 Blender 3D Shortcuts、15 GodotSize。
- **原生依赖(GDExtension/自编译引擎)**:3 Spine、16 GodotSteam —— Web/微信小游戏路径不可用(见各节)。其余 14 款均为纯 GDScript(`plugin.cfg` 齐全,仓库树里无 `.gdextension`)【据码:逐仓库 `git/trees` 检索】。

### 平台通用说明(适用于下文各节)

- **纯编辑器插件**(AS2P / Importality / Script-IDE / TODO / Blender / GodotSize / gdfxr 编辑器部分 / CSV 导入器)只在编辑器里运行,导出产物里只剩它们生成的标准资源,对 Web / Android / 微信无运行时影响【推断:由插件形态得出】。
- **纯 GDScript 运行时插件**:无原生依赖,理论上随引擎全平台;但除非下文单独注明,**各仓库都没有对 Web / Android / 微信小游戏做书面声明,本文也未实测**。
- **GDExtension 在 Web**:官方 4.7 文档要求开启「Extensions Support」,且「GDExtensions still need to be specifically compiled for the web platform」,该选项「Like thread support … requires the use of cross-origin isolation headers」([Exporting for the Web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html))。
- **微信小游戏**:本仓库已实测确认走单线程(nothreads)模板,官方口径「不支持多线程(pthread)」([2026-07-27c](2026-07-27c-wechat-official-common-adaptation.md) §线程);社区插件的 GDExtension 只在编辑器侧(`editor.single`),不进包([2026-07-27d](2026-07-27d-godot-wechat-community-plugin-mechanism.md))。→ 依赖 GDExtension 运行时的插件在微信上**不可用**【推断】;用 `ResourceLoader.load_threaded_*` 的插件在 nothreads 下的表现**未确认**(kit 自己是 web 下关线程/同步 load)。

---

## 1. AS2P —— AnimatedSprite to AnimationPlayer Converter

- **仓库 / 作者**:[poohcom1/godot-animated-sprite-2-player](https://github.com/poohcom1/godot-animated-sprite-2-player),作者 poohcom1(plugin.cfg `author="poohcom1"`,目录 `addons/AS2P`);132★。
- **license**:MIT([LICENSE](https://github.com/poohcom1/godot-animated-sprite-2-player/blob/master/LICENSE))。
- **Godot 版本**:分支 `3.x` / `4.0` / `master`;master 最近一次提交「[Godot4.4] Upgrade project to Godot 4.4」(2026-03-31)。AssetLib 两个条目:[#1605](https://godotengine.org/asset-library/asset/1605)(4.0,v1.4,2023-09-03)、[#1216](https://godotengine.org/asset-library/asset/1216)(3.5,v1.1)。**4.7**:[issue #28](https://github.com/poohcom1/godot-animated-sprite-2-player/issues/28)(2026-07-30,open)报告 4.7 下点 AnimationPlayer 时 inspector 被撑大,提出者给了绕法(`drop_down.fit_to_longest_item = false`),未合入。
- **维护状态**:README 顶部「⚠️ Not actively maintained / Looking for maintainers」([#21](https://github.com/poohcom1/godot-animated-sprite-2-player/issues/21));无 GitHub release,plugin.cfg `version=""`;最后提交 2026-03-31(修 #26)。
- **形态**:纯 GDScript 编辑器插件。
- **核心功能**【据源 README】:
  - 在 AnimationPlayer 的 inspector 增加一个槽位,下拉选一个 AnimatedSprite;
  - 一键把 SpriteFrames 的各动画转成 AnimationPlayer 动画轨;
  - 对已有动画只更新必要的轨道。
- **已知限制**:无人维护;4.7 inspector 布局问题;纯编辑器期工具,导出后无影响。
- **与 kit**:无关。kit 不管 2D 动画编排。→ **不用**(需要「帧动画 + 同轨触发音效/碰撞盒」的游戏可自装)。

## 2. Importality

- **仓库 / 作者**:[nklbdev/godot-4-importality](https://github.com/nklbdev/godot-4-importality),Nikolay Lebedev(nklbdev);541★。
- **license**:MIT。
- **Godot 版本**:AssetLib [#2025](https://godotengine.org/asset-library/asset/2025) 标 4.1、v0.4.0;4.7 未确认。
- **维护状态**:[release 0.4.0](https://github.com/nklbdev/godot-4-importality/releases/tag/0.4.0)(2026-03-21,社区 PR 合集:Pixelorama v3 格式、显式数组转型等);上一版 0.3.0 是 2023-10。注意仓库内 `plugin.cfg` 仍写 `version="0.3.0"`。[#51](https://github.com/nklbdev/godot-4-importality/issues/51)「Most Krita file importers seem to be completely broken」(2026-03 已关闭)。
- **形态**:纯 GDScript 编辑器导入器;Aseprite / Krita / Pencil2D 依赖调用**本机外部程序 CLI**导出数据,Piskel / Pixelorama 用自带解析器【据源 README「How to use」】。
- **核心功能**【据源 README】:
  - 把 Aseprite(及 LibreSprite)、Krita、Pencil2D、Piskel、Pixelorama 源文件直接当图片识别;
  - 导入为:精灵图集、`SpriteFrames`、或现成场景(`AnimatedSprite2D/3D`,或由 `AnimationPlayer` 驱动的 `Sprite2D/3D`/`TextureRect`);
  - 网格 / 紧凑两种图集布局,多种避免边缘伪影的方式;
  - 源文件改了 Godot 自动重新导入;可借外部 CLI 导入任意其它格式。
- **已知限制**:需在 Editor Settings 配临时目录与外部程序命令;Krita 集成 README 标「Critical!」;CI/无头导入要求机器上装对应美术软件【推断】。
- **与 kit**:无关(资产管线)。可与 asset-bank 的 drop-in 接缝衔接(美术把 .aseprite 丢进去 → 导入成 SpriteFrames)。→ **游戏层按需用**。

## 3. spine-godot(Esoteric Software 官方)

- **仓库 / 作者**:[EsotericSoftware/spine-runtimes](https://github.com/EsotericSoftware/spine-runtimes)(默认分支 `4.3`)下的 [`spine-godot/`](https://github.com/EsotericSoftware/spine-runtimes/tree/4.3/spine-godot);文档 [esotericsoftware.com/spine-godot](https://esotericsoftware.com/spine-godot)。
- **license**:Spine Runtimes License(GitHub 识别为 NOASSERTION)。README 原文:可免费评估;集成后若要分发给**没有 Spine 授权的人**,集成时须持有 [Spine license](https://esotericsoftware.com/spine-purchase);正式条款见 [Spine Runtimes License Agreement](http://esotericsoftware.com/spine-runtimes-license)。→ **不是开源许可,商用需买 Spine 编辑器授权**。
- **Godot 版本**:spine-godot README 里写「Godot 3.5.x and 4.0.x」是旧句未更新;实际以 CI 为准——4.3 分支 [`spine-godot-extension-v4-all.yml`](https://github.com/EsotericSoftware/spine-runtimes/blob/4.3/.github/workflows/spine-godot-extension-v4-all.yml) 构建 **4.6.3-stable 与 4.7.2-stable** 的 GDExtension,`spine-godot-v4-all.yml` 构建同版本的 module 编辑器(含 mono)。数据须由 **Spine 4.3.xx** 导出(README「Spine version」)。tint black 要求 Godot 4.3+。
- **维护状态**:活跃,spine-godot 目录最近提交 2026-09-25(此前 2026-09-11 加 SpineSprite3D 光照/阴影)。无 GitHub release,按分支 + CI 产物分发。
- **形态**:两种——① **GDExtension**(丢进 `bin/`);② **C++ module**,需用他们的**自定义编辑器 + 自定义导出模板**,或自己编译【据源 文档】。
- **核心功能**【据源 文档/README】:
  - 加载、操作、渲染 Spine 骨骼动画(`SpineSprite`、实验性 `SpineSprite3D`);
  - 除 screen 混合模式外支持全部 Spine 2D 特性;Spine 4.3 起支持 tint black;
  - AnimationPlayer 轨道集成(`SpineAnimationTrack`);
  - C# 绑定仅 module 版有。
- **已知限制**:
  - 文档:module 版可导出 Windows/Linux/macOS/iOS/Android/Web;GDExtension 构建目标含 `web`、`android`。
  - GDExtension「does not have dedicated C# bindings and is missing a minor editor feature」;C# 版仅桌面。
  - 不支持预乘 alpha 图集;JSON 必须用 `.spine-json` 扩展名。
  - **Web**:GDExtension 需开 Extensions Support + 跨域隔离头(见平台通用说明);module 版需自建 Web 模板。**微信小游戏:不可用**【推断:单线程模板 + 无法加载 GDExtension;module 版需自己编出能跑在微信适配层上的模板,未见任何先例】。
- **与 kit**:无关;且 kit 「纯 GDScript、零原生依赖」原则下**永不纳入**。→ **不用**(除非美术管线已定 Spine 并接受授权与平台代价)。

## 4. Phantom Camera

- **仓库 / 作者**:[ramokz/phantom-camera](https://github.com/ramokz/phantom-camera),Marcus Skov(ramokz);3598★;文档 [phantom-camera.dev](https://phantom-camera.dev)。
- **license**:MIT。
- **Godot 版本**:AssetLib [#1822](https://godotengine.org/asset-library/asset/1822) 标 4.4。**4.7**:[v0.11.0.3](https://github.com/ramokz/phantom-camera/releases/tag/v0.11.0.3) 修了「Godot 4.7.1 引入的 `PhantomCameraManager` autoload 未反注册」;release note 注明 `Node not found: "PhantomCameraManager"` 报错仍待 Godot 侧 [PR #121509](https://github.com/godotengine/godot/pull/121509) 合并。[#677](https://github.com/ramokz/phantom-camera/issues/677)「Group Camera forgetting Look At Targets in 4.7」已修;[#651](https://github.com/ramokz/phantom-camera/issues/651)「not working on godot 4.6.3-mono」open。
- **维护状态**:活跃,最新 release v0.11.0.3(2026-07-19),main 提交 2026-10-07。仍是 0.x。
- **形态**:纯 GDScript;运行时节点(`PhantomCamera2D/3D`、`PhantomCameraHost`、噪声发射器)+ 编辑器面板/gizmo + 一个 autoload `PhantomCameraManager`【据码:`addons/phantom_camera/scripts/` 目录】。
- **核心功能**【据源 README】:
  - 受 Unity Cinemachine 启发,驱动内置 `Camera2D/3D`;
  - **优先级**切换:更高 priority 的 PCam 激活时主相机平滑过渡过去;
  - 跟随模式:Glued / Simple(偏移+阻尼)/ Group(多目标取中心、自动缩放取景)/ Path(约束在路径上)/ Framed(死区)/ Third Person(3D);
  - Look At(3D);可配置切换 Tween(时长/曲线);
  - 噪声/震屏(`PhantomCameraNoise2D/3D` + Noise Emitter)。
- **已知限制**:0.x API 仍在变;4.7 下 autoload 相关报错依赖引擎 PR;Web/Android 无书面声明(纯 GDScript,推断可用)。
- **与 kit**:互补,kit 没有相机子系统。→ **游戏层直接用**,不要自建。kit 唯一可能的交集是「转场时相机」——`CoreKit.scenes` 不碰相机,不冲突。

## 5. Script-IDE

- **仓库 / 作者**:[Maran23/script-ide](https://github.com/Maran23/script-ide),Marius Hanl(Maran23);1057★。
- **license**:MIT。
- **Godot 版本**:AssetLib [#2206](https://godotengine.org/asset-library/asset/2206) 标 4.5;README「Contributing」给的工程 `config/features=PackedStringArray("4.7")`;2.2.4 release「Support Godot 4.8.dev4」;已上 [4.7 Asset Store](https://store.godotengine.org/asset/maran23/script-ide/)。→ **4.7 支持**。
- **维护状态**:活跃,2.2.5(2026-09-02)。
- **形态**:纯 GDScript 编辑器插件(改造内置脚本编辑器 UI)。
- **核心功能**【据源 README】:
  - 脚本以多行 Tab 显示,可拆分只读副本并排看;
  - 大纲(Outline)列出类/常量/信号/export 变量/变量/引擎回调/函数/setter/getter,各有图标与过滤;
  - `Shift+Shift` 快速搜文件,`Alt+Ins` 覆写父类方法;
  - 大纲/脚本弹窗快捷键、隐藏私有成员等配置。
- **已知限制**:README 自述依赖引擎 `script_editor_plugin.cpp` 的布局结构,「each version can introduce changes in the layout」,遇到意外会 fail fast 不做修改。
- **与 kit**:无关(编辑器体验)。→ 开发者个人可装,不进游戏、不进 kit。

## 6. Dialogue Manager(nathanhoad)

- **仓库 / 作者**:[nathanhoad/godot_dialogue_manager](https://github.com/nathanhoad/godot_dialogue_manager),Nathan Hoad;3908★。
- **license**:MIT。
- **Godot 版本**:README 标题「Dialogue Manager 4 _for Godot 4.6+_」;旧版:[v3.10](https://github.com/nathanhoad/godot_dialogue_manager/tree/v3.x) 给 4.4/4.5,v3.3 给 4.3,v2.x 给 ≤4.3,v1.x 给 Godot 3。AssetLib 上最新条目是「Dialogue Manager 3」([#3654](https://godotengine.org/asset-library/asset/3654),v3.10.4),v4 走新 Asset Store / GitHub【据源】。
- **维护状态**:很活跃,[v4.1.0](https://github.com/nathanhoad/godot_dialogue_manager/releases/tag/v4.1.0)(2026-09-04),main 提交 2026-10-08。
- **形态**:纯 GDScript 编辑器(对话脚本编辑器)+ 运行时;另有 C# 包装([docs/CSharp.md](https://github.com/nathanhoad/godot_dialogue_manager/blob/main/docs/CSharp.md))。
- **核心功能**【据源 README / docs 目录】:
  - 无状态的分支对话编辑器与运行时,以类剧本语法写 `.dialogue`;
  - 条件与变更(Conditions & Mutations)直接调用游戏状态;
  - 可定制的对话气泡(balloons);
  - 翻译支持(docs/Translations.md);
  - 文档 + 示例工程齐全,v3→v4 有升级指南。
- **已知限制**:v4 硬性 4.6+;Web/Android/微信无书面声明(纯 GDScript,推断可用)。
- **与 kit**:互补,kit 没有对话系统。可接点:对话里的 mutation 调 `CoreKit.bus.emit`、翻译走与 `CoreKit.i18n` 同一套 TranslationServer。→ **游戏层直接用**。

## 7. Scene Manager(多个同名)

同名候选(AssetLib 搜「Scene Manager」):

| 候选 | 仓库 | AssetLib | 最近 | 备注 |
|---|---|---|---|---|
| **glass-brick Scene Manager** ⭐ | [glass-brick/Scene-Manager](https://github.com/glass-brick/Scene-Manager) | [#1303](https://godotengine.org/asset-library/asset/1303) 4.4,v2.1.0 | release v2.1.0 2026-08-20 | 653★,v2 新增后台加载 + GUT 测试 + CI |
| maktoobgar Scene Manager Tool | [maktoobgar/scene_manager](https://github.com/maktoobgar/scene_manager) | [#1582](https://godotengine.org/asset-library/asset/1582) 4.0,v3.10.0 | 2024-07-06 | 431★,两年无提交 |
| 其它 | Mid or Feed「Godot Scene Manager」#4346、symbol24 #3287、mcanton #3110 等 | — | — | 体量小 |

按星数 maktoobgar 曾是最常被推荐的 Godot 4 版,但**它已停更两年**;仍在维护且已适配 4.4+/Asset Store 的是 glass-brick。下文两者都列。

- **license**:glass-brick 的 `addons/scene_manager/LICENSE` 为 MIT(仓库根无 LICENSE,GitHub 识别为 null),AssetLib 标 MIT;maktoobgar MIT。
- **形态**:都是纯 GDScript autoload 运行时 + 编辑器部分(maktoobgar 有场景登记表编辑器面板)。
- **glass-brick 核心功能**【据源 [wiki Features](https://github.com/glass-brick/Scene-Manager/wiki/Features) / [API Reference](https://github.com/glass-brick/Scene-Manager/wiki/API-Reference) / [v2.0.0](https://github.com/glass-brick/Scene-Manager/releases/tag/v2.0.0)、[v2.1.0](https://github.com/glass-brick/Scene-Manager/releases/tag/v2.1.0)】:
  - `change_scene` / `reload_scene`,自带 shader 淡变,**遮罩图案**(如 `"pattern": "squares"`)+ 反相 + ease;
  - **默认后台加载**:淡出时在 worker 线程加载新场景;`loading_screen: true` 用内置进度条或自定义场景(只需实现 `set_progress(value)`),`min_loading_time`;
  - `preload_scene` / `is_scene_ready` / `get_load_progress` / `drop_preloaded_scene`;
  - **拆分 `fade_out` / `fade_in`**:黑屏期间做自己的事(挪玩家、存档);
  - 回调 `on_tree_enter` / `on_ready` / `on_fade_out` / `on_fade_in`;可接自定义 AnimationPlayer 转场;项目设置默认值;一组 `background_load_*` 信号。
- **maktoobgar 核心功能**【据源 [README](https://github.com/maktoobgar/scene_manager#features)】:场景**按 key 登记**(编辑器面板分类/忽略目录/重复 key 检查,存 scenes.db)、**返回上一场景栈**(`back` + 深度上限 + reset)、图案淡入淡出(`shader_patterns/*.png`)、交互式加载(`load_percent_changed`/`load_finished`)、暂停/恢复。
- **已知限制**:两者都直接用 `ResourceLoader.load_threaded_request`,**没有 web 分支**【据码:glass-brick `SceneManager.gd:245`、maktoobgar `scene_manager.gd:363/469`】;nothreads Web / 微信下的行为**未确认**。kit 的 `CoreKit.scenes` 刻意「同步 load()(不用线程,Web 导出安全)」【据码 `systems/scene_manager.gd:8`】。
- **与 kit:重叠**(`CoreKit.scenes` + `KitTransition` FADE/SLIDE)。插件有、kit 没有的:
  1. **加载屏 + 进度 + 预载**(kit 只有同步 load,大场景会卡在遮罩上);
  2. **`fade_out` / `fade_in` 拆分**的「黑屏窗口」API(kit `change_scene` 一口气走完);
  3. **遮罩图案转场**(shader + 灰度图;kit 只有 FADE/SLIDE);
  4. 转场节点回调 `on_tree_enter` / `on_ready`(kit 有 `scene_changing/changed` 信号,无「新场景入树但未 ready」时机);
  5. `reload_scene`、场景返回栈(maktoobgar)。
- **建议**:**借鉴纳入**,不并装(会与 `CoreKit.scenes` 抢 `change_scene_to_*`)。实现时预载走现有 `CoreKit.res`(已是 web 安全的分帧加载)而不是线程。

## 8. Godot State Charts(derkork)

- **仓库 / 作者**:[derkork/godot-statecharts](https://github.com/derkork/godot-statecharts),Jan Thomä & Contributors;1619★;[手册](https://derkork.github.io/godot-statecharts/)。
- **license**:MIT。
- **Godot 版本**:安装文档「This plugin requires Godot 4.0.3 or later」,不支持 3.x([01_installation.md](https://github.com/derkork/godot-statecharts/blob/main/docs/_docs/01_installation.md));AssetLib [#1778](https://godotengine.org/asset-library/asset/1778)。4.7:[#223](https://github.com/derkork/godot-statecharts/issues/223) 用户在 4.7 下找 Asset Store 条目,作者答已提交审核。
- **维护状态**:活跃,[v0.22.5](https://github.com/derkork/godot-statecharts/releases/tag/v0.22.5)(2026-06-26)。
- **形态**:纯 GDScript 运行时节点 + 编辑器内检查/警告 + 运行时调试视图;提供 C# 包装【据源 FAQ】。
- **核心功能**【据源 README + `addons/godot_state_charts/*.gd` 文件清单】:
  - 状态图(statecharts):`CompoundState`(层级)/ `ParallelState`(并行)/ `AtomicState` / `HistoryState`(历史);
  - 声明式 `Transition` + **守卫**(`ExpressionGuard`、`AllOf/AnyOf/Not`、`StateIsActiveGuard`);
  - **延时转移**(做冷却),非激活状态不逐帧更新,遵守暂停;
  - 内置游戏内**调试视图**、stepping 模式;
  - `AnimationPlayerState` / `AnimationTreeState`;
  - `StateChartSerializer` 存读档,产出 `SerializedStateChart` 资源([07_saving_and_loading.md](https://github.com/derkork/godot-statecharts/blob/main/docs/_docs/usage/07_saving_and_loading.md))。
- **已知限制**:状态逻辑以节点 + 信号连线为主,纯代码驱动的场景偏重;Web/Android 无书面声明(纯 GDScript,推断可用)。
- **与 kit:重叠**(`KitStateMachine`:name-based 转移、事件转移表 + `ANYSTATE` 通配、pushdown 栈、`MAX_CHAIN` 死循环守卫)。插件有、kit 没有的:
  1. 层级(compound)与**并行**状态;
  2. **历史状态**(kit 的 pushdown 只覆盖「暂停-恢复」单一路径);
  3. **延时转移**(N 秒后自动转);
  4. 表达式/组合守卫;
  5. **存读档序列化**;
  6. 运行时调试视图。
- **建议**:复杂 AI / 角色行为的游戏**直接用**它;kit 保持轻量 FSM 定位,只**小幅借鉴**延时转移与 `to_dict/from_dict`(对齐 kit 其它类库的存档约定)。并行/层级不进 kit(那是另一个量级的东西)。

## 9. TODO Manager

- **仓库 / 作者**:[OrigamiDev-Pete/TODO_Manager](https://github.com/OrigamiDev-Pete/TODO_Manager),Peter de Vroom;515★。
- **license**:MIT。
- **Godot 版本**:AssetLib [#1327](https://godotengine.org/asset-library/asset/1327)「TODO Manager (Godot 4)」标 4.0;Godot 3 另有 [#768](https://godotengine.org/asset-library/asset/768)。4.7:[#62](https://github.com/OrigamiDev-Pete/TODO_Manager/issues/62) 用户在 4.7 下使用,请求上架 Asset Store。
- **维护状态**:[v2.7.0](https://github.com/OrigamiDev-Pete/TODO_Manager/releases/tag/v2.7.0)(2026-04-03,最后提交「Use execute_with_pipe」)。open:[#63](https://github.com/OrigamiDev-Pete/TODO_Manager/issues/63)「Ignore Paths not working」。
- **形态**:纯 GDScript 编辑器 dock 插件。
- **核心功能**【据源 README】:扫描 GDScript / C# / GDNative 里的 TODO;集成进 dock;宽松语法;点击跳行或调外部编辑器;自定义正则与颜色。
- **已知限制**:README 要求不得改 `addons/Todo_Manager` 目录名(否则设置读写失效)。
- **与 kit**:无关。→ 开发者个人可装。

## 10. Sound Manager(nathanhoad)

- **仓库 / 作者**:[nathanhoad/godot_sound_manager](https://github.com/nathanhoad/godot_sound_manager),Nathan Hoad;829★。
- **license**:MIT。
- **Godot 版本**:main 分支 README「Sound Manager _for Godot 4.6+_」;但**最新 tag 仍是 [v2.6.2](https://github.com/nathanhoad/godot_sound_manager/releases/tag/v2.6.2)(2024-04-18)**,AssetLib [#2048](https://godotengine.org/asset-library/asset/2048) 停在 v2.6.1(4.0)。→ 「4.6+」的 main 代码尚无对应 release;用 AssetLib 版拿到的是 2024 年代码【据源】。
- **维护状态**:低频,main 最后提交 2026-03-29(「Ensure prepared players are marked as busy」)。
- **形态**:纯 GDScript autoload 运行时(含 C# 包装)。
- **核心功能**【据源 README / docs】:
  - 音频播放器**池化**;音乐**交叉淡切**;
  - 自动探测可能的音效/音乐总线;
  - **音效分 UI 音效与普通音效两路**,默认游戏暂停时普通音效暂停、UI 音效不暂停(`sound_process_mode` / `ui_sound_process_mode`,[Sounds.md](https://github.com/nathanhoad/godot_sound_manager/blob/main/docs/Sounds.md));
  - **环境音层**:`play_ambient_sound(stream, fade_in)` / `stop_ambient_sound` / `stop_all_ambient_sounds`([AmbientSounds.md](https://github.com/nathanhoad/godot_sound_manager/blob/main/docs/AmbientSounds.md));
  - 音乐:`play_music_from_position`、`play_music_at_volume`、曲目历史 `get_music_track_history`、`is_music_playing`、`get_currently_playing_music`([Music.md](https://github.com/nathanhoad/godot_sound_manager/blob/main/docs/Music.md));
  - `play_sound*` 返回 `AudioStreamPlayer`,`stop_sound(stream)` 按资源停。
- **已知限制**:release 滞后;Web 首次播放需用户手势是浏览器/微信通用约束(kit 已有记录),插件未专门处理【推断】。
- **与 kit:重叠**(`CoreKit.audio`:总线音量 + 持久化、BGM 交叉淡切、SFX 轮转池、pitch)。插件有、kit 没有的:
  1. **UI 音效独立通道 + 暂停豁免**(kit 只有一个 SFX 池,process_mode 未区分【据码:`audio_manager.gd` 无 process_mode 设置】);
  2. **环境音层**(多条循环音,各自淡入淡出);
  3. `stop_sfx(stream)`、`is_music_playing()`、从指定位置播放、`play_sfx` 返回 player;
  4. 曲目历史(切回上一首 BGM)。
- **建议**:**借鉴纳入**,不要并装(两个 autoload 抢总线和音量设置)。

## 11. gdfxr(Godot Sfxr)

视频里的「Godot Sfxr」有两个同类:**timothyqiu/gdfxr**(AssetLib [#1676](https://godotengine.org/asset-library/asset/1676),4.1,v2.1)与 tomeyro「GodotSfxr (for Godot 4.x)」(AssetLib [#2139](https://godotengine.org/asset-library/asset/2139),2023-09 后无更新)。下文以星数与维护更好的 gdfxr 为准。

- **仓库 / 作者**:[timothyqiu/gdfxr](https://github.com/timothyqiu/gdfxr),Haoyu Qiu(timothyqiu);195★。
- **license**:MIT。
- **Godot 版本**:默认分支 `godot-4`(Godot 3 用 `godot-3` 分支);AssetLib 标 4.1;4.7 未确认。
- **维护状态**:**停滞**,2.1(tag,2024-08-21)后无提交;无 GitHub release。
- **形态**:纯 GDScript 编辑器底部面板 + `.sfxr` 导入器。
- **核心功能**【据源 README】:
  - 移植 DrPetter 的 sfxr:7 类生成按钮 + 变异 + 全随机,右侧参数微调;
  - 存为 `.sfxr`(只存参数,约 100 字节),**可直接当 `AudioStream` 用**;
  - 与原版 sfxr 文件互通;
  - Loop / 位深 / 采样率作为导入选项。
- **已知限制**:README:GDScript 性能所限,编辑器内生成长音效会卡顿;「Using `.sfxr` files in-game won't generate anything at runtime」——即导入期就烘焙,**运行时零开销,对 Web/微信无额外风险**【推断】。
- **与 kit**:互补。kit 本体无音效生成;项目级 skill `asset-bank` 的 `sound_bank.gd` 模板做程序化合成兜底 + drop-in 真音频(`.claude/skills/asset-bank/templates/sound_bank.gd`)。gdfxr 的 `.sfxr` 是「可再编辑的程序化音效源文件」,正好可做 asset-bank 的一级接缝(丢 `.sfxr` 即被当 AudioStream 用)。→ **游戏层(编辑器)直接用**;asset-bank skill 可补一句「`.sfxr` 也是合法 drop-in」。不进 kit。

## 12. CSV Data Importer

- **仓库 / 作者**:[timothyqiu/godot-csv-data-importer](https://github.com/timothyqiu/godot-csv-data-importer),Haoyu Qiu;127★。
- **license**:MIT。
- **Godot 版本**:AssetLib [#1793](https://godotengine.org/asset-library/asset/1793) 标 4.0、v2.0(2023-04)。**4.6**:[#11](https://github.com/timothyqiu/godot-csv-data-importer/issues/11) 报告 4.6 编辑器把 `.csv` 强制当翻译/纯文本打开(双击看不到资源),作者说明「Loading the imported CSV still works」,上游 [godot#115945](https://github.com/godotengine/godot/issues/115945),后续评论「Fixed in Godot 4.7」。
- **维护状态**:低频;tag 2.1 指向 2026-01-03 提交(新增分号分隔符),但 `plugin.cfg` 仍 `version="2.0"`,无 GitHub release。
- **形态**:纯 GDScript **导入器**(编辑器期把 CSV/TSV 转成自定义 Resource;运行时只是读资源)。
- **核心功能**【据源 README】:
  - Import 面板选「CSV Data」,产出带 `records` 数组的 Resource,可 `preload("res://x.csv").records`;
  - 分隔符 逗号/Tab/分号;
  - Headers:首行做键,每行变 `Dictionary`;
  - 自动识别数字(可强制 float)、布尔。
- **已知限制**:4.6 编辑器体验问题(4.7 修);只出 Array/Dictionary,无 schema/类型校验。
- **与 kit**:互补 `KitDataRegistry`(type→{id→def},`register` / `load_dir` 扫 `.tres`)。kit 缺的是「表格 → 定义」的批量入口。→ **游戏层直接用**导入器;kit 侧借鉴一个很小的入口:`KitDataRegistry.register_records(type, records, id_key)` 吃「字典数组」,这样 CSV 导入器 / JSON / 远端配置都能喂进来。

## 13. Input Helper(nathanhoad)

- **仓库 / 作者**:[nathanhoad/godot_input_helper](https://github.com/nathanhoad/godot_input_helper),Nathan Hoad;1107★。
- **license**:MIT。
- **Godot 版本**:README「for Godot 4」(Godot 3 用 v2.x);AssetLib [#2107](https://godotengine.org/asset-library/asset/2107) 标 4.0、v4.7.0;4.7 未确认。
- **维护状态**:[v4.7.0](https://github.com/nathanhoad/godot_input_helper/releases/tag/v4.7.0)(2025-06-08)后无提交,超过一年。
- **形态**:纯 GDScript autoload 运行时(含 C# 包装)。
- **核心功能**【据源 README / [Devices.md](https://github.com/nathanhoad/godot_input_helper/blob/main/docs/Devices.md) / [Mapping.md](https://github.com/nathanhoad/godot_input_helper/blob/main/docs/Mapping.md)】:
  - `device_changed(device, device_index)`,**区分手柄品牌**(`DEVICE_XBOX_CONTROLLER` 等,可开「granular device identifiers」),`guess_device_name()` 在无输入前猜测,`last_known_joypad_device`;
  - **键鼠与手柄分开的绑定槽**:`get/set_keyboard_input_for_action`、`get/set_joypad_input_for_action`、`replace_*_at_index`;
  - **`swap_if_taken`**:冲突时自动与被占用的动作互换,并对两边各发 `*_input_changed`;
  - `serialize_inputs_for_actions` / `deserialize_inputs_for_actions` 存读;`reset_all_actions`;
  - 手柄**震动**([Rumbling.md](https://github.com/nathanhoad/godot_input_helper/blob/main/docs/Rumbling.md))。
- **已知限制**:文档自述 Windows 蓝牙 Joy-Con 不发输入事件;无输入缓冲(jump buffer)。
- **与 kit:重叠**(`CoreKit.input`:重绑定 + 持久化、`device_changed`(KEYBOARD_MOUSE/GAMEPAD/TOUCH)、输入缓冲;`KitRebindButton/List`:捕获 + 冲突拦截)。插件有、kit 没有的:
  1. **分设备绑定槽**——kit 的 `rebind_action` 是「整体替换 action 绑定为单个 event」【据源 `docs/systems/input-manager.md`】,玩家改键盘键会**顺带删掉手柄绑定**,这是 kit 的真实缺口;
  2. **手柄品牌识别**(UI 换 Xbox/PS/Switch 图标需要);
  3. 冲突时**互换**选项(kit 只拦截);
  4. 震动封装;
  5. 每动作多个绑定(index 寻址)。
  反过来,kit 有它没有的:TOUCH 设备类型、输入缓冲、重绑 UI 组件。
- **建议**:**借鉴纳入**(优先级最高的一项,见 §对 kit 的结论)。不并装(两套都改 InputMap 并各自持久化,会互相覆盖)。

## 14. Blender 3D Shortcuts

- **仓库 / 作者**:[imjp94/gd-blender-3d-shortcuts](https://github.com/imjp94/gd-blender-3d-shortcuts),imjp94;181★。
- **license**:MIT。
- **Godot 版本**:README「This version is only compatible with **Godot 4.6 and onwards**」,4.0–4.5 用 [`godot4.5`](https://github.com/imjp94/gd-blender-3d-shortcuts/tree/godot4.5) 分支,Godot 3 用 `godot3` 分支;AssetLib [#1106](https://godotengine.org/asset-library/asset/1106) 停在 v0.3.2(4.0)。4.7 未确认(0.4.0 面向 4.6+)。
- **维护状态**:[0.4.0](https://github.com/imjp94/gd-blender-3d-shortcuts/releases/tag/0.4.0)(2026-01-31,「Port to Godot 4.6」)。
- **形态**:纯 GDScript 编辑器插件(3D 视口)。
- **核心功能**【据源 README】:G/R/S 平移旋转缩放、H 隐藏;Alt 撤销变换;X/Y/Z 轴约束、Shift+轴 平面约束;键入数值;Z 切换显示模式;与 Godot 本地空间/吸附设置协同。
- **已知限制**:README 建议清掉 Spatial Editor 的 Scale Mode 快捷键(与旋转冲突);目录名 README 写 `addons/blender_3d_shortcuts`、仓库实际为 `addons/gd-blender-3d-shortcuts`【据码】。
- **与 kit**:无关(kit 面向 2D)。→ **不用**。

## 15. GodotSize

- **仓库 / 作者**:[snibk/godotsize](https://github.com/snibk/godotsize)(AssetLib 链接 [the-sink/godotsize](https://github.com/the-sink/godotsize) 已重定向到此),plugin.cfg `author="the-sink"`;65★。
- **license**:MIT。
- **Godot 版本**:AssetLib [#1476](https://godotengine.org/asset-library/asset/1476) 标 4.5、v1.4.0;release tag 命名为引擎版本(`4.6.stable` 2026-03-14、`4.4.stable` 2025-05-12)。4.7 未确认。
- **维护状态**:1.4.0(2026-03-14)。
- **形态**:纯 GDScript 编辑器工具(Project > Tools > Show Size Map...)。
- **核心功能**【据源 README】:按大小排序列出项目文件;可切换为扫描**导入后数据**大小(例:`icon.svg` 3.42 KB,改 VRAM Uncompressed 后 65.59 KB),用于找出导出后会变大的资源。
- **已知限制**:只看单文件大小,不是导出包分析。
- **与 kit**:无关,但对 kit 的微信路线有用——微信首包/分包体积是硬约束([2026-07-27c](2026-07-27c-wechat-official-common-adaptation.md))。→ **开发期直接用**来审计包体;kit 不纳入(`tools/export-pipeline` 已在 manifest 里记 size,足够)。

## 16. GodotSteam

- **仓库 / 作者**:主仓库已迁到 [Codeberg godotsteam/godotsteam](https://codeberg.org/godotsteam/godotsteam)(默认分支 `godot4`);[GitHub GodotSteam/GodotSteam](https://github.com/GodotSteam/GodotSteam) 已 **archived**。作者 GP Garcia(Gramps)、Chris Ridenour 及贡献者;文档 [godotsteam.com](https://godotsteam.com)。
- **license**:MIT([license.md](https://codeberg.org/godotsteam/godotsteam/src/branch/godot4/license.md));Steamworks SDK 本身受 Valve 条款约束(未展开)。
- **Godot 版本**:Codeberg [releases](https://codeberg.org/godotsteam/godotsteam/releases):`v4.23.1`「Godot 4.4+ - Steamworks 1.65 - GodotSteam GDExtension 4.23.1」(2026-10-07);`v4.23`「Godot 4.x - … GodotSteam 4.23」(module 版,2026-10-05)。AssetLib:GDExtension 4.4+ [#2445](https://godotengine.org/asset-library/asset/2445)(4.23.1);4.1–4.3 的 GDExtension 条目已标 Deprecated。4.7 未在 release 名里单独声明(「4.4+」)。
- **维护状态**:很活跃(Codeberg 提交 2026-10-08)。Steamworks 1.65 对应 GodotSteam 4.21+(README 兼容表)。
- **形态**:**GDExtension 插件**(`gdextension` 分支 / `gdextension-plugin`)或**引擎 module**(需用其预编译编辑器与模板,或自编译);另有 Server 版、MultiplayerPeer。
- **核心功能**【据源 readme / 文档】:Steamworks API 绑定(成就/统计/排行榜/云存档/创意工坊/大厅/P2P 联网等);`SteamMultiplayerPeer`;配套 Skillet 示例、GodotSteamKit。
- **已知限制**【据源 readme「Known Issues」】:仓库描述「For Linux, Mac, and Windows」——**无 Web/Android/iOS/微信**;编辑器内运行时 Steam Overlay 可能不工作;Steam 版 Godot 的 `steam_api64.dll` 可能过旧需手动替换。
- **与 kit**:互补 `KitAchievements.set_steam_sink(Callable)`——kit 已预留「新解锁时 `sink.call(id)` 一次」的平台抽象层。接法:桌面 Steam 版在启动时 `achievements.set_steam_sink(func(id): Steam.setAchievement(String(id)); Steam.storeStats())`(API 名以 godotsteam.com 文档为准)。→ **游戏层直接用**(仅桌面 Steam 构建);kit **不纳入**(原生依赖、平台单一),最多在 `kit-achievements.md` 加一段适配示例。

---

## 17. 对 kit 的结论

### 17.1 不该做的

- **不并装**与门面子系统同职责的插件(Scene Manager / Sound Manager / Input Helper):它们各自是 autoload,会与 `CoreKit.scenes` / `audio` / `input` 抢 `change_scene`、总线音量、InputMap 持久化。借设计,不借代码。
- **不纳入原生依赖**(Spine、GodotSteam):违背「纯 GDScript、Web/微信可跑」的 kit 底线。
- **不自建**相机(Phantom Camera)、对话(Dialogue Manager)、层级/并行状态图(State Charts):成熟、活跃、MIT,游戏层直接用即可。这和 2026-07-10 调研对 ECS/行为树「不自建、文档指路」的结论一致。

### 17.2 值得借鉴补进 kit 的具体点(按优先级)

**P1 —— `CoreKit.input` 分设备绑定槽**(来源:Input Helper)
现状 `rebind_action(action, event)` 整体替换为单事件,改键盘会丢手柄绑定。改为按设备类别替换:只换同类事件(键鼠类 / 手柄类),其余保留;`get_action_event` 增设备参数;`KitRebindButton` 按设备捕获。顺带:冲突处理加「互换」可选策略(`swap_if_taken` 思路),与现有「拦截」并存。持久化格式需迁移(可走 `SaveManager` 同款版本号思路,或 settings 段内加版本字段)。

**P2 —— `CoreKit.scenes` 加载屏 / 预载 + 黑屏窗口**(来源:glass-brick Scene Manager)
① `change_scene` 支持 `loading_screen`(只要求目标场景实现 `set_progress(v)`)与 `min_loading_time`;② `preload_scene(path)` 复用 `CoreKit.res` 的分帧加载(web 安全,不引线程);③ 拆出 `fade_out()` / `fade_in()` 两个可 await 的动词,给「黑屏时挪玩家/存档」用。`reload_scene()` 顺手补。

**P3 —— `CoreKit.audio` UI 音效通道 + 环境音层**(来源:Sound Manager)
① `play_ui_sfx()` 走独立池,`process_mode = ALWAYS`,游戏暂停时不断;普通 SFX 池随暂停;② `play_ambient(stream, fade)` / `stop_ambient(stream, fade)` / `stop_all_ambient()`,循环、多条并存;③ 小 API:`stop_sfx(stream)`、`is_music_playing()`、`play_music(stream, fade, from_position)`、`play_sfx` 返回 player。

**P4 —— 手柄品牌识别 + 震动**(来源:Input Helper)
`device_changed` 之外增加只读 `joypad_brand()`(按 `Input.get_joy_name` 归类 xbox / playstation / switch / generic),给按键图标换皮用;`rumble(weak, strong, sec)` 薄封装 `Input.start_joy_vibration`(Android 上走 `Input.vibrate_handheld` 分支)。

**P5 —— `KitTransition` 遮罩图案类型**(来源:两款 Scene Manager)
新增 `Type.MASK`:shader + 灰度过渡图 + 反相 + 平滑度。GL Compatibility 下可用的简单 canvas shader,Web/微信应无障碍【推断,需实测】。

**P6 —— `KitDataRegistry.register_records(type, records, id_key)`**(来源:CSV Data Importer)
吃「字典数组」,让 CSV 导入器 / JSON / 远端配置都能直接喂表;kit 不自带 CSV 解析(Godot 自带 `FileAccess.get_csv_line`,导入器游戏层自装)。

**P7 —— `KitStateMachine` 延时转移 + 序列化**(来源:State Charts)
`add_timed_transition(from, to, sec)`(状态进入后计时,离开即取消);`to_dict()/from_dict()` 只存当前态名 + pushdown 栈,对齐 kit 类库存档约定。层级/并行/历史状态**不做**,文档指路 State Charts。

**P8 —— 文档层**(零代码)
`kit-achievements.md` 加 GodotSteam sink 适配示例;`using-core-kit` / README 加「推荐搭配」一节:相机 → Phantom Camera,对话 → Dialogue Manager,复杂状态 → State Charts,表格 → CSV Data Importer,音效素材 → gdfxr(并写入 asset-bank skill 的 drop-in 说明),包体审计 → GodotSize。
