; === AFK 방지 (GTA Online idle 킥 방지) ===
; 사용자가 AFKUserIdleSec 초 동안 키보드·마우스를 안 만졌을 때만, AFKIntervalSec 초(±AFKJitterSec) 간격으로
; 모든 모드에서 마우스를 좌우로 2만큼 움직인다. 클릭·키 입력은 보내지 않는다.
; GTA가 앞일 때만 입력한다. 다른 창이 앞이면 물리 입력과, 이 매크로 밖에서 주입된 입력(크롬 원격 데스크톱·computer-use·코덱스 등)이
; 둘 다 AFKRefocusIdleSec 초(기본 300, 0 이면 끔) 넘게 없을 때만 GTA 를 앞으로 가져오고(최소화면 복원), AFKRefocusSettleMs 기다린 뒤
; 같은 입력 판정을 다시 거친다. 그보다 짧으면 누가 자리에 있거나 다른 창을 쓰는 중이라고 보고 포커스를 뺏지 않는다.
; 0928 07:45 예약 작업이 띄운 크롬이 GTA 포커스를 가져간 뒤 입력이 끊겨 07:59 에 15분 방치 킥을 당했다(그 전에는 전면화하지 않고 건너뛰기만 했다).
; 사용자 물리 입력이 생기면 남은 동작을 취소한다.
; 인형 뽑기 반복이나 이동·자동 클릭 토글이 켜져 있으면 그 자체가 입력이므로 건너뛴다 (W 를 떼면 달리기 유지가 풀린다).
global afkOn := false
global afkNextDue := 0
global gAFKBusy := false
global afkRefocusFails := 0      ; 같은 유휴 구간에서 입력까지 못 가고 연달아 실패한 전면화 횟수
global afkRefocusStretch := 0    ; 그 유휴 구간이 시작된 시각(A_TickCount - A_TimeIdlePhysical)
global afkRefocusLastErr := ""   ; 마지막으로 로그에 적은 실패 까닭. 같은 까닭은 다시 적지 않는다
global afkRefocusWindow := ""    ; 같은 앞 창/유휴 구간의 복귀는 세 번까지만 시도한다
global afkHookTick := 0          ; SetAntiAFK 가 키보드·마우스 훅을 처음 깐 시각(A_TickCount)
global afkSelfFrom := 0          ; 이 매크로가 입력(마우스 왕복·전면화 중 Alt)을 넣기 시작한 시각
global afkSelfTo := 0            ; 그 입력을 끝낸 시각. 0 이면 아직 넣는 중
global afkSelfBefore := 0        ; 그 구간 직전까지의 마지막 남의 입력 시각
; 마우스 왕복 직전에 부를 화면 정리(Main 은 Earner 가 넣는다). MCT 컴퓨터 화면 안에서는 작은 마우스 이동이 화면 속 커서만 움직여
; 방치로 세어진다(1010 04:50~05:31: DJ 목록이 열린 채 3~4분마다 마우스 왕복을 보냈는데 추방됨). 그런 화면을 닫아 마우스 왕복이 먹는 상태로 돌린다.
global gAFKScreenGuard := ""

ToggleAntiAFK(*) {
    global afkOn
    SetAntiAFK(!afkOn)
}

SetAntiAFK(on) {
    global afkOn, afkNextDue, afkHookTick, gEarnOn
    afkOn := on
    afkNextDue := 0
    if (on) {
        InstallKeybdHook()
        InstallMouseHook()
        if (!afkHookTick)
            afkHookTick := A_TickCount
    }
    ; 수익 자동화가 켜져 있으면 EarnTick 이 할 작업이 없는 틈에 AntiAFKTick 을 부른다(한 플로우, 1019 사용자 지시). 따로 도는 타이머는 수익이 꺼졌을 때만 쓴다.
    SetTimer(AntiAFKTick, on && !(IsSet(gEarnOn) && gEarnOn) ? 5000 : 0)
    key := KeyLabelFor("AntiAFK")
    ShowTooltip(on ? "🟢 AFK 방지 켜짐 (" key ": 끄기)" : "⚪ AFK 방지 꺼짐 (" key ": 켜기)", 2000)
    AFKLog(on ? "on" : "off")
}

