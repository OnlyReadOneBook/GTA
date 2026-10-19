#Requires -Version 5.1
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
# Exercise the production scheduler with all window/input/timer dependencies replaced.
$source = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\Earner.ahk') -Raw -Encoding UTF8
$tick = [regex]::Match($source, '(?ms)^EarnTick\(\) \{.*?^\}').Value
if (-not $tick) { throw 'EarnTick missing' }
$guards = @('EarnIdleInit', 'EarnModeTick', 'EarnTaskAllowed', 'EarnStatusDetail', 'EarnAFKCloseMCT', 'EarnInputGuardStart', 'EarnInputGuardStop', 'EarnInputWatch', 'EarnInputAllowed', 'EarnInputAbortEvidence', 'EarnInputWindowEvidence', 'EarnInputEvidenceText', 'EarnGamePID', 'EarnTaskList', 'EarnEnabledText', 'ToggleEarner', 'SetEarner', 'EarnStatusText', 'EarnIsMCTTask', 'EarnScopeLabel', 'EarnHoldsPending', 'EarnRunScheduledTask', 'EarnRunMCTBatch', 'EarnTaskMCTEndWithManualRetry', 'EarnManualStopCleanup', 'EarnBossOffWithManualRetry', 'EarnConfirmNoScreenCleanup', 'EarnManualBossOffCleanup', 'EarnFinishManualStop', 'EarnNotifyStockFull', 'EarnClearStockNotice', 'EarnFinishScheduledTask', 'EarnStopAfterFailure') | ForEach-Object {
    $functionName = $_
    $body = [regex]::Match($source, ('(?ms)^' + $functionName + '\([^\r\n]*\) \{.*?^\}')).Value
    if (-not $body) { throw "Production function missing: $functionName" }
    if ($functionName -eq 'EarnFinishManualStop') {
        $abortCleanup = '    gEarnUserAbort := false'
        if (-not $body.Contains($abortCleanup)) { throw 'EarnFinishManualStop abort cleanup hook missing' }
        $body = $body.Replace($abortCleanup, $abortCleanup + "`n    EarnFinalizerAbortClearedProbe()")
    }
    $body
}
$guards += [regex]::Match($source, '(?ms)^EarnAFKCloseMCTGuarded\([^\r\n]*\) \{.*?^\}').Value
$production = ($tick + "`n" + ($guards -join "`n")).Replace('A_TimeIdlePhysical', 'idleMs').Replace('A_TickCount', 'fakeTick')
$production = $production.Replace('DllCall("GetForegroundWindow", "ptr")', 'FakeForegroundWindow()')
$overlay = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Overlay.ahk') -Raw -Encoding UTF8
$runningItems = [regex]::Match($overlay, '(?ms)^RunningItems\(\) \{.*?^\}').Value
if (-not $runningItems) { throw 'Production RunningItems missing' }
$production += "`n" + $runningItems
$core = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnCore.ahk') -Raw -Encoding UTF8
foreach ($functionName in @('EarnTransactionBegin','EarnTransactionConfirmed')) {
    $production += "`n" + [regex]::Match($core, ('(?ms)^' + $functionName + '\([^\r\n]*\) \{.*?^\}')).Value
}
$mctSitMatcher = [regex]::Match($core, '(?ms)^EarnMCTSitOcrMatches\([^\r\n]*\) \{.*?^\}').Value
if (-not $mctSitMatcher -or $core -notmatch '(?s)if \(name = "mct_sit"\).*?EarnMCTSitOcrSeen\(\)') {
    throw 'Production MCT sit detection must consume its exact OCR fallback'
}
$production += "`n" + $mctSitMatcher
# 밝기와 무관한 MCT 안내 OCR 판정. 실제 EarnSeen 이 이 함수들을 쓰는지도 확인한다.
foreach ($functionName in @('EarnOcrHas','EarnMCTSeatedOcrMatches','EarnMCTNeedCeoOcrMatches','EarnMCTTitleOcrMatches')) {
    $fn = [regex]::Match($core, ('(?ms)^' + $functionName + '\([^
]*\) \{.*?^\}')).Value
    if (-not $fn) { throw "Missing OCR matcher $functionName" }
    $production += "`n" + $fn
}
foreach ($use in @('EarnMCTSeatedOcrMatches(EarnOcrLines("prompt"','EarnMCTTitleOcrMatches(EarnOcrLines("title"','EarnMCTNeedCeoOcrMatches(EarnOcrLines("prompt"')) {
    if (-not $core.Contains($use)) { throw "EarnSeen must consume $use" }
}
$tasks = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnTasks.ahk') -Raw -Encoding UTF8
$mctBegin = [regex]::Match($tasks, '(?ms)^EarnTaskMCTBegin\([^\r\n]*\) \{.*?^\}').Value
if (-not $mctBegin) { throw 'Production EarnTaskMCTBegin missing' }
$mctBegin = [regex]::Replace($mctBegin, '^EarnTaskMCTBegin\(', 'ProductionEarnTaskMCTBegin(')
$production += "`n" + $mctBegin.Replace('A_TimeIdlePhysical', 'idleMs').Replace('A_TickCount', 'fakeTick')
$spotSeen = [regex]::Match($tasks, '(?ms)^EarnMCTSpotSeen\(\) \{.*?^\}').Value
if (-not $spotSeen) { throw 'Production EarnMCTSpotSeen missing' }
$production += "`n" + $spotSeen + "`nEarnMCTTurnInPlace() => false"
$mctPromptRows = @(Import-Csv (Join-Path $PSScriptRoot 'mct-capture-fixtures\mct-sit-prompt-runtime-20261009.tsv') -Delimiter "`t")
if ($mctPromptRows.Count -ne 2 -or $mctPromptRows[0].text -ne 'Press' -or $mctPromptRows[1].text -ne 'to sit down.') {
    throw 'Recorded live MCT prompt OCR fixture is incomplete'
}
$mctPromptLiteral = '[' + (($mctPromptRows | ForEach-Object {
    if ($_.x -notmatch '^\d+$' -or $_.y -notmatch '^\d+$' -or $_.w -notmatch '^\d+$' -or $_.h -notmatch '^\d+$') {
        throw 'Recorded MCT prompt OCR coordinates must be integers'
    }
    '{x:' + $_.x + ',y:' + $_.y + ',w:' + $_.w + ',h:' + $_.h + ',text:"' + $_.text.Replace('"','""') + '"}'
}) -join ',') + ']'
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
OnError(EarnerOfflineFailure)
EarnerOfflineFailure(failure, *) {
    FileAppend("FAIL scheduler runtime: " failure.Message "`n", "**")
    ExitApp(1)
}
global gEarnMode, gEarnModeRequest, gEarnIdleEnabled
global gEarnOn, gEarnBusy, gEarnDue, gEarnDone, gEarnTasks, gEarnCurrent, gEarnFail, gEarnNextDue, gEarnSoftFails, gEarnRetryIn, gAbort, config, GTA_WIN, afkOn
global calls, releaseCount, stopped, mode, windowExists, focused, otherBusy, activationCount, idleMs, gEarnGuardArmed, timers
global modeTimer := 0
global gEarnGamePID, fakePID, fakeTick, gEarnGuardStartedTick, gEarnUserAbort, lockAvailable, lockCalls, lockReleases, lockHeld, hooks, checkCount := 0
global beginCount, endCount, beginCleanupCount, beginOK, endOK, endNoScreen, beginThrows, endThrows, mctOpen, events, logs, taskModes, taskDurations, beginDelay, endDelay, endInput
global endStopMode, bossOffCount, bossProbeOK, bossProbeCount, bossProbeStrictCount, bossProbeGuardedCount, bossProbeMode, bossStopInjected, bossInitialGuardTick, bossRetryBaselineOK, bossRetryCleanupStateOK, staleFailInjected, blockedRestartObserved
global gEarnHeld, gEarnFailures, gEarnRecovery, appCloseOK, appCloseCount
global gEarnManualStop, gEarnManualCleanupActive, gEarnManualCleanupAttempted, gEarnTaskActive, gEarnAFKCleanup, gEarnMCTCleanupOK, stopStatus
global beginStopInjected, gEarnSellNotices, tooltips
global lifecycleTrace, lifecycleEvents, finalizerProbeStages
global gEarnInputAbortReason, metadataFailure, metadataCalls
global recoveryHud, recoveryHudAfter, recoveryMenuCloseOK, visibleModal
global hudDepth := 0, hudTakes := 0, hudReturns := 0, hudInject := ""
global hudStopCount := 0, hudStopReleaseCount := 0
global clawLoopRunning := false, clawTries := 0, clickRunning := false, wRunning := false, shiftWRunning := false
global vellumDrivingRunning := false, cayoTimerRunning := false, cayoEndTick := 0, altF4Running := false
global gJobWarpStart := 0, gJobWarpMinMs := 0, mcRunning := false, gMenuBusy := false
global state := Map(), stateWritable := true
Reset()
previousHUDStops := hudStopCount
EarnTick()
Check(hudStopCount > previousHUDStops && hudStopReleaseCount >= 1,
    "normal finalizer releases held keys before synchronous HUD restoration")
Reset()
endOK := false, endNoScreen := true, recoveryHud := false, recoveryHudAfter := false
EarnTick()
fakeTick := gEarnRecovery.nextTick
EarnTick()
Check(IsObject(gEarnRecovery) && gEarnRecovery.attempts = 2 && gEarnDone["bunker"] = 0
    && bossOffCount = 0 && !HasLog("복구 완료:") && !HasLog("복구 해제:"),
    "unknown no-screen recovery cannot report cleanup or finish transactions even when the arrow probe succeeds")
fakeTick := gEarnRecovery.nextTick
EarnTick()
Check(IsObject(gEarnRecovery) && gEarnRecovery.attempts = 3 && calls.Length = 2 && bossOffCount = 0,
    "repeated unknown screens keep guarded recovery without transactions or speculative menu input")
recoveryHud := true, recoveryHudAfter := true
fakeTick := gEarnRecovery.nextTick
EarnTick()
Check(!IsObject(gEarnRecovery) && calls.Length = 2 && bossOffCount = 1
    && gEarnDone["bunker"] = 1 && gEarnDone["dj"] = 1 && HasLog("복구 완료:"),
    "real HUD and CEO confirmation release the original batch exactly once after unknown screens")
for boundary in ["boss-unconfirmed", "menu-close-failed", "hud-lost"] {
    Reset()
    endOK := false, endNoScreen := true
    bossProbeOK := boundary != "boss-unconfirmed"
    recoveryMenuCloseOK := boundary != "menu-close-failed"
    recoveryHudAfter := boundary != "hud-lost"
    EarnTick()
    fakeTick := gEarnRecovery.nextTick
    EarnTick()
    Check(IsObject(gEarnRecovery) && gEarnRecovery.attempts = 2 && gEarnDone["bunker"] = 0
        && calls.Length = 2 && bossOffCount = 1 && !HasLog("복구 완료:"),
        "no-screen confirmation rejects " boundary " without repeating task bodies")
}
for modal in ["dj_confirm_solomun", "dj_confirm_tale"] {
    Reset()
    previousHUDStops := hudStopCount
    visibleModal := modal
    afkResult := EarnAFKCloseMCT(600)
    Check(afkResult = "MCT 화면 정리 완료 idle=600s" && endCount = 1 && bossOffCount = 1
        && !gEarnBusy && !gEarnAFKCleanup,
        "AFK cleanup recognizes the isolated " modal " without a visible background page")
    Check(hudStopCount > previousHUDStops, "AFK cleanup releases MCT HUD protection in finally: " modal)
}
Reset()
gEarnInputAbortReason := "stale"
EarnInputGuardStart()
fakeTick += 100, idleMs += 100
Check(EarnInputAllowed() && gEarnInputAbortReason = "" && metadataCalls = 0 && releaseCount = 0,
    "normal guarded work clears the previous reason without diagnostic window reads")
for scenario in ["physical", "focus", "both"] {
    Reset()
    previousHUDStops := hudStopCount
    EarnInputGuardStart()
    fakeTick += 100
    idleMs := scenario = "focus" ? 60100 : 0
    focused := scenario = "physical"
    expectedAbort := scenario = "physical" ? "사용자 물리 입력으로 중단" : scenario = "focus" ? "GTA 포커스 판정 실패로 중단" : "사용자 물리 입력 및 GTA 포커스 판정 실패로 중단"
    Check(!EarnInputAllowed() && gAbort && gEarnUserAbort && gEarnInputAbortReason = expectedAbort && releaseCount = 1,
        scenario " immediately latches the exact reason and releases keys")
    Check(hudStopCount > previousHUDStops && hudStopReleaseCount = 1,
        scenario " restores MCT HUD immediately after key release without waiting for a low priority timer")
    Check(InputEvidenceCount() = 1 && HasLog("physical=" (scenario = "focus" ? 0 : 1) " focus=" (scenario = "physical" ? 0 : 1))
        && HasLog("idle_ms=" idleMs " elapsed_ms=100 winactive=" (focused ? 1 : 0))
        && HasLog("expected_game_pid=101") && HasLog("game={hwnd=1 pid=101")
        && HasLog(scenario = "physical" ? "foreground={hwnd=1 pid=101" : "foreground={hwnd=777 pid=707"),
        scenario " records one complete diagnostic after key release")
    EarnFail("화면 판독 중단 또는 시간 초과")
    EarnInputAllowed()
    Check(InputEvidenceCount() = 1 && releaseCount = 1 && gEarnInputAbortReason = expectedAbort,
        scenario " preserves the first reason across repeated guards and later OCR failure")
}
Reset()
EarnInputGuardStart()
focused := false, metadataFailure := true
Check(!EarnInputAllowed() && gAbort && releaseCount = 1 && InputEvidenceCount() = 1
    && HasLog('foreground={hwnd=777 pid=unknown exe="unknown" title="unknown"}'),
    "unreadable window metadata cannot prevent abort or key release")
