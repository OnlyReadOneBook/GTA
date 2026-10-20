#Requires -Version 5.1
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$source = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Teleport\FriendWarp.ahk') -Raw -Encoding UTF8
$functions = @('FriendWarpFindTarget', 'FriendWarpSameTarget', 'FriendWarpJoin', 'FriendWarpAnchor', 'FriendWarpWaitTrigger') | ForEach-Object {
    $body = [regex]::Match($source, ('(?ms)^' + $_ + '\([^\r\n]*\) \{.*?^\}')).Value
    if (-not $body) { throw "$_ missing" }
    $body
}
$production = $functions -join "`n"
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
OnError((err, *) => (FileAppend("ERROR: " err.Message " at " err.Line "`n", "*"), ExitApp(1)))
global checks := 0, failures := 0
global waitResult := true, waitedKey := ""
Check(FriendWarpWaitTrigger("$*ScrollLock") && waitedKey = "ScrollLock", "release actual trigger key before input guard")
waitResult := false
Check(!FriendWarpWaitTrigger("$*ScrollLock"), "held trigger timeout does not start")
waitedKey := ""
Check(FriendWarpWaitTrigger("") && waitedKey = "", "panel action needs no trigger key")
for row in [142, 226, 310, 394] {
    Reset(row)
    Check(FriendWarpFindTarget(&foundTarget, &why) && foundTarget.x = 1223 && foundTarget.y = row + 43, "name in row " row)
}
Reset(226)
marks.RemoveAt(3)
marks.Push(["join_game", 1196, 345, 54, 17])
Check(!FriendWarpFindTarget(&foundTarget, &why), "another friend's JOIN GAME must not match")
Reset(226)
marks.RemoveAt(3)
marks.Push(["invite_game", 1108, 261, 75, 17])
Check(!FriendWarpFindTarget(&foundTarget, &why), "INVITE TO GAME must not match")
Reset(226)
marks.RemoveAt(2)
Check(!FriendWarpFindTarget(&foundTarget, &why), "absent friend")
Reset(226)
marks.RemoveAt(1)
Check(!FriendWarpFindTarget(&foundTarget, &why), "absent Home header")
Reset(226)
marks.Push(["friend_name", 1108, 310, 72, 16])
Check(!FriendWarpFindTarget(&foundTarget, &why), "ambiguous duplicate name")
Reset(455)
Check(!FriendWarpFindTarget(&foundTarget, &why), "clipped button cannot select next panel")
for mutation in ["move", "button-gone", "stop", "cursor"] {
    Reset(226)
    change := mutation
    Check(!FriendWarpJoin(&why) && clicks = 0, "no click after " mutation)
}
Reset(226)
Check(FriendWarpJoin(&why) && clicks = 1 && closed = 1, "stable friend clicked once then overlay closed")
FileAppend((failures ? "FAIL" : "PASS") " FriendWarp: " checks " cases; no game input`n", "*")
ExitApp(failures ? 1 : 0)
Check(ok, name) {
    global checks, failures
    checks += 1
    if (!ok) {
        failures += 1
        FileAppend("FAIL " name "`n", "*")
    }
}
Reset(y) {
    global marks, clicks, closed, change, ready
    marks := [["home_tab",647,22,41,15], ["friend_name",1108,y,72,16], ["join_game",1196,y+35,54,17]]
    clicks := 0, closed := 0, change := "", ready := true
}
FriendWarpFind(name, area, &x, &y) {
    global marks
    for mark in marks {
        if (mark[1] != name)
            continue
        if (IsObject(area) && (mark[2] < area[1] || mark[3] < area[2] || mark[2]+mark[4]-1 > area[3] || mark[3]+mark[5]-1 > area[4]))
            continue
        x := mark[2], y := mark[3]
        return true
    }
    x := 0, y := 0
    return false
}
FriendWarpLocate(&foundTarget, &why) => FriendWarpFindTarget(&foundTarget, &why)
FriendWarpWait(*) {
    global marks, change, ready
    if (change = "move") {
        marks[2][3] += 84
        marks[3][3] += 84
    } else if (change = "button-gone")
        marks.RemoveAt(3)
    else if (change = "stop")
        ready := false
    change := ""
    return ready
}
FriendWarpGuard() {
    global ready
    return ready
}
FriendWarpClose() {
    global closed
    closed += 1
    return true
}
FriendWarpCursorTo(*) {
    global change
    return change != "cursor"
}
Click(*) {
    global clicks
    clicks += 1
}
MacroLog(*) => 0
KeyWait(key, options) {
    global waitedKey, waitResult
    waitedKey := key
    return waitResult && options = "T1"
}
'@
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
    if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'FriendWarp test timed out' }
    $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
    $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
    if ($process.ExitCode -ne 0 -or $stderr -or $stdout -ne 'PASS FriendWarp: 18 cases; no game input') {
        throw "exit=$($process.ExitCode) stdout=$stdout stderr=$stderr"
    }
    $stdout
} finally { $process.Dispose() }
