#Requires -Version 5.1
param(
    [string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
)
$ErrorActionPreference = 'Stop'
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$production = ''
foreach ($entry in @(
    @{ Path = 'Features/AutoClick.ahk'; Names = @('ToggleAutoClick','DoClick','StopAutoClick') },
    @{ Path = 'Features/StopAll.ahk'; Names = @('StopAll') },
    @{ Path = 'Features/Movement.ahk'; Names = @('ToggleWalk','ToggleRun','StopRun','ToggleVellumDriving','PressLCtrlForVellum') },
    @{ Path = 'Core/ClickMouse.ahk'; Names = @('ClickMouse') },
    @{ Path = 'Core/PressKey.ahk'; Names = @('PressKey') },
    @{ Path = 'Core/KeyOwnership.ahk'; Names = @('MacroKeyPhysicallyHeld','ReleaseMacroKey') },
    @{ Path = 'Core/Common.ahk'; Names = @('ReleaseHeldKeys') }
)) {
    $source = Get-Content -LiteralPath (Join-Path $RepoRoot $entry.Path) -Raw -Encoding UTF8
    foreach ($name in $entry.Names) {
        $body = [regex]::Match($source, ('(?ms)^' + $name + '\([^\r\n]*\) \{.*?^\}')).Value
        if (-not $body) { throw "Missing function $name" }
        $production += $body + "`n"
    }
}
$hardStopReason = -join ([char[]]@(0xC804, 0xCCB4, 0x20, 0xBA48, 0xCDA4))
$hardStopCall = 'SetEarner(false, "' + $hardStopReason + '")'
if (-not $production.Contains($hardStopCall)) { throw 'StopAll must pass the explicit hard-stop reason to SetEarner.' }
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
OnError((err, *) => (FileAppend("ERROR " err.Message " line=" err.Line "`n", "*"), ExitApp(2)))
global checks := 0, failures := 0

Reset()
ToggleAutoClick()
Check(clickRunning && TimerOn("DoClick") && !Held("LButton"), "normal autoclick schedules timer and releases button")
StopAll()
Check(!clickRunning && !TimerOn("DoClick") && !Held("LButton"), "stopall stops established autoclick")

Reset()
gEarnBusy := true
StopAll()
Check(gAbort && setCalls = 1 && !setOn, "stopall hard-stops an in-flight F9 cleanup even when earnings are already off")

for phase in [1, 2] {
    Reset()
    injectSleep := phase
    ToggleAutoClick()
    Check(!clickRunning && !TimerOn("DoClick") && !Held("LButton"), "stop during initial click sleep " phase " leaves no timer")
    Report("stop during sleep " phase)
    DoClick()
    Check(!TimerOn("DoClick"), "cancelled callback clears any residual timer " phase)
}

Reset()
keyPressed := true
ToggleAutoClick()
Check(!clickRunning && !TimerOn("DoClick") && downEvents = 0, "key cancellation before first click leaves no timer")
Report("key cancellation")

Reset()
cursorExe := "notepad.exe"
ToggleAutoClick()
Check(!clickRunning && !TimerOn("DoClick") && downEvents = 0, "outside cursor cancellation leaves no timer")
Report("outside cursor cancellation")

Reset()
ToggleAutoClick()
focused := false
DoClick()
focused := true
DoClick()
Check(!clickRunning && !TimerOn("DoClick") && downEvents = 1, "focus loss stops existing autoclick permanently")

Reset()
focused := false
ToggleAutoClick()
Check(!clickRunning && timers.Count = 0 && downEvents = 0, "inactive entry does nothing")

for fn in [ToggleWalk, ToggleRun, ToggleVellumDriving] {
    Reset()
    fn.Call()
    focused := false
    StopAll("tray")
    Check(!wRunning && !shiftWRunning && !vellumDrivingRunning && !Held("w") && !Held("lshift") && !TimerOn("PressLCtrlForVellum"), fn.Name " stop releases held movement keys without focus")
}

Reset()
ToggleVellumDriving()
injectSleep := 1
PressLCtrlForVellum()
Check(!vellumDrivingRunning && !Held("w") && !Held("lctrl") && !TimerOn("PressLCtrlForVellum"), "vellum stop during key hold cannot rearm")
FileAppend((failures ? "FAIL" : "PASS") " movement/autoclick: " checks " checks failures=" failures "; no game input`n", "*")
ExitApp(failures ? 1 : 0)

Reset() {
    global config, clickRunning, wRunning, shiftWRunning, vellumDrivingRunning, gAbort, clawLoopRunning, gEarnOn, gEarnBusy, cayoTimerRunning
    global setCalls, setOn, setReason
    global focused, keyPressed, cursorExe, timers, heldKeys, events, downEvents, injectSleep, sleepCount
    config := Map("Settings", Map("ClickInterval", 1, "ClickHoldTime", 50, "KeyHoldTime", 50, "VellumDrivingCtrlInterval", 3000), "Hotkeys", Map("AutoClick", "F7"))
    clickRunning := false, wRunning := false, shiftWRunning := false, vellumDrivingRunning := false, gAbort := false
    clawLoopRunning := false, gEarnOn := false, gEarnBusy := false, cayoTimerRunning := false
    setCalls := 0, setOn := true, setReason := ""
    focused := true, keyPressed := false, cursorExe := "GTA5_Enhanced.exe"
    timers := Map(), heldKeys := Map(), events := [], downEvents := 0, injectSleep := 0, sleepCount := 0
}
Check(ok, name) {
    global checks, failures
    checks += 1
    failures += !ok
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", "*")
}
Report(name) {
    global events
    FileAppend("TRACE " name ": " JoinEvents() "`n", "*")
}
JoinEvents() {
    global events
    result := ""
    for event in events
        result .= (result = "" ? "" : " | ") event
    return result
}
TimerOn(name) {
    global timers
    return timers.Get(name, 0) != 0
}
Held(key) {
    global heldKeys
    return heldKeys.Get(StrLower(key), false)
}
Sleep(ms) {
    global sleepCount, injectSleep, events
    sleepCount += 1
    events.Push("sleep=" ms)
    if (injectSleep && sleepCount = injectSleep) {
        events.Push("STOP")
        StopAll()
    }
}
Click(value) {
    global events, heldKeys, downEvents
    events.Push("click=" value)
    if (value != "Left Down" && value != "Left Up")
        throw Error("Unexpected click " value)
    heldKeys["lbutton"] := value = "Left Down"
    downEvents += value = "Left Down"
}
Send(value) {
    global heldKeys, events, downEvents
    events.Push("send=" value)
    position := 1
    while (position := RegExMatch(value, "\{([^{} ]+) (down|up)\}", &match, position)) {
        heldKeys[StrLower(match[1])] := match[2] = "down"
        downEvents += match[2] = "down"
        position += match.Len(0)
    }
}
SetTimer(fn, period) {
    global timers, events
    timers[fn.Name] := period
    events.Push("timer=" fn.Name ":" period)
}
IsGTAActive() {
    global focused
    return focused
}
IsAnyKeyPressed(*) {
    global keyPressed
    return keyPressed
}
MouseGetPos(x?, y?, &underWin := 0, *) {
    underWin := 1
}
WinGetProcessName(*) {
    global cursorExe
    return cursorExe
}
GetKeyState(key, mode := "") => mode = "P" ? false : Held(key)
ShowTooltip(*) => 0
MacroLog(*) => 0
SetEarner(on, reason := "", *) {
    global setCalls, setOn, setReason
    setCalls++, setOn := on, setReason := reason
}
ToggleCayoPericoTimer(*) => 0
EarnModeTick(*) => 0
'@
# Every input, timer, environment lookup and wait call is supplied above; Main is never loaded.
foreach ($name in @('Send', 'Click', 'SetTimer', 'Sleep', 'MouseGetPos', 'WinGetProcessName', 'GetKeyState', 'IsGTAActive', 'IsAnyKeyPressed', 'ShowTooltip', 'MacroLog')) {
    if ($driver -notmatch ('(?m)^' + $name + '\(')) { throw "Missing required isolation stub $name" }
}
$generated = $driver + "`n" + $production
if ($generated -match '(?im)^#Include|\b(DllCall|SendInput|SendEvent|SendPlay|ControlSend|MouseMove|Run|WinActivate)\(') { throw 'Unsafe API in generated harness' }
$info = [Diagnostics.ProcessStartInfo]::new()
$info.FileName = $AhkPath
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$scriptPath = Join-Path ([IO.Path]::GetTempPath()) ('gta-autoclick-stop-' + [guid]::NewGuid().ToString('N') + '.ahk')
[IO.File]::WriteAllText($scriptPath, $generated, $utf8NoBom)
$info.Arguments = '/ErrorStdOut /CP65001 "' + $scriptPath + '"'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
try {
$process = [Diagnostics.Process]::Start($info)
try {
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'Isolated test timed out' }
    $output = $stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult()
    $output += "exit=$($process.ExitCode)`n"
    $output
    exit $process.ExitCode
} finally { $process.Dispose() }

} finally { Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue }
