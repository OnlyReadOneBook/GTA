#Requires -Version 5.1
# No game input, foreground changes, real config, powercfg or G-Helper calls.
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $root 'Core\gta-turbo.ps1') -LibraryOnly
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('gta-mode-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
$script:MacroConfig = Join-Path $fixture 'Config.ini'
$script:Config = Join-Path $fixture 'config.json'
$script:Log = Join-Path $fixture 'watch.log'
$script:AwaySignalPath = Join-Path $fixture 'away-want'
$script:FpsWantPath = Join-Path $fixture 'fps-want'
$script:CpuPolicyKey = ''
$checks = 0
function Check($Ok, [string]$Name) { $script:checks++; if (-not $Ok) { throw "FAIL: $Name" } }
function Throws([scriptblock]$Action, [string]$Name) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    Check $failed $Name
}
function Set-FixtureAway([string]$Value, [string]$Automatic = '60') { [IO.File]::WriteAllText($script:MacroConfig, "[Settings]`r`nAwayMode=$Value`r`nAutoAwayIdleSec=$Automatic`r`n") }
function Set-FixtureMode([int]$Value) { [IO.File]::WriteAllText($script:Config, (@{ performance_mode = $Value } | ConvertTo-Json)) }
$script:senderAlive = $true; $script:senderName = 'AutoHotkey64'; $script:tickCount = 100000
function Get-ModeTickCount { return [uint64]$script:tickCount }
function Get-Process {
    param($Id, $Name, $ErrorAction)
    if ($Id -eq 42) {
        if (-not $script:senderAlive) { throw 'fixture process exited' }
        return [pscustomobject]@{ ProcessName=$script:senderName; Id=42; HasExited=$false }
    }
    return [pscustomobject]@{ ProcessName='GHelper'; Id=1; HasExited=$false; StartTime=[datetime]'2026-01-01' }
}
function Set-FixtureSignal([string]$Text) { [IO.File]::WriteAllText($script:AwaySignalPath, $Text) }
$script:afterModeWait = $null
function Start-Sleep {
    param($Milliseconds, $Seconds)
    if ($Milliseconds -eq 1200 -and $script:afterModeWait) { & $script:afterModeWait; $script:afterModeWait = $null }
}
try {
    Check ((Get-WantedGameMode $true) -eq 1) 'running GTA requires Turbo'
    Check ((Get-WantedGameMode $false) -eq 2) 'absent GTA requires Silent even on watcher startup'
    Check ((Get-WantedGameMode $true $true) -eq 2) 'idle GTA requires Silent'
    Check ((Get-WantedGameMode $false $true) -eq 2) 'game exit stays Silent while away'
    Set-FixtureAway '1'; Check (Read-AwayMode $script:MacroConfig) 'ON parses'
    Set-FixtureAway '0'; Check (-not (Read-AwayMode $script:MacroConfig)) 'OFF parses'
    foreach ($text in @('[Settings]', "[Other]`nAwayMode=1", "[Settings]`nAwayMode=1`nAwayMode=0", "[Settings]`nAwayMode=garbage")) {
        [IO.File]::WriteAllText($script:MacroConfig, $text)
        Throws { Read-AwayMode $script:MacroConfig } 'ambiguous/truncated config fails closed'
    }
    Check (Test-ModeApplied 'new Mode = 2 : OK' 2) 'ACPI success accepted'
    Check (-not (Test-ModeApplied 'Mode = 2 : Failed' 2)) 'ACPI failure rejected'
    Check (-not (Test-ModeApplied "Mode = 2 : OK`nMode = 1 : OK" 2)) 'later conflicting mode rejected'

    Set-FixtureAway '0'
    Check (-not (Get-WantedModePolicy).Away -and (Get-WantedModePolicy).CpuWanted) 'missing auto heartbeat restores normal CPU policy'
    foreach ($text in @('v1|42|85000|1|0','v1|42|100000|1|0')) {
        Set-FixtureSignal $text
        Check ((Get-WantedModePolicy).Away -and -not (Get-WantedModePolicy).CpuWanted) 'fresh live automatic heartbeat accepted including 15 second boundary'
    }
    foreach ($text in @('v1|42|84999|1|0','v1|42|100001|1|0','v1|42|-1|1|0','v1|42|18446744073709551616|1|0',
        'v2|42|100000|1|0','v1|0|100000|1|0','v1|2147483648|100000|1|0','v1|42|100000|2|0','v1|42|100000|1|2',"v1|42|100000|1|0`n",'')) {
        Set-FixtureSignal $text
        Check ($null -eq (Read-AwaySignal $script:AwaySignalPath)) 'invalid stale future or malformed signal rejected'
        Check (-not (Get-WantedModePolicy).Away -and (Get-WantedModePolicy).CpuWanted) 'bad signal does not trap user in automatic away'
    }
    Set-FixtureSignal 'v1|42|100000|1|0'; $script:senderAlive = $false
    Check ($null -eq (Read-AwaySignal $script:AwaySignalPath)) 'dead sender rejected'
    $script:senderAlive = $true; $script:senderName = 'notepad'
    Check ($null -eq (Read-AwaySignal $script:AwaySignalPath)) 'non AutoHotkey sender rejected'
    $script:senderName = 'AutoHotkey64'
    Set-FixtureAway '0' '0'
    Check (-not (Get-WantedModePolicy).Away) 'disabled automatic setting ignores automatic away request'
    Set-FixtureAway '1'; Set-FixtureSignal 'v1|42|100000|0|1'
    Check ((Get-WantedModePolicy).Away -and -not (Get-WantedModePolicy).CpuWanted) 'manual ON overrides live user-return signal'
    Set-FixtureSignal 'stale'
    Check ((Get-WantedModePolicy).Away -and -not (Get-WantedModePolicy).CpuWanted) 'manual ON survives missing invalid automatic heartbeat'
    Set-FixtureAway '0'; Set-FixtureSignal 'v1|42|100000|0|0'
    Check (-not (Get-WantedModePolicy).Away -and -not (Get-WantedModePolicy).CpuWanted) 'normal idle CPU desired remains distinct from automatic away'
    [IO.File]::WriteAllText($script:FpsWantPath, '30')
    Check (-not (Sync-AwayFpsPolicy) -and [IO.File]::ReadAllText($script:FpsWantPath) -eq '30') 'normal idle CPU policy preserves Main FPS choice'
    Set-FixtureSignal 'stale'; Set-FixtureAway '1'
    Check (-not (Sync-AwayFpsPolicy) -and [IO.File]::ReadAllText($script:FpsWantPath) -eq '30') 'manual ON never releases FPS even with stale signal'
    Set-FixtureAway '0' '0'
    Check (-not (Sync-AwayFpsPolicy)) 'disabled auto-away does not take FPS ownership'
    Set-FixtureAway '0'
    Check ((Sync-AwayFpsPolicy) -and [IO.File]::ReadAllText($script:FpsWantPath) -eq '0') 'dead automatic heartbeat atomically releases lingering 30 FPS'
    Check (-not (Sync-AwayFpsPolicy)) 'already released FPS is not rewritten'
    [IO.File]::WriteAllText($script:FpsWantPath, '60')
    Check (-not (Sync-AwayFpsPolicy) -and [IO.File]::ReadAllText($script:FpsWantPath) -eq '60') 'non-away FPS limits are preserved'
    [IO.File]::WriteAllText($script:FpsWantPath, '30')
    $lock = [IO.File]::Open($script:FpsWantPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try { Throws { Sync-AwayFpsPolicy } 'FPS request access failure propagates for retry' } finally { $lock.Dispose() }
    Check (Sync-AwayFpsPolicy) 'FPS release retries successfully after access failure clears'
    Set-FixtureSignal 'v1|42|100000|1|0'
    Check ((Sync-AwayFpsPolicy) -eq '30' -and [IO.File]::ReadAllText($script:FpsWantPath) -eq '30') 'fresh idle signal caps FPS without waiting for any Main power timer'
    Check ($null -eq (Sync-AwayFpsPolicy)) 'unchanged idle request is not rewritten'
    Set-FixtureSignal 'v1|42|100000|0|1'
    Check ((Sync-AwayFpsPolicy) -eq '0' -and [IO.File]::ReadAllText($script:FpsWantPath) -eq '0') 'live user return releases FPS without waiting for Main'
    Set-FixtureSignal 'v1|42|100000|0|0'; [IO.File]::WriteAllText($script:FpsWantPath, '60')
    Check ($null -eq (Sync-AwayFpsPolicy) -and [IO.File]::ReadAllText($script:FpsWantPath) -eq '60') 'normal idle CPU state preserves configured non-away FPS'
    Set-FixtureAway '0' '0'; Set-FixtureSignal 'v1|42|100000|1|0'
    Check ($null -eq (Sync-AwayFpsPolicy) -and [IO.File]::ReadAllText($script:FpsWantPath) -eq '60') 'disabled automatic mode leaves normal FPS untouched'
    Set-FixtureAway '1'; Set-FixtureSignal 'stale'
    Check ((Sync-AwayFpsPolicy) -eq '30') 'manual away applies FPS without a heartbeat'
    [IO.File]::Delete($script:FpsWantPath)
    Check ((Sync-AwayFpsPolicy) -eq '30' -and [IO.File]::ReadAllText($script:FpsWantPath) -eq '30') 'missing request is created atomically for manual away'
    Set-FixtureAway '0'; Set-FixtureSignal 'v1|42|100000|1|0'; [IO.File]::WriteAllText($script:FpsWantPath, '0')
    $realPolicy = ${function:Get-WantedModePolicy}; $script:policyReads = 0
    function Get-WantedModePolicy {
        $script:policyReads++
        if ($script:policyReads -eq 2) { Set-FixtureSignal 'v1|42|100000|0|1' }
        & $realPolicy
    }
    Check ($null -eq (Sync-AwayFpsPolicy) -and [IO.File]::ReadAllText($script:FpsWantPath) -eq '0') 'user return before atomic commit cancels an obsolete idle cap'
    ${function:Get-WantedModePolicy} = $realPolicy
    Set-FixtureSignal 'stale'

    # Replace only boundaries, exercising the real process policy and orchestration.
    $script:setCalls = 0; $script:cpuCalls = 0; $script:failMode = $false; $script:failCpu = $false
    $realSet = ${function:Set-GHelperMode}
    $realCpu = ${function:Set-ModeCpuPolicy}
    function Set-GHelperMode([int]$Target) {
        $script:setCalls++
        if ($script:failMode) { throw 'fixture ACPI failure' }
        $changed = (Get-Mode) -ne $Target
        Set-FixtureMode $Target
        return $changed
    }
    function Set-ModeCpuPolicy([bool]$Enabled) {
        $script:cpuCalls++
        $script:lastCpu = $Enabled
        if ($script:failCpu) { throw 'fixture CPU failure' }
    }
    Set-FixtureMode 1; Set-FixtureAway '1'; $script:failMode = $true
    [IO.File]::WriteAllText($script:FpsWantPath, '0')
    Throws { Invoke-ModeTick $true } 'failed Silent application is not successful'
    Check ([IO.File]::ReadAllText($script:FpsWantPath) -eq '30') 'G-Helper failure cannot block independent FPS synchronization'
    $script:failMode = $false; $script:failCpu = $true
    Throws { Invoke-ModeTick $true } 'CPU reassert failure is reported'
    $script:failCpu = $false
    Invoke-ModeTick $true
    Check ($script:cpuCalls -eq 2 -and (Get-Mode) -eq 2) 'CPU retry preserves manual Silent with GTA present'
    Check (-not $script:lastCpu) 'manual away CPU policy remains independent'
    Set-FixtureAway '0'; Set-FixtureSignal 'v1|42|100000|1|0'
    Invoke-ModeTick $true
    Check ((Get-Mode) -eq 2 -and -not $script:lastCpu) 'automatic away applies Silent and limits CPU'
    Set-FixtureSignal 'v1|42|100000|0|1'
    Invoke-ModeTick $true
    Check ((Get-Mode) -eq 1 -and $script:lastCpu) 'live user return restores Turbo and CPU boost'
    Set-FixtureSignal 'v1|42|100000|1|0'
    Invoke-ModeTick $true
    Check ((Get-Mode) -eq 2 -and -not $script:lastCpu) 'next idle period returns to Silent'
    Set-FixtureSignal 'stale'
    Invoke-ModeTick $true
    Check ((Get-Mode) -eq 1 -and $script:lastCpu) 'expired heartbeat releases automatic Silent and restores Turbo'
    $script:failMode = $true
    Throws { Invoke-ModeTick $false } 'failed game-exit Silent application is retried'
    $script:failMode = $false
    Invoke-ModeTick $false; Invoke-ModeTick $false
    Check ((Get-Mode) -eq 2 -and -not $script:lastCpu) 'absent game converges to Silent with CPU boost off'
    Invoke-ModeTick $true
    Check ((Get-Mode) -eq 1) 'next game start switches to Turbo without a restore state file'
    Set-FixtureMode 0; Invoke-ModeTick $true
    Check ((Get-Mode) -eq 1) 'manual profile drift converges to requested running-game policy'
    Set-FixtureAway ''
    Throws { Invoke-ModeTick $false } 'invalid CPU settings are reported separately'
    Check ((Get-Mode) -eq 2) 'invalid macro config cannot prevent game-exit Silent profile'
    Set-FixtureAway '0'

    # Native and UIA boundaries are replaced, so the real orchestration cannot
    # show a window, activate anything, touch power settings or synthesize input.
    $source = [IO.File]::ReadAllText((Join-Path $root 'Core\gta-turbo.ps1'))
    Check ($source -notmatch 'SendInput|keybd_event|mouse_event|SetForegroundWindow|Send-ModeHotkey|GetAsyncKeyState') 'production controller contains no input or activation API'
    Check ($source -notmatch 'InvokePattern|\.Invoke\(') 'UIA is observation only and never invokes or focuses a button'
    Check ($source -match 'SendMessageTimeout\(parent.Handle, 0x0111, wParam, button.Handle, 0x23, 1500, out result\)') 'documented WM_COMMAND notification goes to direct parent with button HWND and bounded 1500ms wait'
    Check ($source -notmatch '0x00F5|0x2111') 'no ineffective BM_CLICK or private reflected message is sent'
    Check ($source -match 'GetParent\(button.Handle\) != parent.Handle' -and $source -match 'GetDlgCtrlID\(button.Handle\)') 'notification parent and control ID come from observed native button'
    Check ($source -match 'ShowWindow\(saved.Handle, 4\)' -and $source -match 'ShowWindow\(saved.Handle, 0\)' -and $source -match '0x215') 'lazy WinForms controls use nonactivating show and hide with position preserved'
    Initialize-ModeWindow # Compile only. No native method is called by this test.
    Check ([GtaModeWindow]::ClickNotificationParameter(0x12345678).ToUInt64() -eq 0x5678) 'WM_COMMAND control ID truncates to unsigned low word and leaves BN_CLICKED high word zero'
    Check ([GtaModeWindow]::ClickNotificationParameter(-1).ToUInt64() -eq 65535) 'signed native control ID is packed without sign extension'
    Check ([GtaModeWindow]::ClickNotificationParameter([int]::MinValue).ToUInt64() -eq 0) 'negative high-bit control ID keeps exactly its low word'
    Check ([GtaModeWindow]::ClickNotificationParameter(0).ToUInt64() -eq 0) 'zero control ID is represented without inventing an identifier'
    $settingsIdentity = [GtaModeWindow+Snapshot]::new()
    $settingsIdentity.Handle = [IntPtr]66914; $settingsIdentity.ProcessId = 14080
    $buttonIdentity = [GtaModeWindow+Snapshot]::new()
    $buttonIdentity.Handle = [IntPtr]216334424; $buttonIdentity.ProcessId = 14080
    $buttonIdentity.Class = 'WindowsForms10.Button.app.0.5c39d4_r3_ad1'; $buttonIdentity.Visible = $true
    Check ([GtaModeWindow]::MatchesButton($settingsIdentity,$buttonIdentity,$true,$true)) 'live Turbo button class and identity accepted without invoking native API'
    Check (-not [GtaModeWindow]::MatchesButton($settingsIdentity,$buttonIdentity,$false,$true)) 'button outside identified Settings ancestry rejected'
    Check (-not [GtaModeWindow]::MatchesButton($settingsIdentity,$buttonIdentity,$true,$false)) 'disabled button rejected'
    $buttonIdentity.ProcessId = 22
    Check (-not [GtaModeWindow]::MatchesButton($settingsIdentity,$buttonIdentity,$true,$true)) 'wrong process button rejected'
    $buttonIdentity.ProcessId = 14080; $buttonIdentity.Handle = [IntPtr]::Zero
    Check (-not [GtaModeWindow]::MatchesButton($settingsIdentity,$buttonIdentity,$true,$true)) 'zero native handle rejected'
    $buttonIdentity.Handle = $settingsIdentity.Handle
    Check (-not [GtaModeWindow]::MatchesButton($settingsIdentity,$buttonIdentity,$true,$true)) 'Settings HWND itself is never a click target'
    $buttonIdentity.Handle = [IntPtr]216334424; $buttonIdentity.Visible = $false
    Check (-not [GtaModeWindow]::MatchesButton($settingsIdentity,$buttonIdentity,$true,$true)) 'hidden button rejected'
    $buttonIdentity.Visible = $true; $buttonIdentity.Class = 'WindowsForms10.Window.8.app.0.5c39d4_r3_ad1'
    Check (-not [GtaModeWindow]::MatchesButton($settingsIdentity,$buttonIdentity,$true,$true)) 'non-button native class rejected'
    $settingsIdentity.Enabled = $true; $settingsIdentity.Visible = $true; $buttonIdentity.Enabled = $true
    $ancestorIdentity = [GtaModeWindow+Snapshot]::new()
    $ancestorIdentity.Handle = [IntPtr]54267048; $ancestorIdentity.ProcessId = 14080
    $ancestorIdentity.Enabled = $true; $ancestorIdentity.Visible = $true
    $ancestorPath = [GtaModeWindow+Snapshot[]]@($buttonIdentity,$ancestorIdentity,$settingsIdentity)
    Check ([GtaModeWindow]::MatchesEnabledAncestors($settingsIdentity,$buttonIdentity,$ancestorPath)) 'enabled visible button ancestry accepted'
    $settingsIdentity.Enabled = $false
    Check (-not [GtaModeWindow]::MatchesEnabledAncestors($settingsIdentity,$buttonIdentity,$ancestorPath)) 'live Update-modal case rejects enabled button with disabled Settings ancestor'
    $settingsIdentity.Enabled = $true; $ancestorIdentity.Enabled = $false
    Check (-not [GtaModeWindow]::MatchesEnabledAncestors($settingsIdentity,$buttonIdentity,$ancestorPath)) 'disabled intermediate parent rejects click'
    $ancestorIdentity.Enabled = $true; $ancestorIdentity.Visible = $false
    Check (-not [GtaModeWindow]::MatchesEnabledAncestors($settingsIdentity,$buttonIdentity,$ancestorPath)) 'hidden intermediate parent rejects click'
    $ancestorIdentity.Visible = $true; $ancestorIdentity.ProcessId = 22
    Check (-not [GtaModeWindow]::MatchesEnabledAncestors($settingsIdentity,$buttonIdentity,$ancestorPath)) 'changed ancestor process rejects click'
    $ancestorIdentity.ProcessId = 14080
    Check (-not [GtaModeWindow]::MatchesEnabledAncestors($settingsIdentity,$buttonIdentity,([GtaModeWindow+Snapshot[]]@($buttonIdentity,$ancestorIdentity)))) 'ancestor chain must reach identified Settings window'
    $script:windowFixtures = @(
        @{ Handle=[IntPtr]66914; ProcessId=1; Title='G-Helper - ASUS TUF Gaming A14 FA401UV'; Class='WindowsForms10.Window.8.app.0.5c39d4_r3_ad1'; Visible=$false; Minimized=$false; Enabled=$true },
        @{ Handle=[IntPtr]89198232; ProcessId=1; Title='Update'; Class='#32770'; Visible=$true; Minimized=$false },
        @{ Handle=[IntPtr]30; ProcessId=2; Title='G-Helper - another instance'; Class='WindowsForms10.Window.8'; Visible=$true; Minimized=$false })
    function Get-ModeWindows([int]$ProcessId) { return $script:windowFixtures }
    Check ((Get-ModeSettingsWindow (Get-Process -Name GHelper)).Handle -eq [IntPtr]66914) 'real G-Helper hyphenated title selects only correct process settings and excludes Update dialog'
    $script:windowFixtures[0].Enabled = $false
    Throws { Get-ModeSettingsWindow (Get-Process -Name GHelper) } 'disabled Settings defers before any window preparation'
    $script:windowFixtures[0].Enabled = $true
    $script:windowFixtures[0].Minimized = $true
    Throws { Get-ModeSettingsWindow (Get-Process -Name GHelper) } 'user minimized settings are not restored implicitly'
    $script:windowFixtures[0].Minimized = $false
    $script:windowFixtures += $script:windowFixtures[0].Clone()
    Throws { Get-ModeSettingsWindow (Get-Process -Name GHelper) } 'ambiguous settings windows are rejected'
    $realInvoke = ${function:Invoke-GHelperModeButton}
    function Reset-UiFixture {
        $script:uiDesktop = @(10,10,10,10); $script:desktopIndex = 0
        $script:uiAvailable = $true; $script:uiForegroundPid = 50; $script:uiVisible = $false
        $script:prepareCalls = 0; $script:restoreCalls = 0; $script:buttonCalls = 0
        $script:failPrepare = $false; $script:failButton = $false; $script:failInvoke = $false; $script:failRestore = $false
    }
    function Get-ModeDesktopState {
        $value = $script:uiDesktop[[Math]::Min($script:desktopIndex++, $script:uiDesktop.Count - 1)]
        return @{ Foreground=[IntPtr]$value; ProcessId=$script:uiForegroundPid; Available=$script:uiAvailable }
    }
    function Get-ModeSettingsWindow($Helper) { return @{ Handle=[IntPtr]20; ProcessId=1; Visible=$script:uiVisible } }
    function Prepare-ModeSettingsWindow($Window) { $script:prepareCalls++; if ($script:failPrepare) { throw 'fixture partial preparation failure' } }
    function Restore-ModeSettingsWindow($Window) { $script:restoreCalls++; if ($script:failRestore) { throw 'fixture restore failure' } }
    function Get-ModeButton($Window, [int]$Target) { if ($script:failButton) { throw 'fixture ambiguous button' }; return @{ Target=$Target } }
    function Invoke-ModeButton($Button) { $script:buttonCalls++; if ($script:failInvoke) { throw 'fixture BN_CLICKED timeout' } }
    $helper = Get-Process -Name GHelper
    Reset-UiFixture
    Invoke-GHelperModeButton 2 $helper
    Check ($script:prepareCalls -eq 1 -and $script:restoreCalls -eq 1 -and $script:buttonCalls -eq 1) 'hidden UI is prepared invoked and restored once without foreground changes'
    Check ([IO.File]::ReadAllText($script:Log) -match 'before=10 ready=10 invoked=10 final=10') 'all observed foreground values are logged'
    Reset-UiFixture; $script:uiVisible = $true
    Invoke-GHelperModeButton 1 $helper
    Check ($script:prepareCalls -eq 0 -and $script:restoreCalls -eq 0 -and $script:buttonCalls -eq 1) 'already visible user window is not moved or hidden'
    foreach ($failure in @('failPrepare','failButton','failInvoke','failRestore')) {
        Reset-UiFixture; Set-Variable -Name $failure -Scope Script -Value $true
        Throws { Invoke-GHelperModeButton 2 $helper } "UI $failure is reported"
        Check ($script:restoreCalls -eq 1) "UI $failure still attempts original state restoration"
    }
    Reset-UiFixture; $script:uiAvailable = $false
    Throws { Invoke-GHelperModeButton 2 $helper } 'locked or UAC desktop defers'
    Check ($script:prepareCalls -eq 0 -and $script:buttonCalls -eq 0) 'secure desktop is never prepared or invoked'
    Reset-UiFixture; $script:uiForegroundPid = 1
    Throws { Invoke-GHelperModeButton 2 $helper } 'user working in G-Helper defers'
    Check ($script:prepareCalls -eq 0 -and $script:buttonCalls -eq 0) 'foreground G-Helper untouched'
    Reset-UiFixture; $script:uiDesktop = @(10,11,11)
    Throws { Invoke-GHelperModeButton 2 $helper } 'foreground race before invocation cancels mode change'
    Check ($script:buttonCalls -eq 0 -and $script:restoreCalls -eq 1) 'foreground race restores prepared UI without activation or invocation'
    Reset-UiFixture; $script:uiDesktop = @(10,10,11,11)
    Throws { Invoke-GHelperModeButton 2 $helper } 'foreground change during invocation is reported'
    Check ($script:restoreCalls -eq 1) 'unexpected foreground change still cleans prepared window'

    ${function:Set-GHelperMode} = $realSet
    $script:sendCalls = 0
    $script:ackConfig = $true; $script:ackLog = $true
    function Invoke-GHelperModeButton([int]$Target, $Helper) {
        $script:sendCalls++
        $script:LastModeAttemptKey = "$($Helper.Id):$($Helper.StartTime.Ticks):$Target"
        $script:NextModeAttempt = (Get-Date).AddMinutes(5)
        if ($script:ackConfig) { Set-FixtureMode $Target }
        if ($script:ackLog) { Add-Content -LiteralPath (Join-Path $fixture 'log.txt') "new Mode = $Target : OK" }
    }
    $script:clock = [datetime]'2026-01-01'; $script:clockStep = 0
    function Get-Date { param([string]$Format); if ($Format) { return $script:clock.ToString($Format) }; $result=$script:clock; $script:clock=$script:clock.AddSeconds($script:clockStep); return $result }
    $script:LastModeAttemptKey = ''
    Set-FixtureMode 1; [IO.File]::WriteAllText((Join-Path $fixture 'log.txt'), "old Mode = 1 : OK`r`n")
    Check (Set-GHelperMode 2) 'real acknowledgement checker requires new success and config'
    Check (-not (Set-GHelperMode 2)) 'steady Silent does not generate more input'
    Check ($script:sendCalls -eq 1) 'one BN_CLICKED request across repeated checks'
    [IO.File]::WriteAllText($script:Config, '{"performance_mode":1,"skip_hotkeys":1}')
    Check (Set-GHelperMode 2) 'disabled shortcuts do not prevent explicit BN_CLICKED button operation'
    Check ($script:sendCalls -eq 2) 'BN_CLICKED does not depend on shortcut configuration'
    Set-FixtureMode 1; $script:ackLog = $false; $script:clockStep = 3
    Throws { Set-GHelperMode 2 } 'config alone without new ACPI ACK is rejected'
    $beforeCalls = $script:sendCalls
    Throws { Set-GHelperMode 2 } 'uncertain BN_CLICKED request is throttled for five minutes'
    Check ($script:sendCalls -eq $beforeCalls) 'pending ACK never repeatedly invokes UI'
    Add-Content -LiteralPath (Join-Path $fixture 'log.txt') 'late Mode = 2 : OK'
    Check (Set-GHelperMode 2) 'late new ACPI ACK completes pending request without another invocation'
    Check ($script:sendCalls -eq $beforeCalls -and $script:LastModeAttemptKey -eq '') 'late ACK clears retry state and preserves single invocation'
    $script:LastModeAttemptKey = ''; $script:ackLog = $true; $script:ackConfig = $false
    Set-FixtureMode 1
    Throws { Set-GHelperMode 2 } 'new ACPI ACK without matching config is rejected'

    ${function:Set-ModeCpuPolicy} = $realCpu
    $script:powerCalls = @(); $script:powerFailure = $false
    function powercfg {
        $script:powerCalls += ,@($args)
        $global:LASTEXITCODE = if ($script:powerFailure) { 1 } else { 0 }
    }
    Set-ModeCpuPolicy $true
    Check ($script:powerCalls.Count -eq 5) 'normal CPU restoration applies AC DC maximum boost and active scheme'
    Check ($script:powerCalls[0][-1] -eq 100 -and $script:powerCalls[2][-1] -eq 100) 'normal maximum is 100 on AC and DC'
    Check ($script:powerCalls[1][-1] -eq 2 -and $script:powerCalls[3][-1] -eq 1) 'normal boost matches Main AC 2 and DC 1'
    $script:powerCalls = @(); Set-ModeCpuPolicy $false
    Check ($script:powerCalls[0][-1] -eq 99 -and $script:powerCalls[2][-1] -eq 99 -and $script:powerCalls[1][-1] -eq 0 -and $script:powerCalls[3][-1] -eq 0) 'away CPU uses 99 maximum and disabled boost'
    $script:powerFailure = $true
    Throws { Set-ModeCpuPolicy $true } 'power failure is not marked applied'

    # Frame parsing is pure; the live feed must stay one long-lived session.
    Check ((Format-Fps (@(20.0) * 20)) -eq '50.0,50.0') 'frame samples give average and low FPS'
    Check ((Format-Fps (@(20.0) * 5)) -eq ',') 'too few frames give empty FPS'
    $fpsSource = (Get-Command New-FrameFeed).Definition
    Check ($fpsSource -match '--output_stdout' -and $fpsSource -notmatch '--timed') 'FPS launch streams without a timed termination'
    $script:FrameFeed = $null; Check ($null -eq (Get-FrameFeed $false)) 'feed stops when game is not running'
    Write-Output "PASS G-Helper process policy cases=$checks"
} finally {
    # Fixture only, never the real game or user settings.
    Get-ChildItem -LiteralPath $fixture -File | Remove-Item
    Remove-Item -LiteralPath $fixture
}
