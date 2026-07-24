# ─────────────────────────────────────────────────────────────────────────────
# 导出管线编排模板(示例 —— 复制到你的游戏仓库改路径后使用)
#
# 产出「薄壳 base + 远程内容包 + manifest.json」三件套,喂给 CoreKit.updater。
# 完整原理见 addons/godot-core-kit/docs/tools/export-pipeline.md。
#
# 前置:在编辑器 Project > Export 里配好两个(或更多)preset,并把它们的
#       export_filter 手写成下面这样(export_presets.cfg 是本地文件,不入库):
#
#   [preset.N]  name="base"      export_filter="scenes"
#               export_files=PackedStringArray("res://boot.tscn")   # 只圈启动场景+依赖
#   [preset.M]  name="content"   export_filter="exclude"
#               export_files=PackedStringArray("res://boot.tscn","res://boot.gd")  # 排掉壳,其余全进
#
#   base 走**平台导出**(--export-debug/release,进 APK/exe,含引擎二进制);
#   content 走 **--export-pack**(仅数据,无需 export 模板)。
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = 'Stop'

# —— 改这几行 ——
$Godot   = "D:\Program Files\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe"  # 非 mono 标准版
$Project = "E:\path\to\your\game"          # 含 project.godot 的工程根
$OutDir  = "$Project\build\packs"          # 内容包 + manifest 产出目录
$UrlBase = "https://cdn.example.com/packs/" # 内容包下发前缀(相对 url 拼在其后)

# —— 内容包清单:每个内容域一个包(别切太碎)。version 每次改内容要 +1 ——
#    file 用相对工程根的路径;url 相对则拼 UrlBase,绝对(http)则原样。
$Packs = @(
  @{ id = "content"; version = 3; order = 0; file = "build/packs/content-v3.pck"; url = "content-v3.pck" }
  # @{ id = "dlc1"; version = 1; order = 1; file = "build/packs/dlc1-v1.pck"; url = "dlc1-v1.pck" }
)

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# 1) 首次或纹理设置变过:先 import(生成资源导入产物 + class/uid 缓存)
& $Godot --headless --path $Project --import

# 2) 逐个内容包:--export-pack "<preset>" <out.pck>(preset 名 = export_presets.cfg 的 name=)
& $Godot --headless --path $Project --export-pack "content" "$OutDir\content-v3.pck"
# & $Godot --headless --path $Project --export-pack "dlc1" "$OutDir\dlc1-v1.pck"

# 3) 生成 manifest.json:写一份 spec.json 交给 kit 的 build_manifest CLI
#    (用**导出这些包的同一个 Godot**跑,以戳对引擎版本)
$spec = @{ engine = ""; url_base = $UrlBase; packs = $Packs }
$specPath = "$OutDir\spec.json"
$spec | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $specPath

& $Godot --headless --path $Project `
  --script "res://addons/godot-core-kit/tools/build_manifest.gd" `
  -- $specPath "$OutDir\manifest.json"

# 4) base 端(薄壳 APK/exe)照常走平台导出,例如 Android:
# & $Godot --headless --path $Project --export-debug "Android" "$Project\build\game.apk"

Write-Output "done -> $OutDir\manifest.json  +  内容包 .pck"
Write-Output "把 $OutDir 下的 .pck 与 manifest.json 上传到 $UrlBase,"
Write-Output "游戏里 CoreKit.updater.check('${UrlBase}manifest.json') 即可拉更新。"
