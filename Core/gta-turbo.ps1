#Requires -Version 5.1
# Canonical source for the existing Startup/GTA Turbo.lnk watcher.
# Dot-source with -LibraryOnly for input-free policy tests.
[CmdletBinding()]
param(
    [string]$MacroConfig = (Join-Path $env:USERPROFILE 'GTA\Config.ini'),
    [switch]$LibraryOnly
)

function Read-ModeSettings([string]$Path) {
    $section = ''; $values = @(); $automatic = @()
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*\[([^]]+)\]\s*$') { $section = $Matches[1]; continue }
        if ($section -eq 'Settings' -and $line -match '^\s*AwayMode\s*=(.*)$') {
            $values += $Matches[1].Trim()
        }
        if ($section -eq 'Settings' -and $line -match '^\s*AutoAwayIdleSec\s*=(.*)$') {
            $automatic += $Matches[1].Trim()
        }
    }
    # Never interpret an incomplete/unreadable save as permission to leave Silent.
    if ($values.Count -ne 1 -or $values[0] -notmatch '^[01]$') { throw 'AwayMode must occur once in [Settings] with value 0 or 1.' }
    if ($automatic.Count -gt 1 -or ($automatic.Count -eq 1 -and $automatic[0] -notmatch '^\d{1,8}$')) {
        throw 'AutoAwayIdleSec must be a nonnegative integer in [Settings].'
    }
    return @{ Manual = ($values[0] -eq '1'); Automatic = ($automatic.Count -eq 1 -and [int]$automatic[0] -gt 0) }
}

function Read-AwayMode([string]$Path) { return (Read-ModeSettings $Path).Manual }

function Test-AwaySender([int]$SenderId) {
    try {
        $sender = Get-Process -Id $SenderId -ErrorAction Stop
        return -not $sender.HasExited -and $sender.ProcessName -match '^AutoHotkey(?:32|64)?$'
    } catch { return $false }
}

function Get-ModeTickCount {
    Initialize-ModeWindow
    return [GtaModeWindow]::GetTickCount64()
}

function Read-AwaySignal([string]$Path) {
    try {
        $text = [IO.File]::ReadAllText($Path)
        if ($text -notmatch '\Av1\|([1-9]\d{0,9})\|(\d{1,20})\|([01])\|([01])\z') { return $null }
        [int]$senderId = 0; [uint64]$tick = 0
        if (-not [int]::TryParse($Matches[1], [ref]$senderId) -or
            -not [uint64]::TryParse($Matches[2], [ref]$tick)) { return $null }
        $autoAway = $Matches[3] -eq '1'; $cpuWanted = $Matches[4] -eq '1'
        [uint64]$now = Get-ModeTickCount
        if ($tick -gt $now -or ($now - $tick) -gt 15000 -or -not (Test-AwaySender $senderId)) { return $null }
        return @{ AutoAway = $autoAway; CpuWanted = $cpuWanted; SenderId = $senderId; Tick = $tick }
    } catch { return $null }
}

function Get-WantedModePolicy {
    $settings = Read-ModeSettings $script:MacroConfig
    $signal = Read-AwaySignal $script:AwaySignalPath
    $away = $settings.Manual -or ($settings.Automatic -and $null -ne $signal -and $signal.AutoAway)
    $cpuWanted = if ($away) { $false } elseif ($null -ne $signal) { $signal.CpuWanted } else { $true }
    return @{ Away = $away; CpuWanted = [bool]$cpuWanted;
        Manual = $settings.Manual; Automatic = $settings.Automatic; SignalValid = ($null -ne $signal) }
}

function Get-AwayFpsTarget($Policy, [string]$Current) {
    if ($Policy.Manual -or ($Policy.Automatic -and $Policy.SignalValid -and $Policy.Away)) { return '30' }
    if ($Policy.Automatic -and (($Policy.SignalValid -and $Policy.CpuWanted) -or
        (-not $Policy.SignalValid -and $Current -eq '30'))) { return '0' }
    return $null
}

function Sync-AwayFpsPolicy {
    $current = if ([IO.File]::Exists($script:FpsWantPath)) { [IO.File]::ReadAllText($script:FpsWantPath).Trim() } else { '' }
    $target = Get-AwayFpsTarget (Get-WantedModePolicy) $current
    if ($null -eq $target -or $current -eq $target) { return $null }
    # Main may finish a task or publish user return during this write. Recheck
    # policy before the atomic replacement; the next tick repairs later races.
    $pending = $script:FpsWantPath + '.watcher.pending'
    [IO.File]::WriteAllText($pending, $target, [Text.UTF8Encoding]::new($false))
    $current = if ([IO.File]::Exists($script:FpsWantPath)) { [IO.File]::ReadAllText($script:FpsWantPath).Trim() } else { '' }
    $latest = Get-AwayFpsTarget (Get-WantedModePolicy) $current
    if ($null -eq $latest -or $latest -ne $target -or $current -eq $target) { return $null }
    if ([IO.File]::Exists($script:FpsWantPath)) { [IO.File]::Replace($pending, $script:FpsWantPath, [NullString]::Value) }
    else { [IO.File]::Move($pending, $script:FpsWantPath) }
    if ([IO.File]::ReadAllText($script:FpsWantPath) -ne $target) { throw 'Away FPS request was not confirmed; retrying on next tick.' }
    return $target
}

