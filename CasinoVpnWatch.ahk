#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon
; GTA 가 켜질 때마다 카지노용 VPN 을 잠깐 켰다 끈다 (Features\CasinoVpn.ahk). 시작 프로그램 바로가기로 로그온 때 뜬다.
; 유지 시간은 Config.ini [Settings] CasinoVpnHoldSec 로 바꾼다.
#Include Features\CasinoVpn.ahk

ini := A_ScriptDir "\Config.ini"
hold := IniRead(ini, "Settings", "CasinoVpnHoldSec", 5)
StartCasinoVpnWatch(IsNumber(hold) ? hold + 0 : 5)
Persistent()
