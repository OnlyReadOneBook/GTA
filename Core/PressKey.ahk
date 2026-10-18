#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\KeyOwnership.ahk

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
