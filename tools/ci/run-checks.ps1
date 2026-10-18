#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$AhkPath,
    [string]$PythonPath = 'python',
    [string]$OutputDirectory = (Join-Path $env:TEMP ('gta-ci-' + [guid]::NewGuid().ToString('N'))),
    [string[]]$ChangedFiles,
    [string]$ChangedFilesPath = ''
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $outputPath) {
    if (@(Get-ChildItem -LiteralPath $outputPath -Force).Count) { throw 'Choose a new or empty results directory.' }
} else {
    $null = New-Item -ItemType Directory -Path $outputPath
}
$results = New-Object 'System.Collections.Generic.List[object]'
$failure = $null
$revision = $null
$workingTree = $null
$runtimeVersion = $null
$runtimeHash = $null
$sourceHashes = @()
$ahkSuites = @('test-earner', 'test-earnledger', 'test-antiafk', 'test-altf4teleport', 'test-botwarp-stop', 'test-claw-stop', 'test-autoclick-stop', 'test-held-keys', 'test-earnnav', 'test-earntasks', 'test-earnblip',
    'test-earnpolicy', 'test-earnscreen', 'test-earnscreen-command', 'test-earnvinewood', 'test-earnwarehouse-read', 'test-earnwarehouse',
    'test-earnstaff', 'test-afk-notification-command', 'test-afk-input-lock', 'test-arrow-color', 'test-cpuboost', 'test-discord-hud', 'test-discordhud-launch', 'test-overlay-place', 'test-memguard', 'test-earndj', 'test-phone-call-template')
$allAuxChecks = @(
    'test-earnocr', 'test-mct-seated-template', 'test-bunker-templates', 'test-dj-templates', 'test-earnwarehouse-templates', 'test-afk-overlays', 'test-notification-dismiss', 'test-session-guard', 'test-gui-input', 'test-perf-watch', 'test-fps-helper', 'test-screen-capture', 'test-gta-mode')
$selectionScript = Join-Path $PSScriptRoot 'check-selection.ps1'
. $selectionScript
if ($ChangedFilesPath) {
    $changedFiles = @(Get-Content -LiteralPath $ChangedFilesPath -Encoding UTF8)
    $checkPlan = Get-CiCheckPlan $changedFiles
} elseif ($PSBoundParameters.ContainsKey('ChangedFiles')) {
    $changedFiles = @($ChangedFiles)
    $checkPlan = Get-CiCheckPlan $changedFiles
} else {
    $changedFiles = @()
    $checkPlan = Get-CiCheckPlan @() -Full
}
$selectedSuites = @($checkPlan.Suites)
$verificationScope = if ($checkPlan.Full) { 'full' } else { 'targeted' }
$expectedChecks = @('syntax-powershell', 'syntax-python', 'validate-main', 'test-check-selection') + $selectedSuites
$started = [DateTime]::UtcNow
. (Join-Path $PSScriptRoot 'common.ps1')

