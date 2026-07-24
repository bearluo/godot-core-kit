# 导出管线（`KitPackManifest` + `build_manifest.gd`）

> 产出「薄壳 base + 远程内容包 + `manifest.json`」的**构建期工具**,供 `CoreKit.updater`
> 消费。可行性与坑的一手论证见 `docs/research/2026-07-23-godot-hot-update-feasibility.md`;
> 运行时消费端见 [pack-updater](../systems/pack-updater.md)。

## 职责

Godot **没有**「薄壳 base + 内容包」的一等按钮(调研 §2:官方只有「完整 base 之上叠补丁」
和「运行时挂 mod」两种)。本管线把「手搓拆分」固化成三步:

1. **薄壳 base** —— 一个 `export_filter="scenes"` 的 preset,只圈启动场景及其依赖,走**平台导出**
   (`--export-debug`/`--export-release`,进 APK/exe)。base 不夹带内容(prototype 实测坐实)。
2. **内容包** —— 一个 `export_filter="exclude"` 的 preset(排掉壳、其余全进),走 **`--export-pack`**
   (仅数据,**无需 export 模板**)。每个内容域一个包,别切太碎。
3. **manifest** —— `KitPackManifest` 读导出好的 `.pck`,算 size + sha256、戳引擎版本,产出
   `CoreKit.updater.check()` 能**逐字消费**的 `manifest.json`。

一键编排模板:[`tools/export_packs.example.ps1`](../../tools/export_packs.example.ps1)(复制到游戏仓库改路径)。

## preset 怎么配（`export_presets.cfg`，本地文件不入库）

```ini
[preset.0]
name="base"
platform="Android"          ; 或 Windows Desktop 等;base 走平台导出
export_filter="scenes"
export_files=PackedStringArray("res://boot.tscn")   ; 只圈启动场景 → 依赖自动带上

[preset.1]
name="content"
platform="Windows Desktop"  ; 导 pck 与平台二进制无关,纹理压缩变体受平台影响
export_filter="exclude"
export_files=PackedStringArray("res://boot.tscn", "res://boot.gd")  ; 列出的被排除
include_filter="content/data/*.json"   ; 顺带带上非资源数据文件(txt/json/csv)
```

> `exclude` 模式下 `export_files` 是**排除清单**;`scenes`/`resources` 模式下是**包含清单**。

## `KitPackManifest`（可测核心，`class_name`，`RefCounted`）

| 方法 | 说明 |
|---|---|
| `build(specs: Array, engine := "") -> Dictionary` | 从包规格产出 manifest。每个 spec = `{id, version, url, order, file}`;`file` 是磁盘上已导出的 `.pck`,仅用于算 size+sha256、**不进输出**。`engine` 空 → 戳运行引擎 `major.minor`。输出按 `order` 升序。 |
| `validate(manifest: Dictionary) -> Array` | 返回 size≤0 或 sha256 为空的 pack id 列表(引用了缺失/不可读 `.pck`)。写盘前拦「哑弹」manifest。 |
| `write_manifest(manifest, out_path) -> int` | 原子写(temp+rename),返回 `Error`。 |

CLI 封装 [`tools/build_manifest.gd`](../../tools/build_manifest.gd) 读一份 spec JSON、组装 url、调上面三个方法:

```
godot --headless --path . --script res://addons/godot-core-kit/tools/build_manifest.gd \
  -- build/packs/spec.json build/packs/manifest.json
```

## 数据格式

**spec.json**(喂给 CLI):

```json
{
  "engine": "",
  "url_base": "https://cdn.example.com/packs/",
  "packs": [
    {"id": "content", "version": 3, "order": 0, "file": "build/packs/content-v3.pck", "url": "content-v3.pck"}
  ]
}
```

`url` 以 `http(s)://` 开头则原样;否则拼到 `url_base` 之后。

**manifest.json**(产物,`CoreKit.updater.check(<其 url>)` 直接消费):

```json
{
  "engine": "4.7",
  "packs": [
    {"id": "content", "version": 3, "url": "https://cdn.example.com/packs/content-v3.pck",
     "size": 12345678, "sha256": "…", "order": 0}
  ]
}
```

## 注意事项

- **引擎版本必须一致**:用**导出这些包的同一个 Godot** 跑 `build_manifest`,`engine` 才戳得对。
  客户端运行引擎若比 `engine` 旧,`updater.check` 会 `check_failed("engine_mismatch:x.y")` 拒下
  (调研 §3:包头拒收更新版引擎导出的包)。**升 Godot 版本 → 所有历史内容包重导 + 重生 manifest。**
- **内容包非「纯内容」**:每个 `.pck` 冗余带 `project.binary` + `.godot/uid_cache.bin` +
  `global_script_class_cache.cfg`(prototype 实测)。运行时以 `replace_files=true` 挂载会覆盖 base
  的这几份,但 `project.binary` 在启动期已读入、运行期挂载不重读,故**无害**——只是别指望内容包
  「只有你选的那几个文件」。`class_name` 解析所需的缓存正因此随包走(4.3+,调研 §4)。
- **`version` 是更新的唯一开关**:`updater` 只下 `version` **高于**本地已装的包。改了内容忘了 +1 →
  客户端不会更新。
- **构建工具别打进游戏包**:消费者导出游戏时把 `addons/godot-core-kit/tools/*` 加进 preset 的
  `exclude_filter`(`KitPackManifest` 是 `RefCounted`,运行时永不实例化,留着无害但没必要打包)。
- **含 GDScript 逻辑的包换逻辑必须重启**(调研 §4b):这是运行时约束,不是导出问题;见 pack-updater 文档。
- **UID 唯一性自检**未纳入本轮(调研 §5 标为「可加」步):跨包新增资源的 UID 碰撞目前靠「同路径
  `replace_files` 覆盖、别靠 UID 顶替」的纪律规避,留作后续。
- **测试边界**:`KitPackManifest` 由 `test/test_pack_manifest.gd` 覆盖(含 `sha256("abc")` 已知向量
  与「生成器产出 → 喂 `updater.check/download` 咬合」的握手测);CLI `build_manifest.gd`(需真实
  文件/命令行)不进 headless 门,同 `http_pack_transport.gd`。
