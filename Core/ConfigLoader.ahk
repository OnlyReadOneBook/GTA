; === 설정 로드 모듈 ===
; [Features]·[Settings] 는 기본값 표의 키를 읽고, [Hotkeys] 는 섹션 전체를 읽어 Map 에 넣는다.
; 새 기능은 Config.ini [Hotkeys] 한 줄 + HotkeyManager 액션 표 한 줄로 붙는다.
global config := Map()
config["Features"] := Map()
config["Hotkeys"] := Map()
config["Settings"] := Map()

; 값이 없거나 숫자가 아닐 때 쓰는 기본값. 값 줄 끝에 ; 주석을 붙이면 IniRead 가 주석까지 값으로 읽으므로 주석은 줄을 따로 쓴다.
global CONFIG_DEFAULTS := Map()
CONFIG_DEFAULTS["Features"] := Map(
    "Teleport", 1, "AltF4Teleport", 1, "Movement", 1, "AutoClick", 1, "Timer", 1,
    "CasinoFingerprint", 0, "ClawMachine", 1, "AntiAFK", 1, "SessionSwitch", 1, "MenuMacros", 1, "Earner", 1)
CONFIG_DEFAULTS["Settings"] := Map(
    "ClickInterval", 1, "ClickHoldTime", 50, "KeyHoldTime", 100,
    "ConfirmWindowMs", 2000, "HelpShowMs", 8000,
    "MenuOpenDelay", 50, "MenuControlDelay", 50,
    "PhoneOpenDelay", 1000, "PhoneControlDelay", 150, "MCDisbandDelay", 1000, "PhoneCloseDelay", 1000,
    "TeleportWaitTime", 38000, "TeleportTimerInterval", 100,
    "TeleportEnterDuration", 100000, "TeleportEnterInterval", 50, "TeleportClickToEnterDelay", 4000,
    "JobWarpStartToConfirmMs", 1200, "JobWarpConfirmToAltF4Ms", 900, "JobWarpQuitWaitMs", 90000, "JobWarpMinWaitMs", 60000, "JobWarpAfterPromptMs", 1500,
    "CayoCooldownMinutes", 48, "VellumDrivingCtrlInterval", 3000,
    "ClawForwardMs", 5000, "ClawRightMs", 5000, "ClawEnterTimeout", 15000, "ClawResultTimeout", 30000,
    "SessionMenuDelay", 600,
    "AFKUserIdleSec", 120, "CpuBoostIdleSec", 300, "IdleFpsLimit", 30, "AwayMode", 0, "AutoAwayIdleSec", 0, "AFKIntervalSec", 200, "AFKJitterSec", 20, "AFKTapMs", 150, "AFKGapMs", 250, "AFKOnStart", 1,
    "AFKRefocusIdleSec", 300, "AFKRefocusSettleMs", 800, "AFKMCTCloseIdleSec", 300, "MemWarnPct", 80, "MemClosePct", 92, "MemCloseMinGB", 25,
    "OverlayEnabled", 1, "OverlayXPct", 98, "OverlayYPct", 18,
    "DiscordHUDAppID", "",
    "DiscordHUDPath", "", "SaleAlertName", "", "SaleAlertIntervalSec", 10, "LagSwitchMode", "suspend", "LagSwitchMaxMs", 6000, "LagSwitchAdapter", "",
    "MenuTopOffset", 0, "SnackMenuSteps", 4, "SnackSubSteps", 2, "SnackItemSteps", 0, "SnackCount", 1, "SnackCloseMenu", 1,
    "EarnKeyDelay", 350, "EarnTurnUnitsPerDeg", 29, "EarnRerollMax", 12, "EarnReachPx", 14, "EarnWalkRetry", 3, "EarnUserIdleSec", 45, "EarnMCTBatchAheadSec", 120, "EarnLoadMinSec", 8, "EarnLoadTimeoutSec", 240,
    "EarnMCTOnly", 1, "EarnBunker", 0, "EarnBunkerIntervalSec", 6720, "EarnDJ", 0, "EarnDJIntervalMin", 5, "EarnDJPopularityPct", 95,
    "EarnSafe", 1, "EarnSafeIntervalMin", 5, "EarnSafeFirstMin", 0, "EarnSafeRetryMin", 15, "EarnSoftFailMax", 12, "EarnGlitchRejoinFails", 3,
    "EarnWarehouse", 1, "EarnWarehouseIntervalMin", 10,
    "EarnBailAgents", 1, "EarnCargoStaff", 1, "EarnHangarStaff", 1, "EarnStaffIntervalMin", 5,
    "EarnDispatch", 0, "EarnDispatchIntervalMin", 48, "EarnDispatchFirstMin", 0)

