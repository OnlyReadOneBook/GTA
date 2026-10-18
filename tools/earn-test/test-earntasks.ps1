#Requires -Version 5.1
<#
Runs the actual EarnTasks.ahk functions with all game dependencies replaced.
No game input, screen reads, window activation, or Main.ahk execution.
Run: powershell -NoProfile -ExecutionPolicy Bypass -File tools/earn-test/test-earntasks.ps1
#>
[CmdletBinding()]
param(
    [string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
)

$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $PSScriptRoot '..\..\Features\Earn\EarnTasks.ahk'
$sourceText = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8
$script:earnCaseTotal = 0
if (-not (Test-Path -LiteralPath $AhkPath -PathType Leaf)) {
    throw "AutoHotkey executable not found: $AhkPath"
}

function Get-EarnFunctionBody {
    param([string]$Text, [string]$FunctionName)
    $pattern = '(?ms)^' + [regex]::Escape($FunctionName) + '\([^\r\n]*\) \{.*?^\}'
    $functionMatches = [regex]::Matches($Text, $pattern)
    if ($functionMatches.Count -ne 1) {
        throw "Expected one source function: $FunctionName ($($functionMatches.Count))"
    }
    return $functionMatches[0].Value
}

function Invoke-EarnOfflineCheck {
    param(
        [string]$Name,
        [string]$FunctionName,
        [string]$Driver,
        [int]$CaseCount
    )

    $functionBody = Get-EarnFunctionBody $sourceText $FunctionName
    if ($Name -eq 'TurnGuard') {
        $functionBody += "`n" + (Get-EarnFunctionBody $sourceText 'EarnTurnLoop')
    }
    if ($Name -eq 'MCTEndDeadline') {
        $functionBody = $functionBody.Replace('A_TickCount', 'CleanupClock()')
    }
    if ($Name -eq 'MCTBegin') {
        $functionBody = $functionBody.Replace('A_TickCount', 'SpotClock()')
    }
    $prefix = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global transactionPending := Map()
global gEarnSkipOcr := false
global stockNotices := [], stockNoticeSources := [], stockNoticeClears := [], gEarnSellNotices := Map()
global fixtureHudHidden := false, requireHudBeforeCEO := false
EarnTransactionBegin(id, reason) {
    transactionPending[id] := reason
    return true
}
EarnTransactionConfirmed(id) => transactionPending.Delete(id)
EarnTransactionCashConfirmed(id, direction, amount, source, evidence, path := "") {
    EarnTransactionConfirmed(id)
    return true
}
EarnNotifyStockFull(source, reason) {
    global stockNotices, stockNoticeSources, gEarnSellNotices
    if (gEarnSellNotices.Get(source, "") = reason)
        return true
    gEarnSellNotices[source] := reason
    stockNoticeSources.Push(source)
    stockNotices.Push(reason)
    return true
}
EarnClearStockNotice(source) {
    global stockNoticeClears, gEarnSellNotices
    if (gEarnSellNotices.Has(source)) {
        stockNoticeClears.Push(source)
        gEarnSellNotices.Delete(source)
    }
}
; EarnTasks tests extract individual task functions, not EarnCore's screen helpers.
EarnMCTSitOcrSeen() => false
EarnOcrLines(key, area, whiteText) => false
EarnMCTSeatedOcrMatches(lines) => false
EarnBossOffIfOn() => true
EarnMCTNeedCeoOcrMatches(lines) => false
EarnMCTTitleOcrMatches(lines) => false
DiscordHUDMCTSet(open) {
    global fixtureHudHidden
    fixtureHudHidden := open
    return true
}
OnError(EarnOfflineFailure)
EarnOfflineFailure(failure, *) {
    FileAppend("FAIL offline runtime: " failure.Message "`n", "**")
    ExitApp(1)
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
    $info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $testProcess = [Diagnostics.Process]::Start($info)
    try {
        $testProcess.StandardInput.WriteLine($prefix + $Driver + "`n" + $functionBody)
        $testProcess.StandardInput.Close()
        if (-not $testProcess.WaitForExit(10000)) {
            $testProcess.Kill()
            $testProcess.WaitForExit()
            throw "$Name : AHK check timed out after 10 seconds"
        }
        $stdout = $testProcess.StandardOutput.ReadToEnd().Trim()
        $stderr = $testProcess.StandardError.ReadToEnd().Trim()
        $expected = "PASS $Name cases=$CaseCount"
        if ($testProcess.ExitCode -ne 0 -or $stderr -ne '' -or $stdout -ne $expected) {
            throw "$Name failed (exit=$($testProcess.ExitCode))`nstdout: $stdout`nstderr: $stderr"
        }
        Write-Output $stdout
        $script:earnCaseTotal += $CaseCount
    } finally {
        if (-not $testProcess.HasExited) {
            $testProcess.Kill()
            $testProcess.WaitForExit()
        }
        $testProcess.Dispose()
    }
}

$spawnDriver = @'
global config := Map("Settings", Map("EarnReachPx", 14))
global routeCase := []
; Name, safe seen/distance/plan/goal, laptop seen/distance/plan/goal, expected route.
cases := [
    ["edge path", false, 0, false, 0, true, 999, true, 80, "laptop"],
    ["edge no path", false, 0, false, 0, true, 999, false, 0, ""],
    ["office reachable", false, 0, false, 0, true, 80, true, 30, "laptop"],
    ["office blocked", false, 0, false, 0, true, 80, true, 31, ""],
    ["safe preferred", true, 60, true, 14, true, 999, true, 80, "safe"],
    ["safe blocked fallback", true, 60, true, 15, true, 999, true, 80, "laptop"],
    ["edge safe ignored", true, 999, true, 10, false, 0, false, 0, ""],
    ["no blips", false, 0, false, 0, false, 0, false, 0, ""]
]
for testCase in cases {
    routeCase := testCase
    actual := EarnSpawnRoute()
    if (actual != testCase[10]) {
        FileAppend("FAIL " testCase[1] ": expected=" testCase[10] " actual=" actual Chr(10), "*", "UTF-8")
        ExitApp(1)
    }
}
FileAppend("PASS SpawnRoute cases=8" Chr(10), "*", "UTF-8")
ExitApp(0)
EarnBlip(name, &angle, &distance) {
    global routeCase
    base := name = "safe" ? 2 : 6
    angle := 0
    distance := routeCase[base + 1]
    return routeCase[base]
}
EarnNavPlan(name, &angle, &step, &goal) {
    global routeCase
    base := name = "safe" ? 2 : 6
    angle := 0, step := 10, goal := routeCase[base + 3]
    return routeCase[base + 2]
}
'@

$collectDriver = @'
global EARN_PROMPT_AREA := [], mode := "", presses := 0, walks := 0, opened := false
cases := [["MissingOpen", false, 0, 0], ["FaceFail", false, 1, 0], ["ClosedEmpty", true, 1, 0], ["OpenEmpty", true, 0, 0], ["OpenMoney", true, 0, 1]]
for c in cases {
    mode := c[1], presses := 0, walks := 0, opened := InStr(mode, "Open") = 1
    result := EarnSafeCollect()
    if (result != c[2] || presses != c[3] || walks != c[4]) {
        FileAppend("FAIL " mode ": result=" result " presses=" presses " walks=" walks Chr(10), "*", "UTF-8")
        ExitApp(1)
    }
}
FileAppend("PASS SafeCollect cases=5" Chr(10), "*", "UTF-8")
ExitApp(0)
EarnSeen(name, area := "") {
    global mode, opened, walks
    if (name = "safe_prompt")
        return !opened && mode != "MissingOpen"
    if (name = "hud_safe_zero")
        return mode != "FaceFail" && (mode != "OpenMoney" || walks > 0)
    return name = "safe_close_prompt" && opened
}
EarnPress(*) {
    global presses, opened
    presses += 1
    opened := !opened
    return true
}
EarnWalk(*) {
    global walks
    walks += 1
    return true
}
EarnFace(*) => mode != "FaceFail"
EarnFail(*) => false
EarnSleep(*) => true
EarnLog(*) => true
EarnWaitGone(*) => true
'@

$placeDriver = @'
global EARN_MENU_AREA := [], openOk := true, seenOk := true, closeOk := true, closeCalls := 0
cases := [[true, true, true, true, 1], [true, true, false, false, 1], [true, false, true, false, 1], [false, true, true, false, 0]]
for c in cases {
    openOk := c[1], seenOk := c[2], closeOk := c[3], closeCalls := 0
    result := EarnInPlace("Arcade")
    if (result != c[4] || closeCalls != c[5]) {
        FileAppend("FAIL EarnInPlace" Chr(10), "*", "UTF-8")
        ExitApp(1)
    }
}
FileAppend("PASS InPlace cases=4" Chr(10), "*", "UTF-8")
ExitApp(0)
EarnMenuOpen() {
    global openOk
    return openOk
}
EarnSeen(*) {
    global seenOk
    return seenOk
}
EarnMenuClose() {
    global closeOk, closeCalls
    closeCalls += 1
    return closeOk
}
'@

$homeDriver = @'
global config := Map("Settings", Map("EarnWalkRetry", 3)), atMCT := false, inArcade := false, walkFirst := true, walkCalls := 0, order := "", laptopSeated := false, standOk := true, reloadOk := true
; Existing MCT, inside success/failure, outside success/failure, session entry failure.
cases := [[true,false,true,true,"",true], [false,true,true,true,"IW",true], [false,true,false,true,"IW",false],
    [false,false,true,true,"IRW",true], [false,false,false,true,"IRW",false], [false,false,true,false,"IR",false]]
for c in cases {
    atMCT := c[1], inArcade := c[2], walkFirst := c[3], reloadOk := c[4], walkCalls := 0, order := ""
    result := EarnGoHome()
    if (result != c[6] || order != c[5] || walkCalls > 1) {
        FileAppend("FAIL Home order=" order Chr(10), "*", "UTF-8")
        ExitApp(1)
    }
}
laptopSeated := true, standOk := true, atMCT := false, inArcade := true, walkFirst := true, order := ""
if (!EarnGoHome() || order != "DUVIW")
    throw Error("Laptop recovery must stand and verify before walking: " order)
standOk := false, order := ""
if (EarnGoHome() || order != "DUV")
    throw Error("Failed laptop exit must not navigate: " order)
FileAppend("PASS GoHome cases=8" Chr(10), "*", "UTF-8")
ExitApp(0)
EarnAtMCT() {
    global atMCT
    return atMCT
}
EarnInPlace(*) {
    global inArcade, order
    order .= "I"
    return inArcade
}
EarnWalkToMCT() {
    global walkFirst, walkCalls, order
    order .= "W", walkCalls += 1
    return walkFirst
}
EarnGoTo(*) {
    FileAppend("FAIL GoHome must not use repeated destination search`n", "*")
    ExitApp(1)
}
EarnReloadInto(place, direction) {
    global order
    if (place != "Arcade" || direction != "Right")
        throw Error("Unexpected session destination")
    order .= "R"
    return reloadOk
}
EarnAborted() => false
EarnFail(*) => false
EarnLog(*) => true
EarnRejoin(*) {
    FileAppend("FAIL GoHome must not rejoin after navigation failure`n", "*")
    ExitApp(1)
}
EarnSeen(name,*) => name = "arcade_laptop_seated" && laptopSeated
Click(key) {
    global order
    order .= key = "Right Down" ? "D" : "U"
}
Sleep(*) => true
EarnSleep(*) => true
EarnWaitGone(*) {
    global order
    order .= "V"
    return standOk
}
'@

$safeDriver = @'
global config := Map("Settings", Map("EarnSafeRetryMin", 15, "EarnRerollMax", 12)), gEarnFail := "", gSafeCollectedTick := 0, homeOk := true, homeCalls := 0, softCalls := 0, inCalls := 0
global seated := false, closeOk := true, closeCalls := 0
for c in [[true, false], [false, false], [true, true]] {
    homeOk := c[1], gSafeCollectedTick := c[2] ? A_TickCount : 0, homeCalls := 0, softCalls := 0, inCalls := 0
    result := EarnSafeTask()
    if (result != homeOk || homeCalls != 1 || softCalls != (homeOk ? 0 : 1) || !gSafeCollectedTick || inCalls != (c[2] ? 0 : 1)) {
        FileAppend("FAIL SafeTask empty return" Chr(10), "*", "UTF-8")
        ExitApp(1)
    }
}
for allowed in [true,false] {
    seated := true, closeOk := allowed, closeCalls := 0, gSafeCollectedTick := 0, inCalls := 0
    if (EarnSafeTask() != allowed || closeCalls != 1 || inCalls != (allowed ? 1 : 0))
        throw Error("Safe visit must leave the MCT chair before opening interaction menus")
}
FileAppend("PASS SafeTask cases=5" Chr(10), "*", "UTF-8")
ExitApp(0)
EarnAtMCT() => seated
EarnMCTClose() {
    global closeCalls
    closeCalls++
    return closeOk
}
EarnGoHome() {
    global homeOk, homeCalls
    homeCalls += 1
    return homeOk
}
EarnSoftFail(*) {
    global softCalls
    softCalls += 1
    return false
}
EarnInPlace(*) {
    global inCalls
    inCalls += 1
    return true
}
EarnSeen(*) => true
EarnLog(*) => true
EarnAborted() => false
EarnReloadInto(*) => false
EarnFail(*) => false
EarnSpawnRoute(*) => ""
EarnWalkToSafeVia(*) => false
EarnRejoin(*) => false
EarnSafeCollect(*) => false
'@

# Avoid a UTF-8 BOM in AHK stdin on Windows PowerShell 5.1; restore on exit.
$previousInputEncoding = [Console]::InputEncoding
try {
    [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
    Invoke-EarnOfflineCheck 'SpawnRoute' 'EarnSpawnRoute' $spawnDriver 8
    Invoke-EarnOfflineCheck 'SafeCollect' 'EarnSafeCollect' $collectDriver 5
    Invoke-EarnOfflineCheck 'InPlace' 'EarnInPlace' $placeDriver 4
    Invoke-EarnOfflineCheck 'GoHome' 'EarnGoHome' $homeDriver 8
    Invoke-EarnOfflineCheck 'SafeTask' 'EarnSafeTask' $safeDriver 5
    $atMCTDriver = @'
global EARN_PROMPT_AREA := [], visible := ""
for c in [["mct_sit",false],["arcade_laptop_seated",false],["mct_seated",true],["mct_title",true]] {
    visible := c[1]
    if (EarnAtMCT() != c[2])
        throw Error("MCT identity mismatch: " visible)
}
FileAppend("PASS AtMCT cases=4`n", "*")
ExitApp(0)
EarnSeen(name,*) => name = visible
'@
    Invoke-EarnOfflineCheck 'AtMCT' 'EarnAtMCT' $atMCTDriver 4
    $seatDriver = @'
global EARN_PROMPT_AREA := [], prompt := true, mctSeated := true, presses := 0
for c in [[true,true,true,1],[true,false,false,1],[false,false,false,0]] {
    prompt := c[1], mctSeated := c[2], presses := 0
    if (EarnConfirmMCTSeat() != c[3] || presses != c[4])
        throw Error("Generic sit prompt cannot confirm MCT arrival")
}
FileAppend("PASS MCTSeat cases=3`n", "*")
ExitApp(0)
EarnSeen(*) => prompt
EarnPress(key) {
    global presses
    if (key != "e")
        throw Error("Unexpected input")
    presses++
    return true
}
EarnWaitSeen(name,*) => name = "mct_seated" && mctSeated
EarnFail(*) => false
'@
    Invoke-EarnOfflineCheck 'MCTSeat' 'EarnConfirmMCTSeat' $seatDriver 3
    $basementDriver = @'
global mode := "", order := ""
for c in [["spawn",false,"S"],["walk",false,"SW"],["sleep",false,"SWL"],
    ["blip",false,"SWLB"],["edge",false,"SWLB"],["plan",false,"SWLBP"],
    ["goal",false,"SWLBP"],["nav",false,"SWLBPN"],["seat",false,"SWLBPNC"],["ok",true,"SWLBPNC"]] {
    mode := c[1], order := ""
    if (EarnArcadeBasementToMCT() != c[2] || order != c[3]) {
        FileAppend("FAIL Basement route " mode " order=" order "`n", "*")
        ExitApp(1)
    }
}
FileAppend("PASS BasementRoute cases=10`n", "*")
ExitApp(0)
EarnArcadeBasementReady() {
    global order
    order .= "S"
    return mode != "spawn"
}
EarnWalk(path) {
    global order
    order .= "W"
    if (!RegExMatch(path, "^w:\d+$"))
        throw Error("Basement traversal must use the guarded forward segment")
    return mode != "walk"
}
EarnSleep(*) {
    global order
    order .= "L"
    return mode != "sleep"
}
EarnBlip(name, &a, &d) {
    global order
    order .= "B", a := 0, d := mode = "edge" ? 999 : 62
    return name = "mct" && mode != "blip"
}
EarnNavPlan(name, &t, &s, &g) {
    global order
    order .= "P", t := 0, s := 10, g := mode = "goal" ? 15 : 14
    return name = "mct" && mode != "plan"
}
EarnNavTo(name, prompt) {
    global order
    order .= "N"
    return name = "mct" && prompt = "mct_sit" && mode != "nav"
}
EarnConfirmMCTSeat() {
    global order
    order .= "C"
    return mode != "seat"
}
EarnFail(*) => false
EarnLog(*) => true
'@
    Invoke-EarnOfflineCheck 'BasementRoute' 'EarnArcadeBasementToMCT' $basementDriver 10
    $basementReadyDriver = @'
global blip := true, measuredAngle := 51.5, measuredDistance := 93, scene := true
for c in [[true,51.5,93,true,true],[false,51.5,93,true,false],
    [true,100,93,true,false],[true,51.5,20,true,false],[true,51.5,999,true,false],
    [true,51.5,93,false,false],[true,55,110,true,true]] {
    blip := c[1], measuredAngle := c[2], measuredDistance := c[3], scene := c[4]
    if (EarnArcadeBasementReady() != c[5])
        throw Error("Basement starting position must match direction, distance and scene")
}
FileAppend("PASS BasementReady cases=7`n", "*")
ExitApp(0)
EarnBlip(name,&a,&d) {
    a := measuredAngle, d := measuredDistance
    return name = "laptop" && blip
}
EarnSeen(name,*) => name = "arcade_basement_spawn" && scene
'@
    Invoke-EarnOfflineCheck 'BasementReady' 'EarnArcadeBasementReady' $basementReadyDriver 7
    $djDriver = @'
cases := [[-1,95,false],[0,95,true],[80,95,true],[86,95,true],[90,95,true],[90.1,95,true],[94,95,true],[95,95,false],[100,95,false],[80,80,false]]
for c in cases {
    if (EarnDJNeedsRebook(c[1],c[2]) != c[3])
        throw Error("DJ boundary " c[1])
}
FileAppend("PASS DJRebook cases=10`n", "*")
ExitApp(0)
'@
    Invoke-EarnOfflineCheck 'DJRebook' 'EarnDJNeedsRebook' $djDriver 10
    $mctDriver = @'
global config := Map("Settings", Map("EarnMCTOnly",1)), scene := "", failAt := "", order := "", softRetry := 0, spotClockMs := 0, sweepCalls := 0
global gEarnManualStop := false
for c in [["list","",true,"OR"],["stand","",true,"OR"],["chair","",true,"OR"],
    ["need-ceo","",true,"OR"],["away","",false,""],["list","O",false,"OE"],
    ["stand","O",false,"OE"],["stand","R",false,"ORE"],["flicker","",true,"OR"],["sweep","",false,""]] {
    scene := c[1], failAt := c[2], order := "", softRetry := 0, spotClockMs := 0, sweepCalls := 0
    if (EarnTaskMCTBegin() != c[3] || order != c[4])
        throw Error("MCT begin guard: " c[1] "/" c[2] " order=" order)
    if ((c[1] = "away" || c[1] = "sweep") && softRetry != 3)
        throw Error("MCT begin away must retry later instead of stopping")
    if (sweepCalls != 0)
        throw Error("MCT begin must wait without camera input when no prompt is seen: " c[1] " calls=" sweepCalls)
}
FileAppend("PASS MCTBegin cases=10`n", "*")
ExitApp(0)
EarnUIReady(name,*) => EarnSeen(name)
EarnAtMCT() => scene = "list" || scene = "chair" || scene = "need-ceo"
EarnSeen(name,*) => name = "mct_sit" && scene = "stand" || name = "mct_title" && scene = "list"
    || name = "mct_seated" && scene = "chair" || name = "mct_need_ceo" && scene = "need-ceo"
EarnMCTClose() {
    throw Error("MCT entry must preserve an existing terminal or seated state")
}
EarnCEO(on) {
    throw Error("MCT entry must not use the interaction menu to register")
}
EarnMCTOpen() {
    global order, failAt
    order .= "O"
    return failAt != "O"
}
EarnMCTRefresh() {
    global order, failAt
    order .= "R"
    return failAt != "R"
}
EarnTaskMCTEnd() {
    global order
    order .= "E"
    return true
}
EarnTaskMCTEndWithManualRetry() => EarnTaskMCTEnd()
EarnGoHome(*) {
    throw Error("MCT tasks must not travel")
}
EarnSleep(ms) {
    global scene, spotClockMs
    if (scene = "flicker")
        scene := "stand"
    spotClockMs += ms
    return true
}
SpotClock() => spotClockMs
EarnAborted() => false
EarnMCTSpotSweep() {
    global sweepCalls
    sweepCalls += 1
    return false
}
EarnSoftFail(reason, retryMin) {
    global softRetry := retryMin
    return false
}
EarnFail(*) => false
'@
    Invoke-EarnOfflineCheck 'MCTBegin' 'EarnTaskMCTBegin' $mctDriver 10
    $mctCleanupSupport = @'
EarnAborted() => endAbort
EarnWaitSeen(name,area,timeoutMs) {
    expectedArea := name = "mct_sit" ? [0,0,0.3,0.1] : name = "bunker_page" ? [0.15,0,0.35,0.12] : []
    if (timeoutMs != 3000 || expectedArea.Length != 4 || !(area is Array) || area.Length != 4)
        throw Error("Cleanup wait must use a known prompt/page and three-second deadline")
    for index,value in expectedArea
        if (area[index] != value)
            throw Error("Cleanup wait must stay in its bounded prompt/page region")
    return EarnUIReady(name)
}
EarnUIReady(name,*) {
    global endScene
    if (name = endScene)
        return true
    ; Parent page remains visible behind known confirmation dialogs.
    return name = "bunker_page" && (endScene = "bunker_confirm" || endScene = "bunker_pending")
        || name = "nc_dj_menu" && InStr(endScene,"dj_confirm_") = 1
}
EarnUIClick(name,x,y,*) {
    global endScene, endFailure, endOrder
    if (!EarnUIReady(name))
        throw Error("Cleanup clicked an unconfirmed screen")
    if (name = "bunker_confirm") {
        if (x != 850 || y != 619)
            throw Error("Cleanup must never confirm a bunker purchase")
        endOrder .= "x", nextScene := "bunker_page"
    } else if (name = "bunker_pending") {
        if (x != 960 || y != 619)
            throw Error("Unexpected bunker acknowledgement coordinate")
        endOrder .= "p", nextScene := "bunker_page"
    } else if (name = "dj_confirm_solomun" || name = "dj_confirm_tale") {
        if (x != 750 || y != 628)
            throw Error("Cleanup must only click the observed left DJ Cancel")
        endOrder .= "d", nextScene := "nc_dj_menu"
    } else if (name = "nc_dj_menu") {
        if (x != 495 || y != 596)
            throw Error("Nightclub cleanup must first choose Home")
        endOrder .= "H", nextScene := "nc_dj_menu"
    } else {
        throw Error("Unexpected cleanup click " name)
    }
    if (endFailure = "click")
        return EarnFail("cleanup click rejected")
    endScene := endFailure = "unknown_after_click" ? "unknown" : endFailure = "modal_fade" ? "fading_page" : nextScene
    return true
}
EarnWaitGone(*) => endFailure != "gone"
EarnSleep(*) => endFailure != "sleep"
EarnUIBackToMCT(guard,presses) {
    global endScene, endFailure, endOrder
    if (!EarnUIReady(guard))
        throw Error("Cleanup back from unknown screen")
    if (guard = "bunker_page" && presses = 2)
        endOrder .= "B2"
    else if (guard = "bunker_entry" && presses = 1)
        endOrder .= "E1"
    else if (guard = "nc_dj_menu" && presses = 1)
        endOrder .= "N1"
    else
        throw Error("Cleanup exceeded a confirmed back route")
    if (endFailure = "back")
        return EarnFail("cleanup back failed")
    if (endFailure != "back_unchanged")
        endScene := "mct_title"
    return true
}
EarnMCTClose(requireChairPrompt := true, &terminalKind := "") {
    global endScene, endFailure, endOrder
    if (requireChairPrompt)
        throw Error("CEO retirement must not wait to reacquire the chair prompt")
    if (endScene != "mct_title" && endScene != "mct_seated" && endScene != "mct_need_ceo")
        throw Error("Close without confirmed MCT state")
    endOrder .= "C"
    if (endFailure = "close_error")
        throw Error("cleanup close exception")
    if (endFailure = "close")
        return EarnFail("cleanup close failed")
    endScene := "mct_standing"
    terminalKind := endFailure = "terrorbyte" ? "terrorbyte" : "chair"
    return true
}
EarnCEO(on) {
    global endScene, endFailure, endOrder, endBoss
    if (!on && requireHudBeforeCEO && fixtureHudHidden)
        throw Error("Delayed closed-screen confirmation must restore HUD before CEO retirement")
    if (on) {
        endOrder .= "+"
        if (endFailure = "register")
            return EarnFail("registration failed")
        endBoss := true
        if (endFailure = "register_error")
            throw Error("registration exception")
        return true
    }
    if (endScene != "mct_sit" && endScene != "mct_standing" && endScene != "mct_terrorbyte")
        throw Error("Retire attempted before returning to confirmed standing state")
    endOrder .= "-"
    if (endFailure = "retire")
        return EarnFail("cleanup retire failed")
    endBoss := false
    return true
}
EarnTerrorbyteMCTReady() => !endBoss
EarnMCTReturnReady(terminalKind) {
    global endScene, endBoss
    if (terminalKind = "terrorbyte")
        return EarnTerrorbyteMCTReady()
    if (terminalKind != "chair")
        throw Error("Unknown return kind")
    if (endBoss || endScene != "mct_standing")
        throw Error("Chair alignment must follow CEO retirement")
    endScene := "mct_sit"
    return true
}
EarnFail(reason) {
    global gEarnFail, endLogs
    gEarnFail := reason
    endLogs.Push(reason)
    return false
}
'@
    $mctEndDriver = @'
global endScene := "", endFailure := "", endOrder := "", endAbort := false, endBoss := true, gEarnFail := "", endLogs := []
cases := [
 ["mct_title","",false,"original",true,"C-"],
 ["mct_seated","",false,"original",true,"C-"],
 ["mct_need_ceo","",false,"original",true,"C-"],
 ["mct_sit","",false,"original",true,"-"],
 ["unknown","",false,"original",false,""],
 ["mct_title","",true,"original",false,""],
 ["bunker_confirm","",false,"original",true,"xB2C-"],
 ["bunker_pending","",false,"original",true,"pB2C-"],
 ["bunker_page","",false,"original",true,"B2C-"],
 ["bunker_entry","",false,"original",true,"E1C-"],
 ["nc_dj_menu","",false,"original",true,"HN1C-"],
 ["dj_confirm_solomun","",false,"original",true,"dHN1C-"],
 ["dj_confirm_tale","",false,"original",true,"dHN1C-"],
 ["mct_title","close",false,"original",false,"C"],
 ["mct_title","retire",false,"original",false,"C-"],
 ["bunker_confirm","click",false,"original",false,"x"],
 ["bunker_confirm","gone",false,"original",false,"x"],
 ["bunker_pending","click",false,"original",false,"p"],
 ["bunker_pending","gone",false,"original",false,"p"],
 ["dj_confirm_solomun","click",false,"original",false,"d"],
 ["dj_confirm_tale","gone",false,"original",false,"d"],
 ["bunker_page","back",false,"original",false,"B2"],
 ["nc_dj_menu","click",false,"original",false,"H"],
 ["nc_dj_menu","sleep",false,"original",false,"H"],
 ["nc_dj_menu","back",false,"original",false,"HN1"],
 ["bunker_confirm","unknown_after_click",false,"original",false,"x"],
 ["bunker_page","back_unchanged",false,"original",false,"B2"],
 ["unknown","",false,"",false,""],
 ["mct_title","close",false,"",false,"C"],
 ["mct_title","",false,"",true,"C-"],
 ["mct_sit","retire",false,"original",false,"-"],
 ["mct_title","close_error",false,"original",false,"C"],
 ["mct_terrorbyte","",false,"original",true,"-"],
 ["mct_terrorbyte","retire",false,"original",false,"-"],
 ["mct_title","terrorbyte",false,"original",true,"C-"]
]
for c in cases {
    endScene := c[1], endFailure := c[2], endAbort := c[3], gEarnFail := c[4], endOrder := "", endLogs := [], endBoss := true
    result := EarnTaskMCTEnd()
    if (result != c[5] || endOrder != c[6] || (result && endBoss))
        throw Error("MCT cleanup: " c[1] "/" c[2] " order=" endOrder " result=" result)
    if (c[4] != "" && gEarnFail != c[4])
        throw Error("Cleanup replaced the original task failure")
    if (c[4] = "" && ((!result && gEarnFail = "") || (result && gEarnFail != "")))
        throw Error("Cleanup must retain its own failure only when no prior failure exists")
}
FileAppend("PASS MCTEnd cases=35`n", "*")
ExitApp(0)
'@
    $mctEndDriver += "`n" + $mctCleanupSupport
    Invoke-EarnOfflineCheck 'MCTEnd' 'EarnTaskMCTEnd' $mctEndDriver 35
    $deadlineDriver = @'
global endScene := "unknown", endFailure := "", endOrder := "", endAbort := false, endBoss := true, gEarnFail := "original", endLogs := []
global clockMs := 0, reads := 0, abortRead := 0, foundRead := 0
for scenario in [0,1,2,3] {
    interrupted := scenario = 1
    clockMs := 0, reads := 0, endAbort := false, endOrder := "", endLogs := [], abortRead := interrupted ? 2 : 0, foundRead := scenario = 2 ? 11 : 0
    result := EarnTaskMCTEnd()
    if (result || endOrder != "" || gEarnFail != "original")
        throw Error("Slow cleanup must not input or erase the original failure")
    if (reads != (scenario = 3 ? 720 : interrupted ? 2 : 11) || clockMs != (scenario = 3 ? 12000 : interrupted ? 2200 : 12100))
        throw Error("Cleanup exceeded its elapsed deadline: reads=" reads " elapsed=" clockMs)
    for message in endLogs
        if (InStr(message,"오류"))
            throw Error("Cleanup attempted a forbidden read: " message)
}
FileAppend("PASS MCTEndDeadline cases=4`n", "*")
ExitApp(0)
CleanupClock() => clockMs
EarnUIReady(name, area := "") {
    global clockMs, reads, endAbort
    if (clockMs >= 12000 || endAbort)
        throw Error("Another screen read started after the deadline or interruption")
    if ((name = "mct_title" || name = "mct_seated") && !IsObject(area))
        throw Error("Cleanup searched the whole screen for a known bounded menu")
    reads++, clockMs += scenario = 3 ? 0 : 1100
    if (abortRead && reads = abortRead)
        endAbort := true
    return foundRead && reads = foundRead
}
EarnSleep(ms) {
    global clockMs
    clockMs += ms
    return !endAbort
}
'@
    $deadlineSupport = $mctCleanupSupport.Replace((Get-EarnFunctionBody $mctCleanupSupport 'EarnUIReady'), '')
    $deadlineSupport = $deadlineSupport.Replace('EarnSleep(*) => endFailure != "sleep"', '')
    $deadlineDriver += "`n" + $deadlineSupport
    Invoke-EarnOfflineCheck 'MCTEndDeadline' 'EarnTaskMCTEnd' $deadlineDriver 4
    $mctEndPromptDriver = @'
global endScene := "", endFailure := "", endOrder := "", endAbort := false, endBoss := true, gEarnFail := "", endLogs := []
global cleanupClockMs := 0, cleanupPromptAt := -1, cleanupAbortAt := -1, cleanupWaits := 0, cleanupPromptName := "mct_sit"
; Initial scene, prompt arrival, interruption, result, inputs, elapsed, wait calls.
for c in [["transition",1200,-1,true,"-",1200,1],
    ["transition",4000,-1,false,"",3000,1],
    ["transition",1200,400,false,"",400,1],
    ["mct_title",1200,-1,true,"C-",0,0],
    ["mct_sit",1200,-1,true,"-",0,0],
    ["bunker_pending",1200,-1,true,"pB2C-",1200,1,"bunker_page"],
    ["bunker_confirm",1200,-1,true,"xB2C-",1200,1,"bunker_page"],
    ["bunker_pending",4000,-1,false,"p",3000,1,"bunker_page"],
    ["bunker_pending",1200,400,false,"p",400,1,"bunker_page"]] {
    endScene := c[1], cleanupPromptAt := c[2], cleanupAbortAt := c[3],
        endOrder := "", endAbort := false, endBoss := true, gEarnFail := "original", endLogs := [],
        cleanupClockMs := 0, cleanupWaits := 0
    cleanupPromptName := c.Length = 8 ? c[8] : "mct_sit", endFailure := c.Length = 8 ? "modal_fade" : ""
    fixtureHudHidden := true, requireHudBeforeCEO := c[1] = "transition"
    result := EarnTaskMCTEnd()
    if (result != c[4] || endOrder != c[5] || cleanupClockMs != c[6] || cleanupWaits != c[7])
        throw Error("Cleanup prompt wait " c[1] " result=" result " input=" endOrder " elapsed=" cleanupClockMs " waits=" cleanupWaits)
    if (gEarnFail != "original" || (result && endBoss))
        throw Error("Delayed cleanup must retain the original failure and confirm retirement")
}
FileAppend("PASS MCTEndPrompt cases=9`n", "*")
ExitApp(0)
EarnSeen(name,*) => EarnUIReady(name)
EarnWaitSeen(name,area,timeoutMs) {
    global cleanupWaits
    expectedArea := name = "mct_sit" ? [0,0,0.3,0.1] : name = "bunker_page" ? [0.15,0,0.35,0.12] : []
    if (timeoutMs != 3000 || expectedArea.Length != 4 || !(area is Array) || area.Length != 4)
        throw Error("Cleanup wait must use a known prompt/page and three-second deadline")
    for index,value in expectedArea
        if (area[index] != value)
            throw Error("Cleanup wait must stay in its bounded prompt/page region")
    cleanupWaits++
    return FixtureCleanupWaitSeen(name,area,timeoutMs)
}
CleanupClock() => cleanupClockMs
Sleep(ms) {
    global cleanupClockMs, endAbort, endScene
    cleanupClockMs += ms
    if (cleanupAbortAt >= 0 && cleanupClockMs >= cleanupAbortAt)
        endAbort := true
    if (!endAbort && cleanupPromptAt >= 0 && cleanupClockMs >= cleanupPromptAt)
        endScene := cleanupPromptName
}
'@
    $promptCoreText = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnCore.ahk') -Raw -Encoding UTF8
    $cleanupPollingBody = (Get-EarnFunctionBody $promptCoreText 'EarnWaitSeen').Replace('EarnWaitSeen(', 'FixtureCleanupWaitSeen(').Replace('A_TickCount', 'CleanupClock()')
    $cleanupPromptSupport = $mctCleanupSupport.Replace((Get-EarnFunctionBody $mctCleanupSupport 'EarnWaitSeen'), '') + "`nEarnLog(*) => true`n"
    $mctEndPromptDriver += "`n" + $cleanupPromptSupport + "`n" + $cleanupPollingBody
    Invoke-EarnOfflineCheck 'MCTEndPrompt' 'EarnTaskMCTEnd' $mctEndPromptDriver 9
    $mctBeginCleanupDriver = @'
global config := Map(), endScene := "mct_sit", endFailure := "", endOrder := "", endAbort := false, endBoss := false, gEarnFail := "", endLogs := []
global gEarnManualStop := false
global beginFailure := "", beginFailedScene := ""
cases := [
 ["open","mct_sit",false,"O-",false],
 ["open","mct_seated",false,"OC-",false],
 ["open","unknown",false,"O",false],
 ["refresh","bunker_entry",false,"ORE1C-",false],
 ["refresh","bunker_page",false,"ORB2C-",false],
 ["refresh","bunker_confirm",false,"ORxB2C-",false],
 ["refresh","unknown",false,"OR",true],
 ["register","mct_need_ceo",false,"ORC-",false],
 ["","mct_title",true,"OR",true]
]
for c in cases {
    beginFailure := c[1], beginFailedScene := c[2], endScene := "mct_sit", endFailure := "",
        endOrder := "", endBoss := false, gEarnFail := "", endLogs := []
    result := EarnTaskMCTBegin()
    if (result != c[3] || endOrder != c[4] || endBoss != c[5])
        throw Error("Begin cleanup: " c[1] "/" c[2] " order=" endOrder)
    if ((c[1] = "open" && gEarnFail != "opening failed") || (c[1] = "refresh" && gEarnFail != "refresh failed"))
        throw Error("Begin cleanup erased its original failure")
}
; A successful registration can be followed by a native screen-reading error.
; Cleanup errors are caught by the real End function and must not replace it.
for c in [["open_error","mct_seated","",false,"OC-",false,"opening exception"],
    ["refresh_error","bunker_page","",false,"ORB2C-",false,"refresh exception"],
    ["register_error","mct_need_ceo","",false,"ORC-",false,"registration exception"],
    ["open_error","mct_seated","close_error",false,"OC",false,"opening exception"],
    ["refresh_error","bunker_page","",true,"OR",true,"refresh exception"]] {
    beginFailure := c[1], beginFailedScene := c[2], endFailure := c[3], endAbort := c[4],
        endScene := "mct_sit", endOrder := "", endBoss := false, gEarnFail := "", endLogs := []
    caught := ""
    try EarnTaskMCTBegin()
    catch as beginException
        caught := beginException.Message
    if (caught != c[7] || endOrder != c[5] || endBoss != c[6])
        throw Error("Begin exception cleanup: " c[1] " order=" endOrder " exception=" caught)
}
FileAppend("PASS MCTBeginCleanup cases=14`n", "*")
ExitApp(0)
EarnAtMCT() => endScene = "mct_title" || endScene = "mct_seated"
EarnSeen(name,*) => EarnUIReady(name)
EarnMCTOpen() {
    global endScene, endOrder, beginFailure, beginFailedScene
    endOrder .= "O"
    if (beginFailure = "open" || beginFailure = "open_error") {
        endScene := beginFailedScene
        if (beginFailure = "open_error")
            throw Error("opening exception")
        return EarnFail("opening failed")
    }
    endScene := "mct_title"
    return true
}
EarnMCTRefresh() {
    global endScene, endOrder, beginFailure, beginFailedScene, endBoss
    endOrder .= "R"
    if (beginFailure = "register") {
        endScene := beginFailedScene
        return EarnFail("registration failed")
    }
    endBoss := true
    if (beginFailure = "register_error") {
        endScene := beginFailedScene
        throw Error("registration exception")
    }
    if (beginFailure = "refresh" || beginFailure = "refresh_error") {
        endScene := beginFailedScene
        if (beginFailure = "refresh_error")
            throw Error("refresh exception")
        return EarnFail("refresh failed")
    }
    return true
}
EarnTaskMCTEndWithManualRetry() => EarnTaskMCTEnd()
'@
    $mctBeginCleanupDriver += "`n" + $mctCleanupSupport + "`n" + (Get-EarnFunctionBody $sourceText 'EarnTaskMCTEnd')
    $mctBeginCleanupDriver += "`nEarnSoftFail(reason, *) => EarnFail(reason)`n"
    $mctBeginCleanupDriver += "`nEarnMCTSpotSweep() => false`n"
    Invoke-EarnOfflineCheck 'MCTBeginCleanup' 'EarnTaskMCTBegin' $mctBeginCleanupDriver 14
    $mctRefreshDriver = @'
global refreshOptions := Map(), refreshClockMs := 0, refreshAborted := false, refreshFocused := true,
    refreshClicks := 0, refreshCtrl := 0, refreshCtrlAt := -1, refreshLastClickAt := 0,
    refreshBacks := 0, refreshLogs := 0, refreshFailure := "", refreshHover := false, refreshCursorClears := 0,
    gEarnBunkerFull := false
; Options, result, card clicks, LCtrl attempts, confirmed business exits, registration logs.
for c in [[Map("alreadyBoss",true),true,1,0,1,0],
    [Map("alreadyBoss",true,"business","bunker_page"),false,1,0,0,0],
    [Map(),true,2,1,1,1],
    [Map("business","bunker_page"),false,2,1,0,0],
    [Map("promptAfter",600,"registerAfter",1200,"titleAfter",400,"businessAfter",500),true,2,1,1,1],
    [Map("promptWithoutTitle",true),false,1,0,0,0],
    [Map("registerAfter",9000),false,1,1,0,0],
    [Map("titleAfter",4000),false,1,1,0,0],
    [Map("repeatedPrompt",true),false,2,1,0,0],
    [Map("rejectCtrl",true),false,1,1,0,0],
    [Map("rejectClick",2),false,2,1,0,0],
    [Map("promptAfter",600,"abortAt",400),false,1,0,0,0],
    [Map("registerAfter",1200,"abortAt",400),false,1,1,0,0],
    [Map("registerAfter",1200,"focusLostAt",400),false,1,1,0,0],
    [Map("businessAfter",9000),false,2,1,0,0],
    [Map("noResponse",true),false,2,0,0,0],
    [Map("rejectClick",1),false,1,0,0,0],
    [Map("rejectBack",true),false,2,1,1,1],
    [Map("promptAfter",7000,"registerAfter",1000,"businessAfter",7900),true,3,1,1,1],
    [Map("alreadyBoss",true,"businessAfter",1200),true,1,0,1,0],
    [Map("alreadyBoss",true,"rejectCursorClear",true),false,1,0,0,0],
    [Map("alreadyBoss",true,"abortCursorClear",true),false,1,0,0,0],
    [Map("alreadyBoss",true,"focusCursorClear",true),false,1,0,0,0]] {
    refreshOptions := c[1], refreshClockMs := 0, refreshAborted := false, refreshFocused := true,
        refreshClicks := 0, refreshCtrl := 0, refreshCtrlAt := -1, refreshLastClickAt := 0,
        refreshBacks := 0, refreshLogs := 0, refreshFailure := "", refreshHover := false, refreshCursorClears := 0
    result := EarnMCTRefresh()
    if (result != c[2] || refreshClicks != c[3] || refreshCtrl != c[4] || refreshBacks != c[5] || refreshLogs != c[6])
        throw Error("MCT register case " A_Index " result=" result " clicks=" refreshClicks " ctrl=" refreshCtrl " backs=" refreshBacks " logs=" refreshLogs)
    if (refreshCtrl > 1 || refreshClicks > 3)
        throw Error("MCT registration must never retry LCtrl or click the card more than three times")
    if (result && (refreshHover || !refreshCursorClears))
        throw Error("Business screen must be read only after its cursor obstruction is cleared")
    if (refreshOptions.Get("registerAfter",0) = 9000 && refreshClockMs != 8000)
        throw Error("Registration disappearance wait exceeded its eight-second deadline")
    if (refreshOptions.Get("titleAfter",0) = 4000 && refreshClockMs != 3000)
        throw Error("Registration list recovery wait exceeded its three-second deadline")
    if (refreshOptions.Get("promptAfter",0) = 7000 && refreshClockMs < 15000)
        throw Error("Business arrival must use a fresh deadline after successful registration")
}
; 재고 만재 여부와 관계없이 등록·갱신은 나이트클럽 카드만 사용한다.
gEarnBunkerFull := true
for c in [[Map("alreadyBoss",true,"business","nc_dj_menu"),true,1,0,1,0],
    [Map("business","nc_dj_menu"),true,2,1,1,1]] {
    refreshOptions := c[1], refreshClockMs := 0, refreshAborted := false, refreshFocused := true,
        refreshClicks := 0, refreshCtrl := 0, refreshCtrlAt := -1, refreshLastClickAt := 0,
        refreshBacks := 0, refreshLogs := 0, refreshFailure := "", refreshHover := false, refreshCursorClears := 0
    result := EarnMCTRefresh()
    if (result != c[2] || refreshClicks != c[3] || refreshCtrl != c[4] || refreshBacks != c[5] || refreshLogs != c[6])
        throw Error("MCT nightclub refresh case " A_Index " result=" result " clicks=" refreshClicks " ctrl=" refreshCtrl " backs=" refreshBacks " logs=" refreshLogs)
}
FileAppend("PASS MCTRefresh cases=25`n", "*")
ExitApp(0)
EarnSeen(name,*) {
    alreadyBoss := refreshOptions.Get("alreadyBoss",false)
    registeredAt := refreshCtrlAt < 0 ? -1 : refreshCtrlAt + refreshOptions.Get("registerAfter",0)
    if (name = "mct_need_ceo") {
        if (alreadyBoss || !refreshClicks || refreshOptions.Get("noResponse",false))
            return false
        if (refreshCtrlAt >= 0 && refreshClicks >= 2)
            return refreshOptions.Get("repeatedPrompt",false)
        return refreshHover && refreshClockMs >= refreshOptions.Get("promptAfter",0)
            && (refreshCtrlAt < 0 || refreshClockMs < registeredAt)
    }
    if (name = "mct_title") {
        if ((refreshOptions.Get("promptWithoutTitle",false) && refreshClicks) || RefreshBusinessFrame())
            return false
        return refreshCtrlAt < 0 || refreshClockMs >= registeredAt + refreshOptions.Get("titleAfter",0)
    }
    if (name = "bunker_entry" || name = "bunker_page" || name = "nc_dj_menu") {
        return RefreshBusinessFrame() && !refreshHover && name = refreshOptions.Get("business","nc_dj_menu")
    }
    return false
}
EarnUIReady(name,*) => !EarnAborted() && EarnSeen(name)
RefreshBusinessFrame() {
    ready := (refreshOptions.Get("alreadyBoss",false) && refreshClicks >= 1) || (refreshCtrlAt >= 0 && refreshClicks >= 2 && refreshLastClickAt >= refreshCtrlAt)
    return ready && !refreshOptions.Get("repeatedPrompt",false) && !refreshOptions.Get("noResponse",false)
        && refreshClockMs >= refreshLastClickAt + refreshOptions.Get("businessAfter",0)
}
EarnUIClick(name,x,y,area := "",clearCursor := true) {
    global refreshClicks, refreshLastClickAt, refreshHover, refreshCursorClears
    if (EarnAborted() || name != "mct_nightclub_card"
        || x != 520 || y != 525 || !EarnSeen("mct_title"))
        throw Error("MCT refresh must use nightclub without opening an unneeded bunker")
    ; 첫 클릭이 씹혀 아무 변화가 없을 때의 한 번 재클릭은 허용한다.
    unanswered := refreshClicks = 1 && refreshCtrl = 0 && !EarnSeen("mct_need_ceo")
    if (refreshClicks && !unanswered && (refreshCtrl != 1 || EarnSeen("mct_need_ceo")))
        throw Error("MCT card re-click before registration prompt disappeared")
    refreshClicks++, refreshLastClickAt := refreshClockMs
    if (refreshOptions.Get("rejectClick",0) = refreshClicks)
        return false
    refreshHover := !clearCursor
    if (clearCursor)
        refreshCursorClears++
    return true
}
EarnUIClearCursor() {
    global refreshHover, refreshCursorClears, refreshAborted, refreshFocused
    if (EarnAborted() || EarnSeen("mct_title"))
        throw Error("Explicit cursor clearing must wait for departure from the MCT list")
    refreshCursorClears++
    if (refreshOptions.Get("abortCursorClear",false))
        refreshAborted := true
    if (refreshOptions.Get("focusCursorClear",false))
        refreshFocused := false
    if (EarnAborted() || refreshOptions.Get("rejectCursorClear",false))
        return false
    refreshHover := false
    return true
}
EarnPress(key) {
    global refreshCtrl, refreshCtrlAt
    if (EarnAborted() || key != "LCtrl" || !EarnSeen("mct_need_ceo") || !EarnSeen("mct_title") || refreshCtrl)
        throw Error("LCtrl is allowed once only at the confirmed MCT registration prompt")
    refreshCtrl++
    if (refreshOptions.Get("rejectCtrl",false))
        return false
    refreshCtrlAt := refreshClockMs
    return true
}
EarnUIBackToMCT(guard,presses) {
    global refreshBacks
    if (EarnAborted() || !EarnSeen(guard) || presses != 1 || guard != "nc_dj_menu")
        throw Error("MCT refresh must return from a confirmed business screen")
    refreshBacks++
    return !refreshOptions.Get("rejectBack",false)
}
EarnCEO(*) {
    throw Error("MCT registration must not open the interaction menu")
}
EarnLog(*) {
    global refreshLogs
    if (!EarnSeen("bunker_entry") && !EarnSeen("bunker_page") && !EarnSeen("nc_dj_menu"))
        throw Error("Registration cannot be logged before business entry is confirmed")
    refreshLogs++
}
EarnSleep(ms) {
    Sleep(ms)
    return !EarnAborted()
}
Sleep(ms) {
    global refreshClockMs, refreshAborted, refreshFocused
    refreshClockMs += ms
    if (refreshOptions.Has("abortAt") && refreshClockMs >= refreshOptions["abortAt"])
        refreshAborted := true
    if (refreshOptions.Has("focusLostAt") && refreshClockMs >= refreshOptions["focusLostAt"])
        refreshFocused := false
}
EarnAborted() => refreshAborted || !refreshFocused
RefreshClock() => refreshClockMs
EarnFail(reason) {
    global refreshFailure
    refreshFailure := reason
    return false
}
'@
    foreach ($waitFunction in @('EarnWaitSeen','EarnWaitGone')) {
        $mctRefreshDriver += "`n" + (Get-EarnFunctionBody $promptCoreText $waitFunction).Replace('A_TickCount', 'RefreshClock()')
    }
    $savedRefreshSource = $sourceText
    try {
        $sourceText = $sourceText.Replace('A_TickCount', 'RefreshClock()')
        Invoke-EarnOfflineCheck 'MCTRefresh' 'EarnMCTRefresh' $mctRefreshDriver 25
    } finally { $sourceText = $savedRefreshSource }
    $djFlowDriver = @'
global config := Map("Settings",Map("EarnDJPopularityPct",95)), popularity := 90, allowRebook := true,
    gain := 10, confirmations := 0, djScene := "mct", djMode := "", homeReads := 0, backs := 0,
    gEarnDJCheckAbove := -1, resultCalls := "", resultLogs := []
; Real Home reader/opening and DJ flow. A stale MCT value (92) is never authoritative.
; After a rebook the run goes Home → MCT → Home and rebooks again only when the fresh Home shows a rise.
; "lag": Home has not caught up yet, so the run stops paying and the next run checks the rise.
; [popularity, rebook allowed, gain, result, payments, start scene, mode, previous rebook popularity]
cases := [[97,true,10,true,0,"mct","",-1],[90,true,10,true,1,"mct","",-1],
    [90,false,10,false,0,"mct","",-1],[95,true,10,true,0,"mct","",-1],
    [90,true,10,true,1,"mct","lag",-1],[20,true,10,true,8,"mct","",-1],
    [94,true,10,true,1,"mct","",-1],[0,true,10,true,10,"mct","",-1],
    [-1,true,10,false,0,"mct","",-1],[95,true,10,true,0,"home","",-1],
    [90,true,10,false,0,"unknown","",-1],[90,true,10,false,0,"mct","missing_label",-1],
    [90,true,10,false,0,"mct","open_failed",-1],[90,true,10,false,0,"mct","home_failed",-1],
    [90,true,10,false,1,"mct","post_label_missing",-1],
    [95,true,10,false,0,"mct","back_failed",-1],[90,true,10,false,0,"mct","abort",-1],
    ; 지난 재고용이 먹었는지는 다음 방문의 첫 Home 값으로 본다.
    [100,true,10,true,0,"mct","",91],[91,true,10,false,0,"mct","",91],
    [80,true,10,false,0,"mct","",91],[91,true,10,true,1,"mct","",80],
    [90,true,10,false,0,"mct","confirm_click_failed",-1],
    [90,true,10,false,1,"mct","confirm_gone_failed",-1],
    [90,true,10,false,1,"mct","resident_failed",-1],
    [90,true,10,false,1,"mct","resident_log_failed",-1],
    [90,true,10,false,1,"mct","cursor_aborted",-1],
    [90,true,10,false,1,"mct","cursor_focus_lost",-1],
    [90,true,10,true,1,"mct","cursor_restored",-1]]
for c in cases {
    popularity := c[1], allowRebook := c[2], gain := c[3], confirmations := 0,
        djScene := c[6], djMode := c[7], homeReads := 0, backs := 0, gEarnDJCheckAbove := c[8], resultCalls := "", resultLogs := []
    result := EarnDJSwapLoop(92)
    if (result != c[4] || confirmations != c[5] || (result && (djScene != "mct" || backs != confirmations + 1)))
        throw Error("DJ Home flow " A_Index ": result=" result " payments=" confirmations " scene=" djScene " backs=" backs)
    if (c[1] >= 95 && confirmations)
        throw Error("Stale MCT reading spent money while Home already reached target")
    if (homeReads > confirmations + 1)
        throw Error("DJ read Home popularity more than once per rebook")
    if (c[1] = 0 && popularity != 100)
        throw Error("DJ stopped below target while Home kept showing each rise")
    if (gEarnDJCheckAbove != ((djMode = "lag" || djMode = "post_label_missing") && confirmations ? c[1] : -1))
        throw Error("DJ flow " A_Index ": next-visit check=" gEarnDJCheckAbove)
    failureStages := Map("confirm_click_failed", ["C", "confirm_click"], "confirm_gone_failed", ["CG", "confirm_gone"],
        "resident_failed", ["CGXR", "resident_seen"], "resident_log_failed", ["CGXR", "resident_seen"])
    if (djMode = "cursor_aborted" || djMode = "cursor_focus_lost") {
        if (resultCalls != "CGX" || !transactionPending.Has("dj"))
            throw Error("Cursor cleanup cancellation must retain pending and skip Resident/payment confirmation")
    }
    if (failureStages.Has(djMode)) {
        expected := failureStages[djMode]
        if (resultCalls != expected[1] || resultLogs.Length != 1 || !InStr(resultLogs[1], "stage=" expected[2]))
            throw Error("DJ failure diagnostics changed short-circuit order or omitted the failed stage")
        if (!transactionPending.Has("dj"))
            throw Error("DJ diagnostics must preserve the unresolved transaction")
    }
}
FileAppend("PASS DJFlow cases=" cases.Length "`n", "*")
ExitApp(0)
EarnPopularityMCTPct() {
    throw Error("MCT popularity is diagnostic only and must not be read for DJ spending")
}
EarnBarFill(x1,x2,y,kind) {
    global popularity, homeReads, djScene
    if (x1 != 1069 || x2 != 1584 || y != 173 || kind != "pop" || djScene != "home")
        throw Error("DJ read pixels outside the confirmed Home popularity bar")
    homeReads++
    return popularity / 100
}
EarnAborted() => djMode = "abort"
EarnUIReady(name,*) => !EarnAborted() && EarnSeen(name)
EarnSeen(name,*) {
    global allowRebook, djScene, djMode, confirmations
    if (name = "mct_title")
        return djScene = "mct"
    if (name = "nc_popularity_home")
        return djScene = "home" && djMode != "missing_label" && !(djMode = "post_label_missing" && confirmations)
    if (name = "nc_home")
        return djScene = "club" || djScene = "home" || djScene = "dj"
    if (name = "nc_dj_menu")
        return djScene = "home" || djScene = "dj"
    if (name = "mct_nightclub_card")
        return djScene = "mct"
    if (name = "dj_rebook_10k" || name = "dj_rebook_10k_right")
        return djScene = "dj" && allowRebook
    if (name = "dj_solomun" || name = "dj_resident" || name = "dj_resident_right")
        return djScene = "dj"
    return djScene = name
}
EarnUIClick(name,x,y,*) {
    global popularity, gain, confirmations, djScene, djMode, resultCalls
    if (!EarnUIReady(name))
        throw Error("DJ clicked an unconfirmed screen: " name " from " djScene)
    if (name = "mct_nightclub_card") {
        if (djMode = "open_failed")
            return false
        djScene := "club"
    } else if (name = "nc_home") {
        if (djMode = "home_failed")
            return false
        djScene := "home"
    } else if (name = "nc_dj_menu") {
        djScene := "dj"
    } else if (name = "dj_rebook_10k" || name = "dj_rebook_10k_right") {
        djScene := name = "dj_rebook_10k" ? "dj_confirm_solomun" : "dj_confirm_tale"
    } else if (name = "dj_confirm_solomun" || name = "dj_confirm_tale") {
        resultCalls .= "C"
        if (djMode = "confirm_click_failed")
            return false
        confirmations += 1
        if (djMode != "lag")
            popularity := Min(100,popularity+gain)
        djScene := "dj"
    } else {
        throw Error("Unexpected DJ click " name)
    }
    return true
}
EarnUIClearCursor() {
    global resultCalls
    if (SubStr(resultCalls, -1) != "G")
        throw Error("Cursor must be cleared after confirmation disappears")
    resultCalls .= "X"
    return djMode != "cursor_aborted" && djMode != "cursor_focus_lost"
}
EarnWaitSeen(name,area := "", timeoutMs := 0) {
    global resultCalls
    if (name = "dj_resident" || name = "dj_resident_right") {
        if (timeoutMs != 5000)
            throw Error("Resident wait budget changed")
        if (SubStr(resultCalls, -1) != "X")
            throw Error("Restored game cursor still obscures Resident")
        resultCalls .= "R"
        if (djMode = "resident_failed" || djMode = "resident_log_failed")
            return false
    }
    return EarnSeen(name)
}
EarnWaitGone(name,area,timeoutMs) {
    global resultCalls
    if (timeoutMs != 15000)
        throw Error("Confirmation wait budget changed")
    resultCalls .= "G"
    return djMode != "confirm_gone_failed" && !EarnSeen(name)
}
EarnSleep(ms) => !EarnAborted()
EarnUIBackToMCT(guard,presses) {
    global djScene, backs, djMode
    if (guard != "nc_dj_menu" || presses != 1 || djScene != "home")
        throw Error("DJ return must start on Home")
    if (djMode = "back_failed")
        return false
    djScene := "mct", backs++
    return true
}
EarnFail(*) => false
EarnLog(message) {
    if (InStr(message, "[dj-result]")) {
        resultLogs.Push(message)
        if (djMode = "resident_log_failed")
            throw Error("Simulated diagnostic log failure")
    }
    return true
}
EarnDJSchedule(*) => true
'@
    foreach ($fn in @('EarnDJNeedsRebook','EarnDJHomeOpen','EarnPopularityHomePct')) {
        $djFlowDriver += "`n" + (Get-EarnFunctionBody $sourceText $fn)
    }
    Invoke-EarnOfflineCheck 'DJFlow' 'EarnDJSwapLoop' $djFlowDriver 28
    # Real saved pixels, real bar sampler and real Home reader. No desktop APIs.
    Add-Type -AssemblyName System.Drawing
    Add-Type -ReferencedAssemblies System.Drawing @'
using System;
using System.Collections.Generic;
using System.Drawing;
public static class EarnHomeTextFixture {
    public static bool Contains(Bitmap source, Bitmap mask) {
        var points = new List<Point>();
        var colors = new List<Color>();
        for (int y = 0; y < mask.Height; y++) for (int x = 0; x < mask.Width; x++) {
            Color c = mask.GetPixel(x, y);
            if (c.R == 255 && c.G == 0 && c.B == 255) continue;
            if (Math.Min(c.R, Math.Min(c.G, c.B)) < 220)
                throw new Exception("Home context template retained unstable background pixels");
            points.Add(new Point(x,y)); colors.Add(c);
        }
        if (points.Count < 1000) throw new Exception("Home context mask is incomplete");
        for (int y = 0; y + mask.Height <= source.Height; y++) {
            for (int x = 0; x + mask.Width <= source.Width; x++) {
                bool found = true;
                for (int p = 0; p < points.Count; p++) {
                    Color a = source.GetPixel(x + points[p].X, y + points[p].Y), b = colors[p];
                    if (Math.Abs(a.R-b.R)>40 || Math.Abs(a.G-b.G)>40 || Math.Abs(a.B-b.B)>40) {
                        found = false; break;
                    }
                }
                if (found) return true;
            }
        }
        return false;
    }
}
'@
    $fixtureRoot = Join-Path $PSScriptRoot 'test-earntasks-fixtures'
    $homeFixture = [Drawing.Bitmap]::FromFile((Join-Path $fixtureRoot 'nightclub-home-95.png'))
    $mctFixture = [Drawing.Bitmap]::FromFile((Join-Path $fixtureRoot 'mct-popularity-92.png'))
    $homeTemplate = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot '..\..\Images\Earn\1920x1080\nc_popularity_home.png'))
    try {
        if (-not [EarnHomeTextFixture]::Contains($homeFixture,$homeTemplate)) { throw 'Home text template does not match the observed Home screen' }
        if ([EarnHomeTextFixture]::Contains($mctFixture,$homeTemplate)) { throw 'Home text template accepted the MCT popularity card' }
        $pixelEntries = @()
        for ($x=1069; $x -le 1584; $x+=3) {
            $color = $homeFixture.GetPixel($x-728,173-135).ToArgb() -band 0xFFFFFF
            $pixelEntries += ('"{0},173",{1}' -f $x,$color)
        }
        for ($x=340; $x -le 708; $x+=3) {
            $color = $mctFixture.GetPixel($x-325,471-435).ToArgb() -band 0xFFFFFF
            $pixelEntries += ('"{0},471",{1}' -f $x,$color)
        }
    } finally {
        $homeFixture.Dispose(); $mctFixture.Dispose(); $homeTemplate.Dispose()
    }
    Write-Output 'PASS DJHomeTemplate cases=2 (saved pixels only)'
    $script:earnCaseTotal += 2
    $homePixelDriver = @'
global fixturePixels := Map(__PIXELS__), fixtureContext := "home", fixtureActive := true, fixtureAbort := false, pixelReads := 0
if (EarnPopularityHomePct() != 95 || pixelReads != 172 || EarnDJNeedsRebook(EarnPopularityHomePct()))
    throw Error("Observed Home 95% must not cause a DJ purchase")
fixtureContext := "mct", pixelReads := 0
if (EarnPopularityMCTPct() != 92 || pixelReads != 123)
    throw Error("MCT comparison fixture no longer represents the old 92% diagnostic")
pixelReads := 0
if (EarnPopularityHomePct() != -1 || pixelReads)
    throw Error("MCT pixels were accepted without Nightclub Home context")
fixtureContext := "unknown", pixelReads := 0
if (EarnPopularityHomePct() != -1 || pixelReads)
    throw Error("Unconfirmed Home text must block pixel reads")
fixtureContext := "home", fixtureActive := false, pixelReads := 0
if (EarnPopularityHomePct() != -1 || pixelReads)
    throw Error("Missing game focus must block Home reads")
fixtureActive := true, fixtureAbort := true, pixelReads := 0
if (EarnPopularityHomePct() != -1 || pixelReads)
    throw Error("Input cancellation must block Home reads")
FileAppend("PASS DJHomePixels cases=6`n", "*")
ExitApp(0)
EarnUIReady(name,area) {
    if (name != "nc_popularity_home" || area[1] != 0.38 || area[2] != 0.14 || area[3] != 0.54 || area[4] != 0.19)
        throw Error("Unexpected popularity context")
    return fixtureContext = "home" && !fixtureAbort
}
EarnSeen(name,*) => name = "mct_title" && fixtureContext = "mct"
EarnLog(*) {
    throw Error("Non-bunker bar must not emit bunker diagnostics")
}
IsGTAActive() => fixtureActive ? 1 : 0
WinGetClientPos(&cx,&cy,&cw,&ch,*) {
    cx := 0, cy := 0, cw := 1920, ch := 1080
}
CoordMode(*) => true
PixelGetColor(x,y) {
    global pixelReads
    pixelReads++
    return fixturePixels[x "," y]
}
'@
    $homePixelDriver = $homePixelDriver.Replace('__PIXELS__',($pixelEntries -join ','))
    $barReaderSource = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnCore.ahk') -Raw -Encoding UTF8
    foreach ($fn in @('EarnBarFill','EarnPopularityMCTPct')) {
        $homePixelDriver += "`n" + (Get-EarnFunctionBody $barReaderSource $fn)
    }
    $homePixelDriver += "`n" + (Get-EarnFunctionBody $sourceText 'EarnDJNeedsRebook')
    Invoke-EarnOfflineCheck 'DJHomePixels' 'EarnPopularityHomePct' $homePixelDriver 6
    $policyText = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnPolicy.ahk') -Raw -Encoding UTF8
    $screenText = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnScreen.ahk') -Raw -Encoding UTF8
    $bunkerPolicy = "`n" + (Get-EarnFunctionBody $policyText 'EarnBunkerOrderPlan')
    $bunkerObserve = "`n" + (Get-EarnFunctionBody $sourceText 'EarnBunkerObservePlan')
    $bunkerTaskDriver = @'
global config := Map("Settings",Map("EarnBunkerIntervalSec",6720)), gEarnNextDue := Map(), gEarnBunkerOrdered := false, gEarnBunkerFull := false
global c := [], buyCalls := 0, beginCalls := 0, endCalls := 0
; stock, supply, interval, begin OK, buy OK, end OK, result, buys, ends, due milliseconds.
cases := [[0.4,1,8400,true,true,true,true,0,1,60000],
    [0.4,0.25,6720,true,true,true,true,0,1,60000],
    [0.4,0.24,6720,true,true,true,true,0,1,60000],
    [0.4,0.2,6720,true,true,true,true,1,1,60000],
    [1,0,8400,true,true,true,true,0,1,300000],
    [0.97,0,8400,true,true,true,true,0,1,300000],
    [0.4,0.75,1680,true,true,true,true,0,1,60000],
    [0.4,0,8400,true,true,true,true,1,1,60000],
    [0.4,0.8,1680,true,true,true,true,1,1,60000],
    [0.4,0.6,3360,true,true,true,true,1,1,60000],
    [0.4,0,1645,true,true,true,false,0,1,0],
    [-1,0,8400,true,true,true,false,0,1,0],
    [0.4,1.1,8400,true,true,true,false,0,1,0],
    [0.4,0,8400,false,true,true,false,0,0,0],
    [0.4,0,8400,true,false,true,false,1,1,60000],
    [0.4,0,8400,true,true,false,false,1,1,60000]]
for row in cases {
    c := row, config["Settings"]["EarnBunkerIntervalSec"] := c[3]
    gEarnNextDue := Map("bunker",0), buyCalls := 0, beginCalls := 0, endCalls := 0,
        gEarnBunkerOrdered := true, gEarnBunkerFull := false, stockNotices := [], stockNoticeSources := [], stockNoticeClears := [],
        gEarnSellNotices := Map("bunker", "기존 벙커 경고", "nightclub", "나이트클럽 경고")
    before := A_TickCount
    result := EarnBunkerTask()
    after := A_TickCount
    due := gEarnNextDue["bunker"]
    if (result != c[7] || buyCalls != c[8] || beginCalls != 1 || endCalls != c[9])
        throw Error("Bunker task result/cleanup " A_Index)
    if (c[10] = 0 ? due != 0 : due < before+c[10] || due > after+c[10])
        throw Error("Bunker task scheduling " A_Index " due=" due)
    expectedFull := c[1] >= 0.97 ? 1 : 0
    if (gEarnBunkerFull != expectedFull || stockNotices.Length != expectedFull
        || (expectedFull && (stockNoticeSources[1] != "bunker" || stockNotices[1] != "벙커 재고 만재: 판매 필요")))
        throw Error("Bunker task stock notice " A_Index " full=" gEarnBunkerFull " count=" stockNotices.Length)
    validObservation := c[4] && c[1] >= 0 && c[1] <= 1 && c[2] >= 0 && c[2] <= 1
        && c[3] >= 1680 && c[3] <= 8400 && Mod(c[3], 1680) = 0
    if (gEarnSellNotices.Get("nightclub", "") != "나이트클럽 경고")
        throw Error("Bunker task changed another source " A_Index)
    if (expectedFull) {
        if (gEarnSellNotices.Get("bunker", "") != "벙커 재고 만재: 판매 필요" || stockNoticeClears.Length)
            throw Error("Bunker task full notice state " A_Index)
    } else if (validObservation) {
        if (gEarnSellNotices.Has("bunker") || stockNoticeClears.Length != 1 || stockNoticeClears[1] != "bunker")
            throw Error("Bunker task confirmed non-full clear " A_Index)
    } else if (gEarnSellNotices.Get("bunker", "") != "기존 벙커 경고" || stockNoticeClears.Length) {
        throw Error("Bunker task unconfirmed observation must preserve notice " A_Index)
    }
}
; The grouped scheduler already owns the MCT session, including no-purchase and invalid-read paths.
for row in [[0.4,1,8400,false,true,false,true,0,0,60000],
    [0.4,0,8400,false,true,false,true,1,0,60000],
    [-1,0,8400,false,true,false,false,0,0,0]] {
    c := row, config["Settings"]["EarnBunkerIntervalSec"] := c[3]
    gEarnNextDue := Map("bunker",0), buyCalls := 0, beginCalls := 0, endCalls := 0, gEarnBunkerOrdered := true,
        stockNotices := [], stockNoticeSources := [], stockNoticeClears := [], gEarnSellNotices := Map("bunker", "기존 벙커 경고")
    before := A_TickCount
    result := EarnBunkerTask(false)
    after := A_TickCount, due := gEarnNextDue["bunker"]
    if (result != c[7] || buyCalls != c[8] || beginCalls || endCalls)
        throw Error("Shared-session bunker task reopened or closed the caller's session")
    if (c[10] = 0 ? due != 0 : due < before+c[10] || due > after+c[10])
        throw Error("Shared-session bunker scheduling changed")
    if (c[1] < 0 ? gEarnSellNotices.Get("bunker", "") != "기존 벙커 경고" : gEarnSellNotices.Has("bunker"))
        throw Error("Shared-session bunker notice confirmation changed")
}
; 1018: 직전에 주문했어도 막대가 사야 할 때면 매번 벙커에 들어간다(배송 중 기록으로 건너뛰지 않는다).
config["Settings"]["EarnBunkerIntervalSec"] := 8400, c := [0.4,0,8400,true,true,true,true,1,1,60000], buyCalls := 0, gEarnNextDue := Map("bunker",0)
EarnBunkerTask(), EarnBunkerTask()
if (buyCalls != 2)
    throw Error("Bunker must reopen on every empty-supply observation after an order")
FileAppend("PASS BunkerTask cases=19`n", "*")
ExitApp(0)
EarnTaskMCTBegin() {
    global beginCalls
    beginCalls++
    return c[4]
}
EarnTaskMCTEnd() {
    global endCalls, c
    endCalls++
    return c[6]
}
EarnBunkerBuy() {
    global buyCalls, c, gEarnBunkerOrdered
    if (gEarnBunkerOrdered)
        throw Error("Previous order state must reset")
    buyCalls++
    return c[5]
}
EarnBarFill(x1,x2,y,*) => y = 555 ? c[1] : c[2]
EarnAborted() => false
EarnMCTRefresh() {
    throw Error("Non-near boundary must not refresh in this driver")
}
EarnSleep(*) {
    throw Error("Non-near boundary must not hold MCT in this driver")
}
EarnLog(*) => true
EarnFail(*) => false
'@
    Invoke-EarnOfflineCheck 'BunkerTask' 'EarnBunkerTask' ($bunkerTaskDriver + $bunkerPolicy + $bunkerObserve) 19
    $bunkerObserveDriver = @'
global config := Map("Settings",Map("EarnBunkerIntervalSec",6720)), gEarnNextDue := Map(), gEarnBunkerOrdered := false, gEarnBunkerFull := false
global c := Map(), clockMs := 0, supplyNow := 0.21, stockNow := 0.4,
    refreshes := 0, buys := 0, begins := 0, ends := 0, sleeps := [], abortNow := false, reads := 0
; Name, observations/options, result, purchases, next delay, expected observation time.
cases := [
    ["catch boundary on fresh frame",Map("supply",0.22,"at",150000,"next",0.2),true,1,60000,154000],
    ["already at boundary",Map("supply",0.2),true,1,60000,0],
    ["production paused stays bounded",Map(),true,0,10000,240000],
    ["accelerated supply reaches actual boundary",Map("supply",0.22,"at",11000,"next",0.2),true,1,60000,11000],
    ["new delivery resets prediction",Map("at",20000,"next",1),true,0,60000,22000],
    ["stock fills during observation",Map("at",20000,"nextStock",1),true,0,300000,22000],
    ["missed boundary preserves spending limit",Map("at",20000,"next",0.19),true,0,60000,22000],
    ["scheduler late after another task",Map("beginMs",200000,"supply",0.19),true,0,60000,200000],
    ["invalid later supply stops",Map("at",20000,"next",-1),false,0,0,22000],
    ["invalid later stock stops",Map("at",20000,"nextStock",-1),false,0,0,22000],
    ["refresh failure stops",Map("refreshFail",true),false,0,0,11000],
    ["sleep detects focus loss",Map("sleepAbort",true),false,0,0,10000],
    ["refresh detects user input",Map("refreshAbort",true),false,0,0,11000],
    ["abort before observation",Map("abort",true),false,0,0,0],
    ["late refresh cannot authorize payment",Map("refreshMs",230000,"at",1,"next",0.2),true,0,10000,240000],
    ["refresh crossing deadline cannot authorize payment",Map("refreshMs",231000,"at",1,"next",0.2),true,0,10000,241000],
    ["near earlier configured boundary",Map("interval",1680,"supply",0.81,"at",20000,"next",0.8),true,1,60000,22000],
    ["deadline not extended by closer observation",Map("supply",0.22,"at",20000,"next",0.21),true,0,10000,240000],
    ["read completing after deadline discarded",Map("lateRead",true,"at",1,"next",0.2),true,0,10000,240000]]
for scenario in cases {
    c := scenario[2], config["Settings"]["EarnBunkerIntervalSec"] := c.Get("interval",6720)
    clockMs := 0, supplyNow := c.Get("supply",0.21), stockNow := 0.4,
        refreshes := 0, buys := 0, begins := 0, ends := 0, sleeps := [], reads := 0,
        abortNow := c.Get("abort",false), gEarnBunkerOrdered := true, gEarnBunkerFull := false,
        gEarnNextDue := Map("bunker",0), stockNotices := [], stockNoticeSources := [], stockNoticeClears := [],
        gEarnSellNotices := Map("bunker", "기존 벙커 경고", "nightclub", "나이트클럽 경고")
    result := EarnBunkerTask()
    expectedDue := scenario[5] ? clockMs + scenario[5] : 0
    if (result != scenario[3] || buys != scenario[4] || gEarnNextDue["bunker"] != expectedDue
        || clockMs != scenario[6] || begins != 1 || ends != 1)
        throw Error("Bunker observe " scenario[1] " result=" result " buys=" buys " time=" clockMs " due=" gEarnNextDue["bunker"])
    for ms in sleeps {
        if (ms <= 0 || ms > 10000)
            throw Error("Boundary observation sleeps must stay within ten seconds")
    }
    if (scenario[6] >= 240000 && buys)
        throw Error("No deadline-late purchase permitted")
    expectedFull := scenario[1] = "stock fills during observation" ? 1 : 0
    if (gEarnBunkerFull != expectedFull || stockNotices.Length != expectedFull
        || (expectedFull && (stockNoticeSources[1] != "bunker" || stockNotices[1] != "벙커 재고 만재: 판매 필요")))
        throw Error("Bunker observe stock notice " scenario[1] " full=" gEarnBunkerFull " count=" stockNotices.Length)
    if (gEarnSellNotices.Get("nightclub", "") != "나이트클럽 경고")
        throw Error("Bunker observe changed another source " scenario[1])
    if (expectedFull) {
        if (gEarnSellNotices.Get("bunker", "") != "벙커 재고 만재: 판매 필요" || stockNoticeClears.Length)
            throw Error("Bunker observe full notice state " scenario[1])
    } else if (result) {
        if (gEarnSellNotices.Has("bunker") || stockNoticeClears.Length != 1 || stockNoticeClears[1] != "bunker")
            throw Error("Bunker observe confirmed non-full clear " scenario[1])
    } else if (gEarnSellNotices.Get("bunker", "") != "기존 벙커 경고" || stockNoticeClears.Length) {
        throw Error("Bunker observe unconfirmed state must preserve notice " scenario[1])
    }
}
FileAppend("PASS BunkerObserve cases=19`n", "*")
ExitApp(0)
BunkerClock() => clockMs
EarnTaskMCTBegin() {
    global begins, clockMs
    begins++
    clockMs += c.Get("beginMs",0)
    return true
}
EarnTaskMCTEnd() {
    global ends
    ends++
    return true
}
EarnAborted() => abortNow
EarnBarFill(x1,x2,y,*) {
    global reads, clockMs
    reads++
    if (c.Get("lateRead",false) && refreshes)
        clockMs := 240000
    return y = 555 ? stockNow : supplyNow
}
EarnBunkerBuy() {
    global buys
    if (gEarnBunkerOrdered || abortNow || clockMs >= 240000)
        throw Error("Purchase must use current observation, live guard and cleared order state")
    buys++
    return true
}
EarnSleep(ms) {
    global clockMs, sleeps, abortNow
    sleeps.Push(ms), clockMs += ms
    if (c.Get("sleepAbort",false))
        abortNow := true
    return !abortNow
}
EarnMCTRefresh() {
    global clockMs, refreshes, abortNow, supplyNow, stockNow
    if (abortNow || clockMs >= 240000)
        throw Error("No refresh may start after abort or deadline")
    refreshes++, clockMs += c.Get("refreshMs",1000)
    if (clockMs >= c.Get("at",300000)) {
        supplyNow := c.Get("next",supplyNow)
        stockNow := c.Get("nextStock",stockNow)
    }
    if (c.Get("refreshAbort",false))
        abortNow := true
    return !abortNow && !c.Get("refreshFail",false)
}
EarnLog(*) => true
EarnFail(*) => false
'@
    $bunkerObserveDriver += $bunkerPolicy + $bunkerObserve.Replace('A_TickCount', 'BunkerClock()')
    $savedBunkerSource = $sourceText
    try {
        $sourceText = $sourceText.Replace('A_TickCount', 'BunkerClock()')
        Invoke-EarnOfflineCheck 'BunkerObserve' 'EarnBunkerTask' $bunkerObserveDriver 19
    } finally { $sourceText = $savedBunkerSource }
    $taskFinallyDriver = @'
global config := Map("Settings",Map("EarnBunkerIntervalSec",8400,"EarnDJPopularityPct",95)),
    gEarnNextDue := Map(), gEarnBunkerOrdered := false, gEarnBunkerFull := false, gEarnFail := "",
    endScene := "mct_title", endFailure := "", endOrder := "", endAbort := false,
    endBoss := true, endLogs := [], taskMode := "", originalException := 0, taskBegins := 0, taskEnds := 0
cases := [
    ["read_throw","",false,"C-",false,true],
    ["write_throw","",false,"C-",false,true],
    ["write_throw","close_error",false,"C",true,true],
    ["write_throw","retire",false,"C-",true,true],
    ["abort_throw","",false,"",true,true],
    ["return_false","close_error",false,"C",true,false],
    ["ok","close_error",false,"C",true,false],
    ["ok","",true,"C-",false,false]
]
for manageSession in [true,false] {
for task in [EarnBunkerTask, EarnDJTask, EarnWarehouseTask] {
    for c in cases {
        taskMode := c[1], endFailure := c[2], endScene := "mct_title", endOrder := "",
            endBoss := true, endAbort := false, gEarnFail := "", endLogs := [], gEarnNextDue := Map(),
            originalException := Error("original task exception"), caught := 0, result := false, taskBegins := 0, taskEnds := 0
        try result := manageSession ? task.Call() : task.Call(false)
        catch as taskException
            caught := taskException
        expectedResult := manageSession ? c[3] : taskMode = "ok"
        expectedOrder := manageSession ? c[4] : "", expectedBoss := manageSession ? c[5] : true
        if (result != expectedResult || endOrder != expectedOrder || endBoss != expectedBoss
            || taskBegins != (manageSession ? 1 : 0) || taskEnds != (manageSession ? 1 : 0))
            throw Error(task.Name " cleanup " c[1] " order=" endOrder " result=" result)
        if (c[6] ? !caught || ObjPtr(caught) != ObjPtr(originalException) : IsObject(caught))
            throw Error(task.Name " original exception was replaced or swallowed")
        if (taskMode = "return_false" && gEarnFail != "original task failure")
            throw Error(task.Name " cleanup replaced the original failure reason")
        if (manageSession && taskMode = "ok" && endFailure = "close_error" && !InStr(gEarnFail,"cleanup close exception"))
            throw Error(task.Name " cleanup-only error was not reported")
    }
}
}
FileAppend("PASS MCTTaskFinally cases=48`n", "*")
ExitApp(0)
EarnTaskMCTBegin() {
    global taskBegins
    taskBegins++
    return true
}
EarnTaskMCTEnd() {
    global taskEnds
    taskEnds++
    return FixtureTaskMCTEnd()
}
TaskReadGuard() {
    global taskMode, originalException
    if (taskMode = "read_throw")
        throw originalException
}
TaskWriteResult() {
    global taskMode, originalException, endAbort
    if (taskMode = "abort_throw")
        endAbort := true
    if (taskMode = "write_throw" || taskMode = "abort_throw")
        throw originalException
    return taskMode = "return_false" ? EarnFail("original task failure") : true
}
EarnBarFill(x1,x2,y,*) {
    TaskReadGuard()
    return y = 555 ? 0.4 : 0
}
EarnBunkerBuy() => TaskWriteResult()
EarnMCTRefresh() => false
EarnDJSwapLoop(*) {
    TaskReadGuard()
    return TaskWriteResult()
}
EarnWarehouseManage() {
    TaskReadGuard()
    return TaskWriteResult()
}
EarnLog(*) => true
'@
    $warehouseText = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnWarehouse.ahk') -Raw -Encoding UTF8
    $taskFinallyDriver += "`n" + $mctCleanupSupport + $bunkerPolicy + $bunkerObserve
    $taskFinallyDriver += "`n" + (Get-EarnFunctionBody $sourceText 'EarnTaskMCTEnd').Replace('EarnTaskMCTEnd(', 'FixtureTaskMCTEnd(')
    foreach ($fn in @('EarnDJTask','EarnDJNeedsRebook')) {
        $taskFinallyDriver += "`n" + (Get-EarnFunctionBody $sourceText $fn)
    }
    $taskFinallyDriver += "`n" + (Get-EarnFunctionBody $warehouseText 'EarnWarehouseTask')
    Invoke-EarnOfflineCheck 'MCTTaskFinally' 'EarnBunkerTask' $taskFinallyDriver 48
    $bunkerBuyDriver = @'
global config := Map("Settings",Map("EarnBunkerIntervalSec",6720)), gEarnBunkerOrdered := false, gEarnBunkerFull := false
global c := Map(), stage := "mct", pays := 0, cancels := 0, reads := 0, buyClicks := 0, resupplyClicks := 0
; Options, result, payments, cancellations, delivery confirmed, OCR reads.
cases := [
    ["empty",Map(),true,1,0,true,2],
    ["one-bar",Map("supply",0.8,"interval",1680,"quote","$15,000"),true,1,0,true,2],
    ["two-bars",Map("supply",0.6,"interval",3360,"quote","$30,000"),true,1,0,true,2],
    ["default four-bars",Map("supply",0.2,"quote","$60,000"),true,1,0,true,2],
    ["four-bars rounding rejected",Map("supply",0.2,"quote","$75,000"),true,0,1,false,1],
    ["four-bars price changes while reading",Map("supply",0.2,"quote","$60,000","quote2","$75,000"),true,0,1,false,2],
    ["default earlier boundary does not buy",Map("supply",0.4,"quote","$45,000"),true,0,0,false,0],
    ["default missed last boundary does not buy",Map("supply",0.19),true,0,0,false,0],
    ["pending",Map("pending",true),true,0,0,false,0],
    ["price-too-high",Map("supply",0.8,"interval",1680,"quote","$30,000"),true,0,1,false,1],
    ["discount-unknown",Map("quote","$74,000"),true,0,1,false,1],
    ["OCR-letters",Map("quote","$75,OOO"),false,0,1,false,1],
    ["OCR-failed",Map("quote",false),false,0,1,false,1],
    ["second-price-changed",Map("quote2","$90,000"),true,0,1,false,2],
    ["second-OCR-failed",Map("quote2",false),false,0,1,false,2],
    ["full-stock",Map("stock",1),true,0,0,false,0],
    ["full-supply",Map("supply",1),true,0,0,false,0],
    ["past-boundary",Map("supply",0.75,"interval",1680),true,0,0,false,0],
    ["invalid-interval",Map("interval",1645),false,0,0,false,0],
    ["read-negative",Map("stock",-1),false,0,0,false,0],
    ["read-range",Map("supply",1.1),false,0,0,false,0],
    ["missing-card",Map("ready",false),false,0,0,false,0],
    ["card-click-failed",Map("fail","mct_bunker_card"),false,0,0,false,0],
    ["resupply-failed",Map("fail","bunker_resupply"),false,0,0,false,0],
    ["payment-send-failed",Map("fail","pay"),false,0,0,false,2],
    ["payment-outcome-unknown",Map("confirmGone",false),false,1,0,false,2],
    ["delivery-not-confirmed",Map("postPending",false),false,1,0,false,2],
    ["pending-dismiss-failed",Map("fail","bunker_pending"),false,1,0,true,2],
    ["return-failed",Map("back",false),false,1,0,true,2],
    ["entry-screen",Map("entry",true),true,1,0,true,2],
    ["delivery-full",Map("pageSupply",1),true,0,0,false,0],
    ["delivery-nearly-full",Map("pageSupply",0.97),true,0,0,false,0],
    ["delivery-partial",Map("pageSupply",0.43),true,0,0,false,0],
    ["delivery-return-failed",Map("pageSupply",1,"back",false),false,0,0,false,0],
    ["page-unreadable",Map("pageSupply",-1),false,0,0,false,0],
    ["page-guard-interrupted",Map("pageAbort",true),false,0,0,false,0],
    ["same-boundary",Map("supply",0.2,"pageSupply",0.2,"quote","$60,000"),true,1,0,true,2],
    ["page-sampling-difference",Map("supply",0.2,"pageSupply",0.225,"quote","$60,000"),true,1,0,true,2],
    ["missing-dialog",Map("dialog",false),false,0,0,false,0],
    ["cancel-failed",Map("quote","$90,000","fail","cancel"),false,0,0,false,1],
    ["pending-dismiss-unknown",Map("pendingGone",false),false,1,0,true,2]]
for scenario in cases {
    c := scenario[2], config["Settings"]["EarnBunkerIntervalSec"] := c.Get("interval",6720)
    stage := "mct", pays := 0, cancels := 0, reads := 0, buyClicks := 0, resupplyClicks := 0, gEarnBunkerOrdered := false
    result := EarnBunkerBuy()
    if (result != scenario[3] || pays != scenario[4] || cancels != scenario[5]
        || gEarnBunkerOrdered != scenario[6] || reads != scenario[7])
        throw Error("Bunker buy " scenario[1] ": result=" result " pays=" pays " cancels=" cancels " reads=" reads)
    if (pays > 1)
        throw Error("No repeated payment permitted")
    if (c.Get("pageSupply",0) > c.Get("supply",0) + 0.03 || c.Get("pageSupply",0) < 0 || c.Get("pageAbort",false)) {
        if (resupplyClicks || buyClicks || pays || reads)
            throw Error("Changed or unreadable internal supply must block all resupply and purchase actions")
        if (result && stage != "mct")
            throw Error("Skipped purchase is only successful after returning to MCT")
    }
}
FileAppend("PASS BunkerBuy cases=41`n", "*")
ExitApp(0)
EarnUIReady(name,*) => name = "mct_bunker_card" && stage = "mct" && c.Get("ready",true)
EarnBarFill(x1,x2,y,*) => y = 555 ? c.Get("stock",0.4) : c.Get("supply",0)
EarnBunkerPageSupply() {
    if (stage != "bunker_page")
        throw Error("Internal supply must only be read after bunker page arrival")
    return c.Get("pageAbort",false) ? -1 : c.Get("pageSupply",c.Get("supply",0))
}
EarnSeen(name,*) => stage = name
EarnWaitSeen(name,*) => EarnSeen(name)
EarnWaitGone(name,*) {
    global c, stage
    return stage != name && (name != "bunker_confirm" || c.Get("confirmGone",true))
        && (name != "bunker_pending" || c.Get("pendingGone",true))
}
EarnUIClick(name,x,y,*) {
    global c, stage, pays, cancels, buyClicks, resupplyClicks
    action := name = "bunker_confirm" ? (x = 1065 ? "pay" : "cancel") : name
    if (c.Get("fail","") = action)
        return false
    switch name {
        case "mct_bunker_card":
            if (stage != "mct")
                throw Error("Card requires MCT")
            stage := c.Get("entry",false) ? "bunker_entry" : "bunker_page"
        case "bunker_entry":
            if (stage != name)
                throw Error("Entry requires visible entry")
            stage := "bunker_page"
        case "bunker_resupply":
            if (stage != "bunker_page")
                throw Error("Resupply requires bunker page")
            resupplyClicks++
            stage := "bunker_buy"
        case "bunker_buy":
            if (stage != name)
                throw Error("Buy requires purchase page")
            buyClicks++
            stage := buyClicks = 1 ? (c.Get("dialog",true) ? (c.Get("pending",false) ? "bunker_pending" : "bunker_confirm") : "unknown")
                : (c.Get("postPending",true) ? "bunker_pending" : "bunker_confirm")
        case "bunker_confirm":
            if (stage != name || (x != 1065 && x != 850))
                throw Error("Confirmation requires visible dialog and known button")
            if (x = 1065)
                pays++
            else
                cancels++
            stage := "bunker_buy"
        case "bunker_pending":
            if (stage != name)
                throw Error("Delivery dismissal requires confirmed delivery")
            stage := "bunker_buy"
        default:
            throw Error("Unexpected game action " name)
    }
    return true
}
EarnReadScreen(*) {
    global c, reads
    reads++
    value := reads = 1 ? c.Get("quote","$75,000") : c.Get("quote2",c.Get("quote","$75,000"))
    return Type(value) = "String" ? [{text:value}] : false
}
EarnUIBackToMCT(*) {
    global c, stage
    if (!c.Get("back",true))
        return false
    stage := "mct"
    return true
}
EarnSleep(*) => false
EarnLog(*) => true
EarnFail(*) => false
'@
    $bunkerBuyDriver += $bunkerPolicy + "`n" + (Get-EarnFunctionBody $policyText 'EarnBunkerPriceAllowed')
    $bunkerBuyDriver += "`n" + (Get-EarnFunctionBody $screenText 'EarnScreenText')
    $bunkerBuyDriver += "`n" + (Get-EarnFunctionBody $screenText 'EarnReadDollars')
    Invoke-EarnOfflineCheck 'BunkerBuy' 'EarnBunkerBuy' $bunkerBuyDriver 41
    $uiClickDriver = @'
global clickMode := "", clickAbort := false, cursorMoves := 0, mouseEvents := [], dpiCalls := 0
for c in [["normal",true,2,2,2,""],["abort-held",false,1,2,2,""],
    ["abort-before",false,0,0,0,""],["bad-size",false,0,0,2,""],
    ["abort-move",false,1,0,2,""],["lost-context",false,1,0,2,""],
    ["throw-held",false,1,2,2,"held failure"],
    ["keep-hover",true,1,2,2,"",false],
    ["abort-held",false,1,2,2,"",false],
    ["abort-move",false,1,0,2,"",false],
    ["abort-settle",false,1,2,2,"",false]] {
    clickMode := c[1], clickAbort := clickMode = "abort-before", cursorMoves := 0, mouseEvents := [], dpiCalls := 0
    result := false, caught := ""
    try result := c.Length = 7 ? EarnUIClick("known",100,200,"",c[7]) : EarnUIClick("known",100,200)
    catch as e
        caught := e.Message
    if (result != c[2] || cursorMoves != c[3] || mouseEvents.Length != c[4] || dpiCalls != c[5] || caught != c[6])
        throw Error("UI click " clickMode ": result=" result " cursor=" cursorMoves " events=" mouseEvents.Length " error=" caught)
    if (mouseEvents.Length && (mouseEvents[1] != "{Blind}{LButton down}" || mouseEvents[2] != "{Blind}{LButton up}"))
        throw Error("Mouse button was not released after an interrupted click")
}
FileAppend("PASS UIClickBoundary cases=11`n", "*")
ExitApp(0)
EarnAborted() => clickAbort
EarnUIReady(*) => !clickAbort && !(clickMode = "lost-context" && cursorMoves)
IsGTAActive() => 42
WinGetClientPos(&x,&y,&w,&h,window) {
    x := 10, y := 20, w := clickMode = "bad-size" ? 1280 : 1920, h := 1080
}
DllCall(name,args*) {
    global cursorMoves, dpiCalls
    if (name = "SetThreadDpiAwarenessContext") {
        dpiCalls++
        if ((dpiCalls = 1 && args[2] != -4) || (dpiCalls = 2 && args[2] != 77))
            throw Error("DPI context was not restored")
        return 77
    }
    if (name != "SetCursorPos")
        throw Error("Unexpected native call " name)
    if (clickAbort)
        throw Error("Cursor moved after physical-input abort")
    cursorMoves++
    return true
}
SendEvent(event) {
    global mouseEvents
    mouseEvents.Push(event)
}
Sleep(ms) {
    global clickAbort
    if (ms != 100)
        throw Error("Unexpected held-button delay")
    if (clickMode = "abort-held")
        clickAbort := true
    if (clickMode = "throw-held")
        throw Error("held failure")
}
EarnSleep(ms) {
    global clickAbort
    if (clickMode = "abort-move" && ms = 80)
        clickAbort := true
    if (clickMode = "abort-settle" && ms = 450)
        clickAbort := true
    return !clickAbort
}
EarnFail(*) => false
'@
    Invoke-EarnOfflineCheck 'UIClickBoundary' 'EarnUIClick' $uiClickDriver 11
    $uiBackDriver = @'
global backOptions := Map(), backClockMs := 0, backAborted := false, backspaces := 0,
    backPageReadyAt := 0, backMCTAt := -1, backFocused := true
; Options, result, Backspace count, elapsed time.
for c in [[Map("alreadyMCT",true),true,0,0],
    [Map("mctAfterFirst",1200,"secondPageAfter",9000),true,1,1250],
    [Map("mctAfterFirst",4000,"secondPageAfter",9000),true,1,4010],
    [Map("mctAfterFirst",9000,"secondPageAfter",9000),false,1,8650],
    [Map("mctAfterFirst",1200,"secondPageAfter",9000,"abortAt",900),false,1,1010],
    [Map("mctAfterFirst",1200,"secondPageAfter",9000,"focusLostAt",900),false,1,1010],
    [Map("pageAt",1200),true,2,2500],
    [Map("pageAt",4000),true,2,5380],
    [Map("pageAt",9000),false,0,8000],
    [Map("pageAt",1200,"abortAt",400),false,0,480],
    [Map("secondPageAfter",1200),true,2,1900],
    [Map("secondPageAfter",9000),false,1,8650],
    [Map("mctAfterLast",1200),true,2,1900],
    [Map("alreadyMCT",true,"aborted",true),false,0,0],
    [Map("slowTitleOcr",true),true,2,1300],
    [Map("slowTitleOcr",true,"alreadyMCT",true),true,0,0]] {
    backOptions := c[1], backClockMs := 0, backAborted := backOptions.Get("aborted",false), backspaces := 0,
        backPageReadyAt := backOptions.Get("pageAt",0), backMCTAt := -1, backFocused := true
    result := EarnUIBackToMCT("bunker_page",2)
    if (result != c[2] || backspaces != c[3] || backClockMs != c[4])
        throw Error("Return wait result=" result " inputs=" backspaces " elapsed=" backClockMs)
    if (gEarnSkipOcr)
        throw Error("Return probe leaked its template-only state")
}
FileAppend("PASS UIBackToMCT cases=16`n", "*")
ExitApp(0)
EarnSeen(name,*) {
    global backClockMs
    if (name = "mct_title" && !gEarnSkipOcr && backOptions.Get("slowTitleOcr",false)
        && !backOptions.Get("alreadyMCT",false) && backMCTAt < 0)
        backClockMs += 9000
    if (name = "mct_title")
        return backOptions.Get("alreadyMCT",false) || (backMCTAt >= 0 && backClockMs >= backMCTAt)
    return name = "bunker_page" && backspaces < 2 && backClockMs >= backPageReadyAt
}
EarnUIReady(name,*) => !EarnAborted() && EarnSeen(name)
EarnWaitSeen(name,area,timeoutMs) {
    if (timeoutMs != 3000)
        throw Error("Each back transition has a single three-second deadline")
    if (name != "mct_title" && name != "bunker_page")
        throw Error("Unexpected return wait target: " name)
    return FixtureBackWaitSeen(name,area,timeoutMs)
}
EarnPress(key) {
    global backspaces, backPageReadyAt, backMCTAt
    if (EarnAborted() || key != "Backspace" || !EarnSeen("bunker_page")
        || backOptions.Get("alreadyMCT",false) || (backMCTAt >= 0 && backClockMs >= backMCTAt))
        throw Error("Return input before the page recovered or after interruption")
    backspaces++
    if (backspaces = 1)
        backPageReadyAt := backClockMs + backOptions.Get("secondPageAfter",0)
    if (backspaces = 1 && backOptions.Has("mctAfterFirst"))
        backMCTAt := backClockMs + backOptions["mctAfterFirst"]
    if (backspaces = 2)
        backMCTAt := backClockMs + backOptions.Get("mctAfterLast",0)
    return true
}
EarnSleep(ms) {
    Sleep(ms)
    return !EarnAborted()
}
Sleep(ms) {
    global backClockMs, backAborted, backFocused
    backClockMs += ms
    if (backOptions.Has("abortAt") && backClockMs >= backOptions["abortAt"])
        backAborted := true
    if (backOptions.Has("focusLostAt") && backClockMs >= backOptions["focusLostAt"])
        backFocused := false
}
EarnAborted() => backAborted || !backFocused
BackClock() => backClockMs
'@
    $backWaitBody = (Get-EarnFunctionBody $promptCoreText 'EarnWaitSeen').Replace('EarnWaitSeen(', 'FixtureBackWaitSeen(').Replace('A_TickCount', 'BackClock()')
    $uiBackDriver += "`nEarnLog(*) => true`n" + $backWaitBody
    $savedBackSource = $sourceText
    try {
        $sourceText = $sourceText.Replace('A_TickCount', 'BackClock()')
        Invoke-EarnOfflineCheck 'UIBackToMCT' 'EarnUIBackToMCT' $uiBackDriver 16
    } finally { $sourceText = $savedBackSource }
    $sourceText = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\Earner.ahk') -Raw -Encoding UTF8
    $listDriver = @'
global config := Map("Settings", Map("EarnMCTOnly",1,"EarnBunker",1,"EarnBunkerIntervalSec",300,"EarnDJ",1,"EarnDJIntervalMin",5,"EarnSafe",1,"EarnSafeIntervalMin",210,"EarnDispatch",1,"EarnDispatchIntervalMin",48))
for mode in [1,0] {
    config["Settings"]["EarnMCTOnly"] := mode
    list := EarnTaskList()
    ; MCT 묶음(벙커·DJ·창고)이 앞, 앱에서 하는 금고·직원 파견이 뒤다.
    if (list.Length != 6 || list[1].id != "bunker" || list[2].id != "dj"
        || list[3].id != "warehouse" || list[4].id != "safe" || list[5].id != "staff" || list[6].id != "dispatch"
        || !list[1].on || !list[2].on || !list[3].on || !list[4].on || !list[5].on || list[6].on != !mode
        || list[4].fn != EarnVinewoodSafeTask || list[3].fn != EarnWarehouseTask || list[5].fn != EarnVinewoodStaffTask)
        throw Error("MCT task priority, phone safe, or warehouse routing")
}
FileAppend("PASS MCTTaskList cases=2`n", "*")
ExitApp(0)
EarnBunkerTask() => true
EarnDJTask() => true
EarnVinewoodSafeTask() => true
EarnWarehouseTask() => true
EarnVinewoodStaffTask() => true
EarnDispatchTask() => true
'@
    Invoke-EarnOfflineCheck 'MCTTaskList' 'EarnTaskList' $listDriver 2
    $sourceText = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnCore.ahk') -Raw -Encoding UTF8
    $waitDiagnosticDriver = @'
global waitClock := 0, waitReads := 0, waitLogs := [], waitCase := []
; target, budget, read cost, successful read, abort time, result, reads, clock, logs, log throws
waitCases := [["dj_resident",400,0,1,-1,true,1,0,0,false],
    ["dj_resident",400,0,-1,-1,false,3,400,1,false],
    ["dj_resident",400,600,1,-1,true,1,600,0,false],
    ["dj_resident_right",400,600,-1,-1,false,1,600,1,false],
    ["mct_seated",400,0,-1,0,false,0,0,1,false],
    ["mct_seated",400,0,-1,200,false,1,200,1,false],
    ["unrelated",400,0,-1,-1,false,3,400,0,false],
    ["dj_resident",400,0,-1,-1,false,3,400,1,true]]
for waitCase in waitCases {
    waitClock := 0, waitReads := 0, waitLogs := []
    result := EarnWaitSeen(waitCase[1], [0,0,0.3,0.1], waitCase[2])
    if (result != waitCase[6] || waitReads != waitCase[7] || waitClock != waitCase[8] || waitLogs.Length != waitCase[9])
        throw Error("Wait diagnostics changed read count, deadline, or return value: " A_Index)
    if (waitLogs.Length) {
        expectedReason := waitCase[5] >= 0 ? "aborted" : "timeout"
        expectedLast := waitReads ? "0" : "unread"
        for field in ["target=" waitCase[1], "area=0,0,0.3,0.1", "reason=" expectedReason,
            "reads=" waitReads, "last_seen=" expectedLast, "elapsed_ms=" waitClock, "dpi_context=", "script="]
            if (!InStr(waitLogs[1], field))
                throw Error("Missing actual wait observation: " field)
    }
}
FileAppend("PASS WaitDiagnostics cases=" waitCases.Length "`n", "*")
ExitApp(0)
WaitDiagnosticClock() => waitClock
EarnAborted() => waitCase[5] >= 0 && waitClock >= waitCase[5]
EarnSeen(*) {
    global waitClock, waitReads
    waitReads++, waitClock += waitCase[3]
    return waitReads = waitCase[4]
}
Sleep(ms) {
    global waitClock
    waitClock += ms
}
EarnLog(message) {
    waitLogs.Push(message)
    if (waitCase[10])
        throw Error("Simulated log write failure")
}
'@
    $savedWaitSource = $sourceText
    try {
        $sourceText = $sourceText.Replace('A_TickCount', 'WaitDiagnosticClock()')
        Invoke-EarnOfflineCheck 'WaitDiagnostics' 'EarnWaitSeen' $waitDiagnosticDriver 8
    } finally { $sourceText = $savedWaitSource }
    $ceoMenuDriver = @'
global EARN_MENU_AREA := [0,0,0.3,0.5], menuScene := "closed", menuBoss := true,
    menuCursor := 2, menuMode := "", menuOrder := "", menuAbort := false,
    retireRequests := 0, submenuUps := 0, menuTests := 0, menuFailure := "", arrowState := -1, menuSlept := false
for c in [["main",true],["preferences",true],["boss",true],["securo",true],["unknown",false],["closed",false]] {
    menuScene := c[1]
    MenuCheck(EarnMenuIsOpen() = c[2], "known title " c[1])
}
MenuCheck(!EarnSeen("mct_need_ceo"), "CEO warning uses its bounded prompt area")
menuScene := "boss", menuCursor := 0, menuOrder := ""
MenuCheck(EarnSelectRow("m_ceo_sel",EARN_MENU_AREA,"Down",3) && menuOrder = "DD",
    "boss submenu can select a row that is not initially highlighted")
; Start registered, with SecuroServ and Retire both initially unselected.
for c in [["normal","closed",true,false,true,"MUUEUUUEMM",false,1,3],
    ["normal","closed",false,false,true,"MM",false,0,0],
    ["normal","closed",true,true,true,"MM",true,0,0],
    ["normal","securo",true,false,false,"M",true,0,0],
    ["normal","unknown",true,false,false,"",true,0,0],
    ["unknown_submenu","closed",true,false,false,"MUUE",true,0,0],
    ["abort_submenu","closed",true,false,false,"MUUE",true,0,0],
    ["missing_retire","closed",true,false,false,"MUUEUUUUUUUUUUUUM",true,0,12],
    ["reject_retire","closed",true,false,false,"MUUEUUUEM",true,1,3],
    ["verify_missing","closed",true,false,false,"MUUEUUUEMM",false,1,3],
    ; 해제 직후 맨션 안: SecuroServ 도 Register as a Boss 도 메뉴에 없으면 이미 해제다.
    ["verify_missing","closed",false,false,true,"MM",false,0,0],
    ; 열자마자 메뉴가 다시 그려져 두 줄 다 안 보이면 1.5초 뒤 다시 읽는다(1004 18:11).
    ["relayout","closed",false,false,true,"MM",false,0,0],
    ["relayout","closed",true,false,true,"MUUEUUUE",false,1,3],
    ; 해제 뒤 화살표가 흰색이면 메뉴를 다시 열지 않는다.
    ["arrow_white","closed",true,false,true,"MUUEUUUE",false,1,3],
    ; 이미 CEO(노랑)면 메뉴를 열지 않는다. 흰색은 MCT 아이콘이 덮은 것일 수 있어 해제 전에는 믿지 않고 메뉴로 본다.
    ["arrow_already_white","closed",true,false,true,"MUUEUUUE",false,1,3],
    ["arrow_already_yellow","closed",true,true,true,"",true,0,0]] {
    arrowState := c[1] = "arrow_already_white" ? 0 : c[1] = "arrow_already_yellow" ? 1 : -1
    menuMode := c[1], menuScene := c[2], menuBoss := c[3], menuCursor := 2,
        menuOrder := "", menuAbort := false, retireRequests := 0, submenuUps := 0, menuFailure := "", menuSlept := false
    result := EarnCEO(c[4])
    MenuCheck(result = c[5] && menuOrder = c[6] && menuBoss = c[7]
        && retireRequests = c[8] && submenuUps = c[9],
        "CEO flow " c[1] "/" c[2] " order=" menuOrder " result=" result)
    if (!result && menuFailure = "" && menuMode != "abort_submenu" && menuMode != "reject_retire")
        throw Error("CEO failure must have a reason")
}
FileAppend("PASS CEOSubmenu cases=" menuTests "`n", "*")
ExitApp(0)
MenuCheck(condition,label) {
    global menuTests
    if (!condition)
        throw Error(label)
    menuTests++
}
; 글자 템플릿이 맞으면 안내 상자 바탕 확인도 통과한 것으로 본다.
TemplateAt(*) => true
TemplateSeen(folder,name,area := "",&fx := 0,&fy := 0,variation := 40) {
    global menuScene, menuBoss, menuCursor, menuMode
    if (name = "mct_need_ceo" && (!(area is Array) || area.Length != 4
        || area[1] != 0 || area[2] != 0 || area[3] != 0.3 || area[4] != 0.1))
        throw Error("CEO warning lookup must not scan the whole transition screen")
    if (name = "m_sub_boss" || name = "m_sub_securo" || name = "m_securo"
        || name = "m_securo_sel" || name = "m_boss" || name = "m_boss_sel"
        || name = "m_retire_sel" || name = "m_ceo_sel" || name = "m_start_org_sel") {
        if (folder != "JobWarp")
            throw Error("Boss menu must use the shared JobWarp template: " name)
    } else if (folder != "Earn") {
        throw Error("Ordinary menu title must retain its Earn template: " name)
    }
    switch name {
        case "m_title": return menuScene = "main"
        case "m_pref_title": return menuScene = "preferences"
        case "m_sub_boss": return menuScene = "boss"
        case "m_sub_securo": return menuScene = "securo"
        case "m_securo": return menuScene = "main" && menuBoss && Drawn()
        case "m_securo_sel": return menuScene = "main" && menuBoss && menuCursor = 0 && Drawn()
        case "m_boss": return menuScene = "main" && !menuBoss && menuMode != "verify_missing" && Drawn()
        case "m_boss_sel": return menuScene = "main" && !menuBoss && menuCursor = 0 && menuMode != "verify_missing" && Drawn()
        case "m_retire_sel": return menuScene = "securo" && menuCursor = 7 && menuMode != "missing_retire"
        case "m_ceo_sel": return menuScene = "boss" && menuCursor = 2
        default: return false
    }
}
EarnPress(key) {
    global menuScene, menuBoss, menuCursor, menuMode, menuOrder, menuAbort, retireRequests, submenuUps
    if (menuAbort)
        return false
    menuOrder .= key = "m" ? "M" : key = "Enter" ? "E" : key = "Up" ? "U" : key = "Down" ? "D" : "?"
    if (key = "m") {
        if (menuScene = "unknown")
            throw Error("No input is allowed on an unknown menu")
        menuScene := menuScene = "closed" ? "main" : "closed", menuCursor := 2
    } else if (key = "Up" && menuScene = "main") {
        menuCursor := Max(0,menuCursor-1)
    } else if (key = "Up" && menuScene = "securo") {
        menuCursor := Mod(menuCursor+7,8), submenuUps++
    } else if (key = "Down" && menuScene = "boss") {
        menuCursor++
    } else if (key = "Enter" && menuScene = "main" && menuBoss && menuCursor = 0) {
        menuScene := menuMode = "unknown_submenu" ? "unknown" : "securo", menuCursor := 2
        menuAbort := menuMode = "abort_submenu"
    } else if (key = "Enter" && menuScene = "securo" && menuCursor = 7) {
        retireRequests++
        if (menuMode = "reject_retire")
            return false
        menuBoss := false, menuScene := "closed"
    } else {
        throw Error("Unexpected CEO menu input " key " in " menuScene)
    }
    return true
}
EarnHudVisible() => menuScene = "closed"
; relayout: 메뉴를 연 직후 한 번 쉬기 전까지는 보스·SecuroServ 줄이 그려지지 않는다.
Drawn() => menuMode != "relayout" || menuSlept
; arrow_white 는 해제 전 노랑, Retire 를 누른 뒤 흰색이다.
EarnArrowCEOColor() => menuMode = "arrow_white" || menuMode = "relayout" ? (retireRequests ? 0 : 1) : arrowState
EarnWaitSeen(name,*) => EarnSeen(name)
EarnSleep(*) {
    global menuSlept
    menuSlept := true
    return !menuAbort
}
Sleep(*) => true
EarnLog(*) => true
EarnFail(reason) {
    global menuFailure
    menuFailure := reason
    return false
}
'@
    foreach ($fn in @('EarnSeen','EarnMenuIsOpen','EarnSelectRow','EarnMenuOpen','EarnMenuClose','EarnCEOIs')) {
        $ceoMenuDriver += "`n" + (Get-EarnFunctionBody $sourceText $fn)
    }
    Invoke-EarnOfflineCheck 'CEOSubmenu' 'EarnCEO' $ceoMenuDriver 24
    $mctOpenDriver = @'
global EARN_PROMPT_AREA := [0,0,0.3,0.1], openOptions := Map(), openScene := "", openOrder := "",
    openClockMs := 0, openAborted := false, promptWaits := 0, seatedAfterAt := -1, titleAfterAt := -1
; Initial scene/options, result, input order, elapsed time, standing-prompt waits.
cases := [["already-open",Map("scene","mct_title"),true,"",0,0],
    ["already-seated",Map("scene","mct_seated"),true,"Enter;",800,0],
    ["standing",Map("scene","mct_sit"),true,"e;Enter;",2300,1],
    ["CEO-prompt-delay",Map("promptAt",1200,"seatedAfter",600,"titleAfter",400),true,"e;Enter;",4500,1],
    ["prompt-timeout",Map("promptAt",9000),false,"",8000,1],
    ["abort-prompt",Map("promptAt",1200,"abortAt",400),false,"",400,1],
    ["seated-after-notification",Map("scene","mct_sit","seatedAfter",13000),true,"e;Enter;",15300,1],
    ["seated-timeout",Map("scene","mct_sit","seatedAfter",21000),false,"e;",20000,1],
    ["title-timeout",Map("scene","mct_seated","titleAfter",9000),false,"Enter;",8000,0],
    ["abort-seating",Map("scene","mct_sit","seatedAfter",1200,"abortAt",400),false,"e;",400,1],
    ["sit-key-rejected",Map("scene","mct_sit","rejectKey","e"),false,"",0,1],
    ["enter-swallowed",Map("scene","mct_seated","swallow",1),true,"Enter;Enter;",8800,0]]
for c in cases {
    openOptions := c[2], openScene := openOptions.Get("scene","transition"), openOrder := "",
        openClockMs := 0, openAborted := false, promptWaits := 0, seatedAfterAt := -1, titleAfterAt := -1
    fixtureHudHidden := false
    result := EarnMCTOpen()
    if (result != c[3] || openOrder != c[4] || openClockMs != c[5] || promptWaits != c[6])
        throw Error("MCT open " c[1] " result=" result " input=" openOrder " elapsed=" openClockMs " waits=" promptWaits)
    if (result && !fixtureHudHidden)
        throw Error("MCT screen must be hidden before success")
}
FileAppend("PASS MCTOpen cases=11`n", "*")
ExitApp(0)
EarnSeen(name,area := "") {
    global openScene
    if (openScene = "transition" && openClockMs >= openOptions.Get("promptAt",0))
        openScene := "mct_sit"
    if (openScene = "seating" && openClockMs >= seatedAfterAt)
        openScene := "mct_seated"
    if (openScene = "opening" && openClockMs >= titleAfterAt)
        openScene := "mct_title"
    return name = openScene
}
EarnWaitSeen(name,area,timeoutMs) {
    global promptWaits
    ; 앉은 안내는 게임 알림이 가릴 수 있어 20초까지 기다린다(1003 23:24 실측).
    if (timeoutMs != (name = "mct_seated" ? 20000 : 8000))
        throw Error("MCT transitions require one bounded wait (seated 20s, others 8s)")
    if (name = "mct_sit") {
        if (!(area is Array) || area.Length != 4 || area[1] != 0 || area[2] != 0 || area[3] != 0.3 || area[4] != 0.1)
            throw Error("Standing prompt wait must use the prompt region")
        promptWaits++
    }
    return FixtureOpenWaitSeen(name,area,timeoutMs)
}
EarnPress(key) {
    global openOrder, openScene, seatedAfterAt, titleAfterAt
    if ((key = "Enter" && !fixtureHudHidden) || (key = "e" && fixtureHudHidden))
        throw Error("HUD must stay visible while sitting and hide immediately before opening the web screen")
    if (openAborted || key = openOptions.Get("rejectKey",""))
        return false
    if (key = "e" && openScene = "mct_sit")
        openScene := "seating", seatedAfterAt := openClockMs + openOptions.Get("seatedAfter",0)
    else if (key = "Enter" && openScene = "mct_seated" && openOptions.Get("swallow",0) > 0)
        openOptions["swallow"] -= 1
    else if (key = "Enter" && openScene = "mct_seated")
        openScene := "opening", titleAfterAt := openClockMs + openOptions.Get("titleAfter",0)
    else
        throw Error("MCT input before matching prompt: " key " at " openScene)
    openOrder .= key ";"
    return true
}
EarnAborted() => openAborted
OpenClock() => openClockMs
Sleep(ms) {
    global openClockMs, openAborted
    openClockMs += ms
    if (openOptions.Has("abortAt") && openClockMs >= openOptions["abortAt"])
        openAborted := true
}
EarnFail(*) => false
'@
    $openWaitBody = (Get-EarnFunctionBody $sourceText 'EarnWaitSeen').Replace('EarnWaitSeen(', 'FixtureOpenWaitSeen(').Replace('A_TickCount', 'OpenClock()')
    $mctOpenDriver += "`nEarnLog(*) => true`n" + $openWaitBody + "`n" + (Get-EarnFunctionBody $sourceText 'EarnSleep').Replace('A_TickCount', 'OpenClock()')
    foreach ($fn in @('EarnChairMCTOpen','EarnTerrorbyteMCTOpen')) {
        $mctOpenDriver += "`n" + (Get-EarnFunctionBody $sourceText $fn)
    }
    Invoke-EarnOfflineCheck 'MCTOpen' 'EarnMCTOpen' $mctOpenDriver 11
    $mctCloseDriver = @'
global EARN_PROMPT_AREA := [], config := Map("Settings",Map("EarnTurnUnitsPerDeg",29))
global closeCase := Map(), scene := "", aborted := false, backspaces := 0, clicks := [], promptReads := 0, turns := 0, turnUnits := 0, turnList := [],
    closeClockMs := 0, seatedWaits := 0, seatedReads := 0, seatedAt := -1, stoodAt := -1, abortInputs := -1, steps := [],
    callActive := false, callWaits := 0
; Options, result, Backspace presses, right-button events, camera turns, prompt waits.
cases := [
    ["list",Map("scene","mct_title"),true,1,2,0,1],
    ["CEO-message",Map("scene","mct_need_ceo"),true,1,2,0,1],
    ["seated",Map(),true,0,2,0,1],
    ["unknown",Map("scene","unknown"),false,0,0,0,0],
    ["close-timeout",Map("scene","mct_title","seatedAfter",21000),false,1,0,0,0],
    ["seated-after-notification",Map("scene","mct_title","seatedAfter",11000),true,1,2,0,1],
    ["press-failed",Map("scene","mct_title","press",false),false,0,0,0,0],
    ["abort-before-click",Map("abortAt","start"),false,0,0,0,0],
    ["still-seated",Map("gone",false),false,0,2,0,0],
    ["reverse-wall",Map("prompt",false),true,0,2,1,2],
    ["prompt-still-missing",Map("prompt",false,"foundAt",0),false,0,2,4,6],
    ["back-to-chair",Map("prompt",false,"foundAt",4),true,0,2,2,4],
    ["turn-failed",Map("prompt",false,"foundAt",0,"turn",false),false,0,2,0,1],
    ["abort-during-prompt",Map("abortAt","prompt"),false,0,2,0,1],
    ["abort-button-held",Map("abortAt","held"),false,0,2,0,0],
    ["abort-after-back",Map("scene","mct_title","abortAt","back"),false,1,0,0,0],
    ["calibrated-turn",Map("prompt",false,"foundAt",3,"sensitivity",15),true,0,2,1,3],
    ["delayed-seated",Map("scene","mct_title","seatedAfter",1200),true,1,2,0,1],
    ["abort-transition",Map("scene","mct_title","seatedAfter",1200,"abortAt","transition"),false,1,0,0,0],
    ["transient-stand-prompt",Map(),true,0,2,0,1],
    ["abort-standing",Map("abortAt","standing"),false,0,2,0,0],
    ; 일어선 직후 게임 전화가 오면 Backspace 로 끊고 안내를 찾는다(1004 17:41).
    ["game-call",Map("call",true),true,0,2,0,1],
    ["game-call-stuck",Map("call",true,"callStuck",true),false,0,2,0,0],
    ; 연결된 통화는 테두리 템플릿 대신 빨간 끊기 아이콘으로만 보인다(1006 19:26).
    ["game-call-connected",Map("call",true,"connected",true),true,0,2,0,1],
    ["retire-no-chair",Map("prompt",false,"chair",false),true,0,2,0,0],
    ["retire-hud-missing",Map("chair",false,"hud",false),false,0,2,0,0]]
for scenario in cases {
    closeCase := scenario[2], scene := closeCase.Get("scene","mct_seated")
    aborted := closeCase.Get("abortAt","") = "start", backspaces := 0, clicks := [], promptReads := 0, turns := 0, turnUnits := 0, turnList := [],
        closeClockMs := 0, seatedWaits := 0, seatedReads := 0, seatedAt := -1, stoodAt := -1, abortInputs := -1, steps := [],
        callActive := closeCase.Get("call",false), callWaits := 0
    config["Settings"]["EarnTurnUnitsPerDeg"] := closeCase.Get("sensitivity",29)
    fixtureHudHidden := true
    result := EarnMCTClose(closeCase.Get("chair",true))
    if (result != scenario[3] || backspaces != scenario[4] || clicks.Length != scenario[5]
        || turns != scenario[6] || promptReads != scenario[7])
        throw Error("MCT close " scenario[1] " result=" result " keys=" backspaces " clicks=" clicks.Length " turns=" turns " waits=" promptReads)
    if (clicks.Length && (clicks[1] != "Right Down" || clicks[2] != "Right Up"))
        throw Error("Right button must be released even after interruption")
    if (steps.Length != Max(0, promptReads-2))
        throw Error("MCT close " scenario[1] " must take one short step before each later prompt read")
    for step in steps
        if (step != "w:150")
            throw Error("Recovery steps must be short forward taps")
    for i, units in turnList
        if (units != Round((i = 1 ? 180 : 90)*config["Settings"]["EarnTurnUnitsPerDeg"]))
            throw Error("Recovery must turn 180 degrees first, then calibrated quarter-turns")
    if (backspaces > 1 || (scenario[1] = "seated" && seatedWaits))
        throw Error("A known seated state needs no close key; a transition must never resend it")
    if (scenario[1] = "delayed-seated" && (seatedReads < 7 || seatedAt != 1200))
        throw Error("A prompt absent at 900ms must be allowed to arrive later without resending Backspace")
    if (scenario[1] = "close-timeout" && (closeClockMs != 20000))
        throw Error("Close transition must stop at its single 20-second deadline")
    if (scenario[1] = "abort-transition" && (closeClockMs != 400))
        throw Error("User input during the transition must stop before any stand/camera input")
    if (result && !FixtureCEOEntryReady())
        throw Error("Close allowed CEO menu entry before the stand animation finished")
    if (scenario[1] = "transient-stand-prompt" && closeClockMs - stoodAt != 3500)
        throw Error("A transient approach prompt must not bypass the stand animation wait")
    if (scenario[1] = "retire-no-chair" && (turns || promptReads || !FixtureCEOEntryReady()))
        throw Error("CEO retirement must proceed from confirmed standing HUD without searching for the chair")
    if (scenario[1] = "retire-hud-missing" && (turns || promptReads || closeClockMs - stoodAt < 6500))
        throw Error("CEO retirement must fail safely when standing HUD is missing")
    if (callWaits != (scenario[1] = "game-call" || scenario[1] = "game-call-connected" ? 1 : scenario[1] = "game-call-stuck" ? 3 : 0))
        throw Error("A game phone call must be hung up with Backspace, at most three times")
    if (scenario[1] = "abort-standing" && (closeClockMs - stoodAt != 700
        || abortInputs != backspaces + clicks.Length + turns))
        throw Error("Stand wait did not stop promptly without further input")
}
FileAppend("PASS MCTClose cases=" cases.Length "`n", "*")
ExitApp(0)
EarnSeen(name,*) {
    global scene, closeCase, seatedReads, seatedAt
    if (scene = "transition" && name = "mct_seated") {
        seatedReads++
        if (closeClockMs >= closeCase.Get("seatedAfter",0))
            scene := "mct_seated", seatedAt := closeClockMs
    }
    if (name = "afk_phone_frame")
        return callActive && !closeCase.Get("connected",false)
    if (name = "phone_call_end")
        return callActive && closeCase.Get("connected",false)
    return scene = name
}
EarnAborted() => aborted
EarnPress(key) {
    global closeCase, aborted, backspaces, scene, callActive, callWaits
    if (key != "Backspace")
        throw Error("Unexpected close key " key)
    if (aborted || !closeCase.Get("press",true))
        return false
    if (callActive) {
        callWaits++
        if (!closeCase.Get("callStuck",false))
            callActive := false
        return true
    }
    backspaces++
    scene := "transition"
    if (closeCase.Get("abortAt","") = "back")
        aborted := true
    return true
}
Click(event) {
    global clicks, aborted
    if (fixtureHudHidden)
        throw Error("MCT closed HUD must restore before standing or later CEO and chair recovery")
    if (event != "Right Down" && event != "Right Up")
        throw Error("Unexpected click " event)
    if (event = "Right Down" && aborted)
        throw Error("Right button pressed after abort")
    clicks.Push(event)
}
Sleep(ms) {
    global closeCase, aborted, closeClockMs, scene, stoodAt, abortInputs, backspaces, clicks, turns
    closeClockMs += ms
    if (closeCase.Get("abortAt","") = "held")
        aborted := true
    if (scene = "transition" && closeCase.Get("abortAt","") = "transition" && closeClockMs >= 400)
        aborted := true
    if (stoodAt >= 0 && closeCase.Get("abortAt","") = "standing" && closeClockMs - stoodAt >= 700) {
        aborted := true
        if (abortInputs < 0)
            abortInputs := backspaces + clicks.Length + turns
    }
}
CloseClock() => closeClockMs
FixtureCEOEntryReady() => !aborted && stoodAt >= 0 && closeClockMs - stoodAt >= 3500
EarnMCTRecoveryHud() => closeCase.Get("hud",true) && FixtureCEOEntryReady() && !callActive
EarnWaitGone(name,area,timeoutMs) {
    global closeCase, aborted, stoodAt, scene, callActive, callWaits
    if (name = "afk_phone_frame" || name = "phone_call_end") {
        if (timeoutMs != 3000)
            throw Error("A hung-up call must disappear within 3 seconds")
        return !aborted && !callActive
    }
    if (name != "mct_seated" || timeoutMs != 8000)
        throw Error("Must confirm standing before camera recovery")
    if (aborted || !closeCase.Get("gone",true))
        return false
    stoodAt := closeClockMs, scene := "standing"
    return true
}
EarnWaitSeen(name,area,timeoutMs) {
    global closeCase, promptReads, aborted, seatedWaits
    if (timeoutMs != (name = "mct_sit" ? (promptReads >= 1 ? 2000 : 3000) : 20000))
        throw Error("Recovery must wait for the seated-entry prompt")
    if (name = "mct_seated") {
        seatedWaits++
        return FixtureWaitSeen(name,area,timeoutMs)
    }
    if (name != "mct_sit")
        throw Error("Unexpected close wait target " name)
    if (!FixtureCEOEntryReady())
        throw Error("Approach prompt checked while standing animation was still active")
    promptReads++
    if (closeCase.Get("abortAt","") = "prompt")
        aborted := true
    return !aborted && (promptReads = 1 ? closeCase.Get("prompt",true)
        : promptReads = closeCase.Get("foundAt",2))
}
EarnWalk(path) {
    global steps, aborted
    if (aborted)
        return false
    steps.Push(path)
    return true
}
EarnTurn(units, pitchUnits := 0, hdrMCTRecovery := false) {
    global closeCase, aborted, turns, turnUnits, turnList
    if (pitchUnits != 0 || !hdrMCTRecovery)
        throw Error("MCT close recovery must explicitly enable the guarded HDR path")
    if (aborted || !closeCase.Get("turn",true))
        return false
    turns++, turnUnits := units, turnList.Push(units)
    return true
}
EarnFail(*) => false
EarnLog(*) => true
'@
    # Keep the production polling loop; replace only its clock and input-free dependencies.
    $closeWaitBody = (Get-EarnFunctionBody $sourceText 'EarnWaitSeen').Replace('EarnWaitSeen(', 'FixtureWaitSeen(').Replace('A_TickCount', 'CloseClock()')
    $mctCloseDriver += "`n" + $closeWaitBody + "`n" + (Get-EarnFunctionBody $sourceText 'EarnSleep').Replace('A_TickCount', 'CloseClock()')
    $mctCloseDriver += "`n" + (Get-EarnFunctionBody $sourceText 'EarnWaitCallEnd')
    $mctCloseDriver += "`n" + (Get-EarnFunctionBody $sourceText 'EarnMCTFindChairPrompt')
    foreach ($fn in @('EarnMCTClosedKind','EarnMCTWaitClosed','EarnChairMCTClose','EarnTerrorbyteMCTClose')) {
        $mctCloseDriver += "`n" + (Get-EarnFunctionBody $sourceText $fn).Replace('A_TickCount', 'CloseClock()')
    }
    Invoke-EarnOfflineCheck 'MCTClose' 'EarnMCTClose' $mctCloseDriver 26
    $terrorbyteDriver = @'
global EARN_PROMPT_AREA := [], scene := "", now := 0, stopped := false, inputs := "", swallow := 0,
    delayMs := 0, changedAt := 0, overlap := false, abortAt := -1
cases := ["roundtrip", "already-open", "swallowed-space", "overlap", "delayed-close", "timeout", "abort-close", "missing-return", "unknown", "abort-settle"]
for name in cases {
    scene := name = "already-open" ? "mct_title" : name = "unknown" ? "unknown" : "mct_terrorbyte"
    now := 0, stopped := false, inputs := "", swallow := name = "swallowed-space" ? 1 : 0,
        delayMs := name = "delayed-close" ? 1200 : name = "timeout" ? 21000 : 0,
        changedAt := 0, overlap := name = "overlap", abortAt := -1
    fixtureHudHidden := false
    observedKind := "chair"
    if (name = "unknown") {
        if (EarnMCTClose(false, &observedKind) || observedKind != "" || inputs != "")
            throw Error("Unknown screen reused an old observedKind or sent input")
        continue
    }
    if (name = "abort-settle")
        abortAt := 400
    observedOpen := EarnMCTOpen()
    if (name = "abort-settle") {
        if (observedOpen || inputs != "Space;")
            throw Error("Open settle ignored interruption")
        continue
    }
    if (!observedOpen || !fixtureHudHidden)
        throw Error("Terrorbyte did not open the guarded terminal: " name)
    if (name = "abort-close")
        abortAt := now + 400, delayMs := 1200
    closedAt := now
    observedClose := EarnMCTClose(false, &observedKind)
    if (name = "timeout" || name = "abort-close") {
        if (observedClose || observedKind != "" || (name = "timeout" && now - closedAt != 20000))
            throw Error("Unconfirmed close returned a observedKind or exceeded deadline: " name)
        continue
    }
    if (!observedClose || observedKind != "terrorbyte" || fixtureHudHidden || now - closedAt != delayMs)
        throw Error("Close did not recognize standing Terrorbyte immediately: " name)
    missing := name = "missing-return", beforeReady := inputs
    if (missing)
        scene := "unknown"
    if (EarnMCTReturnReady(observedKind) = missing || inputs != beforeReady)
        throw Error("Return must verify Terrorbyte without movement: " name)
    if (name = "roundtrip") {
        if (!EarnMCTOpen() || !EarnMCTClose(true, &observedKind) || observedKind != "terrorbyte"
            || inputs != "Space;Backspace;Space;Backspace;")
            throw Error("Same-position reentry failed")
    }
}
if (EarnMCTReturnReady(""))
    throw Error("Unknown return observedKind accepted")
scene := "mct_terrorbyte", now := 0, stopped := false, inputs := "", swallow := 0,
    delayMs := 0, changedAt := 0, overlap := false, abortAt := -1
if (!TerrorbytePlaceSmoke() || inputs != "Space;Backspace;Space;Backspace;"
    || gEarnBusy || gEarnGuardArmed || fixtureHudHidden)
    throw Error("Place-only smoke must run two independent cycles and release its guard")
FileAppend("PASS TerrorbyteMCT cases=12`n", "*")
ExitApp(0)
EarnSeen(name,*) {
    global scene
    if (scene = "closing" && now - changedAt >= delayMs)
        scene := "mct_terrorbyte"
    return name = scene || (overlap && scene = "mct_terrorbyte" && name = "mct_seated")
}
EarnPress(key) {
    global scene, inputs, swallow, changedAt
    if (stopped)
        return false
    if (key = "Space" && scene = "mct_terrorbyte") {
        if (!fixtureHudHidden)
            throw Error("Space sent before HUD guard")
        if (swallow)
            swallow--
        else
            scene := "mct_title"
    } else if (key = "Backspace" && scene = "mct_title")
        scene := "closing", changedAt := now
    else
        throw Error("Unexpected Terrorbyte input: " key " from " scene)
    inputs .= key ";"
    return true
}
EarnAborted() => stopped
TerrorbyteClock() => now
Sleep(ms) {
    global now, stopped
    now += ms
    if (abortAt >= 0 && now >= abortAt)
        stopped := true
}
EarnChairMCTOpen() {
    throw Error("Terrorbyte routed through chair open")
}
EarnChairMCTClose(*) {
    throw Error("Terrorbyte routed through chair close")
}
EarnMCTFindChairPrompt() {
    throw Error("Terrorbyte searched for a chair")
}
EarnFail(*) => false
EarnLog(*) => true
DiscordHUDMCTStop() {
    global fixtureHudHidden := false
}
'@
    foreach ($fn in @('EarnMCTOpen','EarnTerrorbyteMCTOpen','EarnMCTClosedKind','EarnMCTWaitClosed',
        'EarnTerrorbyteMCTClose','EarnTerrorbyteMCTReady','EarnMCTReturnReady','EarnWaitSeen','EarnSleep')) {
        $terrorbyteDriver += "`n" + (Get-EarnFunctionBody $sourceText $fn).Replace('A_TickCount', 'TerrorbyteClock()')
    }
    $harnessText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'earntest.ahk'))
    $terrorbyteDriver += "`n" + (Get-EarnFunctionBody $harnessText 'TerrorbytePlaceSmoke')
    Invoke-EarnOfflineCheck 'TerrorbyteMCT' 'EarnMCTClose' $terrorbyteDriver 12
    $turnGuardDriver = @'