function Quote-NativeArgument([string]$Value) {
    # Windows CommandLineToArgvW quoting, including spaces and trailing backslashes.
    return '"' + ([regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
}

function Stop-CheckProcessTree([Diagnostics.Process]$Process, [DateTime]$Started) {
    # Snapshot descendants of this exact process only. Never select by executable name.
    $owned = New-Object 'System.Collections.Generic.List[object]'
    $owned.Add([pscustomobject]@{ id = $Process.Id; started = $Started })
    $snapshot = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    for ($index = 0; $index -lt $owned.Count; $index++) {
        $parent = $owned[$index]
        foreach ($child in $snapshot) {
            if ($child.ParentProcessId -eq $parent.id -and $child.CreationDate -ge $parent.started -and
                $child.ProcessId -notin $owned.id) {
                $owned.Add([pscustomobject]@{ id = $child.ProcessId; started = $child.CreationDate })
            }
        }
    }
    # Stop the parent first to prevent it launching more children during cleanup.
    foreach ($item in $owned) {
        $target = Get-Process -Id $item.id -ErrorAction SilentlyContinue
        if ($target) {
            try {
                # A PID may have been recycled after the snapshot.
                if ([Math]::Abs(($target.StartTime - $item.started).TotalMilliseconds) -lt 10) {
                    $target.Kill()
                    $null = $target.WaitForExit(3000)
                }
            } finally { $target.Dispose() }
        }
    }
}

function Invoke-LoggedCheck {
    param([string]$Name, [string]$Executable, [string[]]$Arguments, [int]$TimeoutSeconds = 90, [switch]$RequireEmptyStderr)
    $stdoutPath = Join-Path $outputPath ($Name + '.stdout.log')
    $stderrPath = Join-Path $outputPath ($Name + '.stderr.log')
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = ($Arguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' '
    $info.WorkingDirectory = $repositoryRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $exitCode = $null
    $timedOut = $false
    $process = $null
    $stdout = ''
    $stderr = ''
    try {
        $process = [Diagnostics.Process]::Start($info)
        # Keep the root identity even if it exits before a child closes the inherited pipes.
        $processStarted = $process.StartTime
        # Drain both pipes while the child is running, so verbose failures cannot deadlock.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            Stop-CheckProcessTree $process $processStarted
        }
        $drained = [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutTask, $stderrTask), 5000)
        if (-not $drained) {
            try { Stop-CheckProcessTree $process $processStarted }
            finally {
                $process.StandardOutput.Close()
                $process.StandardError.Close()
            }
            throw 'Output pipes did not close within five seconds after process exit/cleanup.'
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
    } catch {
        $stderr += $_.Exception.ToString()
    } finally {
        $watch.Stop()
        if ($process) { $process.Dispose() }
        [IO.File]::WriteAllText($stdoutPath, $stdout, (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($stderrPath, $stderr, (New-Object Text.UTF8Encoding($false)))
        $passed = $null -ne $exitCode -and $exitCode -eq 0 -and -not $timedOut -and
            (-not $RequireEmptyStderr -or $stderr.Length -eq 0)
        $results.Add([ordered]@{
            name = $Name; passed = $passed; exitCode = $exitCode; timedOut = $timedOut
            seconds = [Math]::Round($watch.Elapsed.TotalSeconds, 3)
            executable = $Executable; arguments = $Arguments
            stdout = $stdoutPath; stderr = $stderrPath
        })
        Write-Host (('{0}: {1} (exit={2})' -f $Name, $(if ($passed) { 'PASS' } else { 'FAIL' }), $exitCode))
        if ($stdout.Trim()) { Write-Host $stdout.Trim() }
        if ($stderr.Trim()) { Write-Host $stderr.Trim() }
    }
}

try {
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) {
        throw 'Run with Windows PowerShell 5.1 (powershell.exe), not pwsh.'
    }
    $pin = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'autohotkey.json') -Raw | ConvertFrom-Json
    $AhkPath = (Resolve-Path -LiteralPath $AhkPath).Path
    $runtimeVersion = (Get-Item -LiteralPath $AhkPath).VersionInfo.ProductVersion
    $runtimeHash = (Get-FileHash -LiteralPath $AhkPath -Algorithm SHA256).Hash
    if ($runtimeVersion -ne $pin.version -or $runtimeHash -cne $pin.executableSha256) {
        throw 'AutoHotkey does not match tools/ci/autohotkey.json. Use install-autohotkey.ps1.'
    }
    $python = (Get-Command -Name $PythonPath -CommandType Application -ErrorAction Stop).Source
    $powershell = Join-Path $PSHOME 'powershell.exe'
    $revision = (& git -C $repositoryRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the Git revision.' }
    $workingTree = @(& git -C $repositoryRoot status --porcelain=v1)
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the Git working-tree status.' }
    $sourceHashes = Get-MacroHashes $repositoryRoot
    $psArguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File')
    Invoke-LoggedCheck 'syntax-powershell' $powershell ($psArguments + @((Join-Path $PSScriptRoot 'check-powershell.ps1'), '-RepositoryRoot', $repositoryRoot))
    Invoke-LoggedCheck 'syntax-python' $python @((Join-Path $PSScriptRoot 'check-python.py'), $repositoryRoot)
    # /validate returns before AutoExecSection and before replacing an existing instance.
    # The verified 2.0.28 interpreter never executes Main.ahk here.
    Invoke-LoggedCheck 'validate-main' $AhkPath @('/validate', '/ErrorStdOut', '/CP65001', (Join-Path $repositoryRoot 'Main.ahk')) 30 -RequireEmptyStderr
    # Explicit allowlist: never discover/run arbitrary *test* scripts or Main.ahk.
    Invoke-LoggedCheck 'test-check-selection' $powershell ($psArguments + @((Join-Path $PSScriptRoot 'test-check-selection.ps1')))
    foreach ($suite in $ahkSuites) {
        if ($suite -notin $selectedSuites) { continue }
        $scriptPath = Join-Path $repositoryRoot ('tools\earn-test\' + $suite + '.ps1')
        Invoke-LoggedCheck $suite $powershell ($psArguments + @($scriptPath, '-AhkPath', $AhkPath))
    }
    if ('test-earnocr' -in $selectedSuites) { Invoke-LoggedCheck 'test-earnocr' $powershell ($psArguments + @((Join-Path $repositoryRoot 'tools\earn-test\test-earnocr.ps1'))) }
    if ('test-notification-dismiss' -in $selectedSuites) { Invoke-LoggedCheck 'test-notification-dismiss' $powershell ($psArguments + @((Join-Path $repositoryRoot 'tools\earn-test\test-notification-dismiss.ps1'))) }
    if ('test-mct-seated-template' -in $selectedSuites) { Invoke-LoggedCheck 'test-mct-seated-template' $powershell ($psArguments + @((Join-Path $repositoryRoot 'tools\earn-test\test-mct-seated-template.ps1'))) }
    if ('test-bunker-templates' -in $selectedSuites) { Invoke-LoggedCheck 'test-bunker-templates' $powershell ($psArguments + @((Join-Path $repositoryRoot 'tools\earn-test\test-bunker-templates.ps1'))) }
    if ('test-dj-templates' -in $selectedSuites) { Invoke-LoggedCheck 'test-dj-templates' $powershell ($psArguments + @((Join-Path $repositoryRoot 'tools\earn-test\test-dj-templates.ps1'))) }
    if ('test-earnwarehouse-templates' -in $selectedSuites) { Invoke-LoggedCheck 'test-earnwarehouse-templates' $powershell ($psArguments + @((Join-Path $repositoryRoot 'tools\earn-test\test-earnwarehouse-templates.ps1'))) }
    if ('test-afk-overlays' -in $selectedSuites) { Invoke-LoggedCheck 'test-afk-overlays' $powershell ($psArguments + @((Join-Path $repositoryRoot 'tools\earn-test\test-afk-overlays.ps1'))) }
    if ('test-session-guard' -in $selectedSuites) { Invoke-LoggedCheck 'test-session-guard' $AhkPath @('/ErrorStdOut', '/CP65001', (Join-Path $repositoryRoot 'tools\earn-test\test-session-guard.ahk')) 30 }
    if ('test-gui-input' -in $selectedSuites) { Invoke-LoggedCheck 'test-gui-input' $AhkPath @('/ErrorStdOut', '/CP65001', (Join-Path $repositoryRoot 'tools\earn-test\gui-input.ahk'), '--self-test') 30 }
    if ('test-perf-watch' -in $selectedSuites) { Invoke-LoggedCheck 'test-perf-watch' $powershell ($psArguments + @(
        (Join-Path $repositoryRoot 'tools\tests\gta-perf-watch.tests.ps1'),
        '-FixtureDir', (Join-Path $outputPath 'perf-fixtures')
    )) }
    if ('test-fps-helper' -in $selectedSuites) { Invoke-LoggedCheck 'test-fps-helper' $powershell ($psArguments + @(
        (Join-Path $repositoryRoot 'tools\tests\fps-helper.tests.ps1')
    )) }
    if ('test-screen-capture' -in $selectedSuites) { Invoke-LoggedCheck 'test-screen-capture' $powershell ($psArguments + @(
        (Join-Path $repositoryRoot 'tools\tests\screen-capture.tests.ps1'), '-AhkPath', $AhkPath
    )) }
    if ('test-gta-mode' -in $selectedSuites) { Invoke-LoggedCheck 'test-gta-mode' $powershell ($psArguments + @(
        (Join-Path $repositoryRoot 'tools\tests\gta-mode.tests.ps1')
    )) }
    if (($sourceHashes | ConvertTo-Json -Compress) -cne ((Get-MacroHashes $repositoryRoot) | ConvertTo-Json -Compress)) {
        throw 'Package source files changed during verification.'
    }
} catch {
    $failure = $_.Exception.ToString()
    Write-Host $failure
} finally {
    $failedChecks = @($results | Where-Object { -not $_.passed })
    $missingChecks = @($expectedChecks | Where-Object { $_ -notin $results.name })
    $passed = -not $failure -and $results.Count -eq $expectedChecks.Count -and
        $failedChecks.Count -eq 0 -and $missingChecks.Count -eq 0
    [ordered]@{
        passed = $passed; revision = $revision; workingTree = $workingTree
        selectedPlan = [ordered]@{ full = $checkPlan.Full; suites = $selectedSuites; packageRequired = $checkPlan.PackageRequired; changedFiles = $changedFiles }
        verificationScope = $verificationScope
        startedUtc = $started.ToString('o'); finishedUtc = [DateTime]::UtcNow.ToString('o')
        powershell = $PSVersionTable.PSVersion.ToString()
        autoHotkeyVersion = $runtimeVersion; autoHotkeySha256 = $runtimeHash
        repositoryRoot = $repositoryRoot; failure = $failure; missingChecks = $missingChecks
        checks = @($results.ToArray()); sources = $sourceHashes
    } | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $outputPath 'results.json') -Encoding UTF8
    Write-Host ('Results: ' + (Join-Path $outputPath 'results.json'))
}
if (-not $passed) { exit 1 }
