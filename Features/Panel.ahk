; === 설정·실행 창 ===
; GTA 가 없는 모니터(노트북 화면) 가운데에 여는 일반 창. 트레이 메뉴 "설정 창 열기"(아이콘 더블클릭) 또는 도움말 키 두 번으로 연다.
; 여기서 바꾼 값은 Config.ini 에 저장하고(SetConfigValue) 바로 반영한다. 원본은 계속 Config.ini 다.
; 매크로 키는 GTA 창이 앞일 때만 동작하므로, 실행 버튼은 GTA 를 앞으로 가져온 뒤(BringGTAToFront) 300ms 뒤에 실행한다. 창은 숨기지 않는다.
; 되돌리기 어려운 기능(confirm: 초대 세션·텔레포트·작텔)은 3초 안에 버튼을 한 번 더 눌러야 실행한다.
; MsgBox 는 쓰지 않는다: 확인창이 포커스를 또 가져가서 GTA 가 뒤로 간다.
global gPanel := ""
global gPanelCtl := Map()
global gPanelArmed := Map()      ; confirm 버튼의 첫 번째 누름 시각
global gPanelLastStatus := ""
global PANEL_CONFIRM_MS := 3000
global PANEL_LOG_LINES := 15

OpenPanel() {
    global gPanel
    if (!IsObject(gPanel))
        BuildPanel()
    if (!DllCall("IsWindowVisible", "ptr", gPanel.Hwnd)) {
        PanelLoadValues()
        PanelRefreshLogs()
        WinGetPos(, , &w, &h, gPanel)
        PanelTargetArea(&l, &t, &r, &b)
        gPanel.Show("x" (l + Max(0, (r - l - w) // 2)) " y" (t + Max(0, (b - t - h) // 2)))
    } else {
        gPanel.Show()
    }
    SetTimer(PanelTick, 1000)
}

; GTA 창 가운데가 들어 있지 않은 첫 모니터의 작업 영역. GTA 가 없거나 모니터가 하나면 주 모니터.
PanelTargetArea(&l, &t, &r, &b) {
    global GTA_WIN
    pick := MonitorGetPrimary()
    if (hwnd := WinExist(GTA_WIN)) {
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
        gx := wx + ww // 2, gy := wy + wh // 2
        Loop MonitorGetCount() {
            MonitorGet(A_Index, &ml, &mt, &mr, &mb)
            if (!(gx >= ml && gx < mr && gy >= mt && gy < mb)) {
                pick := A_Index
                break
            }
        }
    }
    MonitorGetWorkArea(pick, &l, &t, &r, &b)
}

BuildPanel() {
    global gPanel, gPanelCtl, gActions, config, PANEL_LOG_LINES
    g := Gui("-MaximizeBox", "GTA 매크로")
    g.SetFont("s9", "Malgun Gothic")
    g.OnEvent("Close", PanelClose)
    g.OnEvent("Escape", PanelClose)
    c := gPanelCtl

    ; 왼쪽 위: 상태
    g.Add("GroupBox", "x8 y6 w350 h150", "지금 상태")
    c["status"] := g.Add("Text", "x20 y26 w328 h124", "")

    ; 왼쪽 아래: 설정 (Config.ini 에 저장)
    g.Add("GroupBox", "x8 y162 w350 h204", "설정 (Config.ini 에 저장하고 바로 반영)")
    g.Add("Text", "x20 y184 w330", "메뉴 위치 MenuTopOffset (스낵·CEO·MC 매크로 칸 수 보정)")
    c["inside"] := g.Add("Radio", "x20 y204 w160", "부동산 안 (1)")
    c["outside"] := g.Add("Radio", "x184 y204 w160", "부동산 밖 (0)")
    c["inside"].OnEvent("Click", (*) => PanelSetMenuOffset(1))
    c["outside"].OnEvent("Click", (*) => PanelSetMenuOffset(0))
    c["afk"] := g.Add("Checkbox", "x20 y236 w330", "AFK 방지 켜기 (" KeyLabelFor("AntiAFK") ")")
    c["afk"].OnEvent("Click", (ctl, *) => SetAntiAFK(ctl.Value = 1))
    g.Add("Text", "x36 y264 w200", "입력이 없을 때 몇 초 뒤부터 누를지")
    c["idle"] := g.Add("Edit", "x240 y261 w56 Number Limit3", "")
    g.Add("Text", "x302 y264 w30", "초")
    g.Add("Text", "x36 y292 w200", "누르는 간격 (±" config["Settings"]["AFKJitterSec"] "초 흔들림)")
    c["interval"] := g.Add("Edit", "x240 y289 w56 Number Limit3", "")
    g.Add("Text", "x302 y292 w30", "초")
    g.Add("Button", "x36 y316 w110 h24", "AFK 값 저장").OnEvent("Click", PanelSaveAFK)
    c["overlay"] := g.Add("Checkbox", "x20 y344 w330", "게임 화면 위 상태 표시 (오버레이)")
    c["overlay"].OnEvent("Click", PanelSetOverlay)

    ; 오른쪽: 기능 실행 버튼 (키가 비어 있는 기능 포함, 종료 제외)
    g.Add("GroupBox", "x366 y6 w470 h360", "기능 실행 (GTA 를 앞으로 가져온 뒤 실행, ×2 는 두 번 눌러 실행)")
    n := 0
    for action in gActions {
        if (action.id = "Exit")
            continue
        x := 378 + Mod(n, 2) * 228
        y := 28 + (n // 2) * 36
        enabled := !action.HasProp("feature") || config["Features"].Get(action.feature, 0)
        btn := g.Add("Button", "x" x " y" y " w150 h28", action.label)
        btn.OnEvent("Click", PanelActionClick.Bind(action))
        if (!enabled)
            btn.Enabled := false
        g.Add("Text", "x" (x + 156) " y" (y + 7) " w70", enabled ? PanelKeyText(action) : "기능 꺼짐")
        n += 1
    }

    ; 아래: 최근 로그
    g.Add("GroupBox", "x8 y372 w828 h262", "최근 로그 (%TEMP%\gta-macro.log · gta-afk.log 끝 " PANEL_LOG_LINES "줄)")
    c["log"] := g.Add("Edit", "x16 y392 w812 h206 ReadOnly -Wrap HScroll VScroll", "")
    g.Add("Button", "x16 y604 w90 h24", "새로고침").OnEvent("Click", (*) => PanelRefreshLogs())

    ; 맨 아래: 파일·재시작·닫기
    g.Add("Button", "x8 y642 w120 h28", "Config.ini 열기").OnEvent("Click", (*) => Run('notepad.exe "' A_ScriptDir '\Config.ini"'))
    g.Add("Button", "x134 y642 w110 h28", "다시 불러오기").OnEvent("Click", (*) => Reload())
    g.Add("Button", "x250 y642 w90 h28", "창 닫기").OnEvent("Click", PanelClose)
    c["msg"] := g.Add("Text", "x350 y649 w486", "")
    g.Show("Hide w844 h678")
    gPanel := g
}

; 버튼 옆에 보이는 현재 키. confirm 액션은 ×2.
PanelKeyText(action) {
    keys := KeyLabelFor(action.id)
    if (keys = "(키 없음)")
        return "키 없음"
    return keys (action.HasProp("confirm") && action.confirm ? " ×2" : "")
}

PanelClose(*) {
    global gPanel
    SetTimer(PanelTick, 0)
    if (IsObject(gPanel))
        gPanel.Hide()
}

PanelTick() {
    global gPanel
    if (!IsObject(gPanel) || !DllCall("IsWindowVisible", "ptr", gPanel.Hwnd)) {
        SetTimer(PanelTick, 0)
        return
    }
    PanelSync()
}

; 창을 열 때: 입력칸까지 현재 값으로 채운다 (입력칸은 입력 중일 수 있어 1초 갱신에서는 건드리지 않는다).
PanelLoadValues() {
    global gPanelCtl, config
    gPanelCtl["idle"].Value := config["Settings"]["AFKUserIdleSec"]
    gPanelCtl["interval"].Value := config["Settings"]["AFKIntervalSec"]
    PanelSync()
}

; 1초마다: 상태 글과 스위치·체크를 실제 상태에 맞춘다 (단축키로 바꾼 것도 따라오게).
PanelSync() {
    global gPanelCtl, gPanelLastStatus, afkOn, config
    c := gPanelCtl
    text := MacroStatusText(false)
    if (text != gPanelLastStatus) {
        c["status"].Text := text
        gPanelLastStatus := text
    }
    afk := afkOn ? 1 : 0
    if (c["afk"].Value != afk)
        c["afk"].Value := afk
    inside := config["Settings"]["MenuTopOffset"] ? 1 : 0
    if (c["inside"].Value != inside)
        c["inside"].Value := inside
    if (c["outside"].Value != 1 - inside)
        c["outside"].Value := 1 - inside
    ov := OverlayIsOn() ? 1 : 0
    if (c["overlay"].Value != ov)
        c["overlay"].Value := ov
}

PanelMessage(text) {
    global gPanelCtl
    try gPanelCtl["msg"].Text := FormatTime(, "HH:mm:ss") "  " text
}

; Config.ini 저장. 실패하면(파일이 잠김 등) 창에 알리고 false.
PanelSave(key, value) {
    try {
        SetConfigValue("Settings", key, value)
        return true
    } catch as e {
        MacroLog("error", "설정 저장 실패 " key "=" value ": " e.Message)
        PanelMessage("저장 실패 " key ": " e.Message)
        return false
    }
}

PanelSetMenuOffset(v) {
    global config
    if (config["Settings"]["MenuTopOffset"] = v)
        return
    if (PanelSave("MenuTopOffset", v))
        PanelMessage("메뉴 위치: 부동산 " (v ? "안" : "밖") " (MenuTopOffset=" v ") 저장")
    PanelSync()
}

PanelSetOverlay(ctl, *) {
    v := ctl.Value ? 1 : 0
    if (!PanelSave("OverlayEnabled", v)) {
        PanelSync()
        return
    }
    SetOverlay(v = 1)
    PanelMessage("오버레이 " (v ? "켜짐" : "꺼짐") " (OverlayEnabled=" v ") 저장")
}

; AFK 값은 5~600초만 받는다 (ms 로 잘못 적는 실수나 너무 긴 간격으로 idle 킥을 맞는 일을 막는다).
PanelSaveAFK(*) {
    global gPanelCtl, afkNextDue, config
    idle := Trim(gPanelCtl["idle"].Value)
    interval := Trim(gPanelCtl["interval"].Value)
    if (!IsInteger(idle) || Integer(idle) < 5 || Integer(idle) > 600) {
        PanelMessage("입력 없음 시간은 5~600초로 적으세요")
        return
    }
    if (!IsInteger(interval) || Integer(interval) < 30 || Integer(interval) > 600) {
        PanelMessage("누르는 간격은 30~600초로 적으세요")
        return
    }
    idle := Integer(idle), interval := Integer(interval)
    if (!PanelSave("AFKUserIdleSec", idle) || !PanelSave("AFKIntervalSec", interval))
        return
    ; 수익 자동화도 같은 유휴 기준을 쓴다(ConfigLoader 와 같게)
    config["Settings"]["EarnUserIdleSec"] := idle
    ; 이미 잡힌 다음 입력이 새 간격보다 멀면 새 간격으로 당긴다
    if (afkNextDue && afkNextDue - A_TickCount > interval * 1000)
        afkNextDue := A_TickCount + interval * 1000
    PanelMessage("AFK 값 저장: 입력 없음 " idle "초 뒤부터, 간격 " interval "초")
}

PanelActionClick(action, btn, *) {
    global gPanelArmed, PANEL_CONFIRM_MS
    if (action.HasProp("confirm") && action.confirm) {
        if (!(gPanelArmed.Has(action.id) && A_TickCount - gPanelArmed[action.id] <= PANEL_CONFIRM_MS)) {
            gPanelArmed[action.id] := A_TickCount
            btn.Text := "한 번 더 누르면 실행"
            SetTimer(PanelDisarm.Bind(action, btn), -PANEL_CONFIRM_MS)
            return
        }
        gPanelArmed.Delete(action.id)
        btn.Text := action.label
    }
    if (!BringGTAToFront()) {
        PanelMessage("GTA 를 앞으로 가져오지 못해 " action.label " 은(는) 실행하지 않음")
        return
    }
    PanelMessage(action.label " 실행")
    MacroLog("panel", action.id)
    SetTimer(PanelRunAction.Bind(action), -300)
}

PanelDisarm(action, btn) {
    global gPanelArmed, PANEL_CONFIRM_MS
    if (gPanelArmed.Has(action.id) && A_TickCount - gPanelArmed[action.id] >= PANEL_CONFIRM_MS - 50) {
        gPanelArmed.Delete(action.id)
        btn.Text := action.label
    }
}

PanelRunAction(action) {
    ; 커서가 설정 창 위에 남아 있으면 자동 클릭이 게임 대신 설정 창 버튼을 1ms 간격으로 누른다(0926 실측: AFK·벨럼 버튼이 저절로 켜졌다 꺼졌다).
    ; 그래서 자동 클릭만 실행 전에 커서를 게임 화면 가운데로 옮긴다. SetCursorPos 는 원시 마우스 입력을 만들지 않아 카메라가 돌지 않는다.
    ; 다른 버튼까지 옮기지 않는 까닭: 커서가 게임 안에 들어가면 GTA 가 커서를 게임 창에 가둬(ClipCursor) 설정 창을 다시 누르려면 Alt+Tab 이 필요해진다.
    if (action.id = "AutoClick")
        PanelCursorToGTA()
    ; 창의 도움말 버튼은 두 번 누름(설정 창 열기) 판정 없이 도움말만 토글한다
    if (action.id = "Help")
        ToggleHelp()
    else
        action.fn.Call()
}

PanelCursorToGTA() {
    global GTA_WIN
    if (!(hwnd := WinExist(GTA_WIN)))
        return
    WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
    DllCall("SetCursorPos", "int", cx + cw // 2, "int", cy + ch // 2)
}

PanelRefreshLogs() {
    global gPanelCtl, PANEL_LOG_LINES
    gPanelCtl["log"].Value := "── gta-macro.log ──`r`n" TailLines(A_Temp "\gta-macro.log", PANEL_LOG_LINES)
        . "`r`n`r`n── gta-afk.log ──`r`n" TailLines(A_Temp "\gta-afk.log", PANEL_LOG_LINES)
}

; 파일 끝 n 줄. 로그가 커져도 끝 16KB 만 읽는다.
TailLines(path, n) {
    if (!FileExist(path))
        return "(파일 없음)"
    try {
        f := FileOpen(path, "r", "UTF-8")
        size := f.Length
        cut := size > 16384
        if (cut)
            f.Pos := size - 16384
        text := f.Read()
        f.Close()
    } catch as e {
        return "(읽기 실패: " e.Message ")"
    }
    lines := StrSplit(RTrim(text, "`r`n"), "`n", "`r")
    if (cut && lines.Length > 1)
        lines.RemoveAt(1)   ; 중간에서 잘린 첫 줄
    out := ""
    start := Max(1, lines.Length - n + 1)
    Loop lines.Length - start + 1
        out .= (A_Index = 1 ? "" : "`r`n") lines[start + A_Index - 1]
    return out
}