function Get-WantedGameMode([bool]$Running, [bool]$Away = $false) {
    if ($Running -and -not $Away) { return 1 }
    return 2
}

function Get-Mode {
    $value = ([IO.File]::ReadAllText($script:Config) | ConvertFrom-Json).performance_mode
    if ($null -eq $value -or "$value" -notmatch '^[0-4]$') { throw 'G-Helper mode unavailable.' }
    return [int]$value
}

function Invoke-ModeTick([bool]$Running) {
    try {
        $fps = Sync-AwayFpsPolicy
        if ($null -ne $fps) { Add-Content -LiteralPath $script:Log "$(Get-Date -Format s) away FPS request=$fps synchronized" }
        $script:LastFpsReleaseError = ''
    } catch {
        if ($script:LastFpsReleaseError -ne $_.Exception.Message) { Add-Content -LiteralPath $script:Log "$(Get-Date -Format s) FPS synchronization pending: $($_.Exception.Message)" }
        $script:LastFpsReleaseError = $_.Exception.Message
    }
    $away = if ($Running) { (Get-WantedModePolicy).Away } else { $false }
    $target = Get-WantedGameMode $Running $away
    $changed = Set-GHelperMode $target
    if ($changed) {
        $script:CpuPolicyKey = ''
        Add-Content -LiteralPath $script:Log "$(Get-Date -Format s) mode=$target running=$Running applied"
        Start-Sleep -Milliseconds 1200
    }
    $latest = Get-WantedModePolicy
    $cpuWanted = $Running -and $latest.CpuWanted
    $cpuKey = [string][int]$cpuWanted
    if ($script:CpuPolicyKey -ne $cpuKey) {
        Set-ModeCpuPolicy $cpuWanted
        $script:CpuPolicyKey = $cpuKey
    }
}

function Test-ModeApplied([string]$Text, [int]$Target) {
    $records = [regex]::Matches($Text, 'Mode = (\d+) : ([^\r\n]+)')
    return $records.Count -gt 0 -and [int]$records[$records.Count - 1].Groups[1].Value -eq $Target -and
        $records[$records.Count - 1].Groups[2].Value.Trim() -eq 'OK'
}

