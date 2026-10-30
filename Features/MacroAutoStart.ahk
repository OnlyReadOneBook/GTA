; === GTA 가 켜지면 매크로(Main) 자동 실행 ===
; 시작 프로그램에서 늘 도는 CasinoVpnWatch.ahk 가 이 파일을 싣는다. GTA5_Enhanced 가 나타나는 순간 Main.ahk 가 안 떠 있으면 띄운다.
; Main 이 뜨면 디코 오버레이(DiscordChatHUD)도 Main 이 같이 띄우므로, GTA → 매크로 → 오버레이가 한 번에 올라온다(1030 사용자 지시).
; 게임이 켜지는 순간(없음 → 있음)과 감시 시작 때 이미 켜져 있던 경우에만 띄운다. 사용자가 Pause 로 매크로를 끈 뒤에는 게임이 다시 켜질 때까지 안 띄운다.
; 기록은 %TEMP%\gta-macro.log 의 [autostart] 줄.
global gMacroAutoStartPrevRunning := false

MacroAutoStartLog(msg) {
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [autostart] " msg "`n", A_Temp "\gta-macro.log", "UTF-8")
}

MacroAutoStartGameRunning() => !!ProcessExist("GTA5_Enhanced.exe")

; Main.ahk 의 숨은 주 창(제목이 스크립트 전체 경로로 시작)으로 실행 여부를 본다. 다른 AutoHotkey 스크립트와 섞이지 않는다.
MacroAutoStartMainRunning(mainPath) {
    previousHidden := A_DetectHiddenWindows
    DetectHiddenWindows true
    try return !!WinExist(mainPath " ahk_class AutoHotkey")
    finally DetectHiddenWindows previousHidden
}

MacroAutoStartLaunch(mainPath) {
    try Run('"' A_AhkPath '" "' mainPath '"', A_ScriptDir)
    catch as launchError {
        MacroAutoStartLog("매크로 실행 실패: " launchError.Message)
        return false
    }
    MacroAutoStartLog("GTA 실행 감지 → 매크로 실행: " mainPath)
    return true
}

StartMacroAutoStartWatch(mainPath := A_ScriptDir "\Main.ahk") {
    global gMacroAutoStartPrevRunning := MacroAutoStartGameRunning()
    MacroAutoStartLog("감시 시작 (게임 " (gMacroAutoStartPrevRunning ? "실행 중" : "꺼짐") ", 매크로 " (MacroAutoStartMainRunning(mainPath) ? "실행 중" : "꺼짐") ")")
    if (gMacroAutoStartPrevRunning && !MacroAutoStartMainRunning(mainPath))
        MacroAutoStartLaunch(mainPath)
    SetTimer(() => MacroAutoStartTick(mainPath), 1000)
}

MacroAutoStartTick(mainPath) {
    global gMacroAutoStartPrevRunning
    running := MacroAutoStartGameRunning()
    if (running && !gMacroAutoStartPrevRunning && !MacroAutoStartMainRunning(mainPath))
        MacroAutoStartLaunch(mainPath)
    gMacroAutoStartPrevRunning := running
}
