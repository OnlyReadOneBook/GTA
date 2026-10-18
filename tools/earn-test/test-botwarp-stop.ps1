#Requires -Version 5.1
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$source = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Teleport\BotWarp.ahk') -Raw -Encoding UTF8
$functions = @('BotWarpSteamJoin', 'BotWarpSteamClick', 'BotWarpSteamWait', 'BotWarpStopPressed') | ForEach-Object {
    $body = [regex]::Match($source, ('(?ms)^' + $_ + '\([^\r\n]*\) \{.*?^\}')).Value
    if (-not $body) { throw "$_ missing" }
    $body
}
$production = ($functions -join "`n").Replace('A_TickCount', 'FakeTick()')
# Only these production functions are loaded. Every OS input/window call is a stub.
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
OnError((err, *) => (FileAppend("ERROR: " err.Message " at " err.Line "`n", "*"), ExitApp(1)))
global checks := 0, failures := 0
for action in ["abort", "physical_stop", "focus"] {
    Reset(80, action)
    ok := BotWarpSteamClick(10, 20, "Left", "ahk_id 1", &why)
    Check(!ok && events.Length = 0 && why != "", "click wait interrupted: " action)
    for boundary in [230, 330] {
        Reset(boundary, action)
        ok := BotWarpSteamJoin(1, &why)
        expected := boundary = 230 ? "click:Left" : "click:Left,{Blind}^a"
        Check(!ok && EventText() = expected && why != "", "filter wait " boundary " interrupted: " action " (" EventText() ")")
    }
}
for action in ["abort", "physical_stop"] {
    Reset(790, action)
    ok := BotWarpSteamJoin(1, &why)
    Check(!ok && why != "" && EventText() = "click:Left,{Blind}^a,{Blind}{U+0041},{Blind}{U+0042},click:Right,click:Left",
        "stop after Join Game prevents returning to game: " action)
}
Reset()
Check(BotWarpSteamClick(10, 20, "Left", "ahk_id 1", &why) && EventText() = "click:Left", "normal click")
Reset()
Check(BotWarpSteamJoin(1, &why) && EventText() = "click:Left,{Blind}^a,{Blind}{U+0041},{Blind}{U+0042},click:Right,click:Left", "normal join")
Reset()
gAbort := true
Check(!BotWarpSteamClick(10, 20, "Left", "ahk_id 1", &why) && events.Length = 0, "stopped entry")
Reset()
focused := false
Check(!BotWarpSteamClick(10, 20, "Left", "ahk_id 1", &why) && events.Length = 0, "inactive entry")
Reset()
cursorOk := false
Check(!BotWarpSteamClick(10, 20, "Left", "ahk_id 1", &why) && events.Length = 0, "cursor failure")
Reset(50, "abort")
Check(!BotWarpSteamWait(50), "final wait boundary observes stop")
FileAppend((failures ? "FAIL" : "PASS") " BotWarp stop: " checks " cases; no game input`n", "*")
ExitApp(failures ? 1 : 0)

Check(condition, name) {
    global checks, failures
    checks += 1
    if (!condition) {
        failures += 1
        FileAppend("FAIL: " name "`n", "*")
    }
}
Reset(at := -1, action := "") {
    global config, gAbort, focused, physicalStop, cursorOk, fakeNow, injectAt, injectAction, injected, events
    global BOTWARP_FILTER_OFS, BOTWARP_BOT_OFS, BOTWARP_JOIN_OFS, BOTWARP_JOIN_SEARCH
    global BOTWARP_FILTER_TEXT, BOTWARP_STEAM_EXE, BOTWARP_CHAT_W, BOTWARP_CHAT_H
    config := Map("Settings", Map("BotWarpSteamStepMs", 0, "BotWarpSteamFilterMs", 0, "BotWarpBotRow", 1), "Hotkeys", Map("StopAll", "End"))
    BOTWARP_FILTER_OFS := [0, 0], BOTWARP_BOT_OFS := [[0, 0]], BOTWARP_JOIN_OFS := [0, 0], BOTWARP_JOIN_SEARCH := 1
    BOTWARP_FILTER_TEXT := "AB", BOTWARP_STEAM_EXE := "steam.exe", BOTWARP_CHAT_W := 100, BOTWARP_CHAT_H := 100
    gAbort := false, focused := true, physicalStop := false, cursorOk := true, fakeNow := 0
    injectAt := at, injectAction := action, injected := false, events := []
}
EventText() {
    global events
    text := ""
    for event in events
        text .= (text = "" ? "" : ",") event
    return text
}
FakeTick() {
    global fakeNow
    return fakeNow
}
Sleep(ms) {
    global fakeNow, injectAt, injectAction, injected, gAbort, physicalStop, focused
    fakeNow += ms
    if (!injected && injectAt >= 0 && fakeNow >= injectAt) {
        injected := true
        if (injectAction = "abort")
            gAbort := true
        else if (injectAction = "physical_stop")
            physicalStop := true
        else
            focused := false
    }
}
WinActive(*) {
    global focused
    return focused
}
GetKeyState(*) {
    global physicalStop
    return physicalStop
}
BotWarpCursorTo(*) {
    global cursorOk
    return cursorOk
}
Click(value) {
    global events
    events.Push("click:" value)
}
Send(value) {
    global events
    events.Push(value)
}
BotWarpPlaceChat(chat, &x, &y, &why) {
    x := 0, y := 0, why := ""
    return true
}
BotWarpSteamRef(name, x1, y1, x2, y2, &x, &y) {
    x := 0, y := 0
    return 1
}
WinExist(*) => 1
BotWarpActivate(*) => true
DllCall(*) => 1
MacroLog(*) => 0
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
        if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'BotWarp test timed out' }
        $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
        $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
        if ($process.ExitCode -ne 0 -or $stderr -or $stdout -ne 'PASS BotWarp stop: 17 cases; no game input') {
            throw "exit=$($process.ExitCode) stdout=$stdout stderr=$stderr"
        }
        $stdout
    } finally { $process.Dispose() }
} finally { [Console]::InputEncoding = $previous }