function Initialize-ModeWindow {
    if ('GtaModeWindow' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class GtaModeWindow {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    public class Snapshot { public IntPtr Handle; public uint ProcessId; public string Title, Class; public bool Visible, Minimized, Enabled; public RECT Rect; }
    delegate bool EnumProc(IntPtr window, IntPtr data);
    [DllImport("kernel32.dll")] public static extern ulong GetTickCount64();
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr data);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr window, StringBuilder text, int size);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder text, int size);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsChild(IntPtr parent, IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr window);
    [DllImport("user32.dll", SetLastError=true)] static extern int GetDlgCtrlID(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out RECT rect);
    [DllImport("user32.dll", SetLastError=true)] static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool GetUserObjectInformation(IntPtr handle, int index, StringBuilder value, uint length, out uint needed);
    [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("kernel32.dll")] static extern void SetLastError(uint error);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
    public static bool InteractiveDesktop() {
        IntPtr desktop = OpenInputDesktop(0, false, 1);
        if (desktop == IntPtr.Zero) return false;
        try {
            uint needed; var name = new StringBuilder(256);
            return GetUserObjectInformation(desktop, 2, name, 512, out needed) && name.ToString() == "Default";
        } finally { CloseDesktop(desktop); }
    }
    public static Snapshot Read(IntPtr window) {
        uint process; RECT rect;
        if (GetWindowThreadProcessId(window, out process) == 0 || !GetWindowRect(window, out rect)) throw new InvalidOperationException("G-Helper window disappeared.");
        var title = new StringBuilder(512); GetWindowText(window, title, title.Capacity);
        var cls = new StringBuilder(256); GetClassName(window, cls, cls.Capacity);
        return new Snapshot { Handle=window, ProcessId=process, Title=title.ToString(), Class=cls.ToString(), Visible=IsWindowVisible(window), Minimized=IsIconic(window), Enabled=IsWindowEnabled(window), Rect=rect };
    }
    public static Snapshot[] Find(uint process) {
        var windows = new List<Snapshot>();
        EnumWindows((window,data) => { uint id; GetWindowThreadProcessId(window,out id); if(id == process) { try { windows.Add(Read(window)); } catch {} } return true; }, IntPtr.Zero);
        return windows.ToArray();
    }
    static void Identity(Snapshot saved) {
        var current = Read(saved.Handle);
        if (current.ProcessId != saved.ProcessId || current.Title != saved.Title || current.Class != saved.Class) throw new InvalidOperationException("G-Helper window identity changed.");
    }
    public static bool MatchesButton(Snapshot settings, Snapshot button, bool child, bool enabled) {
        return settings != null && button != null && settings.Handle != IntPtr.Zero && button.Handle != IntPtr.Zero &&
            settings.Handle != button.Handle && settings.ProcessId == button.ProcessId && child && enabled && button.Visible &&
            button.Class.StartsWith("WindowsForms10.Button", StringComparison.OrdinalIgnoreCase);
    }
    public static bool MatchesEnabledAncestors(Snapshot settings, Snapshot button, Snapshot[] path) {
        if (path == null || path.Length < 2 || path[0].Handle != button.Handle || path[path.Length - 1].Handle != settings.Handle) return false;
        foreach (var window in path) {
            if (window.Handle == IntPtr.Zero || window.ProcessId != settings.ProcessId || !window.Enabled || !window.Visible) return false;
        }
        return true;
    }
    public static UIntPtr ClickNotificationParameter(int controlId) {
        // WM_COMMAND: LOWORD = control ID, HIWORD = BN_CLICKED (zero).
        // WinForms can use a signed HWND-sized ID. Keep only its low 16 bits.
        return new UIntPtr(unchecked((uint)controlId) & 0xffffu);
    }
    public static void ClickButton(Snapshot settings, Snapshot button) {
        Identity(settings); Identity(button);
        var current = Read(button.Handle);
        if (!MatchesButton(settings, current, IsChild(settings.Handle, button.Handle), IsWindowEnabled(button.Handle)))
            throw new InvalidOperationException("G-Helper native button identity or enabled state changed.");
        var path = new List<Snapshot>();
        for (var handle = button.Handle; handle != IntPtr.Zero && path.Count < 64; handle = GetParent(handle)) {
            path.Add(Read(handle));
            if (handle == settings.Handle) break;
        }
        if (!MatchesEnabledAncestors(settings, button, path.ToArray()))
            throw new InvalidOperationException("G-Helper button or ancestor is unavailable, disabled or modal; deferring mode change.");
        var parent = path[1];
        if (GetParent(button.Handle) != parent.Handle) throw new InvalidOperationException("G-Helper button parent changed.");
        SetLastError(0);
        int controlId = GetDlgCtrlID(button.Handle);
        int idError = Marshal.GetLastWin32Error();
        if (controlId == 0 && idError != 0) throw new InvalidOperationException("G-Helper button control ID unavailable; error=" + idError);
        var wParam = ClickNotificationParameter(controlId);
        // Public Win32 BN_CLICKED notification to the observed DIRECT parent,
        // not a guessed menu ID or private reflected message. .NET 10 Control
        // reflects it to Button.WndProc, which raises the normal Click event.
        // UIA identifies the control only; no accessibility action or focus call.
        UIntPtr result; SetLastError(0);
        if (SendMessageTimeout(parent.Handle, 0x0111, wParam, button.Handle, 0x23, 1500, out result) == IntPtr.Zero)
            throw new InvalidOperationException("G-Helper BN_CLICKED failed or timed out; error=" + Marshal.GetLastWin32Error());
    }
    public static void Prepare(Snapshot saved) {
        Identity(saved);
        int x = Math.Max(0, GetSystemMetrics(76) + GetSystemMetrics(78)) + 100;
        int y = Math.Max(0, GetSystemMetrics(77) + GetSystemMetrics(79)) + 100;
        // Move while hidden, then expose without activation. Never use negative Y:
        // G-Helper's GPU refresh snaps negative Top back onto the screen.
        if (!SetWindowPos(saved.Handle, IntPtr.Zero, x,y,0,0, 0x215)) throw new InvalidOperationException("Could not prepare G-Helper window position.");
        // SW_SHOWNOACTIVATE delivers WM_SHOWWINDOW, which creates lazy WinForms
        // child controls. SetWindowPos(SWP_SHOWWINDOW) alone leaves them absent.
        ShowWindow(saved.Handle, 4);
        var ready = Read(saved.Handle);
        if (!ready.Visible || (ready.Rect.Left < x && ready.Rect.Top < y)) throw new InvalidOperationException("G-Helper did not stay outside the visible desktop.");
    }
    public static void Restore(Snapshot saved) {
        Identity(saved);
        // Hide before moving back, preserving activation and Z order throughout.
        ShowWindow(saved.Handle, 0);
        if (!SetWindowPos(saved.Handle, IntPtr.Zero,saved.Rect.Left,saved.Rect.Top,0,0,0x215)) throw new InvalidOperationException("Could not restore G-Helper window position.");
        var restored = Read(saved.Handle);
        if (restored.Visible || restored.Rect.Left != saved.Rect.Left || restored.Rect.Top != saved.Rect.Top) throw new InvalidOperationException("G-Helper window restoration was not confirmed.");
    }
}
'@
}

function Invoke-ModeCheck([bool]$Running) {
    try { Invoke-ModeTick $Running; $script:LastModeError = '' }
    catch {
        if ($script:LastModeError -ne $_.Exception.Message) { Add-Content -LiteralPath $script:Log "$(Get-Date -Format s) mode pending: $($_.Exception.Message)" }
        $script:LastModeError = $_.Exception.Message
    }
}

