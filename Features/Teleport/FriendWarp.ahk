; Rockstar Home 화면의 -Atra_Mora- 카드. 템플릿은 2026-10-20 사용자가 제공한 1920x1080 화면에서 추출했다.
; 이름과 버튼의 절대 위치는 저장하지 않는다. 버튼 검색은 찾은 이름과 같은 카드 안으로 제한한다.
FriendWarpAddDefaults()
global gFriendWarpQuietSince := 0
FriendWarpAddDefaults() {
    global CONFIG_DEFAULTS
    CONFIG_DEFAULTS["Features"]["FriendWarp"] := 1
}

ExecuteFriendWarp() {
    ExecuteBotWarp("friend")
}

FriendWarpWaitTrigger(hotkey) {
    trigger := RegExReplace(hotkey, "^[~*$<>!^+#]+")
    if (trigger = "")
        return true
    ; 실행키의 key-up도 물리 이벤트다. 그 이벤트 뒤에 유휴 기준을 잡는다.
    try return KeyWait(trigger, "T1")
    catch
        return false
}

FriendWarpReady(&why) {
    global gImageRoot, gFriendWarpQuietSince
    why := ""
    if (!IsGTAActive()) {
        why := "GTA가 앞에 없음"
        return false
    }
    previous := BotWarpDpiPhys()
    try WinGetClientPos(, , &cw, &ch, "ahk_id " IsGTAActive())
    finally BotWarpDpiRestore(previous)
    if (cw != 1920 || ch != 1080) {
        why := "친구 텔은 1920x1080 템플릿이 필요함"
        return false
    }
    for name in ["friend_name", "join_game", "home_tab"] {
        if (!FileExist(gImageRoot "\FriendWarp\1920x1080\" name ".png")) {
            why := "친구 텔 템플릿 없음: " name
            return false
        }
    }
    InstallMouseHook()
    if (!FriendWarpWaitTrigger(A_ThisHotkey) || BotWarpStopPressed() || !IsGTAActive()) {
        why := "실행키 해제 대기 중 중단"
        return false
    }
    gFriendWarpQuietSince := A_TickCount
    return true
}

FriendWarpGuard() {
    global gAbort, gFriendWarpQuietSince
    return !gAbort && IsGTAActive() && !BotWarpStopPressed()
        && A_TimeIdlePhysical >= A_TickCount - gFriendWarpQuietSince
}

FriendWarpWait(ms) {
    deadline := A_TickCount + ms
    Loop {
        if (!FriendWarpGuard())
            return false
        if (A_TickCount >= deadline)
            return true
        Sleep(Min(25, deadline - A_TickCount))
    }
}

FriendWarpOpen(&why) {
    why := ""
    if (!FriendWarpGuard()) {
        why := "사용자 입력·중단 또는 포커스 이탈"
        return false
    }
    if (FriendWarpAnchor(&x, &y))
        return true
    PressKey("Home")
    Loop 30 {
        if (!FriendWarpWait(100))
            break
        if (FriendWarpAnchor(&x, &y))
            return true
    }
    why := "Home 친구 목록을 확인하지 못함"
    return false
}

FriendWarpLocate(&target, &why) {
    if (!FriendWarpOpen(&why))
        return false
    ; 현재 페이지를 먼저 보고, 없으면 목록 맨 위로 이동한 뒤 제한된 횟수만 스크롤한다.
    Loop 14 {
        if (!FriendWarpGuard()) {
            why := "사용자 입력·중단 또는 포커스 이탈"
            return false
        }
        if (FriendWarpFindTarget(&target, &why))
            return true
        if (why != "-Atra_Mora-가 현재 보이는 목록에 없음")
            return false
        if (A_Index = 14)
            break
        if (!FriendWarpAnchor(&hx, &hy))
            break
        if (!FriendWarpCursorTo(hx + 160, hy + 170) || !FriendWarpWait(80))
            break
        if (!FriendWarpAnchor(&newX, &newY) || hx != newX || hy != newY)
            break
        if (!FriendWarpGuard())
            break
        Click(A_Index = 1 ? "WheelUp 30" : "WheelDown 3")
        if (!FriendWarpWait(250))
            break
    }
    why := "친구 목록 탐색 중단 또는 -Atra_Mora-를 찾지 못함"
    return false
}

FriendWarpClose() {
    if (!FriendWarpGuard())
        return false
    if (!FriendWarpAnchor(&x, &y))
        return true
    PressKey("Home")
    Loop 20 {
        if (!FriendWarpWait(100))
            return false
        if (!FriendWarpAnchor(&x, &y))
            return true
    }
    return false
}

FriendWarpPrepare(&why) {
    if (!FriendWarpReady(&why) || !FriendWarpLocate(&target, &why))
        return false
    if (!FriendWarpClose()) {
        why := "친구 목록을 닫지 못함"
        return false
    }
    return true
}

FriendWarpJoin(&why) {
    if (!FriendWarpLocate(&target, &why))
        return false
    if (!FriendWarpCursorTo(target.x, target.y) || !FriendWarpWait(80)) {
        why := "클릭 전 입력 중단"
        return false
    }
    ; 온라인 상태 변화로 목록 순서가 바뀌면 이전 좌표를 누르지 않는다.
    if (!FriendWarpFindTarget(&current, &why) || !FriendWarpSameTarget(target, current)) {
        why := "클릭 직전 친구 카드가 바뀜"
        return false
    }
    if (!FriendWarpGuard()) {
        why := "클릭 직전 사용자 입력·중단 또는 포커스 이탈"
        return false
    }
    Click("Left")
    MacroLog("friendwarp", "-Atra_Mora- JOIN GAME 클릭 " target.x "," target.y)
    if (!FriendWarpWait(500) || !FriendWarpClose()) {
        why := "참가 후 입력 중단 또는 오버레이 닫기 실패"
        return false
    }
    return true
}

FriendWarpCursorTo(x, y) {
    if (!FriendWarpGuard())
        return false
    previous := BotWarpDpiPhys()
    try {
        CoordMode("Mouse", "Screen")
        ; AHK가 주입한 이동으로 표시해 물리 입력 중단 감지와 구분한다.
        MouseMove(x, y, 0)
        pt := Buffer(8, 0)
        DllCall("GetCursorPos", "ptr", pt)
        return Abs(NumGet(pt, 0, "int") - x) <= 2 && Abs(NumGet(pt, 4, "int") - y) <= 2
    } finally {
        BotWarpDpiRestore(previous)
    }
}

FriendWarpFindTarget(&target, &why) {
    target := "", why := ""
    if (!FriendWarpAnchor(&hx, &hy)) {
        why := "Rockstar Home 친구 목록이 보이지 않음"
        return false
    }
    ; 이름 전체가 보이는 카드만 검색한다. 카드 아래쪽이 잘리면 JOIN GAME은 선택하지 않는다.
    list := [hx, hy + 25, hx + 299, hy + 388]
    if (!FriendWarpFind("friend_name", list, &nx, &ny)) {
        why := "-Atra_Mora-가 현재 보이는 목록에 없음"
        return false
    }
    nameBelow := [list[1], ny + 16, list[3], list[4]]
    if (FriendWarpFind("friend_name", nameBelow, &otherX, &otherY)) {
        why := "친구 이름이 여러 곳에서 감지됨"
        return false
    }
    buttonArea := [nx - 2, ny + 25, Min(nx + 210, list[3]), Min(ny + 58, list[4])]
    if (!FriendWarpFind("join_game", buttonArea, &jx, &jy)) {
        why := "-Atra_Mora- 카드에 JOIN GAME이 보이지 않음"
        return false
    }
    target := {nameX: nx, nameY: ny, x: jx + 27, y: jy + 8}
    return true
}

FriendWarpAnchor(&x, &y) {
    if (!FriendWarpFind("home_tab", "", &tx, &ty))
        return false
    ; 친구 목록 본문을 스크롤해도 상단 HOME 탭은 고정되어 있다.
    x := tx + 387, y := ty + 72
    return true
}

FriendWarpFind(name, area, &x, &y) {
    global gImageRoot
    x := 0, y := 0
    hwnd := IsGTAActive()
    if (!hwnd)
        return false
    previous := BotWarpDpiPhys()
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        if (cw != 1920 || ch != 1080)
            return false
        path := gImageRoot "\FriendWarp\1920x1080\" name ".png"
        if (!FileExist(path))
            return false
        bounds := IsObject(area) ? area : [cx, cy, cx + cw - 1, cy + ch - 1]
        left := Max(cx, bounds[1]), top := Max(cy, bounds[2])
        right := Min(cx + cw - 1, bounds[3]), bottom := Min(cy + ch - 1, bounds[4])
        if (left >= right || top >= bottom)
            return false
        CoordMode("Pixel", "Screen")
        return ImageSearch(&x, &y, left, top, right, bottom, "*25 " path)
    } catch {
        return false
    } finally {
        BotWarpDpiRestore(previous)
    }
}

FriendWarpSameTarget(first, second) {
    return first.nameX = second.nameX && first.nameY = second.nameY
        && first.x = second.x && first.y = second.y
}
