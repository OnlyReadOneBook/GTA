$ErrorActionPreference = 'Stop'
$src = $args[0]
$dir = 'C:\Program Files (x86)\RivaTuner Statistics Server'
$helperPath = Join-Path $dir 'gta-fps-helper.ps1'
$traceSource = Join-Path (Split-Path -Parent $src) '..\..\Core\gta-stage-trace.ps1'
if (-not (Test-Path -LiteralPath $traceSource)) { throw "Stage trace source missing: $traceSource" }
Copy-Item $traceSource "$dir\gta-stage-trace.ps1" -Force -ErrorAction Stop
Copy-Item $src "$dir\gta-fps-helper.ps1" -Force
$a = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\conhost.exe" -Argument "--headless $env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$dir\gta-fps-helper.ps1`""
$t = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$p = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName 'GTA FPS Helper' -Action $a -Trigger $t -Principal $p -Settings $s -Force | Out-Null
$commandPattern = '(?i)-File\s+"?' + [regex]::Escape($helperPath) + '"?(?:\s|$)'
$previous = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match $commandPattern })
Stop-ScheduledTask -TaskName 'GTA FPS Helper'
# Ending the conhost task can leave its PowerShell child alive.
foreach ($process in $previous) {
    $current = Get-CimInstance Win32_Process -Filter "ProcessId=$($process.ProcessId)"
    if ($current -and $current.CreationDate -eq $process.CreationDate -and $current.CommandLine -match $commandPattern) {
        Stop-Process -Id $current.ProcessId -ErrorAction Stop
    }
}
if (@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match $commandPattern }).Count) {
    throw 'Previous FPS helper is still running; replacement was not started.'
}
Start-ScheduledTask -TaskName 'GTA FPS Helper'
'installed' | Out-File 'C:\Users\rlfjr\.gta-fps-install.log' -Encoding utf8