function Get-ModeDesktopState {
    Initialize-ModeWindow
    $foreground = [GtaModeWindow]::GetForegroundWindow(); [uint32]$foregroundId = 0
    $null = [GtaModeWindow]::GetWindowThreadProcessId($foreground, [ref]$foregroundId)
    $name = if ($foregroundId) { (Get-Process -Id $foregroundId -ErrorAction Stop).ProcessName } else { '' }
    return @{ Foreground = $foreground; ProcessId = $foregroundId;
        Available = ([GtaModeWindow]::InteractiveDesktop() -and $foreground -ne [IntPtr]::Zero -and $name -notin @('LockApp','LogonUI','consent')) }
}

function Get-ModeWindows([int]$ProcessId) {
    Initialize-ModeWindow
    return [GtaModeWindow]::Find($ProcessId)
}

function Get-ModeSettingsWindow($Helper) {
    $windows = @(Get-ModeWindows $Helper.Id | Where-Object {
        $_.ProcessId -eq $Helper.Id -and $_.Title -match '^G-?Helper\s*-' -and $_.Class -like 'WindowsForms10.Window*'
    })
    if ($windows.Count -ne 1) { throw 'Expected one identified G-Helper settings window.' }
    if (-not $windows[0].Enabled) { throw 'G-Helper settings are disabled by a dialog; deferring mode change.' }
    if ($windows[0].Minimized) { throw 'G-Helper was minimized by the user; deferring mode change.' }
    return $windows[0]
}

function Prepare-ModeSettingsWindow($Window) { [GtaModeWindow]::Prepare($Window) }
function Restore-ModeSettingsWindow($Window) { [GtaModeWindow]::Restore($Window) }

function Get-ModeButton($Window, [int]$Target) {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $element = [Windows.Automation.AutomationElement]::FromHandle($Window.Handle)
    $buttonId = @('buttonBalanced','buttonTurbo','buttonSilent')[$Target]
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty, $buttonId)
    $buttons = $element.FindAll([Windows.Automation.TreeScope]::Descendants, $condition)
    if ($buttons.Count -ne 1 -or $buttons[0].Current.ProcessId -ne $Window.ProcessId -or
        $buttons[0].Current.ControlType -ne [Windows.Automation.ControlType]::Button -or -not $buttons[0].Current.IsEnabled) {
        throw 'Expected one enabled G-Helper mode button.'
    }
    $handle = [IntPtr]$buttons[0].Current.NativeWindowHandle
    if ($handle -eq [IntPtr]::Zero) { throw 'G-Helper mode button has no native handle.' }
    return @{ Window = $Window; Native = [GtaModeWindow]::Read($handle) }
}

function Invoke-ModeButton($Button) { [GtaModeWindow]::ClickButton($Button.Window, $Button.Native) }

function Invoke-GHelperModeButton([int]$Target, $Helper) {
    $before = Get-ModeDesktopState
    if (-not $before.Available -or $before.ProcessId -eq $Helper.Id) { throw 'Desktop unavailable or G-Helper is being used; deferring mode change.' }
    $window = Get-ModeSettingsWindow $Helper
    $prepared = $false; $invoked = $false; $trace = @("before=$($before.Foreground)")
    try {
        if (-not $window.Visible) { $prepared = $true; Prepare-ModeSettingsWindow $window }
        $button = Get-ModeButton $window $Target
        $ready = Get-ModeDesktopState; $trace += "ready=$($ready.Foreground)"
        if (-not $ready.Available -or $ready.Foreground -ne $before.Foreground) { throw 'Foreground changed before G-Helper invocation; deferred without input.' }
        $currentHelper = Get-Process -Id $Helper.Id -ErrorAction Stop
        if ($currentHelper.StartTime.Ticks -ne $Helper.StartTime.Ticks) { throw 'G-Helper process identity changed.' }
        $script:LastModeAttemptKey = "$($Helper.Id):$($Helper.StartTime.Ticks):$Target"
        $script:NextModeAttempt = (Get-Date).AddMinutes(5)
        Invoke-ModeButton $button
        $invoked = $true
        $after = Get-ModeDesktopState; $trace += "invoked=$($after.Foreground)"
        if ($after.Foreground -ne $before.Foreground) { throw 'Foreground changed during G-Helper invocation; no focus restoration attempted.' }
    } finally {
        try { if ($prepared) { Restore-ModeSettingsWindow $window } }
        finally {
            $final = Get-ModeDesktopState; $trace += "final=$($final.Foreground)"
            Add-Content -LiteralPath $script:Log "$(Get-Date -Format s) mode request target=$Target invoked=$invoked foreground $($trace -join ' ')"
        }
    }
}