AntiAFKTick() {
    global afkOn, afkNextDue, config, clawLoopRunning, gEarnBusy, gMenuBusy, gAFKBusy, afkRefocusFails, afkRefocusLastErr, gAFKScreenGuard
    if (!afkOn || gAFKBusy)
        return
    if (IsSet(clawLoopRunning) && clawLoopRunning)
        return
    ; 수익 자동화가 메뉴·터미널을 조작하는 동안 W/S 가 끼어들면 선택 줄이 움직인다
    if (IsSet(gEarnBusy) && gEarnBusy)
        return
    if (IsSet(gMenuBusy) && gMenuBusy)
        return
    if (AnyInputToggleOn())
        return
    if (AFKPhysicalIdleMs() < config["Settings"]["AFKUserIdleSec"] * 1000)
        return
    if (afkNextDue && A_TickCount < afkNextDue)
        return
    if (!WinExist("ahk_exe GTA5_Enhanced.exe"))
        return
    ; 작텔(Alt+F4·스팀 봇·MC)이 도는 중에는 누르지 않는다. 스팀 봇 작텔은 도착까지 최대 90초 입력 없이 기다려 유휴 시간을 넘길 수 있고,
    ; 그때 끼어든 W/S 나 GTA 전면화가 그쪽의 알림 판정·스팀 클릭 사이에 들어간다
    if (IsTeleportRunning())
        return
    try inputLock := AFKInputLockAcquire()
    catch as err {
        AFKLog("input lock blocked: " err.Message)
        afkNextDue := A_TickCount + 120000
        return
    }
    if (!IsObject(inputLock))
        return
    idleSec := Round(AFKPhysicalIdleMs() / 1000)
    gAFKBusy := true
    try {
        if (!IsGTAActive()) {
            ; 유휴를 둘로 잰다. 물리 유휴(AFKPhysicalIdleMs)는 SetAntiAFK 가 깐 훅 덕에 주입 입력으로는 줄지 않는다. 사람이 자리에 있으면 짧다.
            ; 크롬 원격 데스크톱으로 쓰는 사람과 computer-use·코덱스 같은 에이전트의 입력은 주입 입력이라 물리 유휴에 안 잡힌다. 그때 GTA 를
            ; 가져오면 그 클릭·타이핑이 게임으로 들어간다(클릭은 사격, T 뒤 글자와 Enter 는 공개 채팅). 그래서 이 매크로 것을 뺀 주입 포함
            ; 유휴(AFKOthersIdleMs)도 기준을 넘어야 한다. 대가: 에이전트가 15분 넘게 쉬지 않고 입력하면 방치 킥을 못 막는다.
            refocusSec := config["Settings"].Get("AFKRefocusIdleSec", 300)
            othersMs := AFKOthersIdleMs()
            if (refocusSec <= 0 || AFKPhysicalIdleMs() < refocusSec * 1000 || othersMs < refocusSec * 1000) {
                AFKLog("skip: GTA 포커스 없음, 전면화하지 않음 (idle=" idleSec "s, 주입 포함 idle=" Round(othersMs / 1000) "s"
                    . (refocusSec > 0 ? ", 기준 " refocusSec "s)" : ", 전면화 꺼짐)"))
                afkNextDue := A_TickCount + 30000
                return
            }
            if (!AFKRefocusGTA(idleSec, othersMs))
                return
            ; 전면화 직후 곧바로 키를 보내지 않는다. 기다리는 사이 사람이 돌아오거나 포커스를 다시 잃으면 이번 차례는 건너뛰고,
            ; 다음 시도는 30초 뒤로 미룬다(5초 틱마다 창을 뺏고 뺏기지 않게)
            afkNextDue := A_TickCount + 30000
            if (!AFKWait(config["Settings"].Get("AFKRefocusSettleMs", 800))) {
                ; 사람이 돌아와 다른 창을 눌렀으면 전면화 실패가 아니다
                if (!IsGTAActive() && AFKPhysicalIdleMs() >= Max(1, config["Settings"]["AFKUserIdleSec"]) * 1000)
                    AFKRefocusFailed("전면화 뒤 포커스를 다시 잃음", idleSec)
                return
            }
        }
        if (!AFKInputAllowed())
            return
        closeSec := config["Settings"].Get("AFKMCTCloseIdleSec", 300)
        if (IsObject(gAFKScreenGuard) && closeSec > 0 && AFKPhysicalIdleMs() >= closeSec * 1000) {
            AFKSelfInput(true)
            try guarded := gAFKScreenGuard.Call(idleSec)
            catch as err
                guarded := "화면 정리 오류: " err.Message
            finally
                AFKSelfInput(false)
            if (guarded != "")
                AFKLog(guarded)
            if (!AFKInputAllowed())
                return
        }
        ; 화면 판독에 의존하지 않는 작은 마우스 왕복. 사용자 개입 시 복귀 입력도 취소한다.
        AFKSelfInput(true)
        try {
            if (!AFKMousePulse())
                return
            action := "mouse pulse dx=2,-2"
        } finally {
            AFKSelfInput(false)
        }
        jitter := config["Settings"]["AFKJitterSec"]
        afkNextDue := A_TickCount + (config["Settings"]["AFKIntervalSec"] + Random(-jitter, jitter)) * 1000
        AFKLog(action " idle=" idleSec "s gameIdle=unverified")
        afkRefocusFails := 0
        afkRefocusLastErr := ""
    } finally {
        gAFKBusy := false
        AFKInputLockRelease(inputLock)
    }
}

