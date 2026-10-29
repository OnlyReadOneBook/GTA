; === 수익 자동화 스케줄러 (Vinewood 금고·직원 파견 · 벙커 보급 · DJ 교체 · 창고 직원) ===
; Main 시작 시 유휴 앱 모드(재시작 전 F9 전체 수익이었으면 전체 수익). F9 두 번은 전체 수익과 유휴 앱을 전환하고 End는 모두 멈춘다.
; 때가 된 벙커·DJ·창고는 MCT를 한 번 열어 묶어 처리하고 한 번 닫는다. 금고·앱 파견은 그다음 별도로 한다.
; 사용자 물리 입력이 EarnUserIdleSec 동안 없고 GTA가 앞일 때만 시작한다. 진행 중 사용자 입력·포커스 이탈 시 중단한다.
; 개별 실패는 기록하고 정리된 화면에서 다른 작업을 계속한다. 결과가 불명확해도 보류하지 않고 다음 차례에 다시 읽는다.
; 게임 종료·재시작 시 끄고, 사용자가 다시 켜야 새 게임 상태에서 예약을 시작한다.
global gEarnOn := false
global gEarnMode := "full"
global gEarnModeRequest := ""
global gEarnIdleEnabled := false
global gEarnDue := Map()        ; 작업 id → 다음 실행 시각(A_TickCount)
global gEarnDone := Map()       ; 작업 id → 켠 뒤 성공 횟수
global gEarnCurrent := ""       ; 지금 하는 작업 이름
global gEarnSellNotices := Map() ; 사업장별 판매 알림. 다른 사업장 관측이나 F9 토글로 지우지 않는다.
global gEarnSellNoticeSeen := Map() ; 사업장별 마지막 만재 확인 시각(A_TickCount). 오버레이가 오래된 알림을 숨기는 데 쓴다.
global gEarnTasks := []
global gEarnNextDue := Map()   ; 작업이 스스로 정한 다음 실행 시각(A_TickCount). 없으면 시작 시각 + 간격
global gEarnSoftFails := Map()   ; 작업별 연속 실패 횟수(로그용). 실패 뒤 간격을 늘리지 않는다
global gEarnHeld := Map()        ; 거래 결과 불명확 작업 id → 사유. 수동 재활성화 전에는 재실행하지 않는다
global gEarnFailures := Map()    ; 작업 id → 마지막 실패 사유와 다음 시도 시각(보류는 0)
global gEarnRecovery := ""        ; 확인된 정리 경로를 다음 tick에서 우선 재시도한다
global gEarnGuardArmed := false
global gEarnGuardStartedTick := 0
global gEarnUserAbort := false
global gEarnInputAbortReason := "" ; 최초 입력 감시 사유. 뒤따른 OCR 실패가 원인을 덮지 않게 회차별로 보존한다.
global gEarnManualStop := false
global gEarnManualCleanupActive := false
global gEarnManualCleanupAttempted := false
global gEarnTaskActive := false
global gEarnInputGuard := EarnInputAllowed
global gAFKScreenGuard := EarnAFKCloseMCT
global gEarnAFKCleanup := false

; AFK 방지가 오래 방치된 MCT 화면을 만나면 수익 작업과 같은 확인된 정리 경로(확인창 취소 → MCT 닫기 → 일어서기 → 사장 해제)로 닫는다.
; 수익 작업이 도는 중에는 건드리지 않는다. 열린 MCT 화면이 안 보이면 아무 입력도 하지 않고 빈 문자열을 돌려준다.
EarnAFKCloseMCT(idleSec) {
    global gEarnOn, gEarnBusy, gAbort, gEarnMode, gEarnRecovery
    if (gEarnMode = "apps")
        return ""
    if ((IsSet(gEarnBusy) && gEarnBusy) || gAbort)
        return ""
    ; 정리 복구가 걸려 있으면 같은 정리를 EarnTick 이 맡는다. AFK 는 마우스 왕복·전면화만 한다.
    ; 수익이 꺼진 뒤 남은 복구는 아무도 이어 하지 않으니 이 경우엔 AFK 가 정리한다.
    if (gEarnOn && IsObject(gEarnRecovery))
        return ""
    started := A_TickCount
    if (!IsGTAActive() || A_TimeIdlePhysical < A_TickCount - started)
        return ""
    return EarnAFKCloseMCTGuarded(idleSec)
}

