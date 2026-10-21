; === 단축키 관리 모듈 ===
; 액션 표 한 줄 + Config.ini [Hotkeys] 한 줄로 기능이 붙는다. 액션의 속성:
;   id      : [Hotkeys] 의 키 이름
;   label   : 도움말·툴팁에 보이는 이름
;   fn      : 실행할 함수
;   feature : [Features] 플래그 이름. 0 이면 등록하지 않는다 (없으면 항상 등록)
;   confirm : true 면 ConfirmWindowMs 안에 두 번 눌러야 실행 (세션 이동처럼 되돌리기 어려운 것)
;   global  : true 면 게임 밖에서도 잡는다 (종료만)
;   state   : 도움말에 붙일 현재 상태 문자열을 돌려주는 함수
; 게임 키는 전부 GTA 창이 앞일 때만 잡힌다. 밖에서는 F키·넘패드가 원래대로 동작한다.
global gActions := []
global gKeyTable := Map()   ; 등록된 키 -> 액션 id (도움말·중복 검사)
global gArmed := Map()      ; confirm 액션의 첫 번째 누름 시각

; NumLock 이 꺼지면 넘패드 숫자가 이 이름으로 들어오므로 둘 다 등록한다. NumpadDiv·NumpadMult 는 영향이 없다.
global NUMLOCK_ALIAS := Map("Numpad0", "NumpadIns", "Numpad1", "NumpadEnd", "Numpad2", "NumpadDown",
    "Numpad3", "NumpadPgDn", "Numpad4", "NumpadLeft", "Numpad5", "NumpadClear", "Numpad6", "NumpadRight",
    "Numpad7", "NumpadHome", "Numpad8", "NumpadUp", "Numpad9", "NumpadPgUp", "NumpadDot", "NumpadDel")

; * (수식어 무시) 를 붙이지 않는 키. F4 는 Alt+F4(게임 종료)가 그대로 통과해야 하고,
; F5 는 gta-turbo.ps1 이 보내는 Ctrl+Shift+F5 를 가로채면 안 되며, Pause 는 Ctrl+Pause(Break)를 남겨 둔다.
global NO_STAR_KEYS := Map("F4", 1, "F5", 1, "Pause", 1)

RegisterActions() {
    global gActions
    gActions := []
    gActions.Push({id: "ClawAttempt", label: "인형 1판", fn: (*) => ClawAttempt(), feature: "ClawMachine"})
    gActions.Push({id: "ClawLoop", label: "인형 반복", fn: (*) => ToggleClawLoop(), feature: "ClawMachine", state: (*) => clawLoopRunning ? "켜짐 " clawTries "판" : ""})
    gActions.Push({id: "AntiAFK", label: "AFK 방지", fn: (*) => ToggleAntiAFK(), feature: "AntiAFK", state: (*) => afkOn ? "켜짐" : "꺼짐"})
    gActions.Push({id: "InviteOnlySession", label: "초대 전용 세션", fn: (*) => (IsSet(gEarnBusy) && gEarnBusy) ? ShowTooltip("초대 전용 세션: 수익 자동화가 진행 중", 1500) : JoinInviteOnlySession(), feature: "SessionSwitch", confirm: true})
    gActions.Push({id: "Walk", label: "걷기", fn: (*) => ToggleWalk(), feature: "Movement", state: (*) => wRunning ? "켜짐" : ""})
    gActions.Push({id: "Run", label: "달리기", fn: (*) => ToggleRun(), feature: "Movement", state: (*) => shiftWRunning ? "켜짐" : ""})
    gActions.Push({id: "AutoClick", label: "자동 클릭", fn: (*) => ToggleAutoClick(), feature: "AutoClick", state: (*) => clickRunning ? "켜짐" : ""})
    gActions.Push({id: "WalkCtrl", label: "벨럼", fn: (*) => ToggleVellumDriving(), feature: "Movement", state: (*) => vellumDrivingRunning ? "켜짐" : ""})
    gActions.Push({id: "CayoPericoTimer", label: "카요 타이머", fn: (*) => ToggleCayoPericoTimer(), feature: "Timer", state: (*) => cayoTimerRunning ? "켜짐" : ""})
    gActions.Push({id: "Snack", label: "스낵", fn: (*) => EatSnack(), feature: "MenuMacros"})
    gActions.Push({id: "SaleAlert", label: "판매 차례 알림", fn: (*) => ToggleSaleAlert(), state: (*) => gSaleOn ? "켜짐" : ""})
    gActions.Push({id: "Earner", label: "수익 자동화", fn: (*) => ToggleEarner(), feature: "Earner", confirm: true, state: (*) => gEarnOn ? (gEarnMode = "apps" ? "유휴 앱 자동" : "전체 켜짐") : ""})
    gActions.Push({id: "CasinoVpn", label: "카지노 VPN 실행", fn: (*) => StartCasinoVpn(), feature: "CasinoVpn", global: true, confirm: true, state: (*) => gCasinoVpnOn ? "켜짐" : ""})
    gActions.Push({id: "Help", label: "도움말", fn: (*) => HelpKey()})   ; 두 번 누르면 설정 창
    gActions.Push({id: "StopAll", label: "전체 멈춤", fn: (*) => StopAll("hotkey")})
    gActions.Push({id: "Exit", label: "종료", fn: (*) => ExitAll(), global: true, confirm: true})   ; 전역이라 노트북 Fn+P/Fn+B(Pause) 오타로 꺼지지 않게 두 번 누름
    gActions.Push({id: "TeleportMC1", label: "CEO 재등록 텔레포트", fn: (*) => TeleportMC("CEO"), feature: "Teleport", confirm: true})
    gActions.Push({id: "TeleportMC2", label: "MC 재등록 텔레포트", fn: (*) => TeleportMC("MC"), feature: "Teleport", confirm: true})
    gActions.Push({id: "TeleportAltF4", label: "작텔(Alt+F4)", fn: (*) => TeleportAltF4(), feature: "AltF4Teleport", confirm: true})
    gActions.Push({id: "BotWarp", label: "작텔(스팀 봇)", fn: (*) => TeleportBotWarp(), feature: "BotWarp", confirm: true})
    gActions.Push({id: "FriendWarp", label: "친구 텔(-Atra_Mora-)", fn: (*) => ExecuteFriendWarp(), feature: "FriendWarp", confirm: true})
    gActions.Push({id: "CasinoFingerprint", label: "지문 해킹", fn: (*) => ExecuteCasinoFingerprint(), feature: "CasinoFingerprint"})
}

