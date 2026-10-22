#Requires AutoHotkey v2.0
#NoTrayIcon
; GTA 바로가기(바탕화면·시작 메뉴)가 부르는 창 없는 실행기. 일은 launch-gta.ps1 이 한다(PowerShell 콘솔 창이 깜빡이지 않게 숨겨서 부른다).
Run('powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' A_ScriptDir '\launch-gta.ps1"', A_ScriptDir, "Hide")
