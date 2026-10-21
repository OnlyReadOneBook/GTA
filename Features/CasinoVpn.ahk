; === 카지노 VPN ===
; 한국 IP 에서는 다이아몬드 카지노 도박이 막힌다. 지역 판정은 런처·게임 부팅 때 이뤄진다고 알려져 있어(Sportskeeda, 공식 확인 없음)
; 게임이 꺼진 상태에서 VPN(Proton 무료 NL, WireGuard) 을 켜고 → 국가가 KR 이 아닌지 확인 → 게임을 띄우고 →
; GTA5_Enhanced.exe 가 뜬 뒤 CasinoVpnHoldSec 초가 지나면 끈다. 어떤 경우에도 CasinoVpnMaxSec 를 넘기지 않는다.
; WireGuard 는 관리자 권한이 필요해 예약 작업 GTA-VPN-On/Off(가장 높은 권한) 로 부른다. 설정 파일은 vpn\gtanl.conf (깃 제외).
; 시점별 기록은 %TEMP%\gta-casino-vpn.log. 유지 시간을 줄이려면 HoldSec 을 낮춰 카지노 테이블이 열리는지 재 본다.
global gCasinoVpnOn := false, gCasinoVpnStart := 0, gCasinoVpnGtaSeen := 0
global CASINO_VPN_STEAM_URL := "steam://rungameid/3240220"

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

StartCasinoVpn() {
    global gCasinoVpnOn, gCasinoVpnStart, gCasinoVpnGtaSeen
    if (gCasinoVpnOn)
        return ShowTooltip("카지노 VPN: 이미 진행 중", 1500)
    if (ProcessExist("GTA5_Enhanced.exe") || ProcessExist("PlayGTAV.exe"))
        return ShowTooltip("카지노 VPN: 게임을 먼저 끄세요 (지역 판정은 부팅 때)", 3000)
    RunWait('schtasks /run /tn GTA-VPN-On', , "Hide")
    country := ""
    loop 10 {
        Sleep(1000)
        country := CasinoVpnCountry()
        if (country != "" && country != "KR")
            break
    }
    if (country = "" || country = "KR") {
        CasinoVpnLog("연결 실패 (국가 " country ")")
        StopCasinoVpn("연결 실패")
        return ShowTooltip("카지노 VPN: 해외 IP 연결 실패", 3000)
    }
    gCasinoVpnOn := true, gCasinoVpnStart := A_TickCount, gCasinoVpnGtaSeen := 0
    CasinoVpnLog("VPN 켬 (" country "), 게임 실행")
    ShowTooltip("카지노 VPN: " country " 연결, 게임 실행", 2000)
    Run(CASINO_VPN_STEAM_URL)
    SetTimer(CasinoVpnTick, 1000)
}

CasinoVpnTick() {
    global gCasinoVpnGtaSeen, gCasinoVpnStart, config
    s := config["Settings"]
    if (!gCasinoVpnGtaSeen && ProcessExist("GTA5_Enhanced.exe")) {
        gCasinoVpnGtaSeen := A_TickCount
        CasinoVpnLog("GTA5_Enhanced 뜸 (+" Round((A_TickCount - gCasinoVpnStart) / 1000) "s)")
    }
    if (gCasinoVpnGtaSeen && A_TickCount - gCasinoVpnGtaSeen >= s["CasinoVpnHoldSec"] * 1000)
        return StopCasinoVpn("게임 뜬 뒤 " s["CasinoVpnHoldSec"] "s")
    if (A_TickCount - gCasinoVpnStart >= s["CasinoVpnMaxSec"] * 1000)
        return StopCasinoVpn("최대 유지 시간")
}

StopCasinoVpn(reason := "") {
    global gCasinoVpnOn, gCasinoVpnStart
    SetTimer(CasinoVpnTick, 0)
    RunWait('schtasks /run /tn GTA-VPN-Off', , "Hide")
    if (gCasinoVpnOn) {
        CasinoVpnLog("VPN 끔 (" reason ", 총 " Round((A_TickCount - gCasinoVpnStart) / 1000) "s)")
        ShowTooltip("카지노 VPN 해제: " reason, 2000)
    }
    gCasinoVpnOn := false
}

; 매크로가 꺼질 때 VPN 이 남아 있으면 해외 IP 로 계속 쓰게 된다. 항상 끈다.
OnExit((*) => (gCasinoVpnOn ? StopCasinoVpn("매크로 종료") : 0, 0))
