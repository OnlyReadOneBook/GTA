param(
    [Parameter(Mandatory=$true)][string]$Pythonw,
    [Parameter(Mandatory=$true)][string]$SteamVideo,
    [string]$OutputRoot = (Join-Path $env:LOCALAPPDATA 'GTA-DJ-Evidence')
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script = Join-Path $PSScriptRoot 'watch.pyw'
foreach ($path in @($Pythonw, $SteamVideo, $script)) {
    if (!(Test-Path -LiteralPath $path)) { throw "Missing path: $path" }
    if ($path.Contains('"')) { throw 'Quotes are not allowed in paths.' }
}
if ([IO.Path]::GetFileName($Pythonw) -ne 'pythonw.exe') { throw 'Use pythonw.exe to avoid a console window.' }
if ($OutputRoot.Contains('"')) { throw 'Quotes are not allowed in paths.' }
$arguments = '"{0}" --root "{1}" --steam "{2}" --repo "{3}"' -f $script, $OutputRoot, $SteamVideo, $repo
$action = New-ScheduledTaskAction -Execute ([IO.Path]::GetFullPath($Pythonw)) -Argument $arguments
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$logon = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'GTA DJ Evidence' -Action $action -Trigger @($trigger, $logon) -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName 'GTA DJ Evidence'
Get-ScheduledTask -TaskName 'GTA DJ Evidence' | Select-Object TaskName, State