Check(EarnInputEvidenceText("line1`r`n" Chr(34) "line2") = '"line1\r\n\"line2"',
    "window titles remain escaped on one diagnostic line")
Reset()
EarnInputGuardStart()
focused := false
EarnInputAllowed()
previousHUDStops := hudStopCount
EarnInputGuardStop()
Check(hudStopCount > previousHUDStops && !gEarnGuardArmed, "guard ending synchronously restores HUD before the next job")
gAbort := false, gEarnUserAbort := false, focused := true
EarnInputGuardStart()
Check(EarnInputAllowed() && gEarnInputAbortReason = "" && InputEvidenceCount() = 1,
    "new guarded attempt does not inherit the previous abort reason")
for scenario in ["physical", "focus", "both"] {
    Reset()
    mode := scenario "-ocr"
    EarnTick()
    expectedAbort := scenario = "physical" ? "사용자 물리 입력으로 중단" : scenario = "focus" ? "GTA 포커스 판정 실패로 중단" : "사용자 물리 입력 및 GTA 포커스 판정 실패로 중단"
    Check(gEarnFail = expectedAbort && HasLog("bunker: " expectedAbort " → 손을 떼면 바로 다시") && tooltips[tooltips.Length] = "💰 " expectedAbort " → 손을 떼면 바로 다시",
        scenario " scheduler and tooltip preserve the first reason after OCR overwrites gEarnFail")
}
Reset()
gEarnInputAbortReason := "old focus failure"
SetEarner(true)
Check(gEarnInputAbortReason = "", "manual enable clears old guard evidence")
Reset()
gEarnInputAbortReason := "outer reason", gEarnUserAbort := true, mctOpen := true, endInput := true, endDelay := 100
afkResult := EarnAFKCloseMCT(600)
Check(InStr(afkResult, "사용자 물리 입력으로 중단") && gEarnInputAbortReason = "outer reason" && gEarnUserAbort,
    "AFK cleanup reports its own abort but restores the caller evidence scope")
Reset()
gEarnInputAbortReason := "old guard reason", gEarnUserAbort := true, gAbort := true
gEarnGuardArmed := true, lockHeld := true, mctOpen := true
Check(EarnManualStopCleanup() && gEarnInputAbortReason = "" && !gEarnUserAbort,
    "manual MCT cleanup starts a fresh evidence scope")
Reset()
gEarnInputAbortReason := "old guard reason", gEarnUserAbort := true, gAbort := true
gEarnGuardArmed := true, lockHeld := true
Check(EarnManualBossOffCleanup() && gEarnInputAbortReason = "" && !gEarnUserAbort,
    "manual CEO cleanup starts a fresh evidence scope")
Reset()
gEarnManualStop := true, gAbort := true, gEarnUserAbort := true
gEarnInputAbortReason := "GTA 포커스 판정 실패로 중단", gEarnFail := "화면 판독 중단 또는 시간 초과"
EarnFinishManualStop(false, true, true)
Check(gEarnFail = "GTA 포커스 판정 실패로 중단" && gEarnInputAbortReason = "" && !gEarnUserAbort,
    "manual finalizer preserves first guard reason in the result then clears its evidence scope")
Reset()
gEarnInputAbortReason := "old guard reason", gEarnBusy := true
SetEarner(false, "메모리 보호")
Check(gEarnInputAbortReason = "" && gEarnFail = "메모리 보호" && gAbort,
    "explicit hard stop replaces stale input evidence with its own reason")
Reset()
gEarnFail := "old failure"
gEarnOn := false
SetEarner(false)
Check(gEarnFail = "" && EarnStatusText() = "", "idle manual off clears stale stopped overlay")
Reset()
endStopMode := "manual"
EarnTick()
Check(!gEarnOn && !gAbort && !gEarnManualStop && !gEarnManualCleanupActive && !gEarnManualCleanupAttempted,
    "busy F9 off consumes only its original abort after safe cleanup")
Check(endCount = 2 && bossOffCount = 1 && !mctOpen && lockReleases = 1 && gEarnFail = "",
    "F9 during MCT cleanup retries once, closes the session, and retires CEO before unlocking")
Check(staleFailInjected && stopStatus = "수익: 끄는 중 · MCT 정리와 CEO 해제"
    && blockedRestartObserved && TimerPeriodCount(1000) = 0 && EarnStatusText() = ""
    && gEarnDone["bunker"] = 0 && gEarnDone["dj"] = 0,
    "busy F9 off clears the OCR race and does not record interrupted work as complete")
Reset()
mode := "finalizer-race"
gEarnOn := false, gEarnManualStop := true, gEarnManualCleanupAttempted := true
gAbort := true, gEarnUserAbort := true, gEarnFail := "화면 판독 중단 또는 시간 초과"
EarnFinishManualStop(false, true, true)
Check(finalizerProbeStages.Length = 3
    && finalizerProbeStages[1].stage = "log" && finalizerProbeStages[1].abort
    && finalizerProbeStages[2].stage = "tooltip" && finalizerProbeStages[2].abort
    && finalizerProbeStages[3].stage = "abort-cleared" && !finalizerProbeStages[3].abort
    && !finalizerProbeStages[3].userAbort
    && finalizerProbeStages[1].latched && finalizerProbeStages[2].latched && finalizerProbeStages[3].latched
    && finalizerProbeStages[1].critical && finalizerProbeStages[2].critical && finalizerProbeStages[3].critical,
    "manual stop finalizer stays critical and latched through log, tooltip, and abort cleanup")
Check(!gEarnManualStop && !gEarnManualCleanupAttempted && !gAbort && !gEarnUserAbort && !A_IsCritical,
    "manual stop finalizer clears its latches last and leaves the critical section")
Reset()
gEarnOn := false, gEarnManualStop := false, gEarnManualCleanupAttempted := false
gAbort := true, gEarnUserAbort := false, gEarnFail := "전체 멈춤"
EarnFinishManualStop(true, true, true)
Check(gAbort && !gEarnManualStop && !gEarnManualCleanupAttempted && gEarnFail = "전체 멈춤"
    && logs.Length = 0 && !A_IsCritical,
    "hard stop that clears the latch first preempts the stale manual finalizer without clearing abort")
for hardReason in ["전체 멈춤", "메모리 보호"] {
    Reset()
    endStopMode := hardReason
    EarnTick()
    Check(!gEarnOn && gAbort && !gEarnManualStop && endCount = 1 && bossOffCount = 0
        && mctOpen && lockReleases = 1 && gEarnFail = hardReason,
        hardReason " stays a hard stop without cleanup input")
}
Reset()
endStopMode := "manual-user"
EarnTick()
Check(!gAbort && !gEarnUserAbort && !gEarnManualStop && mctOpen && bossOffCount = 0
    && gEarnFail = "사용자 물리 입력으로 중단"
    && EarnStatusText() = "수익 멈춤: 사용자 물리 입력으로 중단",
    "manual cleanup interruption keeps its reason but releases the abort latch for later AFK cleanup")
Reset()
gEarnTasks := [{id:"safe", label:"safe", on:true, every:300000, fn:RunTask.Bind("safe")}]
gEarnDue := Map("safe", 0), gEarnDone := Map("safe", 0)
mode := "manual-stop-app"
EarnTick()
Check(!gEarnOn && !gAbort && gEarnFail = "" && EarnStatusText() = "" && gEarnDone["safe"] = 0
    && endCount = 0 && bossOffCount = 0,
    "manual off outside MCT stops without cleanup input or a false CEO warning")
Reset()
mctOpen := true
endStopMode := "afk-manual"
afkResult := EarnAFKCloseMCT(600)
Check(afkResult = "MCT 화면 정리 완료 idle=600s" && !gEarnOn && !gEarnBusy && !gEarnAFKCleanup
    && !gEarnManualStop && !gEarnManualCleanupAttempted && !gAbort && gEarnFail = "",
    "F9 during AFK MCT cleanup consumes its stop latch after the existing cleanup")
Check(endCount = 2 && bossOffCount = 1 && !mctOpen && !gEarnGuardArmed,
    "AFK MCT cleanup retries once after F9 key-up, then closes the session and retires CEO")
Reset()
mode := "begin-initial-manual"
gEarnBusy := true, gEarnTaskActive := true, gEarnGuardArmed := true, lockHeld := true, mctOpen := true
endOK := false
beginResult := ProductionEarnTaskMCTBegin()
Check(!beginResult && beginStopInjected && endCount = 1 && gEarnManualCleanupAttempted && gEarnManualStop
    && !gEarnMCTCleanupOK && mctOpen && bossOffCount = 0,
    "F9 during initial MCT OCR uses the central cleanup wrapper and propagates cleanup failure")
Reset()
Check(EarnTransactionBegin("staff", "sent") && state["pending_staff"] = "sent", "request records persistent pending before input")
EarnTransactionConfirmed("staff")
Check(state["pending_staff"] = "", "confirmed result clears pending")
stateWritable := false
Check(!EarnTransactionBegin("staff", "sent"), "state persistence failure prevents transaction")
Reset()
state["pending_staff"] := "unconfirmed before restart"
SetEarner(true)
Check(!gEarnHeld.Has("staff") && state["pending_staff"] = "", "staff dispatch never stays held across restarts")
Reset()
state["pending_bunker"] := "unconfirmed before restart"
SetEarner(true)
Check(gEarnHeld.Has("bunker") && state["pending_bunker"] != "", "manual enable preserves unconfirmed purchase across restarts")
Reset()
gEarnOn := false
EarnTick()
Check(calls.Length = 0, "disabled")
Reset()
gEarnBusy := true
EarnTick()
Check(calls.Length = 0, "busy")
Reset()
windowExists := false
EarnTick()
Check(calls.Length = 0 && !gEarnOn && stopped = 1 && releaseCount = 0, "no game stops without cleanup input")
Reset()
fakePID := 102
EarnTick()
Check(calls.Length = 0 && !gEarnOn && stopped = 1 && lockCalls = 0, "game restart requires manual enable")
Reset()
config["Settings"]["EarnUserIdleSec"] := 1000000000
EarnTick()
Check(calls.Length = 0, "user active")
Reset()
idleMs := 1999
EarnTick()
Check(calls.Length = 0 && lockCalls = 0 && !gEarnGuardArmed, "two-second start gate waits at 1999ms")
fakeTick++, idleMs++
EarnTick()
Check(calls.Length = 2 && gEarnDone["bunker"] = 1 && lockReleases = 1, "two-second start gate executes at 2000ms")
Reset()
idleMs := 2000
mode := "long-readonly"
EarnTick()
Check(gEarnOn && !gAbort && gEarnDone["bunker"] = 1 && lockReleases = 1, "pre-start input never aborts long readonly work")
Reset()
idleMs := 2000
mode := "long-physical"
EarnTick()
Check(gEarnOn && !gAbort && idleMs > 2000 && gEarnDone["bunker"] = 0 && lockReleases = 1 && gEarnDue["bunker"] <= A_TickCount,
    "input during blocked work aborts even when newer idle exceeds start wait")
Reset()
idleMs := 0
Check(EarnStatusText() = "MCT · 수익: 입력 안정 대기 2초", "overlay shows two-second input countdown")
idleMs := 1999
Check(EarnStatusText() = "MCT · 수익: 입력 안정 대기 1초", "overlay keeps countdown before boundary")
idleMs := 2000
Check(EarnStatusText() = "MCT · 수익: bunker 시작 대기", "overlay clears input countdown at boundary")
focused := false
Check(EarnStatusText() = "MCT · 수익: GTA 포커스 대기", "overlay explains focus wait")
focused := true, otherBusy := true
Check(EarnStatusText() = "MCT · 수익: 다른 매크로 종료 대기", "overlay explains busy macro wait")
otherBusy := false
for id in ["bunker", "dj"]
    gEarnDue[id] := A_TickCount + 5000
