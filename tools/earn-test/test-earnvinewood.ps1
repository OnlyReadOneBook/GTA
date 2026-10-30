#Requires -Version 5.1
<#
Runs the real Vinewood flow and text-selection/parser helpers against a fake menu.
No game input, screen capture, window activation, or Main.ahk execution.
#>
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$production = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnVinewood.ahk') -Raw -Encoding UTF8
$screen = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnScreen.ahk') -Raw -Encoding UTF8
$commonScreen = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Core\Screen.ahk') -Raw -Encoding UTF8
foreach ($helper in @('HealthHudVisible', 'HealthHudColors')) {
    $match = [regex]::Match($commonScreen, ('(?ms)^' + $helper + '\([^\r\n]*\) \{.*?^\}'))
    if (-not $match.Success) { throw "Missing common HUD helper: $helper" }
    $production += "`n" + $match.Value
}
foreach ($functionName in @('EarnFindText', 'EarnReadDollars', 'EarnSelectText', 'EarnMenuStepKey')) {
    $match = [regex]::Matches($screen, ('(?ms)^' + $functionName + '\([^\r\n]*\) \{.*?^\}'))
    if ($match.Count -ne 1) { throw "Expected exactly one screen helper: $functionName" }
    $production += "`n" + $match[0].Value
}
# 빈 화면 시작의 물리 유휴는 시험 값으로 바꾼다(A_TimeIdlePhysical 은 이 프로세스의 실제 값이다).
$idleNeedle = 'A_TimeIdlePhysical < idleMs'
if (([regex]::Matches($production, [regex]::Escape($idleNeedle))).Count -ne 1) { throw "Expected one free-HUD idle check" }
$production = $production.Replace($idleNeedle, 'gPhysIdle < idleMs')
$deadlineNeedle = 'deadline := A_TickCount + Max(0, timeoutMs)'
$remainingNeedle = 'remainingMs := deadline - A_TickCount'
if (([regex]::Matches($production, [regex]::Escape($deadlineNeedle))).Count -ne 1 -or
    ([regex]::Matches($production, [regex]::Escape($remainingNeedle))).Count -ne 1) {
    throw "Expected the free-HUD wait to use one wall-clock deadline"
}
$production = $production.Replace($deadlineNeedle, 'deadline := gNowMs + Max(0, timeoutMs)')
$production = $production.Replace($remainingNeedle, 'remainingMs := deadline - gNowMs')
# Every production wall-clock read uses the same fake clock. OCR and key latency
# advance it too, so a deadline cannot silently turn into a sleep-only budget.
$production = [regex]::Replace($production, '\bA_TickCount\b', 'gNowMs')
if (-not (Test-Path -LiteralPath $AhkPath -PathType Leaf)) { throw "AutoHotkey executable not found: $AhkPath" }
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global transactionPending := Map()
EarnTransactionBegin(id, reason) {
    transactionPending[id] := reason
    return true
}
EarnTransactionConfirmed(id) {
    global gConfirmCalls
    gConfirmCalls += 1
    transactionPending.Delete(id)
}
EarnTransactionCashConfirmed(id, direction, amount, source, evidence, path := "") {
    global gCashMovements, gCashFail
    if (gCashFail)
        return false
    gCashMovements.Push({id:id, direction:direction, amount:amount, source:source, evidence:evidence})
    EarnTransactionConfirmed(id)
    return true
}
global gMode, gState, gSelected, gBiz, gIdx, gReads, gClaims, gClaimAttempts, gKeys, gStandWaits, gMctCloses, gCEOCalls, gFailure, gScheduled, gPhoneFrameVisible, gTests := 0
global gNowMs := 0, gSleepMs := 0, gTimedReads := 0
global gClaimPlan := 0, gClaimAt := -1, gClaimReads := [], gAbort := false, gConfirmCalls := 0, gCashMovements := [], gCashFail := false
global gEarnRetryIn := 0, gEarnOn := false, gEarnBusy := false, gEarnDue := Map(), gEarnNextDue := Map(), gGlitch := Map()
global config := Map("Settings", Map("EarnUserIdleSec", 45)), gPhysIdle := 600000, gOthersIdle := 600000
IsGTAActive() => false
EarnAborted() => gAbort
RunClaimTimingTests()
RunTests()
FileAppend("PASS EarnVinewood cases=" gTests Chr(10), "*", "UTF-8")
ExitApp(0)

; 기본 목록은 1004 00:24 실측 순서와 금액이다(Car Wash 는 빈 금고).
DefaultBiz() => [["Nightclub",150000], ["Arcade",10000], ["Agency",80000], ["Salvage Yard",6300],
    ["Bail Office",12800], ["Garment Factory",35720], ["Hands On Car Wash",0]]

