; === 공통 함수 ===
; GTA 창 판정. 제목 부분일치만 쓰면 스팀 설치 폴더를 연 탐색기("Grand Theft Auto V Enhanced")도 맞으므로 exe 를 같이 본다.
global GTA_WIN := "Grand Theft Auto V ahk_exe GTA5_Enhanced.exe"

IsGTAActive() {
    global GTA_WIN
    return WinActive(GTA_WIN)
}

; GTA 창이 없는 모니터(보조 모니터)의 작업 영역. 없으면 false. 0928 사용자 지시: 상태 메시지는 GTA 화면이 아니라 보조 모니터에 띄운다
OtherMonitorArea(&l, &t, &r, &b) {
    global GTA_WIN
    gx := 0, gy := 0
    if (hwnd := WinExist(GTA_WIN)) {
        try {
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
            gx := wx + ww // 2, gy := wy + wh // 2
        }
    }
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        if (gx < l || gx >= r || gy < t || gy >= b)
            return true
    }
    return false
}

ShowTooltip(text, duration := 1000) {
    ; 상태 메시지가 게임 왼쪽 위의 단계 안내와 이미지 검색을 가리지 않게 한다.
    CoordMode("ToolTip", "Screen")
    if (OtherMonitorArea(&ml, &mt, &mr, &mb)) {
        ToolTip(text, ml + 20, mb - 100)
    } else if (hwnd := IsGTAActive()) {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        ; 미니맵(왼쪽 아래 290x190) 오른쪽에 띄운다. 그 위에 띄우면 수익 자동화의 미니맵 픽셀 판정을 가린다(0927 실측)
        ToolTip(text, cx + Round(cw * 0.17), cy + Max(260, ch - 100))
    } else {
        ToolTip(text, 20, A_ScreenHeight - 100)
    }
    ; 이름 있는 함수로 걸어야 앞서 건 타이머가 교체된다. 익명 클로저는 호출마다 따로 남아 뒤에 띄운 메시지를 먼저 지운다.
    SetTimer(ClearStatusTip, -duration)
}

ClearStatusTip() {
    ToolTip()
}

; 매크로 공통 로그. AFK 방지는 %TEMP%\gta-afk.log, 인형 뽑기는 %TEMP%\gta-claw.log 에 따로 남긴다.
MacroLog(tag, msg) {
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" tag "] " msg "`n", A_Temp "\gta-macro.log", "UTF-8")
}

; 아무 키가 눌렸는지 체크하는 함수 (특정 키 제외)
IsAnyKeyPressed(excludeKeys := []) {
    ; 주요 키들 체크
    keys := ["Space", "Escape", "Tab", "Shift", "Ctrl", "Alt", 
             "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
             "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
             "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
             "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
             "Enter", "BackSpace", "Delete", "Home", "End", "PgUp", "PgDn",
             "Up", "Down", "Left", "Right"]
    
    for key in keys {
        ; 제외할 키 목록에 있는지 체크
        skip := false
        for excludeKey in excludeKeys {
            if (key = excludeKey) {
                skip := true
                break
            }
        }
        
        if (!skip && GetKeyState(key, "P"))
            return true
    }
    return false
}

; 이동·자동 클릭 토글이 하나라도 켜져 있는지. 켜져 있으면 그 자체가 입력이라 AFK 방지가 건너뛴다.
AnyInputToggleOn() {
    global wRunning, shiftWRunning, vellumDrivingRunning, clickRunning
    return (IsSet(wRunning) && wRunning) || (IsSet(shiftWRunning) && shiftWRunning)
        || (IsSet(vellumDrivingRunning) && vellumDrivingRunning) || (IsSet(clickRunning) && clickRunning)
}

; 매크로가 누르고 있을 수 있는 키 중 논리적으로 눌린 것만 뗀다. 사람이 물리적으로 누르고 있는 키는 건드리지 않는다.
; 종료·전체 멈춤 때 부른다. 이동 키를 누른 채 끝나면 캐릭터가 계속 걸어가 버린다(실측).
ReleaseHeldKeys() {
    for key in ["w", "a", "s", "d", "LShift", "LCtrl", "Enter", "e", "m", "Up", "Down", "Left", "Right"] {
        try {
            if (GetKeyState(key))
                ReleaseMacroKey(key)
        }
    }
    try {
        if (GetKeyState("LButton") && !GetKeyState("LButton", "P"))
            Click("Left Up")
    }
}

; 모든 기능 종료
ExitAll() {
    try StopAll("exit")
    try ReleaseHeldKeys()
    ToolTip()
    ToolTip(, , , 2)
    ExitApp()
}