Check(EarnStatusText() = "MCT · 수익: 다음 bunker 0:05 뒤", "overlay preserves future due countdown")
gEarnCurrent := "bunker", idleMs := 0, focused := false
Check(EarnStatusText() = "MCT · 수익: bunker 진행 중", "running task status precedes startup wait")
Reset()
otherBusy := true
EarnTick()
Check(calls.Length = 0, "other macro")
Reset()
gEarnDue["bunker"] := A_TickCount + 300000
gEarnDue["dj"] := A_TickCount + 300000
EarnTick()
Check(calls.Length = 0, "not due")
Reset()
EarnTick()
EarnTick()
EarnTick()
Check(calls.Length = 2 && calls[1] = "bunker" && calls[2] = "dj", "serial and no immediate repeat")
Check(selfMarks = "SE", "earner marks its own input span for idle detection")
Check(gEarnDone["bunker"] = 1 && gEarnDone["dj"] = 1 && releaseCount = 1, "counts and one grouped release")
gEarnDue["bunker"] := A_TickCount - 1
EarnTick()
Check(calls.Length = 3 && gEarnDone["bunker"] = 2, "next cycle")
Reset()
gEarnDue["dj"] := A_TickCount + 60000
EarnTick()
Check(calls.Length = 2 && calls[2] = "dj" && releaseCount = 1 && gEarnDone["dj"] = 1, "MCT task due within batch window joins the session")
Reset()
gEarnDue["dj"] := A_TickCount + 121000
EarnTick()
Check(calls.Length = 1 && calls[1] = "bunker" && gEarnDone["dj"] = 0, "MCT task beyond batch window waits")
Reset()
gEarnTasks := [{id:"bunker",label:"bunker",on:true,every:300000,fn:RunTask.Bind("bunker")},
    {id:"staff",label:"staff",on:true,every:300000,fn:RunTask.Bind("staff")}]
gEarnDue := Map("bunker", fakeTick - 1, "staff", fakeTick + 120000)
gEarnDone := Map("bunker", 0, "staff", 0), taskModes := Map("bunker", "override-short"), endDelay := 180000
EarnTick()
Check(calls.Length = 1 && calls[1] = "bunker" && gEarnDue["bunker"] = fakeTick + 60000
    && gEarnDue["staff"] < gEarnDue["bunker"],
    "expired bunker self-schedule waits one minute after long MCT cleanup")
EarnTick()
Check(calls.Length = 2 && calls[2] = "staff" && gEarnDone["staff"] = 1,
    "older staff due runs before repeated bunker observation")
EarnTick()
Check(calls.Length = 2, "completed bunker does not repeat immediately after the older task")
fakeTick := gEarnDue["bunker"] - 1
EarnTick()
Check(calls.Length = 2, "expired bunker self-schedule waits the full post-cleanup minute")
fakeTick++
EarnTick()
Check(calls.Length = 3 && calls[3] = "bunker" && gEarnDone["bunker"] = 2,
    "expired bunker self-schedule runs after the post-cleanup minute")
Reset()
gEarnTasks := [{id:"dj",label:"dj",on:true,every:300000,fn:RunTask.Bind("dj")},
    {id:"staff",label:"staff",on:true,every:300000,fn:RunTask.Bind("staff")}]
gEarnDue := Map("dj", fakeTick - 1, "staff", fakeTick + 120000)
gEarnDone := Map("dj", 0, "staff", 0), taskModes := Map("dj", "override-short"), endDelay := 180000
EarnTick()
Check(calls.Length = 1 && calls[1] = "dj" && gEarnDue["dj"] = fakeTick
    && gEarnDue["staff"] < gEarnDue["dj"],
    "expired non-bunker self-schedule still loses stale priority at completion")
EarnTick()
Check(calls.Length = 2 && calls[2] = "staff",
    "older staff due still runs before the completed non-bunker task")
Reset()
gEarnTasks := [{id:"bunker",label:"bunker",on:true,every:300000,fn:RunTask.Bind("bunker")}]
gEarnDue := Map("bunker", fakeTick - 1), gEarnDone := Map("bunker", 0), endDelay := 360000
EarnTick()
Check(gEarnDue["bunker"] = fakeTick,
    "bunker fallback interval without an explicit reservation keeps the generic completion clamp")
Reset()
sellReason := "나이트클럽 창고 만재 3개: 판매 필요"
gEarnFail := "existing failure", gEarnRetryIn := 1234
EarnNotifyStockFull("nightclub", sellReason)
Check(gEarnSellNotices.Count = 1 && gEarnSellNotices["nightclub"] = sellReason && logs.Length = 1 && tooltips.Length = 1
    && gEarnOn && !gAbort && !gEarnManualStop && gEarnFail = "existing failure" && gEarnRetryIn = 1234,
    "stock-full notification changes only notice and output, not control flow or failure state")
EarnNotifyStockFull("nightclub", sellReason)
Check(logs.Length = 1 && tooltips.Length = 1, "unchanged stock-full notice is deduplicated")
EarnNotifyStockFull("nightclub", "나이트클럽 창고 만재 4개: 판매 필요")
Check(logs.Length = 2 && tooltips.Length = 2 && gEarnSellNotices["nightclub"] = "나이트클럽 창고 만재 4개: 판매 필요",
    "changed stock-full notice for the same source is reported")
EarnNotifyStockFull("bunker", "벙커 재고 만재: 판매 필요")
Check(logs.Length = 3 && tooltips.Length = 3 && gEarnSellNotices.Count = 2
    && gEarnSellNotices["nightclub"] = "나이트클럽 창고 만재 4개: 판매 필요"
    && gEarnSellNotices["bunker"] = "벙커 재고 만재: 판매 필요",
    "different stock-full sources coexist without overwriting")
runningNotices := RunningItems()
Check(runningNotices.Length >= 2 && HasItem(runningNotices, gEarnSellNotices["nightclub"])
    && HasItem(runningNotices, gEarnSellNotices["bunker"]),
    "actual overlay consumer displays every concurrent stock notice")
EarnClearStockNotice("nightclub")
Check(gEarnSellNotices.Count = 1 && !gEarnSellNotices.Has("nightclub")
    && gEarnSellNotices["bunker"] = "벙커 재고 만재: 판매 필요"
    && logs.Length = 4 && tooltips.Length = 3,
    "clearing one source preserves the other source and emits no tooltip")
EarnClearStockNotice("nightclub")
Check(logs.Length = 4 && tooltips.Length = 3 && gEarnSellNotices.Count = 1,
    "clearing an already absent source is idempotent")
Reset()
sellReason := "나이트클럽 창고 만재 3개: 판매 필요"
gEarnTasks := [{id:"bunker",label:"bunker",on:true,every:300000,fn:RunTask.Bind("bunker")},
    {id:"warehouse",label:"warehouse",on:true,every:300000,fn:RunTask.Bind("warehouse")},
    {id:"dj",label:"dj",on:true,every:300000,fn:RunTask.Bind("dj")},
    {id:"safe",label:"safe",on:true,every:300000,fn:RunTask.Bind("safe")}]
gEarnDue := Map("bunker", fakeTick - 1, "warehouse", fakeTick - 1, "dj", fakeTick - 1, "safe", fakeTick - 1)
gEarnDone := Map("bunker", 0, "warehouse", 0, "dj", 0, "safe", 0), taskModes := Map("warehouse", "stock-full")
sellStart := fakeTick
EarnTick()
Check(calls.Length = 3 && calls[1] = "bunker" && calls[2] = "warehouse" && calls[3] = "dj"
    && gEarnDone["bunker"] = 1 && gEarnDone["warehouse"] = 1 && gEarnDone["dj"] = 1,
    "stock-full notification allows following MCT tasks and finalizes all bodies once")
Check(gEarnDue["bunker"] = sellStart + 300000 && gEarnDue["warehouse"] = sellStart + 300000
    && gEarnDue["dj"] = sellStart + 300000 && !gEarnFailures.Has("bunker") && !gEarnFailures.Has("warehouse"),
    "stock-full batch keeps ordinary scheduling for every completed task")
Check(gEarnOn && !gAbort && !gEarnBusy && !gEarnGuardArmed && !lockHeld && lockReleases = 1
    && endCount = 1 && bossOffCount = 1 && !mctOpen && stopped = 0
    && gEarnSellNotices.Get("nightclub", "") = sellReason && gEarnFail = "" && !InStr(EarnStatusText(), "수익 멈춤:"),
    "stock-full batch remains enabled after guarded MCT cleanup without a stopped overlay")
EarnTick()
Check(calls.Length = 4 && calls[4] = "safe" && gEarnDone["safe"] = 1 && gEarnOn,
    "the next tick runs a non-MCT task after stock-full detection")
fakeTick := gEarnDue["bunker"], idleMs := 60000
EarnTick()
Check(calls.Length = 7 && gEarnDone["bunker"] = 2 && gEarnDone["warehouse"] = 2 && gEarnDone["dj"] = 2
    && endCount = 2 && bossOffCount = 2 && gEarnOn && stopped = 0 && tooltips.Length = 1,
    "future due ticks continue full-stock checks and following tasks without repeating the same notice")
SetEarner(false, "", "manual")
EarnTick()
Check(!gEarnOn && calls.Length = 7 && stopped = 1 && !gEarnManualStop,
    "manual F9 still stops automation after stock-full detection and later ticks do not restart it")
Check(gEarnSellNotices.Get("nightclub", "") = sellReason,
    "manual F9 off preserves the last confirmed stock notice")
Reset()
sellReason := "나이트클럽 창고 만재 3개: 판매 필요"
gEarnTasks := [{id:"bunker",label:"bunker",on:true,every:300000,fn:RunTask.Bind("bunker")},
    {id:"warehouse",label:"warehouse",on:true,every:300000,fn:RunTask.Bind("warehouse")},
    {id:"dj",label:"dj",on:true,every:300000,fn:RunTask.Bind("dj")}]
gEarnDue := Map("bunker", fakeTick - 1, "warehouse", fakeTick - 1, "dj", fakeTick - 1)
gEarnDone := Map("bunker", 0, "warehouse", 0, "dj", 0), taskModes := Map("warehouse", "stock-full")
sellStart := fakeTick, endOK := false
EarnTick()
Check(gEarnOn && IsObject(gEarnRecovery) && gEarnSellNotices.Get("nightclub", "") = sellReason
    && calls.Length = 3 && gEarnDone["bunker"] = 0 && gEarnDone["warehouse"] = 0 && gEarnDone["dj"] = 0,
    "stock-full batch still waits for cleanup recovery before finalizing work")
Check(endCount = 1 && bossOffCount = 0 && mctOpen && lockReleases = 1 && stopped = 0,
    "failed stock-full cleanup keeps automation on and the MCT recovery state open")
endOK := true, fakeTick := gEarnRecovery.nextTick, idleMs := 60000
EarnTick()
Check(calls.Length = 3 && endCount = 2 && bossOffCount = 1 && lockReleases = 2
    && gEarnDone["bunker"] = 1 && gEarnDone["warehouse"] = 1 && gEarnDone["dj"] = 1,
    "stock-full recovery retries only End and finalizes each completed body once")
Check(gEarnOn && !IsObject(gEarnRecovery) && gEarnSellNotices.Get("nightclub", "") = sellReason && stopped = 0
    && !InStr(EarnStatusText(), "수익 멈춤:"),
    "stock-full recovery resumes normal scheduling without a sale stop")
fakeTick := gEarnDue["bunker"], idleMs := 60000
EarnTick()
Check(calls.Length = 6 && gEarnDone["bunker"] = 2 && gEarnDone["warehouse"] = 2 && gEarnDone["dj"] = 2,
    "the recovered stock-full batch runs again at its next ordinary due time")
Reset()
sellReason := "나이트클럽 창고 만재 3개: 판매 필요"
gEarnTasks := [{id:"bunker",label:"bunker",on:true,every:300000,fn:RunTask.Bind("bunker")},
    {id:"warehouse",label:"warehouse",on:true,every:300000,fn:RunTask.Bind("warehouse")},
    {id:"dj",label:"dj",on:true,every:300000,fn:RunTask.Bind("dj")}]
gEarnDue := Map("bunker", fakeTick - 1, "warehouse", fakeTick - 1, "dj", fakeTick - 1)
gEarnDone := Map("bunker", 0, "warehouse", 0, "dj", 0), taskModes := Map("warehouse", "stock-full")
endOK := false, endNoScreen := true, bossProbeOK := false
EarnTick()
lifecycleTrace := true, lifecycleEvents := []
fakeTick := gEarnRecovery.nextTick, idleMs := 60000
EarnTick()
lifecycleTrace := false
Check(bossProbeGuardedCount = 1 && lifecycleEvents.Length = 5
    && lifecycleEvents[1] = "lock-acquire" && lifecycleEvents[2] = "guard-start"
    && lifecycleEvents[3] = "boss-strict" && lifecycleEvents[4] = "guard-stop"
    && lifecycleEvents[5] = "lock-release",
    "ordinary no-screen CEO probe runs before guard stop and input lock release")
Check(gEarnOn && IsObject(gEarnRecovery) && gEarnSellNotices.Get("nightclub", "") = sellReason
    && calls.Length = 3 && endCount = 2 && bossProbeCount = 1 && bossProbeStrictCount = 1
    && gEarnDone["bunker"] = 0 && gEarnDone["warehouse"] = 0 && gEarnDone["dj"] = 0 && stopped = 0,
    "stock-full waits for confirmed cleanup without stopping or repeating transactions")
