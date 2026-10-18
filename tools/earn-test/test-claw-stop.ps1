#Requires -Version 5.1
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$claw = Get-Content (Join-Path $PSScriptRoot '..\..\Features\ClawMachine.ahk') -Raw -Encoding UTF8
$keys = Get-Content (Join-Path $PSScriptRoot '..\..\Core\PressKey.ahk') -Raw -Encoding UTF8
$keys += "`n" + (Get-Content (Join-Path $PSScriptRoot '..\..\Core\KeyOwnership.ahk') -Raw -Encoding UTF8)
$functions = @('ClawFailure', 'ClawWaitFor', 'ClawHold', 'ClawAttempt', 'ClawLoopStep', 'PressKey', 'MacroKeyPhysicallyHeld', 'ReleaseMacroKey') | ForEach-Object {
    $source = if ($_ -in @('PressKey', 'MacroKeyPhysicallyHeld', 'ReleaseMacroKey')) { $keys } else { $claw }
    $body = [regex]::Match($source, ('(?ms)^' + $_ + '\([^\r\n]*\) \{.*?^\}')).Value
    if (-not $body) { throw "$_ missing" }
    $body
}
# Keep the production flow and PressKey's interruptible sleep. Every external
# effect is replaced; neither Main.ahk nor any real input/screen helper is loaded.
$production = ($functions -join "`n").Replace('A_TickCount', 'FakeTick()')
$production = [regex]::Replace($production, '\bSend\(', 'RecordSend(')
$production = [regex]::Replace($production, '\bSleep\(', 'FakeSleep(')
$production = [regex]::Replace($production, '\bSetTimer\(', 'RecordTimer(')
if ($production -match '(?im)^\s*#Include|\b(?:Send|SendInput|SendEvent|Click|MouseMove|SetTimer|DllCall|WinActivate)\s*\(') {
    throw 'Unstubbed external effect in extracted production functions'
}
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
OnError((err, *) => (FileAppend("ERROR: " err.Message " at " err.Line "`n", "*"), ExitApp(1)))
global checks := 0, failures := 0
RunAttempt("normal round", "forward", "", "", false, true, "w,d,Enter")
RunAttempt("normal partial-round recovery", "right", "", "", false, true, "d,Enter,e,w,d,Enter")
RunAttempt("stop during recovery down wait", "right", "wait-down", "abort", true, false, "d")
RunAttempt("focus lost during recovery down wait", "right", "wait-down", "focus", true, false, "d")
RunAttempt("missing down prompt stops recovery", "right", "", "", true, false, "d")
RunAttempt("stop inside recovery direction key", "right", "recover-partial-attempt", "abort", false, false, "d")
RunAttempt("focus lost inside recovery direction key", "right", "recover-partial-attempt", "focus", false, false, "d")
RunAttempt("stop during forward hold releases key", "forward", "hold-w", "abort", false, false, "w")
RunAttempt("focus lost during forward hold releases key", "forward", "hold-w", "focus", false, false, "w")
RunAttempt("stop during result animation cancels loop", "forward", "result-animation", "abort", false, false, "w,d,Enter")
FileAppend((failures ? "FAIL" : "PASS") " Claw stop: " checks " cases; no game input`n", "*")
ExitApp(failures ? 1 : 0)

RunAttempt(name, initialStage, injectStep, action, missingDown, success, expected) {
    global events, held, timers, clawLoopRunning, clawLastReason
    Reset(initialStage, injectStep, action, missingDown)
    ClawLoopStep()
    actual := ""
    for event in events
        actual .= (actual = "" ? "" : ",") event
    ok := actual = expected && held.Count = 0 && clawLoopRunning = success && timers.Length = (success ? 1 : 0)
    Check(ok, name " (input=" actual ", loop=" clawLoopRunning ", held=" held.Count ", timers=" timers.Length ", reason=" clawLastReason ")")
}
Check(condition, name) {
    global checks, failures
    checks += 1
    if (!condition)
        failures += 1
    FileAppend((condition ? "PASS: " : "FAIL: ") name "`n", "*")
}
Reset(initialStage, injectStep, action, missingDown) {
    global config, gAbort, focused, clawLoopRunning, clawTries, clawLastReason, clawStep
    global stage, fakeNow, events, held, timers, injectionStep, injectionAction, injected, noDown
    config := Map("Settings", Map("ClawForwardMs", 60, "ClawRightMs", 60,
        "ClawResultTimeout", 1000, "ClawEnterTimeout", 1000, "KeyHoldTime", 40))
    gAbort := false, focused := true, clawLoopRunning := true, clawTries := 0, clawLastReason := "", clawStep := ""
    stage := initialStage, fakeNow := 100, events := [], held := Map(), timers := []
    injectionStep := injectStep, injectionAction := action, injected := false, noDown := missingDown
}
FakeTick() {
    global fakeNow
    return fakeNow
}
FakeSleep(ms) {
    global fakeNow, injected, injectionStep, injectionAction, clawStep, gAbort, focused, stage, clawLoopRunning
    fakeNow += ms
    if (!injected && injectionStep != "" && clawStep = injectionStep) {
        injected := true
        if (injectionAction = "abort") {
            gAbort := true
            clawLoopRunning := false
        } else
            focused := false
    }
    if (ms = 3000 && stage = "result")
        stage := "play"
}
RecordSend(value) {
    global events, held, stage, noDown
    value := StrReplace(value, "{Blind}")
    if (!RegExMatch(value, "^\{(.+) (down|up)\}$", &match))
        throw Error("Unexpected input stub: " value)
    key := match[1]
    if (match[2] = "down") {
        events.Push(key)
        held[key] := true
        return
    }
    if (held.Has(key))
        held.Delete(key)
    if (key = "w")
        stage := "right"
    else if (key = "d")
        stage := noDown ? "unknown" : "down"
    else if (key = "Enter")
        stage := "result"
    else if (key = "e")
        stage := "forward"
}
RecordTimer(callback, delay) {
    global timers
    timers.Push(delay)
}
IsGTAActive() {
    global focused
    return focused
}
ClawSeen(name) {
    global stage, focused
    return focused && stage = name
}
ClawTrace(step, reason := "", event := "") {
    global clawStep, clawLastReason
    clawStep := step
    if (reason != "")
        clawLastReason := reason
}
ClawLog(*) => 0
ShowTooltip(*) => 0
GetKeyState(*) => false
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
    if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'Claw stop test timed out' }
    $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
    $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
    $stdout
    if ($process.ExitCode -ne 0 -or $stderr) {
        throw "exit=$($process.ExitCode) stderr=$stderr"
    }
} finally { $process.Dispose() }

} finally { [Console]::InputEncoding = $previous }
