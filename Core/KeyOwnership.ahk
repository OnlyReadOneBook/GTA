#Requires AutoHotkey v2.0

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