Check(!HasLog("복구 해제:") && !HasLog("복구 완료:") && !HasLog("꺼짐"),
    "unconfirmed cleanup never reports release or completion")
Reset()
sellReason := "나이트클럽 창고 만재 3개: 판매 필요"
gEarnTasks := [{id:"bunker",label:"bunker",on:true,every:300000,fn:RunTask.Bind("bunker")},
    {id:"warehouse",label:"warehouse",on:true,every:300000,fn:RunTask.Bind("warehouse")},
    {id:"dj",label:"dj",on:true,every:300000,fn:RunTask.Bind("dj")}]
gEarnDue := Map("bunker", fakeTick - 1, "warehouse", fakeTick - 1, "dj", fakeTick - 1)
gEarnDone := Map("bunker", 0, "warehouse", 0, "dj", 0), taskModes := Map("warehouse", "stock-full")
endOK := false, endNoScreen := true
EarnTick()
bossProbeMode := "manual-retry-success", lifecycleTrace := true, lifecycleEvents := []
fakeTick := gEarnRecovery.nextTick, idleMs := 60000
EarnTick()
lifecycleTrace := false
Check(bossStopInjected && bossProbeCount = 2 && bossProbeStrictCount = 2 && bossProbeGuardedCount = 2
    && bossRetryBaselineOK && bossRetryCleanupStateOK && lifecycleEvents.Length = 6
    && lifecycleEvents[1] = "lock-acquire" && lifecycleEvents[2] = "guard-start"
    && lifecycleEvents[3] = "boss-strict" && lifecycleEvents[4] = "boss-strict"
    && lifecycleEvents[5] = "guard-stop" && lifecycleEvents[6] = "lock-release"
    && lockCalls = 2 && lockReleases = 2 && calls.Length = 3 && endCount = 2,
    "F9 during ordinary CEO retirement retries exactly once under the same guarded input lock")
Check(!gEarnOn && !gEarnManualStop && !gEarnManualCleanupActive && !gEarnManualCleanupAttempted
    && !gAbort && !gEarnUserAbort && gEarnFail = "" && EarnStatusText() = ""
    && gEarnDone["bunker"] = 0 && gEarnDone["warehouse"] = 0 && gEarnDone["dj"] = 0
    && HasLog("끄기 정리 재확인: CEO 해제 도중 F9 감지")
    && HasLog("꺼짐: MCT 정리와 CEO 해제 완료"),
    "successful ordinary CEO retry finalizes the F9 stop as cleaned without rerunning task bodies")
Reset()
sellReason := "나이트클럽 창고 만재 3개: 판매 필요"
gEarnTasks := [{id:"bunker",label:"bunker",on:true,every:300000,fn:RunTask.Bind("bunker")},
    {id:"warehouse",label:"warehouse",on:true,every:300000,fn:RunTask.Bind("warehouse")},
    {id:"dj",label:"dj",on:true,every:300000,fn:RunTask.Bind("dj")}]
gEarnDue := Map("bunker", fakeTick - 1, "warehouse", fakeTick - 1, "dj", fakeTick - 1)
gEarnDone := Map("bunker", 0, "warehouse", 0, "dj", 0), taskModes := Map("warehouse", "stock-full")
endOK := false, endNoScreen := true
EarnTick()
bossProbeMode := "manual-retry-fail", lifecycleTrace := true, lifecycleEvents := []
fakeTick := gEarnRecovery.nextTick, idleMs := 60000
EarnTick()
lifecycleTrace := false
Check(bossStopInjected && bossProbeCount = 2 && bossProbeStrictCount = 2 && bossProbeGuardedCount = 2
    && bossRetryBaselineOK && bossRetryCleanupStateOK && lifecycleEvents.Length = 6
    && lifecycleEvents[3] = "boss-strict" && lifecycleEvents[4] = "boss-strict"
    && lifecycleEvents[5] = "guard-stop" && lifecycleEvents[6] = "lock-release"
    && lockCalls = 2 && lockReleases = 2 && calls.Length = 3 && endCount = 2,
    "failed ordinary CEO retry is still bounded to one retry under the same guard and lock")
Check(!gEarnOn && !gEarnManualStop && !gEarnManualCleanupActive && !gEarnManualCleanupAttempted
    && !gAbort && !gEarnUserAbort
    && gEarnFail = "수동 종료 정리 미확인. 화면 확인 후 보스 해제 필요"
    && EarnStatusText() = "수익 멈춤: 수동 종료 정리 미확인. 화면 확인 후 보스 해제 필요"
    && gEarnDone["bunker"] = 0 && gEarnDone["warehouse"] = 0 && gEarnDone["dj"] = 0
    && HasLog("끄기 정리 재확인: CEO 해제 도중 F9 감지")
    && HasLog("끄기 정리 실패: 수동 종료 정리 미확인. 화면 확인 후 보스 해제 필요"),
    "failed ordinary CEO retry finalizes the F9 stop with an explicit cleanup warning")
Reset()
mode := "override"
EarnTick()
Check(gEarnDue["bunker"] > A_TickCount + 299000 && !gEarnNextDue.Has("bunker"), "task override consumed")
Reset()
mode := "retry"
EarnTick()
Check(gEarnOn && gEarnSoftFails["bunker"] = 1 && gEarnDue["bunker"] > A_TickCount + 59000, "soft retry")
gEarnDue["bunker"] := A_TickCount - 1
EarnTick()
Check(gEarnOn && stopped = 0 && gEarnSoftFails["bunker"] = 2 && gEarnDue["bunker"] > fakeTick + 59000 && gEarnDue["bunker"] < fakeTick + 120000, "repeated failure keeps the task wait without backoff or stopping")
Reset()
mode := "fail"
EarnTick()
Check(gEarnOn && stopped = 0 && releaseCount = 1 && !gEarnBusy && gEarnFailures.Has("bunker"), "individual failure records and continues")
mode := "ok"
EarnTick()
Check(calls.Length >= 2 && calls[calls.Length] = "dj" && gEarnDone["dj"] = 1, "other due task runs after failure even when the failed task retries at once")
Reset()
mode := "ambiguous"
EarnTick()
Check(gEarnOn && gEarnHeld.Has("bunker") && gEarnFailures["bunker"].nextTick = 0, "ambiguous transaction holds only its task")
mode := "ok"
EarnTick()
fakeTick += 3600000
EarnTick()
Check(calls.Length = 3 && calls[2] = "dj" && calls[3] = "dj", "held task never repeats while other task continues")
Reset()
endOK := false
EarnTick()
Check(gEarnOn && IsObject(gEarnRecovery) && gEarnDone["bunker"] = 0 && !lockHeld, "cleanup failure schedules guarded recovery and releases lock")
EarnTick()
Check(calls.Length = 2 && endCount = 2, "recovery retries cleanup at once without business input")
gEarnTasks.Push({id:"warehouse",label:"warehouse",on:true,every:300000,fn:RunTask.Bind("warehouse")})
gEarnDue["warehouse"] := 0, gEarnDone["warehouse"] := 0
endInput := true, fakeTick := gEarnRecovery.nextTick
EarnTick()
Check(gEarnRecovery.tasks.Length = 2 && gEarnDue["warehouse"] = 0,
    "user intervention during recovery preserves original batch without postponing new due task")
endInput := false, idleMs := 60000
endOK := true
fakeTick := gEarnRecovery.nextTick
EarnTick()
Check(!IsObject(gEarnRecovery) && endCount = 4 && calls.Length = 2 && gEarnDone["bunker"] = 1, "known cleanup recovery finalizes once without repeating transactions")
Reset()
endOK := false, endNoScreen := true
EarnTick()
Check(IsObject(gEarnRecovery) && gEarnRecovery.attempts = 1, "no-screen cleanup failure first waits in recovery")
fakeTick := gEarnRecovery.nextTick
EarnTick()
Check(!IsObject(gEarnRecovery) && gEarnOn && gEarnDone["bunker"] = 1 && endCount = 2
    && bossOffCount = 1 && bossProbeStrictCount = 1 && HasLog("복구 완료:"),
    "no-screen recovery finishes only after free HUD and actual CEO retirement confirmation")
Reset()
endOK := false, endNoScreen := false
EarnTick()
fakeTick := gEarnRecovery.nextTick
EarnTick()
Check(IsObject(gEarnRecovery) && gEarnRecovery.attempts = 2 && gEarnDone["bunker"] = 0, "other cleanup failures keep guarded recovery")
Reset()
gEarnTasks := [{id:"staff",label:"staff",on:true,every:300000,fn:RunTask.Bind("staff")}]
gEarnDue := Map("staff",0), gEarnDone := Map("staff",0)
mode := "fail", appCloseOK := false
EarnTick()
Check(gEarnOn && IsObject(gEarnRecovery) && appCloseCount = 1 && calls.Length = 1, "failed app schedules known close recovery")
gEarnCleanupNoScreen := true, fakeTick := gEarnRecovery.nextTick
EarnTick()
Check(IsObject(gEarnRecovery) && appCloseCount = 2 && bossOffCount = 0 && calls.Length = 1,
    "app cleanup cannot consume stale MCT no-screen state or change CEO registration")
appCloseOK := true, fakeTick := gEarnRecovery.nextTick
EarnTick()
Check(gEarnOn && !IsObject(gEarnRecovery) && appCloseCount = 3 && calls.Length = 1 && gEarnFailures.Has("staff"), "app recovery does not repeat staff request")
Reset()
mode := "throw"
EarnTick()
Check(gEarnOn && stopped = 0 && releaseCount = 1 && !gEarnBusy && InStr(gEarnFail, "test exception")
    && gEarnFailures.Has("bunker"), "task exception records and retries after cleanup")
Check(lockReleases = 1 && !lockHeld, "exception releases input lock")
mode := "ok"
EarnTick()
Check(calls.Length >= 2 && calls[calls.Length] = "dj", "other task continues after task exception")
Reset()
mode := "reenter"
EarnTick()
Check(calls.Length = 2 && releaseCount = 1, "reentry blocked while outer group continues")
Reset()
focused := false
EarnTick()
Check(calls.Length = 0 && activationCount = 0 && gEarnDue["bunker"] > A_TickCount + 29000, "focus loss postpones without activation")
Reset()
endOK := false
EarnTick()
Check(IsObject(gEarnRecovery), "recovery focus regression starts from a pending cleanup recovery")
focused := false, fakeTick := gEarnRecovery.nextTick
focusWaitLogs := FocusWaitLogCount(), endBefore := endCount, callsBefore := calls.Length
EarnTick()
Check(FocusWaitLogCount() = focusWaitLogs + 1 && gEarnRecovery.nextTick >= fakeTick + 30000,
    "recovery without focus logs once and postpones the recovery tick by 30 seconds")
fakeTick += 1000
EarnTick()
fakeTick += 28000
EarnTick()
Check(FocusWaitLogCount() = focusWaitLogs + 1 && endCount = endBefore && calls.Length = callsBefore,
    "recovery without focus stays silent on later one-second ticks and sends no input")
fakeTick += 1000
EarnTick()
Check(FocusWaitLogCount() = focusWaitLogs + 2 && IsObject(gEarnRecovery), "recovery without focus logs again only after the 30-second wait")
Reset()
mode := "physical"
EarnTick()
Check(gEarnOn && !gAbort && stopped = 0 && !gEarnGuardArmed && gEarnDone["bunker"] = 0 && gEarnRetryIn = 0
    && gEarnDue["bunker"] <= A_TickCount && gEarnSoftFails.Get("bunker", 0) = 0, "physical input retries as soon as idle instead of stopping")
Reset()
mode := "physical-pending"
EarnTick()
Check(gEarnOn && gEarnHeld.Has("bunker") && state.Has("pending_bunker") && !gAbort,
    "user intervention preserves sent transaction and holds only its task")
Reset()
mode := "focus"
EarnTick()
Check(gEarnOn && !gAbort && !gEarnGuardArmed && gEarnDone["bunker"] = 0 && gEarnDue["bunker"] <= A_TickCount,
    "focus loss retries without a fixed wait instead of stopping")