; The live response was absent at +2s and present by +35s. Deterministic
; delayed frames reproduce the old 15-second rejection without live input.
RunClaimTimingTests() {
    global gNowMs, gClaimAt, gClaimReads, gAbort, gClaimAttempts, gKeys, gConfirmCalls, transactionPending, gCashMovements, gCashFail
    for delay in [35000, 16000, 0] {
        ClaimReset(Map("delay", delay))
        ok := EarnVinewoodClaim("Nightclub", 250000)
        elapsed := gNowMs - gClaimAt
        Check(ok, "claim response at " delay "ms succeeds; elapsed=" elapsed "ms")
        Check(gCashMovements.Length = 1 && gCashMovements[1].direction = "income"
            && gCashMovements[1].amount = 250000 && gCashMovements[1].source = "Nightclub",
            "confirmed safe claim records exact income")
        ClaimSafety(true, "claim response at " delay "ms")
        Check(elapsed >= Max(1000, delay) && elapsed < Max(1500, delay + 500), "delayed claim completes promptly after its result")
    }
    ClaimReset(Map("delay", 0))
    gCashFail := true
    Check(!EarnVinewoodClaim("Nightclub", 250000), "ledger write failure rejects the confirmed claim result")
    ClaimSafety(false, "ledger write failure")
    Check(!gCashMovements.Length, "failed ledger write is not counted as recorded income")
    gCashFail := false
    for plan in [Map("delay", 120000), Map("delay", 120000, "keyCost", 9000),
        Map("delay", 120000, "readCost", 14000), Map("delay", 120000, "missingUntil", 120000)] {
        ClaimReset(plan)
        Check(!EarnVinewoodClaim("Nightclub", 250000), "unconfirmed claim stops at the shared deadline")
        ClaimSafety(false, "unconfirmed claim")
        Check(gNowMs - gClaimAt = 60000, "60-second budget includes key, initial wait, OCR, and retry waits")
    }
    for missing in ["false", "unknown"] {
        ClaimReset(Map("delay", 35000, "missingUntil", 6000, "missingKind", missing))
        Check(EarnVinewoodClaim("Nightclub", 250000), "temporary " missing " OCR recovers without another claim")
        ClaimSafety(true, "temporary OCR")
        Check(gNowMs - gClaimAt >= 35000 && gNowMs - gClaimAt < 35500, "temporary OCR does not restart the response clock")
    }
    ; An intentionally non-cooperative OCR stub returns a correct empty frame
    ; after the deadline. The caller must reject it and never launch a reread.
    ClaimReset(Map("delay", 0, "readCost", 61000, "honorDeadline", false))
    Check(!EarnVinewoodClaim("Nightclub", 250000), "late empty OCR result is rejected")
    ClaimSafety(false, "late empty OCR")
    Check(gClaimReads.Length = 1, "deadline overrun launches no further OCR")
    ClaimReset(Map("delay", 0, "abortBeforeRead", true))
    Check(!EarnVinewoodClaim("Nightclub", 250000), "cancellation before result OCR stops verification")
    ClaimSafety(false, "cancel before OCR")
    Check(gClaimReads.Length = 0, "cancellation before OCR launches no read")
    ClaimReset(Map("delay", 0, "abortAfterRead", true))
    Check(!EarnVinewoodClaim("Nightclub", 250000), "cancellation during OCR rejects the empty result")
    ClaimSafety(false, "cancel after OCR")
    Check(gClaimReads.Length = 1, "cancellation after OCR launches no further read")
    for badDetail in [false, true] {
        ClaimReset(Map("delay", 0, "otherSafe", "Arcade", "badDetail", badDetail))
        Check(!EarnVinewoodClaim("Nightclub", 250000), "another selected safe never confirms this transaction")
        ClaimSafety(false, "different selected business")
        Check(gClaimReads.Length = 1, "different selected business fails immediately even if its amount is unreadable")
    }
    ClaimReset(Map("delay", 0))
    gAbort := true
    Check(!EarnVinewoodClaim("Nightclub", 250000) && gClaimAttempts = 0 && !gKeys.Length
        && !transactionPending.Has("safe") && !gConfirmCalls, "pre-request cancellation sends no transaction")

    ; Direct helper boundaries also cover calls that are not inside Claim.
    readSelected := EarnVinewoodReadSelected
    ClaimReset(Map("delay", 0))
    gClaimAt := gNowMs
    name := "stale", amount := 0
    Check(!readSelected(&name, &amount, gNowMs, "Nightclub")
        && name = "" && amount = -1 && !gClaimReads.Length, "expired ReadSelected launches no OCR and clears old outputs")
    ClaimReset(Map("delay", 0, "readCost", 60001, "honorDeadline", false))
    gClaimAt := gNowMs
    Check(!readSelected(&name, &amount, gNowMs + 60000, "Nightclub")
        && name = "" && amount = -1 && gClaimReads.Length = 1, "ReadSelected rejects late data before selection parsing")
    ClaimReset(Map("delay", 0, "abortAfterRead", true))
    gClaimAt := gNowMs
    Check(!readSelected(&name, &amount, gNowMs + 60000, "Nightclub")
        && name = "" && amount = -1 && gClaimReads.Length = 1, "ReadSelected rejects canceled data before selection parsing")
}

ClaimReset(plan) {
    global gClaimPlan, gNowMs
    Reset("claim_timing", "earnings", Map("Nightclub", 250000))
    gClaimPlan := plan, gNowMs := 1000
}

ClaimSafety(confirmed, label) {
    global gClaimAt, gClaimReads, gClaimAttempts, gKeys, gConfirmCalls, transactionPending
    Check(gClaimAttempts = 1 && gKeys.Length = 1 && gKeys[1] = "Enter", label " sends exactly one Enter and no navigation")
    Check(gConfirmCalls = (confirmed ? 1 : 0) && transactionPending.Has("safe") = !confirmed,
        label " only confirmed success clears the pending transaction")
    if (!confirmed)
        Check(transactionPending["safe"] = "Nightclub $250000 수거 요청 결과 확인 필요", label " preserves the exact pending reason")
    for read in gClaimReads {
        Check(read.deadline = gClaimAt + 60000, label " passes the same absolute deadline to OCR")
        Check(read.started < read.deadline, label " never starts OCR at or after the deadline")
    }
}