function Set-GHelperMode([int]$Target) {
    if ($Target -notin @(0,1,2)) { throw 'Automatic restore supports built-in G-Helper modes only.' }
    $helpers = @(Get-Process -Name GHelper -ErrorAction SilentlyContinue)
    if ($helpers.Count -ne 1) { throw 'Expected one running G-Helper.' }
    $current = Get-Mode
    $helperLog = Join-Path (Split-Path $script:Config) 'log.txt'
    $existingLog = [IO.File]::ReadAllText($helperLog)
    $attemptKey = "$($helpers[0].Id):$($helpers[0].StartTime.Ticks):$Target"
    if ($script:LastModeAttemptKey -eq $attemptKey) {
        $lateTail = if ($existingLog.StartsWith($script:ModeAttemptLogBefore)) { $existingLog.Substring($script:ModeAttemptLogBefore.Length) } else { $existingLog }
        if ($current -eq $Target -and (Test-ModeApplied $lateTail $Target)) {
            $script:LastModeAttemptKey = ''
            return $true
        }
    } elseif ($current -eq $Target -and (Test-ModeApplied $existingLog $Target)) { return $false }
    if ($script:LastModeAttemptKey -eq $attemptKey -and (Get-Date) -lt $script:NextModeAttempt) {
        throw 'Awaiting G-Helper acknowledgement; mode retry is limited to once per five minutes.'
    }
    $script:ModeAttemptLogBefore = $existingLog
    Invoke-GHelperModeButton $Target $helpers[0]
    # A config write precedes ACPI completion. Require a NEW final successful ACPI record too.
    $deadline = (Get-Date).AddSeconds(8)
    do {
        Start-Sleep -Milliseconds 250
        $text = [IO.File]::ReadAllText($helperLog)
        $tail = if ($text.StartsWith($existingLog)) { $text.Substring($existingLog.Length) } else { $text }
        if ((Get-Mode) -eq $Target -and (Test-ModeApplied $tail $Target)) {
            $script:LastModeAttemptKey = ''
            return $true
        }
    } while ((Get-Date) -lt $deadline)
    throw "G-Helper mode $Target is not confirmed by configuration and ACPI log."
}

function Set-ModeCpuPolicy([bool]$Enabled) {
    # Match Main's final policy, after G-Helper applies per-mode auto_boost/plan.
    foreach ($supply in @('ac', 'dc')) {
        $maximum = if ($Enabled) { 100 } else { 99 }
        $boost = if (-not $Enabled) { 0 } elseif ($supply -eq 'ac') { 2 } else { 1 }
        & powercfg "/set${supply}valueindex" SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX $maximum | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not apply CPU maximum.' }
        & powercfg "/set${supply}valueindex" SCHEME_CURRENT SUB_PROCESSOR be337238-0d82-4146-a960-4f3749d470c7 $boost | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not apply CPU boost policy.' }
    }
    & powercfg /setactive SCHEME_CURRENT | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not activate CPU policy.' }
}

# iCloud sync competed with the game for CPU and disk (1019 measurement), so it
# is suspended while the game runs and resumed when it exits. Suspension keeps
# its state; relaunching the packaged app would open its window instead.
function Set-CloudSyncPaused([bool]$Paused) {
    if (-not ('GtaProcessPause' -as [type])) {
        Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class GtaProcessPause {
    [DllImport("ntdll.dll")] public static extern int NtSuspendProcess(IntPtr handle);
    [DllImport("ntdll.dll")] public static extern int NtResumeProcess(IntPtr handle);
}
'@
    }
    foreach ($process in @(Get-Process -Name 'iCloud*' -ErrorAction SilentlyContinue)) {
        try {
            if ($Paused) { $null = [GtaProcessPause]::NtSuspendProcess($process.Handle) }
            else { $null = [GtaProcessPause]::NtResumeProcess($process.Handle) }
        } catch { }
    }
}

function Sync-CloudSync([bool]$Running) {
    if ($script:CloudPaused -eq $Running) { return }
    Set-CloudSyncPaused $Running
    $script:CloudPaused = $Running
    Add-Content -LiteralPath $script:Log "$(Get-Date -Format s) icloud $(if ($Running) { 'paused' } else { 'resumed' })"
}