; GUI receiver는 이름 존재로 진입을 막으므로 그 이름도 AFK 종료까지 예약한다.
; standalone afk-guard가 같은 스레드에서 이미 가진 macro mutex는 재귀 취득/해제가 된다.
AFKInputLockAcquire(macroName := "Local\GtaMacroInput", guiName := "Local\GtaGuiInput") {
    guiHandle := DllCall("CreateMutexW", "ptr", 0, "int", 0, "str", guiName, "ptr")
    existed := A_LastError = 183
    if (!guiHandle)
        throw Error("GUI 입력 잠금을 만들지 못함")
    if (existed) {
        DllCall("CloseHandle", "ptr", guiHandle)
        return 0
    }
    macroHandle := 0
    try {
        macroHandle := DllCall("CreateMutexW", "ptr", 0, "int", 0, "str", macroName, "ptr")
        if (!macroHandle)
            throw Error("매크로 입력 잠금을 만들지 못함")
        acquired := DllCall("WaitForSingleObject", "ptr", macroHandle, "uint", 0, "uint")
        if (acquired = 0 || acquired = 0x80)
            return {macro: macroHandle, gui: guiHandle}
        if (acquired != 0x102)
            throw Error("매크로 입력 잠금 상태를 확인하지 못함")
    } catch as err {
        if (macroHandle)
            DllCall("CloseHandle", "ptr", macroHandle)
        DllCall("CloseHandle", "ptr", guiHandle)
        throw err
    }
    DllCall("CloseHandle", "ptr", macroHandle)
    DllCall("CloseHandle", "ptr", guiHandle)
    return 0
}

AFKInputLockRelease(inputLock) {
    try {
        DllCall("ReleaseMutex", "ptr", inputLock.macro)
    } finally {
        DllCall("CloseHandle", "ptr", inputLock.macro)
        DllCall("CloseHandle", "ptr", inputLock.gui)
    }
}