ClaimFrame(deadlineTick) {
    global gClaimPlan, gClaimAt, gClaimReads, gNowMs, gSelected, gAbort
    if (gClaimAt < 0) {
        gSelected := "Nightclub"
        return Frame("Claim $250000 from your Nightclub safe.")
    }
    gClaimReads.Push({started: gNowMs, deadline: deadlineTick})
    cost := gClaimPlan.Get("readCost", 50)
    gNowMs += cost
    if (deadlineTick && gClaimPlan.Get("honorDeadline", true) && gNowMs >= deadlineTick) {
        gNowMs := deadlineTick
        return false
    }
    if (gClaimPlan.Get("abortAfterRead", false))
        gAbort := true
    elapsed := gNowMs - gClaimAt
    if (elapsed < gClaimPlan.Get("missingUntil", 0)) {
        if (gClaimPlan.Get("missingKind", "false") = "false")
            return false
        gSelected := ""
        return [FakeLine("THE VINEWOOD CLUB APP"), FakeLine("Unknown status")]
    }
    name := gClaimPlan.Get("otherSafe", "Nightclub"), gSelected := name
    if (gClaimPlan.Get("badDetail", false))
        return [FakeLine("THE VINEWOOD CLUB APP"), FakeLine(name), FakeLine("Unreadable amount")]
    detail := elapsed >= gClaimPlan.Get("delay", 0)
        ? "Your " name " safe is empty." : "Claim $250000 from your " name " safe."
    return [FakeLine("THE VINEWOOD CLUB APP"), FakeLine(name), FakeLine(detail)]
}

