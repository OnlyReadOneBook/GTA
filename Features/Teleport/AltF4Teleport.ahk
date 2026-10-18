; === Alt+F4 작텔 (잡 워프) ===
; 2026-09-26 Enhanced 실측: 수동 1회(에이전시 → Del Perro Pier) + 매크로 1회(Del Perro → Chiliad "Branching Out") 성공.
;   매크로가 32초 만에 No 를 눌렀던 1회는 작업 로비로 들어가 실패(로비는 Backspace → Yes 로 빠져나오면 원래 자리).
; 출처: Ragnarson70 "How to JOB WARP within MISSIONS [Workaround] 2025 Agents of Sabotage 1.70" 의 일반(casual) 방식.
;
; 쓰는 법: 일시정지 지도(P → MAP, 실내면 CapsLock 으로 전체 지도)에서 가고 싶은 곳의 작업 블립을 골라
;          화면 아래에 "Start Job (Space)" 가 보이는 상태에서 이 단축키를 두 번 누른다.
; 순서: Space(작업 시작) → Enter(CONFIRM "Are you sure you want to start this Job?")
;       → 곧바로 Alt+F4 (작업 메뉴가 뜨기 전에) → "Quit ... Grand Theft Auto V?" 창에서 로딩 스피너가 사라질 때까지 대기
;       → Backspace = No → 작업 위치의 프리모드에 스폰.
; 안전: 종료 확인창에서 Enter(Yes)는 절대 보내지 않는다. Esc 도 쓰지 않는다(Backspace 가 No 로 먹힘).
;       대기 중 End(전체 멈춤)를 누르면 Backspace 를 보내지 않고 멈춘다(창은 직접 No 로 닫는다).
; 사전 설정: Online → Options → Matchmaking = Closed. 상호작용 메뉴 → Preferences → Map Blip Options → Jobs 표시.

; 성공(No 까지 보냄)이면 true. F11 두 단계(QuickJoinPrep.ahk)가 이 값으로 준비 상태를 푼다
ExecuteAltF4Teleport() {
    global config, altF4Running, gAbort, gJobWarpStart, gJobWarpMinMs

    ; 스팀 봇 작텔이 도는 중에 Alt+F4 를 보내면 그쪽 Enter 가 종료 확인창에 들어갈 수 있다
    if (!IsGTAActive() || IsTeleportRunning())
        return
    if (IsSet(gEarnBusy) && gEarnBusy) {
        ShowTooltip("작텔: 수익 자동화가 진행 중", 1500)
        return
    }

    altF4Running := true
    gAbort := false
    s := config["Settings"]
    ok := false
    try {
        ShowAltF4Message("🚀 작텔: 작업 시작", 1000)
        PressKey("Space")
        if (!WaitAbortable(s["JobWarpStartToConfirmMs"]))
            return
        PressKey("Enter")
        Sleep(s["JobWarpConfirmToAltF4Ms"])
        if (gAbort || !IsGTAActive())
            return
        Send("{Blind}{Alt down}{F4}{Alt up}")
        MacroLog("jobwarp", "alt+f4 sent")

        ; 종료 확인창 뒤에서 작업이 로딩된다. 오른쪽 아래 스피너가 사라지고 "No [Esc]  Yes [↵]" 안내가 뜬 뒤에 No 를 눌러야
        ; 작업 위치의 프리모드로 나온다. 안내는 약 20초에 뜨지만 뒤에서 작업이 튕길 때(영상 표현: "소리가 끊길 때")까지 더 기다려야 한다.
        ; 0926 실측: 32초에 No → 작업 로비(실패), 60초에 No → 성공. 그래서 JobWarpMinWaitMs(기본 60초)가 지난 뒤 안내가 보이면 No.
        waitMs := s["JobWarpQuitWaitMs"]
        start := A_TickCount
        ready := false
        ; 대기 시간은 오버레이가 "작텔 대기 N/60초" 로 보여 준다. 오버레이가 꺼져 있으면 예전처럼 왼쪽 위 툴팁으로 보인다.
        gJobWarpStart := start
        gJobWarpMinMs := s["JobWarpMinWaitMs"]
        while (A_TickCount - start < waitMs) {
            if (gAbort) {
                ShowAltF4Message("⏹ 작텔 중단: 종료 확인창은 직접 No(Backspace)로 닫으세요", 4000)
                MacroLog("jobwarp", "aborted during quit wait")
                return
            }
            if (!IsGTAActive()) {
                MacroLog("jobwarp", "focus lost during quit wait")
                return
            }
            if (A_TickCount - start > s["JobWarpMinWaitMs"] && QuitPromptReady()) {
                ready := true
                break
            }
            ToolTip("⏳ 작텔: 종료창 로딩 대기 " Round((A_TickCount - start) / 1000) "초 (End: 중단)", 20, 20)
            Sleep(500)
        }
        ToolTip()
        if (!ready) {
            ShowAltF4Message("⚠ 작텔: No/Yes 안내를 못 찾음. 종료 확인창은 직접 No(Backspace)로 닫으세요", 5000)
            MacroLog("jobwarp", "prompt not detected within " waitMs "ms")
            return
        }
        MacroLog("jobwarp", "prompt ready after " (A_TickCount - start) "ms")
        if (!WaitAbortable(s["JobWarpAfterPromptMs"]))
            return
        PressKey("Backspace")   ; No
        ok := true
        ShowAltF4Message("✅ 작텔 완료 (작업 위치 확인)", 2500)
    } finally {
        ToolTip()
        gJobWarpStart := 0
        altF4Running := false
        MacroLog("jobwarp", ok ? "done" : "stopped")
    }
    return ok
}

; 종료 확인창 오른쪽 아래의 "No [Esc]" 키캡(흰 네모)이 보이면 true. 로딩 중에는 그 자리가 검고 스피너는 더 오른쪽(↵ 자리)에 있다.
; 1920x1080 실측 위치: Esc 키캡 x≈1756-1784, y≈1036-1056 → 창 크기 비율로 잡는다.
QuitPromptReady() {
    hwnd := IsGTAActive()
    if (!hwnd)
        return false
    WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
    CoordMode("Pixel", "Screen")
    x1 := cx + Round(cw * 0.905), x2 := cx + Round(cw * 0.935)
    y1 := cy + Round(ch * 0.955), y2 := cy + Round(ch * 0.985)
    return PixelSearch(&fx, &fy, x1, y1, x2, y2, 0xFFFFFF, 30)
}

; ms 만큼 기다리되 전체 멈춤·포커스 이탈이면 false
WaitAbortable(ms) {
    global gAbort
    start := A_TickCount
    while (A_TickCount - start < ms) {
        if (gAbort || !IsGTAActive())
            return false
        Sleep(50)
    }
    return !gAbort && IsGTAActive()
}
