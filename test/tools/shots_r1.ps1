# R1 验收截图批量生成(全部经引擎内 test/tools/screenshot.gd,进程内 save_png)
# 用法(仓库根目录): powershell -File test\tools\shots_r1.ps1
# 可选: -Godot "<godot.exe 路径>"(默认找 PATH 上的 godot;PATH 上若是 mono 版请显式传标准版)
param(
  [string]$Godot = "",
  [string]$OutDir = "docs/vision/evidence-r1"
)
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)

if (-not $Godot) {
  $cand = "D:\Program Files\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe"
  if (Test-Path $cand) { $Godot = $cand } else { $Godot = (Get-Command godot).Source }
}
Write-Output "godot: $Godot"

# name | w | h | steps
$shots = @(
  @('01-boot-720x1280',       720, 1280, 'wait:30'),
  @('02-boot-540x960',        540,  960, 'wait:30'),
  @('03-boot-1152x648',      1152,  648, 'wait:30'),
  @('04-crossfire-720x1280',  720, 1280, 'gold:9999;place:1,0,fire;place:1,4,fire;place:2,4,fire;place:3,4,ice;place:1,2,fire;place:1,6,fire;sim:130;wave;run:6'),
  @('05-crossfire-540x960',   540,  960, 'gold:9999;place:1,0,fire;place:1,4,fire;place:2,4,fire;place:3,4,ice;place:1,2,fire;place:1,6,fire;sim:130;wave;run:6'),
  @('06-victory-720x1280',    720, 1280, 'gold:99999;place:1,2,fire;place:3,4,fire;place:1,6,fire;place:1,4,fire;place:2,4,fire;place:2,2,ice;place:0,4,fire;place:2,6,ice;place:1,0,fire;place:3,2,fire;place:3,6,fire;place:0,0,fire;place:4,2,fire;place:4,6,fire;place:3,1,fire;place:3,0,fire;sim:900;wait:5'),
  @('07-defeat-720x1280',     720, 1280, 'sim:200;wait:5'),
  @('08-prep-1152x648',      1152,  648, 'gold:9999;place:1,4,fire;place:2,4,ice;wave;sim:40;wait:5')
)

foreach ($s in $shots) {
  $name = $s[0]; $w = $s[1]; $h = $s[2]; $steps = $s[3]
  $out = "$OutDir/$name.png"
  & $Godot --path . -s res://test/tools/screenshot.gd -- "--w=$w" "--h=$h" "--out=$out" "--steps=$steps" 2>&1 |
    Select-String -Pattern '^SHOT' | ForEach-Object { Write-Output $_.Line }
}
Write-Output "done -> $OutDir"
