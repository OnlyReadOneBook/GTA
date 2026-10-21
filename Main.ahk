#Requires AutoHotkey v2.0
#SingleInstance Force
; Send 는 기본값에서 보내기 전 CapsLock 을 껐다가 되돌린다 → CapsLock 이 켜져 있으면 W/S 앞뒤로 CapsLock 눌림이 게임에 들어가 특수 능력이 발동한다 (0926 원인 확정). 끈다.
SetStoreCapsLockMode false
; Alt/Win 이 든 조합 뒤에 기본 마스크 키(LCtrl)가 끼어 게임에서 웅크리기가 되는 일을 막는다. vkE8 은 할당되지 않은 가상 키다.
A_MenuMaskKey := "vkE8"

; === 코어 모듈 로드 ===
#Include Core\PressKey.ahk
#Include Core\ClickMouse.ahk
#Include Core\Common.ahk
#Include Core\ConfigLoader.ahk
#Include Core\HotkeyManager.ahk
#Include Core\Menu.ahk
#Include Core\Screen.ahk

; === 기능 모듈 로드 ===
#Include Features\Teleport\TeleportBase.ahk
#Include Features\Teleport\TeleportMessages.ahk
#Include Features\Teleport\MCTeleport.ahk
#Include Features\Teleport\AltF4Teleport.ahk
#Include Features\Movement.ahk
#Include Features\AutoClick.ahk
#Include Features\CayoPericoTimer.ahk
#Include Features\Hacks\CasinoFingerprint.ahk
#Include Features\ClawMachine.ahk
#Include Features\SessionSwitch.ahk
#Include Features\AntiAFK.ahk
#Include Features\Snack.ahk
#Include Features\Earn\EarnCore.ahk
#Include Features\Earn\EarnLedger.ahk
#Include Features\Earn\EarnScreen.ahk
#Include Features\Earn\EarnPolicy.ahk
#Include Features\Earn\EarnTasks.ahk
#Include Features\Earn\EarnVinewood.ahk
#Include Features\Earn\EarnStaff.ahk
#Include Features\Earn\EarnWarehouseRead.ahk
#Include Features\Earn\EarnWarehouse.ahk
#Include Features\Earn\Earner.ahk
#Include Features\CpuBoost.ahk
#Include Features\MemoryGuard.ahk
#Include Features\StopAll.ahk
#Include Features\Help.ahk
#Include Features\Overlay.ahk
#Include Features\Panel.ahk
#Include Features\DiscordHUD.ahk
#Include Features\SaleQueueAlert.ahk

; === 초기화 ===
; 0929 04:14 이후 AFK 로그가 끊기고 15시쯤 방치 킥을 당했다. 04:15:52 에 Claude 데스크톱 앱이 자동 업데이트로 재시작했는데,
; Claude 세션(셸)이 띄운 Main 은 그 앱의 프로세스 트리·작업 개체 안에 있어 함께 죽었다(OnExit 도 못 돌아 로그에 off 가 없다).
; 탐색기·WMI 가 아닌 부모(claude·셸·터미널)에서 떴으면 WMI 로 부모 없는 새 프로세스를 띄우고 이 사본은 끝낸다.
DetachFromLauncher()
DetachFromLauncher() {
    parent := ""
    try {
        for p in ComObjGet("winmgmts:").ExecQuery("SELECT ParentProcessId FROM Win32_Process WHERE ProcessId=" DllCall("GetCurrentProcessId"))
            for q in ComObjGet("winmgmts:").ExecQuery("SELECT Name FROM Win32_Process WHERE ProcessId=" p.ParentProcessId)
                parent := q.Name
    }
    if (parent = "" || parent = "explorer.exe" || parent = "WmiPrvSE.exe" || parent = "svchost.exe")
        return
    try {
        ComObjGet("winmgmts:").Get("Win32_Process").Create('"' A_AhkPath '" "' A_ScriptFullPath '"', A_ScriptDir, , &pid := 0)
        if (pid) {
            FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " 매크로를 " parent " 밖으로 다시 띄움 (pid " pid ")`n", A_Temp "\gta-afk.log", "UTF-8")
            ExitApp()
        }
    }
}
; 날짜 없는 AFK 로그만으로는 어느 날 켜지고 꺼졌는지 가릴 수 없었다. 시작·종료를 날짜와 함께 남긴다.
FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " 매크로 시작 pid " DllCall("GetCurrentProcessId") "`n", A_Temp "\gta-afk.log", "UTF-8")
OnExit(LogMacroExit)
LogMacroExit(reason, *) {
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " 매크로 종료 (" reason ")`n", A_Temp "\gta-afk.log", "UTF-8")
}
; 스크립트가 이동 키를 누른 채로 종료되면 캐릭터가 계속 걸어가 버린다(실측). 종료 시 항상 뗀다.
OnExit((*) => (ReleaseHeldKeys(), 0))
; 실행 중 오류는 대화상자 대신 로그(%TEMP%\gta-macro.log)와 툴팁으로 알린다. 대화상자는 게임 포커스를 빼앗아 AFK 방지까지 막는다.
OnError(OnScriptError)
OnScriptError(err, mode) {
    try ReleaseHeldKeys()
    MacroLog("error", mode ": " err.Message " (" err.File ":" err.Line ") " err.What)
    try ShowTooltip("⚠ 매크로 오류: " err.Message "`n" err.File ":" err.Line, 5000)
    return 1
}
LoadConfig()
SetupHotkeys()
SetTimer(KeyHookWatchdog, 60000)
SetupTrayMenu()
if (config["Features"]["AntiAFK"] && config["Settings"]["AFKOnStart"])
    SetAntiAFK(true)
; 게임 화면 오른쪽 위 상태 표시 (클릭 통과·포커스 안 가져감). 설정 창은 트레이 메뉴 또는 도움말 키 두 번.
if (config["Settings"]["OverlayEnabled"])
    SetOverlay(true)
; 디코 오버레이(DiscordChatHUD)를 같이 띄운다. 경로는 Config [Settings] DiscordHUDPath, 비우면 끈다.
StartDiscordHUD()
DiscordHUDVisibilityInit()
EarnIdleInit()

; === 시작 메시지 ===
ShowTooltip("✅ GTA 매크로 시작됨 (게임 창에서만 동작)`n" KeyLabelFor("Help") ": 단축키 보기 (두 번: 설정 창) | " KeyLabelFor("StopAll") ": 전체 멈춤 | " KeyLabelFor("Exit") ": 종료", 3000)