global turnLogs := [], logThrows := false
global turnCase := [], moves := 0, movedX := 0, movedY := 0, turnMs := 0, menuChecks := 0, menuAbort := false
global EARN_PROMPT_AREA := [], goalAfter := -1, goalCost := 0, goalAbort := false, goalMenuOnly := false
; Relative mouse calls are intercepted. Run the actual turn loop and input guards.
for scenario in [[5220,0,-1,-1,true,261,5220,0],
    [5220,0,0,-1,false,0,0,0],[5220,0,1,-1,false,1,20,0],
    [5220,0,-1,0,false,0,0,0],[5220,0,-1,1,false,1,20,0],
    [5220,0,-1,0,true,261,5220,0,true,true,1200,false,125],
    [5220,0,1,0,false,1,20,0,true,true],
    [5220,0,-1,0,false,0,0,0,true,false],
    [5220,0,-1,0,false,0,0,0,false,true],
    [5220,0,-1,0,true,261,5220,0,true,true,9500],
    [5220,0,-1,0,true,261,5220,0,true,true,5000],
    [5220,0,-1,0,false,0,0,0,true,true,100,true],
    [5220,0,-1,0,false,17,340,0,true,true,0,false,0,1]] {
    sIndex := (IsSet(sIndex) ? sIndex : 0) + 1
    turnLogs := []
    turnCase := scenario, moves := 0, movedX := 0, movedY := 0, turnMs := 0, menuChecks := 0, menuAbort := false
    if (EarnTurn(scenario[1],0,scenario.Length >= 9 ? scenario[9] : false) != scenario[5] || moves != scenario[6]
        || movedX != scenario[7] || movedY != scenario[8])
        throw Error("Camera recovery must preserve abort/HUD guards and bounded movement: moves=" moves " time=" turnMs " expected=" scenario[6] " scenario=" sIndex)
    recovering := scenario.Length >= 9 && scenario[9]
    if (turnLogs.Length != (recovering ? 1 : 0))
        throw Error("Recovery logs once; ordinary turns do not log")
    if (recovering && (!InStr(turnLogs[1], "moves=" moves "/261") || !InStr(turnLogs[1], "emitted=" movedX "," movedY)))
        throw Error("Diagnostic movement must match intercepted native calls")
    if (scenario.Length >= 11 && scenario[11] = 1200 && (menuChecks != 3 || turnMs > 12500))
        throw Error("Slow menu checks must be throttled while HDR recovery remains bounded")
}
; A real arrival must terminate the production loop instead of completing all 261 moves.
; The late-arrival case makes a slow menu check cross the deadline with the prompt now visible.
for arrival in [[1,0,false,0,true], [0,0,false,0,true], [0,50,true,0,false],
    [0,0,false,9500,true,true], [-1,0,false,9500,true], [0,50,true,9500,false,true],
    [0,9500,false,0,true], [-1,40000,false,0,false], [0,9500,true,0,false], [0,50,false,90001,true,true]] {
    aIndex := (IsSet(aIndex) ? aIndex : 0) + 1
    turnLogs := []
    goalAfter := arrival[1], goalCost := arrival[2], goalAbort := arrival[3]
    goalMenuOnly := arrival.Length >= 6 && arrival[6]
    turnCase := [5220,0,-1,0,false,0,0,0,true,true,arrival[4]]
    moves := 0, movedX := 0, movedY := 0, turnMs := 0, menuChecks := 0, menuAbort := false
    if (EarnTurn(5220,0,true) != arrival[5] || (moves >= 261 && goalAfter >= 0) || (goalAfter = 0 && !goalMenuOnly && moves != 0) || (goalMenuOnly && moves > 16))
        throw Error("MCT prompt arrival must stop movement, including at deadline; moves=" moves " arrival=" aIndex)
    if (turnLogs.Length != 1 || !InStr(turnLogs[1], "elapsed_ms=" turnMs))
        throw Error("Each arrival exit must report actual elapsed time")
    if (aIndex = 8 && (!InStr(turnLogs[1], "budget_ms=90000") || !InStr(turnLogs[1], "budget_kind=total-cap")))
        throw Error("Slow probes must expose the whole-turn cap")
    if (aIndex = 10 && !InStr(turnLogs[1], "stage=terminal-goal"))
        throw Error("Final deadline probe must be distinguished")
}
logThrows := true, goalAfter := 0, goalCost := 0, goalAbort := false, goalMenuOnly := false
menuAbort := false
if (!EarnTurn(5220,0,true))
    throw Error("Diagnostic log failure must preserve the turn result")
