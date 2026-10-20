#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$helperPath = Join-Path $repositoryRoot 'tools\fps-helper\gta-fps-helper.ps1'
$source = [IO.File]::ReadAllText($helperPath)

$tokens = $null
$parseErrors = $null
$null = [Management.Automation.Language.Parser]::ParseFile($helperPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) {
    throw ('fps helper parse errors: ' + (($parseErrors | ForEach-Object Message) -join '; '))
}

$rtssMissing = $source.IndexOf("if (-not (Get-Process RTSS -ErrorAction SilentlyContinue))", [StringComparison]::Ordinal)
$gtaRunning = $source.IndexOf("if (Get-Process GTA5_Enhanced -ErrorAction SilentlyContinue)", [StringComparison]::Ordinal)
$deferLog = $source.IndexOf('RTSS start deferred until GTA exits', [StringComparison]::Ordinal)
$continue = $source.IndexOf('continue', $gtaRunning, [StringComparison]::Ordinal)
$startRtss = $source.IndexOf('Start-Process "$rtssDir\RTSS.exe"', [StringComparison]::Ordinal)

if ($rtssMissing -lt 0) { throw 'RTSS absence guard is missing.' }
if ($gtaRunning -le $rtssMissing) { throw 'GTA running guard must be inside the RTSS absence path.' }
if ($deferLog -le $gtaRunning) { throw 'Deferred RTSS start must leave an operator-visible log.' }
if ($continue -le $gtaRunning -or $continue -ge $startRtss) {
    throw 'The GTA running path must skip RTSS startup.'
}
if ($startRtss -le $gtaRunning) { throw 'RTSS may only start after the GTA running guard.' }

Write-Output 'PASS fps helper defers RTSS startup while GTA is running (source-only; no process changes)'

. $helperPath -LibraryOnly
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('fps-stage-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
try {
    Initialize-GtaStageTrace -Component 'fps-helper-test' -SourcePath $helperPath -Directory $fixture
    Add-Type @'
using System;
public static class Rtss {
    public static uint Requested;
    public static int Updates;
    public static bool FailLoad;
    public static bool LoadProfile(string name) { if (FailLoad) throw new InvalidOperationException("fixture native failure"); return true; }
    public static bool SetProfileProperty(string name, ref uint value, uint size) { Requested = value; return true; }
    public static bool SaveProfile(string name) { return false; }
    public static void UpdateProfiles() { Updates++; }
}
'@
    $request = Join-Path $fixture 'request'
    [IO.File]::WriteAllText($request, '30')
    if ((Read-FpsRequest $request) -ne 30) { throw 'Request value was lost by tracing.' }
    Set-FpsProfile -Fps 30
    if ([Rtss]::Requested -ne 30 -or [Rtss]::Updates -ne 1) { throw 'RTSS call sequence changed.' }
    $events = @(Get-Content (Join-Path $fixture 'fps-helper-test.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
    foreach ($stage in @('fps.request.read', 'rtss.load_profile', 'rtss.set_limit', 'rtss.save_profile', 'rtss.update_profiles')) {
        $records = @($events | Where-Object stage -eq $stage)
        if ($records.Count -ne 2) { throw "Missing before/after evidence: $stage" }
    }
    $failedSave = @($events | Where-Object stage -eq 'rtss.save_profile.result')
    if ($failedSave.Count -ne 1 -or $failedSave[0].data.ok -ne $false) { throw 'RTSS false result must remain observable.' }
    [Rtss]::FailLoad = $true
    if (Try-SetFpsProfile -Fps 0) { throw 'Native exception must not report success.' }
    [Rtss]::FailLoad = $false
    if (-not (Try-SetFpsProfile -Fps 0) -or [Rtss]::Updates -ne 2) { throw 'Helper must survive an exception and allow the next poll to retry.' }
    Write-Output 'PASS fps request and RTSS stages preserve calls and expose unsuccessful native results (fake DLL)'
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}

& {
    $fixtureState = @{}
    $fixtureState.stopped = @()
    $fixtureState.started = 0
    $fixtureState.instances = @(
        [pscustomobject]@{ ProcessId = 1001; CreationDate = [datetime]'2026-01-01'; CommandLine = 'powershell.exe -File "C:\Program Files (x86)\RivaTuner Statistics Server\gta-fps-helper.ps1"' },
        [pscustomobject]@{ ProcessId = 1002; CreationDate = [datetime]'2026-01-01'; CommandLine = 'powershell.exe -File "C:\unrelated.ps1"' }
    )
    function Copy-Item {}
    function New-ScheduledTaskAction { @{} }
    function New-ScheduledTaskTrigger { @{} }
    function New-ScheduledTaskPrincipal { @{} }
    function New-ScheduledTaskSettingsSet { @{} }
    function Register-ScheduledTask {}
    function Stop-ScheduledTask {}
    function Start-ScheduledTask { $fixtureState.started++ }
    function Out-File {}
    function Get-CimInstance {
        param($ClassName, $Filter)
        if ($Filter -match '^ProcessId=(\d+)$') { return $fixtureState.instances | Where-Object ProcessId -eq ([int]$Matches[1]) }
        return $fixtureState.instances
    }
    function Stop-Process {
        param($Id, $ErrorAction)
        $fixtureState.stopped += $Id
        $fixtureState.instances = @($fixtureState.instances | Where-Object ProcessId -ne $Id)
    }
    & (Join-Path $repositoryRoot 'tools\fps-helper\install-fps-helper.ps1') $helperPath
    if ($fixtureState.started -ne 1 -or $fixtureState.stopped.Count -ne 1 -or $fixtureState.stopped[0] -ne 1001 -or $fixtureState.instances[0].ProcessId -ne 1002) {
        throw 'Installer must remove its surviving helper child before restarting, without touching unrelated PowerShell.'
    }
    Write-Output 'PASS installer replaces surviving helper child by exact path and leaves unrelated processes alone (mocked tasks/processes)'
}
