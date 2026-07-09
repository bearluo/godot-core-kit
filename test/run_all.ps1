# godot-core-kit 全量验证:import -> 12 个断言测试 -> demo 冒烟
# 用法(在仓库根目录): powershell -File test\run_all.ps1
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path $PSScriptRoot -Parent)
$tmp = $env:TEMP

function Run-Godot([string[]]$gargs, [int]$ms, [string]$tag) {
  $out = "$tmp\rt-$tag.out.txt"; $err = "$tmp\rt-$tag.err.txt"
  $p = Start-Process godot -ArgumentList $gargs -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -NoNewWindow
  $null = $p.Handle   # 先取 Handle,后面读 ExitCode 才可靠
  if (-not $p.WaitForExit($ms)) { $p.Kill(); return @{ tag=$tag; code='TIMEOUT'; pass=$false; out=$out } }
  $pass = Select-String -Path $out -Pattern 'ALL PASS' -Quiet
  return @{ tag=$tag; code=$p.ExitCode; pass=$pass; out=$out }
}

Write-Output '=== import (class cache) ==='
$imp = Run-Godot @('--headless','--path','.','--import') 120000 'import'
Write-Output "import exit=$($imp.code)"

$tests = @('test_log','test_event_bus','test_scene_manager','test_object_pool',
  'test_save_manager','test_settings','test_frame_scheduler','test_state_machine',
  'test_input_manager','test_audio_manager','test_resource_manager','test_core_kit')
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
foreach ($e in @('all subsystems smoke-tested','FrameScheduler:','ResourceManager:','-> [Idle]','-> [Run]')) {
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
