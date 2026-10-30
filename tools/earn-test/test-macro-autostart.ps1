#Requires -Version 5.1
# GTA 가 켜지는 순간 Main.ahk 를 띄우는 감시(Features\MacroAutoStart.ahk)의 회귀 검사. Run·ProcessExist·WinExist·SetTimer 는 스텁이라 실제 실행·창 조회가 없다.
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..\..'
$source = Get-Content (Join-Path $root 'Features\MacroAutoStart.ahk') -Raw -Encoding UTF8
$watch = Get-Content (Join-Path $root 'CasinoVpnWatch.ahk') -Raw -Encoding UTF8
$config = Get-Content (Join-Path $root 'Config.ini') -Raw -Encoding UTF8
if ($watch -notmatch '(?m)^#Include Features\\MacroAutoStart\.ahk\r?$' -or $watch -notmatch 'StartMacroAutoStartWatch\(\)') {
    throw 'The logon watcher must include and start the macro autostart watch.'
}
if ($config -notmatch '(?m)^MacroAutoStart=1\r?$') { throw 'Tracked Config.ini must keep macro autostart on.' }

$production = [regex]::Replace($source, '(?ms)^MacroAutoStartLog\(msg\) \{.*?^\}', 'MacroAutoStartLog(msg) => logs.Push(msg)')
if ($production -match 'FileAppend') { throw 'Log file write remains in the autostart fixture.' }
if ($production -notmatch '(?m)^MacroAutoStartLaunch\(mainPath\) \{' -or $production -notmatch "try Run\('`"' A_AhkPath '`" `"' mainPath '`"', A_ScriptDir\)") {
    throw 'Launcher must call Run with the AutoHotkey runtime, the Main.ahk path and the script directory.'
}

$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global gameRunning := false, mainRunning := false, launches := [], logs := [], timers := [], failRun := false
global mainPath := "C:\fake\GTA\Main.ahk"
@PRODUCTION@
try {
    StartMacroAutoStartWatch(mainPath)
    Check(launches.Length = 0 && timers.Length = 1 && timers[1].period = 1000, "watch start without the game launches nothing and polls every second")
    tick := timers[1].fn
    tick.Call()
    Check(launches.Length = 0, "game still off: no launch")
    gameRunning := true
    tick.Call()
    Check(launches.Length = 1 && launches[1].target = '"' A_AhkPath '" "' mainPath '"' && launches[1].dir = A_ScriptDir, "game appearing launches Main.ahk once")
    tick.Call(), tick.Call()
    Check(launches.Length = 1, "game staying on does not launch again")
    mainRunning := true, gameRunning := false
    tick.Call()
    gameRunning := true
    tick.Call()
    Check(launches.Length = 1, "game restart while Main runs does not launch a second copy")
    mainRunning := false, gameRunning := false
    tick.Call()
    gameRunning := true, failRun := true
    tick.Call()
    Check(launches.Length = 1 && logs.Length > 0 && InStr(logs[logs.Length], "실행 실패"), "launch failure is logged and swallowed")
    failRun := false, gameRunning := false
    tick.Call()
    gameRunning := true
    tick.Call()
    Check(launches.Length = 2, "next game start retries after a failed launch")

    Reset()
    gameRunning := true, mainRunning := false
    StartMacroAutoStartWatch(mainPath)
    Check(launches.Length = 1, "watch starting with the game already on launches Main when it is not running")

    Reset()
    gameRunning := true, mainRunning := true
    StartMacroAutoStartWatch(mainPath)
    Check(launches.Length = 0, "watch starting with the game and Main on launches nothing")
    FileAppend("PASS MacroAutoStart: 9 cases; Run stubbed; no process or window access`n", "*")
    ExitApp(0)
} catch as fixtureError {
    FileAppend("FAIL MacroAutoStart: " fixtureError.Message " line=" fixtureError.Line "`n", "**")
    ExitApp(1)
}
Check(value, message) {
    if (!value)
        throw Error(message)
}
Reset() {
    global launches := [], logs := [], timers := [], failRun := false, gameRunning := false, mainRunning := false
}
Run(target, dir) {
    if (failRun)
        throw Error("launch refused")
    launches.Push({target: target, dir: dir})
}
ProcessExist(name) => (name = "GTA5_Enhanced.exe" && gameRunning) ? 1 : 0
WinExist(spec) => (InStr(spec, mainPath) && mainRunning) ? 1 : 0
SetTimer(fn, period) => timers.Push({fn: fn, period: period})
'@
$driver = $driver.Replace('@PRODUCTION@', $production)
$expected = '^PASS MacroAutoStart: 9 cases; Run stubbed; no process or window access$'

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
        $process.StandardInput.WriteLine($driver)
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'MacroAutoStart fixture timed out' }
        $stdout = $process.StandardOutput.ReadToEnd().Trim()
        $stderr = $process.StandardError.ReadToEnd().Trim()
        if ($process.ExitCode -ne 0 -or $stderr -or $stdout -notmatch $expected) {
            throw "MacroAutoStart fixture exit=$($process.ExitCode) stdout=$stdout stderr=$stderr"
        }
        $stdout
    } finally { $process.Dispose() }
} finally { [Console]::InputEncoding = $previous }