FileAppend("PASS TurnGuard cases=24`n", "*")
ExitApp(0)
EarnAborted() => menuAbort || (turnCase[3] >= 0 && moves >= turnCase[3])
EarnHudVisible() => turnCase[4] < 0 || moves < turnCase[4]
HealthHudVisible() {
    global turnMs
    turnMs += turnCase.Length >= 13 ? turnCase[13] : 0
    return turnCase.Length >= 10 && turnCase[10] && (turnCase.Length < 14 || moves < turnCase[14])
}
EarnMCTRecoveryHud() {
    global turnMs, menuChecks, menuAbort
    menuChecks++, turnMs += turnCase.Length >= 11 ? turnCase[11] : 0
    menuAbort := turnCase.Length >= 12 && turnCase[12]
    return turnCase.Length >= 10 && turnCase[10]
}
EarnMCTRecoveryArrived() {
    global turnMs, menuAbort
    turnMs += goalCost
    if (goalAbort)
        menuAbort := true
    return goalAfter >= 0 && moves >= goalAfter && (!goalMenuOnly || menuChecks > 0)
}
TurnClock() => turnMs
DllCall(name,args*) {
    global moves, movedX, movedY
    if (name != "mouse_event" || args[2] != 1 || Abs(args[4]) > 20 || Abs(args[6]) > 20)
        throw Error("Unexpected native input call")
    moves++, movedX += args[4], movedY += args[6]
    return 0
}
Sleep(ms) {
    global turnMs
    turnMs += ms
    return true
}
EarnFail(*) => false
EarnLog(message) {
    if (logThrows)
        throw Error("Synthetic log failure")
    turnLogs.Push(message)
}
'@
    $turnSource = $sourceText
    $sourceText = $sourceText.Replace('A_TickCount','TurnClock()')
    try { Invoke-EarnOfflineCheck 'TurnGuard' 'EarnTurn' $turnGuardDriver 24 }
    finally { $sourceText = $turnSource }
    $recoveryArrivedDriver = @'
