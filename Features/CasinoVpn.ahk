; === 카지노 VPN (자동) ===
; 한국 IP 에서는 다이아몬드 카지노 도박이 막힌다. 지역 판정은 런처·게임 부팅 때 이뤄진다고 알려져 있어(Sportskeeda, 공식 확인 없음)
; GTA 가 어떤 경로(Steam·바탕화면·Rockstar 런처)로 켜지든 PlayGTAV/GTA5_Enhanced 가 나타나는 순간 VPN(Proton 무료 NL, WireGuard) 을 켜고,
; GTA5_Enhanced.exe 가 뜬 뒤 CasinoVpnHoldSec 초가 지나면 끈다. 어떤 경우에도 CasinoVpnMaxSec 를 넘기지 않고, 게임이 먼저 꺼지면 바로 끈다.
; WireGuard 는 관리자 권한이 필요해 예약 작업 GTA-VPN-On/Off(가장 높은 권한) 로 부른다. 설정 파일은 vpn\gtanl.conf (깃 제외).
; 매크로(Main) 와 따로 CasinoVpnWatch.ahk 가 시작 프로그램에서 돌며 이 파일을 쓴다. 시점별 기록은 %TEMP%\gta-casino-vpn.log.
global gCasinoVpnOn := false, gCasinoVpnStart := 0, gCasinoVpnGtaSeen := 0, gCasinoVpnPrevRunning := false
global gCasinoVpnHoldSec := 90, gCasinoVpnMaxSec := 600

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

StartCasinoVpnWatch(holdSec := 90, maxSec := 600) {
    global gCasinoVpnHoldSec := holdSec, gCasinoVpnMaxSec := maxSec, gCasinoVpnPrevRunning := CasinoVpnGameRunning()
    ; 이미 켜진 게임은 판정이 끝났으니 건드리지 않는다. 다음 실행부터 적용된다.
    CasinoVpnLog("감시 시작 (hold " holdSec "s, max " maxSec "s, 게임 " (gCasinoVpnPrevRunning ? "실행 중" : "꺼짐") ")")
    OnExit((*) => (gCasinoVpnOn ? StopCasinoVpn("감시 종료") : 0, 0))
    SetTimer(CasinoVpnTick, 250)
}

CasinoVpnTick() {
    global gCasinoVpnOn, gCasinoVpnStart, gCasinoVpnGtaSeen, gCasinoVpnPrevRunning
    running := CasinoVpnGameRunning()
    if (running && !gCasinoVpnPrevRunning) {
        gCasinoVpnOn := true, gCasinoVpnStart := A_TickCount, gCasinoVpnGtaSeen := 0
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
    if (gCasinoVpnGtaSeen && A_TickCount - gCasinoVpnGtaSeen >= gCasinoVpnHoldSec * 1000)
        return StopCasinoVpn("게임 뜬 뒤 " gCasinoVpnHoldSec "s")
    if (A_TickCount - gCasinoVpnStart >= gCasinoVpnMaxSec * 1000)
        return StopCasinoVpn("최대 유지 시간")
}

StopCasinoVpn(reason := "") {
    global gCasinoVpnOn, gCasinoVpnStart
    RunWait('schtasks /run /tn GTA-VPN-Off', , "Hide")
    if (gCasinoVpnOn)
        CasinoVpnLog("VPN 끔 (" reason ", 총 " Round((A_TickCount - gCasinoVpnStart) / 1000) "s)")
    gCasinoVpnOn := false
}