RunTests() {
    global gClaims, gClaimAttempts, gKeys, gState, gMctCloses, gCEOCalls, gScheduled, gBiz, gIdx, gSelected, gPhysIdle, gOthersIdle
    global gNowMs, gSleepMs, gTimedReads
    ; mode, starting screen, amounts to override, success, claimed names, final screen, scheduled minutes (0 = not checked)
    cases := [
        ["normal", "main", Map(), true, "", "standing", 88],
        ["empty_row_missing", "main", Map(), true, "", "standing", 88],
        ["empty_row_missing", "main", Map("Nightclub",0), true, "", "standing", 136],
        ["empty_row_missing", "main", Map("Nightclub",250000), true, "Nightclub", "standing", 136],
        ["normal", "main", Map("Nightclub",250000), true, "Nightclub", "standing", 136],
        ["normal", "main", Map("Nightclub",205000,"Arcade",96000,"Agency",235000,"Garment Factory",99000), true,
            "Nightclub,Arcade,Agency,Garment Factory", "standing", 136],
        ["normal", "main", Map("Arcade",95000), true, "", "standing", 40],
        ["normal", "main", Map("Arcade",95001), true, "Arcade", "standing", 88],
        ["normal", "main", Map("Hands On Car Wash",100000), true, "Hands On Car Wash", "standing", 88],
        ["normal", "main", Map("Hands On Car Wash",1), true, "Hands On Car Wash", "standing", 0],
        ["normal", "main", Map("Hands On Car Wash",100001), true, "", "standing", 0],
        ["empty_row_missing", "main", Map("Hands On Car Wash",100000), true, "Hands On Car Wash", "standing", 0],
        ["normal", "main", Map("Salvage Yard",76001,"Bail Office",80001), true, "Salvage Yard,Bail Office", "standing", 88],
        ["unknown_business", "main", Map(), true, "", "standing", 40],
        ["unreadable_agency", "main", Map(), true, "", "standing", 40],
        ["no_earnings", "main", Map(), true, "", "standing", 184],
        ["normal", "earnings_mid", Map("Nightclub",250000), true, "Nightclub", "standing", 136],
        ["recheck_amount", "main", Map("Nightclub",240000), false, "", "earnings", 0],
        ["cancel_claim", "main", Map("Nightclub",240000), false, "", "earnings", 0],
        ["post_unconfirmed", "main", Map("Nightclub",240000), false, "Nightclub", "earnings", 0],
        ["select_cancel", "main", Map(), false, "", "earnings", 0],
        ["no_selection", "main", Map(), false, "", "earnings", 0],
        ["close_unknown", "main", Map(), true, "", "unknown", 0],
        ["prompt_delay", "main", Map(), true, "", "standing", 0],
        ["normal", "standing", Map("Nightclub",250000), true, "Nightclub", "standing", 0],
        ["normal", "mct", Map("Nightclub",250000), true, "Nightclub", "standing", 0],
        ["normal", "phone_job", Map("Nightclub",250000), true, "Nightclub", "standing", 0],
        ["normal", "phone_internet", Map("Nightclub",250000), true, "Nightclub", "standing", 0],
        ["normal", "phone_vinewood", Map("Nightclub",250000), true, "Nightclub", "standing", 0],
        ["phone_texts", "hud", Map("Nightclub",250000), true, "Nightclub", "standing", 0],
        ["phone_texts_hdr", "hud", Map("Nightclub",250000), true, "Nightclub", "standing", 0],
        ["phone_texts_hdr", "phone_texts", Map("Nightclub",250000), true, "Nightclub", "standing", 0],
        ["phone_texts_internet", "hud", Map("Nightclub",250000), true, "Nightclub", "standing", 0],
        ["open_unreadable", "standing", Map(), false, "", "standing", 0],
        ["open_unreadable", "phone_job", Map(), false, "", "phone_job", 0],
        ["normal", "unknown", Map(), false, "", "unknown", 0],
        ["normal", "hud", Map("Nightclub",250000), true, "Nightclub", "standing", 0],
        ["wrong_phone", "standing", Map(), false, "", "wrong_phone", 0]
    ]
    for c in cases {
        Reset(c[1], c[2], c[3])
        result := EarnVinewoodSafeTask()
        claimed := ""
        for name in gClaims
            claimed .= (claimed = "" ? "" : ",") name
        label := c[1] "/" c[2] "/" claimed
        Check(result = c[4] && claimed = c[5] && gState = c[6], label " result=" result " claims=" claimed " state=" gState)
        if (c[7])
            Check(gScheduled = 0, label " leaves interval ownership to scheduler")
        Check(gClaimAttempts <= gClaims.Length + 1, label " never replays collection")
        if (c[1] = "post_unconfirmed" && !transactionPending.Has("safe"))
            throw Error("Unconfirmed collection must retain pending state")
        if (result && gClaims.Length && transactionPending.Has("safe"))
            throw Error("Confirmed collection must clear pending state")
        for key in gKeys
            Check(key != "Esc", label " never sends Esc")
        if (c[2] = "hud")
            Check(gMctCloses = 0 && gCEOCalls = 0, "free HUD start leaves CEO/MC state alone")
        if (c[2] = "mct")
            Check(gMctCloses = 1 && gCEOCalls = 1, "MCT start closes terminal before phone")
        if (c[2] = "phone_job" || c[2] = "phone_vinewood") {
            Check(gMctCloses = 0 && gCEOCalls = 0, "open phone does not repeat MCT or CEO setup")
            for key in gKeys
                Check(key != "Up", "open phone never sends the phone-opening Up key again")
        }
        if (c[2] = "phone_internet")
            Check(gKeys.Length >= 3 && gKeys[1] = "Up" && gKeys[2] = "Right" && gKeys[3] = "Enter",
                "already-open Internet home moves up to verified Job List without reopening the phone")
        if (c[1] = "phone_texts")
            Check(gKeys.Length >= 4 && gKeys[1] = "Up" && gKeys[2] = "Down"
                && gKeys[3] = "Right" && gKeys[4] = "Enter",
                "recorded Texts home is verified, moved to Job List, then opened")
        if (c[1] = "phone_texts_hdr")
            if (c[2] = "phone_texts")
                Check(gKeys.Length >= 3 && gKeys[1] = "Down" && gKeys[2] = "Right" && gKeys[3] = "Enter",
                    "already-open HDR Texts home is recognized without pressing Up again")
            else
                Check(gKeys.Length >= 4 && gKeys[1] = "Up" && gKeys[2] = "Down"
                    && gKeys[3] = "Right" && gKeys[4] = "Enter",
                    "Texts OCR recovers the phone home when the HDR frame template is absent")
        if (c[1] = "phone_texts_internet")
            Check(gKeys.Length >= 5 && gKeys[1] = "Up" && gKeys[2] = "Down" && gKeys[3] = "Up"
                && gKeys[4] = "Right" && gKeys[5] = "Enter",
                "Internet after Down is corrected to verified Job List before opening Vinewood")
        if (c[1] = "open_unreadable" || c[2] = "unknown")
            Check(gKeys.Length = 0, "unknown opening screen sends no keys")
        if (c[1] = "no_earnings")
            Check(gClaimAttempts = 0 && gKeys.Length = 1 && gKeys[1] = "Backspace", "global empty skips entering business list")
        if (result && c[1] != "no_earnings") {
            downs := 0
            for key in gKeys
                downs += key = "Down"
            Check(downs = gBiz.Length + ((c[1] = "phone_texts" || c[1] = "phone_texts_hdr" || c[1] = "phone_texts_internet") ? 1 : 0),
                label " visits every row once and stops on wrap (downs=" downs ")")
        }
    }
    for idleStart in ["hud", "standing", "mct_transition"] {
        Reset(idleStart = "mct_transition" ? "mct_ready_delay" : "normal", idleStart, Map("Nightclub",250000))
        Check(EarnVinewoodSafeTask(false), "idle safe completes at " idleStart)
        Check(gMctCloses = 0 && gCEOCalls = 0, "idle safe preserves MCT and boss at " idleStart)
    }
    Reset("close_stuck", "main")
    Check(!EarnVinewoodClose() && gKeys.Length = 4, "stuck app closing is bounded at four Backspaces")
    Reset("normal", "phone_vinewood")
    Check(EarnVinewoodClose() && gState = "standing", "phone home is closed before reporting success")
    Reset("normal", "pause_menu")
    RetryIn(999)
    Check(!EarnVinewoodOpen() && gKeys.Length = 0 && RetryIn() = 0 && InStr(gFailure, "HUD"),
        "away from MCT retries immediately without input")
    for idle in [[1000, 600000, "physical"], [600000, 1000, "remote"]] {
        Reset("normal", "hud")
        RetryIn(999)
        gPhysIdle := idle[1], gOthersIdle := idle[2]
        Check(!EarnVinewoodOpen() && gKeys.Length = 0 && RetryIn() = 0,
            "free HUD waits while recent " idle[3] " input exists")
        Check(!EarnVinewoodOpen(false) && gKeys.Length = 0, "staff preserves " idle[3] " input guard")
    }
    Reset("hud_menu", "hud")
    Check(!EarnVinewoodOpen() && gKeys.Length = 0, "free HUD with an open menu sends no keys")
    Check(!EarnVinewoodOpen(false) && gKeys.Length = 0, "staff also blocks an open menu")
    for color in [0x4C8F4C, 0x9BFF9F, 0xA5FFAC, 0xACFFB2, 0x000000, 0xFFFFFF, 0xFF3333, 0x3399FF] {
        samples := []
        Loop 16
            samples.Push(color)
        Check(EarnVinewoodHealthColors(samples) = (color = 0x4C8F4C || color = 0x9BFF9F || color = 0xA5FFAC || color = 0xACFFB2),
            "health bar accepts recorded normal/bright green and rejects other colors " color)
    }
    Check(!EarnVinewoodHealthColors([0x9BFF9F]), "one green pixel is not a health bar")
    sparse := []
    Loop 16
        sparse.Push(A_Index <= 11 ? 0xA5FFAC : 0xFFFFFF)
    Check(!EarnVinewoodHealthColors(sparse), "eleven HDR green samples do not establish the health bar")
    sparse[12] := 0xA5FFAC
    Check(EarnVinewoodHealthColors(sparse), "twelve HDR green samples establish the health bar")
    ; 1030 실측 체력 약 70%: 밝은 칸 22개 뒤에 깎인 어두운 칸 9개, 끝 1개는 막대 밖.
    hurt := []
    for c in [0x4D8F4B,0x4D8F4B,0x4D904B,0x4D904C,0x4A8C49,0x4B914F,0x4A904F,0x4A904F,0x4A9150,0x4B9150,0x4B914F,0x4B9150,0x4B9150,0x4B914F,0x4B914F,0x4B9150,
        0x4C9250,0x4C9250,0x4C9250,0x4B9250,0x4B914F,0x4B9150,0x24562D,0x24572E,0x24562D,0x24562E,0x24562D,0x24562C,0x24582E,0x24572E,0x245830,0x0F1A25]
        hurt.Push(c)
    Check(EarnVinewoodHealthColors(hurt), "health bar with lost health (dark green tail) is still the HUD")
    empty := []
    Loop 16
        empty.Push(0x24562D)
    Check(!EarnVinewoodHealthColors(empty), "dark green alone is not a health bar")
    Reset("normal", "hud")
    Check(EarnVinewoodOpen() && gState = "main" && gKeys[1] = "Up" && gCEOCalls = 0, "free HUD opens the phone without CEO setup")
    Reset("normal", "hud")
    Check(EarnVinewoodOpen(false) && gState = "main" && gMctCloses = 0 && gCEOCalls = 0,
        "staff opens away from MCT without terminal or boss operations")
    ; CEO/menu cleanup can finish one frame before the confirmed MCT standing
    ; prompt returns. Staff must wait without input, then accept that prompt as a
    ; normal free-HUD anchor even when the health bar itself is not detected.
    Reset("mct_ready_delay", "mct_transition")
    Check(EarnVinewoodOpen(false) && gState = "main" && gStandWaits >= 1
        && gKeys.Length = 3 && gKeys[1] = "Up" && gKeys[2] = "Right" && gKeys[3] = "Enter"
        && gMctCloses = 0 && gCEOCalls = 0,
        "staff waits for the delayed MCT standing prompt before opening the app")
    Reset("mct_ready_delay", "mct_transition")
    Check(EarnVinewoodOpen() && gState = "main" && gStandWaits >= 1
        && gKeys.Length = 3 && gKeys[1] = "Up" && gKeys[2] = "Right" && gKeys[3] = "Enter"
        && gMctCloses = 0 && gCEOCalls = 1,
        "safe reclassifies the delayed MCT standing prompt and retires CEO before opening the app")
    Reset("mct_ready_once", "mct_transition")
    Check(EarnVinewoodOpen() && gState = "main" && gStandWaits >= 1
        && gKeys.Length = 3 && gKeys[1] = "Up" && gKeys[2] = "Right" && gKeys[3] = "Enter"
        && gMctCloses = 0 && gCEOCalls = 1,
        "safe preserves a one-frame MCT standing result and retires CEO without rereading it")
    Reset("wait_deadline", "timed_wait")
    timedMCT := true
    Check(!EarnVinewoodWaitFreeHud(450, &timedMCT) && !timedMCT
        && gTimedReads = 2 && gSleepMs = 200 && gNowMs = 460,
        "free-HUD wait counts OCR time against one wall-clock deadline")
    Reset("normal", "standing")
    Check(EarnVinewoodFreeHud(), "MCT standing prompt is a free-HUD anchor without a health bar")
    gOthersIdle := 1000
    Check(EarnVinewoodFreeHud(), "MCT standing prompt permits recent injected input")
    gOthersIdle := 600000, gPhysIdle := 1000
    Check(!EarnVinewoodFreeHud(), "MCT standing prompt still rejects recent physical input")
    Reset("hud_menu", "standing")
    Check(!EarnVinewoodFreeHud(), "MCT standing prompt does not override an open interaction menu")
    Reset("mct_phone", "standing")
    Check(!EarnVinewoodFreeHud(), "MCT standing prompt does not override an open phone")
    Reset("normal", "phone_job")
    Check(EarnVinewoodOpen() && gState = "main" && gKeys.Length = 2
        && gKeys[1] = "Right" && gKeys[2] = "Enter", "Job List home only moves right and opens the selected app")
    Reset("right_stuck", "phone_job")
    RetryIn(999)
    Check(!EarnVinewoodOpen() && gState = "standing" && gKeys.Length = 2 && gKeys[2] = "Backspace" && RetryIn() = 0,
        "unconfirmed Vinewood selection closes the phone and retries immediately")
    Reset("normal", "phone_vinewood")
    Check(EarnVinewoodOpen() && gState = "main" && gKeys.Length = 1
        && gKeys[1] = "Enter", "selected Vinewood home opens directly without changing phone selection")
    ; 휴대폰 무반응은 Up 을 보낸 뒤 전화가 안 뜬 연속 횟수로 센다. 앱이 열리면 0 으로 돌아간다(재접속 판정은 Earner).
    gGlitch.Clear()
    Loop 2 {
        Reset("phone_dead", "hud")
        Check(!EarnVinewoodOpen() && gState = "hud" && gKeys.Length = 1 && gKeys[1] = "Up" && InStr(gFailure, "전화 홈 화면 미확인"),
            "dead phone fails after one Up without further keys (" A_Index ")")
    }
    Check(gGlitch["phone"] = 2, "dead phone counts consecutive unanswered Ups")
    Reset("right_stuck", "phone_job")
    EarnVinewoodOpen()
    Check(gGlitch["phone"] = 3, "unconfirmed Vinewood selection also counts as phone unresponsive")
    Reset("normal", "hud")
    Check(EarnVinewoodOpen() && gGlitch["phone"] = 0, "opened Vinewood app resets the phone unresponsive count")
    Reset("normal", "pause_menu")
    EarnVinewoodOpen()
    Check(gGlitch["phone"] = 0, "waiting for a free HUD sends nothing and is not counted as unresponsive")

    Reset("normal", "earnings")
    Check(EarnVinewoodNightclubAmount(Frame("Claim $250,000 from your Nightclub safe.")) = 250000, "comma-formatted detail amount")
    Check(EarnVinewoodNightclubAmount(Frame("Claim $250000 from your Nightclub safe.")) = 250000, "plain detail amount")
    Check(EarnVinewoodNightclubAmount(Frame("Claim $50000 from ydÜr Nightclub safe.")) = 50000, "garbled your still reads amount")
    Check(EarnVinewoodNightclubAmount(Frame("Claim $150000 fromyour Nightclub safe.")) = 150000, "your glued to from still reads amount")
    gSelected := ": Nightclub"
    Check(EarnVinewoodNightclubAmount([FakeLine("THE VINEWOOD CLUB APP"), FakeLine(": Nightclub"), FakeLine("Claim $100000 from your Nightclub safe.")]) = 100000, "leading colon on selected Nightclub row")
    gSelected := "Garment Factory"
    wrapped := [FakeLine("THE VINEWOOD CLUB APP"), FakeLine("Garment Factory"), FakeLine("Claim $35720 from your Garment Factory"), FakeLine("safe.")]
    Check(EarnVinewoodSelectedSafe(wrapped) = "Garment Factory" && EarnVinewoodSafeAmountOf(wrapped, "Garment Factory") = 35720, "footer wrapped onto two lines")
    Check(EarnVinewoodSafeAmountOf(wrapped, "Nightclub") = -1, "another business footer is not this safe's amount")
    gSelected := "Nightclub"
    Check(EarnVinewoodNightclubAmount(Frame("Your Nightclub safe is empty.")) = 0, "explicit nightclub empty detail")
    Check(EarnVinewoodNightclubAmount(Frame("Your Nightclub safe is empty")) = 0, "empty detail read without its period (1006 06:51)")
    Check(EarnVinewoodNightclubAmount(Frame("Your Nightclub safe is empty now")) = -1, "empty detail with trailing words is rejected")
    for text in ["Claim $250000 from your Arcade safe.", "Your Arcade safe is empty.", "Nightclub $250000", "Claim $25O000 from your Nightclub safe.", "Claim $250,00 from your Nightclub safe.", "Claim $250 000 from your Nightclub safe.", "Claim $250000 from your Nightclub safe. Confirm?", "Claim $250000 from Nightclub safe.", "Claim $250000 from your Arcade Nightclub safe"]
        Check(EarnVinewoodNightclubAmount(Frame(text)) = -1, "reject detail: " text)
    Check(EarnVinewoodNightclubAmount(false) = -1, "OCR failure is not an empty safe")
    gSelected := ""
    for name in ["Nightclub", "Hands On Car Wash"] {
        empty := [FakeLine("THE VINEWOOD CLUB APP"), FakeLine("Your " name " safe is empty.")]
        Check(EarnVinewoodSelectedSafe(empty) = name, "missing gray label uses exact empty footer: " name)
        Check(EarnVinewoodSafeAmountOf(empty, name) = 0, "footer fallback is empty only")
    }
    for details in [["Claim $250000 from your Nightclub safe."],
        ["Your Nightclub safe is empty.", "Your Arcade safe is empty."],
        ["Your Nightclub safe is empty.", "Your Nightclub safe is empty."],
        ["Your Nightclub safe is empty.", "Claim $100 from your Arcade safe."],
        ["Your Unknown Shop safe is empty."], ["Your Nightclub safe is empty now"]] {
        missingRows := [FakeLine("THE VINEWOOD CLUB APP")]
        for detail in details
            missingRows.Push(FakeLine(detail))
        Check(EarnVinewoodSelectedSafe(missingRows) = "", "ambiguous or nonempty footer cannot identify missing row")
    }
    Check(EarnVinewoodSelectedSafe([FakeLine("Your Nightclub safe is empty.")]) = "", "empty footer requires app title")
    gSelected := "Arcade"
    Check(EarnVinewoodSelectedSafe(Frame("Your Nightclub safe is empty.")) = "Arcade",
        "visible selected row takes precedence over another safe footer")
}