Reset()
config["Settings"]["EarnUserIdleSec"] := 0
mode := "idle-zero"
EarnTick()
Check(gEarnOn && gEarnDone["bunker"] = 0 && gEarnDue["bunker"] <= A_TickCount, "physical guard still enabled with zero start wait")
Reset()
mode := "pid"
EarnTick()
Check(!gEarnOn && gAbort && stopped = 1 && lockReleases = 1 && !lockHeld, "game restart during task aborts and unlocks")
Reset()
lockAvailable := false
EarnTick()
Check(gEarnOn && calls.Length = 0 && lockCalls = 1 && lockReleases = 0 && releaseCount = 0, "occupied input lock waits without input")
lockAvailable := true
EarnTick()
Check(calls.Length = 2 && lockReleases = 1 && !lockHeld, "available lock resumes due group")
Reset()
mode := "lock-error"
EarnTick()
Check(!gEarnOn && stopped = 1 && calls.Length = 0 && releaseCount = 0, "lock creation failure stops without game input")
Reset()
EarnInputGuardStart()
gAbort := true
Check(!EarnInputAllowed(), "abort stays latched")
EarnInputGuardStop()
Check(!gEarnGuardArmed && timers[timers.Length] = 0, "watch removed")
Reset()
for mctMode in [0,1] {
    config["Settings"]["EarnMCTOnly"] := mctMode
    tasks := EarnTaskList()
    Check(tasks.Length = 6 && tasks[1].id = "bunker" && tasks[2].id = "dj" && tasks[3].id = "warehouse"
        && tasks[4].id = "safe" && tasks[5].id = "staff" && tasks[6].id = "dispatch", "task order " mctMode)
    Check(tasks[4].on && tasks[4].fn.Name = "EarnVinewoodSafeTask" && tasks[3].on
        && tasks[3].fn.Name = "EarnWarehouseTask" && tasks[5].on
        && tasks[5].fn.Name = "EarnVinewoodStaffTask" && !tasks[6].on, "production tasks and MCT safe " mctMode)
}
Check(tasks[3].every = 600000 && tasks[4].every = 300000, "warehouse default and safe screen check interval")
config["Settings"]["EarnWarehouse"] := 0
config["Settings"]["EarnWarehouseIntervalMin"] := 12
tasks := EarnTaskList()
Check(!tasks[3].on && tasks[3].every = 720000, "warehouse explicit setting")
config["Settings"]["EarnBailAgents"] := 0
config["Settings"]["EarnCargoStaff"] := 0
config["Settings"]["EarnStaffIntervalMin"] := 7
tasks := EarnTaskList()
Check(tasks[5].on && tasks[5].every = 420000, "hangar staff alone keeps staff task on")
config["Settings"]["EarnHangarStaff"] := 0
tasks := EarnTaskList()
Check(!tasks[5].on && tasks[5].every = 420000, "staff disabled and interval")
config["Settings"]["EarnCargoStaff"] := 1
Check(EarnTaskList()[5].on, "cargo alone enables staff")
Reset()
start := A_TickCount
gEarnSellNotices["bunker"] := "벙커 재고 만재: 판매 필요"
SetEarner(true)
Check(gEarnOn && gEarnGamePID = fakePID && hooks = 2 && timers[timers.Length] = 1000
    && gEarnSellNotices.Get("bunker", "") = "벙커 재고 만재: 판매 필요",
    "enable binds current game and one-second timer without clearing confirmed notices")
Check(timers.Length = 1, "enable only starts the one-second task scheduler")
Check(gEarnDue["safe"] >= start && gEarnDue["safe"] <= A_TickCount
    && gEarnDue["warehouse"] >= start && gEarnDue["warehouse"] <= A_TickCount, "safe and warehouse first check immediately")
Check(gEarnDue["bunker"] <= A_TickCount && gEarnDue["dj"] <= A_TickCount, "bunker and DJ fresh read immediately")
gEarnNextDue["bunker"] := A_TickCount + 900000
gEarnDone["safe"] := 8
config["Settings"]["EarnSafeFirstMin"] := 3
fakePID := 202
start := A_TickCount
SetEarner(true)
Check(gEarnGamePID = 202 && gEarnNextDue.Count = 0 && gEarnDone["safe"] = 0
    && gEarnDue["safe"] >= start + 180000, "manual restart resets old reservations and respects first wait")
Reset()
windowExists := false
SetEarner(true)
Check(!gEarnOn && hooks = 0 && stopped = 1 && releaseCount = 0, "enable without game stays off")
Reset()
SetEarner(true)
EarnTick()
EarnTick()
EarnTick()
EarnTick()
EarnTick()
Check(calls.Length = 5 && calls[1] = "bunker" && calls[2] = "dj" && calls[3] = "warehouse"
    && calls[4] = "safe" && calls[5] = "staff" && lockReleases = 3, "real task list consumes MCT group then two app tasks")
Reset()
gEarnTasks := [
    {id:"bunker", label:"bunker", on:true, every:300000, fn:RunTask.Bind("bunker")},
    {id:"safe", label:"safe", on:true, every:300000, fn:RunTask.Bind("safe")},
    {id:"staff", label:"staff", on:true, every:300000, fn:RunTask.Bind("staff")}
]
gEarnDue := Map("bunker", fakeTick - 1000, "safe", fakeTick - 5000, "staff", fakeTick - 3000)
gEarnDone := Map("bunker", 0, "safe", 0, "staff", 0)
EarnTick()
Check(calls.Length = 1 && calls[1] = "safe", "oldest overdue task runs before a newer recurring MCT task")
Check(EarnMCTSitOcrMatches(@MCT_PROMPT_LINES@), "recorded HDR MCT prompt OCR fragments are accepted")
Check(!EarnMCTSitOcrMatches([{x:70,y:40,w:55,h:18,text:"Press"},{x:191,y:39,w:114,h:20,text:"to access terminal."}]),
    "different interaction prompt is rejected")
Check(!EarnMCTSitOcrMatches([{x:70,y:40,w:55,h:18,text:"Press"},{x:191,y:62,w:114,h:20,text:"to sit down."}]),
    "prompt fragments at different vertical positions are rejected")
Check(!EarnMCTSitOcrMatches([]), "empty OCR is rejected")
; 1010 17:24 실화면 OCR: 키 문자만 빠지고 한 줄로 읽힘(흰 글자 모드, 일반 모드)
Check(EarnMCTSitOcrMatches([{x:145,y:38,w:205,h:18,text:"Press to sit down."}]), "one-line MCT prompt OCR is accepted")
Check(EarnMCTSitOcrMatches([{x:154,y:40,w:226,h:22,text:"Press to sit down—"}]), "one-line MCT prompt OCR with trailing mark is accepted")
Check(!EarnMCTSitOcrMatches([{x:145,y:38,w:205,h:18,text:"Press to access terminal."}]), "different one-line prompt is rejected")
Check(!EarnMCTSitOcrMatches([{x:145,y:300,w:205,h:18,text:"Press to sit down."}]), "one-line prompt outside the help box is rejected")
; 1010 실화면 OCR(밝기가 템플릿과 달라 템플릿이 실패하던 화면)
Check(EarnMCTSeatedOcrMatches([{x:192,y:38,w:236,h:18,text:"Master Control Terminal"},{x:161,y:70,w:176,h:21,text:"Security Cameras"},{x:118,y:98,w:90,h:20,text:"Stand up"}]),
    "seated MCT menu OCR is accepted")
Check(!EarnMCTSeatedOcrMatches([{x:192,y:38,w:236,h:18,text:"Touchscreen computer"},{x:161,y:70,w:176,h:21,text:"Master Control Terminal"}]),
    "Terrorbyte prompt without Stand up is not a seated menu")
Check(EarnMCTNeedCeoOcrMatches([{x:224,y:40,w:368,h:23,text:"You need to be a CEO or Motorcycle"},{x:242,y:70,w:401,h:23,text:"Club President to manage this business."},{x:197,y:98,w:311,h:21,text:"Press • to register as a CEO."}]),
    "CEO registration prompt OCR is accepted")
Check(!EarnMCTNeedCeoOcrMatches([{x:224,y:40,w:368,h:23,text:"You need to be a Motorcycle Club"},{x:197,y:98,w:311,h:21,text:"Press • to start a Motorcycle Club."}]),
    "MC president prompt is not the CEO registration prompt")
Check(EarnMCTTitleOcrMatches([{x:960,y:62,w:521,h:31,text:"MASTER CONTROL TERMINAL"}]), "MCT page title OCR is accepted")
Check(!EarnMCTTitleOcrMatches([]) && !EarnMCTNeedCeoOcrMatches("") && !EarnMCTSeatedOcrMatches(false), "empty or failed OCR is rejected")
Reset()
gEarnBusy := true
SetEarner(false, "전체 멈춤")
Check(gAbort && releaseCount > 0 && !gEarnManualStop && gEarnFail = "전체 멈춤",
    "hard stop releases held keys without starting manual cleanup")
Reset()
EarnTick()
Check(calls.Length = 2 && lockReleases = 1 && hudDepth = 0 && hudTakes = 0,
    "scheduler does not hide whole MCT batch or CEO cleanup")
Reset()
gEarnTasks := [{id:"staff", label:"staff", on:true, every:300000, fn:RunTask.Bind("staff")}]
gEarnDue := Map("staff", fakeTick-1), gEarnDone := Map("staff",0)
EarnTick()
Check(calls.Length = 1 && calls[1] = "staff" && hudDepth = 0 && hudTakes = 0,
    "phone staff task never acquires broad HUD hiding")
Reset()
Check(EarnAFKCloseMCT(300) = "" && endCount = 0 && hudDepth = 0 && hudTakes = 0,
    "AFK first screen check leaves idle HUD visible")
Reset()
mctOpen := true
EarnAFKCloseMCT(300)
Check(endCount = 1 && hudDepth = 0 && hudTakes = 0,
    "AFK relies on MCT screen boundaries rather than whole cleanup lease")
Reset()
gEarnOn := false
gEarnDue := Map(), gEarnDone := Map()
config["Features"]["Earner"] := 1
EarnIdleInit()
EarnModeTick()
Check(gEarnOn && gEarnMode = "apps" && gEarnIdleEnabled, "Main startup arms app scheduler")
Check(!EarnTaskAllowed("bunker") && !EarnTaskAllowed("dj") && !EarnTaskAllowed("warehouse") && !EarnTaskAllowed("dispatch") && EarnTaskAllowed("safe") && EarnTaskAllowed("staff"), "apps mode selects only safe and staff")
gEarnDue["safe"] := fakeTick - 1
gEarnDue["staff"] := fakeTick + 99999
EarnTick()
Check(calls.Length = 1 && calls[1] = "safe" && beginCount = 0 && endCount = 0, "idle safe executes without MCT session")
safeDue := gEarnDue["safe"]
gEarnHeld["staff"] := "pending"
ToggleEarner()
Check(gEarnMode = "full" && gEarnDue["safe"] = safeDue && gEarnHeld.Has("staff"), "F9 full preserves due and holds")
stopped := 0
ToggleEarner()
Check(gEarnOn && gEarnMode = "apps" && stopped = 0 && !gEarnManualStop && gEarnDue["safe"] = safeDue && gEarnHeld.Has("staff"),
    "F9 off only drops MCT tasks and keeps Vinewood apps running without a stop")
