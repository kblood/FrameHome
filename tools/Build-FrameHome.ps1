# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param([ValidateSet('Frame','Windows','Both')][string]$Target='Both')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$engine=Join-Path $projectRoot '.tools/godot/Godot_v4.6.1-stable_win64_console.exe'
if(-not (Test-Path -LiteralPath $engine)) { throw 'Run tools/Setup-FrameHome.ps1 -Templates first.' }
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'build/frame'),(Join-Path $projectRoot 'build/windows') -Force | Out-Null
foreach($item in @(@('Frame','Steam Frame ARM64','frame'),@('Windows','Windows Desktop','windows'))) {
    if($Target -notin @('Both',$item[0])) { continue }
    $log=Join-Path $projectRoot ("build/export-"+$item[2]+'.log')
    & $engine --headless --xr-mode off --path $projectRoot --export-release $item[1] *> $log
    if($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR:','ERROR:' -Quiet)) {
        Get-Content -LiteralPath $log -Tail 40
        throw "Export failed: $($item[1]); inspect $log"
    }
    Write-Host "Built $($item[1])"
}
foreach($folder in @('frame','windows')) {
    if(($Target -eq 'Frame' -and $folder -eq 'windows') -or ($Target -eq 'Windows' -and $folder -eq 'frame')) { continue }
    foreach($file in @('LICENSE','NOTICE.md','licenses/GODOT.txt','licenses/GODOT-THIRD-PARTY.txt')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $file) -Destination (Join-Path $projectRoot ("build/$folder/"+[IO.Path]::GetFileName($file)))
    }
}
if($Target -ne 'Windows') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'launch-framehome.sh') -Destination (Join-Path $projectRoot 'build/frame/launch-framehome.sh')
}