Reset(mode, state, amounts := "") {
    global transactionPending := Map()
    global gMode, gState, gSelected, gBiz, gIdx, gReads, gClaims, gClaimAttempts, gKeys, gStandWaits, gMctCloses, gCEOCalls, gFailure, gScheduled, gPhysIdle, gOthersIdle, gPhoneFrameVisible
    global gNowMs, gSleepMs, gTimedReads
    global gClaimPlan, gClaimAt, gClaimReads, gAbort, gConfirmCalls
    global gCashMovements, gCashFail
    gClaimPlan := 0, gClaimAt := -1, gClaimReads := [], gAbort := false, gConfirmCalls := 0, gCashMovements := []
    gCashFail := false
    gMode := mode, gState := state = "earnings_mid" ? "earnings" : state, gBiz := DefaultBiz(), gIdx := state = "earnings_mid" ? 4 : 1
    gPhoneFrameVisible := mode != "phone_texts_hdr"
    if (mode = "unknown_business")
        gBiz.InsertAt(3, ["Weed Shop", 50000])
    if (IsObject(amounts))
        for name, amount in amounts
            for biz in gBiz
                if (biz[1] = name)
                    biz[2] := amount
    gSelected := gState = "earnings" ? gBiz[gIdx][1] : "Claim Business Earnings"
    gReads := Map(), gClaims := [], gClaimAttempts := 0, gKeys := [], gStandWaits := 0, gMctCloses := 0, gCEOCalls := 0, gFailure := "", gScheduled := 0, gPhysIdle := 600000, gOthersIdle := 600000
    gNowMs := 0, gSleepMs := 0, gTimedReads := 0
}