SetupHotkeys() {
    global config, gActions, gKeyTable, GTA_WIN, NUMLOCK_ALIAS, NO_STAR_KEYS

    RegisterActions()
    gKeyTable := Map()
    for action in gActions {
        if (action.HasProp("feature") && !config["Features"].Get(action.feature, 0))
            continue
        ; 쉼표로 키를 여러 개 둘 수 있다 (예: ClawLoop=NumpadMult,F4)
        for key in StrSplit(config["Hotkeys"].Get(action.id, ""), ",", " `t") {
            if (key = "")
                continue
            for name in (NUMLOCK_ALIAS.Has(key) ? [key, NUMLOCK_ALIAS[key]] : [key]) {
                if (gKeyTable.Has(name)) {
                    MacroLog("hotkey", "중복 " name ": " gKeyTable[name] " 가 이미 써서 " action.id " 는 건너뜀")
                    continue
                }
                if (action.HasProp("global") && action.global)
                    HotIf()
                else
                    HotIfWinActive(GTA_WIN)
                prefix := NO_STAR_KEYS.Has(name) ? "$" : "*$"
                try {
                    Hotkey(prefix name, Dispatch.Bind(action, name))
                    gKeyTable[name] := action.id
                    HotkeyAudit(action, name, "registered")
                    if (action.id = "Earner") {
                        HotIf((*) => !WinActive(GTA_WIN))
                        Hotkey("~*$" name, IgnoredEarnerKey.Bind(action, name))
                    }
                } catch as e {
                    MacroLog("hotkey", "등록 실패 " action.id "=" name " : " e.Message)
                }
            }
        }
    }
    HotIf()
}

; Windows 는 저수준 키보드 훅이 콜백에 늦으면 말없이 떼어 버리는데 AHK 는 그걸 모른 채 살아 있다고 본다.
; 1010 19:21 에 띄운 매크로가 3시간 동안 F9 를 한 번도 받지 못했다(hotkey 기록에 received 없음). 그래서 1분마다
; 강제로 다시 붙인다(Force). 누른 이동 키의 물리 상태 추적이 끊기지 않게 키를 놓은 뒤로 미룬다.
KeyHookWatchdog() {
    for vk in [0x57, 0xA0, 0xA1]
        if (DllCall("GetAsyncKeyState", "int", vk, "short") & 0x8000)
            return
    InstallKeybdHook(true, true)
}

