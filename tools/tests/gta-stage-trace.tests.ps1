#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$source = Join-Path $root 'Core\gta-stage-trace.ps1'
. $source
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('gta-stage-test-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($fixture)
$checks = 0
function Check($Ok, [string]$Name) { $script:checks++; if (-not $Ok) { throw "FAIL: $Name" } }
function Read-Events { @(Get-Content -LiteralPath (Join-Path $fixture 'test.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }) }
try {
    Initialize-GtaStageTrace -Component 'test' -SourcePath $source -Directory $fixture
    $events = @(Read-Events)
    Check ($events.Count -eq 1 -and $events[0].stage -eq 'trace.initialized') 'initialization produces a parseable record'
    Check ($events[0].pid -eq $PID -and $events[0].run_id.Length -eq 32) 'records identify the actual writer and run'
    Check ($events[0].source_sha256 -eq (Get-FileHash -LiteralPath $source).Hash -and $events[0].source_path -eq $source) 'source identity matches the analyzed file'
    Check ([datetime]::Parse($events[0].process_start_utc).ToUniversalTime() -le [datetime]::UtcNow) 'process start is present'
    $result = @(Invoke-GtaTraceStage -Stage 'slow' -Data @{ request = 1 } -Action {
        $inside = @(Read-Events)
        Check ($inside[-1].stage -eq 'slow' -and $inside[-1].phase -eq 'begin') 'begin is readable before action starts'
        [Threading.Thread]::Sleep(120)
        7
        'result'
    })
    Check ($result.Count -eq 2 -and $result[0] -eq 7 -and $result[1] -eq 'result') 'action output order and values are preserved without diagnostic output'
    $events = @(Read-Events | Where-Object stage -eq 'slow')
    Check ($events.Count -eq 2 -and $events[1].phase -eq 'end') 'successful action has begin and end'
    Check ($events[0].span_id -eq $events[1].span_id -and $events[1].duration_ms -ge 100) 'slow stage has matched monotonic duration'
    Check ($events[1].data.request -eq 1) 'caller metadata survives serialization'
    $caught = $null
    try { Invoke-GtaTraceStage -Stage 'failure' -Action { throw [InvalidOperationException]::new('original action failure') } } catch { $caught = $_ }
    Check ($caught.Exception -is [InvalidOperationException] -and $caught.Exception.Message -eq 'original action failure') 'terminating exception type and message are preserved'
    $events = @(Read-Events | Where-Object stage -eq 'failure')
    Check ($events.Count -eq 2 -and $events[1].phase -eq 'error' -and $events[1].error -eq 'original action failure') 'failed action records error rather than success'
    $path = Join-Path $fixture 'test.jsonl'
    $locked = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        Check ((Invoke-GtaTraceStage -Stage 'locked' -Action { 'still runs' }) -eq 'still runs') 'exclusive file lock does not prevent action'
    } finally { $locked.Dispose() }
    $blocker = Join-Path $fixture 'file-as-directory'
    [IO.File]::WriteAllText($blocker, 'fixture')
    Initialize-GtaStageTrace -Component 'test' -SourcePath $source -Directory $blocker
    Check ((Invoke-GtaTraceStage -Stage 'init.failed' -Action { 42 }) -eq 42) 'failed initialization does not prevent control'
    Initialize-GtaStageTrace -Component 'test' -SourcePath $source -Directory $fixture -MaxBytes 4096 -Backups 2
    for ($i = 0; $i -lt 50; $i++) { Write-GtaStageEvent -Stage 'rotate' -Data @{ i = $i } }
    $files = @(Get-ChildItem -LiteralPath $fixture -Filter 'test.jsonl*')
    Check ($files.Count -eq 3 -and @($files | Where-Object Length -gt 4096).Count -eq 0) 'rotation limits active and backup count and size'
    foreach ($file in $files) {
        $rows = @(Get-Content -LiteralPath $file.FullName | ForEach-Object { $_ | ConvertFrom-Json })
        Check ($rows.Count -gt 0) 'rotated file retains complete JSONL records'
    }
    $originalWriter = ${function:Write-GtaStageEvent}
    function Write-GtaStageEvent { throw 'injected diagnostic failure' }
    Check ((Invoke-GtaTraceStage -Stage 'writer.failed' -Action { 'control result' }) -eq 'control result') 'unexpected writer failure cannot replace successful result'
    $caught = $null
    try { Invoke-GtaTraceStage -Stage 'both.failed' -Action { throw 'control failure' } } catch { $caught = $_ }
    Check ($caught.Exception.Message -eq 'control failure') 'writer failure cannot replace action error'
    ${function:Write-GtaStageEvent} = $originalWriter
    Write-Output "PASS stage trace cases=$checks"
} finally {
    Get-ChildItem -LiteralPath $fixture -File | Remove-Item
    Remove-Item -LiteralPath $fixture
}
