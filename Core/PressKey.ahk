#Requires AutoHotkey v2.0

; 키 누르기 함수
PressKey(key, count := 1, betweenDelay := 0) {
    global config
    
    keyHoldTime := config["Settings"]["KeyHoldTime"]
    
    Loop count {
        if (MacroKeyPhysicallyHeld(key))
            return
        Send("{Blind}{" key " down}")
        try Sleep(keyHoldTime)
        finally ReleaseMacroKey(key)
        
        ; 마지막이 아니고 betweenDelay가 설정되었으면 적용
        if (A_Index < count && betweenDelay > 0) {
            Sleep(betweenDelay)
        }
    }
}

MacroKeyPhysicallyHeld(key) {
    if (key = "Shift")
        return GetKeyState("LShift", "P") || GetKeyState("RShift", "P")
    return GetKeyState(key, "P")
}

ReleaseMacroKey(key) {
    ; A physical press during the macro's wait transfers the hold to the user.
    if (MacroKeyPhysicallyHeld(key))
        return false
    Send("{Blind}{" key " up}")
    return true
}