global EARN_PROMPT_AREA := [0,0,0.3,0.1], prompt := false, hud := false
for scenario in [[true,true,true],[false,true,false],[true,false,false],[false,false,false]] {
    prompt := scenario[1], hud := scenario[2]
    if (EarnMCTRecoveryArrived() != scenario[3])
        throw Error("MCT arrival requires both verified prompt and menu-free HUD")
}
FileAppend("PASS MCTRecoveryArrived cases=4`n", "*")
ExitApp(0)
EarnSeen(name, area) {
    if (name != "mct_sit" || area != EARN_PROMPT_AREA)
        throw Error("MCT recovery must reuse the background-verified prompt in its ROI")
    return prompt
}
EarnMCTRecoveryHud() => hud
'@
    Invoke-EarnOfflineCheck 'MCTRecoveryArrived' 'EarnMCTRecoveryArrived' $recoveryArrivedDriver 4
    $recoveryHudDriver = @'
global EARN_PROMPT_AREA := [], overlay := "", healthColor := 0xAAFFB4
for scenario in [[0xAAFFB4,"",true],[0x000000,"",false],[0xFFFFFF,"",false],
    [0xAAFFB4,"interaction",false],[0xAAFFB4,"afk_phone_frame",false],
    [0xAAFFB4,"ph_joblist_sel",false],[0xAAFFB4,"ph_vinewood_sel",false],
    [0xAAFFB4,"afk_vinewood_title",false],[0xAAFFB4,"mct_title",false],[0xAAFFB4,"mct_seated",false]] {
    healthColor := scenario[1], overlay := scenario[2]
    if (EarnMCTRecoveryHud() != scenario[3])
        throw Error("HDR recovery HUD must exclude menus/phone/terminal despite visible health bar: " overlay)
}
FileAppend("PASS MCTRecoveryHud cases=10`n","*")
ExitApp(0)
HealthHudVisible() {
    samples := []
    Loop 16
        samples.Push(healthColor)
    return HealthHudColors(samples)
}
EarnMenuIsOpen() => overlay = "interaction"
EarnSeen(name,*) => name = overlay
'@
    $commonScreen = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Core\Screen.ahk') -Raw -Encoding UTF8
    $recoveryHudDriver += "`n" + (Get-EarnFunctionBody $commonScreen 'HealthHudColors')
    Invoke-EarnOfflineCheck 'MCTRecoveryHud' 'EarnMCTRecoveryHud' $recoveryHudDriver 10
    $safeNavDriver = @'
