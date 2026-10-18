#Requires -Version 5.1
param(
    [string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
    [string]$SourceRoot = (Join-Path $PSScriptRoot '..\..')
)
$ErrorActionPreference = 'Stop'
$source = Get-Content (Join-Path $SourceRoot 'Features\AntiAFK.ahk') -Raw -Encoding UTF8
$screenSource = Get-Content (Join-Path $SourceRoot 'Core\Screen.ahk') -Raw -Encoding UTF8
$source += "`n" + $screenSource
$functions = @('AntiAFKTick', 'AFKInputAllowed', 'AFKMousePulse', 'AFKKeysHeld', 'AFKMenuSeen', 'AFKFreeHud', 'AFKPhoneOrAppOpen', 'AFKHudVisible',
    'AFKRefocusGTA', 'AFKRefocusFailed', 'AFKForegroundLabel', 'AFKPhysicalIdleMs', 'AFKOthersIdleMs', 'AFKSelfInput',
    'AFKRefocusAllowed', 'AFKRefocusCanceled', 'HealthHudVisible', 'HealthHudColors') | ForEach-Object {
    $body = [regex]::Match($source, ('(?ms)^' + $_ + '\([^)\r\n]*\) \{.*?^\}')).Value
    if (-not $body) { throw "$_ missing" }
    $body
}
# A_TimeIdlePhysical(훅이 본 물리 입력)은 idleMs, A_TimeIdle(주입 포함 전체 입력)은 AnyIdle() 로 바꿔 끼운다.
# A_TickCount 는 AFKWait 만 앞으로 미는 가짜 시계 FakeTick() 으로 바꾼다. 실제 시계를 쓰면 idleMs 를 고정한 채
# 틱 사이에 2초 넘게 흐를 때(병렬 CI 부하) AFKRefocusGTA 가 새 유휴 구간으로 보고 실패 횟수를 비운다.
$production = ($functions -join "`n").Replace('A_TimeIdlePhysical', 'idleMs').Replace('A_TimeIdle', 'AnyIdle()').Replace('A_TickCount', 'FakeTick()')
# Main의 실제 유지보수 등록을 가짜 스케줄러로 실행한다. 과거 소스의 F24 probe도
# 같은 테스트에 넣어 AFK 복귀가 영구 연기되는 회귀를 재현할 수 있다.
$mainSource = Get-Content (Join-Path $SourceRoot 'Main.ahk') -Raw -Encoding UTF8
$hotkeySource = Get-Content (Join-Path $SourceRoot 'Core\HotkeyManager.ahk') -Raw -Encoding UTF8
$maintenanceBodies = @()
foreach ($name in @('KeyHookWatchdog', 'KeyHookProbe', 'KeyProbeSeen')) {
    $body = [regex]::Match($hotkeySource, ('(?ms)^' + $name + '\([^\r\n]*\) \{.*?^\}')).Value
    if (-not $body -and $name -eq 'KeyHookWatchdog') { throw 'KeyHookWatchdog missing' }
    if ($body) { $maintenanceBodies += $body }
}
$maintenance = ($maintenanceBodies -join "`n").Replace('A_TickCount', 'FakeTick()')
$maintenance = $maintenance.Replace('DllCall("GetAsyncKeyState", "int", vk, "short")', 'HarnessHeldKey(vk)')
$maintenance = $maintenance.Replace('InstallKeybdHook(', 'HarnessInstallKeybdHook(').Replace('SendEvent(', 'HarnessSendEvent(').Replace('SendLevel(', 'HarnessSendLevel(').Replace('MacroLog(', 'HarnessMacroLog(')
$maintenanceCalls = @('KeyHookWatchdog', 'KeyHookProbe', 'KeyProbeSeen', 'FakeTick', 'HarnessHeldKey', 'HarnessInstallKeybdHook', 'HarnessSendEvent', 'HarnessSendLevel', 'HarnessMacroLog', 'if')
$maintenanceCode = [regex]::Replace($maintenance, '(?m);[^\r\n]*', '')
foreach ($call in [regex]::Matches($maintenanceCode, '(?<![\w.])([A-Za-z_]\w*)\s*\(')) {
    if ($call.Groups[1].Value -cnotin $maintenanceCalls) { throw "Unsafe maintenance call: $($call.Groups[1].Value)" }
}
$timerLines = @([regex]::Matches($mainSource, '(?m)^SetTimer\(KeyHook(?:Watchdog|Probe),\s*-?\d+\)\s*$') | ForEach-Object { $_.Value.Trim().Replace('SetTimer(', 'HarnessSetTimer(') })
$production += "`n" + $maintenance + "`nRegisterMaintenanceTimers() {`n" + ($timerLines -join "`n") + "`n}`n"
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global checkCount := 0
global fakeNow := 50000000
Reset()
afkOn := false
AntiAFKTick()
Check(events.Length = 0, "disabled")
Reset()
gEarnBusy := true
AntiAFKTick()
Check(events.Length = 0, "earn input owner")
Reset()
gMenuBusy := true
AntiAFKTick()
Check(events.Length = 0, "menu input owner")
Reset()
gAFKBusy := true
AntiAFKTick()
Check(events.Length = 0, "AFK reentry")
Reset()
clawLoopRunning := true
AntiAFKTick()
Check(events.Length = 0, "claw owner")
Reset()
teleportBusy := true
AntiAFKTick()
Check(events.Length = 0, "teleport owner")
Reset()
idleMs := 0
AntiAFKTick()
Check(events.Length = 0, "physical user input")
Reset()
afkNextDue := FakeTick() + 100000
AntiAFKTick()
Check(events.Length = 0, "not due")
Reset()
windowExists := false
AntiAFKTick()
Check(events.Length = 0, "game absent")
Reset()
focused := false
AntiAFKTick()
Check(events.Length = 0 && activations = 0 && !gAFKBusy && afkNextDue > FakeTick() && LogHas("skip: GTA 포커스 없음"), "no focus stealing while idle is short")
Reset()
AntiAFKTick()
Check(events.Length = 2 && events[1] = "mouse:2" && events[2] = "mouse:-2" && !gAFKBusy && afkNextDue > FakeTick() && releases = 1, "mouse pair and lock release")
Reset()
gAFKScreenGuard := FakeScreenGuard, idleMs := 301000
AntiAFKTick()
Check(guardCalls = 1 && events.Length = 2 && LogHas("MCT 화면 정리 완료"), "long idle runs the screen guard before the mouse pair")
Reset()
gAFKScreenGuard := FakeScreenGuard, idleMs := 120000
AntiAFKTick()
Check(guardCalls = 0 && events.Length = 2, "screen guard waits for five minutes of idle")
Reset()
gAFKScreenGuard := FakeScreenGuard, idleMs := 301000, guardInterrupts := true
AntiAFKTick()
Check(guardCalls = 1 && events.Length = 0 && !gAFKBusy && releases = 1, "user input during the screen guard cancels the mouse pair")
Reset()
interrupt := true
AntiAFKTick()
Check(events.Length = 1 && !gAFKBusy && releases = 1, "user interrupts mouse return")
Reset()
config["Settings"]["EarnMCTOnly"] := 0
AntiAFKTick()
Check(events.Length = 2 && events[1] = "mouse:2" && events[2] = "mouse:-2" && !gAFKBusy, "mouse pair normal mode")
Reset()
config["Settings"]["EarnMCTOnly"] := 0
interrupt := true
AntiAFKTick()
Check(events.Length = 1 && events[1] = "mouse:2" && !gAFKBusy, "cancel return movement on user input")
Reset()
config["Settings"]["AFKUserIdleSec"] := 0
idleMs := 0
Check(!AFKInputAllowed(), "zero idle setting still guards physical input")
Reset()
focused := false, idleMs := 301000
config["Settings"]["AFKRefocusSettleMs"] := 650
AntiAFKTick()
Check(activations = 1 && waits.Length && waits[1] = 650 && events.Length = 2 && !gAFKBusy && afkNextDue > FakeTick() + 100000 && LogHas("refocus ok idle=301s"), "refocus after long physical idle then settle and input")
Reset()
focused := false, idleMs := 301000, minimized := true
AntiAFKTick()
Check(restored = 1 && activations = 1 && events.Length = 2, "minimized game restored before activation")
Reset()
focused := false, idleMs := 900000
config["Settings"]["AFKRefocusIdleSec"] := 0
AntiAFKTick()
Check(activations = 0 && events.Length = 0 && afkNextDue > FakeTick() && LogHas("전면화 꺼짐"), "zero refocus setting never activates")
Reset()
focused := false, idleMs := 301000, activateWorks := false
AntiAFKTick()
firstGap := afkNextDue - FakeTick()
afkNextDue := 0
AntiAFKTick()
secondGap := afkNextDue - FakeTick()
afkNextDue := 0
AntiAFKTick()
afkNextDue := 0
AntiAFKTick()
fourthGap := afkNextDue - FakeTick()
Check(activations = 3 && events.Length = 0 && logs.Length = 2 && warnings.Length = 1
    && InStr(logs[1], "refocus 실패: 2초 안에") && LogHas("refocus blocked:") && !gAFKBusy
    && firstGap > 25000 && firstGap <= 30000 && secondGap > 55000 && secondGap <= 60000 && fourthGap > 115000 && fourthGap <= 120000,
    "failed refocus backs off then blocks repeated activation and warns")
Reset()
focused := false, idleMs := 400000, activateWorks := false
AntiAFKTick()
afkNextDue := 0
idleMs := 310000   ; 그사이 사람이 만졌다가 다시 비워 유휴 시작 시각이 바뀜
AntiAFKTick()
Check(activations = 2 && logs.Length = 2 && afkRefocusFails = 1 && afkNextDue - FakeTick() <= 30000, "new idle stretch restarts backoff and logging")
Reset()
focused := false, idleMs := 301000, stealBack := true
AntiAFKTick()
Check(activations = 1 && events.Length = 0 && afkRefocusFails = 1 && LogHas("다시 잃음") && afkNextDue - FakeTick() > 25000 && !gAFKBusy, "focus stolen back during settle")
Reset()
focused := false, idleMs := 301000, interrupt := true
AntiAFKTick()
Check(activations = 1 && events.Length = 0 && afkRefocusFails = 0 && afkNextDue - FakeTick() > 25000 && !gAFKBusy, "user returns during settle")
Reset()
focused := false, idleMs := 301000, activateWorks := false
AntiAFKTick()
afkNextDue := 0, activateWorks := true
AntiAFKTick()
Check(events.Length = 2 && afkRefocusFails = 0 && LogHas("앞선 실패 1회 뒤"), "success after failure clears count")
Reset()
focused := false, idleMs := 900000, anyIdleMs := 20000   ; 원격 데스크톱·에이전트가 20초 전에 다른 창에 입력
AntiAFKTick()
Check(activations = 0 && events.Length = 0 && afkNextDue > FakeTick() && LogHas("주입 포함 idle=20s"), "injected input from others blocks refocus")
Reset()
focused := false, idleMs := 301000, activateWorks := false
AntiAFKTick()
ownIgnored := AFKOthersIdleMs() >= 300000   ; 실패한 WinActivate 가 누른 Alt 는 남의 입력이 아니다
afkSelfFrom -= 3000, afkSelfTo -= 3000, anyInjectedAt := FakeTick(), afkNextDue := 0   ; 그 구간이 끝나고 3초 뒤 남이 입력
AntiAFKTick()
Check(ownIgnored && activations = 1 && LogHas("skip: GTA 포커스 없음"), "own Alt ignored, later outside input counted")
Reset()
idleMs := 600000, anyIdleMs := 600000
AFKSelfInput(true), anyInjectedAt := FakeTick(), fakeNow += 1000, AFKSelfInput(false)   ; 수익 작업이 키를 넣고 끝남
fakeNow += 3000, AFKSelfInput(true)                                                    ; 3초 뒤 AFK 가 새 구간을 엶
Check(AFKOthersIdleMs() >= 600000, "previous own interval stays hidden when the next one starts")
AFKSelfInput(false), fakeNow += 3000, anyInjectedAt := FakeTick(), fakeNow += 1000, AFKSelfInput(true)
Check(AFKOthersIdleMs() < 2000, "outside input between own intervals is still counted")
Reset()
focused := false, idleMs := 2000, hookExtraMs := 600000, afkHookTick := FakeTick() - 2000   ; Main 재시작 직후, 그 전 10분 비움
AntiAFKTick()
Check(activations = 1 && events.Length = 2 && LogHas("refocus ok idle=602s"), "fresh hook uses whole-input idle")
Reset()
focused := false, idleMs := 2000, hookExtraMs := 600000, afkHookTick := FakeTick() - 2000, interruptAt := 2
AntiAFKTick()
Check(activations = 1 && events.Length = 1 && !gAFKBusy, "fresh hook still sees user return during input")
Reset()
focused := false, idleMs := 301000, activateWorks := false, altRescue := true, frontExe := "TextInputHost.exe"
AntiAFKTick()
Check(activations = 2 && events.Length = 3 && events[1] = "{Blind}{Alt down}{Alt up}" && LogHas("Alt 보조: TextInputHost.exe"), "input host in front gets one Alt")
Reset()
focused := false, idleMs := 301000, activateWorks := false, altRescue := true, frontExists := false
AntiAFKTick()
Check(activations = 2 && events.Length = 3 && events[1] = "{Blind}{Alt down}{Alt up}" && LogHas("앞 창 없음"), "no foreground window gets one Alt")
Reset()
focused := false, idleMs := 301000, interrupt := true, stealBack := true
AntiAFKTick()
Check(activations = 1 && events.Length = 0 && afkRefocusFails = 0 && !gAFKBusy, "user returns and clicks elsewhere during settle")
Reset()
focused := false, idleMs := 700000, activateWorks := false, frontExe := "ShellExperienceHost.exe", frontTitle := "New notification", toastRescue := true
AntiAFKTick()
Check(notificationCalls = 1 && activations = 2 && events.Length = 2 && LogHas("알림을 알림 센터로 이동")
    && LogHas("mouse pulse") && !gAFKBusy, "exact notification dismisses once then confirms game menu response")
Reset()
focused := false, idleMs := 700000, activateWorks := false, frontExe := "ShellExperienceHost.exe", frontTitle := "Other notification"
AntiAFKTick()
Check(notificationCalls = 0 && activations = 1 && events.Length = 0, "unrecognized shell title does not dismiss")
Reset()
focused := false, idleMs := 700000, activateWorks := false, frontTitle := "New notification"
AntiAFKTick()
Check(notificationCalls = 0 && activations = 1 && events.Length = 0, "notification title in another process is not eligible")
Reset()
focused := false, idleMs := 700000, activateWorks := false, frontExe := "ShellExperienceHost.exe", frontTitle := "New notification", notificationResult := "blocked:ambiguous-button"
AntiAFKTick()
Check(notificationCalls = 1 && activations = 1 && events.Length = 0 && LogHas("blocked:ambiguous-button"), "helper refusal is logged without fallback clicks")
Reset()
focused := false, idleMs := 700000, activateWorks := false, frontExe := "ShellExperienceHost.exe", frontTitle := "New notification"
AntiAFKTick()
Check(notificationCalls = 1 && activations = 2 && events.Length = 0 && afkRefocusFails = 1,
    "successful dismissal is not proof of focus or AFK input")
Reset()
focused := false, idleMs := 700000, activateWorks := false, frontExe := "ShellExperienceHost.exe", frontTitle := "New notification", interruptActivate := true
AntiAFKTick()
Check(notificationCalls = 0 && activations = 1 && events.Length = 0 && afkRefocusFails = 0 && LogHas("refocus 취소"), "user returns during initial activation")
Reset()
focused := false, idleMs := 700000, activateWorks := false, frontExe := "ShellExperienceHost.exe", frontTitle := "New notification", interruptNotification := true
AntiAFKTick()
Check(notificationCalls = 1 && activations = 1 && events.Length = 0 && afkRefocusFails = 0 && LogHas("refocus 취소"), "user returns during notification helper")
Reset()
focused := false, idleMs := 700000, activateWorks := false, frontExe := "ShellExperienceHost.exe", frontTitle := "New notification", externalNotificationInput := true
AntiAFKTick()
Check(notificationCalls = 1 && activations = 1 && events.Length = 0 && afkRefocusFails = 0
    && AFKOthersIdleMs() < 1000 && LogHas("refocus 취소"), "helper-detected external input is not hidden by own activation interval")
Reset()
focused := false, idleMs := 700000, minimized := true, interruptRestore := true
AntiAFKTick()
Check(restored = 1 && activations = 0 && events.Length = 0 && afkRefocusFails = 0, "user returns after window restoration before activation")
Reset()
focused := false, idleMs := 700000, activateWorks := false
Loop 3 {
    afkNextDue := 0
    AntiAFKTick()
}
afkNextDue := 0, frontExe := "ShellExperienceHost.exe", frontTitle := "New notification", toastRescue := true
AntiAFKTick()
Check(activations = 5 && notificationCalls = 1 && events.Length = 2 && afkRefocusFails = 0,
    "a changed foreground window allows a new bounded recovery")
Reset()
lockAvailable := false, focused := false, idleMs := 700000
AntiAFKTick()
Check(activations = 0 && events.Length = 0 && releases = 0 && !gAFKBusy, "GUI or standalone harness lock prevents refocus and game input")
Reset()
lockError := true
AntiAFKTick()
Check(events.Length = 0 && releases = 0 && !gAFKBusy && LogHas("input lock blocked"), "lock creation failure sends no input")
for screen in ["mct_title", "mct_seated", "mct_sit", "phone", "ground", "m_title"] {
    Reset()
    menuState := screen
    AntiAFKTick()
    Check(events.Length = 2 && events[1] = "mouse:2" && events[2] = "mouse:-2" && menuState = screen && releases = 1, "mouse-only pulse preserves " screen)
}
Reset()
heldKey := true
AntiAFKTick()
Check(events.Length = 0 && releases = 1, "held physical key blocks mouse input")
Reset()
stealBack := true
AntiAFKTick()
Check(events.Length = 1 && releases = 1 && !gAFKBusy, "focus loss cancels return movement")
Reset()
focused := false, idleMs := 900000, anyIdleMs := 900000
config["Settings"]["AFKRefocusIdleSec"] := 60
config["Settings"]["AwayMode"] := 1
RegisterMaintenanceTimers()
Check(maintenanceTimers.Has("KeyHookWatchdog") && maintenanceTimers["KeyHookWatchdog"].period = 60000,
    "Main keeps the real sixty-second key-hook watchdog registration")
maintenanceStart := FakeTick()
Loop 49 {
    elapsed := (A_Index - 1) * 5000
    fakeNow := maintenanceStart + elapsed
    idleMs := 900000 + elapsed, anyIdleMs := 900000 + elapsed
    RunMaintenanceTimers()
    ; 실제 장애처럼 정기 probe가 이미 돈 뒤 포커스 복귀를 검사한다.
    if (elapsed >= 65000)
        AntiAFKTick()
}
Check(maintenanceWatchdogs = 4, "watchdog runs on the actual Main schedule without installing real hooks")
Check(activations = 1 && events.Length = 2 && LogHas("refocus ok") && AFKOthersIdleMs() >= 60000,
    "scheduled maintenance must not starve AFK refocus: activations=" activations " probe_sends=" maintenanceProbeSends " other_idle=" AFKOthersIdleMs())
Check(maintenanceProbeSends = 0, "background diagnostics never inject keys into the desktop")
Reset()
focused := false, idleMs := 900000, anyIdleMs := 900000
config["Settings"]["AFKRefocusIdleSec"] := 60
config["Settings"]["AwayMode"] := 1
RegisterMaintenanceTimers()
maintenanceStart := FakeTick()
Loop 49 {
    elapsed := (A_Index - 1) * 5000
    fakeNow := maintenanceStart + elapsed
    idleMs := 900000 + elapsed, anyIdleMs := 900000 + elapsed
    if (Mod(elapsed, 15000) = 0)
        anyInjectedAt := FakeTick() ; 다른 실행기·원격 입력은 계속 보호해야 한다.
    RunMaintenanceTimers()
    AntiAFKTick()
}
Check(activations = 0 && events.Length = 0 && maintenanceProbeSends = 0 && AFKOthersIdleMs() < 60000,
    "away mode and maintenance still defer to recent external injected input")
Reset()
focused := false, idleMs := 0
config["Settings"]["AFKRefocusIdleSec"] := 60
config["Settings"]["AwayMode"] := 1
RegisterMaintenanceTimers()
fakeNow += 60000
RunMaintenanceTimers()
AntiAFKTick()
Check(activations = 0 && events.Length = 0 && maintenanceProbeSends = 0,
    "away mode and maintenance still defer to physical user input")
FileAppend("PASS AntiAFK: " checkCount " cases; no game input`n", "*")
ExitApp(0)
Reset() {
    global
    afkOn := true, afkNextDue := 0, gAFKBusy := false
    afkRefocusFails := 0, afkRefocusStretch := 0, afkRefocusLastErr := "", afkRefocusWindow := "", GTA_WIN := "fake"
    afkHookTick := 0, afkSelfFrom := 0, afkSelfTo := 0, afkSelfBefore := 0
    gAFKScreenGuard := "", guardCalls := 0, guardInterrupts := false
    clawLoopRunning := false, gEarnBusy := false, gMenuBusy := false
    idleMs := 60000, hookExtraMs := 0, anyIdleMs := 1000000000, anyInjectedAt := 0
    focused := true, windowExists := true, frontExists := true, frontExe := "chrome.exe", frontTitle := "about:blank", teleportBusy := false
    interrupt := false, interruptAt := 0, events := [], heldKey := false
    activations := 0, activateWorks := true, altRescue := false, altSent := false, minimized := false, restored := 0, stealBack := false
    notificationCalls := 0, notificationResult := "dismissed", toastRescue := false, notificationDone := false
    interruptNotification := false, interruptActivate := false, interruptRestore := false
    externalNotificationInput := false
    maintenanceTimers := Map(), maintenanceWatchdogs := 0, maintenanceProbeSends := 0
    gProbeSent := 0, gProbeSeen := 0
    lockAvailable := true, lockError := false, releases := 0
    menuState := "mct_title", menuReads := 0, hideBeforeMenuKey := false, menuOpenWorks := true, menuCloseWorks := true, menuChanges := 0, failMenuWaitAt := 0
    seatedTarget := "mct_seated", seatedReturnState := "mct_seated"
    hudVisible := false, hudReads := 0, hideHudAfter := 0, hideHudOnClose := false, hudOriginX := 0, hudOriginY := 0,
        hudWidth := 1920, hudHeight := 1080, hudWindowError := false, visibleOverlay := "", guardAssetMissing := false, menuReturnState := "", gImageRoot := "fake",
        phonePresses := 0, phoneCloseAfter := 2
    logs := [], waits := [], warnings := []
    config := Map("Settings", Map("AFKUserIdleSec",45,"AFKJitterSec",0,"AFKIntervalSec",200,"AFKTapMs",100,"AFKGapMs",100,"EarnMCTOnly",1,
        "AFKRefocusIdleSec",300,"AFKRefocusSettleMs",800))
}
; 전체 입력 유휴(GetLastInputInfo). 물리 입력도 세므로 훅이 본 물리 유휴(+훅 설치 전 유휴)보다 길 수 없고, 주입 입력마다 0 이 된다.
FakeTick() => fakeNow
HarnessSetTimer(callback, period) {
    if (!(callback.Name = "KeyHookWatchdog" || callback.Name = "KeyHookProbe") || period != 60000)
        throw Error("Unexpected maintenance timer registration")
    maintenanceTimers[callback.Name] := {callback:callback,period:period,due:FakeTick()+period}
}
RunMaintenanceTimers() {
    for name, timer in maintenanceTimers {
        if (FakeTick() >= timer.due) {
            timer.due += timer.period
            timer.callback.Call()
        }
    }
}
HarnessHeldKey(vk) => 0
HarnessInstallKeybdHook(install, force) {
    global maintenanceWatchdogs
    if (!install || !force)
        throw Error("Unexpected watchdog hook arguments")
    maintenanceWatchdogs++
}
HarnessSendLevel(level) {
    if (level != 1)
        throw Error("Unexpected probe input level")
}
HarnessSendEvent(value) {
    global maintenanceProbeSends, anyInjectedAt, gProbeSeen
    if (value != "{F24}")
        throw Error("Unexpected diagnostic key")
    maintenanceProbeSends++
    anyInjectedAt := FakeTick() ; GetLastInputInfo가 주입 키마다 초기화되는 효과만 재현한다.
    gProbeSeen := FakeTick()
}
HarnessMacroLog(*) {
}
FakeScreenGuard(idleSec) {
    global guardCalls, idleMs
    guardCalls++
    if (guardInterrupts)
        idleMs := 0
    return "MCT 화면 정리 완료 idle=" idleSec "s"
}
AnyIdle() {
    global
    v := Min(idleMs + hookExtraMs, anyIdleMs)
    return anyInjectedAt ? Min(v, FakeTick() - anyInjectedAt) : v
}
LogHas(text) {
    for line in logs
        if InStr(line, text)
            return true
    return false
}
Check(ok, label) {
    global checkCount
    if (!ok) {
        FileAppend("FAIL " label "`n", "*")
        ExitApp(1)
    }
    checkCount++
}
WinExist(title := "") => title = "A" ? frontExists : windowExists
IsGTAActive() => focused
IsTeleportRunning() => teleportBusy
AnyInputToggleOn() => false
GetKeyState(*) => heldKey
Send(value) {
    global events, anyInjectedAt, altSent, menuState, menuChanges, menuReturnState, seatedTarget, seatedReturnState, hudVisible, visibleOverlay, phonePresses, phoneCloseAfter
    if (!gAFKBusy)
        throw Error("input without ownership")
    events.Push(value)
    anyInjectedAt := FakeTick()
    if InStr(value, "Alt")
        altSent := true
    ; 남은 전화·앱은 Backspace 로 한 단계씩 닫힌다.
    if (value = "{Backspace down}" && visibleOverlay != ""
        && InStr(" afk_phone_frame afk_vinewood_title ph_joblist_sel ph_vinewood_sel ", " " visibleOverlay " ")) {
        phonePresses++
        if (phonePresses >= phoneCloseAfter)
            visibleOverlay := ""
        return
    }
    if (value = "{Backspace down}" || value = "{Enter down}" || value = "{m down}" || value = "{e down}") {
        menuChanges++
        if ((menuChanges = 1 && !menuOpenWorks) || (menuChanges > 1 && !menuCloseWorks))
            return
        if (value = "{Backspace down}" && menuState = "mct_title")
            menuState := seatedReturnState
        else if (value = "{Enter down}" && (menuState = "mct_seated" || menuState = "mct_seated_mansion"))
            seatedReturnState := menuState, menuState := "mct_title"
        else if (value = "{e down}" && menuState = "mct_sit")
            menuState := seatedTarget
        else if (value = "{m down}" && (menuState = "mct_sit" || menuState = "ground"))
            menuReturnState := menuState, menuState := "m_title"
        else if (value = "{m down}" && menuState = "m_title") {
            menuState := menuReturnState
            if (hideHudOnClose)
                hudVisible := false
        }
        else
            throw Error("Unknown game state received menu input")
    }
}
DllCall(name, args*) {
    if (name = "mouse_event") {
        if (!gAFKBusy || args[2] != 1 || args[6] != 0)
            throw Error("unexpected mouse flags or ownership")
        events.Push("mouse:" args[4])
        return 1
    }
    if (name = "SetThreadDpiAwarenessContext")
        return 1
    throw Error("No mouse movement/native input should be needed: " name)
}
WinGetClientPos(&x, &y, &w, &h, *) {
    if (hudWindowError)
        throw Error("test window disappeared")
    x := hudOriginX, y := hudOriginY, w := hudWidth, h := hudHeight
}
CoordMode(kind, mode) {
    if (kind != "Pixel" || mode != "Screen")
        throw Error("Unexpected coordinate-mode mutation")
}
PixelGetColor(x, y) {
    global hudReads
    if (x < hudOriginX+40 || x > hudOriginX+85 || Mod(x-hudOriginX-40,3) || y != hudOriginY+1053)
        throw Error("HUD samples leave the physical health-bar line")
    if (x = hudOriginX+40)
        hudReads++
    return hudVisible && (!hideHudAfter || hudReads <= hideHudAfter) ? 0xA5FFAC : 0
}
FileExist(path) => guardAssetMissing ? "" : "A"
AFKWait(ms) {
    global idleMs, hookExtraMs, focused, fakeNow
    waits.Push(ms)
    fakeNow += ms
    if (interrupt || (interruptAt && waits.Length >= interruptAt))
        idleMs := 0, hookExtraMs := 0
    if (stealBack)
        focused := false
    if (failMenuWaitAt && waits.Length >= failMenuWaitAt)
        return false
    return AFKInputAllowed()
}
AFKLog(msg) {
    logs.Push(msg)
}
WinGetMinMax(*) => minimized ? -1 : 0
WinRestore(*) {
    global restored, minimized, idleMs
    restored += 1
    minimized := false
    if (interruptRestore)
        idleMs := 0
}
WinActivate(*) {
    global activations, focused, anyInjectedAt, idleMs
    if (!gAFKBusy)
        throw Error("activation without ownership")
    activations += 1
    if (interruptActivate)
        idleMs := 0
    if (activateWorks || (altRescue && altSent) || (toastRescue && notificationDone))
        focused := true
    else
        anyInjectedAt := FakeTick()   ; AHK 의 WinActivate 는 실패하면 Alt 를 두 번 누른다
}
WinWaitActive(*) => focused
WinGetProcessName(*) => frontExe
WinGetTitleSafe(*) => frontTitle
AFKDismissNotification(*) {
    global notificationCalls, notificationDone, idleMs, afkSelfBefore
    if (!AFKRefocusAllowed() || frontExe != "ShellExperienceHost.exe" || frontTitle !== "New notification")
        throw Error("Notification helper called without exact identity and idle guards")
    notificationCalls++
    notificationDone := notificationResult = "dismissed"
    if (interruptNotification)
        idleMs := 0
    if (externalNotificationInput) {
        afkSelfBefore := FakeTick()
        return "blocked:input-changed"
    }
    return notificationResult
}
ShowTooltip(message,*) => warnings.Push(message)
; 글자 템플릿이 맞으면 안내 상자 바탕 확인도 통과한 것으로 본다.
TemplateAt(*) => true
TemplateSeen(folder,name,*) {
    global menuReads
    if (folder != "Earn" && folder != "JobWarp")
        throw Error("Unexpected template namespace")
    menuReads++
    return (name = menuState || name = visibleOverlay) && !(hideBeforeMenuKey && menuReads >= 2)
}
AFKInputLockAcquire(*) {
    if (lockError)
        throw Error("lock unavailable")
    return lockAvailable ? {macro:1,gui:2} : 0
}
AFKInputLockRelease(inputLock) {
    global releases
    if (gAFKBusy || inputLock.macro != 1 || inputLock.gui != 2)
        throw Error("Lock released before state cleanup or invalid handle")
    releases++
}
'@
$previous = [Console]::InputEncoding
[Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
try {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $AhkPath
    $info.Arguments = '/ErrorStdOut /CP65001 *'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($info)
    try {
        $stdoutTask = $p.StandardOutput.ReadToEndAsync()
        $stderrTask = $p.StandardError.ReadToEndAsync()
        $p.StandardInput.WriteLine($driver + "`n" + $production)
        $p.StandardInput.Close()
        if (-not $p.WaitForExit(10000)) {
            $p.Kill()
            $p.WaitForExit()
            $timeoutOut = $stdoutTask.GetAwaiter().GetResult().Trim()
            $timeoutErr = $stderrTask.GetAwaiter().GetResult().Trim()
            throw "AFK test timed out. stdout=$timeoutOut stderr=$timeoutErr"
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
        $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
        if ($p.ExitCode -ne 0 -or $stderr -or $stdout -notmatch '^PASS AntiAFK: [0-9]+ cases; no game input$') {
            throw "exit=$($p.ExitCode) stdout=$stdout stderr=$stderr"
        }
        $stdout
    } finally { $p.Dispose() }
} finally { [Console]::InputEncoding = $previous }
