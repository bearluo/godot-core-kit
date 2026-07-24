<#
build_gacha_pack.ps1 — 一键把「扭蛋房」导出成可下载内容包 + 生成 manifest.json

三步:
  1. --export-pack "gacha" <out>/gacha-v<Version>.pck   (导出扭蛋房脚本+数据,不含引擎/其它房)
  2. 写 spec.json(engine 留空=运行引擎 major.minor,url_base 拼下载地址)
  3. 跑 kit 的 build_manifest CLI → 生成 manifest.json(戳 size/sha256/engine)

产物 <out>/manifest.json 直接可作游戏内 CoreKit.updater.check(<manifest_url>) 的下发内容。
本地联调加 -Serve 起 python http.server;真机改 -UrlBase 指向你的 CDN/服务器。

前置:export_presets.cfg 里要有名为 "gacha" 的 preset(export_filter="resources" +
export_files 列出 gacha_room.gd/gacha_item_def.gd/gacha_upgrade_def.gd + 7 个 .tres,
script_export_mode=2)。--export-pack 无需导出模板(区别于 --export-debug)。
export_presets.cfg 是 .gitignore 的本机文件,preset 配置见 docs/README.md「OTA」节。

用法:
  powershell -File examples/fortune-mill/tools/build_gacha_pack.ps1
  powershell -File examples/fortune-mill/tools/build_gacha_pack.ps1 -Serve -Port 8091
  powershell -File examples/fortune-mill/tools/build_gacha_pack.ps1 -UrlBase "https://cdn.example.com/packs/" -Version 2
#>
param(
	[string]$Godot   = "D:\Program Files\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe",
	[string]$OutDir  = "",
	[string]$UrlBase = "http://127.0.0.1:8091/",
	[int]   $Version = 1,
	[switch]$Serve,
	[int]   $Port    = 8091
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# 仓库根 = 本脚本 ../../../(examples/fortune-mill/tools/ → root)
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
if ([string]::IsNullOrEmpty($OutDir)) { $OutDir = Join-Path $Root "build\packs" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$PckName    = "gacha-v$Version.pck"
$PckPath    = Join-Path $OutDir $PckName
$SpecPath   = Join-Path $OutDir "spec.json"
$Manifest   = Join-Path $OutDir "manifest.json"
$BuildCli   = "res://addons/godot-core-kit/tools/build_manifest.gd"

if (-not (Test-Path $Godot)) { throw "找不到 Godot(非 mono 标准版):$Godot —— 用 -Godot 指定" }

# --- 1. 导出扭蛋房内容包 ---
Write-Host "[1/3] --export-pack gacha -> $PckPath"
& $Godot --headless --path $Root --export-pack "gacha" $PckPath
if ($LASTEXITCODE -ne 0) { throw "export-pack 失败(exit $LASTEXITCODE)。确认 export_presets.cfg 有 'gacha' preset" }
if (-not (Test-Path $PckPath)) { throw "导出未产出 $PckPath" }
$Size = (Get-Item $PckPath).Length
Write-Host "      pck size=$Size bytes"

# --- 2. 写 spec.json ---
Write-Host "[2/3] write $SpecPath"
$PckFwd = $PckPath -replace '\\','/'
$spec = @{
	engine   = ""            # 空 = build_manifest 用运行引擎 major.minor
	url_base = $UrlBase
	packs    = @(@{ id = "gacha"; version = $Version; order = 0; file = $PckFwd; url = $PckName })
}
($spec | ConvertTo-Json -Depth 5) | Out-File -FilePath $SpecPath -Encoding utf8

# --- 3. 生成 manifest.json ---
Write-Host "[3/3] build_manifest -> $Manifest"
$SpecFwd = $SpecPath -replace '\\','/'
$ManFwd  = $Manifest -replace '\\','/'
& $Godot --headless --path $Root --script $BuildCli -- $SpecFwd $ManFwd
if ($LASTEXITCODE -ne 0) { throw "build_manifest 失败(exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "OK 内容包就绪:"
Write-Host "  pck      : $PckPath ($Size bytes)"
Write-Host "  manifest : $Manifest"
Write-Host "  下载地址 : ${UrlBase}$PckName"
Write-Host "  游戏内   : CoreKit.updater.check(`"${UrlBase}manifest.json`") → download → 重启"

if ($Serve) {
	Write-Host ""
	Write-Host "起本地服务器 http://127.0.0.1:$Port/(Ctrl+C 停)..."
	py -m http.server $Port --directory $OutDir
}
