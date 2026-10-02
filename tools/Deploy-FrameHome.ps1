# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param([string]$Device='frame',[string]$User='steamos',[string]$IdentityFile='')
$ErrorActionPreference='Stop'
if($Device -notmatch '^[A-Za-z0-9][A-Za-z0-9.:-]*$' -or $User -notmatch '^[A-Za-z0-9_]+$') { throw 'Invalid device or user name' }
$projectRoot=Split-Path -Parent $PSScriptRoot
$build=Join-Path $projectRoot 'build/frame'
$files=@('FrameHome.arm64','FrameHome.pck','launch-framehome.sh','LICENSE','NOTICE.md','GODOT.txt','GODOT-THIRD-PARTY.txt')
foreach($file in $files) { if(-not (Test-Path -LiteralPath (Join-Path $build $file))) { throw "Missing build file: $file" } }
$identity=@()
if($IdentityFile) { $identity=@('-i',$IdentityFile) }
$remote="$User@$Device"
# Uses a host already paired by the user. Never writes system partitions or Steam configuration.
& ssh @identity -o BatchMode=yes -o StrictHostKeyChecking=yes $remote 'mkdir -p ~/FrameHome'
if($LASTEXITCODE -ne 0) { throw 'SSH login unavailable. Pair this PC in SteamOS Devkit Client first.' }
foreach($file in $files) {
    & scp @identity -o BatchMode=yes -o StrictHostKeyChecking=yes (Join-Path $build $file) "${remote}:FrameHome/"
    if($LASTEXITCODE -ne 0) { throw "Could not upload $file" }
}
& ssh @identity -o BatchMode=yes -o StrictHostKeyChecking=yes $remote 'chmod +x ~/FrameHome/FrameHome.arm64 ~/FrameHome/launch-framehome.sh'
if($LASTEXITCODE -ne 0) { throw 'Could not mark the executable runnable' }
Write-Host 'Uploaded to ~/FrameHome. Launch from SteamOS Devkit Client with the Steam Linux Runtime 3.0 ARM64 (Sniper) runtime.'