# Preserve the existing performance CSV contract consumed by frame-watch.
function Initialize-FrameFeed {
    if ('GtaFrameFeed' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Diagnostics; using System.Globalization; using System.IO;
public sealed class GtaFrameFeed {
    readonly object gate = new object();
    readonly Queue<KeyValuePair<long, double>> frames = new Queue<KeyValuePair<long, double>>();
    readonly Process process;
    readonly string directory;
    readonly System.Threading.Thread reader;
    StreamWriter output;
    DateTime nextFile, nextFlush;
    int column = -1;
    string header = "", rawPath = "", error = "", etwStatus = "";
    long rows;
    DateTime lastFrame = DateTime.MinValue;
    DateTime lastOutput = DateTime.UtcNow;
    volatile bool ended;
    public GtaFrameFeed(string exe, string args, string rawDirectory) {
        directory = rawDirectory;
        Directory.CreateDirectory(directory);
        var info = new ProcessStartInfo(exe, args);
        info.UseShellExecute = false; info.CreateNoWindow = true;
        info.RedirectStandardOutput = true; info.RedirectStandardError = true;
        process = Process.Start(info);
        process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e) {
            if (!String.IsNullOrWhiteSpace(e.Data)) RecordError(e.Data);
        };
        process.BeginErrorReadLine();
        reader = new System.Threading.Thread(Read);
        reader.IsBackground = true; reader.Start();
    }
    public bool Alive { get { try { return !ended && !process.HasExited; } catch { return false; } } }
    public string RawPath { get { lock(gate) { return rawPath; } } }
    public string LastError { get { lock(gate) { return error; } } }
    public string EtwStatus { get { lock(gate) { return etwStatus; } } }
    public long Rows { get { lock(gate) { return rows; } } }
    public DateTime LastFrameUtc { get { lock(gate) { return lastFrame; } } }
    public DateTime LastOutputUtc { get { lock(gate) { return lastOutput; } } }
    void RecordError(string message) {
        lock(gate) {
            error = message;
            try { File.AppendAllText(Path.Combine(directory, "errors.log"), DateTimeOffset.Now.ToString("o") + " " + message + Environment.NewLine); }
            catch { }
        }
    }
    void Preserve(string line, bool isHeader) {
        var now = DateTime.Now;
        if (output == null || now >= nextFile) {
            if (output != null) output.Dispose();
            var day = Path.Combine(directory, now.ToString("yyyyMMdd"));
            Directory.CreateDirectory(day);
            var path = Path.Combine(day, now.ToString("HHmmss") + "-" + Guid.NewGuid().ToString("N") + ".csv");
            output = new StreamWriter(new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.ReadWrite));
            lock(gate) { rawPath = path; }
            nextFile = now.AddMinutes(10); nextFlush = now;
            output.WriteLine("CapturedAt," + header);
        }
        if (!isHeader) output.WriteLine(DateTimeOffset.Now.ToString("o") + "," + line);
        if (now >= nextFlush) { output.Flush(); nextFlush = now.AddSeconds(1); }
    }
    void Read() {
        try {
            string line;
            while ((line = process.StandardOutput.ReadLine()) != null) {
                if (line.StartsWith("[ETW Status]", StringComparison.Ordinal)) {
                    lock(gate) { etwStatus = line; }
                    continue;
                }
                lock(gate) { lastOutput = DateTime.UtcNow; }
                var cells = line.Split(',');
                bool isHeader = Array.IndexOf(cells, "ProcessID") >= 0;
                if (isHeader) {
                    header = line;
                    column = Array.FindIndex(cells, value => String.Equals(value, "msBetweenDisplayChange", StringComparison.OrdinalIgnoreCase));
                    Preserve(line, true);
                    if (column < 0) throw new InvalidDataException("PresentMon header lacks MsBetweenDisplayChange; v1 metrics required: " + line);
                    continue;
                }
                if (column < 0) { RecordError("Before CSV header: " + line); continue; }
                Preserve(line, false);
                lock(gate) { rows++; }
                double ms;
                if (column >= cells.Length || !double.TryParse(cells[column], NumberStyles.Float, CultureInfo.InvariantCulture, out ms) || ms <= 0) continue;
                long now = Stopwatch.GetTimestamp();
                lock (gate) {
                    lastFrame = DateTime.UtcNow;
                    frames.Enqueue(new KeyValuePair<long, double>(now, ms));
                    while (frames.Count > 0 && now - frames.Peek().Key > Stopwatch.Frequency * 10) frames.Dequeue();
                }
            }
        } catch(Exception e) { RecordError(e.ToString()); }
        finally {
            try { if (output != null) output.Dispose(); } catch(Exception e) { RecordError(e.ToString()); }
            ended = true;
        }
    }
    public double[] Recent(double seconds) {
        long cutoff = Stopwatch.GetTimestamp() - (long)(Stopwatch.Frequency * seconds);
        var result = new List<double>();
        lock (gate) { foreach (var frame in frames) { if (frame.Key >= cutoff) { result.Add(frame.Value); } } }
        return result.ToArray();
    }
    public void Stop() {
        try { if (!process.HasExited) process.Kill(); } catch { }
        reader.Join(3000);
        if (!reader.IsAlive) process.Dispose();
    }
}
'@
}

# One long-lived ETW session. Starting a PresentMon session per sample made the
# game hitch for 60-290 ms every telemetry interval (1019 measurement).
function Test-FrameFeedStalled($Feed, [datetime]$NowUtc, [bool]$GameForeground) {
    return $GameForeground -and $Feed.Alive -and ($NowUtc - $Feed.LastOutputUtc).TotalSeconds -ge 60
}

function New-FrameFeed([int]$GameId) {
    Initialize-FrameFeed
    return [GtaFrameFeed]::new($script:PresentMon,
        "--process_id $GameId --output_stdout --no_console_stats --v1_metrics --date_time --track_etw_status --stop_existing_session --session_name gta_perf",
        (Join-Path $script:PerfDir 'frames'))
}

