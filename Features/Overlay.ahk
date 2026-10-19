; === 상태 오버레이 (게임 화면 위 작은 상태 표시) ===
; AFK 방지 켜짐 여부, 돌고 있는 기능, 작텔 대기 시간, 상호작용 메뉴 위치 모드(부동산 안/밖)를 GTA 화면 오른쪽 위에 작게 띄운다.
; 클릭이 통과하고(WS_EX_TRANSPARENT) 포커스를 가져가지 않는다(WS_EX_NOACTIVATE + Show("NA")). 게임에 보내는 입력은 없다.
; GTA 가 앞일 때만 보이고, 다른 창이 앞이면 숨겨서 다른 앱 위에 남지 않게 한다.
; 픽셀·이미지 감지는 화면에 보이는 그대로 읽으므로 이 창이 감지 영역을 덮으면 오판한다. 그래서 작텔 종료창 안내 감지 영역(오른쪽 아래 구석),
; 인형 뽑기 안내 검색 영역(왼쪽 위 900x250)과 화면 가운데를 피해 설정 위치에 가장 가까운 안전한 자리에 놓는다.
; 위치는 Config [Settings] OverlayXPct(오른쪽 끝의 가로 %) / OverlayYPct(위쪽 끝의 세로 %). 기본 98 / 18 은 오른쪽 위 돈 표시 아래다.
global gOverlayGui := ""
global gOverlayText := ""
global gOverlayShown := false
global gOverlayLastText := ""
global gOverlayLastPos := ""

SetOverlay(on) {
    global gOverlayGui, gOverlayText, gOverlayShown, gOverlayLastText, gOverlayLastPos
    if (on) {
        if (!IsObject(gOverlayGui)) {
            g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x08000000 -DPIScale")
            g.BackColor := "101010"
            g.MarginX := 0, g.MarginY := 0
            g.SetFont("s10 cWhite", "Malgun Gothic")
            gOverlayText := g.Add("Text", "x8 y4 w100 h20", "")
            WinSetTransparent(200, g)   ; 반투명 (WS_EX_LAYERED 가 붙어야 WS_EX_TRANSPARENT 로 클릭이 통과한다)
            gOverlayGui := g
            gOverlayShown := false
            gOverlayLastText := ""
            gOverlayLastPos := ""
        }
        SetTimer(OverlayTick, 500)
        OverlayTick()
    } else {
        SetTimer(OverlayTick, 0)
        if (IsObject(gOverlayGui))
            gOverlayGui.Destroy()
        gOverlayGui := ""
        gOverlayShown := false
    }
}

OverlayIsOn() {
    global gOverlayGui
    return IsObject(gOverlayGui)
}

; 지금 게임 화면에 실제로 떠 있는지. 켜져 있어도 창이 작아 감지 영역을 피할 자리가 없으면 숨는다 → 그때는 작텔 카운트다운을 툴팁으로 보여야 한다.
OverlayVisible() {
    global gOverlayShown
    return gOverlayShown
}

OverlayTick() {
    global gOverlayGui, gOverlayText, gOverlayShown, gOverlayLastText, gOverlayLastPos
    if (!IsObject(gOverlayGui))
        return
    hwnd := IsGTAActive()
    if (!hwnd) {
        OverlayHide()
        return
    }
    text := MacroStatusText(true)
    if (text != gOverlayLastText) {
        MeasureText(gOverlayText, text, &tw, &th)
        gOverlayText.Move(, , tw, th)
        gOverlayText.Text := text
        gOverlayLastText := text
    }
    gOverlayText.GetPos(, , &tw, &th)
    w := tw + 16, h := th + 8
    ; 보조 모니터가 있으면 거기 오른쪽 위에 띄운다(0928 사용자 지시: AFK 상태 등을 GTA 화면에 띄우지 않는다)
    if (OtherMonitorArea(&ml, &mt, &mr, &mb)) {
        x := mr - w - 20, y := mt + 20
    } else {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
    }
    if (!IsSet(x) && !OverlayPlace(cx, cy, cw, ch, w, h, &x, &y)) {
        OverlayHide()
        return
    }
    pos := x "," y "," w "," h
    if (!gOverlayShown || pos != gOverlayLastPos) {
        gOverlayGui.Show("NA x" x " y" y " w" w " h" h)
        ; 배율이 다른 보조 모니터(175%)로 옮기면 창이 DPI 변경을 받아 글자 칸만 밀려 빈 검은 상자가 된다(0928 실측). 자리를 다시 잡는다
        gOverlayText.Move(8, 4, tw, th)
        gOverlayText.Redraw()
        gOverlayShown := true
        gOverlayLastPos := pos
    }
}

