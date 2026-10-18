; === 아케이드 인형 뽑기 (Shiny Wasabi Kitty Claw) ===
; 기계 앞 "Press E to play" 안내가 떠 있는 상태에서 사용한다.
; 단계마다 화면 왼쪽 위 안내 문구(Images\Claw\*.png)를 확인하고 나서 다음 키를 누른다.
; 안내가 안 보이면 아무 키도 누르지 않고 멈춘다 — 캐릭터가 걸어가 버리는 사고를 막는다.
; 안내 문구 이미지는 게임 클라이언트 해상도별로 선택한다. 창 위치가 바뀌어도 게임 안에서만 찾는다.
global clawLoopRunning := false
global clawTries := 0
global clawStep := "loaded"
global clawLastReason := ""

; 종료 시 이동 키를 떼는 OnExit 는 Main.ahk 의 ReleaseHeldKeys 가 맡는다.
; 전체 멈춤(gAbort)이 켜지면 단계 대기·키 유지 루프가 즉시 실패로 끝나고 키를 뗀다.
ClawTrace("loaded", "", "script-loaded")

ClawLog(msg) {
    FileAppend(FormatTime(, "HH:mm:ss") " " msg "`n", A_Temp "\gta-claw.log", "UTF-8")
}

; 진단 실패가 키 입력이나 반복 흐름을 중단하지 않게 한다.
ClawTrace(step, reason := "", event := "") {
    global clawLoopRunning, clawTries, clawStep, clawLastReason
    clawStep := step
    if (reason != "")
        clawLastReason := reason
    try {
        fg := WinExist("A")
        fgProcess := ""
        fgTitle := ""
        fgDpi := 0
        if (fg) {
            try fgProcess := WinGetProcessName("ahk_id " fg)
            try fgTitle := WinGetTitle("ahk_id " fg)
            fgDpi := DllCall("GetDpiForWindow", "ptr", fg, "uint")
        }
        stamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        context := "fg=" fgProcess " hwnd=" fg " title=" StrReplace(StrReplace(fgTitle, "`r", " "), "`n", " ")
        if (event != "")
            ClawLog(event " loop=" clawLoopRunning " tries=" clawTries " step=" step " reason=" clawLastReason " " context)

        values := Map("on", clawLoopRunning ? 1 : 0, "step", step, "time", stamp,
            "tickCount", A_TickCount, "pid", DllCall("GetCurrentProcessId", "uint"),
            "tries", clawTries, "lastReason", clawLastReason,
            "foregroundProcess", fgProcess, "foregroundTitle", fgTitle, "foregroundHwnd", fg,
            "foregroundDpi", fgDpi, "scriptDpi", A_ScreenDPI,
            "threadDpiContext", DllCall("GetThreadDpiAwarenessContext", "ptr"),
            "systemDpi", DllCall("GetDpiForSystem", "uint"),
            "primarySize", A_ScreenWidth "," A_ScreenHeight, "monitorCount", MonitorGetCount())
        if (game := WinExist(GTA_WIN)) {
            previousDpiContext := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
            try {
                WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " game)
                values["gameClient"] := cx "," cy "," cw "," ch
                values["gameClientPhysical"] := previousDpiContext ? 1 : 0
                values["gameClientDpiContext"] := DllCall("GetThreadDpiAwarenessContext", "ptr")
            } finally {
                if (previousDpiContext)
                    DllCall("SetThreadDpiAwarenessContext", "ptr", previousDpiContext, "ptr")
            }
        }
        Loop MonitorGetCount() {
            MonitorGet(A_Index, &ml, &mt, &mr, &mb)
            values["monitor" A_Index] := ml "," mt "," mr "," mb
        }
        text := "[Claw]`n"
        for key, value in values
            text .= key "=" StrReplace(StrReplace(value "", "`r", " "), "`n", " ") "`n"
        statusFile := FileOpen(A_Temp "\claw-status.ini", "w", "UTF-16")
        statusFile.Write(text)
        statusFile.Close()
    } catch {
        ; 진단 파일을 쓸 수 없어도 기존 매크로 동작은 유지한다.
    }
}

