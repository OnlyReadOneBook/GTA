#Requires -Version 5.1
<#
바탕화면·시작 메뉴(Steam 폴더)의 "Grand Theft Auto V Enhanced.url"(steam://rungameid/3240220)을
launch-gta.ahk 를 부르는 같은 이름의 .lnk 로 바꾼다. 아이콘은 원래 .url 의 것을 그대로 쓴다.
원래 .url 은 %USERPROFILE%\gta-perf\steam-launch\shortcut-backup 으로 옮겨 둔다. 게임·Steam 은 건드리지 않는다.
#>
[CmdletBinding()]
param(
    [string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
    [string[]]$Folders = @([Environment]::GetFolderPath('Desktop'), (Join-Path ([Environment]::GetFolderPath('Programs')) 'Steam')),
    [string]$BackupRoot = (Join-Path $env:USERPROFILE 'gta-perf\steam-launch\shortcut-backup')
)

$ErrorActionPreference = 'Stop'
$name = 'Grand Theft Auto V Enhanced'
$launcher = Join-Path $PSScriptRoot 'launch-gta.ahk'
if (-not (Test-Path -LiteralPath $AhkPath)) { throw "AutoHotkey 가 없음: $AhkPath" }
if (-not (Test-Path -LiteralPath $launcher)) { throw "실행기가 없음: $launcher" }

$shell = New-Object -ComObject WScript.Shell
foreach ($folder in $Folders) {
    $url = Join-Path $folder ($name + '.url')
    $lnk = Join-Path $folder ($name + '.lnk')
    if (-not (Test-Path -LiteralPath $url) -and -not (Test-Path -LiteralPath $lnk)) { continue }
    $icon = $null
    if (Test-Path -LiteralPath $url) {
        $iconLine = @(Get-Content -LiteralPath $url | Where-Object { $_ -like 'IconFile=*' }) | Select-Object -First 1
        if ($iconLine) { $icon = $iconLine.Substring('IconFile='.Length) }
    } elseif (Test-Path -LiteralPath $lnk) {
        $icon = ($shell.CreateShortcut($lnk).IconLocation -split ',')[0]
    }
    $shortcut = $shell.CreateShortcut($lnk)
    $shortcut.TargetPath = $AhkPath
    $shortcut.Arguments = '"' + $launcher + '"'
    $shortcut.WorkingDirectory = $PSScriptRoot
    $shortcut.Description = 'GTA V Enhanced (Steam 메인 창·Special Offers 없이 실행)'
    if ($icon -and (Test-Path -LiteralPath $icon)) { $shortcut.IconLocation = $icon + ',0' }
    $shortcut.Save()
    if (Test-Path -LiteralPath $url) {
        $backup = Join-Path $BackupRoot (Split-Path -Leaf $folder)
        $null = New-Item -ItemType Directory -Force -Path $backup
        Move-Item -LiteralPath $url -Destination (Join-Path $backup ($name + '.url')) -Force
        Write-Output ('바꿈: ' + $lnk + ' (원래 .url 은 ' + $backup + ')')
    } else {
        Write-Output ('다시 씀: ' + $lnk)
    }
}