global EARN_PROMPT_AREA := [], config := Map("Settings", Map("EarnTurnUnitsPerDeg",29))
; Open-safe prompt succeeds before navigation and at the final arrival check.
if (!EarnNavTo("safe", "safe_prompt", 12, 1) || !EarnNavTo("safe", "safe_prompt", 12, 0)
    || EarnNavTo("laptop", "laptop_prompt", 12, 0))
    throw Error("Open safe arrival must not start navigation or satisfy other prompts")
FileAppend("PASS OpenSafeNav cases=3`n", "*")
ExitApp(0)
EarnSeen(name,*) => name = "safe_close_prompt"
EarnAborted() => false
EarnFail(*) => false
EarnNavPlan(*) {
    throw Error("Already at open safe: navigation forbidden")
}
EarnBlip(*) => false
EarnWalk(*) => false
EarnTurn(*) => false
EarnFace(*) => false
EarnLog(*) => true
'@
    Invoke-EarnOfflineCheck 'OpenSafeNav' 'EarnNavTo' $safeNavDriver 3
    $mctNavDriver = @'
global EARN_PROMPT_AREA := [], config := Map("Settings", Map("EarnTurnUnitsPerDeg",29)), distance := 20, planCalls := 0
; Edge distance 999 with gp=0 must not become nearby after walking, in either final or next-loop check.
for c in [[20,1,true,0],[20,0,true,0],[100,1,false,1],[100,0,false,0],[999,1,false,1],[999,2,false,2]] {
    distance := c[1], planCalls := 0
    if (EarnNavTo("mct", "mct_sit", 12, c[2]) != c[3] || planCalls != c[4]) {
        FileAppend("FAIL Generic sit prompt must require nearby MCT; distance=" distance " steps=" c[2] "`n", "*")
        ExitApp(1)
    }
}
FileAppend("PASS MCTNav cases=6`n", "*")
ExitApp(0)
EarnSeen(name,*) => name = "mct_sit"
EarnAborted() => false
EarnFail(*) => false
EarnNavPlan(name, &a, &s, &g) {
    global planCalls
    planCalls++
    a := 0, s := 10, g := 0
    return true
}
EarnBlip(name, &a, &d) {
    a := 0, d := distance
    return true
}
EarnWalk(*) => distance = 999
EarnTurn(*) => false
EarnFace(*) => false
EarnLog(*) => true
Sleep(*) => true
'@
    Invoke-EarnOfflineCheck 'MCTNav' 'EarnNavTo' $mctNavDriver 6
    $mctStallDriver = @'
