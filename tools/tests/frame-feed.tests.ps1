param(
    [string]$FixtureDir = (Join-Path $env:TEMP ('gta-frame-feed-tests-' + [guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\Core\gta-turbo.ps1') -LibraryOnly
$null = New-Item -ItemType Directory -Path $FixtureDir -Force
$FixtureDir = (Resolve-Path -LiteralPath $FixtureDir).Path
$results = New-Object 'System.Collections.Generic.List[object]'
$fixtureShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Check([string]$Name, [bool]$Condition) {
    if (-not $Condition) { throw "Assertion failed: $Name" }
    $results.Add([pscustomobject]@{ test = $Name; result = 'pass' })
}

function Wait-Condition([scriptblock]$Condition, [string]$Description) {
    $deadline = [datetime]::UtcNow.AddSeconds(5)
    do {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 25
    } while ([datetime]::UtcNow -lt $deadline)
    throw "Timed out waiting for $Description"
}

function Start-FixtureFeed([string]$Name, [string]$Body) {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("`$ProgressPreference = 'SilentlyContinue'`r`n" + $Body))
    return [GtaFrameFeed]::new(
        $fixtureShell,
        "-NoProfile -NonInteractive -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand $encoded",
        (Join-Path $FixtureDir $Name)
    )
}

Initialize-FrameFeed
$nowUtc = [datetime]::Parse('2026-10-20T00:01:00Z').ToUniversalTime()
$stalledFeed = [pscustomobject]@{ Alive = $true; LastOutputUtc = $nowUtc.AddSeconds(-60) }
Check 'foreground silence below sixty seconds keeps the feed' (-not (Test-FrameFeedStalled $stalledFeed ($nowUtc.AddMilliseconds(-1)) $true))
Check 'foreground silence at sixty seconds requires recovery' (Test-FrameFeedStalled $stalledFeed $nowUtc $true)
Check 'background silence never requests stall recovery' (-not (Test-FrameFeedStalled $stalledFeed ($nowUtc.AddMinutes(5)) $false))
$stalledFeed.Alive = $false
Check 'exited feed is not classified as a live stdout stall' (-not (Test-FrameFeedStalled $stalledFeed $nowUtc $true))
$stalledFeed.Alive = $true
$stalledFeed.LastOutputUtc = $nowUtc.AddSeconds(-1)
Check 'new stdout resets the sixty second silence window' (-not (Test-FrameFeedStalled $stalledFeed $nowUtc $true))
$feed = $null
$reader = $null
try {
    $body = @'
[Console]::Out.WriteLine('Application,ProcessID,MsBetweenDisplayChange,CPUStartDateTime')
[Console]::Out.WriteLine('[ETW Status] EventsLost=0')
[Console]::Out.Flush()
Start-Sleep -Milliseconds 500
1..10 | ForEach-Object { [Console]::Out.WriteLine('fixture.exe,123,10,2026-10-19T23:59:59.100000000') }
1..2 | ForEach-Object { [Console]::Out.WriteLine('fixture.exe,123,20,2026-10-19T23:59:59.200000000') }
[Console]::Out.WriteLine('fixture.exe,123,NA,2026-10-19T23:59:59.300000000')
[Console]::Out.WriteLine('fixture.exe,123,0,2026-10-19T23:59:59.400000000')
[Console]::Out.WriteLine('[ETW Status] EventsLost=123')
[Console]::Error.WriteLine('fixture stderr warning')
[Console]::Out.Flush()
[Console]::Error.Flush()
'@
    $feed = Start-FixtureFeed 'valid' $body
    Wait-Condition { $feed.RawPath -and (Test-Path -LiteralPath $feed.RawPath) } 'raw header file'
    $reader = [IO.File]::Open($feed.RawPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    Wait-Condition { $feed.Rows -eq 14 -and -not $feed.Alive } 'fixture EOF and frame drain'
    $feed.Stop()
    $reader.Dispose()
    $reader = $null

    $raw = @([IO.File]::ReadAllLines($feed.RawPath))
    Check 'EOF flush preserves every valid, NA and zero frame while a reader is open' ($raw.Count -eq 15)
    Check 'ETW status lines do not enter raw CSV or frame row count' ($feed.Rows -eq 14 -and -not ([IO.File]::ReadAllText($feed.RawPath).Contains('[ETW Status]')))
    Check 'latest ETW status is available independently of frame data' ($feed.EtwStatus -ceq '[ETW Status] EventsLost=123')
    Check 'raw header retains source columns with capture timestamp' ($raw[0] -ceq 'CapturedAt,Application,ProcessID,MsBetweenDisplayChange,CPUStartDateTime')
    $sourceRows = @($raw | Select-Object -Skip 1 | ForEach-Object { $_.Substring($_.IndexOf(',') + 1) })
    Check 'valid source rows are preserved verbatim' (@($sourceRows | Where-Object { $_ -ceq 'fixture.exe,123,10,2026-10-19T23:59:59.100000000' }).Count -eq 10)
    Check 'NA source row remains available for diagnosis' ($sourceRows -ccontains 'fixture.exe,123,NA,2026-10-19T23:59:59.300000000')
    Check 'zero source row remains available for diagnosis' ($sourceRows -ccontains 'fixture.exe,123,0,2026-10-19T23:59:59.400000000')
    foreach ($line in $raw | Select-Object -Skip 1) {
        $captured = [datetimeoffset]::MinValue
        Check 'capture timestamp includes parseable time and timezone' ([datetimeoffset]::TryParseExact(
            $line.Substring(0, $line.IndexOf(',')), 'o', [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$captured
        ))
    }
    $recent = @($feed.Recent(10))
    Check 'NA and zero are excluded from frame metrics only' ($recent.Count -eq 12)
    Check 'display intervals produce expected mean FPS and slowest one percent' ((Format-Fps $recent) -ceq '85.7,50.0')
    Check 'last frame UTC is updated for valid data' ($feed.LastFrameUtc -ne [datetime]::MinValue)
    Check 'stdout health timestamp is available alongside valid frame time' ($feed.LastOutputUtc -ge $feed.LastFrameUtc -and $feed.LastOutputUtc -ne [datetime]::MinValue)
    $errorFile = Join-Path (Join-Path $FixtureDir 'valid') 'errors.log'
    Wait-Condition { (Test-Path -LiteralPath $errorFile) -and ([IO.File]::ReadAllText($errorFile).Contains('fixture stderr warning')) } 'stderr persistence'
    Check 'stderr is available as feed error' ($feed.LastError.Contains('fixture stderr warning'))
    $feed = $null

    $observedV1Header = 'Application,ProcessID,SwapChainAddress,Runtime,SyncInterval,PresentFlags,Dropped,TimeInSeconds,msInPresentAPI,msBetweenPresents,AllowsTearing,PresentMode,msUntilRenderComplete,msUntilDisplayed,msBetweenDisplayChange,msFlipDelay,msUntilRenderStart,msGPUActive,msSinceInput'
    $observedLayoutRow = 'fixture.exe,123,0x1,DXGI,1,0,0,1.0,0.1,5,0,Hardware Composed: Independent Flip,4,6,10,0,1,3,NA'
    $headerCases = @(
        @{ Name = 'observed-v1-lowercase'; Header = $observedV1Header },
        @{ Name = 'v1-mixed-case'; Header = $observedV1Header.Replace('msBetweenDisplayChange', 'mSbETWEENdISPLAYcHANGE') }
    )
    foreach ($headerCase in $headerCases) {
        $body = "[Console]::Out.WriteLine('$($headerCase.Header)')`r`n1..10 | ForEach-Object { [Console]::Out.WriteLine('$observedLayoutRow') }"
        $feed = Start-FixtureFeed $headerCase.Name $body
        Wait-Condition { $feed.Rows -eq 10 -and -not $feed.Alive } "$($headerCase.Name) EOF"
        $feed.Stop()
        Check "$($headerCase.Name) uses display interval despite neighboring present interval" ((Format-Fps @($feed.Recent(10))) -ceq '100.0,100.0')
        Check "$($headerCase.Name) preserves original header casing and all source columns" ([IO.File]::ReadAllLines($feed.RawPath)[0] -ceq ('CapturedAt,' + $headerCase.Header))
        Check "$($headerCase.Name) is accepted without parser errors" ([string]::IsNullOrEmpty($feed.LastError))
        $feed = $null
    }

    $feed = Start-FixtureFeed 'unsupported' @'
[Console]::Out.WriteLine('Application,ProcessID,FrameTime,DisplayedTime')
[Console]::Out.Flush()
Start-Sleep -Seconds 10
'@
    Wait-Condition { -not $feed.Alive -and $feed.LastError.Contains('MsBetweenDisplayChange') } 'unsupported header rejection'
    Check 'unsupported v2 metrics fail closed before fixture process exits' (-not $feed.Alive)
    $feed.Stop()
    Check 'unsupported header is preserved in raw evidence' ([IO.File]::ReadAllText($feed.RawPath).Contains('Application,ProcessID,FrameTime,DisplayedTime'))
    Check 'unsupported header failure is persisted' ([IO.File]::ReadAllText((Join-Path (Join-Path $FixtureDir 'unsupported') 'errors.log')).Contains('v1 metrics required'))
    $feed = $null

    $script:PerfDir = Join-Path $FixtureDir 'summaries'
    $null = New-Item -ItemType Directory -Path $script:PerfDir
    $script:Header = 'time,fps_avg,fps_1pct_low,gpu_util_pct,gpu_temp_c,gpu_power_w,gpu_clock_mhz,vram_used_mb,vram_total_mb,throttle_reasons,cpu_util_pct,mode'
    $script:FrameFeed = $null
    $script:FeedError = ''
    function Get-Fps { return '60.0,45.0' }
    function Read-PerfGpu { return '90,70,100,2000,6000,8000,0' }
    function Read-PerfCpu { return 55 }
    function Get-Mode { return 1 }
    Write-Perf ([datetime]'2026-10-19T23:59:59')
    Write-Perf ([datetime]'2026-10-20T00:00:00')
    $previousCsv = Join-Path $script:PerfDir '20261019.csv'
    $currentCsv = Join-Path $script:PerfDir '20261020.csv'
    $previousRows = @(Import-Csv -LiteralPath $previousCsv)
    $currentRows = @(Import-Csv -LiteralPath $currentCsv)
    Check 'midnight writes the previous sample to the previous date' ($previousRows.Count -eq 1 -and $previousRows[0].time -eq '2026-10-19T23:59:59')
    Check 'midnight creates a new daily CSV with one header' ($currentRows.Count -eq 1 -and $currentRows[0].time -eq '2026-10-20T00:00:00' -and $currentRows[0].fps_avg -eq '60.0')
    $status = Get-Content -LiteralPath (Join-Path $script:PerfDir 'status.json') -Raw | ConvertFrom-Json
    Check 'successful sample reports saved FPS and current CSV' ($status.csv_saved -and $status.fps_available -and $status.csv -eq $currentCsv -and @($status.errors).Count -eq 0)

    $reader = [IO.File]::Open($currentCsv, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    function Read-PerfGpu { throw 'fixture GPU timeout' }
    function Read-PerfCpu { throw 'fixture CPU unavailable' }
    function Get-Mode { throw 'fixture mode unavailable' }
    Write-Perf ([datetime]'2026-10-20T00:00:10')
    $reader.Dispose()
    $reader = $null
    $currentRows = @(Import-Csv -LiteralPath $currentCsv)
    Check 'sensor errors and overlapping reader do not drop the FPS sample' ($currentRows.Count -eq 2 -and $currentRows[1].fps_avg -eq '60.0' -and $currentRows[1].fps_1pct_low -eq '45.0')
    Check 'failed sensors preserve empty columns without shifting the CSV' (
        $currentRows[1].gpu_util_pct -eq '' -and $currentRows[1].cpu_util_pct -eq '' -and $currentRows[1].mode -eq '' -and
        @($currentRows[1].PSObject.Properties).Count -eq 12
    )
    $status = Get-Content -LiteralPath (Join-Path $script:PerfDir 'status.json') -Raw | ConvertFrom-Json
    $health = @(Get-Content -LiteralPath (Join-Path $script:PerfDir 'health.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
    Check 'sensor failures are observable with successful CSV persistence' ($status.csv_saved -and $status.fps_available -and @($status.errors).Count -eq 3 -and $health.Count -eq 1)
    Check 'health retains each failing sensor reason' (
        $status.errors -contains 'gpu: fixture GPU timeout' -and
        $status.errors -contains 'cpu: fixture CPU unavailable' -and
        $status.errors -contains 'mode: fixture mode unavailable'
    )

    function Get-Fps { return ',' }
    function Read-PerfGpu { return '90,70,100,2000,6000,8000,0' }
    function Read-PerfCpu { return 55 }
    function Get-Mode { return 1 }
    Write-Perf ([datetime]'2026-10-20T00:00:20')
    $status = Get-Content -LiteralPath (Join-Path $script:PerfDir 'status.json') -Raw | ConvertFrom-Json
    $health = @(Get-Content -LiteralPath (Join-Path $script:PerfDir 'health.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
    Check 'missing FPS produces explicit health even when sensors succeed' ($status.csv_saved -and -not $status.fps_available -and $health.Count -eq 2 -and -not $health[1].fps_available)

    $etwReleasePath = Join-Path $FixtureDir 'release-etw.txt'
    $body = @'
$deadline = [datetime]::UtcNow.AddSeconds(5)
while (-not [IO.File]::Exists('__RELEASE_PATH__')) {
    if ([datetime]::UtcNow -gt $deadline) { exit 2 }
    Start-Sleep -Milliseconds 10
}
[Console]::Out.WriteLine('[ETW Status] EventsLost=456')
[Console]::Out.Flush()
'@
    $body = $body.Replace('__RELEASE_PATH__', $etwReleasePath.Replace("'", "''"))
    $feed = Start-FixtureFeed 'etw-only' $body
    $outputBeforeEtw = $feed.LastOutputUtc
    [IO.File]::WriteAllText($etwReleasePath, 'release')
    Wait-Condition { $feed.EtwStatus -ceq '[ETW Status] EventsLost=456' -and -not $feed.Alive } 'ETW-only fixture EOF'
    $feed.Stop()
    Check 'ETW status alone does not reset the frame output silence clock' ($feed.LastOutputUtc -eq $outputBeforeEtw)
    Check 'ETW status before any frame does not create raw CSV or parser error' (
        $feed.Rows -eq 0 -and [string]::IsNullOrEmpty($feed.RawPath) -and [string]::IsNullOrEmpty($feed.LastError)
    )
    $script:FrameFeed = $feed
    Write-Perf ([datetime]'2026-10-20T00:00:25')
    $status = Get-Content -LiteralPath (Join-Path $script:PerfDir 'status.json') -Raw | ConvertFrom-Json
    $health = @(Get-Content -LiteralPath (Join-Path $script:PerfDir 'health.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
    Check 'status retains ETW loss evidence with zero raw frames' ($status.raw_rows -eq 0 -and -not $status.fps_available -and $status.etw_status -ceq '[ETW Status] EventsLost=456')
    Check 'health persists ETW loss evidence when FPS is missing' ($health[-1].etw_status -ceq '[ETW Status] EventsLost=456' -and $health[-1].raw_rows -eq 0)
    $healthCountBeforePartialLoss = $health.Count
    function Get-Fps { return '60.0,45.0' }
    Write-Perf ([datetime]'2026-10-20T00:00:26')
    $health = @(Get-Content -LiteralPath (Join-Path $script:PerfDir 'health.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
    Check 'partial ETW loss persists in health despite available FPS and no sensor errors' (
        $health.Count -eq $healthCountBeforePartialLoss + 1 -and $health[-1].fps_available -and
        @($health[-1].errors).Count -eq 0 -and $health[-1].etw_status -ceq '[ETW Status] EventsLost=456'
    )
    function Get-Fps { return ',' }
    $script:FrameFeed = $null
    $feed = $null

    $script:Game = 'fixture-game'
    $script:FixtureGameId = 123
    $script:FrameGameId = 123
    $script:NextFeedStart = [datetime]::Now.AddMinutes(5)
    $script:RecoveryLogError = ''
    $script:FrameFeed = [pscustomobject]@{
        Alive = $true; LastOutputUtc = [datetime]::UtcNow.AddMinutes(-2)
        LastError = ''; Stopped = $false
    }
    $script:FrameFeed | Add-Member -MemberType ScriptMethod -Name Stop -Value { $this.Stopped = $true }
    $recoveryFeed = $script:FrameFeed
    function Get-ModeDesktopState { return @{ Available = $true; ProcessId = 123 } }
    function Get-Process {
        param([string]$Name, [string]$ErrorAction)
        if ($Name -ne 'fixture-game') { throw "Unexpected process lookup: $Name" }
        if ($null -ne $script:FixtureGameId) { return [pscustomobject]@{ Id = $script:FixtureGameId } }
    }
    $reader = [IO.File]::Open((Join-Path $script:PerfDir 'health.jsonl'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    $recoveryResult = Get-FrameFeed $true
    $reader.Dispose()
    $reader = $null
    Check 'locked recovery log does not prevent stopping the stalled feed' ($recoveryFeed.Stopped -and $null -eq $script:FrameFeed)
    Check 'recovery respects restart cooldown without launching another process' ($null -eq $recoveryResult)
    Check 'recovery log failure is retained for independent status reporting' ($script:RecoveryLogError.StartsWith('recovery log: '))
    Write-Perf ([datetime]'2026-10-20T00:00:30')
    $status = Get-Content -LiteralPath (Join-Path $script:PerfDir 'status.json') -Raw | ConvertFrom-Json
    Check 'status exposes recovery log failure while continuing CSV persistence' ($status.csv_saved -and $status.errors -contains $script:RecoveryLogError)

    $script:PresentMon = $fixtureShell
    $script:FixtureLaunchIds = New-Object 'System.Collections.Generic.List[int]'
    function New-FrameFeed([int]$GameId) {
        $script:FixtureLaunchIds.Add($GameId)
        $createdFeed = [pscustomobject]@{
            Alive = $true; LastOutputUtc = [datetime]::UtcNow; LastError = ''; Stopped = $false
        }
        $createdFeed | Add-Member -MemberType ScriptMethod -Name Stop -Value { $this.Alive = $false; $this.Stopped = $true }
        return $createdFeed
    }
    $script:NextFeedStart = [datetime]::MinValue
    $feed = Get-FrameFeed $true
    Check 'collector factory receives the observed game PID' ($script:FixtureLaunchIds.Count -eq 1 -and $script:FixtureLaunchIds[0] -eq 123)
    Check 'collector binds its running feed to the selected game PID' ($script:FrameGameId -eq 123)
    $sameFeed = Get-FrameFeed $true
    Check 'unchanged game PID retains the existing capture session without another factory call' ([object]::ReferenceEquals($feed, $sameFeed) -and $script:FixtureLaunchIds.Count -eq 1)

    $previousFeed = $feed
    $script:FixtureGameId = 456
    $script:NextFeedStart = [datetime]::Now.AddMinutes(5)
    $feed = Get-FrameFeed $true
    Check 'changed game PID stops the old session and bypasses its cooldown' (-not $previousFeed.Alive -and $feed.Alive -and -not [object]::ReferenceEquals($previousFeed, $feed))
    Check 'replacement session targets the new game PID' ($script:FrameGameId -eq 456 -and $script:FixtureLaunchIds.Count -eq 2 -and $script:FixtureLaunchIds[1] -eq 456)
    $script:FixtureGameId = $null
    $missingGameResult = Get-FrameFeed $true
    Check 'disappearing game stops capture despite a stale running flag' ($null -eq $missingGameResult -and $null -eq $script:FrameFeed -and -not $feed.Alive)
    $feed = $null
    $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $FixtureDir 'results.json') -Encoding UTF8
    Write-Output ("PASS: {0} assertions; fixtures: {1}" -f $results.Count, $FixtureDir)
} finally {
    if ($reader) { $reader.Dispose() }
    if ($feed) { $feed.Stop() }
}
