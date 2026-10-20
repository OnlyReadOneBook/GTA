#Requires -Version 5.1
# Native process queries and synthetic window snapshots only. No GUI action.
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $root 'Core\gta-turbo.ps1') -LibraryOnly
Initialize-ModeWindow
$checks = 0
function Check($Ok, [string]$Name) {
    $script:checks++
    if (-not $Ok) { throw "FAIL: $Name" }
}
function Reject([scriptblock]$Action, [string]$Name) {
    $rejected = $false
    try { $null = & $Action } catch { $rejected = $true }
    Check $rejected $Name
}
function New-Button([string]$Title, [long]$Handle, [long]$Parent = 200, [uint32]$ProcessId = 100) {
    $button = [GtaModeWindow+Snapshot]::new()
    $button.Handle = [IntPtr]$Handle
    $button.Parent = [IntPtr]$Parent
    $button.ProcessId = $ProcessId
    $button.Title = $Title
    $button.Class = 'WindowsForms10.Button.app.0.fixture'
    $button.Visible = $true
    $button.Enabled = $true
    return $button
}
function New-Group {
    return [GtaModeWindow+Snapshot[]]@(
        (New-Button 'Balanced' 201),
        (New-Button 'Turbo' 202),
        (New-Button 'Silent' 203)
    )
}

$self = [Diagnostics.Process]::GetCurrentProcess()
try {
    $identity = [GtaModeWindow]::ReadProcess([uint32]$PID)
    Check ($identity.Id -eq $PID -and -not $identity.HasExited) 'direct handle identifies the actual live test process'
    Check ($identity.StartTime.ToUniversalTime().Ticks -eq $self.StartTime.ToUniversalTime().Ticks) 'native creation time matches the process identity'
    Check ($identity.ProcessName -eq $self.ProcessName) 'native executable basename matches the running process'
    Reject { [GtaModeWindow]::ReadProcess([uint32]::MaxValue) } 'nonexistent PID cannot produce a live identity'
    $found = @([GtaModeWindow]::FindProcesses($self.ProcessName))
    $matching = @($found | Where-Object { $_.Id -eq $PID -and $_.ProcessName -eq $self.ProcessName })
    Check ($matching.Count -eq 1) 'snapshot discovery includes the current PID and name without opening inaccessible siblings'
    Check (@([GtaModeWindow]::FindProcesses('gta-mode-test-missing-' + [guid]::NewGuid().ToString('N'))).Count -eq 0) 'absent executable discovery is empty'
} finally { $self.Dispose() }

$settings = [GtaModeWindow+Snapshot]::new()
$settings.Handle = [IntPtr]1000
$settings.ProcessId = 100
$settings.Title = 'G-Helper - Fixture'
$settings.Class = 'WindowsForms10.Window.fixture'
$settings.Visible = $true
$settings.Enabled = $true
$group = New-Group
foreach ($target in 0..2) {
    $selected = [GtaModeWindow]::SelectModeButton($settings, $group, $target)
    $expected = @('Balanced', 'Turbo', 'Silent')[$target]
    Check ($selected.Title -ceq $expected -and $selected.Handle -eq $group[$target].Handle) "mode $target selects its exact native caption"
}
$withGpu = [GtaModeWindow+Snapshot[]]@($group + (New-Button 'Standard' 301 300) + (New-Button 'Ultimate' 302 300))
Check ([GtaModeWindow]::SelectModeButton($settings, $withGpu, 1).Handle -eq [IntPtr]202) 'unrelated GPU button group is ignored'
Reject { [GtaModeWindow]::SelectModeButton($settings, [GtaModeWindow+Snapshot[]]@($group[0], $group[2]), 1) } 'missing Turbo is rejected'
Reject { [GtaModeWindow]::SelectModeButton($settings, [GtaModeWindow+Snapshot[]]@($group[1]), 1) } 'one matching caption without the complete mode group is rejected'
Reject { [GtaModeWindow]::SelectModeButton($settings, [GtaModeWindow+Snapshot[]]@($group + (New-Button 'Turbo' 204)), 1) } 'duplicate Turbo is ambiguous'
$invalid = New-Group
$invalid[1].ProcessId = 101
Reject { [GtaModeWindow]::SelectModeButton($settings, $invalid, 1) } 'caption from another process is rejected'
$invalid = New-Group
$invalid[1].Class = 'WindowsForms10.Static.fixture'
Reject { [GtaModeWindow]::SelectModeButton($settings, $invalid, 1) } 'same caption on a non-button is rejected'
$invalid = New-Group
$invalid[1].Parent = [IntPtr]300
Reject { [GtaModeWindow]::SelectModeButton($settings, $invalid, 1) } 'mode captions split across direct parents are rejected'
$invalid = New-Group
$invalid[0].Parent = [IntPtr]::Zero
Reject { [GtaModeWindow]::SelectModeButton($settings, $invalid, 1) } 'mode group without a direct parent is rejected'
$invalid = New-Group
$invalid[1].Handle = $settings.Handle
Reject { [GtaModeWindow]::SelectModeButton($settings, $invalid, 1) } 'settings window cannot substitute for a mode button'
$invalid = New-Group
$invalid[1].Handle = [IntPtr]::Zero
Reject { [GtaModeWindow]::SelectModeButton($settings, $invalid, 1) } 'zero button handle is rejected'
$invalid = New-Group
$invalid[1].Title = 'Turbo '
Reject { [GtaModeWindow]::SelectModeButton($settings, $invalid, 1) } 'unverified caption variants are not guessed'
Reject { [GtaModeWindow]::SelectModeButton($settings, $group, 3) } 'unsupported target is rejected'
Write-Output "PASS native mode identity and selector cases=$checks"