; 물리 유휴와 주입 포함 유휴가 둘 다 AFKRefocusIdleSec 을 넘었을 때만 AntiAFKTick 이 부른다. GTA 를 앞으로 가져오면 true.
; 이 함수가 직접 누르는 키는 앞 창이 입력 도구(TextInputHost)거나 없을 때의 Alt 한 번뿐이다(BringGTAToFront 3차와 같은 조건).
; 다만 AHK 의 WinActivate 는 부드러운 방법이 실패하면 스스로 Alt 를 두 번 누를 수 있다(AHK 소스 기준, 실측 안 함).
; 이 Alt 들은 AFKSelfInput 구간 안에 있어 주입 포함 유휴를 되돌리지 않는다(되돌리면 실패 뒤 재시도가 기준 시간만큼 밀린다).
AFKRefocusGTA(idleSec, othersMs) {
    global GTA_WIN, afkRefocusFails, afkRefocusStretch, afkRefocusLastErr, afkRefocusWindow, afkNextDue
    if (!AFKRefocusAllowed())
        return AFKRefocusCanceled()
    ; 그사이 물리 입력이 한 번이라도 있었으면 새 유휴 구간이다. 실패 횟수와 적어 둔 까닭을 비운다.
    stretch := A_TickCount - AFKPhysicalIdleMs()
    fgLabel := AFKForegroundLabel()
    if (Abs(stretch - afkRefocusStretch) > 2000 || fgLabel != afkRefocusWindow) {
        afkRefocusStretch := stretch
        afkRefocusFails := 0
        afkRefocusLastErr := ""
        afkRefocusWindow := fgLabel
    }
    if (afkRefocusFails >= 3) {
        afkNextDue := A_TickCount + 120000
        return false
    }
    gtaHwnd := WinExist(GTA_WIN)
    if (!gtaHwnd)
        return AFKRefocusFailed("GTA 창 없음", idleSec, fgLabel)
    via := ""
    AFKSelfInput(true)
    try {
        if (WinGetMinMax("ahk_id " gtaHwnd) = -1)
            WinRestore("ahk_id " gtaHwnd)
        if (!AFKRefocusAllowed())
            return AFKRefocusCanceled()
        WinActivate("ahk_id " gtaHwnd)
        activated := WinWaitActive("ahk_id " gtaHwnd, , 2)
        ; 0926 14:49~15:18 에 TextInputHost 가 앞에 있는 동안 전면화가 계속 실패해 방치 킥을 당했다. 그 경우와 앞 창이 없을 때만
        ; Alt 를 한 번 눌렀다 떼고 한 번 더 가져온다. 브라우저·탐색기에서는 Alt 가 메뉴 바를 켜므로 쓰지 않는다.
        if (!activated) {
            if (!AFKRefocusAllowed())
                return AFKRefocusCanceled()
            fg := WinExist("A")
            fgExe := ""
            if (fg)
                try fgExe := WinGetProcessName("ahk_id " fg)
            if (fg && fgExe = "ShellExperienceHost.exe" && WinGetTitleSafe(fg) == "New notification") {
                dismissal := AFKDismissNotification(fg)
                if (!AFKRefocusAllowed())
                    return AFKRefocusCanceled()
                if (dismissal != "dismissed")
                    return AFKRefocusFailed("알림 복귀 " dismissal, idleSec, fgLabel)
                via := " (알림을 알림 센터로 이동)"
                WinActivate("ahk_id " gtaHwnd)
                activated := WinWaitActive("ahk_id " gtaHwnd, , 2)
            } else if (!fg || fgExe = "TextInputHost.exe") {
                via := " (Alt 보조: " (fg ? fgExe : "앞 창 없음") ")"
                Send("{Blind}{Alt down}{Alt up}")
                WinActivate("ahk_id " gtaHwnd)
                activated := WinWaitActive("ahk_id " gtaHwnd, , 2)
            }
        }
    } catch as err {
        return AFKRefocusFailed("오류 " err.Message, idleSec, fgLabel)
    } finally {
        AFKSelfInput(false)
    }
    if (!activated || !IsGTAActive())
        return AFKRefocusFailed("2초 안에 앞으로 오지 않음" via, idleSec, fgLabel)
    AFKLog("refocus ok idle=" idleSec "s 주입 포함 idle=" Round(othersMs / 1000) "s 앞 창=" fgLabel via
        . (afkRefocusFails ? " (앞선 실패 " afkRefocusFails "회 뒤)" : ""))
    return true
}

; 긴 창 활성화/OCR 대기 사이에도 최근 입력과 다른 매크로의 소유권을 다시 확인한다.
AFKRefocusAllowed() {
    global afkOn, config, clawLoopRunning, gEarnBusy, gMenuBusy
    threshold := config["Settings"].Get("AFKRefocusIdleSec", 300)
    return afkOn && threshold > 0
        && AFKPhysicalIdleMs() >= Max(1, threshold, config["Settings"]["AFKUserIdleSec"]) * 1000
        && AFKOthersIdleMs() >= threshold * 1000
        && !(IsSet(clawLoopRunning) && clawLoopRunning)
        && !(IsSet(gEarnBusy) && gEarnBusy) && !(IsSet(gMenuBusy) && gMenuBusy)
        && !IsTeleportRunning() && !AnyInputToggleOn()
}

AFKRefocusCanceled() {
    global afkNextDue
    afkNextDue := A_TickCount + 30000
    AFKLog("refocus 취소: 최근 입력 또는 다른 매크로. 전면화/알림 조작 중단")
    return false
}