; 핫키 스레드 진입점. confirm 액션은 ConfirmWindowMs 안에 두 번 눌러야 실행한다.
Dispatch(action, key, *) {
    global gArmed, config

    HotkeyAudit(action, key, "received")
    if (action.HasProp("confirm") && action.confirm) {
        windowMs := config["Settings"]["ConfirmWindowMs"]
        if (!(gArmed.Has(action.id) && A_TickCount - gArmed[action.id] <= windowMs)) {
            gArmed[action.id] := A_TickCount
            HotkeyAudit(action, key, "confirmation-wait", "window_ms=" windowMs)
            SetTimer(ExpireArmedAction.Bind(action, key, gArmed[action.id]), -windowMs)
            ShowTooltip(action.label ": " Round(windowMs / 1000) "초 안에 한 번 더 누르면 실행", windowMs)
            ; 키를 누르고 있어서 생기는 자동 반복이 두 번째 누름으로 세지지 않게 뗄 때까지 기다린다.
            KeyWait(key, "T" (windowMs / 1000))
            if (GetKeyState(key, "P") && gArmed.Has(action.id)) {
                gArmed.Delete(action.id)
                HotkeyAudit(action, key, "confirmation-cancelled", "key-held")
            }
            return
        }
        HotkeyAudit(action, key, "confirmed", "elapsed_ms=" (A_TickCount - gArmed[action.id]))
        gArmed.Delete(action.id)
    }

    HotkeyAudit(action, key, "action-start")
    try {
        action.fn.Call()
        HotkeyAudit(action, key, "action-return")
    } catch as failure {
        HotkeyAudit(action, key, "action-error", failure.Message)
        throw failure
    }
    ; 토글이 자동 반복으로 켜졌다 바로 꺼지지 않게 뗄 때까지 기다린다 (같은 핫키의 추가 누름은 그동안 무시된다).
    KeyWait(key, "T2")
}

ExpireArmedAction(action, key, started) {
    global gArmed
    if (gArmed.Has(action.id) && gArmed[action.id] = started) {
        gArmed.Delete(action.id)
        HotkeyAudit(action, key, "confirmation-expired")
    }
}

IgnoredEarnerKey(action, key, *) {
    global gArmed
    if (gArmed.Has(action.id))
        gArmed.Delete(action.id)
    HotkeyAudit(action, key, "ignored", "GTA-not-active; key-passed-through")
    KeyWait(key, "T2")
}

HotkeyAudit(action, key, event, detail := "") {
    ; Logging failures must not prevent the requested action or key release.
    try {
        foreground := "unknown"
        try foreground := WinGetProcessName("A")
        MacroLog("hotkey", action.id " key=" key " event=" event
            " pid=" DllCall("GetCurrentProcessId") " foreground=" foreground
            (detail = "" ? "" : " " detail))
    }
}

; 액션 id 에 등록된 키를 표시용 이름으로 돌려준다. 없으면 "(키 없음)".
KeyLabelFor(id) {
    global config, gKeyTable
    names := ""
    for key in StrSplit(config["Hotkeys"].Get(id, ""), ",", " `t") {
        if (key != "" && gKeyTable.Has(key) && gKeyTable[key] = id)
            names .= (names = "" ? "" : ",") DisplayKey(key)
    }
    return names = "" ? "(키 없음)" : names
}

DisplayKey(key) {
    static names := Map("NumpadDiv", "Num/", "NumpadMult", "Num*", "NumpadAdd", "Num+", "NumpadSub", "Num-",
        "NumpadDot", "Num.", "NumpadEnter", "NumEnter")
    if (names.Has(key))
        return names[key]
    if (SubStr(key, 1, 6) = "Numpad" && StrLen(key) = 7)
        return "Num" SubStr(key, 7)
    return key
}

SetupTrayMenu() {
    A_IconTip := "GTA 매크로"
    tray := A_TrayMenu
    tray.Insert("1&", "종료", (*) => ExitAll())
    tray.Insert("1&", "전체 멈춤", (*) => StopAll("tray"))
    tray.Insert("1&", "AFK 방지 켜기/끄기", (*) => ToggleAntiAFK())
    tray.Insert("1&", "단축키 보기", (*) => ShowHelp())
    tray.Insert("1&", "설정 창 열기", (*) => OpenPanel())
    tray.Insert("1&", "외출 저부하 끄기 (일반 복귀)", (*) => SetAwayMode(false))
    tray.Insert("1&", "외출 저부하 켜기 (30 FPS)", (*) => SetAwayMode(true))
    tray.Insert("8&")
    tray.Default := "설정 창 열기"   ; 트레이 아이콘 더블클릭으로도 열린다
    CpuBoostUpdateTray()
}