Check(endCount = 0 && bossOffCount = 0, "F9 off never runs MCT cleanup or CEO release")
Check(InStr(EarnStatusText(), "바인우드 · ") = 1, "idle status is explicit")
savedTasks := gEarnTasks, savedHeld := gEarnHeld, savedMode := gEarnMode
gEarnTasks := [{id:"bunker",on:true}, {id:"safe",on:true}, {id:"staff",on:false}, {id:"dispatch",on:true}], gEarnHeld := Map()
gEarnMode := "full"
Check(EarnScopeLabel() = "MCT + 바인우드 + 현장 파견", "scope label lists every enabled task group")
gEarnMode := "apps"
Check(EarnScopeLabel() = "바인우드", "apps mode scope drops MCT and dispatch")
gEarnTasks[2].on := false
Check(EarnScopeLabel() = "", "no enabled Vinewood task leaves the scope empty")
gEarnMode := "full", gEarnTasks[2].on := true, gEarnHeld := Map("bunker", "pending")
Check(EarnScopeLabel() = "바인우드 + 현장 파견", "held tasks are not shown as running")
gEarnTasks := savedTasks, gEarnHeld := savedHeld, gEarnMode := savedMode
mctOpen := true
Check(EarnAFKCloseMCT(300) = "" && endCount = 0, "idle apps never invoke AFK MCT cleanup")
SetEarner(false, "전체 멈춤")
EarnModeTick()
Check(!gEarnOn && !gEarnIdleEnabled && gEarnModeRequest = "", "hard stop cancels automatic restart")
Reset()
gEarnMode := "apps", gEarnIdleEnabled := true, gEarnBusy := true
ToggleEarner()
Check(gEarnMode = "apps" && gEarnModeRequest = "full", "F9 mode change waits for active app")
gEarnBusy := false
EarnModeTick()
Check(gEarnMode = "full", "deferred full applies at transaction boundary")
Reset()
gEarnIdleEnabled := true, gEarnManualStop := true, gEarnModeRequest := "apps", gEarnOn := false
EarnFinishManualStop(false, true, true)
EarnModeTick()
Check(!gEarnOn && gEarnModeRequest = "", "failed cleanup cannot restart idle apps")
for appCase in ["ok", "fail", "physical-ocr", "focus-ocr"] {
    Reset()
    gEarnMode := "apps"
    gEarnTasks := [{id:"safe", label:"safe", on:true, every:300000, fn:EarnVinewoodSafeTask}, {id:"staff", label:"staff", on:true, every:300000, fn:EarnVinewoodStaffTask}]
    gEarnDue := Map("safe",fakeTick-1,"staff",fakeTick), gEarnDone := Map("safe",0,"staff",0)
    mode := appCase
    EarnTick()
    Check(beginCount = 0 && endCount = 0 && bossOffCount = 0, "idle safe " appCase " never manages MCT or boss")
}
Reset()
gEarnMode := "apps", gEarnGuardArmed := true, gEarnGuardStartedTick := fakeTick, otherBusy := true
Check(!EarnInputAllowed() && gEarnUserAbort && releaseCount = 1, "another feature preempts active idle app")
Reset()
gEarnMode := "apps", otherBusy := true
EarnTick()
Check(calls.Length = 0 && lockCalls = 0, "busy feature prevents idle input")
Reset()
gEarnMode := "apps"
gEarnRecovery := {task:{id:"safe",label:"safe"},tasks:[],mct:false,outcome:{results:[],cleanupOK:false},attempts:1,nextTick:0}
EarnTick()
Check(appCloseCount = 1 && beginCount = 0 && endCount = 0 && bossOffCount = 0, "idle app recovery only closes app")
Reset()
gEarnOn := false, gEarnIdleEnabled := true, gEarnModeRequest := "apps"
SetEarner(false, "전체 멈춤")
EarnModeTick()
Check(modeTimer = 0 && !gEarnOn, "End before startup removes pending initialization")
Reset()
gEarnIdleEnabled := true, gEarnBusy := true
ToggleEarner()
Check(gEarnOn && gEarnMode = "full" && gEarnModeRequest = "apps" && !gAbort, "F9 off during an MCT batch waits for its boundary")
gEarnBusy := false
EarnModeTick()
Check(gEarnOn && gEarnMode = "apps", "F9 off applies apps mode after the batch")
Reset()
gEarnIdleEnabled := true, gEarnBusy := true
ToggleEarner()
ToggleEarner()
gEarnBusy := false
EarnModeTick()
Check(gEarnOn && gEarnMode = "full" && gEarnModeRequest = "", "second F9 before the boundary cancels the pending off")
Reset()
gEarnIdleEnabled := false
gEarnRecovery := {task:{id:"bunker",label:"bunker"},mct:true,nextTick:fakeTick+30000}
ToggleEarner()
Check(gEarnOn && gEarnIdleEnabled && IsObject(gEarnRecovery) && gEarnModeRequest = "apps", "F9 off during MCT recovery keeps recovery and Vinewood apps")
for appId in ["safe", "staff"] {
    for explicitOffset in [-1000, 49*60000] {
        Reset()
        fixedTask := {id:appId,label:appId,every:300000}
        gEarnDone[appId] := 0
        gEarnNextDue[appId] := fakeTick + explicitOffset
        fixedResult := {task:fixedTask,startTick:fakeTick-120000,ok:true}
        EarnFinishScheduledTask(fixedResult)
        Check(gEarnDue[appId] = fakeTick+300000 && !gEarnNextDue.Has(appId), "fixed app interval ignores past or predicted explicit schedule: " appId)
    }
    Reset()
    fixedTask := {id:appId,label:appId,every:420000}
    gEarnDone[appId] := 0
    EarnFinishScheduledTask({task:fixedTask,startTick:fakeTick-900000,ok:true})
    Check(gEarnDue[appId] = fakeTick+420000, "long app execution still waits configured interval from completion: " appId)
    Reset()
    fixedTask := {id:appId,label:appId,every:300000}
    EarnFinishScheduledTask({task:fixedTask,startTick:fakeTick-1000,ok:false,reason:"read failure",retryIn:90000})
    Check(gEarnDue[appId] = fakeTick+90000, "app failure retains explicit retry instead of success interval: " appId)
    Reset()
    fixedTask := {id:appId,label:appId,every:300000}
    state["pending_" appId] := "unconfirmed request"
    EarnFinishScheduledTask({task:fixedTask,startTick:fakeTick-1000,ok:false,reason:"pending",retryIn:90000})
    if (appId = "staff")
        Check(!gEarnHeld.Has(appId) && gEarnDue[appId] = fakeTick+90000, "pending staff dispatch retries instead of holding")
    else
        Check(gEarnHeld.Has(appId) && gEarnFailures[appId].nextTick = 0, "pending app remains held without repeat scheduling: " appId)
}
FileAppend("PASS Earner: " checkCount " cases; no game input`n", "*")
if (hudDepth != 0 || hudTakes != 0 || hudReturns != 0)
    throw Error("Scheduler must not acquire task-wide HUD hiding")
ExitApp(0)