; 현재 관측된 Windows 알림의 닫기 버튼만 UIA로 누른다. 승인/거절 버튼은 대상이 아니다.
; 자식은 HWND/PID/제목/마지막 입력 tick을 Invoke 직전 다시 확인한다.
AFKDismissNotification(hwnd) {
    global afkSelfBefore
    if (!AFKRefocusAllowed() || WinExist("A") != hwnd
        || WinGetProcessName("ahk_id " hwnd) != "ShellExperienceHost.exe"
        || WinGetTitleSafe(hwnd) !== "New notification")
        return "blocked:foreground-or-input"
    notificationPid := WinGetPID("ahk_id " hwnd)
    lastInput := Buffer(8, 0)
    NumPut("uint", 8, lastInput)
    if (!DllCall("GetLastInputInfo", "ptr", lastInput))
        return "error:last-input"
    lastInputTick := NumGet(lastInput, 4, "uint")
    SplitPath(A_LineFile, , &sourceDir)
    output := A_Temp "\gta-afk-notification-" DllCall("GetCurrentProcessId") "-" A_TickCount ".txt"
    command := '"' A_WinDir '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "'
        . sourceDir '\..\Core\NotificationDismiss.ps1" -WindowHandle ' hwnd ' -ProcessId ' notificationPid
        . ' -LastInputTick ' lastInputTick ' -OutputPath "' output '"'
    handle := 0, childPid := 0
    try {
        Run(command, , "Hide", &childPid)
        handle := DllCall("OpenProcess", "uint", 0x101001, "int", false, "uint", childPid, "ptr")
        if (!handle) {
            if (ProcessExist(childPid))
                ProcessClose(childPid)
            return "error:process-handle"
        }
        deadline := A_TickCount + 8000
        while (DllCall("WaitForSingleObject", "ptr", handle, "uint", 0, "uint") = 0x102) {
            allowed := AFKRefocusAllowed()
            if (!allowed || A_TickCount > deadline) {
                DllCall("TerminateProcess", "ptr", handle, "uint", 1)
                DllCall("WaitForSingleObject", "ptr", handle, "uint", 2000)
                return allowed ? "error:timeout" : "blocked:recent-input"
            }
            Sleep(25)
        }
        code := 1
        if (!DllCall("GetExitCodeProcess", "ptr", handle, "uint*", &code) || !FileExist(output))
            return "error:missing-result"
        result := Trim(FileRead(output, "UTF-8"))
        ; 알림을 읽는 동안의 외부 입력을 자기 WinActivate의 Alt로 오인해 숨기지 않는다.
        if (result = "blocked:input-changed")
            afkSelfBefore := A_TickCount - A_TimeIdle
        if (code = 0 && result = "dismissed") {
            ; 자식 종료 직후 마지막 입력이 바뀌었으면 자기 입력이라고 추측하지 않는다.
            if (!DllCall("GetLastInputInfo", "ptr", lastInput))
                return "error:last-input"
            if (NumGet(lastInput, 4, "uint") != lastInputTick) {
                afkSelfBefore := A_TickCount - A_TimeIdle
                return "blocked:recent-input"
            }
            if (!AFKRefocusAllowed())
                return "blocked:recent-input"
            return result
        }
        return RegExMatch(result, "^(blocked|error):[a-z0-9_-]+$") ? result : "error:invalid-result"
    } catch {
        if (handle && DllCall("WaitForSingleObject", "ptr", handle, "uint", 0, "uint") = 0x102) {
            DllCall("TerminateProcess", "ptr", handle, "uint", 1)
            DllCall("WaitForSingleObject", "ptr", handle, "uint", 2000)
        }
        return "error:helper"
    } finally {
        if (handle)
            DllCall("CloseHandle", "ptr", handle)
        if (FileExist(output))
            FileDelete(output)
    }
}

; 물리 입력 유휴(ms). A_TimeIdlePhysical 은 훅을 깐 순간부터 다시 세므로 Main 을 켠 직후에는 실제보다 짧다
; (0928 실측: 133초 비운 뒤 훅을 깔고 1.5초 만에 1531ms). 훅을 깐 뒤 물리 입력을 한 번도 못 봤으면 주입 포함 유휴로 메운다.
; 주입 포함 유휴는 물리 입력도 세므로 실제 물리 유휴보다 길 수 없다. 물리 입력을 본 뒤에는 A_TimeIdlePhysical 만 쓴다
; (이 매크로가 입력하는 구간에 사람이 누른 키는 AFKOthersIdleMs 에서 가려지므로 섞으면 사람 복귀를 놓친다).
AFKPhysicalIdleMs() {
    global afkHookTick
    phys := A_TimeIdlePhysical
    if (afkHookTick && phys >= A_TickCount - afkHookTick - 1000)
        return Max(phys, AFKOthersIdleMs())
    return phys
}

