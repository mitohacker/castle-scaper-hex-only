# shots.ps1 -- clean frames (no UI) of a starter castle from several cameras, under the memory guard.
#   powershell -File tools\shots.ps1 -Out shots\x.png -Starter castle -Views "front/0.6/0.5/90/0/9/0,low/2.4/0.2/70/0/8/0" [-Size 1920x1080] [-Extra "--cs-nobirds"]
# Writes <Out basename>_<view name>.png per view. Windowed (the shot needs a render), muted, guarded.
param([string]$Out = "shots\shot.png", [string]$Starter = "castle", [string]$Views = "", [string]$Size = "1920x1080",
	[string]$Extra = "", [int]$Seconds = 120, [double]$LimitGB = 3.0, [double]$Wait = 3.0, [string]$WindowMode = "Hidden", [string]$NoUi = "--cs-noui")
$wt = (Resolve-Path "$PSScriptRoot\..").Path
$mg = (Resolve-Path "$wt\..\.claude\skills\memory-guard").Path
$gd = "C:\Dev\Godot\Godot_v4.7.1-stable_win64_console.exe"
$outAbs = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $wt $Out }
New-Item -ItemType Directory -Force (Split-Path $outAbs) | Out-Null
$o = $outAbs.Replace([string][char]92, '/')
$v = if ($Views) { "--cs-views=$Views" } else { "" }
$a = "--path . --audio-driver Dummy --resolution $Size -- --cs-fresh --cs-starter=$Starter --cs-shot=$o $NoUi --cs-wait=$Wait $v $Extra"
& powershell -NoProfile -ExecutionPolicy Bypass -File $mg\guard_run.ps1 -WorkDir $wt -Seconds $Seconds -LimitGB $LimitGB -TimeIsFailure -ShowLog -WindowMode $WindowMode -Exe $gd -ExeArgs $a
exit $LASTEXITCODE