LoadConfig() {
    global config, CONFIG_DEFAULTS
    file := A_ScriptDir "\Config.ini"

    ; Config.ini 파일 존재 확인
    if (!FileExist(file)) {
        MsgBox("Config.ini 파일을 찾을 수 없습니다!")
        ExitApp()
    }
    StripConfigBom(file)

    ; Features / Settings: 기본값 표의 키만 읽는다. 숫자가 아니면 기본값을 쓰고 로그를 남긴다 (Integer() 예외로 시작이 막히지 않게).
    for section in ["Features", "Settings"] {
        for key, dflt in CONFIG_DEFAULTS[section] {
            value := IniRead(file, section, key, dflt)
            if (IsNumber(value)) {
                config[section][key] := Number(value)
            } else if (!IsNumber(dflt)) {
                config[section][key] := Trim(value)   ; 기본값이 글자인 키(걷기 경로 등)는 글자 그대로
            } else {
                config[section][key] := dflt
                MacroLog("config", section "." key "=" value " 는 숫자가 아니라 기본값 " dflt " 사용")
            }
        }
    }

    ; 사용자 유휴 기준은 AFK 와 수익이 하나를 쓴다(1019 사용자 지시). EarnUserIdleSec 줄은 읽지 않고 AFKUserIdleSec 으로 덮는다.
    config["Settings"]["EarnUserIdleSec"] := config["Settings"]["AFKUserIdleSec"]
    ; 자동 외출(모드 2) 전환도 같은 유휴 기준을 쓴다(1019 사용자 지시). 0 이면 꺼진 그대로 둔다.
    if (config["Settings"]["AutoAwayIdleSec"] > 0)
        config["Settings"]["AutoAwayIdleSec"] := config["Settings"]["AFKUserIdleSec"]

    ; Hotkeys: 있는 줄을 전부 읽는다. 액션 표에 없는 이름은 등록 때 무시된다.
    for line in StrSplit(IniRead(file, "Hotkeys", , ""), "`n", "`r") {
        pos := InStr(line, "=")
        if (!pos)
            continue
        name := Trim(SubStr(line, 1, pos - 1))
        if (name = "" || SubStr(name, 1, 1) = ";")
            continue
        config["Hotkeys"][name] := Trim(SubStr(line, pos + 1))
    }
}

; Config.ini 의 [section] 안 key= 줄 하나만 바꾸고(없으면 섹션 끝에 추가) config Map 도 바로 고친다. 재시작 없이 반영된다.
; IniWrite 는 쓰지 않는다: BOM 없는 파일을 ANSI 로 다뤄 한국어 주석을 깨뜨릴 수 있다. 파일은 BOM 없는 UTF-8 + CRLF 그대로 둔다.
; 임시 파일에 다 쓴 뒤 바꿔 끼워서, 쓰다가 끊겨도 Config.ini 가 반쯤 잘린 채 남지 않게 한다.
SetConfigValue(section, key, value) {
    global config
    file := A_ScriptDir "\Config.ini"
    lines := StrSplit(FileRead(file, "UTF-8"), "`n", "`r")
    current := ""
    sectionAt := 0     ; 섹션 안 마지막 내용 줄 다음 자리 (없는 키를 넣을 곳)
    done := false
    for i, line in lines {
        if (RegExMatch(line, "^\s*\[\s*(.+?)\s*\]\s*$", &m)) {
            current := m[1]
            if (current = section)
                sectionAt := i + 1
            continue
        }
        if (current != section)
            continue
        if (RegExMatch(line, "i)^\s*\Q" key "\E\s*=")) {
            lines[i] := key "=" value
            done := true
            break
        }
        if (Trim(line) != "")
            sectionAt := i + 1
    }
    if (!done) {
        if (sectionAt)
            lines.InsertAt(sectionAt, key "=" value)
        else if (lines.Length && lines[lines.Length] = "")
            lines.InsertAt(lines.Length, "[" section "]", key "=" value)
        else
            lines.Push("[" section "]", key "=" value)
    }
    text := ""
    for i, line in lines
        text .= (i = 1 ? "" : "`r`n") line
    tmp := file ".tmp"
    f := FileOpen(tmp, "w", "UTF-8-RAW")
    f.Write(text)
    f.Close()
    FileMove(tmp, file, 1)
    config[section][key] := IsNumber(value) ? Number(value) : value
    MacroLog("config", section "." key "=" value " 저장")
}

; UTF-8 BOM 이 있으면 IniRead 가 첫 섹션 이름을 못 읽는다(85009a1 실측). 발견하면 BOM 만 떼고 다시 저장한다.
StripConfigBom(file) {
    try {
        raw := FileRead(file, "RAW")
        if (raw.Size < 3 || NumGet(raw, 0, "UChar") != 0xEF || NumGet(raw, 1, "UChar") != 0xBB || NumGet(raw, 2, "UChar") != 0xBF)
            return
        text := FileRead(file, "UTF-8")
        f := FileOpen(file, "w", "UTF-8-RAW")
        f.Write(text)
        f.Close()
        MacroLog("config", "Config.ini 의 UTF-8 BOM 을 제거함")
    }
}