; 이 매크로 밖의 마지막 입력부터 지난 ms. 물리 입력에 더해 원격 데스크톱·에이전트·다른 프로그램이 주입한 입력도 센다
; (A_TimeIdle 은 GetLastInputInfo 값이다). 마지막 입력이 이 매크로가 입력하던 구간(끝난 뒤 500ms 까지) 안이면 그 구간 직전 값으로 센다.
; 구간 시작이 아니라 그 직전 남의 입력(afkSelfBefore) 이후를 가린다. 수익 작업이 끝나고 몇 초 뒤 AFK 가 새 구간을 열면
; 수익 작업의 마지막 키가 새 구간 시작보다 앞이라 남의 입력으로 잡혀, 44분 방치 중 30fps 제한이 3초 만에 풀렸다(1006 00:39·00:52).
; 두 구간 사이의 남의 입력은 새 구간을 열 때 afkSelfBefore 에 들어가므로 계속 센다.
AFKOthersIdleMs() {
    global afkSelfFrom, afkSelfTo, afkSelfBefore
    last := A_TickCount - A_TimeIdle
    if (afkSelfFrom && last > afkSelfBefore && (!afkSelfTo || last <= afkSelfTo + 500))
        last := afkSelfBefore
    return A_TickCount - last
}

; 이 매크로가 입력을 넣는 구간의 시작(true)과 끝(false). 그 사이 입력은 AFKOthersIdleMs 가 남의 입력으로 세지 않는다.
AFKSelfInput(start) {
    global afkSelfFrom, afkSelfTo, afkSelfBefore
    if (start) {
        afkSelfBefore := A_TickCount - AFKOthersIdleMs()
        afkSelfFrom := A_TickCount
        afkSelfTo := 0
    } else {
        afkSelfTo := A_TickCount
    }
}

; 첫 두 실패 뒤 30초/60초 대기. 세 번째도 실패하면 같은 앞 창/유휴 구간의 재시도를 막고 경고한다.
; 로그는 유휴 구간의 첫 실패와 까닭이 바뀐 때만 남긴다. 항상 false 를 돌려준다.
AFKRefocusFailed(reason, idleSec, fgLabel := "") {
    global afkNextDue, afkRefocusFails, afkRefocusLastErr
    afkRefocusFails += 1
    waitSec := 30 * 2 ** Min(afkRefocusFails - 1, 2)
    afkNextDue := A_TickCount + waitSec * 1000
    if (afkRefocusFails = 1 || reason != afkRefocusLastErr)
        AFKLog("refocus 실패: " reason " idle=" idleSec "s 앞 창=" (fgLabel = "" ? AFKForegroundLabel() : fgLabel)
            . " (다음 시도 " waitSec "초 뒤, 같은 까닭은 다시 적지 않음)")
    afkRefocusLastErr := reason
    if (afkRefocusFails = 3) {
        AFKLog("refocus blocked: 3회 실패. 앞 창/사용자 유휴 구간이 바뀌기 전 추가 전면화 없음. AFK 입력 미확인: " reason)
        ShowTooltip("⚠ AFK 복귀 막힘: GTA 포커스와 알림을 확인하세요. " reason, 10000)
    }
    return false
}

; 지금 앞에 있는 창을 "exe / 제목" 으로. 무엇이 GTA 포커스를 가져갔는지 로그로 알 수 있게 한다.
AFKForegroundLabel() {
    fgHwnd := WinExist("A")
    if (!fgHwnd)
        return "없음"
    exe := ""
    try exe := WinGetProcessName("ahk_id " fgHwnd)
    return (exe = "" ? "?" : exe) " / " WinGetTitleSafe(fgHwnd)
}

AFKInputAllowed() {
    global afkOn, config, gEarnBusy, gMenuBusy
    return afkOn && IsGTAActive()
        && AFKPhysicalIdleMs() >= Max(1, config["Settings"]["AFKUserIdleSec"]) * 1000
        && !(IsSet(gEarnBusy) && gEarnBusy) && !(IsSet(gMenuBusy) && gMenuBusy)
        && !IsTeleportRunning() && !AnyInputToggleOn()
}