ClawFailure(step, reason) {
    ClawTrace(step, reason, "failure")
    return false
}

ClawSeen(name) {
    CoordMode("Pixel", "Screen")
    hwnd := WinActive(GTA_WIN)
    if (!hwnd)
        return ClawFailure("seen-" name, "focus-lost")
    ; 배율이나 모니터가 바뀌어도 크기 조회와 이미지 검색을 같은 물리 픽셀 좌표로 수행한다.
    previousDpiContext := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    if (!previousDpiContext)
        return ClawFailure("seen-" name, "dpi-context-error " A_LastError)
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        imageDir := A_ScriptDir "\Images\Claw"
        if (cw != 2560 || ch != 1600)
            imageDir .= "\" cw "x" ch
        img := imageDir "\" name ".png"
        if (!FileExist(img)) {
            if (clawLastReason != "missing-template " img)
                ClawTrace("seen-" name, "missing-template " img, "failure")
            return false
        }
        try {
            return ImageSearch(&x, &y, cx, cy, cx + Min(900, cw - 1), cy + Min(250, ch - 1), "*50 *Trans0xFF00FF " img)
        } catch as e {
            ClawLog("ImageSearch 오류 " name ": " e.Message)
            return ClawFailure("seen-" name, "image-search-error " e.Message)
        }
    } finally {
        DllCall("SetThreadDpiAwarenessContext", "ptr", previousDpiContext, "ptr")
    }
}

ClawWaitFor(name, timeoutMs) {
    global gAbort
    ClawTrace("wait-" name)
    deadline := A_TickCount + timeoutMs
    while (A_TickCount < deadline) {
        if (gAbort)
            return ClawFailure("wait-" name, "aborted")
        if (!IsGTAActive())
            return ClawFailure("wait-" name, "focus-lost")
        if (ClawSeen(name))
            return true
        Sleep(100)
    }
    return ClawFailure("wait-" name, "timeout " timeoutMs " ms")
}

ClawHold(key, ms) {
    global gAbort
    ClawTrace("hold-" key)
    if (gAbort)
        return ClawFailure("hold-" key, "aborted")
    if (!IsGTAActive())
        return ClawFailure("hold-" key, "focus-lost-before-hold")
    lostFocus := false
    aborted := false
    if (MacroKeyPhysicallyHeld(key))
        return ClawFailure("hold-" key, "physical-key-held")
    Send("{Blind}{" key " down}")
    try {
        deadline := A_TickCount + ms
        while (A_TickCount < deadline) {
            if (gAbort) {
                aborted := true
                break
            }
            if (!IsGTAActive()) {
                lostFocus := true
                break
            }
            Sleep(Min(20, deadline - A_TickCount))
        }
    } finally {
        ReleaseMacroKey(key)
    }
    if (aborted)
        return ClawFailure("hold-" key, "aborted")
    if (lostFocus)
        return ClawFailure("hold-" key, "focus-lost-during-hold")
    return true
}