DiscordHUDVisibilityAcquire() {
    global hudDepth, hudTakes, fakeTick, idleMs, focused
    if (hudInject = "throw")
        throw Error("HUD hide failed")
    hudDepth += 1, hudTakes += 1
    if (hudInject = "physical")
        fakeTick += 200, idleMs := 0
    if (hudInject = "focus")
        focused := false
}
DiscordHUDMCTSet(open) {
    if (open)
        throw Error("Scheduler may restore confirmed free HUD, but never hide a whole task")
    return true
}
DiscordHUDMCTStop() {
    global hudStopCount, hudStopReleaseCount
    hudStopCount += 1, hudStopReleaseCount := releaseCount
}
DiscordHUDVisibilityRelease() {
    global hudDepth, hudReturns
    if (hudDepth != 1)
        throw Error("Unexpected HUD scope release")
    hudDepth -= 1, hudReturns += 1
}
AFKSelfInput(start) {
    global selfMarks
    selfMarks .= start ? "S" : "E"
}
Reset() {
    global
    gEarnMode := "full", gEarnModeRequest := "", gEarnIdleEnabled := false
    hudInject := ""
    selfMarks := ""
    fakeTick := 100000, idleMs := 60000, gEarnGuardArmed := false, gEarnGuardStartedTick := 0, gEarnUserAbort := false
    gEarnInputAbortReason := "", metadataFailure := false, metadataCalls := 0
    timers := [], fakePID := 101, gEarnGamePID := 101
    beginCount := 0, endCount := 0, beginCleanupCount := 0, beginOK := true, endOK := true, endNoScreen := false,
        beginThrows := false, endThrows := false, mctOpen := false, events := [], logs := [],
        taskModes := Map(), taskDurations := Map(), beginDelay := 0, endDelay := 0, endInput := false
    lockAvailable := true, lockCalls := 0, lockReleases := 0, lockHeld := false, hooks := 0
    gEarnOn := true, gEarnBusy := false, gEarnCurrent := "", gEarnFail := "", gEarnRetryIn := 0, gAbort := false, afkOn := false
    gEarnManualStop := false, gEarnManualCleanupActive := false, gEarnManualCleanupAttempted := false
    gEarnTaskActive := false, gEarnAFKCleanup := false, gEarnMCTCleanupOK := true, stopStatus := ""
    beginStopInjected := false
    gEarnSellNotices := Map(), tooltips := []
    endStopMode := "", bossOffCount := 0, bossProbeOK := true, bossProbeCount := 0, bossProbeStrictCount := 0, bossProbeGuardedCount := 0
    bossProbeMode := "", bossStopInjected := false, bossInitialGuardTick := 0, bossRetryBaselineOK := false, bossRetryCleanupStateOK := false
    staleFailInjected := false, blockedRestartObserved := false
    recoveryHud := true, recoveryHudAfter := true, recoveryMenuCloseOK := true, visibleModal := ""
    gEarnCleanupNoScreen := false
    lifecycleTrace := false, lifecycleEvents := [], finalizerProbeStages := []
    gEarnDue := Map("bunker", A_TickCount - 1, "dj", A_TickCount - 1)
    gEarnHeld := Map(), gEarnFailures := Map(), gEarnRecovery := "", appCloseOK := true, appCloseCount := 0, state := Map(), stateWritable := true
    gEarnDone := Map("bunker", 0, "dj", 0), gEarnNextDue := Map(), gEarnSoftFails := Map()
    gEarnTasks := [{id:"bunker", label:"bunker", on:true, every:300000, fn:RunTask.Bind("bunker")}, {id:"dj", label:"dj", on:true, every:300000, fn:RunTask.Bind("dj")}]
    config := Map("Settings", Map("EarnUserIdleSec", 2, "EarnSoftFailMax", 1, "EarnMCTOnly",1,
        "EarnSafe",1,"EarnSafeIntervalMin",5,"EarnSafeFirstMin",0,"EarnBunker",1,"EarnBunkerIntervalSec",6720,
        "EarnDJ",1,"EarnDJIntervalMin",5,"EarnDispatch",0,"EarnDispatchIntervalMin",48,"EarnDispatchFirstMin",0),
        "Features", Map("AntiAFK", 0))
    GTA_WIN := "fake", calls := [], releaseCount := 0, stopped := 0, mode := "ok", windowExists := true, focused := true, otherBusy := false, activationCount := 0
}
RunTask(id, manageSession := true) {
    global calls, mode, gEarnNextDue, gEarnRetryIn, idleMs, focused, fakePID, fakeTick
    if (!lockHeld || !gEarnBusy || !gEarnGuardArmed || hudDepth != 0)
        throw Error("Every body must share the live input lock and guard")
    if (EarnIsMCTTask(id) ? manageSession || !mctOpen : mctOpen)
        throw Error("MCT bodies require the shared session; apps require it closed")
    if (gEarnMode = "apps" && id = "safe" && manageSession)
        throw Error("Idle safe must disable MCT management")
    calls.Push(id)
    events.Push(id)
    taskMode := taskModes.Get(id,mode)
    if (taskMode = "physical-ocr" || taskMode = "focus-ocr" || taskMode = "both-ocr") {
        fakeTick += 100
        idleMs := taskMode = "focus-ocr" ? idleMs + 100 : 0
        focused := taskMode = "physical-ocr"
        EarnInputWatch()
        return EarnFail("화면 판독 중단 또는 시간 초과")
    }
    duration := taskDurations.Get(id,0)
    fakeTick += duration, idleMs += duration
    if (taskMode = "manual-stop-app") {
        SetEarner(false, "", "manual")
        return EarnFail("화면 판독 중단 또는 시간 초과")
    }
    if (taskMode = "stock-full") {
        EarnNotifyStockFull("nightclub", "나이트클럽 창고 만재 3개: 판매 필요")
        return true
    }
    if (taskMode = "long-readonly") {
        fakeTick += 30000
        idleMs += 30000
        EarnInputWatch()
        return true
    }
    if (taskMode = "long-physical") {
        fakeTick += 10000
        idleMs := 5000
        EarnInputWatch()
        return true
    }
    if (taskMode = "pid") {
        fakePID++
        EarnInputWatch()
        return true
    }
    if (taskMode = "physical-pending")
        state["pending_" id] := "sent before user intervention"
    if (taskMode = "physical" || taskMode = "idle-zero" || taskMode = "physical-pending") {
        idleMs := 0
        fakeTick++
        EarnInputWatch()
        gEarnRetryIn := 60000
        return true
    }
    if (taskMode = "focus") {
        focused := false
        EarnInputWatch()
        return true
    }
    if (taskMode = "override")
        gEarnNextDue[id] := A_TickCount + 300000
    if (taskMode = "override-short")
        gEarnNextDue[id] := fakeTick + 60000
    if (taskMode = "retry") {
        gEarnRetryIn := 60000
        return false
    }
    if (taskMode = "fail")
        return EarnFail("expected failure")
    if (taskMode = "ambiguous") {
        state["pending_" id] := "request sent"
        return EarnFail("거래 결과 미확인, 재구매 금지")
    }
    if (taskMode = "throw")
        throw Error("test exception")
    if (taskMode = "reenter")
        EarnTick()
    return true
}
Check(ok, name) {
    global checkCount
    checkCount++
    if (!ok) {
        FileAppend("FAIL " name "`n", "*")
        ExitApp(1)
    }
}
HasItem(items, expected) {
    for item in items
        if (item = expected)
            return true
    return false
}
JobWarpArmedText() => ""
BotWarpStatusText() => ""
WinExist(*) => windowExists
WinGetPID(selector) {
    if (selector = "ahk_id 777") {
        if (metadataFailure)
            throw Error("fixture window vanished")
        return 707
    }
    return fakePID
}
WinGetProcessName(selector) {
    if (metadataFailure)
        throw Error("fixture process unavailable")
    return selector = "ahk_id 777" ? "fixture.exe" : "GTA5_Enhanced.exe"
}
WinGetTitle(selector) {
    if (metadataFailure)
        throw Error("fixture title unavailable")
    return selector = "ahk_id 777" ? "Fixture window" : "Grand Theft Auto V"
}
FakeForegroundWindow() {
    global metadataCalls
    if (!releaseCount)
        throw Error("diagnostic metadata must follow immediate key release")
    metadataCalls++
    return focused ? 1 : 777
}
InputEvidenceCount() {
    count := 0
    for message in logs
        count += InStr(message, "[input-abort]") = 1 ? 1 : 0
    return count
}
IsGTAActive() => focused
EarnOtherMacroBusy() => otherBusy
BringGTAToFront() {
    global activationCount
    activationCount++
    return false
}
ReleaseHeldKeys() {
    global releaseCount
    releaseCount++
}
EarnFail(reason) {
    global gEarnFail
    gEarnFail := reason
    return false
}
SetAntiAFK(*) {
    throw Error("unexpected AFK call")
}
SetTimer(fn, period) {
    global timers, stopped, lifecycleTrace, lifecycleEvents, modeTimer
    if (fn.Name = "EarnModeTick") {
        modeTimer := period
        return
    }
    if (lifecycleTrace && fn.Name = "EarnInputWatch")
        lifecycleEvents.Push(period = 0 ? "guard-stop" : "guard-start")
    timers.Push(period)
    if (fn.Name = "EarnTick" && period = 0)
        stopped++
}
EarnInputLockAcquire(*) {
    global lockCalls, lockHeld, lifecycleTrace, lifecycleEvents
    lockCalls++
    if (mode = "lock-error")
        throw Error("test lock failure")
    if (!lockAvailable)
        return 0
    if (lockHeld)
        throw Error("input lock was not released")
    lockHeld := true
    if (lifecycleTrace)
        lifecycleEvents.Push("lock-acquire")
    return {macro:1,gui:2}
}
EarnInputLockRelease(*) {
    global lockHeld, lockReleases, lifecycleTrace, lifecycleEvents
    if (!lockHeld)
        throw Error("released input lock without ownership")
    lockHeld := false
    lockReleases++
    if (lifecycleTrace)
        lifecycleEvents.Push("lock-release")
}
InstallKeybdHook(*) {
    global hooks
    hooks++
}
InstallMouseHook(*) {
    global hooks
    hooks++
}
KeyLabelFor(*) => "F9"
EarnVinewoodSafeTask(manageMCT := true) => RunTask("safe", manageMCT)
EarnBunkerTask(manageSession := true) => RunTask("bunker",manageSession)
EarnDJTask(manageSession := true) => RunTask("dj",manageSession)
EarnWarehouseTask(manageSession := true) => RunTask("warehouse",manageSession)
EarnVinewoodStaffTask() => RunTask("staff")
EarnBossOffIfOn(requireConfirmed := false) {
    global bossProbeOK, bossProbeCount, bossProbeStrictCount, bossProbeGuardedCount, bossProbeMode, bossStopInjected, bossInitialGuardTick, bossRetryBaselineOK, bossRetryCleanupStateOK, lifecycleTrace, lifecycleEvents, fakeTick, idleMs
    bossProbeCount++
    bossProbeStrictCount += requireConfirmed ? 1 : 0
    bossProbeGuardedCount += lockHeld && gEarnGuardArmed ? 1 : 0
    if (lifecycleTrace)
        lifecycleEvents.Push(requireConfirmed ? "boss-strict" : "boss-probe")
    if (bossProbeMode = "manual-retry-success" || bossProbeMode = "manual-retry-fail") {
        if (!bossStopInjected) {
            bossStopInjected := true
            bossInitialGuardTick := gEarnGuardStartedTick
            fakeTick += 10, idleMs := 0
            SetEarner(false, "", "manual")
            return false
        }
        bossRetryBaselineOK := gEarnGuardStartedTick = fakeTick - idleMs
            && gEarnGuardStartedTick > bossInitialGuardTick
        bossRetryCleanupStateOK := gEarnManualCleanupActive && gEarnManualCleanupAttempted
            && !gAbort && !gEarnUserAbort
        return bossProbeMode = "manual-retry-success"
    }
    return bossProbeOK
}
EarnStateGet(key, default := "") => state.Get(key, default)
EarnStateSet(key, value) {
    if (stateWritable)
        state[key] := value
}
EarnVinewoodClose() {
    global appCloseCount
    if (!lockHeld || !gEarnGuardArmed)
        throw Error("App recovery requires guarded input lock")
    appCloseCount++
    return appCloseOK
}
EarnDispatchTask() => RunTask("dispatch")
EarnAtMCT() {
    global mode, beginStopInjected, idleMs, mctOpen
    if (mode = "begin-initial-manual" && !beginStopInjected) {
        beginStopInjected := true
        idleMs := 0
        SetEarner(false, "", "manual")
        return false
    }
    return mctOpen
}
EarnSeen(name, *) => name = visibleModal
EarnMCTRecoveryHud() => bossOffCount > 0 ? recoveryHudAfter : recoveryHud
EarnMenuClose() => recoveryMenuCloseOK
EarnSleep(*) => !gAbort
EarnAborted() => gAbort || !gEarnOn
EarnMCTSpotSweep() => false
EarnMCTOpen() {
    throw Error("Initial OCR stop must not open MCT")
}
EarnMCTRefresh() {
    throw Error("Initial OCR stop must not refresh MCT")
}
EarnSoftFail(reason, retryMin) {
    global gEarnRetryIn
    gEarnRetryIn := retryMin * 60000
    return EarnFail(reason)
}
EarnTaskMCTBegin() {
    global beginCount, beginCleanupCount, mctOpen, fakeTick, idleMs
    if (!lockHeld || !gEarnGuardArmed || mctOpen)
        throw Error("Group begin requires one guarded lock and no open session")
    beginCount++, events.Push("begin")
    fakeTick += beginDelay, idleMs += beginDelay
    if (!beginOK || beginThrows) {
        beginCleanupCount++
        if (beginThrows)
            throw Error("begin exception")
        return EarnFail("begin failed")
    }
    mctOpen := true
    return true
}
EarnTaskMCTEnd() {
    global endCount, mctOpen, fakeTick, idleMs, endNoScreen, endStopMode, stopStatus, staleFailInjected, blockedRestartObserved, gEarnFail
    if ((!lockHeld && !gEarnAFKCleanup) || !gEarnGuardArmed || (!mctOpen && visibleModal = ""))
        throw Error("Group end must retain its single input lock and guard")
    endCount++, events.Push("end")
    fakeTick += endDelay, idleMs += endDelay
    if (gEarnManualCleanupActive)
        EarnInputWatch()
    if (endStopMode != "" && endCount = 1) {
        if (endStopMode = "afk-manual") {
            idleMs := 0
            SetEarner(false, "", "manual")
            stopStatus := EarnStatusText()
            fakeTick++
            EarnInputWatch()
            if (gAbort)
                return false
        } else if (endStopMode = "manual" || endStopMode = "manual-user") {
            idleMs := 0
            SetEarner(false, "", "manual")
            stopStatus := EarnStatusText()
            ToggleEarner()
            SetEarner(true)
            blockedRestartObserved := !gEarnOn
            staleFailInjected := true
            return EarnFail("화면 판독 중단 또는 시간 초과")
        } else {
            SetEarner(false, endStopMode)
            return false
        }
    }
    if (endStopMode = "manual-user" && endCount = 2) {
        idleMs := 0
        fakeTick++
        EarnInputWatch()
        return false
    }
    if (endInput) {
        idleMs := 0
        EarnInputWatch()
    }
    if (endThrows)
        throw Error("end exception")
    if (!endOK || gAbort) {
        global gEarnCleanupNoScreen
        gEarnCleanupNoScreen := endNoScreen
        return EarnFail("end failed")
    }
    mctOpen := false
    return EarnCEO(false)
}
TimerPeriodCount(period) {
    global timers
    count := 0
    for value in timers
        count += value = period ? 1 : 0
    return count
}
EarnCEO(on) {
    global bossOffCount
    if (on || (!lockHeld && !gEarnAFKCleanup) || !gEarnGuardArmed)
        throw Error("CEO retirement must remain inside the guarded input lock")
    bossOffCount++
    if (endNoScreen)
        return EarnBossOffIfOn(true)
    return true
}
FocusWaitLogCount() {
    global logs
    count := 0
    for message in logs
        count += InStr(message, "GTA 포커스가 돌아오면 다시") ? 1 : 0
    return count
}
HasLog(fragment) {
    global logs
    for message in logs
        if (InStr(message, fragment))
            return true
    return false
}
EarnLog(message) {
    if (mode = "finalizer-race" && InStr(message, "끄기 정리 실패:") = 1)
        EarnFinalizerStateProbe("log")
    logs.Push(message)
    if (SubStr(message,1,3) = "끝: " && mctOpen && !endNoScreen)
        throw Error("Completion log cannot precede MCT cleanup")
}
ShowTooltip(message, *) {
    global tooltips
    tooltips.Push(message)
    if (mode = "finalizer-race" && InStr(message, "수익 자동화 꺼짐:") > 0)
        EarnFinalizerStateProbe("tooltip")
}
EarnFinalizerAbortClearedProbe() {
    if (mode = "finalizer-race")
        EarnFinalizerStateProbe("abort-cleared")
}
EarnFinalizerStateProbe(stage) {
    global finalizerProbeStages
    finalizerProbeStages.Push({stage: stage,
        latched: gEarnManualStop && gEarnManualCleanupAttempted,
        abort: gAbort, userAbort: gEarnUserAbort, critical: A_IsCritical})
}
'@
$driver = $driver.Replace('@MCT_PROMPT_LINES@', $mctPromptLiteral)
$driver = $driver.Replace('A_TickCount', 'fakeTick')
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
    $p = [Diagnostics.Process]::Start($info)
    try {
        $p.StandardInput.WriteLine($driver + "`n" + $production)
        $p.StandardInput.Close()
        if (-not $p.WaitForExit(10000)) { $p.Kill(); throw 'Scheduler test timed out' }
        $stdout = $p.StandardOutput.ReadToEnd().Trim()
        $stderr = $p.StandardError.ReadToEnd().Trim()
        if ($p.ExitCode -ne 0 -or $stderr -or $stdout -ne 'PASS Earner: 224 cases; no game input') {
            throw "exit=$($p.ExitCode) stdout=$stdout stderr=$stderr"
        }
        $stdout
    } finally { $p.Dispose() }
} finally { [Console]::InputEncoding = $previous }