EarnReadScreen(area, whiteText := false, deadlineTick := 0) {
    global gMode, gState, gSelected, gBiz, gIdx, gReads
    if (IsObject(gClaimPlan))
        return ClaimFrame(deadlineTick)
    if (gMode = "open_unreadable")
        return false
    if (gState = "phone_texts")
        return [FakeLine("Texts")]
    if (gState = "phone_internet")
        return [FakeLine("Internet")]
    if (gState = "phone_job")
        return [FakeLine("Job List")]
    if (gState = "main") {
        lines := [FakeLine("THE VINEWOOD CLUB APP"), FakeLine("Claim Business Earnings"), FakeLine("Purchase Ammo")]
        if (gMode = "no_earnings")
            lines.Push(FakeLine("No earnings to claim."))
        return lines
    }
    if (gState != "earnings")
        return []
    biz := gBiz[gIdx], name := biz[1], amount := biz[2]
    gSelected := gMode = "no_selection" ? "" : name
    gReads[name] := (gReads.Has(name) ? gReads[name] : 0) + 1
    lines := [FakeLine("THE VINEWOOD CLUB APP")]
    for row in gBiz
        lines.Push(FakeLine(row[1]))
    if (gMode = "empty_row_missing" && amount = 0) {
        gSelected := ""
        lines := [FakeLine("THE VINEWOOD CLUB APP")]
    }
    if (gMode = "unreadable_agency" && name = "Agency") {
        lines.Push(FakeLine("Claim $8O000 from your Agency safe."))
        return lines
    }
    if (gMode = "recheck_amount" && gReads[name] >= 2)
        amount += 1000
    if (amount = 0) {
        lines.Push(FakeLine("Your " name " safe is empty."))
    } else if (name = "Garment Factory") {
        lines.Push(FakeLine("Claim $" amount " from your Garment Factory"), FakeLine("safe."))
    } else {
        lines.Push(FakeLine("Claim $" amount " from your " name " safe."))
    }
    return lines
}

