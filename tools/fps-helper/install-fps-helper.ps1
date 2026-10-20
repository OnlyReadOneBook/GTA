$ErrorActionPreference = 'Stop'
$src = $args[0]
$dir = 'C:\Program Files (x86)\RivaTuner Statistics Server'
$traceSource = Join-Path (Split-Path -Parent $src) '..\..\Core\gta-stage-trace.ps1'
if (-not (Test-Path -LiteralPath $traceSource)) { throw "Stage trace source missing: $traceSource" }
Copy-Item $traceSource "$dir\gta-stage-trace.ps1" -Force -ErrorAction Stop
Copy-Item $src "$dir\gta-fps-helper.ps1" -Force
$a = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\conhost.exe" -Argument "--headless $env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$dir\gta-fps-helper.ps1`""
$t = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$p = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName 'GTA FPS Helper' -Action $a -Trigger $t -Principal $p -Settings $s -Force | Out-Null
Stop-ScheduledTask -TaskName 'GTA FPS Helper'
Start-ScheduledTask -TaskName 'GTA FPS Helper'
'installed' | Out-File 'C:\Users\rlfjr\.gta-fps-install.log' -Encoding utf8