function Get-FrameFeed([bool]$Running) {
    if (-not $Running) {
        if ($script:FrameFeed) { $script:FrameFeed.Stop(); $script:FrameFeed = $null }
        return $null
    }
    $game = Get-Process -Name $script:Game -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $game) { return Get-FrameFeed $false }
    if ($script:FrameFeed -and $script:FrameGameId -ne $game.Id) {
        $script:FrameFeed.Stop(); $script:FrameFeed = $null
        $script:NextFeedStart = [datetime]::MinValue
    }
    if ($script:FrameFeed -and $script:FrameFeed.Alive) {
        $foreground = $false
        if (([datetime]::UtcNow - $script:FrameFeed.LastOutputUtc).TotalSeconds -ge 60) {
            try {
                $desktop = Get-ModeDesktopState
                $foreground = $desktop.Available -and $desktop.ProcessId -eq $game.Id
            } catch { }
        }
        if (-not (Test-FrameFeedStalled $script:FrameFeed ([datetime]::UtcNow) $foreground)) { return $script:FrameFeed }
        $script:RecoveryLogError = ''
        try {
            Add-PerfLine (Join-Path $script:PerfDir 'health.jsonl') (@{
                time = (Get-Date).ToString('o'); error = 'PresentMon stdout stalled for 60 seconds while game was foreground; restarting'
            } | ConvertTo-Json -Compress)
        } catch { $script:RecoveryLogError = 'recovery log: ' + $_.Exception.Message }
    }
    if ($script:FrameFeed) {
        $script:FeedError = $script:FrameFeed.LastError
        $script:FrameFeed.Stop(); $script:FrameFeed = $null
    }
    if ($script:NextFeedStart -and (Get-Date) -lt $script:NextFeedStart) { return $null }
    $script:NextFeedStart = (Get-Date).AddSeconds(60)
    if (-not (Test-Path -LiteralPath $script:PresentMon)) { throw 'PresentMon executable missing' }
    $script:FrameFeed = New-FrameFeed $game.Id
    $script:FrameGameId = $game.Id
    $script:FeedError = ''
    return $script:FrameFeed
}

function Get-Fps {
    $feed = Get-FrameFeed $true
    if (-not $feed) { return ',' }
    return Format-Fps @($feed.Recent(2))
}

function Format-Fps([double[]]$ms) {
    if ($ms.Count -lt 10) { return ',' }
    $avg = 1000 / ($ms | Measure-Object -Average).Average
    $worst = $ms | Sort-Object -Descending | Select-Object -First ([math]::Max(1, [math]::Floor($ms.Count * 0.01)))
    $low = 1000 / ($worst | Measure-Object -Average).Average
    return [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0:F1},{1:F1}', $avg, $low)
}

function Add-PerfLine([string]$Path, [string]$Line, [string]$Header = '') {
    # Readers and the writer must be able to overlap without dropping a sample.
    $stream = [IO.File]::Open($Path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    $writer = $null
    try {
        $empty = $stream.Length -eq 0
        $null = $stream.Seek(0, [IO.SeekOrigin]::End)
        $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
        if ($empty -and $Header) { $writer.WriteLine($Header) }
        $writer.WriteLine($Line)
    } finally { if ($writer) { $writer.Dispose() } else { $stream.Dispose() } }
}

function Read-PerfGpu {
    $info = [Diagnostics.ProcessStartInfo]::new('nvidia-smi', "--query-gpu=$script:Smi --format=csv,noheader,nounits")
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    try {
        $output = $process.StandardOutput.ReadToEndAsync(); $errorOutput = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(3000)) { $process.Kill(); throw 'nvidia-smi timed out after 3 seconds' }
        if ($process.ExitCode -ne 0) { throw $errorOutput.GetAwaiter().GetResult() }
        $line = ($output.GetAwaiter().GetResult() -split '[\r\n]+' | Where-Object { $_ } | Select-Object -First 1) -replace '\s', ''
        if (($line -split ',').Count -ne 7) { throw 'Unexpected nvidia-smi column count' }
        return $line
    } finally { $process.Dispose() }
}

function Read-PerfCpu {
    return [math]::Round((Get-CimInstance Win32_Processor -OperationTimeoutSec 3 | Measure-Object LoadPercentage -Average).Average)
}