# Use unique Windows object names. These checks never open the live GTA input locks.
$lockFunctions = @('EarnInputLockAcquire', 'EarnInputLockRelease') | ForEach-Object {
    $body = [regex]::Match($source, ('(?ms)^' + $_ + '\([^\r\n]*\) \{.*?^\}')).Value
    if (-not $body) { throw "Production lock function missing: $_" }
    $body
}
function Invoke-EarnerMutexCheck {
    param([string]$Driver, [string]$Expected)
    $previousMutexEncoding = [Console]::InputEncoding
    [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $AhkPath
    $info.Arguments = '/ErrorStdOut /CP65001 *'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($info)
    try {
        $p.StandardInput.WriteLine("#Requires AutoHotkey v2.0`n#SingleInstance Off`n#NoTrayIcon`n#Warn All, StdOut`n" +
            $Driver + "`n" + ($lockFunctions -join "`n"))
        $p.StandardInput.Close()
        if (-not $p.WaitForExit(10000)) {
            $p.Kill()
            $p.WaitForExit()
            throw 'Input mutex check timed out'
        }
        $stdout = $p.StandardOutput.ReadToEnd().Trim()
        $stderr = $p.StandardError.ReadToEnd().Trim()
        if ($p.ExitCode -ne 0 -or $stderr -or $stdout -cne $Expected) {
            throw "Input mutex check failed: exit=$($p.ExitCode) stdout=$stdout stderr=$stderr"
        }
        $stdout
    } finally {
        if (-not $p.HasExited) { $p.Kill(); $p.WaitForExit() }
        $p.Dispose()
        [Console]::InputEncoding = $previousMutexEncoding
    }
}
$mutexPrefix = 'Local\GtaEarnerOffline-' + [guid]::NewGuid().ToString('N')
$macroName = $mutexPrefix + '-macro'
$guiName = $mutexPrefix + '-gui'
$mutexDriver = @'
macroName := "@MACRO@", guiName := "@GUI@"
held := EarnInputLockAcquire(macroName, guiName)
if (!IsObject(held))
    throw Error("free input locks must be acquired")
if (EarnInputLockAcquire(macroName, guiName) != 0)
    throw Error("GUI name reservation must prevent another task")
for name in [macroName,guiName] {
    probe := DllCall("OpenMutexW", "uint", 0x100000, "int", 0, "str", name, "ptr")
    if (!probe)
        throw Error("both names must exist while task holds locks")
    DllCall("CloseHandle", "ptr", probe)
}
EarnInputLockRelease(held)
for name in [macroName,guiName] {
    probe := DllCall("OpenMutexW", "uint", 0x100000, "int", 0, "str", name, "ptr")
    if (probe)
        throw Error("released input lock handle leaked")
}
held := EarnInputLockAcquire(macroName, guiName)
if (!IsObject(held))
    throw Error("next task must reacquire released locks")
EarnInputLockRelease(held)
FileAppend("PASS EarnerMutex free: 5 cases; no game input`n", "*")
ExitApp(0)
'@
Invoke-EarnerMutexCheck ($mutexDriver.Replace('@MACRO@', $macroName).Replace('@GUI@', $guiName)) 'PASS EarnerMutex free: 5 cases; no game input'

# The PowerShell host owns this mutex; AHK is another process and cannot recursively acquire it.
$ownedMutex = New-Object Threading.Mutex($false, $macroName)
$owned = $ownedMutex.WaitOne(0)
if (-not $owned) { $ownedMutex.Dispose(); throw 'Unique test mutex was unexpectedly occupied' }
try {
    $blockedDriver = @'
if (EarnInputLockAcquire("@MACRO@", "@GUI@") != 0)
    throw Error("another process owns the macro mutex")
probe := DllCall("OpenMutexW", "uint", 0x100000, "int", 0, "str", "@GUI@", "ptr")
if (probe)
    throw Error("waiting task must close its temporary GUI reservation")
FileAppend("PASS EarnerMutex busy: 2 cases; no game input`n", "*")
ExitApp(0)
'@
    Invoke-EarnerMutexCheck ($blockedDriver.Replace('@MACRO@', $macroName).Replace('@GUI@', $guiName)) 'PASS EarnerMutex busy: 2 cases; no game input'
} finally {
    $ownedMutex.ReleaseMutex()
    $ownedMutex.Dispose()
}
$existingGui = New-Object Threading.Mutex($false, $guiName)
try {
    $guiDriver = @'
if (EarnInputLockAcquire("@MACRO@", "@GUI@") != 0)
    throw Error("existing GUI receiver must block task entry")
probe := DllCall("OpenMutexW", "uint", 0x100000, "int", 0, "str", "@MACRO@", "ptr")
if (probe)
    throw Error("waiting for GUI must not create or retain a macro mutex")
FileAppend("PASS EarnerMutex GUI: 2 cases; no game input`n", "*")
ExitApp(0)
'@
    Invoke-EarnerMutexCheck ($guiDriver.Replace('@MACRO@', $macroName).Replace('@GUI@', $guiName)) 'PASS EarnerMutex GUI: 2 cases; no game input'
} finally { $existingGui.Dispose() }

# Production persistence uses a unique offline directory, never the live GTA state file.
$stateSupport = @('EarnStateGet','EarnStateSet','EarnTransactionBegin','EarnTransactionConfirmed') | ForEach-Object {
    $body = [regex]::Match($core, ('(?ms)^' + $_ + '\([^\r\n]*\) \{.*?^\}')).Value
    if (-not $body) { throw "Production state function missing: $_" }
    $body.Replace('A_Temp', 'stateDirectory')
}
$stateDriver = @'
stateDirectory := A_Temp "\GtaEarnerStateOffline-@ID@"
EarnFail(*) => false
if (EarnTransactionBegin("staff", "unconfirmed"))
    throw Error("Missing state directory must prevent transaction")
DirCreate(stateDirectory)
if (!EarnTransactionBegin("staff", "unconfirmed"))
    throw Error("Persistent pending write must succeed")
if (EarnStateGet("pending_staff") != "unconfirmed")
    throw Error("A fresh read must retain the pending transaction")
EarnStateSet("unrelated", "preserved")
EarnTransactionConfirmed("staff")
if (EarnStateGet("pending_staff") != "")
    throw Error("Confirmed result must clear persistent pending")
if (EarnStateGet("unrelated") != "preserved")
    throw Error("Pending update must preserve unrelated state")
FileAppend("PASS EarnerState persistence: 5 cases; no game input`n", "*")
ExitApp(0)
'@
Invoke-EarnerMutexCheck ($stateDriver.Replace('@ID@', [guid]::NewGuid().ToString('N')) + "`n" + ($stateSupport -join "`n")) 'PASS EarnerState persistence: 5 cases; no game input'

# Run the real hotkey dispatcher with key waits and timers replaced, never register/send a key.
$hotkeySource = Get-Content (Join-Path $PSScriptRoot '..\..\Core\HotkeyManager.ahk') -Raw -Encoding UTF8
$hotkeyFunctions = @('Dispatch','ExpireArmedAction','IgnoredEarnerKey','HotkeyAudit') | ForEach-Object {
    $body = [regex]::Match($hotkeySource, ('(?ms)^' + $_ + '\([^\r\n]*\) \{.*?^\}')).Value
    if (-not $body) { throw "Production hotkey function missing: $_" }
    $body.Replace('A_TickCount','fakeTick').Replace('KeyWait(','AuditKeyWait(').Replace('GetKeyState(','AuditKeyState(').Replace('SetTimer(','AuditTimer(').Replace('WinGetProcessName(','AuditForeground(')
}
$hotkeyDriver = @'
OnError((failure, *) => (FileAppend("FAIL hotkey: " failure.Message "`n", "**"), ExitApp(1)))
global gArmed := Map(), config := Map("Settings", Map("ConfirmWindowMs", 2000))
global fakeTick := 100, logs := [], scheduled := [], calls := 0, held := false, failAction := false, failLog := false
action := {id:"Earner", confirm:true, label:"earn", fn:RunAction}
Dispatch(action, "F9")
Require(calls = 0 && HasEvent("received") && HasEvent("confirmation-wait"), "first press logged without action")
fakeTick := 500
Dispatch(action, "F9")
Require(calls = 1 && HasEvent("confirmed") && HasEvent("action-start") && HasEvent("action-return"), "confirmation and return logged")
scheduled[1].Call()
Require(!HasEvent("confirmation-expired"), "consumed confirmation cannot expire")
fakeTick := 3000
Dispatch(action, "F9")
fakeTick := 5100
scheduled[2].Call()
Require(!gArmed.Has("Earner") && HasEvent("confirmation-expired"), "unused confirmation expires and logs")
Dispatch(action, "F9")
held := true
fakeTick := 8000
Dispatch(action, "F9")
Require(!gArmed.Has("Earner") && HasEvent("confirmation-cancelled"), "held key cancellation logged")
held := false
gArmed["Earner"] := 8000
IgnoredEarnerKey(action, "F9")
Require(!gArmed.Has("Earner") && HasEvent("ignored"), "outside GTA clears confirmation and logs")
gArmed["Earner"] := fakeTick
failAction := true
caught := false
try Dispatch(action, "F9")
catch {
    caught := true
}
Require(caught && HasEvent("action-error"), "action exception logged and propagated")
failAction := false
failLog := true
gArmed["Earner"] := fakeTick
Dispatch(action, "F9")
Require(calls = 3, "log write failure cannot block action")
FileAppend("PASS Hotkey audit: 8 cases; no game input`n", "*")
ExitApp(0)
RunAction(*) {
    global calls, failAction
    calls += 1
    if (failAction)
        throw Error("fixture action error")
}
MacroLog(tag, text) {
    global logs, failLog
    if (failLog)
        throw Error("fixture log write error")
    logs.Push(text)
}
HasEvent(event) {
    global logs
    for row in logs
        if (InStr(row, "event=" event))
            return true
    return false
}
Require(value, label) {
    if (!value)
        throw Error(label)
}
AuditTimer(callback, *) {
    global scheduled
    scheduled.Push(callback)
}
AuditKeyWait(*) => 0
AuditKeyState(*) {
    global held
    return held
}
AuditForeground(*) => "fixture.exe"
ShowTooltip(*) => 0
'@
Invoke-EarnerMutexCheck ($hotkeyDriver + "`n" + ($hotkeyFunctions -join "`n")) 'PASS Hotkey audit: 8 cases; no game input'

# Real AHK timer priorities, but only in-memory input/window state. The low-priority
# visibility timer cannot interrupt a normal macro thread; the actual 25ms guard must restore.
$timingSource = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\Earner.ahk') -Raw -Encoding UTF8
$timingGuards = foreach ($name in @('EarnInputGuardStart','EarnInputGuardStop','EarnInputWatch','EarnInputAllowed')) {
    $body = [regex]::Match($timingSource, ('(?ms)^' + $name + '\([^\r\n]*\) \{.*?^\}')).Value
    if (-not $body) { throw "HUD timing guard missing: $name" }
    $body.Replace('A_TimeIdlePhysical', 'testIdleMs').Replace('DllCall("GetForegroundWindow", "ptr")', '1')
}
$hudSource = Get-Content (Join-Path $PSScriptRoot '..\..\Features\DiscordHUD.ahk') -Raw -Encoding UTF8
$timingHUD = $hudSource.Substring($hudSource.IndexOf('global gDiscordHUDMCTOpen'))
foreach ($name in @('DiscordHUDWindowList','DiscordHUDWindowRead','DiscordHUDWindowVisible')) {
    $timingHUD = [regex]::Replace($timingHUD, ('(?ms)^' + $name + '\([^\r\n]*\) \{.*?^\}\s*'), '')
}
if ($timingHUD -match 'DllCall\(|WinGet|ShowWindow|WinActivate|\bRun\(') { throw 'Native side effect remains in HUD timing fixture' }
$hudTimingDriver = @'
OnError((failure, *) => (FileAppend("FAIL HUD guard timing: " failure.Message "`n", "**"), ExitApp(1)))
global gEarnMode := "full"
EarnOtherMacroBusy() => false
global gEarnBusy := true, gEarnGuardArmed := false, gEarnGuardStartedTick := 0, gAbort := false
global gEarnRetryIn := 0, gEarnGamePID := 101, gEarnUserAbort := false, gEarnInputAbortReason := ""
global testIdleMs := 60000, focused := true, visible := true, released := false, inputInjected := false
global lowTicks := 0, restoredAfterRelease := false, phase := ""
SetTimer(NormalMacroWork, -1)
return
NormalMacroWork() {
    global gAbort, gEarnUserAbort, testIdleMs, focused, visible, released, inputInjected, lowTicks, restoredAfterRelease, phase
    for scenario in ["physical", "focus"] {
        phase := scenario, gAbort := false, gEarnUserAbort := false, testIdleMs := 60000, focused := true
        released := false, inputInjected := false, restoredAfterRelease := false, lowTicks := 0
        EarnInputGuardStart()
        DiscordHUDMCTSet(true)
        if (visible)
            throw Error("guarded macro did not hide HUD")
        SetTimer(LowVisibilityTick, 25, -10)
        SetTimer(InjectLogicalInput, -75)
        Sleep(350)
        if (!inputInjected || !gAbort || !visible || !restoredAfterRelease || lowTicks != 0)
            throw Error(scenario " did not restore inside normal-priority work after key release")
        SetTimer(LowVisibilityTick, 0)
        EarnInputGuardStop()
    }
    gAbort := false, gEarnUserAbort := false, testIdleMs := 60000, focused := true
    EarnInputGuardStart()
    DiscordHUDMCTSet(true)
    EarnInputGuardStop()
    if (!visible || gEarnGuardArmed)
        throw Error("guard stop did not synchronously restore HUD")
    FileAppend("PASS HUD guard timing: 3 cases; no window or game input`n", "*")
    ExitApp(0)
}
InjectLogicalInput() {
    global testIdleMs, focused, inputInjected
    inputInjected := true
    if (phase = "physical")
        testIdleMs := 0
    else
        focused := false
}
LowVisibilityTick() {
    global lowTicks
    lowTicks += 1
    DiscordHUDVisibilityTick()
}
DiscordHUDWindowList() => [1]
DiscordHUDWindowRead(hwnd) => {hwnd: 1, pid: 123, created: 12345, title: "DiscordChatHUD C#", visible: visible, minimized: false}
DiscordHUDWindowVisible(hwnd, show) {
    global visible, restoredAfterRelease
    visible := show
    if (show && inputInjected)
        restoredAfterRelease := released
    return true
}
ReleaseHeldKeys() {
    global released
    released := true
}
EarnGamePID() => 101
IsGTAActive() => focused
ProcessExist(*) => true
EarnFail(*) => false
EarnInputAbortEvidence(*) => 0
MacroLog(*) => 0
'@
Invoke-EarnerMutexCheck ($timingHUD + "`n" + $hudTimingDriver + "`n" + ($timingGuards -join "`n")) `
    'PASS HUD guard timing: 3 cases; no window or game input'

# Real timer preemption at the startup activation boundary, without input.
$modeTick = [regex]::Match($source, '(?ms)^EarnModeTick\(\) \{.*?^\}').Value
$modeRaceDriver = @'
OnError((failure, *) => (FileAppend("FAIL idle mode race: " failure.Message "`n", "**"), ExitApp(1)))
global gEarnModeRequest := "apps", gEarnMode := "apps", gEarnOn := false, gEarnBusy := false
global gEarnManualStop := false, gEarnRecovery := "", gEarnIdleEnabled := true, starts := 0, endRan := false
SetTimer(EndProbe, -10)
EarnModeTick()
Sleep(100)
if (!endRan || gEarnOn || gEarnIdleEnabled || gEarnModeRequest != "" || starts != 1)
    throw Error("End must run after critical activation and leave scheduler off")
gEarnModeRequest := "apps"
EarnModeTick()
if (starts != 1 || gEarnOn)
    throw Error("stale request after End must not activate")
FileAppend("PASS idle mode race: 2 cases; no game input`n", "*")
ExitApp(0)
EndProbe() {
    global gEarnOn, gEarnIdleEnabled, gEarnModeRequest, endRan
    gEarnOn := false, gEarnIdleEnabled := false, gEarnModeRequest := "", endRan := true
}
SetEarner(*) {
    global starts, gEarnOn
    starts++
    Sleep(60)
    gEarnOn := true
}
EarnGamePID() => 101
EarnOtherMacroBusy() => false
EarnLog(*) => 0
'@
Invoke-EarnerMutexCheck ($modeRaceDriver + "`n" + $modeTick) 'PASS idle mode race: 2 cases; no game input'