EarnAFKCloseMCTGuarded(idleSec) {
    global gEarnBusy, gEarnFail, gAbort, gEarnAFKCleanup, gEarnGuardArmed, gEarnGuardStartedTick, gEarnGamePID, gEarnUserAbort, gEarnManualStop, gEarnInputAbortReason
    if ((IsSet(gEarnBusy) && gEarnBusy) || gAbort)
        return ""
    ; DJ 이름의 흰 글자 템플릿은 야외 하늘에도 일치한다. 화면·확인창으로만 정리에 진입한다(#270).
    if (!EarnAtMCT() && !EarnSeen("nc_dj_menu") && !EarnSeen("bunker_page") && !EarnSeen("bunker_entry")
        && !EarnSeen("dj_confirm_solomun") && !EarnSeen("dj_confirm_tale")
        && !EarnSeen("bunker_confirm") && !EarnSeen("bunker_pending"))
        return ""
    ; 수익 작업과 같은 입력 감시를 건다. 정리 중 사람이 키보드·마우스를 만지면 바로 멈춘다.
    prevArmed := gEarnGuardArmed, prevStarted := gEarnGuardStartedTick, prevPID := gEarnGamePID, prevUserAbort := gEarnUserAbort
    prevAbortReason := gEarnInputAbortReason
    gEarnBusy := true, gEarnAFKCleanup := true
    gEarnUserAbort := false, gEarnInputAbortReason := ""
    gEarnGuardArmed := true, gEarnGuardStartedTick := A_TickCount, gEarnGamePID := EarnGamePID()
    ok := false, result := ""
    try {
        gEarnFail := ""
        ; 정리 도중 F9의 key-up이 입력 감시에 잡히면 중앙 wrapper가 새 기준점으로 딱 한 번 다시 확인한다.
        ok := EarnTaskMCTEndWithManualRetry()
        if (gEarnUserAbort && gEarnInputAbortReason != "")
            gEarnFail := gEarnInputAbortReason
        EarnLog("AFK: " idleSec "초 방치된 MCT 화면 정리 " (ok ? "완료" : "실패: " gEarnFail))
        result := "MCT 화면 정리 " (ok ? "완료" : "실패: " gEarnFail) " idle=" idleSec "s"
    } catch as e {
        EarnFail("AFK MCT 정리 오류: " e.Message)
        if (gEarnUserAbort && gEarnInputAbortReason != "")
            gEarnFail := gEarnInputAbortReason
        result := "MCT 화면 정리 실패: " gEarnFail " idle=" idleSec "s"
    } finally {
        gEarnBusy := false, gEarnAFKCleanup := false
        DiscordHUDMCTStop()
        gEarnGuardArmed := prevArmed, gEarnGuardStartedTick := prevStarted, gEarnGamePID := prevPID
    }
    if (gEarnManualStop)
        EarnFinishManualStop(ok, true, true)
    else if (gEarnUserAbort) {
        ; 보통 사용자 입력으로 멈춘 AFK 정리는 다음 차례에 다시 판단한다. End·메모리 보호의 hard abort는 보존한다.
        gAbort := false
        gEarnUserAbort := prevUserAbort
    } else if (!gAbort)
        gEarnUserAbort := prevUserAbort
    gEarnInputAbortReason := gEarnUserAbort ? prevAbortReason : ""
    return result
}
global gEarnGamePID := 0

EarnTaskList() {
    global config
    s := config["Settings"]
    return [
        {id: "bunker", label: "벙커 보급", on: s["EarnBunker"], every: s["EarnBunkerIntervalSec"] * 1000, fn: EarnBunkerTask},
        {id: "dj", label: "DJ 교체", on: s["EarnDJ"], every: s["EarnDJIntervalMin"] * 60000, fn: EarnDJTask},
        {id: "warehouse", label: "창고 직원", on: s.Get("EarnWarehouse", 1), every: s.Get("EarnWarehouseIntervalMin", 10) * 60000, fn: EarnWarehouseTask},
        {id: "safe", label: "사업장 금고", on: s["EarnSafe"], every: s["EarnSafeIntervalMin"] * 60000, fn: EarnVinewoodSafeTask},
        {id: "staff", label: "앱 직원 파견", on: s.Get("EarnBailAgents", 1) || s.Get("EarnCargoStaff", 1) || s.Get("EarnHangarStaff", 1), every: s.Get("EarnStaffIntervalMin", 5) * 60000, fn: EarnVinewoodStaffTask},
        {id: "dispatch", label: "현장 파견", on: s["EarnDispatch"] && !s.Get("EarnMCTOnly", 0), every: s["EarnDispatchIntervalMin"] * 60000, fn: EarnDispatchTask}
    ]
}

EarnIdleInit() {
    global config, gEarnIdleEnabled, gEarnModeRequest, gEarnMode
    if (!config["Features"]["Earner"])
        return
    gEarnIdleEnabled := true
    gEarnMode := "apps"
    ; 재시작 전 F9 전체 수익이었으면 그대로 복원한다. 배포 재시작이 사용자가 끈 상태를 켜지 않게 F9 를 대신 누르지 않는다(1020).
    gEarnModeRequest := EarnStateGet("mode") = "full" ? "full" : "apps"
    SetTimer(EarnModeTick, 1000)
}

; 모드 전환은 진행 중 거래와 정리가 끝난 경계에서만 적용한다.
EarnModeTick() {
    global gEarnModeRequest, gEarnMode, gEarnOn, gEarnBusy, gEarnManualStop, gEarnRecovery, gEarnIdleEnabled, gEarnMCTSeenTick
    ; 요청 소비와 활성화를 한 경계로 묶는다. End는 해제 직후 새 상태를 중단한다.
    Critical "On"
    try {
        if (!gEarnIdleEnabled || gEarnModeRequest = "" || gEarnBusy || gEarnManualStop
            || IsObject(gEarnRecovery) || EarnOtherMacroBusy() || !EarnGamePID())
            return
        requested := gEarnModeRequest
        gEarnModeRequest := ""
        ; F9 전체 수익은 MCT 곁에서 켠다. 켠 뒤 손대지 않았으면 시선만 돌아간 MCT 를 제자리 회전으로 찾는다(EarnMCTTurnInPlace).
        if (requested != "apps")
            gEarnMCTSeenTick := A_TickCount
        if (gEarnOn) {
            gEarnMode := requested
            EarnStateSet("mode", requested)
            EarnLog("모드 전환: " (requested = "apps" ? "유휴 앱 자동" : "F9 전체 수익"))
        } else
            SetEarner(true, "", "hard", requested, true)
    } finally {
        Critical "Off"
    }
}

EarnTaskAllowed(id) {
    global gEarnMode
    return gEarnMode != "apps" || id = "safe" || id = "staff"
}

ToggleEarner(*) {
    global gEarnOn, gEarnBusy, gEarnManualStop, gEarnMode, gEarnModeRequest, gEarnIdleEnabled, gEarnRecovery
    if (gEarnManualStop) {
        ShowTooltip("💰 수익 자동화 끄기 정리 중: 다시 켤 수 없음", 2000)
        return
    }
    ; F9 두 번은 MCT 수익 켜기·끄기다. 끄기는 자동화를 멈추지 않고 진행 중 묶음이 끝난 경계에서 바인우드 작업만 남긴다.
    ; 끌 때 따로 MCT 정리·CEO 해제를 하지 않는다. CEO 해제는 MCT 작업 안에서만 한다 (1019 사용자 지시).
    if (gEarnOn && gEarnMode = "full") {
        gEarnIdleEnabled := true
        ; 끄기 요청은 다시 눌러도 취소하지 않는다. 묶음이 안 끝나 MCT 가 계속 도는 걸 보고 또 누르면 요청이 지워져
        ; MCT 가 영영 안 꺼졌다(1027 13:09 F9 확정 3번 → apps·취소·apps). 전체 수익으로 돌리는 건 전환이 끝난 뒤 F9 두 번이다.
        gEarnModeRequest := "apps"
        SetTimer(EarnModeTick, 1000)
        EarnLog("F9: MCT 수익 끄기 요청 (진행 중인 작업 하나만 끝내고 MCT 정리)")
        ShowTooltip("💰 MCT 수익 끄는 중: 지금 작업 하나만 끝내고 MCT 를 닫은 뒤 바인우드 작업만 계속", 2500)
        EarnModeTick()
    } else if (gEarnOn) {
        gEarnModeRequest := gEarnModeRequest = "full" ? "" : "full"
        EarnModeTick()
    } else {
        gEarnModeRequest := ""
        gEarnIdleEnabled := true
        SetTimer(EarnModeTick, 1000)
        SetEarner(true)
    }
}

SetEarner(on, reason := "", stopMode := "hard", mode := "full", preserveSchedule := false) {
    global gEarnMode, gEarnModeRequest, gEarnIdleEnabled
    if (!on && stopMode != "manual") {
        gEarnIdleEnabled := false, gEarnModeRequest := ""
        SetTimer(EarnModeTick, 0)
    }
    global gEarnOn, gEarnDue, gEarnDone, gEarnFail, gEarnTasks, gEarnNextDue, gEarnSoftFails, gEarnHeld, gEarnFailures, gEarnRecovery, gEarnRetryIn, gEarnBusy, gAbort, gEarnGamePID, gEarnBunkerFull, gEarnManualStop, gEarnManualCleanupActive, gEarnManualCleanupAttempted, gEarnTaskActive, gEarnAFKCleanup, gEarnUserAbort, gEarnInputAbortReason, config, afkOn
    if (on && (gEarnBusy || gEarnManualStop)) {
        ShowTooltip("💰 수익 자동화 끄기 정리 중: 다시 켤 수 없음", 2000)
        EarnLog("켜기 무시: 종료 정리 중 직접 재활성화 요청")
        return
    }
    if (on) {
        gEarnGamePID := EarnGamePID()
        if (!gEarnGamePID)
            on := false, reason := "GTA 게임 창 없음. 게임에 들어간 뒤 다시 켜기"
    }
    gEarnOn := on
    if (on) {
        InstallKeybdHook()
        InstallMouseHook()
        gEarnFail := ""
        gEarnMode := mode
        EarnStateSet("mode", mode)
        gEarnTasks := EarnTaskList()
        if (!preserveSchedule)
            gEarnDue := Map(), gEarnDone := Map(), gEarnNextDue := Map(), gEarnSoftFails := Map()
        if (!preserveSchedule)
            gEarnHeld := Map(), gEarnFailures := Map()
        gEarnRecovery := ""
        gEarnRetryIn := 0
        gEarnManualStop := false
        gEarnManualCleanupActive := false
        gEarnManualCleanupAttempted := false
        gAbort := false
        gEarnUserAbort := false
        gEarnInputAbortReason := ""
        ; 끈 사이에 벙커를 팔았을 수 있다. 첫 확인은 벙커 카드로 새로 읽는다.
        gEarnBunkerFull := false
        now := A_TickCount
        s := config["Settings"]
        for t in gEarnTasks {
            pending := EarnStateGet("pending_" t.id)
            if (pending != "" && !EarnHoldsPending(t.id)) {
                EarnStateSet("pending_" t.id, "")
                pending := ""
            }
            if (pending != "") {
                gEarnHeld[t.id] := pending
                gEarnFailures[t.id] := {reason: pending, nextTick: 0}
                EarnLog("보류: " t.id " 이전 요청 결과 확인 필요 (" pending "), 나머지 작업 계속")
            }
            if (!gEarnDone.Has(t.id))
                gEarnDone[t.id] := 0
            ; 창고·벙커·DJ는 즉시 확인. 금고와 파견은 설정한 첫 대기를 따른다.
            first := t.id = "safe" ? s["EarnSafeFirstMin"] * 60000 : t.id = "dispatch" ? s["EarnDispatchFirstMin"] * 60000 : 0
            if (!gEarnDue.Has(t.id))
                gEarnDue[t.id] := now + first
        }
        if (config["Features"]["AntiAFK"] && !afkOn)
            SetAntiAFK(true)
        ; AFK 입력도 EarnTick 이 맡는다. AFK 자체 타이머는 끈다.
        try SetTimer(%"AntiAFKTick"%, 0)
        SetTimer(EarnTick, 1000)
        ShowTooltip(mode = "apps" ? "💰 유휴 앱 자동 (" KeyLabelFor("Earner") " 두 번: 전체 수익, End: 멈춤)" : "💰 전체 수익 켜짐 (" KeyLabelFor("Earner") " 두 번: MCT 수익 끄기, End: 멈춤)", 2500)
        EarnLog("켜짐: " EarnEnabledText())
    } else {
        EarnStateSet("mode", "")
        SetTimer(EarnTick, 0)
        ; 수익이 꺼지면 AFK 는 자체 타이머로 돌아간다.
        if (IsSet(afkOn) && afkOn)
            try SetTimer(%"AntiAFKTick"%, 5000)
        gEarnInputAbortReason := ""
        ; gEarnBusy는 예약 작업과 AFK 정리가 공유한다. 정리를 소비할 주체가 있는 구간에만
        ; 수동 종료 latch를 세워 종료 처리가 없는 busy 상태에 남지 않게 한다.
        manualCleanup := stopMode = "manual" && gEarnBusy && (gEarnTaskActive || gEarnAFKCleanup)
        if (reason != "")
            gEarnFail := reason
        else
            gEarnFail := ""
        ; 작업이 도는 중이면 그 자리에서 멈추게 한다 (End 와 같게). 안 그러면 F9 로 꺼도 하던 작업이 끝까지 키를 보낸다
        if (gEarnBusy) {
            gEarnManualStop := manualCleanup
            gEarnManualCleanupAttempted := manualCleanup && gEarnAFKCleanup
            ; 예약 작업은 본문을 끊고 중앙 wrapper에서 정리를 재개한다. 이미 정리 자체를 수행 중인 AFK 경로는
            ; 새 abort를 만들지 않고 그 확인된 닫기와 CEO 해제를 그대로 끝낸다.
            if (!manualCleanup || gEarnTaskActive)
                gAbort := true
            ReleaseHeldKeys()
        } else {
            gEarnManualStop := false
            gEarnManualCleanupAttempted := false
        }
        if (manualCleanup) {
            ShowTooltip("💰 수익 자동화 끄는 중: MCT 정리와 CEO 해제", 3000)
            EarnLog("끄는 중: 진행 작업 중단 뒤 MCT 정리와 CEO 해제")
        } else {
            ShowTooltip("💰 수익 자동화 꺼짐" (reason = "" ? "" : ": " reason), 3000)
            EarnLog("꺼짐" (reason = "" ? "" : ": " reason))
        }
    }
}

EarnEnabledText() {
    global gEarnTasks
    list := ""
    for t in gEarnTasks
        if (t.on && EarnTaskAllowed(t.id))
            list .= (list = "" ? "" : ", ") t.label
    return list = "" ? "켜진 작업 없음" : list
}

EarnTick() {
    global gEarnOn, gEarnBusy, gEarnDue, gEarnDone, gEarnTasks, gEarnCurrent, gEarnFail, gEarnNextDue, gEarnSoftFails, gEarnHeld, gEarnFailures, gEarnRecovery, gEarnRetryIn, gEarnCleanupNoScreen, gEarnCleanupTimedOut, gAbort, gEarnGamePID, gEarnUserAbort, gEarnManualStop, gEarnManualCleanupAttempted, gEarnTaskActive, gEarnInputAbortReason, config, afkOn, afkNextDue
    if (!gEarnOn || gEarnBusy)
        return
    if (!gEarnGamePID || EarnGamePID() != gEarnGamePID) {
        SetEarner(false, "GTA 종료 또는 재시작 감지. 현재 화면을 확인하고 다시 켜기")
        return
    }
    ; 실제 사용자 입력을 기다린다. 자동 입력은 물리 유휴 시간을 초기화하지 않는다.
    if (A_TimeIdlePhysical < config["Settings"]["EarnUserIdleSec"] * 1000)
        return
    ; 다른 매크로가 게임에 키를 보내는 중이면 기다린다
    if (EarnOtherMacroBusy())
        return
    now := A_TickCount
    recovering := IsObject(gEarnRecovery)
    if (recovering && now < gEarnRecovery.nextTick) {
        EarnAFKTick()
        return
    }
    ; F9 두 번의 모드 전환 요청은 묶음이 끝난 경계에서 EarnModeTick 이 적용한다. 그런데 이 틱이 같은 경계에서 차례가 된
    ; 다음 작업을 먼저 잡으면 다시 busy 가 되어 전환이 영영 밀린다(1023 21:34·22:02 F9 뒤 22:19 까지 MCT 묶음이 계속 돌았다).
    ; 작업을 고르기 전에 남은 요청을 먼저 적용한다. 복구 중이면 EarnModeTick 이 스스로 기다린다.
    if (!recovering && IsSet(gEarnModeRequest) && gEarnModeRequest != "")
        EarnModeTick()
    task := recovering ? gEarnRecovery.task : ""
    if (!recovering) {
        ; 짧은 재관측 주기의 앞 작업이 이미 만료돼도 더 오래 기다린 뒤쪽 작업을 계속 굶기지 않는다.
        ; 예약 시각이 같으면 기존 목록 순서를 유지한다.
        for t in gEarnTasks {
            if (t.on && EarnTaskAllowed(t.id) && !gEarnHeld.Has(t.id) && gEarnDue[t.id] <= now
                && (!IsObject(task) || gEarnDue[t.id] < gEarnDue[task.id]))
                task := t
        }
    }
    if (!IsObject(task)) {
        EarnAFKTick()
        return
    }
    ; 시작 시점에 실행할 차례이거나 EarnMCTBatchAheadSec(기본 120초) 안에 차례가 될 MCT 작업을 묶는다. 진행 중 새로 due가 된 작업은 다음 회차다.
    ; 1005 14:10·14:20 에 DJ 가 묶음을 정한 순간보다 몇 초 늦게 due 가 되어, 창고만 하고 나온 뒤 1분 안에 나이트클럽에 다시 들어갔다.
    mctSession := recovering ? gEarnRecovery.mct : EarnIsMCTTask(task.id)
    dueTasks := recovering ? gEarnRecovery.tasks : [task]
    if (mctSession && !recovering) {
        dueTasks := []
        ahead := config["Settings"].Get("EarnMCTBatchAheadSec", 120) * 1000
        for t in gEarnTasks {
            if (t.on && !gEarnHeld.Has(t.id) && EarnIsMCTTask(t.id)
                && gEarnDue[t.id] <= now + (gEarnFailures.Has(t.id) ? 0 : ahead))
                dueTasks.Push(t)
        }
    }
    if (!IsGTAActive()) {
        EarnLog(task.label ": GTA 포커스가 돌아오면 다시 (30초 대기)")
        gEarnDue[task.id] := now + 30000
        ; 복구 경로는 gEarnDue 가 아니라 gEarnRecovery.nextTick 으로 차례를 정한다. 여기서 같이 미루지 않으면
        ; 1초 tick 마다 이 분기로 되돌아와 같은 로그가 매초 쌓인다(1009 02:43 부터 하루 1,351줄).
        if (recovering)
            gEarnRecovery.nextTick := now + 30000
        ; GTA 를 앞으로 가져오는 건 AntiAFKTick 뿐이다. 복구가 걸린 동안 그걸 안 부르면 다른 창이 앞인 채로 영영 멈췄다(1023 04:30).
        EarnAFKTick()
        return
    }
    try inputLock := EarnInputLockAcquire()
    catch as e {
        SetEarner(false, "입력 잠금 오류: " e.Message)
        return
    }
    if (!IsObject(inputLock))
        return
    gEarnBusy := true
    gEarnTaskActive := true
    gAbort := false
    gEarnUserAbort := false
    gEarnCurrent := task.label
    ; 이 작업이 보내는 키를 방치 판정(AFKOthersIdleMs)이 남의 입력으로 세지 않게 한다. 안 그러면 몇 분마다 도는 MCT 작업 때문에
    ; 방치 5분에 닿지 못해 CPU 부스트·프레임 제한이 한 번도 안 걸렸다(1005 13:10~16:30, 핫스팟 95°C. 제한 때는 62~67°C).
    try %"AFKSelfInput"%(true)
    ; 복구는 첫 입력 확인에서 바로 막혀도 지난 묶음 결과를 들고 간다. 빈 결과로 바꾸면 본문을 끝낸 작업의 예약이 지워진다.
    outcome := recovering ? gEarnRecovery.outcome : {results: [], cleanupOK: true}
    fatalReason := ""
    try {
        EarnInputGuardStart()
        if (EarnInputAllowed()) {
            if (recovering) {
                outcome.cleanupOK := gEarnRecovery.mct ? EarnTaskMCTEndWithManualRetry() : EarnVinewoodClose()
            } else if (mctSession)
                outcome := EarnRunMCTBatch(dueTasks)
            else {
                result := EarnRunScheduledTask(task)
                outcome.results.Push(result)
                outcome.cleanupOK := result.cleanupOK
            }
        }
        ; no-screen 복구의 CEO 해제도 다른 화면 입력과 같은 mutex·물리 입력 guard 안에서만 시도한다.
        if (recovering && mctSession && !outcome.cleanupOK && gEarnCleanupNoScreen
            && gEarnRecovery.attempts + 1 >= 2) {
            if (EarnBossOffWithManualRetry(true))
                outcome.cleanupOK := true
        }
        ; 화면을 못 알아본 채 다음 시도까지 아무 입력도 없으면 방치로 세어진다(1020 17:35~17:49 61회 무입력 끝에 추방).
        ; 뒤로(Backspace)는 확인창에서는 취소, MCT 화면에서는 한 단계 나가기라 돈이 나가지 않는다. 누른 뒤 결과는 다음 시도의 화면 확인이 다시 본다.
        ; 판독이 느려 목록을 다 못 훑고 마감된 경우도 같다. MCT 화면 안에서는 AFK 마우스 왕복이 방치를 못 막는다.
        if (recovering && mctSession && !outcome.cleanupOK && (gEarnCleanupNoScreen || gEarnCleanupTimedOut) && EarnInputAllowed()) {
            EarnLog("복구: " task.id " 화면 미인식 → 뒤로(Backspace) 한 번 뒤 다시 확인")
            EarnPress("Backspace")
        }
        ; 마지막 단계에서 사용자가 개입한 경우 성공/자동 재시도로 덮지 않는다.
        if (!EarnInputAllowed()) {
            fatalReason := gEarnFail = "" ? task.label " 중단" : gEarnFail
            gEarnRetryIn := 0
        }
    } catch as e {
        fatalReason := task.label " 오류: " e.Message " (" e.File ":" e.Line ")"
        EarnFail(fatalReason)
    } finally {
        try {
            ; HUD 복원은 창 응답을 기다릴 수 있다. 예외로 남은 키도 먼저 해제하고 감시를 닫는다.
            try ReleaseHeldKeys()
            finally EarnInputGuardStop()
        } finally {
            try %"AFKSelfInput"%(false)
            gEarnBusy := false
            gEarnTaskActive := false
            gEarnCurrent := ""
            EarnInputLockRelease(inputLock)
        }
    }
    ; F9 수동 종료는 새 작업 입력을 즉시 막되, 이미 연 MCT의 확인된 정리와 CEO 해제까지 끝낸 뒤 꺼진다.
    ; 정리 기준점을 다시 잡은 뒤 생긴 End·사용자 입력·포커스 이탈은 gAbort를 다시 켜므로 성공으로 덮지 않는다.
    ; 끝까지 한 작업의 입력은 방치 킥을 막는 입력이기도 하다. 그 뒤 AFK 입력은 한 간격 뒤로 민다.
    ; 복구 시도는 지난 묶음 결과를 다시 쓸 뿐 본문을 돌리지 않는다. 여기서도 밀면 시도마다 200초씩 밀려 AFK 입력이 한 번도 안 나간다.
    if (!recovering)
        for result in outcome.results
            if (result.ok)
                afkNextDue := A_TickCount + config["Settings"].Get("AFKIntervalSec", 200) * 1000
    if (gEarnUserAbort && gEarnInputAbortReason != "")
        gEarnFail := gEarnInputAbortReason
    if (gEarnManualStop) {
        EarnFinishManualStop(outcome.cleanupOK, gEarnManualCleanupAttempted, mctSession)
        return
    }
    ; 사용자가 손을 댄 중단은 끄지 않고 손을 떼면(AFKUserIdleSec) 바로 다시 한다. 따로 기다리는 시간은 두지 않는다(1019 사용자 지시).
    ; MCT 작업은 시작할 때 위치를 다시 확인하므로 정리가 덜 됐어도 여기서 멈추지 않는다.
    ; (1004 18:36 사용자가 잠깐 만져 자동화가 통째로 꺼졌다. 밤새 켜 두는 용도라 매번 F9 를 다시 눌러야 했다)
    if (gEarnUserAbort) {
        gAbort := false
        if (!outcome.cleanupOK || recovering)
            gEarnRecovery := {task: task, tasks: dueTasks, mct: mctSession, outcome: outcome, attempts: 0, nextTick: A_TickCount}
        finished := Map(), bodyDone := Map()
        for result in outcome.results {
            if (result.ok && outcome.cleanupOK && !recovering) {
                EarnFinishScheduledTask(result)
                finished[result.task.id] := true
            } else if (result.ok)
                bodyDone[result.task.id] := true
        }
        for t in dueTasks {
            if (finished.Has(t.id))
                continue
            ; 본문을 끝낸 작업은 정리 복구가 끝날 때 원래 결과로 확정한다. 스스로 잡은 다음 확인을 지우면 기본 간격으로 밀린다
            ; (1023 04:25 보급 3% 벙커의 경계 재확인이 06:16:59 로 밀렸다).
            if (bodyDone.Has(t.id))
                continue
            pending := EarnHoldsPending(t.id) ? EarnStateGet("pending_" t.id) : ""
            if (pending != "") {
                gEarnHeld[t.id] := pending
                gEarnFailures[t.id] := {reason: pending, nextTick: 0}
                EarnLog("보류: " t.id " " pending "; 사용자 중단 뒤 재요청 금지")
                continue
            }
            if (gEarnNextDue.Has(t.id))
                gEarnNextDue.Delete(t.id)
            gEarnDue[t.id] := A_TickCount
        }
        abortReason := gEarnInputAbortReason != "" ? gEarnInputAbortReason : "입력 감시 중단 (상세 사유 없음)"
        EarnLog(task.label ": " abortReason " → 손을 떼면 바로 다시")
        ShowTooltip("💰 " abortReason " → 손을 떼면 바로 다시", 4000)
        return
    }
    if (fatalReason != "") {
        EarnStopAfterFailure(fatalReason)
        return
    }
    ; 템플릿이 모두 안 보인다는 사실은 메뉴가 닫혔다는 증거가 아니다.
    ; DJ 확인창이 남아도 no-screen으로 판독된 1012 방치 추방처럼, 실제 정리 확인 전에는 복구를 유지한다.
    if (!outcome.cleanupOK) {
        attempts := recovering ? gEarnRecovery.attempts + 1 : 1
        delay := 0
        gEarnRecovery := {task: task, tasks: dueTasks, mct: mctSession, outcome: outcome, attempts: attempts, nextTick: A_TickCount + delay}
        EarnLog("복구 대기: " task.id " 정리 미확인 (" gEarnFail ") → 확인된 정리 경로 바로 재시도; 수익 작업 대기")
        ; 복구가 막혀도 겉으로는 아무 표시가 없었다(1029 02:50~12:55 2,449번 실패하는 동안 창고 확인이 멈춰 나클 만재를 10시간 늦게 알림).
        ; 20번(약 5분)째와 그 뒤 240번(약 1시간)마다 다른 작업이 막혀 있다고 알린다.
        if (attempts = 20 || Mod(attempts, 240) = 0) {
            EarnLog("복구 막힘: " task.id " 정리 " attempts "번 실패, 다른 수익 작업 대기 중 (" gEarnFail ")")
            ShowTooltip("⚠ 수익 정리 복구 " attempts "번 실패: 다른 작업 대기 중, 화면 확인 필요", 15000)
        }
        ; 알아본 화면에서 HUD 확인에 막히면 정리는 키를 하나도 안 보낸다. 1023 05:31 부터 이렇게 무입력으로 돌다 방치 킥을 당했다(06:04 녹화).
        ; 시도 사이마다 AFK 마우스 왕복(간격은 AntiAFKTick 이 지킨다)을 넣어 재시도가 길어져도 입력이 끊기지 않게 한다.
        EarnAFKTick()
        return
    }
    if (recovering) {
        gEarnRecovery := ""
        EarnLog("복구 완료: " task.id " 메뉴 종료·보스 해제 확인, 나머지 작업 재개")
    }
    ; 재시도로 미룬 작업이 있어도 묶음의 나머지 결과를 마저 확정한다. 자동화가 꺼졌을 때만 멈춘다.
    for result in outcome.results {
        EarnFinishScheduledTask(result)
        if (!gEarnOn)
            return
    }
}

; 할 작업이 없거나 복구 차례를 기다리는 틈에 AFK 입력을 넣는다. 간격·포커스 복귀·화면 정리 판정은 AntiAFKTick 이 그대로 한다.
EarnAFKTick() {
    global afkOn
    if (IsSet(afkOn) && afkOn)
        try %"AntiAFKTick"%()
}

; 요청 결과를 못 읽어도 어느 작업도 보류하지 않는다. 다음 차례에 화면을 다시 읽어 이어 간다 (1019·1024 사용자 지시).
; 금고는 수입이라 다시 수거해도 잃는 게 없고, 벙커 보급·DJ 재고용·직원 파견은 이미 산 것을 게임이 비활성으로 막아 재요청해도 돈이 다시 나가지 않는다.
; 1024 09:08 Agency 금고 수거 뒤 60초 안에 $0 을 못 읽어 pending_safe 가 남았고, 그 뒤 4시간 넘게 금고 셋 다 수거하지 않았다.
; pending_* 상태는 원장 기록 짝(EarnTransactionBegin/CashConfirmed)으로만 쓴다.
EarnHoldsPending(id) {
    return false
}

EarnIsMCTTask(id) {
    return id = "bunker" || id = "dj" || id = "warehouse"
}

; 지금 실제로 돌 작업(켜짐 · 모드 허용 · 보류 아님)으로 묶음 이름을 만든다. 예: "MCT + 바인우드". 없으면 빈 문자열.
EarnScopeLabel() {
    global gEarnTasks, gEarnHeld
    mct := false, vinewood := false, dispatch := false
    for t in gEarnTasks {
        if (!t.on || !EarnTaskAllowed(t.id) || gEarnHeld.Has(t.id))
            continue
        if (EarnIsMCTTask(t.id))
            mct := true
        else if (t.id = "safe" || t.id = "staff")
            vinewood := true
        else
            dispatch := true
    }
    label := ""
    for part in [mct ? "MCT" : "", vinewood ? "바인우드" : "", dispatch ? "현장 파견" : ""]
        if (part != "")
            label .= (label = "" ? "" : " + ") part
    return label
}

; 각 본문은 자기 예약을 유지한다. 완료 횟수·최종 로그는 공동 MCT 정리가 끝난 뒤 확정한다.
EarnRunScheduledTask(task, mctSession := false) {
    global gEarnCurrent, gEarnFail, gEarnRetryIn, gEarnMode
    result := {task: task, startTick: A_TickCount, ok: false, retryIn: 0, reason: "", cleanupOK: true}
    gEarnCurrent := task.label
    gEarnRetryIn := 0
    gEarnFail := ""
    try {
        EarnLog("시작: " task.label)
        ; 휴대폰·MCT 가 게임 문제로 안 먹는 상태면 앱을 열기 전에 초대 전용 세션으로 다시 들어간다. 앱은 어디서든 열리므로 그대로 이어 한다.
        if (!mctSession && EarnInputAllowed() && EarnGlitchRejoinDue())
            EarnGlitchRejoin()
        ; 앱 작업은 메뉴 없는 HUD 에서 전화를 연다. 남은 상호작용 메뉴는 먼저 닫는다(MCT 묶음은 묶음 시작에서 닫는다).
        if (EarnInputAllowed() && (mctSession || EarnCloseLeftoverMenu()))
            result.ok := mctSession ? task.fn.Call(false) : task.id = "safe" && gEarnMode = "apps" ? task.fn.Call(false) : task.fn.Call()
    } catch as e {
        EarnFail(task.label " 오류: " e.Message " (" e.File ":" e.Line ")")
    }
    if (!EarnInputAllowed()) {
        result.ok := false
        gEarnRetryIn := 0
    }
    result.reason := gEarnFail
    result.retryIn := result.ok ? 0 : gEarnRetryIn
    ; 실패한 앱은 확인된 Backspace 경로만으로 닫는다. 정리가 덮어써도 본래 사유는 보존한다.
    if (!result.ok && !mctSession && (task.id = "safe" || task.id = "staff") && EarnInputAllowed()) {
        result.cleanupOK := EarnVinewoodClose()
        gEarnFail := result.reason
    }
    gEarnRetryIn := 0
    if (result.ok && mctSession)
        EarnLog("본문 완료: " task.label " (MCT 정리 대기)")
    return result
}

EarnRunMCTBatch(tasks) {
    global gEarnCurrent, gEarnFail, gEarnRetryIn, gEarnMCTCleanupOK, gEarnModeRequest
    outcome := {results: [], cleanupOK: true}
    opened := false
    currentTask := tasks[1]
    gEarnCurrent := "MCT 작업 묶음"
    gEarnFail := ""
    gEarnRetryIn := 0
    try {
        ; 남은 상호작용 메뉴가 MCT 접근 안내를 가리면 위치 확인이 끝없이 실패한다(1023 12:33~13:10). 위치를 보기 전에 닫는다.
        if (!EarnCloseLeftoverMenu()) {
            for task in tasks
                outcome.results.Push({task: task, startTick: A_TickCount, ok: false, retryIn: gEarnRetryIn, reason: gEarnFail})
            return outcome
        }
        ; 휴대폰·MCT 가 게임 문제로 둘 다 안 먹으면 초대 전용 세션으로 다시 들어간다. 다시 들어가면 스폰 부동산이라 MCT 곁이 아니므로
        ; 이 묶음은 열지 않고 MCT 수익을 유휴 앱 모드로 내린다. 사용자가 MCT 곁에 세우고 F9 두 번이면 돌아온다.
        if (EarnGlitchRejoinDue()) {
            rejoined := EarnGlitchRejoin()
            reason := rejoined ? "재접속 뒤 MCT 곁이 아님: MCT 곁에서 F9 두 번으로 MCT 수익 다시 켜기" : gEarnFail
            for task in tasks
                outcome.results.Push({task: task, startTick: A_TickCount, ok: false, retryIn: 3 * 60000, reason: reason})
            return outcome
        }
        ; Begin은 진입 실패·예외를 자체 정리한다. 성공한 세션만 여기서 닫는다.
        opened := EarnTaskMCTBegin()
        ; 본문에 못 들어간 묶음은 MCT 무반응으로 센다(사용자 입력·포커스 이탈로 끊긴 것은 세지 않는다).
        if (opened)
            EarnGlitchNote("mct", false)
        else if (EarnInputAllowed())
            EarnGlitchNote("mct", true)
        if (!opened && IsSet(gEarnMCTCleanupOK))
            outcome.cleanupOK := gEarnMCTCleanupOK
        if (opened) {
            for task in tasks {
                ; F9 로 MCT 수익을 끄면 묶음의 남은 작업은 하지 않고 바로 MCT 정리로 간다. 남은 작업은 예약을 그대로 두고 앱 모드에서 걸러진다.
                if (gEarnModeRequest = "apps") {
                    EarnLog("F9: MCT 묶음의 남은 작업 건너뛰고 정리 (" task.label " 부터)")
                    break
                }
                currentTask := task
                result := EarnRunScheduledTask(task, true)
                outcome.results.Push(result)
                if (!result.ok)
                    break
            }
        } else {
            ; 진입 전 위치 확인처럼 위험하지 않은 실패는 Begin 이 재시도 시간을 채워 둔다.
            ; 묶음의 작업 모두에 같은 결과를 남겨야 남은 작업이 다음 틱에 바로 다시 시도되지 않는다.
            for task in tasks
                outcome.results.Push({task: task, startTick: A_TickCount, ok: false, retryIn: gEarnRetryIn, reason: gEarnFail})
        }
    } catch as e {
        EarnFail("MCT 작업 오류: " e.Message " (" e.File ":" e.Line ")")
        outcome.results.Push({task: currentTask, startTick: A_TickCount, ok: false, retryIn: 0, reason: gEarnFail})
    } finally {
        if (opened) {
            try outcome.cleanupOK := EarnTaskMCTEndWithManualRetry()
            catch as e {
                outcome.cleanupOK := false
                EarnFail("MCT 정리 오류: " e.Message " (" e.File ":" e.Line ")")
            }
        }
        gEarnRetryIn := 0
    }
    return outcome
}

; 켜져 있고 지금 모드에서 돌 MCT 작업이 하나라도 있으면 true. 없으면 MCT 무반응은 셀 수 없다.
EarnMCTTasksActive() {
    global gEarnTasks, gEarnHeld
    for t in gEarnTasks
        if (t.on && EarnIsMCTTask(t.id) && EarnTaskAllowed(t.id) && !gEarnHeld.Has(t.id))
            return true
    return false
}

; 휴대폰이 EarnGlitchRejoinFails 회 연속 안 열렸고, MCT 작업이 도는 중이면 MCT 도 같은 횟수만큼 못 열었을 때 true.
; MCT 작업이 없으면(유휴 앱 모드·MCT 작업 꺼짐) 휴대폰만 본다. 0 이면 끔.
EarnGlitchRejoinDue() {
    global gEarnGlitch, config
    n := config["Settings"].Get("EarnGlitchRejoinFails", 3)
    if (n <= 0 || gEarnGlitch["phone"] < n)
        return false
    return !EarnMCTTasksActive() || gEarnGlitch["mct"] >= n
}

; 휴대폰·MCT 가 게임 문제로 안 먹을 때(1010 07:30~08:18: MCT 「앞에 서 있거나…」 16회, 전화 「홈 화면 미확인」 10회가 나란히 쌓였다)
; 초대 전용 세션으로 다시 들어간다. 재접속하면 입력이 다시 먹는다(사용자 관찰, 1023).
; 스폰 위치(사용자 설정, 예: 저택)에서 시작하므로 MCT 곁이 아니다. 저택 AI 패널 빠른 이동으로 테러바이트에 가 MCT 를 찾는 경로는
; 새 화면 템플릿(패널 안내·빠른 이동 목록·테러바이트 도착)이 모두 실측 캡처가 필요해 넣지 않았다. 대신 MCT 수익을 유휴 앱 모드로
; 내리고 바인우드 앱 작업만 계속한다(1023 사용자 지시). 사용자가 MCT 곁에 세우고 F9 두 번이면 전체 수익으로 돌아온다.
; 재접속을 확인하지 못했으면(메뉴 화면 미확인) 자리는 그대로이므로 모드를 바꾸지 않는다. 횟수만 비워 다음 횟수에 다시 시도한다.
EarnGlitchRejoin() {
    global gEarnGlitch, gEarnMCTSeenTick, gEarnMode, gEarnModeRequest, gEarnIdleEnabled, gEarnFail, config
    EarnLog("재접속: 휴대폰 " gEarnGlitch["phone"] "회·MCT " gEarnGlitch["mct"] "회 연속 무반응 → 초대 전용 세션으로 다시 들어감")
    ShowTooltip("💰 휴대폰·MCT 무반응: 초대 전용 세션으로 재접속", 4000)
    EarnGlitchNote("phone", false), EarnGlitchNote("mct", false)
    if (!EarnRejoinSession()) {
        EarnLog("재접속 미확인: " gEarnFail " → 자리를 그대로 보고 다음 무반응 " config["Settings"].Get("EarnGlitchRejoinFails", 3) "회에 다시")
        return false
    }
    ; 재접속 뒤 캐릭터는 스폰 부동산에 있다. MCT 곁 기준 시각을 지워 제자리 회전·안내 없는 Space 를 보내지 않는다.
    gEarnMCTSeenTick := 0
    if (gEarnMode = "full") {
        gEarnIdleEnabled := true
        gEarnModeRequest := "apps"
        SetTimer(EarnModeTick, 1000)
        EarnLog("재접속 완료: MCT 곁이 아니므로 바인우드 작업만 계속. MCT 수익은 MCT 곁에서 F9 두 번으로 다시 켜기")
        ShowTooltip("💰 재접속 완료: 바인우드 작업만 계속. MCT 수익은 MCT 곁에서 F9 두 번", 8000)
    } else
        EarnLog("재접속 완료: 바인우드 작업 계속")
    return true
}

; 정상 정리 도중 F9가 들어오면 첫 호출은 중단 신호를 보고 false로 돌아올 수 있다. 정리 입력은 모두 현재 화면을
; 다시 확인한 뒤 보내므로 같은 잠금과 guard 안에서 딱 한 번만 다시 읽어 이어 간다. End·메모리 보호처럼 사유가 있는
; 중단은 gEarnManualStop을 내리므로 재호출하지 않는다.
EarnTaskMCTEndWithManualRetry() {
    global gEarnManualStop
    if (gEarnManualStop)
        return EarnManualStopCleanup()
    cleaned := EarnTaskMCTEnd()
    if (!cleaned && gEarnManualStop) {
        EarnLog("끄기 정리 재확인: MCT 정리 도중 F9 감지")
        return EarnManualStopCleanup()
    }
    return cleaned
}

; no-screen recovery에서 CEO 해제 중 F9가 들어와도 같은 input lock·guard 안에서 기준점을 새로 잡고 딱 한 번만 다시 확인한다.
EarnBossOffWithManualRetry(requireConfirmed := false) {
    global gEarnManualStop
    cleaned := requireConfirmed ? EarnConfirmNoScreenCleanup() : EarnBossOffIfOn()
    if (!cleaned && gEarnManualStop) {
        EarnLog("끄기 정리 재확인: CEO 해제 도중 F9 감지")
        return EarnManualBossOffCleanup(requireConfirmed)
    }
    return cleaned
}

; no-screen은 HUD 복귀와 실제 보스 메뉴 확인이 모두 있어야 정리 완료다.
; 화살표 판독 불가뿐 아니라 MCT 아이콘에 가려진 흰 화살표도 CEO 해제 증거로 쓰지 않는다.
EarnConfirmNoScreenCleanup() {
    if (!EarnInputAllowed() || !EarnMCTRecoveryHud())
        return false
    DiscordHUDMCTSet(false)
    if (!EarnInputAllowed())
        return false
    if (!EarnCEO(false) || !EarnMenuClose())
        return false
    return EarnInputAllowed() && EarnMCTRecoveryHud()
}

EarnManualBossOffCleanup(requireConfirmed := false) {
    global gEarnManualCleanupActive, gEarnManualCleanupAttempted, gEarnGuardStartedTick, gEarnUserAbort, gAbort, gEarnFail, gEarnInputAbortReason
    gEarnManualCleanupActive := true
    gEarnManualCleanupAttempted := true
    gAbort := false
    gEarnUserAbort := false
    gEarnInputAbortReason := ""
    gEarnGuardStartedTick := A_TickCount - A_TimeIdlePhysical
    gEarnFail := ""
    try return requireConfirmed ? EarnConfirmNoScreenCleanup() : EarnBossOffIfOn()
    finally gEarnManualCleanupActive := false
}

; F9를 누른 시점까지의 중단 신호는 작업 본문에만 적용한다. 같은 입력 잠금과 감시를 유지한 채 기준점을
; 다시 잡아 MCT 정리를 허용하고, 이후 새 사용자 입력·포커스 이탈·End는 다시 gAbort를 켜 즉시 멈춘다.
EarnManualStopCleanup() {
    global gEarnManualCleanupActive, gEarnManualCleanupAttempted, gEarnGuardStartedTick, gEarnUserAbort, gAbort, gEarnFail, gEarnInputAbortReason
    gEarnManualCleanupActive := true
    gEarnManualCleanupAttempted := true
    gAbort := false
    gEarnUserAbort := false
    gEarnInputAbortReason := ""
    ; Dispatch가 두 번째 F9의 key-up까지 기다린 뒤 원래 작업을 재개한다. 현재 물리 유휴 시각을 기준점으로 삼아
    ; 그 F9를 새 사용자 입력으로 다시 세지 않고, 이 뒤에 들어온 입력만 감지한다.
    gEarnGuardStartedTick := A_TickCount - A_TimeIdlePhysical
    gEarnFail := ""
    EarnLog("끄기 정리 시작: 확인된 MCT 화면 닫기와 CEO 해제")
    try return EarnTaskMCTEnd()
    finally gEarnManualCleanupActive := false
}

; 예약 작업과 AFK MCT 정리가 공유하는 F9 종료 finalizer다. hard stop은 gEarnManualStop을 먼저 내리므로 여기에 오지 않는다.
EarnFinishManualStop(cleanupOK, cleanupAttempted, mctSession := true) {
    global gEarnManualStop, gEarnManualCleanupAttempted, gAbort, gEarnUserAbort, gEarnFail, gEarnInputAbortReason, gEarnIdleEnabled, gEarnModeRequest, gEarnRecovery
    ; AHK hotkey thread가 finalizer 사이에 끼어들면 새 run을 켠 뒤 이전 상태로 덮어쓸 수 있다.
    ; 모든 상태 정리가 끝날 때까지 latch를 유지하고, 그 순간의 F9·End는 critical 해제 뒤 새 상태에 적용되게 한다.
    Critical "On"
    try {
    ; Critical보다 먼저 End가 선점했으면 hard stop이 latch를 내린 상태다. 그 중단 상태를 이전 finalizer로 덮지 않는다.
    if (!gEarnManualStop)
        return
    interrupted := cleanupAttempted && gAbort
    cleanupOK := !mctSession || cleanupOK
    if (cleanupOK && !interrupted) {
        gEarnFail := ""
        message := cleanupAttempted ? "MCT 정리와 CEO 해제 완료" : "진행 작업 중단 완료"
        EarnLog("꺼짐: " message)
        ShowTooltip("💰 수익 자동화 꺼짐: " message, 4000)
    } else {
        if (gEarnUserAbort && gEarnInputAbortReason != "")
            gEarnFail := gEarnInputAbortReason
        if (gEarnFail = "" || gEarnFail = "화면 판독 중단 또는 시간 초과")
            gEarnFail := "수동 종료 정리 미확인. 화면 확인 후 보스 해제 필요"
        EarnLog("끄기 정리 실패: " gEarnFail)
        ShowTooltip("⚠ 수익 자동화 꺼짐: " gEarnFail, 8000)
    }
    ; 이 작업과 입력 잠금은 끝났다. 실패 이유는 남기되 수동 종료용 latch를 AFK 정리까지 영구 차단하지 않게 소비한다.
    gAbort := false
    gEarnUserAbort := false
    gEarnInputAbortReason := ""
    gEarnManualCleanupAttempted := false
    gEarnManualStop := false
    gEarnModeRequest := ""
    if (gEarnIdleEnabled && cleanupOK && !interrupted) {
        gEarnRecovery := ""
        gEarnModeRequest := "apps"
    }
    } finally {
        Critical "Off"
    }
}

; 만재는 알림만 남긴다. 구매·조달을 건너뛸지는 각 작업이 판단하고, 전체 자동화 중단은 사용자가 결정한다.
EarnNotifyStockFull(source, reason) {
    global gEarnSellNotices, gEarnSellNoticeSeen
    gEarnSellNoticeSeen[source] := A_TickCount
    if (gEarnSellNotices.Get(source, "") != reason) {
        gEarnSellNotices[source] := reason
        EarnLog("재고 만재 알림: " reason " · 나머지 작업 계속")
        ShowTooltip("💰 " reason " · 자동화 계속, 중단은 직접", 10000)
    }
    return true
}

; 해당 대상의 비만재 상태를 확인한 소비처만 호출한다. 미확인·다른 사업장 관측에서는 보존한다.
EarnClearStockNotice(source) {
    global gEarnSellNotices
    if (gEarnSellNotices.Has(source)) {
        EarnLog("재고 만재 알림 해제: " gEarnSellNotices[source])
        gEarnSellNotices.Delete(source)
    }
}

; 생산 정지 감지. 1021 03:00~14:48 세션에 접속한 채 벙커(재고 97%·보급 96%)와 나이트클럽 재고가
; 12시간 그대로였는데 아무 알림이 없었다. 생산 중이어야 할 사업장의 판독값이 1시간 넘게 같으면 알린다.
; active=false(만재·보급 없음)는 멈춘 게 정상이므로 기록을 지운다. 반환값은 같은 값이 이어진 ms다.
EarnProductionObserve(source, key, active := true) {
    static seenBySource := Map()
    seen := seenBySource.Get(source, "")
    if (!active) {
        if (IsObject(seen))
            seenBySource.Delete(source)
        return 0
    }
    if (!IsObject(seen) || seen.key != key) {
        if (IsObject(seen) && seen.notified)
            EarnLog("생산 재개 확인: " source)
        seenBySource[source] := {key: key, since: A_TickCount, notified: false}
        return 0
    }
    unchanged := A_TickCount - seen.since
    if (unchanged >= 3600000 && !seen.notified) {
        seen.notified := true
        reason := source " 생산 정지 의심: " Round(unchanged / 60000) "분째 같은 값 (" key ")"
        EarnLog(reason " · 재접속 필요")
        ShowTooltip("⚠ " reason " · 재접속하세요", 15000)
    }
    return unchanged
}

EarnFinishScheduledTask(result) {
    global gEarnDue, gEarnDone, gEarnSoftFails, gEarnNextDue, gEarnHeld, gEarnFailures, config
    task := result.task
    if (result.ok) {
        gEarnSoftFails[task.id] := 0
        if (gEarnFailures.Has(task.id))
            gEarnFailures.Delete(task.id)
        ; 주기는 확인을 시작한 때부터 잰다. 다만 실행·공동 정리 중 이미 지난 예약은 완료 시각으로
        ; 당겨, 그 작업이 과거 due를 계속 쌓으며 그사이 due가 된 다른 작업을 굶기지 않게 한다.
        finishedTick := A_TickCount
        explicitNext := gEarnNextDue.Has(task.id)
        nextDue := explicitNext ? gEarnNextDue.Delete(task.id) : result.startTick + task.every
        ; 앱 확인은 완료부터 설정 간격을 기다린다. MCT의 명시 예약과 시작 기준 주기는 유지한다.
        if (task.id = "safe" || task.id = "staff")
            nextDue := finishedTick + task.every
        ; 벙커의 짧은 상태 관측 예약이 MCT 정리 중 만료됐으면 즉시 재진입하지 않는다.
        if (task.id = "bunker" && explicitNext && nextDue <= finishedTick)
            nextDue := finishedTick + 60000
        gEarnDue[task.id] := Max(finishedTick, nextDue)
        gEarnDone[task.id] += 1
        secondsUntilDue := Floor(Max(0, gEarnDue[task.id] - A_TickCount) / 1000)
        EarnLog("끝: " task.label " (" gEarnDone[task.id] "회째, 다음 " FormatTime(DateAdd(A_Now, secondsUntilDue, "Seconds"), "HH:mm:ss") ")")
        return true
    }
    ; 정리된 화면의 일반 판독 실패는 이 작업만 미룬다. 요청 후 결과가 불명확해도 다음 차례에 다시 읽는다.
    if (gEarnNextDue.Has(task.id))
        gEarnNextDue.Delete(task.id)
    reason := result.reason = "" ? task.label " 확인 실패" : result.reason
    pending := EarnHoldsPending(task.id) ? EarnStateGet("pending_" task.id) : ""
    if (pending != "") {
        reason := reason " (" pending ")"
        gEarnHeld[task.id] := reason
        gEarnFailures[task.id] := {reason: reason, nextTick: 0}
        EarnLog("보류: " task.id " (" task.label ") " reason "; 결과 확인 후 pending 상태 해제 필요, 나머지 작업 계속")
        return false
    }
    {
        n := gEarnSoftFails.Get(task.id, 0) + 1
        gEarnSoftFails[task.id] := n
        ; 실패 뒤 기다리지 않고 다음 tick 에 다시 한다(1019 사용자 지시). 작업이 게임 상태 때문에 정한 대기(retryIn)만 따른다.
        retryIn := result.retryIn
        gEarnDue[task.id] := A_TickCount + retryIn
        gEarnFailures[task.id] := {reason: reason, nextTick: gEarnDue[task.id]}
        EarnLog("실패: " task.id " (" task.label ") " reason " → " (retryIn ? Round(retryIn / 1000) "초 뒤" : "바로") " 다시 (연속 " n "회), 나머지 작업 계속")
        ShowTooltip("💰 " task.label ": " (retryIn ? Round(retryIn / 1000) "초 뒤" : "바로") " 다시", 4000)
    }
    return false
}

EarnStopAfterFailure(why) {
    global gEarnFail, config, afkOn
    ; 실패: 전부 끄고 AFK 방지는 켜 둔다
    SetEarner(false, why)
    gEarnFail := why
    if (config["Features"]["AntiAFK"] && !afkOn)
        SetAntiAFK(true)
    ShowTooltip("⚠ 수익 자동화 멈춤: " why, 8000)
}

; 물리 키보드/마우스 입력만 본다. 자동 클릭·카메라 입력은 유휴 시간을 초기화하지 않는다.
EarnInputGuardStart() {
    global gEarnGuardArmed, gEarnGuardStartedTick, gEarnInputAbortReason
    gEarnInputAbortReason := ""
    gEarnGuardStartedTick := A_TickCount
    gEarnGuardArmed := true
    SetTimer(EarnInputWatch, 25)
}

EarnInputGuardStop() {
    global gEarnGuardArmed
    gEarnGuardArmed := false
    SetTimer(EarnInputWatch, 0)
    DiscordHUDMCTStop()
}

EarnInputWatch() {
    EarnInputAllowed()
}

EarnInputAllowed() {
    global gEarnGuardArmed, gEarnGuardStartedTick, gAbort, gEarnRetryIn, gEarnGamePID, gEarnUserAbort, gEarnInputAbortReason, gEarnMode
    if (!gEarnGuardArmed)
        return !gAbort
    if (!gAbort && (!gEarnGamePID || EarnGamePID() != gEarnGamePID)) {
        gAbort := true
        gEarnRetryIn := 0
        ReleaseHeldKeys()
        DiscordHUDMCTStop()
        EarnFail("GTA 종료 또는 재시작으로 중단. 현재 화면을 확인하고 다시 켜기")
    } else if (!gAbort && gEarnMode = "apps" && EarnOtherMacroBusy()) {
        gAbort := true
        gEarnUserAbort := true
        gEarnRetryIn := 0
        gEarnInputAbortReason := "다른 매크로 시작으로 유휴 앱 중단"
        ReleaseHeldKeys()
        DiscordHUDMCTStop()
        EarnFail(gEarnInputAbortReason)
    } else if (!gAbort) {
        elapsedMs := A_TickCount - gEarnGuardStartedTick
        physicalIdleMs := A_TimeIdlePhysical
        activeHwnd := IsGTAActive()
        physicalInput := elapsedMs > 0 && physicalIdleMs < elapsedMs
        if (!physicalInput && activeHwnd)
            return true
        ; 긴 OCR 호출 중 발생한 입력도 시작 이후 경과 시간과 비교해 감지한다.
        ; 끄지 않는다. EarnTick 이 손을 뗀 뒤 바로 다시 한다.
        gAbort := true
        gEarnUserAbort := true
        gEarnRetryIn := 0
        gEarnInputAbortReason := physicalInput ? (activeHwnd ? "사용자 물리 입력으로 중단" : "사용자 물리 입력 및 GTA 포커스 판정 실패로 중단")
            : "GTA 포커스 판정 실패로 중단"
        ; 창 메타데이터 조회가 실패하거나 늦어져도 키 해제와 중단은 먼저 끝낸다.
        ReleaseHeldKeys()
        DiscordHUDMCTStop()
        foreground := "unknown"
        try foreground := DllCall("GetForegroundWindow", "ptr")
        EarnFail(gEarnInputAbortReason)
        try EarnInputAbortEvidence(physicalInput, activeHwnd, physicalIdleMs, elapsedMs, foreground)
    }
    if (gAbort)
        DiscordHUDMCTStop()
    return !gAbort
}

EarnInputAbortEvidence(physicalInput, activeHwnd, idleMs, elapsedMs, foreground) {
    global GTA_WIN, gEarnGamePID
    gameHwnd := "unknown"
    try gameHwnd := WinExist(GTA_WIN)
    EarnLog("[input-abort] physical=" (physicalInput ? 1 : 0) " focus=" (activeHwnd ? 0 : 1)
        " idle_ms=" idleMs " elapsed_ms=" elapsedMs " winactive=" activeHwnd " expected_game_pid=" gEarnGamePID
        " foreground={" EarnInputWindowEvidence(foreground) "} game={" EarnInputWindowEvidence(gameHwnd) "}")
}

EarnInputWindowEvidence(hwnd) {
    pid := "unknown", exe := "unknown", title := "unknown"
    if (IsInteger(hwnd) && hwnd) {
        try pid := WinGetPID("ahk_id " hwnd)
        try exe := WinGetProcessName("ahk_id " hwnd)
        try title := WinGetTitle("ahk_id " hwnd)
    }
    return "hwnd=" hwnd " pid=" pid " exe=" EarnInputEvidenceText(exe) " title=" EarnInputEvidenceText(title)
}

EarnInputEvidenceText(value) {
    ; 제목의 개행이나 따옴표가 하나의 진단을 여러 로그처럼 보이게 하지 않는다.
    return '"' StrReplace(StrReplace(StrReplace(StrReplace(SubStr(value, 1, 512), "\", "\\"), '"', '\"'), "`r", "\r"), "`n", "\n") '"'
}

EarnGamePID() {
    global GTA_WIN
    hwnd := WinExist(GTA_WIN)
    if (!hwnd)
        return 0
    try return WinGetPID("ahk_id " hwnd)
    catch
        return 0
}

; GUI 수신기는 이름의 존재로 배타화한다. 이 이름을 작업 동안 예약해 새 수신기 시작과의 경합도 막는다.
; 실제 검사는 별도 이름을 넘겨 현재 게임 입력 잠금에 닿지 않는다.
EarnInputLockAcquire(macroName := "Local\GtaMacroInput", guiName := "Local\GtaGuiInput") {
    guiHandle := DllCall("CreateMutexW", "ptr", 0, "int", 0, "str", guiName, "ptr")
    existed := A_LastError = 183
    if (!guiHandle)
        throw Error("GUI 입력 잠금을 만들지 못함")
    if (existed) {
        DllCall("CloseHandle", "ptr", guiHandle)
        return 0
    }
    macroHandle := 0
    try {
        macroHandle := DllCall("CreateMutexW", "ptr", 0, "int", 0, "str", macroName, "ptr")
        if (!macroHandle)
            throw Error("매크로 입력 잠금을 만들지 못함")
        acquired := DllCall("WaitForSingleObject", "ptr", macroHandle, "uint", 0, "uint")
        if (acquired = 0 || acquired = 0x80)
            return {macro: macroHandle, gui: guiHandle}
        if (acquired != 0x102)
            throw Error("매크로 입력 잠금 상태를 확인하지 못함")
    } catch as e {
        if (macroHandle)
            DllCall("CloseHandle", "ptr", macroHandle)
        DllCall("CloseHandle", "ptr", guiHandle)
        throw e
    }
    DllCall("CloseHandle", "ptr", macroHandle)
    DllCall("CloseHandle", "ptr", guiHandle)
    return 0
}

EarnInputLockRelease(inputLock) {
    try {
        DllCall("ReleaseMutex", "ptr", inputLock.macro)
    } finally {
        DllCall("CloseHandle", "ptr", inputLock.macro)
        DllCall("CloseHandle", "ptr", inputLock.gui)
    }
}

; 다른 매크로가 게임에 키를 보내는 중이면 true. 작텔(Alt+F4·MC·스팀 봇)은 IsTeleportRunning 이 묶어서 본다
EarnOtherMacroBusy() {
    global clawLoopRunning, gMenuBusy, gAFKBusy, gEarnMode, cayoTimerRunning
    return (IsSet(clawLoopRunning) && clawLoopRunning) || (IsSet(gMenuBusy) && gMenuBusy)
        || (IsSet(gAFKBusy) && gAFKBusy)
        || IsTeleportRunning() || AnyInputToggleOn()
        || (gEarnMode = "apps" && IsSet(cayoTimerRunning) && cayoTimerRunning)
}

; 오버레이·설정 창 한 줄 상태
EarnStatusText() {
    global gEarnOn, gEarnMode
    text := EarnStatusDetail()
    scope := gEarnOn ? EarnScopeLabel() : ""
    return text = "" || scope = "" ? text : scope " · " text
}

EarnStatusDetail() {
    global gEarnOn, gEarnDue, gEarnTasks, gEarnCurrent, gEarnFail, gEarnHeld, gEarnRecovery, gEarnManualStop, config
    if (gEarnManualStop)
        return "수익: 끄는 중 · MCT 정리와 CEO 해제"
    if (!gEarnOn)
        return gEarnFail = "" ? "" : "수익 멈춤: " gEarnFail
    if (gEarnCurrent != "")
        return "수익: " gEarnCurrent " 진행 중"
    if (IsObject(gEarnRecovery))
        return "수익: " gEarnRecovery.task.label " 정리 복구 대기 " Max(0, Ceil((gEarnRecovery.nextTick - A_TickCount) / 1000)) "초"
            . (gEarnRecovery.attempts >= 20 ? " · " gEarnRecovery.attempts "번 실패, 화면 확인 필요" : "")
    nextLabel := "", nextIn := 0
    for t in gEarnTasks {
        if (!t.on || !EarnTaskAllowed(t.id) || gEarnHeld.Has(t.id))
            continue
        left := gEarnDue[t.id] - A_TickCount
        if (nextLabel = "" || left < nextIn)
            nextLabel := t.label, nextIn := left
    }
    if (nextLabel = "")
        return gEarnHeld.Count ? "수익: 결과 확인 필요 " gEarnHeld.Count "개 보류" : "수익: 켜진 작업 없음"
    if (nextIn <= 0) {
        if (!IsGTAActive())
            return "수익: GTA 포커스 대기"
        idleLeft := config["Settings"]["EarnUserIdleSec"] * 1000 - A_TimeIdlePhysical
        if (idleLeft > 0)
            return "수익: 입력 안정 대기 " Ceil(idleLeft / 1000) "초"
        if (EarnOtherMacroBusy())
            return "수익: 다른 매크로 종료 대기"
        return "수익: " nextLabel " 시작 대기"
    }
    sec := Max(0, Ceil(nextIn / 1000))
    return "수익: 다음 " nextLabel " " Format("{:d}:{:02d}", sec // 60, Mod(sec, 60)) " 뒤"
}