OverlayHide() {
    global gOverlayGui, gOverlayShown
    if (gOverlayShown) {
        gOverlayGui.Hide()
        gOverlayShown := false
    }
}

; 설정 위치가 감지 영역을 덮으면 가장 가까운 경계까지만 이동한다. 안전한 자리가 없으면 false = 숨김.
OverlayPlace(cx, cy, cw, ch, w, h, &x, &y) {
    global config
    if (cw <= 0 || ch <= 0 || w <= 0 || h <= 0 || w > cw || h > ch)
        return false
    s := config["Settings"]
    wantX := Max(0, Min(Round(cw * s["OverlayXPct"] / 100) - w, cw - w))
    wantY := Max(0, Min(Round(ch * s["OverlayYPct"] / 100), ch - h))
    if (!OverlayHitsDetection(wantX, wantY, w, h, cw, ch)) {
        x := cx + wantX, y := cy + wantY
        return true
    }
    ; 최근접 안전 위치는 원래 좌표 또는 화면·감지 사각형의 경계에 있다.
    ; 모든 X/Y 경계 조합을 확인하므로 한 영역을 피하다 다른 영역을 가리지 않는다.
    xs := [wantX, 0, cw - w], ys := [wantY, 0, ch - h]
    for z in OverlayDetectionZones(cw, ch) {
        xs.Push(z[1] - w, z[3])
        ys.Push(z[2] - h, z[4])
    }
    bestDistance := -1
    for rx in xs {
        if (rx < 0 || rx + w > cw)
            continue
        for ry in ys {
            if (ry < 0 || ry + h > ch || OverlayHitsDetection(rx, ry, w, h, cw, ch))
                continue
            distance := (rx - wantX) ** 2 + (ry - wantY) ** 2
            if (bestDistance < 0 || distance < bestDistance) {
                bestDistance := distance
                x := cx + rx, y := cy + ry
            }
        }
    }
    return bestDistance >= 0
}

; 게임 클라이언트 기준 좌표의 사각형이 감지 영역과 겹치는지.
;   작텔 종료창 "No [Esc]" 키캡 감지(QuitPromptReady: x 90.5~93.5%, y 95.5~98.5%) → 여유를 두고 오른쪽 아래 구석 전체
;   인형 뽑기 안내 이미지 검색(ClawSeen: 왼쪽 위 900x250)
;   화면 가운데(인형 뽑기 기계·지문 해킹 화면)
OverlayHitsDetection(rx, ry, w, h, cw, ch) {
    for z in OverlayDetectionZones(cw, ch) {
        if (rx < z[3] && rx + w > z[1] && ry < z[4] && ry + h > z[2])
            return true
    }
    return false
}

OverlayDetectionZones(cw, ch) {
    return [
        [Round(cw * 0.89), Round(ch * 0.94), cw, ch],
        [0, 0, Min(900, cw), Min(250, ch)],
        [Round(cw * 0.25), Round(ch * 0.14), Round(cw * 0.75), Round(ch * 0.76)]
    ]
}

; 컨트롤 글꼴로 여러 줄 글자의 크기를 잰다 (DrawText DT_CALCRECT).
MeasureText(ctrl, text, &w, &h) {
    hdc := DllCall("GetDC", "ptr", ctrl.Hwnd, "ptr")
    hFont := DllCall("SendMessage", "ptr", ctrl.Hwnd, "uint", 0x31, "ptr", 0, "ptr", 0, "ptr")   ; WM_GETFONT (숨은 창이어도 되게 HWND 로 직접)
    old := DllCall("SelectObject", "ptr", hdc, "ptr", hFont, "ptr")
    rc := Buffer(16, 0)
    DllCall("DrawTextW", "ptr", hdc, "str", text, "int", -1, "ptr", rc, "uint", 0x400 | 0x800)   ; DT_CALCRECT | DT_NOPREFIX
    DllCall("SelectObject", "ptr", hdc, "ptr", old, "ptr")
    DllCall("ReleaseDC", "ptr", ctrl.Hwnd, "ptr", hdc)
    w := NumGet(rc, 8, "int") + 2
    h := NumGet(rc, 12, "int")
}