; 키를 누른 채 있으면(헬기 상승·가속 유지) 유휴 시간이 늘어도 조작 중이다. 그동안은 아무것도 보내지 않는다.
AFKKeysHeld() {
    for k in ["w","a","s","d","q","e","Space","Shift","Ctrl","LButton","RButton","Up","Down","Left","Right","Numpad8","Numpad5","Numpad4","Numpad6"]
        if (GetKeyState(k, "P"))
            return true
    return false
}

AFKWait(ms) {
    deadline := A_TickCount + ms
    while (A_TickCount < deadline) {
        if (!AFKInputAllowed())
            return false
        Sleep(Min(25, Max(1, deadline - A_TickCount)))
    }
    return AFKInputAllowed()
}

AFKMousePulse() {
    if (!AFKInputAllowed() || AFKKeysHeld())
        return false
    DllCall("mouse_event", "uint", 1, "int", 2, "int", 0, "uint", 0, "uptr", 0)
    if (!AFKWait(100) || AFKKeysHeld())
        return false
    DllCall("mouse_event", "uint", 1, "int", -2, "int", 0, "uint", 0, "uptr", 0)
    return true
}


AFKMenuSeen(name) {
    if (name = "game_hud")
        return AFKFreeHud()
    area := name = "m_title" ? [0,0,0.27,0.55] : name = "mct_title" ? [0.3,0,0.7,0.1]
        : name = "mct_terrorbyte" ? [0,0,0.3,0.25] : [0,0,0.3,0.1]
    ; 흰 글자만 보는 템플릿은 밝은 하늘 위에서 오탐한다. 맞은 자리의 바탕이 어두워야 인정한다(EarnSeen 과 같은 기준).
    if (name = "mct_seated") {
        fx := 0, fy := 0
        for part in ["mct_seated_mansion", "mct_seated"]
            if (TemplateSeen("Earn", part, area, &fx, &fy) && TemplateAt("Earn", part "_bg", fx, fy))
                return true
        return false
    }
    if (name = "mct_sit") {
        fx := 0, fy := 0
        return TemplateSeen("Earn", "mct_sit", area, &fx, &fy) && TemplateAt("Earn", "mct_sit_bg", fx, fy)
    }
    ; 테러바이트 안내는 반투명 상자와 남은 커서 때문에 세 줄 중 하나만 맞아도 인정한다(EarnSeen 과 같은 기준).
    if (name = "mct_terrorbyte") {
        for part in ["mct_terrorbyte", "mct_terrorbyte_reg", "mct_terrorbyte_ceo"]
            if (TemplateSeen("Earn", part, area, , , 60))
                return true
        fx := 0, fy := 0
        return (TemplateSeen("Earn", "mct_terrorbyte_access_native", area, &fx, &fy, 40)
            && TemplateAt("Earn", "mct_terrorbyte_access_native_bg", fx, fy, 60))
            || (TemplateSeen("Earn", "mct_terrorbyte_ceo_native", area, &fx, &fy, 40)
            && TemplateAt("Earn", "mct_terrorbyte_ceo_native_bg", fx, fy, 60))
    }
    return TemplateSeen("Earn", name, area)
}

; 시점이 바뀌어 MCT 접근 안내가 없어도 위치·카메라를 움직이지 않는다.
; 전화와 Vinewood 앱에서도 미니맵은 보이므로 HUD만 보고 M을 누르지 않는다.
AFKPhoneOrAppOpen() {
    if (!AFKInputAllowed())
        return false
    return TemplateSeen("Earn", "afk_phone_frame", [0.83,0.58,0.98,0.72])
        || TemplateSeen("Earn", "ph_joblist_sel", [0.83,0.66,0.98,0.73])
        || TemplateSeen("Earn", "ph_vinewood_sel", [0.83,0.66,0.98,0.73])
        || TemplateSeen("Earn", "afk_vinewood_title", [0,0,0.27,0.2])
}

