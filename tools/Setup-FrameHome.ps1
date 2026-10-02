# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param([switch]$Templates,[switch]$Build)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$cache=Join-Path $projectRoot '.tools'
New-Item -ItemType Directory -Path $cache -Force | Out-Null
$release='https://github.com/godotengine/godot-builds/releases/download/4.6.1-stable'
$editorHash='67c63291115c66ebe7145415b5aac235e1667e417d6cd3d1975848670a1d31cbfad111c8231cb53195bb62e6e4fde951d97aaca227736a94f93dcbf8f23b1fbb'
$templateHash='d80001711c07973b1fd3e88077ba99644e19db7c9e52627e16f38a2937879f809f94dbd8493936fb8204908bbc57a521d41173dce5208061fe4c99772490c541'
function Get-VerifiedArchive([string]$Name,[string]$Destination,[string]$Hash) {
    if(-not (Test-Path -LiteralPath $Destination)) {
        Invoke-WebRequest -Uri "$release/$Name" -OutFile "$Destination.partial"
        Move-Item -LiteralPath "$Destination.partial" -Destination $Destination
    }
    if((Get-FileHash -LiteralPath $Destination -Algorithm SHA512).Hash.ToLowerInvariant() -ne $Hash) {
        throw "SHA512 mismatch: $Destination. File retained for inspection."
    }
}
Get-VerifiedArchive 'Godot_v4.6.1-stable_win64.exe.zip' (Join-Path $cache 'godot-editor.zip') $editorHash
$engine=Join-Path $cache 'godot/Godot_v4.6.1-stable_win64_console.exe'
if(-not (Test-Path -LiteralPath $engine)) {
    Expand-Archive -LiteralPath (Join-Path $cache 'godot-editor.zip') -DestinationPath (Join-Path $cache 'godot')
}
if($Templates -or $Build) {
    Write-Host 'Official export templates download is approximately 1.25 GB (ignored by Git).'
    $archivePath=Join-Path $cache 'godot-templates.tpz'
    Get-VerifiedArchive 'Godot_v4.6.1-stable_export_templates.tpz' $archivePath $templateHash
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $destination=Join-Path $cache 'templates'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        foreach($name in @('linux_debug.arm64','linux_release.arm64','windows_debug_x86_64.exe','windows_release_x86_64.exe')) {
            $entry=$archive.GetEntry("templates/$name")
            if($null -eq $entry) { throw "Missing export template: $name" }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,(Join-Path $destination $name),$true)
        }
    } finally { $archive.Dispose() }
}
$importLog=Join-Path $cache 'asset-import.log'
& $engine --headless --xr-mode off --editor --path $projectRoot --import --quit *> $importLog
if($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR:','ERROR:' -Quiet)) {
    Get-Content -LiteralPath $importLog -Tail 40
    throw "Godot asset import failed: $importLog"
}
Write-Host "Editor: $engine"
if($Build) { & (Join-Path $PSScriptRoot 'Build-FrameHome.ps1') }
