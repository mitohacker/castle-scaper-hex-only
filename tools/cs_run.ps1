# cs_run.ps1 -- run one Castle Scaper Godot script under the memory guard, after checking every script compiles.
#   powershell -File tools\cs_run.ps1 -Script res://tools/smoke.gd [-ScriptArgs "-- --starter=castle"] [-Seconds 300] [-Windowed] [-Import]
param([string]$Script, [string]$ScriptArgs = "", [int]$Seconds = 300, [double]$LimitGB = 1.5, [switch]$Windowed, [switch]$Import, [string]$WindowMode = "Hidden", [string]$Resolution = "1600x900")
$wt = (Resolve-Path "$PSScriptRoot\..").Path
$mg = (Resolve-Path "$wt\..\.claude\skills\memory-guard").Path
$gd = "C:\Dev\Godot\Godot_v4.7.1-stable_win64_console.exe"
Set-Location $wt
New-Item -ItemType Directory -Force "$wt\tmp" | Out-Null
if ($Import) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $mg\guard_run.ps1 -WorkDir $wt -Seconds 180 -LimitGB 2 -TimeIsFailure -Log "$wt\tmp\import.log" -Exe $gd -ExeArgs "--headless --path . --audio-driver Dummy --import" | Out-Null
}
& powershell -NoProfile -ExecutionPolicy Bypass -File $mg\guard_run.ps1 -WorkDir $wt -Seconds 120 -LimitGB 1.5 -TimeIsFailure -Log "$wt\tmp\check.log" -Exe $gd -ExeArgs "--headless --path . --audio-driver Dummy --script res://tools/check_scripts.gd" | Out-Null
$chk = Get-Content "$wt\tmp\check.log" -ErrorAction SilentlyContinue | Select-String "FAIL|failures"
$chk | ForEach-Object { $_.Line }
if ($chk -match "failures: [1-9]" -or $chk -match "FAIL ") { Get-Content "$wt\tmp\check.log.err" -TotalCount 16; exit 2 }
if ($Script -eq "") { exit 0 }
$head = if ($Windowed) { "--resolution $Resolution" } else { "--headless" }
& powershell -NoProfile -ExecutionPolicy Bypass -File $mg\guard_run.ps1 -WorkDir $wt -Seconds $Seconds -LimitGB $LimitGB -TimeIsFailure -ShowLog -WindowMode $WindowMode -Exe $gd -ExeArgs "$head --path . --audio-driver Dummy --script $Script $ScriptArgs"
exit $LASTEXITCODE
