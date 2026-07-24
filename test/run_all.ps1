# godot-core-kit 全量验证:import -> 27 个断言测试 -> demo 冒烟
# 用法(在仓库根目录): powershell -File test\run_all.ps1
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path $PSScriptRoot -Parent)
$tmp = $env:TEMP

# Resolve 'godot' to a native .exe. A .cmd/.bat wrapper cannot be driven with
# UseShellExecute=$false (required below for stream redirection), so unwrap it
# to the real .exe the wrapper forwards to.
function Resolve-GodotExe {
  $src = (Get-Command godot -ErrorAction Stop).Source
  if ($src -match '\.(cmd|bat)$') {
    $m = Select-String -Path $src -Pattern '"([^"]+\.exe)"' | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value }
    throw "Could not resolve godot .exe from wrapper $src"
  }
  return $src
}
$GodotExe = Resolve-GodotExe
Write-Output "godot exe: $GodotExe"

# Drive godot via System.Diagnostics.Process, NOT Start-Process. With
# `Start-Process -NoNewWindow -RedirectStandardOutput`, when the parent's own
# stdout is a pipe/file (e.g. `powershell -File run_all.ps1 | tail`), output is
# silently dropped and ExitCode reads back empty. The .NET path redirects
# deterministically regardless of how the parent was launched. Async stream
# reads (kicked off before WaitForExit) avoid a full-pipe-buffer deadlock.
function Run-Godot([string[]]$gargs, [int]$ms, [string]$tag) {
  $out = "$tmp\rt-$tag.out.txt"; $err = "$tmp\rt-$tag.err.txt"
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $GodotExe
  $psi.Arguments = ($gargs -join ' ')   # none of the args here contains spaces
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $so = $p.StandardOutput.ReadToEndAsync()
  $se = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($ms)) {
    try { $p.Kill() } catch {}
    [System.IO.File]::WriteAllText($out, $so.Result)
    return @{ tag=$tag; code='TIMEOUT'; pass=$false; out=$out }
  }
  [System.IO.File]::WriteAllText($out, $so.Result)
  [System.IO.File]::WriteAllText($err, $se.Result)
  $pass = Select-String -Path $out -Pattern 'ALL PASS' -Quiet
  return @{ tag=$tag; code=$p.ExitCode; pass=$pass; out=$out }
}

Write-Output '=== import (class cache) ==='
$imp = Run-Godot @('--headless','--path','.','--import') 120000 'import'
Write-Output "import exit=$($imp.code)"

$tests = @('test_log','test_event_bus','test_scene_manager','test_object_pool',
  'test_save_manager','test_settings','test_frame_scheduler','test_state_machine',
  'test_input_manager','test_audio_manager','test_resource_manager','test_kit_context','test_core_kit','test_dev_console','test_locale_manager','test_rebind','test_transition','test_ui_stack','test_layer_manager','test_game_clock','test_kit_inventory','test_kit_data_registry','test_kit_offline','test_kit_modifiers','test_kit_stats','test_kit_achievements','test_pack_updater')
$fails = 0
Write-Output "`n=== tests ==="
foreach ($t in $tests) {
  $ms = if ($t -eq 'test_resource_manager') { 120000 } else { 60000 }
  $r = Run-Godot @('--headless','--path','.','-s',"res://test/$t.gd") $ms $t
  $ok = ($r.code -eq 0 -and $r.pass)
  if (-not $ok) { $fails++ }
  Write-Output ("{0,-24} exit={1} pass={2} {3}" -f $t, $r.code, $r.pass, $(if($ok){'OK'}else{'*** FAIL ***'}))
}

Write-Output "`n=== demo smoke (--quit-after 60) ==="
$d = Run-Godot @('--headless','--path','.','res://demo/demo.tscn','--quit-after','60') 90000 'demo'
Write-Output "demo exit=$($d.code)"
$demoText = Get-Content $d.out -Raw
foreach ($e in @('all subsystems smoke-tested','FrameScheduler:','ResourceManager:','KitContext:','-> [Idle]','-> [Run]','-> [Menu]','dispatch(stop) hit=true','stack_depth=0','execute(1+2)=3','god cheat -> god mode','i18n: locale=en t(DEMO_HELLO)=Hello','i18n: locale=zh t(DEMO_HELLO)=','RebindUI: rebind ok=true','conflict_blocked=true','Transition: type=SLIDE none=false','UiStack: depth=3','Layers: hud_z=10','Clock: y1 spring d2 06:00 day_evt=true','Inventory: wood=120 used=3 moved=true','DataRegistry: crops=2 turnip_ok=true','PackUpdater: mounted=0 content_ver=0 errors=0')) {
  $hit = $demoText -match [regex]::Escape($e)
  Write-Output ("demo marker '{0}' : {1}" -f $e, $(if($hit){'present'}else{'*** MISSING ***'}))
  if (-not $hit) { $fails++ }
}
$demoErr = Get-Content "$tmp\rt-demo.err.txt" -Raw
$hasErr = $demoErr -match 'ERROR:|SCRIPT ERROR:'
Write-Output ("demo stderr has ERROR: {0}" -f $(if($hasErr){'*** YES ***'}else{'no'}))
if ($hasErr) { $fails++ }

Write-Output "`n=== SUMMARY FAILS=$fails ==="
exit $fails
