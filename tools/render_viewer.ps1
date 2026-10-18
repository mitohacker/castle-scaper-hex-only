# render_viewer.ps1 -- every picture of the combinations viewer, rendered by the game itself (hidden window, under the memory guard).
#   powershell -File tools\render_viewer.ps1 [-Only patterns,ripple,spots,castle] [-Look noon]
# Needs viewer\data\combos.json (tools\combo_probe.gd): the pictures follow its numbers. Writes viewer\img\*.jpg and viewer\img\renders.json.
param([string]$Only = "patterns,ripple,spots,castle", [string]$Look = "noon")
$wt = (Resolve-Path "$PSScriptRoot\..").Path
$root = $wt.Replace('\', '/')
if (-not (Test-Path "$wt\viewer\data\combos.json")) {
	Write-Host "viewer\data\combos.json is missing: run viewer-castle-scaper-realistic.bat dump first"
	exit 2
}
$common = "--cs-fresh --cs-noui --cs-nobirds --cs-uncap --cs-quality=high --cs-look=$Look --combos=$root/viewer/data/combos.json --out=$root/viewer/img"
$jobs = @()
if ($Only -match "patterns") { $jobs += , @("patterns", "") }
if ($Only -match "ripple") { $jobs += , @("ripple", "--tile=640x480") }
$rest = (@("spots", "castle") | Where-Object { $Only -match $_ }) -join ","
if ($rest -ne "") { $jobs += , @($rest, "") }
foreach ($j in $jobs) {
	Write-Host "=== rendering $($j[0]) ==="
	& powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\cs_run.ps1" -Windowed -Resolution 960x720 -LimitGB 3.5 -Seconds 900 -Script res://tools/analysis_render.gd -ScriptArgs "-- $common --only=$($j[0]) $($j[1])"
	if ($LASTEXITCODE -ne 0) {
		Write-Host "the render of $($j[0]) failed (exit $LASTEXITCODE)"
		exit $LASTEXITCODE
	}
}
exit 0