Frame(detail) {
    return [FakeLine("THE VINEWOOD CLUB APP"), FakeLine("Nightclub"), FakeLine("Arcade"), FakeLine(detail)]
}
FakeLine(text) {
    return {text: text, x: 40, y: 180, w: 350, h: 22}
}
EarnMenuRowSelected(row) {
    global gSelected
    return gSelected != "" && row.text = gSelected
}
EarnPress(key) {
    global gMode, gState, gSelected, gBiz, gIdx, gClaims, gClaimAttempts, gKeys
    global gClaimAt, gNowMs
    gKeys.Push(key)
    if (key = "Down") {
        if (gMode = "select_cancel")
            return false
        if (gState = "phone_texts")
            gState := gMode = "phone_texts_internet" ? "phone_internet" : "phone_job"
        else if (gState = "earnings")
            gIdx := Mod(gIdx, gBiz.Length) + 1, gSelected := gBiz[gIdx][1]
    } else if (key = "Up") {
        if (gState = "phone_internet")
            gState := "phone_job"
        else if (gState != "standing" && gState != "hud")
            throw Error("Phone-opening Up is invalid when the phone is already open: " gState)
        else if (gMode = "phone_dead")
            gState := gState   ; 게임 문제로 Up 이 안 먹는다(1010 07:59~08:18 「전화 홈 화면 미확인」 10회)
        else
            gState := gMode = "wrong_phone" ? "wrong_phone" : (gMode = "phone_texts" || gMode = "phone_texts_hdr" || gMode = "phone_texts_internet") ? "phone_texts" : "phone_job"
    } else if (key = "Right" && gState = "phone_job") {
        gState := gMode = "right_stuck" ? "phone_other" : "phone_vinewood"
    } else if (key = "Backspace" && gState = "phone_other") {
        gState := "standing"
    } else if (key = "Enter") {
        if (gState = "phone_vinewood") {
            gState := "main", gSelected := "Claim Business Earnings"
        } else if (gState = "main" && gSelected = "Claim Business Earnings") {
            gState := "earnings", gIdx := 1, gSelected := gBiz[1][1]
        } else if (gState = "earnings") {
            gClaimAttempts += 1
            if (gMode = "cancel_claim")
                return false
            biz := gBiz[gIdx]
            limits := EarnSafeLimits().Has(biz[1]) ? EarnSafeLimits()[biz[1]] : ""
            if (!IsObject(limits) || biz[2] + limits[2] <= limits[1])
                throw Error("Attempted collection from a safe that is not due: " biz[1] " $" biz[2])
            gClaims.Push(biz[1])
            if (IsObject(gClaimPlan)) {
                gClaimAt := gNowMs
                gNowMs += gClaimPlan.Get("keyCost", 0)
            } else if (gMode != "post_unconfirmed")
                biz[2] := 0
        } else {
            throw Error("Unexpected Enter state: " gState)
        }
    } else if (key = "Backspace") {
        if (gMode = "close_stuck")
            return true
        if (gState = "earnings")
            gState := "main", gSelected := "Claim Business Earnings"
        else if (gState = "main" || gState = "phone_vinewood" || gState = "phone_job")
            gState := gMode = "close_unknown" ? "unknown" : gMode = "prompt_delay" ? "waiting_prompt" : "standing"
    }
    return true
}
EarnSleep(ms) {
    global gMode, gState, gClaims, gStandWaits, gNowMs, gSleepMs
    global gAbort
    gNowMs += ms, gSleepMs += ms
    if (IsObject(gClaimPlan) && gClaimAt >= 0 && gClaimPlan.Get("abortBeforeRead", false))
        gAbort := true
    if (gState = "mct_transition")
        gStandWaits += 1, gState := gMode = "mct_ready_once" ? "standing_once" : "standing"
    if (gClaims.Length && ms = 300 && gMode = "post_unconfirmed")
        return false
    if (gState = "waiting_prompt" && ms = 300 && ++gStandWaits >= 2)
        gState := "standing"
    return true
}
EarnSeen(name, *) {
    global gState, gMode, gNowMs, gTimedReads
    if (name = "m_title")
        return gMode = "hud_menu"
    if (name = "afk_phone_frame")
        return gPhoneFrameVisible && (gState = "phone_texts" || gState = "phone_internet" || gState = "phone_job"
            || gMode = "mct_phone" && gState = "standing")
    if (name = "mct_sit") {
        if (gMode = "wait_deadline") {
            gNowMs += 130, gTimedReads += 1
            return false
        }
        if (gMode = "mct_ready_once" && gState = "standing_once") {
            gState := "hud"
            return true
        }
        return gState = "standing"
    }
    return name = "ph_joblist_sel" ? gState = "phone_job" : name = "ph_vinewood_sel" && gState = "phone_vinewood"
}
EarnWaitSeen(name, *) => EarnSeen(name)
EarnHudVisible() {
    global gState
    return gState = "hud"
}
AFKOthersIdleMs() {
    global gOthersIdle
    return gOthersIdle
}
RetryIn(value := "") {
    global gEarnRetryIn
    if (value != "")
        gEarnRetryIn := value
    return gEarnRetryIn
}
EarnAtMCT() {
    global gState
    return gState = "mct"
}
EarnMCTClose() {
    global gState, gMctCloses
    gMctCloses += 1, gState := "standing"
    return true
}
EarnCEO(*) {
    global gCEOCalls
    gCEOCalls += 1
    return true
}
EarnFail(message) {
    global gFailure
    gFailure := message
    return false
}
; 실제 EarnGlitchNote(EarnCore)처럼 연속 횟수를 센다. 휴대폰 무반응 재접속 판정(Earner)이 이 값을 본다.
EarnGlitchNote(kind, failed) {
    global gGlitch
    gGlitch[kind] := failed ? gGlitch.Get(kind, 0) + 1 : 0
    return failed
}
EarnScheduleNext(id, ms) {
    global gScheduled
    if (id != "safe")
        throw Error("Unexpected schedule id " id)
    gScheduled := ms
    return true
}
EarnLog(*) {
}
Check(ok, name) {
    global gTests
    gTests += 1
    if (!ok) {
        FileAppend("FAIL " name Chr(10), "*", "UTF-8")
        ExitApp(1)
    }
}
'@

