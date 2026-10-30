#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
    [string]$BaselineRevision = ''
)
$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..\..'
if ($BaselineRevision) {
    $source = (& git -C $root show ($BaselineRevision + ':Features/DiscordHUD.ahk')) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read requested baseline' }
    $production = [regex]::Match($source, '(?ms)^DiscordHUDVisibilityWanted\(\) \{.*?^\}').Value
    if (-not $production -or -not $production.Contains('AwayMode')) { throw 'Expected old away-wide hiding policy' }
    $driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
global config := Map("Settings", Map("AwayMode", 1)), gEarnOn := true, gDiscordHUDLeases := 0
if (!DiscordHUDVisibilityWanted())
    ExitApp(1)
FileAppend("EXPECTED_REPRO: away earning hides HUD without MCT`n", "*")
ExitApp(0)
'@
    $expected = '^EXPECTED_REPRO: away earning hides HUD without MCT$'
} else {
    $source = Get-Content (Join-Path $root 'Features\DiscordHUD.ahk') -Raw -Encoding UTF8
    $production = $source.Substring($source.IndexOf('global gDiscordHUDMCTOpen'))
    $tasks = Get-Content (Join-Path $root 'Features\Earn\EarnTasks.ahk') -Raw -Encoding UTF8
    $production += "`n" + [regex]::Match($tasks, '(?ms)^EarnUIReady\([^\r\n]*\) \{.*?^\}').Value
    foreach ($name in @('DiscordHUDWindowList','DiscordHUDWindowRead','DiscordHUDWindowVisible','DiscordHUDOwnedPath','DiscordHUDOwnedSave','DiscordHUDOwnedLoad')) {
        $production = [regex]::Replace($production, ('(?ms)^' + $name + '\([^\r\n]*\) \{.*?^\}\s*'), '')
    }
    if ($production -match 'DllCall\(|WinGet|ShowWindow|WinActivate|\bRun\(|FileAppend|FileRead|FileDelete') { throw 'Native side effect remains in HUD fixture' }
    if (-not $source.Contains('DiscordHUDMainWindowIdentity(title, WinGetProcessName("ahk_id " hwnd))') -or
        -not $source.Contains('GetProcessTimes') -or -not $source.Contains('visible ? 8 : 0')) {
        throw 'Exact HUD identity and non-activating visibility boundary must be retained'
    }
    $driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global n := 0, windows := Map(), writes := [], logs := [], failWrite := false, failRead := false
global timers := [], exits := [], gEarnOn := true, config := Map("Settings", Map("AwayMode", 1))
global gEarnBusy := false, focused := true, gameExists := true, GTA_WIN := "fake", health := true
global gEarnGuardArmed := false, gAbort := false, gEarnUserAbort := false
global templates := Map(), probeReads := [], probeBackground := true
global abortNow := false, abortOnHide := "", persisted := Map()
@PRODUCTION@
try {
    windows[1] := Window(1), windows[2] := Window(2, false)
    windows[3] := Window(3, true, "DiscordChatHUD Config · C# Preview 337")
    windows[4] := Window(4, true, "계정 연결")
    windows[5] := Window(5), windows[5].minimized := true
    DiscordHUDVisibilityInit()
    Check(timers.Length = 1 && exits.Length = 1, "timer and exit hook")
    Check(timers[1].period = 1000 && timers[1].priority = -10, "low priority timer")
    Check(windows[1].visible && gDiscordHUDOwned.Count = 0, "away earning idle stays visible")
    for name in ["ph_joblist_sel", "afk_vinewood_title", "safe_prompt", "staff"]
        Check(DiscordHUDMCTObserved(name, true) && windows[1].visible, "phone app safe staff stays visible: " name)
    for name in ["bunker_page", "bunker_entry", "bunker_confirm", "bunker_pending", "nc_dj_menu", "nc_home", "dj_solomun", "warehouse_title", "mct_title"]
        Check(DiscordHUDMCTObserved(name, true) && windows[1].visible && !gDiscordHUDMCTOpen, "manual screen never starts hiding: " name)
    templates := Map("mct_title", true, "bunker_page", true, "warehouse_title", true), health := false
    Loop 12
        DiscordHUDVisibilityTick()
    Check(windows[1].visible && !gDiscordHUDMCTOpen && probeReads.Length = 0, "idle never scans or hides manual MCT and business pages")
    gEarnBusy := true, gEarnGuardArmed := true
    for name in ["bunker_page", "bunker_confirm", "nc_dj_menu", "dj_confirm_solomun", "warehouse_title"]
        Check(DiscordHUDMCTObserved(name, true) && windows[1].visible && !gDiscordHUDMCTOpen, "business page cannot create an MCT latch even during guarded work: " name)
    DiscordHUDMCTSet(true)
    Check(!windows[1].visible && gDiscordHUDOwned.Count = 1, "MCT opening synchronously hides")
    Check(!windows[2].visible && windows[3].visible && windows[4].visible && windows[5].visible, "other windows unchanged")
    DiscordHUDVisibilityTick()
    Check(writes.Length = 1, "idempotent")
    windows[1].visible := true
    DiscordHUDVisibilityTick()
    Check(!windows[1].visible && writes.Length = 2, "reappeared HUD hidden during MCT")
    config["Settings"]["AwayMode"] := 0, gEarnOn := false
    DiscordHUDVisibilityTick()
    Check(!windows[1].visible, "guarded MCT cleanup can run with scheduler off")
    Check(!DiscordHUDMCTObserved("mct_title", false) && !windows[1].visible, "missing template not close proof")
    for name in ["bunker_page", "bunker_confirm", "bunker_pending", "nc_dj_menu", "dj_confirm_solomun", "dj_confirm_tale", "warehouse_title"]
        Check(DiscordHUDMCTObserved(name, true) && !windows[1].visible, "MCT subpage remains hidden: " name)
    DiscordHUDMCTObserved("mct_seated", true)
    Check(windows[1].visible && gEarnBusy, "restore before standing CEO and chair recovery")
    Check(!windows[2].visible && gDiscordHUDOwned.Count = 0, "original hidden preserved")
    count := logs.Length
    DiscordHUDMCTSet(false)
    Check(logs.Length = count, "restore logged once per actual change")
    for name in ["mct_sit", "mct_terrorbyte"] {
        DiscordHUDMCTSet(true)
        DiscordHUDMCTObserved(name, true)
        Check(windows[1].visible, "closed prompt restores: " name)
    }
    DiscordHUDMCTSet(true)
    focused := false
    DiscordHUDVisibilityTick()
    Check(windows[1].visible && !gDiscordHUDMCTOpen, "focus away restores and clears MCT ownership")
    focused := true
    DiscordHUDVisibilityTick()
    Check(windows[1].visible, "focus back cannot resurrect stale MCT hiding")
    DiscordHUDMCTSet(true)
    gEarnBusy := false, gEarnGuardArmed := false
    DiscordHUDVisibilityTick()
    Check(windows[1].visible && !gDiscordHUDMCTOpen, "macro ending restores even while MCT stays on screen")
    DiscordHUDMCTSet(true)
    Check(windows[1].visible && !gDiscordHUDMCTOpen, "unguarded MCT open cannot hide")
    DiscordHUDVisibilityTick()
    Check(windows[1].visible && probeReads.Length = 0, "manual MCT remains visible without screen reads")
    gEarnBusy := true, gEarnGuardArmed := true
    DiscordHUDMCTObserved("mct_title", true)
    Check(!windows[1].visible, "guarded macro MCT recovery can confirm title and hide")
    for boundary in ["abort", "user", "guard"] {
        DiscordHUDMCTSet(true)
        gAbort := boundary = "abort", gEarnUserAbort := boundary = "user", gEarnGuardArmed := boundary != "guard"
        DiscordHUDVisibilityTick()
        Check(windows[1].visible && !gDiscordHUDMCTOpen, "inactive macro clears protection: " boundary)
        gAbort := false, gEarnUserAbort := false, gEarnGuardArmed := true
    }
    DiscordHUDMCTSet(true)
    gameExists := false
    DiscordHUDVisibilityTick()
    Check(windows[1].visible && !gDiscordHUDMCTOpen, "game exit clears cached state")
    gameExists := true, gEarnBusy := true, gEarnGuardArmed := true
    for changed in ["pid", "created", "title"] {
        windows[1] := Window(1)
        DiscordHUDMCTSet(true)
        if (changed = "title")
            windows[1].title := "계정 연결"
        else
            windows[1].%changed% += 1
        DiscordHUDMCTSet(false)
        Check(!windows[1].visible && gDiscordHUDOwned.Count = 0, "identity change never restored: " changed)
    }
    windows[1] := Window(1), failWrite := true, rejected := false
    try DiscordHUDMCTSet(true)
    catch {
        rejected := true
    }
    Check(rejected && windows[1].visible && !gDiscordHUDMCTOpen, "hide failure rejects entry")
    failWrite := false
    DiscordHUDMCTSet(true)
    failWrite := true
    Check(EarnUIReady("mct_seated"), "confirmed seated screen continues game cleanup despite restore failure")
    Check(DiscordHUDMCTSet(false), "explicit close continues standing and CEO cleanup despite restore failure")
    Check(!windows[1].visible && gDiscordHUDOwned.Has(1) && !gDiscordHUDMCTOpen, "restore failure retains ownership and closed state")
    Check(gDiscordHUDError = "HUD 원상복구 미확인", "deferred restoration remains an observable failure")
    count := logs.Length
    DiscordHUDVisibilityTick()
    Check(!windows[1].visible && gDiscordHUDOwned.Has(1) && logs.Length = count, "failed retry preserves ownership without duplicate error log")
    failWrite := false
    DiscordHUDVisibilityTick()
    Check(windows[1].visible && !gDiscordHUDOwned.Has(1), "timer retries restore")
    Check(gDiscordHUDError = "" && logs.Length = count + 1, "observed restoration clears error and logs completion")
    failRead := true, rejected := false
    try DiscordHUDMCTSet(true)
    catch {
        rejected := true
    }
    Check(rejected && !gDiscordHUDMCTOpen, "identity failure rejects entry")
    failRead := false
    DiscordHUDMCTSet(true)
    failWrite := true
    DiscordHUDMCTStop()
    Check(!gDiscordHUDMCTOpen && gDiscordHUDOwned.Has(1), "stop swallows restore failure but retains retry ownership")
    failWrite := false
    DiscordHUDVisibilityTick()
    Check(windows[1].visible && !gDiscordHUDOwned.Has(1), "failed synchronous stop is retried")
    DiscordHUDMCTSet(true)
    windows.Delete(1)
    DiscordHUDMCTSet(false)
    Check(gDiscordHUDOwned.Count = 0, "destroyed ownership discarded")
    windows[1] := Window(1)
    DiscordHUDMCTSet(true)
    DiscordHUDVisibilityExit()
    Check(windows[1].visible && !windows[2].visible, "exit restores only owned")
    for boundary in ["physical", "focus"] {
        abortNow := false, focused := true, abortOnHide := ""
        DiscordHUDMCTSet(false)
        DiscordHUDMCTSet(true)
        windows[1].visible := true, abortOnHide := boundary
        Check(!EarnUIReady("bunker_confirm"), "input or focus change during hiding rejects final screen-ready: " boundary)
        abortOnHide := "", abortNow := false, focused := true
        DiscordHUDMCTSet(false)
    }
    Check(EarnUIReady("afk_vinewood_title") && windows[1].visible, "real screen-ready keeps Vinewood HUD visible")
    for title in ["DiscordChatHUD C#", "WukChatHUD"]
        Check(DiscordHUDMainWindowIdentity(title, "DiscordChatHUD.exe"), "confirmed main HUD title: " title)
    for title in ["WukChatHUD · 설정", "WukChatHUD Store session", "계정 연결", "WukChatHUD other"]
        Check(!DiscordHUDMainWindowIdentity(title, "DiscordChatHUD.exe"), "non-main window excluded: " title)
    Check(!DiscordHUDMainWindowIdentity("WukChatHUD", "other.exe"), "foreign process excluded")
    windows[1] := Window(1, true, "WukChatHUD")
    windows[3] := Window(3, true, "WukChatHUD · 설정")
    DiscordHUDMCTSet(true)
    Check(!windows[1].visible && windows[3].visible, "Store main hidden without touching settings")
    DiscordHUDMCTSet(false)
    Check(windows[1].visible, "Store main restored after MCT")
    ; 매크로 교체: 숨긴 기록이 남은 창을 다음 매크로가 이어받아 복원한다. 기록에 없는 숨은 창(windows[2])은 그대로 둔다.
    DiscordHUDMCTSet(true)
    Check(!windows[1].visible && persisted.Has(1) && persisted[1].pid = windows[1].pid, "hidden ownership persisted")
    gDiscordHUDOwned := Map(), gDiscordHUDMCTOpen := false, gEarnBusy := false
    DiscordHUDVisibilityInit()
    Check(windows[1].visible && !gDiscordHUDOwned.Has(1) && persisted.Count = 0, "replaced macro adopts persisted hidden HUD and restores it")
    Check(!windows[2].visible, "unrecorded hidden window stays hidden")
    gEarnBusy := true
    DiscordHUDMCTSet(true)
    windows[1].pid += 1
    gDiscordHUDOwned := Map(), gDiscordHUDMCTOpen := false, gEarnBusy := false
    DiscordHUDVisibilityInit()
    Check(!windows[1].visible && gDiscordHUDOwned.Count = 0, "identity mismatch is not adopted")
    FileAppend("PASS DiscordHUD: " n " cases; no window or game input`n", "*")
    ExitApp(0)
} catch as fixtureFailure {
    FileAppend("FAIL DiscordHUD: " fixtureFailure.Message " line=" fixtureFailure.Line "`n", "**")
    ExitApp(1)
}
Check(ok, message) {
    global n
    n += 1
    if (!ok)
        throw Error(message)
}
Window(id, visible := true, title := "DiscordChatHUD C#") => {hwnd: id, pid: 100+id, created: 12345, title: title, visible: visible, minimized: false}
DiscordHUDWindowList() => [1, 2, 3, 4, 5]
DiscordHUDOwnedSave(owned) {
    global persisted
    persisted := Map()
    for hwnd, saved in owned
        persisted[hwnd] := {hwnd: saved.hwnd, pid: saved.pid, created: saved.created, title: saved.title}
}
DiscordHUDOwnedLoad() => persisted.Clone()
DiscordHUDWindowRead(hwnd) {
    if (failRead)
        throw Error("identity unavailable")
    if (!windows.Has(hwnd) || !DiscordHUDMainWindowIdentity(windows[hwnd].title, "DiscordChatHUD.exe"))
        return false
    return windows[hwnd].Clone()
}
DiscordHUDWindowVisible(hwnd, visible) {
    global abortNow, focused
    if (failWrite)
        return false
    windows[hwnd].visible := visible
    writes.Push({hwnd: hwnd, visible: visible})
    if (!visible && abortOnHide != "") {
        abortNow := true
        if (abortOnHide = "focus")
            focused := false
    }
    return true
}
IsGTAActive() => focused && gameExists
WinExist(*) => gameExists
ProcessExist(*) => true
HealthHudVisible() => health
TemplateSeen(folder, name, area, &x := 0, &y := 0, variation := 40) {
    probeReads.Push(name)
    return templates.Get(name, false)
}
TemplateAt(*) => probeBackground
EarnSeen(*) => true
EarnAborted() => abortNow || !focused
MacroLog(kind, message) => logs.Push(message)
SetTimer(fn, period, priority) => timers.Push({fn: fn, period: period, priority: priority})
OnExit(fn) => exits.Push(fn)
'@
    $driver = $driver.Replace('@PRODUCTION@', $production)
    $production = ''
    $expected = '^PASS DiscordHUD: 82 cases; no window or game input$'
}
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
        $process.StandardInput.WriteLine($driver + "`n" + $production)
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'HUD fixture timed out' }
        $stdout = $process.StandardOutput.ReadToEnd().Trim()
        $stderr = $process.StandardError.ReadToEnd().Trim()
        if ($process.ExitCode -ne 0 -or $stderr -or $stdout -notmatch $expected) {
            throw "HUD fixture exit=$($process.ExitCode) stdout=$stdout stderr=$stderr"
        }
        $stdout
    } finally { $process.Dispose() }
} finally { [Console]::InputEncoding = $previous }