; 한 판을 끝까지 진행하고 성공하면 true, 어느 단계든 안내가 안 보이면 false
ClawAttempt() {
    global config, clawTries, clawLastReason, gAbort
    clawLastReason := ""
    gAbort := false
    ClawTrace("attempt", "", "attempt-start")

    if (!IsGTAActive())
        return ClawFailure("attempt", "focus-lost-before-attempt")

    s := config["Settings"]

    ; 이전 판이 중간에 끊겨 "앞으로 이동" 단계에 멈춰 있으면 E 없이 이어서 진행한다.
    ; 오른쪽·내리기 단계에 멈춰 있으면 위치를 알 수 없으니 그 판은 그대로 내려서 끝낸다.
    if (ClawSeen("right") || ClawSeen("down")) {
        ClawTrace("recover-partial-attempt", "", "recover-partial-attempt")
        ClawLog("이전 판이 중간 단계에 멈춰 있어 내려서 정리")
        if (ClawSeen("right"))
            PressKey("d")
        if (!ClawWaitFor("down", 3000))
            return false
        PressKey("Enter")
        Sleep(3000)
        ClawWaitFor("play", s["ClawResultTimeout"])
    }

    if (!ClawSeen("forward")) {
        if (!ClawWaitFor("play", 2000)) {
            ClawLog("중지: Press E 안내 없음")
            ShowTooltip("🧸 기계 앞이 아님 (Press E 안내 없음) - 중지", 2500)
            return false
        }

        PressKey("e")
        if (!ClawWaitFor("forward", s["ClawEnterTimeout"])) {
            ClawLog("중지: 게임 시작 안내 없음")
            ShowTooltip("🧸 게임 시작 확인 실패 - 이동하지 않고 중지", 2500)
            return false
        }
    }

    if (!ClawHold("w", s["ClawForwardMs"]))
        return false
    if (!ClawWaitFor("right", 3000)) {
        ClawLog("중지: 오른쪽 단계 안내 없음")
        ShowTooltip("🧸 오른쪽 이동 단계 확인 실패 - 중지", 2500)
        return false
    }

    if (!ClawHold("d", s["ClawRightMs"]))
        return false
    if (!ClawWaitFor("down", 3000)) {
        ClawLog("중지: 내리기 단계 안내 없음")
        ShowTooltip("🧸 내리기 단계 확인 실패 - 중지", 2500)
        return false
    }

    PressKey("Enter")
    clawTries += 1
    ClawLog(clawTries "판 내림")
    ClawTrace("result-animation", "", "drop")

    ; 집게가 내려갔다 올라오고 다시 "Press E" 안내가 뜰 때까지 기다린다
    Sleep(3000)
    if (!ClawWaitFor("play", s["ClawResultTimeout"])) {
        ShowTooltip("🧸 결과 후 기계 앞 복귀 확인 실패 - 중지", 2500)
        return false
    }
    ClawTrace("complete", "", "attempt-completed")
    return true
}

ToggleClawLoop() {
    global clawLoopRunning, clawLastReason, gAbort

    if (IsSet(gEarnBusy) && gEarnBusy) {
        ShowTooltip("인형 뽑기: 수익 자동화가 진행 중", 1500)
        return
    }
    if (!IsGTAActive()) {
        ClawTrace("toggle-ignored", "focus-lost", "loop-toggle-ignored")
        return
    }

    clawLoopRunning := !clawLoopRunning
    if (clawLoopRunning) {
        clawLastReason := ""
        gAbort := false
        ClawTrace("loop-on", "", "loop-toggle-on")
        ShowTooltip("🧸 인형 뽑기 반복 시작 - 다시 누르면 중지")
        SetTimer(ClawLoopStep, -1)
    } else {
        ; 진행 중인 판은 다음 키 전에 멈추고 키를 뗀다. 중간에 멈춘 판은 다음 시작 때 복구 분기가 내려서 정리한다.
        gAbort := true
        ClawTrace("loop-off", "", "loop-toggle-off")
        ShowTooltip("🧸 인형 뽑기 반복 중지", 1500)
    }
}

ClawLoopStep() {
    global clawLoopRunning, clawTries, clawLastReason

    if (!clawLoopRunning) {
        ClawTrace("idle", "", "iteration-skipped-loop-off")
        return
    }

    ClawTrace("iteration", "", "iteration-start")
    if (!ClawAttempt()) {
        clawLoopRunning := false
        ClawTrace("stopped", clawLastReason = "" ? "attempt-returned-false" : clawLastReason, "loop-stopped")
        return
    }
    ClawTrace("iteration-complete", "", "iteration-completed")
    ShowTooltip("🧸 " clawTries "판 완료", 1500)
    SetTimer(ClawLoopStep, -1000)
}
