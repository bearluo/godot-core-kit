# Android APK 出包:临时剥离 godot_ai 开发插件 -> 导出 -> 无条件还原
# 用法(仓库根目录): powershell -File tools\export_android.ps1
#
# 为什么需要这个脚本:
# godot_ai 是本地 AI 编辑器桥,只在开发期有用。它启用时会把 autoload
# `_mcp_game_helper` 直接写进 project.godot 并立即保存(plugin.gd 的
# _ensure_game_helper_autoload),所以工作区里几乎总是带着这行。导出时
# 它会被打进包;而单纯给 export_presets.cfg 加 exclude_filter 又会留下
# 一个指向已排除脚本的 autoload,导出包一启动就找不到脚本。
# 插件官方的清理路径是 _disable_plugin()(plugin.gd),它做的正是"从
# ProjectSettings 里 clear 掉这个 autoload"。本脚本在导出期间等价地
# 复现这一步,但不需要去编辑器里手动开关插件,且 finally 保证还原。

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$Root = Get-Location

$ProjectFile = Join-Path $Root 'project.godot'
$PresetFile = Join-Path $Root 'export_presets.cfg'
$PresetName = 'Android'
$OutApk = Join-Path $Root 'build\android\farm-sim.apk'

# --- 定位 Godot:必须是标准版,不能用 mono 版 -------------------------------
# mono 版走 Android 导出会牵扯 .NET android workload,本项目是纯 GDScript,
# 没必要。GODOT_ANDROID_EXPORT_EXE 可覆盖。
function Resolve-GodotExe {
  if ($env:GODOT_ANDROID_EXPORT_EXE) {
    if (-not (Test-Path $env:GODOT_ANDROID_EXPORT_EXE)) {
      throw "GODOT_ANDROID_EXPORT_EXE 指向的文件不存在: $($env:GODOT_ANDROID_EXPORT_EXE)"
    }
    return $env:GODOT_ANDROID_EXPORT_EXE
  }
  $std = 'D:\Program Files\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe'
  if (Test-Path $std) { return $std }
  throw "找不到标准版 Godot。请装到 $std,或设环境变量 GODOT_ANDROID_EXPORT_EXE 指向标准版(非 mono) console exe。"
}

# --- 定位 JDK ------------------------------------------------------------
# build-tools 里的 apksigner.bat 只认 JAVA_HOME 或 PATH 上的 java,两者
# 都没有时签名会失败(且报错很晦涩)。这台机器复用 Unity 自带的 JDK 17。
function Resolve-JavaHome {
  if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
    return $env:JAVA_HOME
  }
  $unity = 'C:\Program Files\Unity\Hub\Editor\6000.4.6f1\Editor\Data\PlaybackEngines\AndroidPlayer\OpenJDK'
  if (Test-Path (Join-Path $unity 'bin\java.exe')) { return $unity }
  throw "找不到 JDK。请设 JAVA_HOME 指向 JDK 17,否则 apksigner 签名会失败。"
}

$GodotExe = Resolve-GodotExe
$env:JAVA_HOME = Resolve-JavaHome
Write-Output "godot    : $GodotExe"
Write-Output "JAVA_HOME: $($env:JAVA_HOME)"

# --- 备份原始字节,保证还原后与改动前逐字节一致 ----------------------------
$ProjectBak = [System.IO.File]::ReadAllBytes($ProjectFile)
$PresetBak = [System.IO.File]::ReadAllBytes($PresetFile)
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Write-TextNoBom([string]$path, [string]$text) {
  [System.IO.File]::WriteAllText($path, $text, $Utf8NoBom)
}

$exitCode = 1
try {
  # --- 剥离 project.godot 里的 godot_ai 痕迹 ------------------------------
  $proj = [System.IO.File]::ReadAllText($ProjectFile, [System.Text.Encoding]::UTF8)
  $proj = $proj -replace '(?m)^_mcp_game_helper=.*\r?\n', ''
  # editor_plugins 的 enabled 数组里三种位置形态都要清:中间/末尾/独此一项
  $proj = $proj -replace '"res://addons/godot_ai/plugin\.cfg", ', ''
  $proj = $proj -replace ', "res://addons/godot_ai/plugin\.cfg"', ''
  $proj = $proj -replace '"res://addons/godot_ai/plugin\.cfg"', ''
  Write-TextNoBom $ProjectFile $proj

  # --- 让 export_presets.cfg 排除插件文件本身 -----------------------------
  $preset = [System.IO.File]::ReadAllText($PresetFile, [System.Text.Encoding]::UTF8)
  if ($preset -notmatch 'addons/godot_ai') {
    $preset = [regex]::Replace($preset, '(?m)^exclude_filter="([^"]*)"', {
      param($m)
      $cur = $m.Groups[1].Value
      if ([string]::IsNullOrEmpty($cur)) { $new = 'addons/godot_ai/*' }
      else { $new = "$cur,addons/godot_ai/*" }
      'exclude_filter="' + $new + '"'
    })
    Write-TextNoBom $PresetFile $preset
  }

  Write-Output "`n=== 已剥离 godot_ai(导出期间生效) ==="
  Write-Output ("  autoload _mcp_game_helper : {0}" -f $(if ($proj -match '_mcp_game_helper') { '*** 仍在 ***' } else { '已移除' }))
  Write-Output ("  editor_plugins 条目        : {0}" -f $(if ($proj -match 'godot_ai/plugin\.cfg') { '*** 仍在 ***' } else { '已移除' }))

  Write-Output "`n=== import ==="
  & $GodotExe --headless --path $Root --import 2>&1 | Select-String -Pattern 'ERROR|SCRIPT ERROR' | Select-Object -First 5

  Write-Output "`n=== export ==="
  $null = New-Item -ItemType Directory -Force (Split-Path $OutApk -Parent)
  & $GodotExe --headless --path $Root --export-debug $PresetName $OutApk 2>&1 |
    Select-String -Pattern 'ERROR|Signed|ADDING: lib/'
  $exitCode = $LASTEXITCODE
}
finally {
  # 无论导出成功与否都还原,避免把剥离后的配置留在工作区
  [System.IO.File]::WriteAllBytes($ProjectFile, $ProjectBak)
  [System.IO.File]::WriteAllBytes($PresetFile, $PresetBak)
  Write-Output "`n=== project.godot / export_presets.cfg 已还原 ==="
}

# --- 验证产物:确认包里真的没有插件残留 ------------------------------------
if (Test-Path $OutApk) {
  $size = [math]::Round((Get-Item $OutApk).Length / 1MB, 1)
  Write-Output "`nAPK: $OutApk  ($size MB)"
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [System.IO.Compression.ZipFile]::OpenRead($OutApk)
  try {
    $leak = @($zip.Entries | Where-Object { $_.FullName -like '*godot_ai*' })
    $abis = @($zip.Entries | Where-Object { $_.FullName -like 'lib/*' } |
      ForEach-Object { $_.FullName.Split('/')[1] } | Sort-Object -Unique)
    Write-Output ("ABI      : {0}" -f ($abis -join ', '))
    if ($leak.Count -gt 0) {
      Write-Output ("*** 包内仍有 {0} 个 godot_ai 条目 ***" -f $leak.Count)
      $exitCode = 1
    } else {
      Write-Output "godot_ai : 包内无残留 OK"
    }
  } finally { $zip.Dispose() }
} else {
  Write-Output "`n*** 未产出 APK ***"
  $exitCode = 1
}

exit $exitCode