AFKFreeHud() {
    global gImageRoot
    if (!AFKInputAllowed() || !AFKHudVisible())
        return false
    for name in ["afk_phone_frame", "afk_vinewood_title"]
        if (!FileExist(gImageRoot "\Earn\1920x1080\" name ".png"))
            return false
    if (TemplateSeen("Earn", "afk_phone_frame", [0.83,0.58,0.98,0.72])
        || TemplateSeen("Earn", "ph_joblist_sel", [0.83,0.66,0.98,0.73])
        || TemplateSeen("Earn", "ph_vinewood_sel", [0.83,0.66,0.98,0.73])
        || TemplateSeen("Earn", "afk_vinewood_title", [0,0,0.27,0.2]))
        return false
    area := [0,0,0.27,0.55]
    return !TemplateSeen("Earn", "m_title", area) && !TemplateSeen("Earn", "m_pref_title", area)
        && !TemplateSeen("JobWarp", "m_sub_boss", area) && !TemplateSeen("JobWarp", "m_sub_securo", area)
        && AFKInputAllowed()
}

; EarnCore 없이 standalone AFK에서도 같은 실측 체력 막대를 확인한다.
AFKHudVisible() {
    if (!AFKInputAllowed())
        return false
    return HealthHudVisible()
}




; 다른 창이 앞에 있어도 GTA 를 앞으로 가져온다. 일반 WinActivate 는 Windows 가 거부하는 경우가 있어
; 앞 창의 입력 스레드에 잠깐 붙어서 가져온다. 앞 창에는 키를 보내지 않는다: Windows 검색 창은 포커스를 잃으면 스스로 닫히고,
; 브라우저·탐색기는 Alt 를 받으면 메뉴 바가 활성화된다. 그래도 안 되면 할당되지 않은 가상 키(vkE8) 하나를 눌러 한 번 더 시도한다
; (최근 키 입력이 있어야 전면화를 허용하는 경우 대비. 어느 앱도 vkE8 에 동작을 두지 않는다).
BringGTAToFront() {
    hwnd := WinExist("ahk_exe GTA5_Enhanced.exe")
    if (!hwnd)
        return false
    try {
        if (WinGetMinMax("ahk_id " hwnd) = -1)
            WinRestore("ahk_id " hwnd)
    }
    Loop 2 {
        if (A_Index = 2)
            Send("{Blind}{vkE8}")
        fg := DllCall("GetForegroundWindow", "ptr")
        fgThread := DllCall("GetWindowThreadProcessId", "ptr", fg, "ptr", 0, "uint")
        myThread := DllCall("GetCurrentThreadId", "uint")
        DllCall("AttachThreadInput", "uint", myThread, "uint", fgThread, "int", 1)
        DllCall("BringWindowToTop", "ptr", hwnd)
        DllCall("SetForegroundWindow", "ptr", hwnd)
        DllCall("AttachThreadInput", "uint", myThread, "uint", fgThread, "int", 0)
        Sleep(800)
        if (WinActive("ahk_id " hwnd)) {
            AFKLog("GTA 를 앞으로 가져옴" (A_Index = 2 ? " (2차 시도)" : ""))
            return true
        }
    }
    ; 3차: 앞 창이 입력 도구(TextInputHost: 이모지·터치 키보드·IME 창)거나 앞 창이 없으면 Alt 를 한 번 눌렀다 떼고 AHK WinActivate 로 가져온다.
    ; 0926 14:49~15:18 에 TextInputHost 가 앞에 있는 동안 1·2차가 계속 실패해 30분 가까이 입력이 끊겼고 게임에서 방치 킥을 당했다.
    ; Alt 는 브라우저·탐색기에서 메뉴 바를 켜므로 이 두 경우에만 쓴다.
    fg := DllCall("GetForegroundWindow", "ptr")
    fgExe := ""
    try fgExe := WinGetProcessName("ahk_id " fg)
    if (!fg || fgExe = "TextInputHost.exe") {
        Send("{Blind}{Alt down}{Alt up}")
        try WinActivate("ahk_id " hwnd)
        Sleep(800)
        if (WinActive("ahk_id " hwnd)) {
            AFKLog("GTA 를 앞으로 가져옴 (3차: " (fgExe = "" ? "앞 창 없음" : fgExe) ")")
            return true
        }
    }
    AFKLog("앞 창: " (fgExe = "" ? "없음" : fgExe) " / " WinGetTitleSafe(fg))
    return false
}

WinGetTitleSafe(hwnd) {
    t := ""
    try t := WinGetTitle("ahk_id " hwnd)
    return t
}

AFKLog(msg) {
    try FileAppend(FormatTime(, "HH:mm:ss") " " msg "`n", A_Temp "\gta-afk.log", "UTF-8")
}
