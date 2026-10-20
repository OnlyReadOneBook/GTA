#Requires -Version 5.1
# Diagnostics must never turn a successful control operation into a failure.
$script:GtaStageTrace = $null

function Initialize-GtaStageTrace {
    param(
        [string]$Component,
        [string]$SourcePath,
        [string]$Directory = (Join-Path $env:USERPROFILE 'gta-perf\stage-trace'),
        [long]$MaxBytes = 8388608,
        [int]$Backups = 3
    )
    $script:GtaStageTrace = $null
    try {
        if ($Component -notmatch '^[a-z0-9-]+$' -or $MaxBytes -lt 4096 -or $Backups -lt 1 -or $Backups -gt 8) { return }
        $source = [IO.Path]::GetFullPath($SourcePath)
        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256 -ErrorAction Stop).Hash
        $process = [Diagnostics.Process]::GetCurrentProcess()
        try { $started = $process.StartTime.ToUniversalTime().ToString('o') } finally { $process.Dispose() }
        $null = [IO.Directory]::CreateDirectory($Directory)
        $script:GtaStageTrace = @{
            Path = Join-Path $Directory ($Component + '.jsonl')
            Component = $Component; RunId = [guid]::NewGuid().ToString('N')
            ProcessStart = $started; SourcePath = $source; SourceHash = $hash
            MaxBytes = $MaxBytes; Backups = $Backups
        }
        Write-GtaStageEvent -Stage 'trace.initialized'
    } catch { $script:GtaStageTrace = $null }
}

function Write-GtaStageEvent {
    param(
        [string]$Stage,
        [hashtable]$Data = @{},
        [string]$Phase = 'event',
        [string]$SpanId = '',
        [long]$Started = 0,
        [string]$ErrorMessage = ''
    )
    try {
        $state = $script:GtaStageTrace
        if ($null -eq $state) { return }
        $tick = [Diagnostics.Stopwatch]::GetTimestamp()
        $duration = if ($Started -gt 0) { [math]::Round(1000.0 * ($tick - $Started) / [Diagnostics.Stopwatch]::Frequency, 3) } else { $null }
        $record = [ordered]@{
            schema = 1; time_utc = [datetime]::UtcNow.ToString('o')
            component = $state.Component; run_id = $state.RunId; pid = $PID
            log_path = $state.Path
            process_start_utc = $state.ProcessStart; source_path = $state.SourcePath; source_sha256 = $state.SourceHash
            stage = $Stage; phase = $Phase; span_id = $SpanId
            monotonic_ticks = $tick; monotonic_frequency = [Diagnostics.Stopwatch]::Frequency
            duration_ms = $duration; data = $Data
        }
        if ($ErrorMessage) { $record.error = $ErrorMessage.Substring(0, [math]::Min(2048, $ErrorMessage.Length)) }
        $json = ConvertTo-Json -InputObject $record -Depth 5 -Compress -WarningAction SilentlyContinue -ErrorAction Stop
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json + "`n")
        if ($bytes.Length -gt [math]::Min(65536, $state.MaxBytes)) { return }
        $path = $state.Path
        if ([IO.File]::Exists($path) -and ([IO.FileInfo]$path).Length + $bytes.Length -gt $state.MaxBytes) {
            for ($i = $state.Backups; $i -ge 1; $i--) {
                $target = "$path.$i"
                if ([IO.File]::Exists($target)) { [IO.File]::Delete($target) }
                $previous = if ($i -eq 1) { $path } else { "$path.$($i - 1)" }
                if ([IO.File]::Exists($previous)) { [IO.File]::Move($previous, $target) }
            }
        }
        $stream = [IO.File]::Open($path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            # Make begin visible to readers without a physical disk barrier on the control loop.
            $stream.Flush()
        } finally { $stream.Dispose() }
    } catch { }
}

function Invoke-GtaTraceStage {
    param([string]$Stage, [scriptblock]$Action, [hashtable]$Data = @{})
    $span = [guid]::NewGuid().ToString('N')
    $started = [Diagnostics.Stopwatch]::GetTimestamp()
    try { Write-GtaStageEvent -Stage $Stage -Phase 'begin' -SpanId $span -Data $Data } catch { }
    try {
        & $Action
    } catch {
        try { Write-GtaStageEvent -Stage $Stage -Phase 'error' -SpanId $span -Started $started -Data $Data -ErrorMessage $_.Exception.Message } catch { }
        throw
    }
    try { Write-GtaStageEvent -Stage $Stage -Phase 'end' -SpanId $span -Started $started -Data $Data } catch { }
}