function Save-PerfStatus($Status) {
    $path = Join-Path $script:PerfDir 'status.json'
    $temp = $path + '.' + $PID + '.tmp'
    [IO.File]::WriteAllText($temp, ($Status | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $path) { [IO.File]::Replace($temp, $path, [NullString]::Value) }
    else { [IO.File]::Move($temp, $path) }
}

function Write-Perf([datetime]$Now = (Get-Date)) {
    $errors = @(); $fps = ','; $gpu = ',,,,,,'; $cpu = ''; $mode = ''
    try { $fps = Get-Fps } catch { $errors += 'frames: ' + $_.Exception.Message }
    try { $gpu = Read-PerfGpu } catch { $errors += 'gpu: ' + $_.Exception.Message }
    try { $cpu = Read-PerfCpu } catch { $errors += 'cpu: ' + $_.Exception.Message }
    try { $mode = Get-Mode } catch { $errors += 'mode: ' + $_.Exception.Message }
    $csv = Join-Path $script:PerfDir ($Now.ToString('yyyyMMdd') + '.csv')
    $saved = $false
    try {
        Add-PerfLine $csv ($Now.ToString('s') + ",$fps,$gpu,$cpu,$mode") $script:Header
        $saved = $true
    } catch { $errors += 'csv: ' + $_.Exception.Message }
    $feed = $script:FrameFeed
    if ($script:FeedError) { $errors += $script:FeedError }
    if ($script:RecoveryLogError) { $errors += $script:RecoveryLogError }
    if ($feed -and $feed.LastError) { $errors += $feed.LastError }
    $status = @{
        time = (Get-Date).ToString('o'); watcher_pid = $PID; csv = $csv; csv_saved = $saved
        fps_available = ($fps -ne ','); errors = @($errors)
        feed_alive = [bool]($feed -and $feed.Alive)
        raw_path = $(if ($feed) { $feed.RawPath } else { $null })
        raw_rows = $(if ($feed) { $feed.Rows } else { 0 })
        etw_status = $(if ($feed) { $feed.EtwStatus } else { $null })
        last_frame_utc = $(if ($feed -and $feed.LastFrameUtc -ne [datetime]::MinValue) { $feed.LastFrameUtc.ToString('o') } else { $null })
        last_output_utc = $(if ($feed) { $feed.LastOutputUtc.ToString('o') } else { $null })
    }
    Save-PerfStatus $status
    $etwLoss = $status.etw_status -match '(?:EventsLost|BuffersLost|OverflowedPresents)=[1-9][0-9]*'
    if (-not $saved -or $fps -eq ',' -or $errors.Count -or $etwLoss) {
        Add-PerfLine (Join-Path $script:PerfDir 'health.jsonl') ($status | ConvertTo-Json -Depth 5 -Compress)
    }
}

if ($LibraryOnly) { return }

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    $env:PSModulePath = (Join-Path $PSHOME 'Modules') + ';' + (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules')
}
$script:Game = 'GTA5_Enhanced'
$script:Config = Join-Path $env:APPDATA 'GHelper\config.json'
$script:AwaySignalPath = Join-Path $env:USERPROFILE '.gta-away-want'
$script:FpsWantPath = Join-Path $env:USERPROFILE '.gta-fps-want'
$script:CpuPolicyKey = ''
# Unknown at start: the first tick applies either state, so a watcher that died
# mid-game resumes iCloud on its next run.
$script:CloudPaused = $null
$script:Log = Join-Path $env:LOCALAPPDATA 'gta-turbo.log'
$script:PerfDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'gta-perf'
$script:FeedError = ''; $script:NextFeedStart = [datetime]::MinValue
$script:PresentMon = Join-Path $env:USERPROFILE 'scripts\tools\PresentMon.exe'
$script:Smi = 'utilization.gpu,temperature.gpu,power.draw,clocks.gr,memory.used,memory.total,clocks_throttle_reasons.active'
$script:Header = 'time,fps_avg,fps_1pct_low,gpu_util_pct,gpu_temp_c,gpu_power_w,gpu_clock_mhz,vram_used_mb,vram_total_mb,throttle_reasons,cpu_util_pct,mode'
$singleton = [Threading.Mutex]::new($false, 'Local\GtaPerformanceWatch')
$owned = $false
try {
    try { $owned = $singleton.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) { throw 'GTA performance watcher already running.' }
    New-Item -ItemType Directory -Force -Path $script:PerfDir | Out-Null
    $nextPerf = [datetime]::MinValue; $lastModeError = ''; $lastPerfError = ''
    Add-Content -LiteralPath $script:Log "$(Get-Date -Format s) watcher started pid=$PID config=$MacroConfig"
    while ($true) {
        $running = [bool](Get-Process -Name $script:Game -ErrorAction SilentlyContinue)
        Invoke-ModeCheck $running
        try { $null = Get-FrameFeed $running } catch { $script:FeedError = $_.Exception.Message }
        try { Sync-CloudSync $running } catch { }
        # A control failure must not stop telemetry, and a measurement failure must not stop control.
        if ($running -and (Get-Date) -ge $nextPerf) {
            $nextPerf = (Get-Date).AddSeconds(10)
            try { Write-Perf; $lastPerfError = '' }
            catch {
                if ($lastPerfError -ne $_.Exception.Message) { Add-Content -LiteralPath $script:Log "$(Get-Date -Format s) telemetry failed: $($_.Exception.Message)" }
                $lastPerfError = $_.Exception.Message
            }
            # A user can return during the two-second frame sample.
            Invoke-ModeCheck ([bool](Get-Process -Name $script:Game -ErrorAction SilentlyContinue))
        }
        Start-Sleep -Seconds 1
    }
} finally {
    if ($script:FrameFeed) { $script:FrameFeed.Stop() }
    if ($owned) { try { Set-CloudSyncPaused $false } catch { } }
    if ($owned) { $singleton.ReleaseMutex() }
    $singleton.Dispose()
}
