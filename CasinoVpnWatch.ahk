#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon
; GTA 가 켜질 때마다 카지노용 VPN 을 잠깐 켰다 끄고(Features\CasinoVpn.ahk), 매크로(Main.ahk)가 안 떠 있으면 띄운다(Features\MacroAutoStart.ahk).
; 시작 프로그램 바로가기(GTA Casino VPN.lnk)로 로그온 때 뜬다.
; VPN 유지 시간은 Config.ini [Settings] CasinoVpnHoldSec, 매크로 자동 실행은 [Settings] MacroAutoStart(기본 1)로 바꾼다.
#Include Features\CasinoVpn.ahk
#Include Features\MacroAutoStart.ahk

ini := A_ScriptDir "\Config.ini"
hold := IniRead(ini, "Settings", "CasinoVpnHoldSec", 5)
StartCasinoVpnWatch(IsNumber(hold) ? hold + 0 : 5)
if (IniRead(ini, "Settings", "MacroAutoStart", 1) + 0)
    StartMacroAutoStartWatch()
Persistent()