global EARN_PROMPT_AREA := [], config := Map("Settings", Map("EarnTurnUnitsPerDeg",29))
global walks := 0, progressing := false
for progress in [false,true] {
    progressing := progress, walks := 0
    if (EarnNavTo("mct", "mct_sit") != progress || walks != (progress ? 5 : 4))
        throw Error("MCT approach must stop oscillation and preserve real progress")
}
FileAppend("PASS MCTStall cases=2`n", "*")
ExitApp(0)
EarnSeen(*) => progressing && walks >= 5
EarnAborted() => false
EarnFail(*) => false
EarnNavPlan(name, &a, &s, &g) {
    a := 0, s := 20, g := 0
    return true
}
EarnBlip(name, &a, &d) {
    a := 0, d := progressing ? 60-walks*10 : 40-Mod(walks,2)*2
    return true
}
EarnWalk(path) {
    global walks
    if (!RegExMatch(path,"^w:\d+$"))
        throw Error("MCT stall must not start arbitrary sidesteps")
    walks++
    return true
}
EarnFace(*) => true
EarnLog(*) => true
Sleep(*) => true
'@
    Invoke-EarnOfflineCheck 'MCTStall' 'EarnNavTo' $mctStallDriver 2
    $faceDriver = @'
global config := Map("Settings", Map("EarnTurnUnitsPerDeg",29)), EARN_PROMPT_AREA := []
global sensitivity := 29, angle := 0, mode := "ok", turns := 0, walks := 0
for value in [14.5,29,40] {
    sensitivity := value, angle := 110, mode := "ok", turns := 0, walks := 0
    Check(EarnFace("mct") && Abs(angle) <= 5 && turns > 0 && turns < 8 && walks = 0
        && Abs(config["Settings"]["EarnTurnUnitsPerDeg"]-value) < 1, "sensitivity " value)
}
for c in [[179,-179],[-179,179]] {
    sensitivity := 29, angle := c[1], turns := 0
    config["Settings"]["EarnTurnUnitsPerDeg"] := 29
    Check(EarnFace("mct", c[2], 0.5) && Abs(Wrap(angle-c[2])) <= 0.5 && turns = 1, "angle boundary")
}
for testMode in ["blip-initial","blip-after","abort-initial","abort-after"] {
    sensitivity := 29, angle := 110, mode := testMode, turns := 0, walks := 0
    expectedTurns := InStr(mode,"initial") ? 0 : 1
    Check(!EarnFace("mct") && turns = expectedTurns && walks = 0, mode)
}
; Run the real navigation function with the real facing function. A lost sensor or
; cancellation during facing must stop before the first walking command.
for testMode in ["blip-after","abort-after"] {
    sensitivity := 29, angle := 30, mode := testMode, turns := 0, walks := 0
    Check(!EarnNavTo("mct", "", 12, 1) && turns = 1 && walks = 0, "navigation " mode)
}
FileAppend("PASS FaceControl cases=11`n", "*")
ExitApp(0)
Check(ok, label) {
    if (!ok) {
        FileAppend("FAIL FaceControl " label " angle=" angle " turns=" turns " walks=" walks "`n", "*")
        ExitApp(1)
    }
}
Wrap(value) => Mod(Mod(value + 180, 360) + 360, 360) - 180
EarnAborted() => mode = "abort-initial" || (mode = "abort-after" && turns > 0)
EarnBlip(name, &a, &d) {
    a := angle, d := 80
    return mode != "blip-initial" && !(mode = "blip-after" && turns > 0)
}
EarnTurn(units) {
    global angle, turns
    angle := Wrap(angle - units / sensitivity)
    turns++
    return true
}
EarnSleep(*) => true
EarnSeen(*) => false
EarnNavPlan(name, &a, &s, &g) {
    a := 20, s := 10, g := 5
    return true
}
EarnWalk(*) {
    global walks
    walks++
    return true
}
EarnFail(*) => false
EarnLog(*) => true
Sleep(*) => true
'@
    $faceDriver += "`n" + [regex]::Match($sourceText, '(?ms)^EarnNavTo\([^\r\n]*\) \{.*?^\}').Value
    Invoke-EarnOfflineCheck 'FaceControl' 'EarnFace' $faceDriver 11
    $supplyOutput = @(& (Join-Path $PSScriptRoot 'test-bunker-supply.ps1') -AhkPath $AhkPath)
    $supplyOutput | Write-Output
    $supplyCount = [regex]::Match(($supplyOutput -join "`n"), '(?m)^PASS BunkerSupply cases=(\d+)$')
    if (-not $supplyCount.Success) { throw 'Bunker supply regression summary missing' }
    $script:earnCaseTotal += [int]$supplyCount.Groups[1].Value
    Write-Output "PASS EarnTasks: $script:earnCaseTotal cases; no game input"
} finally {
    [Console]::InputEncoding = $previousInputEncoding
}
