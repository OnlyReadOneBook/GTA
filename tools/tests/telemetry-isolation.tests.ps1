#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$library = Join-Path $root 'Core\gta-turbo.ps1'
. $library -LibraryOnly
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('gta isolation ' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($fixture)
$script:PerfDir = $fixture
$script:MacroConfig = Join-Path $fixture 'request.txt'
$script:WatcherSourcePath = Join-Path $fixture 'collector fixture.ps1'
$script:NextTelemetryStart = [datetime]::MinValue
$script:TelemetryWorker = $null
$serialProcess = $null
$ownerProcess = $null
$checks = 0
function Check($Ok, [string]$Name) {
    $script:checks++
    if (-not $Ok) { throw "FAIL: $Name" }
}
function Wait-File([string]$Path) {
    $deadline = [datetime]::UtcNow.AddSeconds(30)
    while (-not [IO.File]::Exists($Path)) {
        if ([datetime]::UtcNow -gt $deadline) { throw "Fixture did not publish $Path" }
        Start-Sleep -Milliseconds 20
    }
}
$child = @'
param([string]$MacroConfig, [switch]$TelemetryOnly, [int]$OwnerPid, [long]$OwnerStartTicks, [string]$ReadyEvent, [switch]$Serial)
$ErrorActionPreference = 'Stop'
$childOptions = @{ MacroConfig = $MacroConfig; OwnerPid = $OwnerPid; OwnerStartTicks = $OwnerStartTicks; ReadyEvent = $ReadyEvent; Serial = $Serial }
. '__LIBRARY__' -LibraryOnly -MacroConfig $MacroConfig
$MacroConfig = $childOptions.MacroConfig; $OwnerPid = $childOptions.OwnerPid
$OwnerStartTicks = $childOptions.OwnerStartTicks; $ReadyEvent = $childOptions.ReadyEvent; $Serial = $childOptions.Serial
$fixture = Split-Path -Parent $MacroConfig
$script:TelemetryHeartbeat = Join-Path $fixture ("collector-{0}.heartbeat" -f $PID)
$script:NextTelemetrySample = [datetime]::MinValue
function Get-FrameFeed { }
function Invoke-ModeCheck {
    if ([IO.File]::ReadAllText($MacroConfig) -eq 'active') {
        [IO.File]::WriteAllText((Join-Path $fixture 'ack'), [Diagnostics.Stopwatch]::GetTimestamp().ToString())
    }
}
function Write-Perf {
    [IO.File]::WriteAllText((Join-Path $fixture 'sample-begin'), [Diagnostics.Stopwatch]::GetTimestamp().ToString())
    Start-Sleep -Seconds 8
    [IO.File]::WriteAllText((Join-Path $fixture 'sample-end'), [Diagnostics.Stopwatch]::GetTimestamp().ToString())
}
if ($Serial) {
    # The former production ordering: control, synchronous collection, control.
    Invoke-ModeCheck $true
    Invoke-TelemetryIteration $true
    Invoke-ModeCheck $true
    exit
}
if (-not (Test-TelemetryOwner $OwnerPid $OwnerStartTicks)) { exit 2 }
$gate = [Threading.EventWaitHandle]::OpenExisting($ReadyEvent)
try { if (-not $gate.WaitOne(30000)) { exit 3 } } finally { $gate.Dispose() }
$info = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path, '-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 60"')
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$descendant = [Diagnostics.Process]::Start($info)
[IO.File]::WriteAllText((Join-Path $fixture 'descendant'), $descendant.Id.ToString())
Invoke-TelemetryIteration $true
while (Test-TelemetryOwner $OwnerPid $OwnerStartTicks) { Start-Sleep -Milliseconds 100 }
'@
[IO.File]::WriteAllText($script:WatcherSourcePath, $child.Replace('__LIBRARY__', $library.Replace("'", "''")))
function Invoke-ModeCheck {
    if ([IO.File]::ReadAllText($script:MacroConfig) -eq 'active') {
        [IO.File]::WriteAllText((Join-Path $fixture 'ack'), [Diagnostics.Stopwatch]::GetTimestamp().ToString())
    }
}
function Sync-CloudSync { }
try {
    $self = [Diagnostics.Process]::GetCurrentProcess()
    $ownerStart = $self.StartTime.ToUniversalTime().Ticks
    $executable = $self.MainModule.FileName
    $self.Dispose()
    Check (Test-TelemetryOwner $PID $ownerStart) 'actual owner identity accepted'
    Check (-not (Test-TelemetryOwner $PID ($ownerStart + 1))) 'reused PID with different start rejected'
    [IO.File]::WriteAllText($script:MacroConfig, 'away')
    $info = [Diagnostics.ProcessStartInfo]::new($executable, ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -MacroConfig "{1}" -Serial' -f $script:WatcherSourcePath, $script:MacroConfig))
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $serialProcess = [Diagnostics.Process]::Start($info)
    Wait-File (Join-Path $fixture 'sample-begin')
    $issued = [Diagnostics.Stopwatch]::GetTimestamp()
    [IO.File]::WriteAllText($script:MacroConfig, 'active')
    Wait-File (Join-Path $fixture 'ack')
    $serialMs = ([long][IO.File]::ReadAllText((Join-Path $fixture 'ack')) - $issued) * 1000.0 / [Diagnostics.Stopwatch]::Frequency
    Check ($serialMs -ge 7000) 'serial collection delays return for the remaining sample'
    Check ($serialProcess.WaitForExit(5000) -and $serialProcess.ExitCode -eq 0) 'serial fixture completes'
    foreach ($name in @('ack', 'sample-begin', 'sample-end')) { [IO.File]::Delete((Join-Path $fixture $name)) }
    [IO.File]::WriteAllText($script:MacroConfig, 'away')
    Invoke-ControlIteration $true
    $workerId = $script:TelemetryWorker.Process.Id
    Wait-File (Join-Path $fixture 'sample-begin')
    Wait-File (Join-Path $fixture 'descendant')
    $descendantId = [int][IO.File]::ReadAllText((Join-Path $fixture 'descendant'))
    $issued = [Diagnostics.Stopwatch]::GetTimestamp()
    [IO.File]::WriteAllText($script:MacroConfig, 'active')
    Invoke-ControlIteration $true
    Wait-File (Join-Path $fixture 'ack')
    $isolatedMs = ([long][IO.File]::ReadAllText((Join-Path $fixture 'ack')) - $issued) * 1000.0 / [Diagnostics.Stopwatch]::Frequency
    Check (-not [IO.File]::Exists((Join-Path $fixture 'sample-end'))) 'control acknowledges return while real child sample remains blocked'
    Check ($isolatedMs -lt $serialMs / 2) 'isolated acknowledgement excludes most injected sample delay'
    for ($i = 0; $i -lt 3; $i++) { Invoke-ControlIteration $true }
    Check ($script:TelemetryWorker.Process.Id -eq $workerId) 'slow healthy sample does not spawn duplicate collectors'
    Stop-TelemetryWorker
    $deadline = [datetime]::UtcNow.AddSeconds(5)
    do {
        $remaining = @(Get-Process -Id $workerId,$descendantId -ErrorAction SilentlyContinue)
        if ($remaining.Count -eq 0) { break }
        Start-Sleep -Milliseconds 20
    } while ([datetime]::UtcNow -lt $deadline)
    Check ($remaining.Count -eq 0) 'closing owner job kills blocked worker and native descendants'
    foreach ($name in @('sample-begin', 'sample-end', 'descendant')) { [IO.File]::Delete((Join-Path $fixture $name)) }
    $ownerScript = Join-Path $fixture 'owner fixture.ps1'
    $ownerSource = @'
param([string]$Directory)
. '__LIBRARY__' -LibraryOnly
$script:PerfDir = $Directory
$script:MacroConfig = Join-Path $Directory 'request.txt'
$script:WatcherSourcePath = Join-Path $Directory 'collector fixture.ps1'
Start-TelemetryWorker
[IO.File]::WriteAllText((Join-Path $Directory 'worker-pid'), $script:TelemetryWorker.Process.Id.ToString())
Start-Sleep -Seconds 60
'@
    [IO.File]::WriteAllText($ownerScript, $ownerSource.Replace('__LIBRARY__', $library.Replace("'", "''")))
    $info = [Diagnostics.ProcessStartInfo]::new($executable, ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Directory "{1}"' -f $ownerScript, $fixture))
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $ownerProcess = [Diagnostics.Process]::Start($info)
    Wait-File (Join-Path $fixture 'worker-pid')
    Wait-File (Join-Path $fixture 'descendant')
    $orphanIds = @([int][IO.File]::ReadAllText((Join-Path $fixture 'worker-pid')), [int][IO.File]::ReadAllText((Join-Path $fixture 'descendant')))
    $ownerProcess.Kill()
    $null = $ownerProcess.WaitForExit(5000)
    $deadline = [datetime]::UtcNow.AddSeconds(5)
    do {
        $remaining = @(Get-Process -Id $orphanIds -ErrorAction SilentlyContinue)
        if ($remaining.Count -eq 0) { break }
        Start-Sleep -Milliseconds 20
    } while ([datetime]::UtcNow -lt $deadline)
    Check ($remaining.Count -eq 0) 'abrupt owner death also kills child tree while collection is blocked'
    $script:WatcherSourcePath = Join-Path $fixture 'does-not-exist.ps1'
    $script:NextTelemetryStart = [datetime]::MinValue
    Invoke-ControlIteration $true
    $failedWorker = $script:TelemetryWorker
    if ($failedWorker) { $null = $failedWorker.Process.WaitForExit(5000) }
    Invoke-ControlIteration $true
    Check ($null -eq $script:TelemetryWorker -and $script:NextTelemetryStart -gt [datetime]::UtcNow) 'failed worker backs off while control remains available'
    Write-Output ('PASS telemetry isolation cases={0} serial_return_ms={1:N1} isolated_return_ms={2:N1} injected_sample_ms=8000' -f $checks, $serialMs, $isolatedMs)
} finally {
    Stop-TelemetryWorker
    if ($serialProcess) {
        if (-not $serialProcess.HasExited) { $serialProcess.Kill() }
        $serialProcess.Dispose()
    }
    if ($ownerProcess) {
        if (-not $ownerProcess.HasExited) { $ownerProcess.Kill() }
        $ownerProcess.Dispose()
    }
    Get-ChildItem -LiteralPath $fixture -File | Remove-Item
    Remove-Item -LiteralPath $fixture
}
