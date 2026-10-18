#Requires -Version 5.1
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$source = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Teleport\AltF4Teleport.ahk') -Raw -Encoding UTF8
$functions = @('ExecuteAltF4Teleport', 'WaitAbortable') | ForEach-Object {
    $body = [regex]::Match($source, ('(?ms)^' + $_ + '\([^\r\n]*\) \{.*?^\}')).Value
    if (-not $body) { throw "$_ missing" }
    $body
}
# Run the production control flow with a virtual clock and input/window stubs.
# Main.ahk, the screen detector and the real PressKey function are never loaded.
$production = ($functions -join "`n").Replace('A_TickCount', 'FakeTick()')
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
OnError((err, *) => (FileAppend("ERROR: " err.Message " at " err.Line "`n", "*"), ExitApp(1)))
global checks := 0, failures := 0

RunCase("normal completion", "", "", "Space,Enter,AltF4,Backspace", true)
RunCase("stop at end of initial wait", "start", "abort", "Space", false)
RunCase("focus lost at end of initial wait", "start", "focus", "Space", false)
RunCase("stop before Alt+F4", "confirm", "abort", "Space,Enter", false)
RunCase("focus lost before Alt+F4", "confirm", "focus", "Space,Enter", false)
RunCase("stop during quit wait", "quit", "abort", "Space,Enter,AltF4", false)
RunCase("focus loss cannot resume quit wait", "quit", "focus_then_return", "Space,Enter,AltF4", false)
RunCase("stop after prompt detected", "after_prompt", "abort", "Space,Enter,AltF4", false)
RunCase("focus lost after prompt detected", "after_prompt", "focus", "Space,Enter,AltF4", false)
RunCase("missing prompt times out", "", "timeout", "Space,Enter,AltF4", false)

Reset()
focused := false
ExecuteAltF4Teleport()
Check(events.Length = 0 && !altF4Running, "inactive entry sends nothing")
Reset()
teleportBusy := true
ExecuteAltF4Teleport()
Check(events.Length = 0 && !altF4Running, "other teleport owns input")
Reset()
gEarnBusy := true
ExecuteAltF4Teleport()
Check(events.Length = 0 && !altF4Running, "earner owns input")
Reset()
gAbort := true
Check(!WaitAbortable(0), "zero wait still observes stop")
Reset()
focused := false
Check(!WaitAbortable(0), "zero wait still observes focus")
Reset()
Check(WaitAbortable(0), "zero wait succeeds when input is allowed")

FileAppend((failures ? "FAIL" : "PASS") " AltF4Teleport: " checks " cases; no game input`n", "*")
ExitApp(failures ? 1 : 0)

RunCase(name, injectAt, action, expected, success) {
    global events, altF4Running, gJobWarpStart, logs
    Reset(injectAt, action)
    result := ExecuteAltF4Teleport()
    actual := ""
    for key in events
        actual .= (actual = "" ? "" : ",") key
    finished := logs.Length && logs[logs.Length] = (success ? "done" : "stopped")
    Check(actual = expected && !!result = success && !altF4Running && gJobWarpStart = 0 && finished,
        name " (input=" actual ", success=" (!!result) ")")
}
Check(condition, name) {
    global checks, failures
    checks += 1
    if (!condition) {
        failures += 1
        FileAppend("FAIL: " name "`n", "*")
    }
}
Reset(injectAt := "", action := "") {
    global config, gAbort, altF4Running, gJobWarpStart, gJobWarpMinMs, gEarnBusy
    global events, logs, focused, teleportBusy, fakeNow, phase, injected, injectionPhase, injectionAction, promptReady
    config := Map("Settings", Map("JobWarpStartToConfirmMs", 50, "JobWarpConfirmToAltF4Ms", 25,
        "JobWarpQuitWaitMs", 2000, "JobWarpMinWaitMs", 100, "JobWarpAfterPromptMs", 50))
    gAbort := false, altF4Running := false, gJobWarpStart := 0, gJobWarpMinMs := 0, gEarnBusy := false
    events := [], logs := [], focused := true, teleportBusy := false, fakeNow := 100
    phase := "", injected := false, injectionPhase := injectAt, injectionAction := action
    promptReady := action != "timeout"
}
FakeTick() {
    global fakeNow
    return fakeNow
}
Sleep(ms) {
    global fakeNow, injected, injectionPhase, injectionAction, phase, gAbort, focused
    fakeNow += ms
    if (injected) {
        if (injectionAction = "focus_then_return")
            focused := true
        return
    }
    if (phase != injectionPhase || injectionPhase = "")
        return
    injected := true
    if (injectionAction = "abort")
        gAbort := true
    else
        focused := false
}
IsGTAActive() {
    global focused
    return focused
}
IsTeleportRunning() {
    global teleportBusy
    return teleportBusy
}
QuitPromptReady() {
    global focused, promptReady
    return focused && promptReady
}
PressKey(key) {
    global events, phase
    events.Push(key)
    phase := key = "Space" ? "start" : key = "Enter" ? "confirm" : "complete"
}
Send(value) {
    global events, phase
    if (value != "{Blind}{Alt down}{F4}{Alt up}")
        throw Error("Unexpected Send: " value)
    events.Push("AltF4")
    phase := "quit"
}
MacroLog(tag, message) {
    global logs, phase
    logs.Push(message)
    if InStr(message, "prompt ready after")
        phase := "after_prompt"
}
OverlayVisible() => true
ShowAltF4Message(*) => 0
ShowTooltip(*) => 0
ToolTip(*) => 0
'@
$previous = [Console]::InputEncoding
[Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
try {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $AhkPath
    $info.Arguments = '/ErrorStdOut /CP65001 *'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    try {
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.WriteLine($driver + "`n" + $production)
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'AltF4 test timed out' }
        $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
        $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
        if ($process.ExitCode -ne 0 -or $stderr -or $stdout -ne 'PASS AltF4Teleport: 16 cases; no game input') {
            throw "exit=$($process.ExitCode) stdout=$stdout stderr=$stderr"
        }
        $stdout
    } finally { $process.Dispose() }
} finally { [Console]::InputEncoding = $previous }