$testPath = Join-Path ([IO.Path]::GetTempPath()) ('gta-earn-vinewood-' + [Guid]::NewGuid().ToString('N') + '.ahk')
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $AhkPath
$info.Arguments = '/ErrorStdOut /CP65001 "' + $testPath + '"'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
$info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
$testProcess = $null
try {
    [IO.File]::WriteAllText($testPath, $driver + "`n" + $production + "`n", (New-Object Text.UTF8Encoding($true)))
    $testProcess = [Diagnostics.Process]::Start($info)
    if (-not $testProcess.WaitForExit(10000)) {
        $testProcess.Kill()
        $testProcess.WaitForExit()
        throw 'EarnVinewood check timed out after 10 seconds'
    }
    $stdout = $testProcess.StandardOutput.ReadToEnd().Trim()
    $stderr = $testProcess.StandardError.ReadToEnd().Trim()
    if ($testProcess.ExitCode -ne 0 -or $stderr -ne '' -or $stdout -notmatch '^PASS EarnVinewood cases=\d+$') {
        throw "EarnVinewood failed (exit=$($testProcess.ExitCode))`nstdout: $stdout`nstderr: $stderr"
    }
    Write-Output $stdout
} finally {
    if ($null -ne $testProcess) {
        if (-not $testProcess.HasExited) {
            $testProcess.Kill()
            $testProcess.WaitForExit()
        }
        $testProcess.Dispose()
    }
    [IO.File]::Delete($testPath)
}
