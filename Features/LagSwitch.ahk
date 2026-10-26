; === 랜선 뽑기 (렉 스위치) ===
; 단축키를 누르고 있는 동안 GTA 의 네트워크를 끊고, 떼면 곧바로 되돌린다. 레이스에서 내 상태가 다른 사람에게 안 가는 구간을 만든다.
; 오래 끊으면 피어 타임아웃으로 세션에서 튕기므로 LagSwitchMaxMs 가 지나면 키를 쥐고 있어도 자동으로 되돌린다.
; 방식(LagSwitchMode):
;   suspend = GTA5_Enhanced.exe 만 NtSuspendProcess 로 멈췄다 NtResumeProcess 로 푼다. 관리자 권한이 필요 없고 복구가 즉시다. 기본값.
;             화면·입력도 같이 멈춘다. 리소스 모니터의 '프로세스 일시 중단'과 같은 동작을 클릭 없이 한다.
;   adapter = 네트워크 어댑터를 껐다 켠다(물리 랜선 뽑기와 같음). 관리자 권한이 필요하고 재연결 지연이 있다. LagSwitchAdapter 가
;             비어 있으면 연결된 물리 어댑터 중 첫 번째를 쓴다.
; 어느 쪽이 레이스에서 더 낫게 보이는지는 실측하지 않았다. Config.ini [Hotkeys] LagSwitch 에 키를 적으면 켜진다.
; 안전: 이 프로세스가 죽거나 종료돼도 멈춘 GTA 를 풀도록 OnExit 가 되돌린다. 강제 종료(작업 관리자)는 못 풀 수 있다.
global gLagActive := false
global gLagHandle := 0
global gLagAdapter := ""

ExecuteLagSwitch() {
    global config, gLagActive
    if (gLagActive || !IsGTAActive())
        return
    s := config["Settings"]
    mode := StrLower(Trim(s["LagSwitchMode"]))
    key := RegExReplace(A_ThisHotkey, "^[~*$]+")
    if (!LagSwitchCut(mode, s))
        return
    gLagActive := true
    start := A_TickCount
    MacroLog("lagswitch", mode " cut")
    ShowTooltip("🔌 랜선 뽑음 (" mode ")", 600)
    try {
        ; 키를 떼면 즉시, 아니면 최대 시간 뒤에 복구한다. 자동 반복으로 다시 들어오는 누름은 위에서 gLagActive 로 걸러진다.
        KeyWait(key, "T" (s["LagSwitchMaxMs"] / 1000))
    }
    LagSwitchRestore("held " (A_TickCount - start) "ms")
}

LagSwitchCut(mode, s) {
    global gLagHandle, gLagAdapter
    if (mode = "adapter") {
        if (!A_IsAdmin) {
            ShowTooltip("랜선 뽑기: adapter 방식은 관리자 권한이 필요합니다", 2500)
            return false
        }
        name := Trim(s["LagSwitchAdapter"])
        if (name = "")
            name := LagSwitchPS("(Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Select-Object -First 1).Name")
        if (name = "") {
            ShowTooltip("랜선 뽑기: 연결된 물리 어댑터를 못 찾음", 2500)
            return false
        }
        gLagAdapter := name
        q := "'" StrReplace(name, "'", "''") "'"
        ; 끄기가 실패해도 오류는 출력 파일로만 간다. 상태를 다시 읽어 실제로 꺼졌을 때만 끊긴 것으로 본다.
        if (LagSwitchPS("Disable-NetAdapter -Name " q " -Confirm:`$false; (Get-NetAdapter -Name " q ").Status") != "Disabled") {
            LagSwitchRestore("disable failed")
            ShowTooltip("랜선 뽑기: 어댑터 " name " 를 끄지 못함", 2500)
            return false
        }
        return true
    }
    try
        pid := WinGetPID(GTA_WIN)
    catch {
        ShowTooltip("랜선 뽑기: GTA 창을 못 찾음", 1500)
        return false
    }
    h := DllCall("OpenProcess", "UInt", 0x800, "Int", 0, "UInt", pid, "Ptr")   ; PROCESS_SUSPEND_RESUME
    if (!h) {
        ShowTooltip("랜선 뽑기: GTA 프로세스를 못 엶 (관리자로 실행된 게임이면 이 매크로도 관리자여야 함)", 3000)
        return false
    }
    if (DllCall("ntdll\NtSuspendProcess", "Ptr", h) != 0) {
        DllCall("CloseHandle", "Ptr", h)
        ShowTooltip("랜선 뽑기: 프로세스 일시 중단 실패", 2000)
        return false
    }
    gLagHandle := h
    return true
}

LagSwitchRestore(why := "") {
    global gLagActive, gLagHandle, gLagAdapter
    if (gLagHandle) {
        DllCall("ntdll\NtResumeProcess", "Ptr", gLagHandle)
        DllCall("CloseHandle", "Ptr", gLagHandle)
        gLagHandle := 0
    }
    if (gLagAdapter != "") {
        LagSwitchPS("Enable-NetAdapter -Name '" StrReplace(gLagAdapter, "'", "''") "' -Confirm:`$false")
        gLagAdapter := ""
    }
    if (gLagActive) {
        gLagActive := false
        MacroLog("lagswitch", "restored " why)
        ShowTooltip("🔌 랜선 꽂음", 600)
    }
}

; 창 없이 PowerShell 한 줄을 돌리고 출력 첫 줄을 돌려준다.
LagSwitchPS(cmd) {
    out := A_Temp "\gta-lagswitch.txt"
    try FileDelete(out)
    RunWait(A_ComSpec ' /c powershell -NoProfile -Command "' StrReplace(cmd, '"', '\"') '" > "' out '" 2>&1', , "Hide")
    try return Trim(StrSplit(FileRead(out), "`n", "`r")[1])
    return ""
}

OnExit((*) => (LagSwitchRestore("exit"), 0))