; === 오버레이·설정 창이 같이 쓰는 상태 ===
; compact(오버레이): 도는 것이 있으면 한 줄씩, 마지막 줄에 AFK·메뉴 위치. 아무것도 안 돌면 한 줄.
MacroStatusText(compact) {
    global config, GTA_WIN
    running := RunningItems()
    afk := AFKStatusText()
    inside := config["Settings"]["MenuTopOffset"]
    ; 오버레이는 수익 상태 한 줄만 띄운다(1017 사용자 지시: 화면을 가리지 않게, AFK 는 늘 켜져 있어 표시하지 않는다)
    if (compact)
        return EarnOverlayText()
    list := ""
    for item in running
        list .= (list = "" ? "" : ", ") item
    gta := WinExist(GTA_WIN) ? (IsGTAActive() ? "앞에 있음" : "뒤에 있음 (실행 버튼이 앞으로 가져옴)") : "꺼져 있음"
    return "AFK 방지: " afk
        . "`n도는 것: " (list = "" ? "없음" : list)
        . "`n메뉴 위치: 부동산 " (inside ? "안" : "밖") " (MenuTopOffset=" inside ")"
        . "`n오버레이: " (OverlayIsOn() ? "켜짐" : "꺼짐")
        . "`nGTA: " gta
}

; 수익 중 / 수익 대기 N초(사용자 입력 뒤 안정 대기) / 수익 오류: 까닭 / 수익 중단
EarnOverlayText() {
    global gEarnOn, gEarnFail, gEarnCurrent, config
    if (!IsSet(gEarnOn) || !gEarnOn)
        return IsSet(gEarnFail) && gEarnFail != "" ? "수익 오류: " gEarnFail : "수익 중단"
    ; 무엇이 도는지는 켜진 작업 목록에서 만든다(1019 사용자 지시). 대기 중에도 보인다.
    scope := EarnScopeLabel()
    scope := scope = "" ? "" : scope " "
    if (gEarnCurrent = "") {
        idleLeft := config["Settings"]["EarnUserIdleSec"] * 1000 - A_TimeIdlePhysical
        if (idleLeft > 0)
            return scope "수익 대기 " Ceil(idleLeft / 1000) "초"
    }
    return scope "수익 중"
}

AFKStatusText() {
    global afkOn, afkNextDue, clawLoopRunning, config
    if (!afkOn)
        return "꺼짐"
    if (clawLoopRunning || AnyInputToggleOn())
        return "켜짐 · 다른 입력 중이라 쉼"
    dueIn := afkNextDue ? afkNextDue - A_TickCount : 0
    idleIn := config["Settings"]["AFKUserIdleSec"] * 1000 - A_TimeIdle
    return "켜짐 · 다음 입력 " Max(0, Ceil(Max(dueIn, idleIn) / 1000)) "초 뒤"
}

RunningItems() {
    global clawLoopRunning, clawTries, clickRunning, wRunning, shiftWRunning, vellumDrivingRunning
    global cayoTimerRunning, cayoEndTick, altF4Running, gJobWarpStart, gJobWarpMinMs, mcRunning, gMenuBusy
    items := []
    if (clawLoopRunning)
        items.Push("인형 반복 " clawTries "판")
    if (clickRunning)
        items.Push("자동 클릭")
    if (wRunning)
        items.Push("걷기")
    if (shiftWRunning)
        items.Push("달리기")
    if (vellumDrivingRunning)
        items.Push("벨럼")
    if (cayoTimerRunning) {
        left := Max(0, Round((cayoEndTick - A_TickCount) / 1000))
        items.Push("카요 타이머 " Format("{:d}:{:02d}", Floor(left / 60), Mod(left, 60)) " 남음")
    }
    if (altF4Running)
        items.Push(gJobWarpStart ? "작텔 대기 " Round((A_TickCount - gJobWarpStart) / 1000) "/" Round(gJobWarpMinMs / 1000) "초" : "작텔 진행 중")
    if ((quickJoin := JobWarpArmedText()) != "")
        items.Push(quickJoin)
    if ((botWarp := BotWarpStatusText()) != "")
        items.Push(botWarp)
    if (mcRunning)
        items.Push("MC 텔레포트 진행 중")
    if (gMenuBusy)
        items.Push("메뉴 매크로 진행 중")
    if (IsSet(gEarnOn) && (earn := EarnStatusText()) != "")
        items.Push(earn)
    ; 사업장별 판매 알림을 함께 표시한다. 해당 재고의 해소가 확인될 때까지 유지한다.
    if (IsSet(gEarnSellNotices)) {
        for source, notice in gEarnSellNotices
            items.Push(notice)
    }
    return items
}
