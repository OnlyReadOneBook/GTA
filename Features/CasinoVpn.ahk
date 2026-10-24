; === 카지노 VPN (자동) ===
; 한국 IP 에서는 다이아몬드 카지노 도박이 막힌다. 지역 판정은 런처·게임 부팅 때 이뤄진다고 알려져 있어(Sportskeeda, 공식 확인 없음)
; GTA 가 어떤 경로(Steam·바탕화면·Rockstar 런처)로 켜지든 PlayGTAV/GTA5_Enhanced 가 나타나는 순간 VPN(Proton 무료 NL, WireGuard) 을 켜고,
; 게임 화면에 체력 막대(HUD) 가 2초 간격 두 번 연속 보이면(온라인 세션 로딩이 끝남) CasinoVpnHoldSec 초 뒤에 끈다.
; 스토리 모드에도 같은 HUD 가 있어 스토리로 먼저 들어가면 그때 꺼진다(온라인 직행 설정 전제). 시간 상한은 없다(온라인 접속이 늦어도 끊지 않는다). 게임이 먼저 꺼지면 바로 끈다.
; WireGuard 는 관리자 권한이 필요해 예약 작업 GTA-VPN-On/Off(가장 높은 권한) 로 부른다. 설정 파일은 vpn\gtanl.conf (깃 제외).
; 매크로(Main) 와 따로 CasinoVpnWatch.ahk 가 시작 프로그램에서 돌며 이 파일을 쓴다. 시점별 기록은 %TEMP%\gta-casino-vpn.log.
global gCasinoVpnOn := false, gCasinoVpnStart := 0, gCasinoVpnGtaSeen := 0, gCasinoVpnPrevRunning := false
global gCasinoVpnHoldSec := 5, gCasinoVpnHudStreak := 0, gCasinoVpnHudCheck := 0

CasinoVpnLog(msg) {
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " msg "`n", A_Temp "\gta-casino-vpn.log", "UTF-8")
}

CasinoVpnCountry() {
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(3000, 3000, 3000, 3000)
        req.Open("GET", "https://ipinfo.io/country", false)
        req.Send()
        return Trim(req.ResponseText, " `r`n")
    }
    return ""
}

CasinoVpnGameRunning() => ProcessExist("PlayGTAV.exe") || ProcessExist("GTA5_Enhanced.exe")

StartCasinoVpnWatch(holdSec := 5) {
    global gCasinoVpnHoldSec := holdSec, gCasinoVpnPrevRunning := CasinoVpnGameRunning()
    ; 이미 켜진 게임은 판정이 끝났으니 건드리지 않는다. 다음 실행부터 적용된다.
    CasinoVpnLog("감시 시작 (hold " holdSec "s, 게임 " (gCasinoVpnPrevRunning ? "실행 중" : "꺼짐") ")")
    OnExit((*) => (gCasinoVpnOn ? StopCasinoVpn("감시 종료") : 0, 0))
    SetTimer(CasinoVpnTick, 250)
}

CasinoVpnTick() {
    global gCasinoVpnOn, gCasinoVpnStart, gCasinoVpnGtaSeen, gCasinoVpnPrevRunning, gCasinoVpnHudStreak, gCasinoVpnHudCheck
    running := CasinoVpnGameRunning()
    if (running && !gCasinoVpnPrevRunning) {
        gCasinoVpnOn := true, gCasinoVpnStart := A_TickCount, gCasinoVpnGtaSeen := 0, gCasinoVpnHudStreak := 0
        RunWait('schtasks /run /tn GTA-VPN-On', , "Hide")
        CasinoVpnLog("게임 실행 감지 → VPN 켬")
        SetTimer(() => CasinoVpnLog("국가 " CasinoVpnCountry() " (+" Round((A_TickCount - gCasinoVpnStart) / 1000) "s)"), -3000)
    }
    gCasinoVpnPrevRunning := running
    if (!gCasinoVpnOn)
        return
    if (!running)
        return StopCasinoVpn("게임 종료")
    if (!gCasinoVpnGtaSeen && ProcessExist("GTA5_Enhanced.exe")) {
        gCasinoVpnGtaSeen := A_TickCount
        CasinoVpnLog("GTA5_Enhanced 뜸 (+" Round((A_TickCount - gCasinoVpnStart) / 1000) "s)")
    }
    ; 체력 막대는 2초 간격으로 본다. 두 번 연속 보인 시각부터 hold 를 센다(0c13557 은 판정 함수만 두고 부르지 않아 exe 뜬 지 5초 만에 껐다).
    if (gCasinoVpnGtaSeen && gCasinoVpnHudStreak < 2 && A_TickCount - gCasinoVpnHudCheck >= 2000) {
        gCasinoVpnHudCheck := A_TickCount
        gCasinoVpnHudStreak := CasinoVpnHudVisible() ? gCasinoVpnHudStreak + 1 : 0
        if (gCasinoVpnHudStreak >= 2)
            CasinoVpnLog("HUD 확인 (+" Round((A_TickCount - gCasinoVpnStart) / 1000) "s)")
    }
    if (gCasinoVpnHudStreak >= 2 && A_TickCount - gCasinoVpnHudCheck >= gCasinoVpnHoldSec * 1000)
        return StopCasinoVpn("HUD 확인 뒤 " gCasinoVpnHoldSec "s")
}

StopCasinoVpn(reason := "") {
    global gCasinoVpnOn, gCasinoVpnStart
    RunWait('schtasks /run /tn GTA-VPN-Off', , "Hide")
    if (gCasinoVpnOn)
        CasinoVpnLog("VPN 끔 (" reason ", 총 " Round((A_TickCount - gCasinoVpnStart) / 1000) "s)")
    gCasinoVpnOn := false
}

; Core\Screen.ahk HealthHudVisible 와 같은 판정(미니맵 밑 초록 체력 막대, 1920x1080). 감시 스크립트는 매크로 코어를 싣지 않아 따로 둔다.
; 게임 창이 앞에 없으면 화면을 읽을 수 없어 false 로 보고 계속 기다린다.
CasinoVpnHudVisible() {
    hwnd := WinActive("Grand Theft Auto V ahk_exe GTA5_Enhanced.exe")
    if (!hwnd)
        return false
    previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        if (cw != 1920 || ch != 1080)
            return false
        CoordMode("Pixel", "Screen")
        green := 0
        Loop 32 {
            c := PixelGetColor(cx + 40 + (A_Index-1)*4, cy + 1053)
            r := (c >> 16) & 255, g := (c >> 8) & 255, b := c & 255
            green += g >= 100 && g-r >= 40 && g-b >= 40 && Abs(r-b) <= 25
        }
        return green * 4 >= 32 * 3
    } catch {
        return false
    } finally {
        if (previous)
            DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
    }
}