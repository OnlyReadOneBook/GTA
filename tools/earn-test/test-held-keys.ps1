#Requires -Version 5.1
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..\..'
$selected = @{
    'Core/PressKey.ahk' = @('PressKey')
    'Core/KeyOwnership.ahk' = @('MacroKeyPhysicallyHeld', 'ReleaseMacroKey')
    'Core/Common.ahk' = @('ReleaseHeldKeys')
    'Core/HotkeyManager.ahk' = @('KeyHookWatchdog')
    'Features/Earn/EarnCore.ahk' = @('EarnWalk')
    'Features/Movement.ahk' = @('ToggleWalk', 'ToggleRun', 'StopRun')
}
$functions = foreach ($file in $selected.Keys) {
    $source = Get-Content (Join-Path $root $file) -Raw -Encoding UTF8
    foreach ($name in $selected[$file]) {
        $body = [regex]::Match($source, ('(?ms)^' + $name + '\([^\r\n]*\) \{.*?^\}')).Value
        if (!$body) { throw "Missing production function: $name" }
        $body
    }
}
$production = $functions -join "`n"
$production = [regex]::Replace($production, '\bSend\(', 'RecordSend(')
$production = [regex]::Replace($production, '\bSleep\(', 'FakeSleep(')
$production = [regex]::Replace($production, '\bGetKeyState\(', 'FakeKeyState(')
$production = [regex]::Replace($production, '\bDllCall\(', 'FakeDllCall(')
$production = [regex]::Replace($production, '\bInstallKeybdHook\(', 'RecordHook(')
if ($production -match '\b(?:Send|SendInput|SendEvent|Sleep|GetKeyState|DllCall|InstallKeybdHook)\s*\(') {
    throw 'Unstubbed input or hook effect'
}
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
OnError((err, *) => (FileAppend("ERROR: " err.Message " at " err.Line "`n", "*"), ExitApp(1)))
global checks := 0, failures := 0
global physical := Map(), logical := Map(), events := [], duringWait := "", hooks := 0
global config := Map("Settings", Map("KeyHoldTime", 30)), wRunning := false, shiftWRunning := false

Reset()
PressKey("w")
Check(events.Length = 2 && events[1] = "{Blind}{w down}" && events[2] = "{Blind}{w up}", "macro-only hold releases normally")
Reset()
duringWait := "takeover"
PressKey("w")
Check(events.Length = 1 && physical.Get("w", false), "physical W press during tap is not released")
Reset()
physical["w"] := true
PressKey("w")
Check(events.Length = 0, "already-held W is not tapped")
Reset()
physical["LShift"] := true
PressKey("e")
Check(events.Length = 2 && events[1] = "{Blind}{e down}" && events[2] = "{Blind}{e up}", "unrelated key preserves held Shift via Blind")
for side in ["LShift", "RShift"] {
    Reset()
    physical[side] := true
    Check(!ReleaseMacroKey("Shift") && events.Length = 0, "generic Shift release protects " side)
}
Reset()
physical["w"] := true, physical["LShift"] := true
logical["w"] := true, logical["Shift"] := true, logical["LShift"] := true
ReleaseHeldKeys()
Check(events.Length = 0, "abort cleanup preserves both physical holds")
Reset()
logical["w"] := true
ReleaseHeldKeys()
Check(events.Length = 1 && events[1] = "{Blind}{w up}", "abort cleanup releases macro-only W")
Reset()
duringWait := "takeover"
Check(!EarnWalk("w:500") && events.Length = 1, "walk handoff does not release physical W after abort")
Reset()
duringWait := "throw"
try EarnWalk("w:500")
catch {
}
Check(events.Length = 2 && events[2] = "{Blind}{w up}", "walk exception still releases macro-only W")
Reset()
physical["w"] := true
Check(!EarnWalk("w:500") && events.Length = 0, "walk does not acquire user-held W")
Reset()
shiftWRunning := true
physical["w"] := true, physical["LShift"] := true
StopRun()
Check(!shiftWRunning && events.Length = 0, "stop run preserves physical W and Shift")
Reset()
shiftWRunning := true
physical["RShift"] := true
ToggleRun()
Check(events.Length = 2 && events[1] = "{Blind}{w up}" && events[2] = "{Blind}{LShift up}", "toggle run releases macro keys without touching physical right Shift")
Reset()
wRunning := true, physical["w"] := true
ToggleWalk()
Check(!wRunning && events.Length = 0, "toggle walk preserves physical W")
for held in ["w", "LShift", "RShift"] {
    Reset()
    physical[held] := true
    KeyHookWatchdog()
    Check(hooks = 0, "hook replacement deferred while " held " held")
}
Reset()
KeyHookWatchdog()
Check(hooks = 1, "idle hook recovery remains enabled")
FileAppend((failures ? "FAIL" : "PASS") " Held keys: " checks " cases; no real input`n", "*")
ExitApp(failures ? 1 : 0)

Reset() {
    global physical, logical, events, duringWait, hooks, wRunning, shiftWRunning
    physical := Map(), logical := Map(), events := [], duringWait := "", hooks := 0
    wRunning := false, shiftWRunning := false
}
Check(ok, name) {
    global checks, failures
    checks++
    if (!ok)
        failures++
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", "*")
}
RecordSend(value) {
    global events
    if (SubStr(value, 1, 7) != "{Blind}")
        throw Error("Unprotected modifier injection: " value)
    events.Push(value)
}
FakeKeyState(key, mode := "") {
    global physical, logical
    return (mode = "P" ? physical : logical).Get(key, false)
}
FakeSleep(ms) {
    global duringWait, physical
    if (duringWait = "takeover")
        physical["w"] := true
    if (duringWait = "throw")
        throw Error("simulated wait failure")
}
EarnSleep(ms) {
    global duringWait
    FakeSleep(ms)
    return duringWait != "takeover"
}
FakeDllCall(name, type, vk, resultType) {
    global physical
    if (name != "GetAsyncKeyState")
        throw Error("Unexpected API")
    key := Map(0x57, "w", 0xA0, "LShift", 0xA1, "RShift")[vk]
    return physical.Get(key, false) ? 0x8000 : 0
}
RecordHook(*) {
    global hooks
    hooks++
}
EarnAborted() => false
EarnHudVisible() => true
EarnFail(*) => false
IsGTAActive() => true
ShowTooltip(*) => 0
Click(*) => 0
'@
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $AhkPath
$info.Arguments = '/ErrorStdOut /CP65001 *'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardInput = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$previous = [Console]::InputEncoding
[Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
try {
    $process = [Diagnostics.Process]::Start($info)
    try {
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.WriteLine($driver + "`n" + $production)
        $process.StandardInput.Close()
        if (!$process.WaitForExit(10000)) { $process.Kill(); throw 'Held-key test timed out' }
        $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
        $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
        $stdout
        if ($process.ExitCode -ne 0 -or $stderr) { throw "exit=$($process.ExitCode) stderr=$stderr" }
    } finally { $process.Dispose() }
} finally { [Console]::InputEncoding = $previous }
