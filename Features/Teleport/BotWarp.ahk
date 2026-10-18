; === 스팀 봇 작텔 (BotWarp) ===
; 2026-09-26 실측(게임에서 세 번 성공): 작업을 시작해 로딩이 도는 동안 공개 스팀 봇에게 Join Game 을 걸면
;   "Failed to join session due to incompatible assets" 로 참가가 실패하고, GTA Online 으로 돌아오면서 방금 시작한 작업의 출발점 프리모드에 떨어진다.
;   Alt+F4 작텔(TeleportAltF4)과 같은 곳으로 가지만 게임 종료 확인창을 쓰지 않고 60초 대기도 없다.
;
; 쓰는 법: 일시정지 지도(P → MAP)에서 가고 싶은 작업 블립을 골라 화면 아래에 "Start Job (Space)" 가 보이는 상태에서
;          이 단축키(기본 F10)를 두 번 누른다. 도착지는 사용자가 고른 작업의 출발점이다(매크로가 정하지 않는다).
;          지도에 작업 블립이 없으면(세션을 옮긴 직후 한동안) P → ONLINE → Jobs → Play Job 에서 작업을 골라
;          CONFIRM "Are you sure you want to start this Job?" 창이 뜬 상태에서 눌러도 된다(Space 없이 그 Enter 부터 한다).
; 준비: 스팀 그룹 채팅 "CCYXJ差传" 창을 열어 둔다. 창은 GTA 가 없는 모니터(노트북 화면, 배율 175%) 오른쪽 위에 매번 같은 자리·크기로 옮겨 놓고 좌표로 누른다.
;       Images\BotWarp\steam\join_game.png 가 있어야 시작한다(아래 "스팀 참조 이미지"). 게임 화면은 16:9 여야 한다.
; 순서: [스팀 창 자리 맞추기] → Space → CONFIRM "Are you sure you want to start this Job?" 에 Enter (작업 로딩 시작)
;       → 스팀 채팅 창을 앞으로 → 멤버 필터 "CCYXJ" → 봇 줄 우클릭 → Join Game
;       → GTA 를 앞으로 → ALERT "join a different GTA Online session?" Enter
;       → [조준 모드가 봇과 다르면 ALERT "different targeting mode" Enter] → ALERT "incompatible assets" Enter(Continue)
;       → 약 20초 뒤 작업 출발점 도착(왼쪽 아래 체력 막대가 보이면 끝).
; 안전: Esc 는 어디에도 보내지 않는다(Rockstar 런처 종료창).
;       Enter 는 위 순서의 알림이라고 화면으로 판정한 것에만 보낸다. 키를 보내기 직전마다 알림이 떠 있는지와 종류를 새로 본다.
;       quit 로고(게임 종료·세션 나가기·스토리 모드 확인창)가 보이면 어느 단계든 아무 키도 보내지 않고 멈춘다.
;       순서에 없는 알림이면 Enter 하지 않고 멈춘다. Space 직후에 뜬 알림이 작업 확인창이 아닐 때만 Backspace(취소·No)로 닫는다.
;       Join Game 뒤에 키보드를 누르면 사용자가 넘겨받은 것으로 보고 키를 더 보내지 않는다(F5 세션 이동이나 직접 연 확인창과 섞이지 않게).
;       End(전체 멈춤)는 GTA 가 앞이면 단축키로, 스팀 단계에서는 키가 눌렸는지를 직접 본다.
; 실패: 워프로 도착한 세션에서 다시 Start Job 을 누르면 ALERT "Currently unavailable." (Cancel 뿐) 이 뜬다.
;       그 알림이면 Backspace 로 닫은 뒤, 초대 전용 세션(F5 두 번)으로 옮기라고 알리고 멈춘다.
;
; 알림 판정(참조 이미지 없이): 알림 화면은 검은 바탕 가운데 노란 로고와 그 아래 흰 구분선 두 줄, 그 사이 흰 문장이다.
;   로고는 글자 수가 달라 폭이 다르고(quit < alert < confirm), 구분선은 문장 길이에 맞춰 늘어나 문장마다 폭이 다르다.
;   그래서 로고 폭으로 머리글을, 구분선 폭으로 문장을 가른다. 값(아래 BOTWARP_LOGO_KINDS·BOTWARP_ALERT_LINES)은
;   0926 게임 캡처(1920x1080 을 768·960 폭으로 줄인 것 60여 장과 원본 3장)에서 잰 클라이언트 폭 대비 비율이다.
;   16:9 에서 잰 비율이라 게임 화면이 16:9 가 아니면 시작하지 않는다. 로그에 알림마다 두 폭을 남기니 어긋나면 표를 고친다.
; 참조 이미지(선택, 폭 판정보다 먼저 본다): 흰 글자·노란 로고만 남기고 나머지를 0xFF00FF 로 칠한 PNG.
;     Images\BotWarp\<가로>x<세로>\ (GTA 클라이언트 크기, 예: 1920x1080)
;       logo_quit.png        "quit" 로고. 보이면 어느 단계든 키를 보내지 않고 멈춘다
;       txt_start_job.png / txt_unavailable.png / txt_join_session.png / txt_targeting.png / txt_incompatible.png  각 알림의 문장
;       hint_start_job.png   지도 오른쪽 아래 "Start Job" 안내. 있으면 이것이 안 보일 때 시작하지 않는다
; 스팀 참조 이미지(노트북 화면 175% 에서 뜬 스팀 화면 조각, 물리 픽셀 그대로). Images\BotWarp\steam\
;       join_game.png        봇 우클릭 메뉴의 "Join Game" 글자 칸. 필수: 이것을 찾은 자리를 누르고, 안 보이면 누르지 않는다
;                            (메뉴 항목은 봇 상태에 따라 달라져서 좌표로 누르면 다른 항목을 누를 수 있다).
;                            만드는 법: 채팅 창이 매크로 자리에 있을 때 봇 줄을 우클릭해 메뉴를 띄우고, 마우스를 그대로 둔 채
;                            노트북 화면을 물리 해상도로 캡처해 "Join Game" 글자와 둘레 몇 픽셀(대략 220x45)을 잘라 저장한다.
;                            0926 에 잰 자리: 봇 줄 (-200,394) 을 우클릭하면 Join Game 은 (-446,840). 그 둘레 ±300 에서 찾는다
;       bot1.png / bot2.png  멤버 목록의 봇 이름 "差传CCYXJ01" / "差传CCYXJ03" (게임 중일 때의 초록 글자). BotWarpBotRow 번호의 것을 찾아 우클릭한다.
;                            필터 결과에 이름에 CCYXJ 가 든 일반 회원이 끼면 줄 순서가 바뀌어서 줄 자리로 누르지 않는다. 파일이 없을 때만 줄 자리로 누른다
;       open_in_steam.png    초대 페이지의 "Open in Steam" 버튼 (0926 18:09: 메인 창 -2560,0 에서 창 왼쪽 위로부터 약 850,475)
;       join_group_chat.png  "Invite" 창(주 모니터 가운데, 540x260)의 파란 버튼. 이미 가입한 계정이라 글자는 "Go to Group Chat" (창 왼쪽 위에서 216,180)
;                            두 장이 다 있을 때만 채팅 창이 없으면 초대 링크로 연다. 없으면 채팅 창을 열어 두라고 알리고 멈춘다
;       참조 이미지 다섯 장(0926 18:11)은 모두 노트북 화면 175% 에서 물리 픽셀 그대로 잘랐다
; 로그: %TEMP%\gta-macro.log 의 [botwarp] 줄. 알림마다 종류와 로고 폭·구분선 폭(%)을 남긴다.

; 설정 기본값. ConfigLoader 의 기본값 표 대신 여기서 더한다(그 표의 줄을 다른 작업이 고치는 중이라 같은 줄을 건드리지 않으려고).
; 이 파일은 TeleportBase.ahk 끝에서 포함되므로 ConfigLoader 뒤, LoadConfig() 호출 앞에서 실행된다.
BotWarpAddDefaults()
BotWarpAddDefaults() {
    global CONFIG_DEFAULTS
    CONFIG_DEFAULTS["Features"]["BotWarp"] := 1
    for key, value in Map(
        "BotWarpConfirmTimeoutMs", 4000, "BotWarpAlertEnterDelayMs", 600, "BotWarpAfterConfirmMs", 1000,
        "BotWarpSteamStepMs", 600, "BotWarpSteamFilterMs", 800, "BotWarpBotRow", 1,
        "BotWarpJoinAlertTimeoutMs", 20000, "BotWarpArriveTimeoutMs", 90000, "BotWarpMaxJoinAlerts", 3)
        CONFIG_DEFAULTS["Settings"][key] := value
}

global gBotWarpStep := ""        ; 오버레이·로그에 보일 지금 단계
global gBotWarpStartTick := 0

; --- 스팀 쪽 (0926 실측) ---
global BOTWARP_CHAT_TITLE := "CCYXJ差传"          ; 그룹 채팅 창 제목 (정확히 같아야 한다)
global BOTWARP_STEAM_EXE := "steamwebhelper.exe"
global BOTWARP_INVITE_URL := "steam://openurl/https://steamcommunity.com/chat/invite/SzlpRahD"
global BOTWARP_FILTER_TEXT := "CCYXJ"
; 채팅 창 자리 (물리 픽셀). 노트북 패널(175% = DPI 168)에서 창이 x -1300~-14, y 35~1575 일 때 잰 좌표라
; 패널 오른쪽 끝에서 14, 위에서 35 떨어진 1286x1540 으로 옮긴다. 배율이 다르면 좌표가 맞지 않아 시작하지 않는다.
global BOTWARP_CHAT_DPI := 168
global BOTWARP_CHAT_W := 1286
global BOTWARP_CHAT_H := 1540
global BOTWARP_CHAT_RIGHT_GAP := 14
global BOTWARP_CHAT_TOP_GAP := 35
; 창 왼쪽 위에서 잰 클릭 자리 (물리 픽셀). 잰 절대 좌표: 필터 칸 (-180,270), 봇 差传CCYXJ01（全辅瞄） (-200,394), 봇 差传CCYXJ03 (-200,456)
global BOTWARP_FILTER_OFS := [1120, 235]
global BOTWARP_BOT_OFS := [[1100, 359], [1100, 421]]
; 우클릭한 자리에서 컨텍스트 메뉴 "Join Game" 까지 (잰 절대 좌표 (-446,840)). join_game.png 를 이 자리 둘레 ±BOTWARP_JOIN_SEARCH 에서 찾는다
global BOTWARP_JOIN_OFS := [-246, 446]
global BOTWARP_JOIN_SEARCH := 300

; --- GTA 쪽 화면 판정 (클라이언트 비율) ---
global BOTWARP_LOGO_AREA := [0.35, 0.37, 0.65, 0.51]    ; 노란 로고 (가장 넓은 confirm 이 x 39~61%, y 40~49%)
global BOTWARP_TEXT_AREA := [0.12, 0.49, 0.88, 0.66]    ; 로고 아래 흰 선·흰 문장
global BOTWARP_HINT_AREA := [0.55, 0.90, 1.00, 1.00]    ; 오른쪽 아래 버튼 안내
; 흰 구분선을 찾는 띠. 문장이 두 줄이면 선이 y 50.9%·59.7%, 한 줄이면 52.5%·58.1% 에 있고, 선은 문장보다 양옆으로 길다
global BOTWARP_LINE_BAND := [0.03, 0.495, 0.97, 0.615]
; 알림 화면이면 까매야 하는 점들. 로고·문장·오른쪽 아래 버튼 안내·오버레이(오른쪽 위 18% 아래)·상태 툴팁(왼쪽 아래) 자리를 피했다
global BOTWARP_BLACK_POINTS := [[0.06, 0.08], [0.50, 0.12], [0.94, 0.08], [0.06, 0.45], [0.30, 0.44],
    [0.70, 0.44], [0.94, 0.45], [0.06, 0.80], [0.50, 0.82]]
global BOTWARP_BLACK_MAX := 24            ; 세 채널이 모두 이 값 이하면 검정
global BOTWARP_YELLOW := 0xE6BE3C         ; 로고 노랑 (±70: 금색~주황빛 노랑, 흰색·회색은 빠진다)
global BOTWARP_YELLOW_VAR := 70
global BOTWARP_WHITE_VAR := 40            ; 구분선·글자는 약 0xF0F0F0
; 로고 폭(클라이언트 폭 %) 범위. 잰 값: quit 10.9~11.1, alert 15.4~15.5, confirm 21.6~21.7
global BOTWARP_LOGO_KINDS := [["quit", 9.5, 12.5], ["alert", 14.0, 17.0], ["confirm", 20.0, 23.5]]
; 알림 종류 = [이름, 로고, 구분선 폭(클라이언트 폭 %)]. 잰 폭에서 BOTWARP_LINE_TOL 안이면 그 알림이다. 문장과 가까운 다른 알림:
;   start_job    "Are you sure you want to start this Job?"                           (confirm "quit this Job?" 은 32.97)
;   unavailable  "Currently unavailable."
;   join_session "Are you sure you want to join a different GTA Online session? Progress will be automatically saved."  (그래픽 설정 적용 알림은 68.04)
;   targeting    "The Job, Activity or session you're trying to join has a different targeting mode. Do you want to change your targeting mode?"
;   incompatible "Failed to join session due to incompatible assets. Return to GTA Online."  (방치 킥 알림 "Kicked from the session for being idle too long." 은 38.44)
;   quit 로고 알림은 폭과 상관없이 키를 보내지 않는다: 게임 종료 62.58·40.24, 세션 나가기(F5) 35.40, 스토리 모드 49.61
global BOTWARP_ALERT_LINES := [["start_job", "confirm", 33.33], ["unavailable", "alert", 21.72],
    ["join_session", "alert", 67.41], ["targeting", "alert", 58.52], ["incompatible", "alert", 39.69]]
global BOTWARP_LINE_TOL := 0.25
; 도착 판정: 왼쪽 아래 체력 막대(초록 0x4C8F4C, 1920x1080 에서 y 1049~1057). 로딩·알림 화면에서는 안 보인다
global BOTWARP_HUD_BAR := [0.021, 0.972, 0.05, 0.978]
global BOTWARP_HUD_GREEN := 0x4C8F4C

ExecuteBotWarp() {
    global botWarpRunning, gAbort, gBotWarpStep, gBotWarpStartTick, gMenuBusy, clawLoopRunning, gEarnBusy

    if (!IsGTAActive() || IsTeleportRunning())
        return
    ; 다른 매크로가 게임에 키를 보내는 중이면 키가 섞인다 (수익 자동화의 작업, 이동·자동 클릭 토글 포함)
    if (gMenuBusy || clawLoopRunning || (IsSet(gEarnBusy) && gEarnBusy) || AnyInputToggleOn()) {
        ShowTooltip("스팀 작텔: 다른 매크로가 게임에 키를 보내는 중이라 시작하지 않음 (이동·자동 클릭 토글은 끄고 다시)", 2500)
        return
    }
    botWarpRunning := true
    gAbort := false
    gBotWarpStartTick := A_TickCount
    BotWarpAbortKeys(true)   ; 스팀 창이 앞이어도 End 가 먹게(평소 End 는 GTA 창에서만 잡힌다)
    result := "오류로 끝남"
    ShowTooltip("🚀 스팀 작텔 시작 (" KeyLabelFor("StopAll") ": 중단)", 1500)
    try {
        result := BotWarpRun()
    } finally {
        botWarpRunning := false
        BotWarpAbortKeys(false)
        gBotWarpStep := ""
        MacroLog("botwarp", "끝 (" Round((A_TickCount - gBotWarpStartTick) / 1000) "초): " result)
    }
}

; 오버레이·설정 창 한 줄 상태. 돌고 있지 않으면 ""
BotWarpStatusText() {
    global botWarpRunning, gBotWarpStep, gBotWarpStartTick
    if (!botWarpRunning)
        return ""
    return "스팀 작텔: " gBotWarpStep " " Round((A_TickCount - gBotWarpStartTick) / 1000) "초"
}

BotWarpRun() {
    global config, gAbort, BOTWARP_HINT_AREA
    s := config["Settings"]

    ; 0) 시작 조건. 여기서 멈추면 게임에도 스팀에도 아무것도 보내지 않은 것이다
    if (!FileExist(BotWarpSteamImage("join_game")))
        return BotWarpFail("Images\BotWarp\steam\join_game.png 가 없어 시작하지 않음 (Join Game 을 확인 없이 누르지 않으려고). 만드는 법은 BotWarp.ahk 맨 위", "join_game.png 없음")
    if (!BotWarpScreenOk(&why))
        return BotWarpFail(why, "화면 비율")

    ; 1) 스팀 채팅 창 준비. 여기까지는 게임에 키를 보내지 않는다
    BotWarpSetStep("스팀 창 준비")
    chat := BotWarpFindChat()
    if (!chat) {
        if (!FileExist(BotWarpSteamImage("open_in_steam")) || !FileExist(BotWarpSteamImage("join_group_chat")))
            return BotWarpFail('스팀 그룹 채팅 창 "CCYXJ差传" 을 열어 두고 다시 누르세요 (초대 링크로 자동으로 열려면 open_in_steam.png·join_group_chat.png 가 필요)', "채팅 창 없음 (초대 경로 참조 이미지 없음)")
        chat := BotWarpOpenChat()
        if (gAbort)
            return BotWarpFail("중단 (게임에는 아무 키도 보내지 않음)", "중단: 채팅 창 열기")
        if (!chat)
            return BotWarpFail('스팀 그룹 채팅 창 "CCYXJ差传" 을 열어 두고 다시 누르세요 (초대 링크로 열지 못함)', "채팅 창 없음")
        if (!BringGTAToFront() || !WaitAbortable(800))
            return BotWarpFail("채팅 창을 연 뒤 GTA 로 돌아오지 못함: 지도에서 작업을 다시 골라 누르세요", "채팅 창 연 뒤 GTA 복귀 실패")
    }
    if (!BotWarpPlaceChat(chat, &wx, &wy, &why))
        return BotWarpFail("스팀 채팅 창 자리 맞추기 실패: " why, "창 배치 실패: " why)
    ; 최소화된 채팅 창을 펴면 창이 앞으로 나올 수 있다. 한 번 되찾는다
    if (!gAbort && !IsGTAActive()) {
        MacroLog("botwarp", "채팅 창 자리를 맞추는 동안 GTA 가 뒤로 감 → 되찾음")
        if (BringGTAToFront())
            WaitAbortable(500)
    }
    if (gAbort || !IsGTAActive())
        return BotWarpFail("GTA 가 앞에 없어 시작하지 않음", "시작 전 포커스 이탈")
    ; 무슨 알림인지 모르는 채로 Space·Enter 를 보내지 않는다.
    ; 지도에 작업 블립이 없을 때(세션을 옮긴 직후 한동안, 0926 18:16 실측) 작업 목록(P → ONLINE → Jobs → Play Job)에서 고르면
    ; CONFIRM "start this Job?" 이 먼저 뜬다. 그 창이면 Space 없이 그 Enter 부터 한다
    fromList := false
    if (BotWarpAlertVisible()) {
        kind := BotWarpAlertKind(&info)
        MacroLog("botwarp", "시작 전 알림: " kind " (" info ")")
        if (kind = "quit")
            return BotWarpQuitSeen()
        if (kind != "start_job")
            return BotWarpFail("게임에 알림 창이 이미 떠 있어 시작하지 않음 (직접 닫고 다시)", "시작 전 알림: " kind " (" info ")")
        fromList := true
    } else if (BotWarpRef("hint_start_job", BOTWARP_HINT_AREA) = 0)
        return BotWarpFail("지도에 Start Job (Space) 안내가 안 보임: 작업 블립을 고른 뒤 누르세요", "Start Job 안내 없음")

    ; 2) 작업 시작: Space → CONFIRM "start this Job?" → Enter (목록에서 골라 CONFIRM 이 이미 떠 있으면 Space 는 건너뛴다)
    BotWarpSetStep("작업 시작")
    if (!fromList) {
        PressKey("Space")
        r := BotWarpWaitAlert(s["BotWarpConfirmTimeoutMs"])
        if (r = "abort")
            return BotWarpFail("중단: 작업 확인창이 떠 있으면 직접 Backspace(No)로 닫으세요", "중단: CONFIRM 대기")
        if (r = "timeout") {
            MacroLog("botwarp", "CONFIRM 판정 실패 화면값: " BotWarpScreenDump())
            return BotWarpFail("작업 확인창(CONFIRM)을 못 찾음: 지도에서 작업 블립을 골라 Start Job (Space) 가 보일 때 누르세요", "CONFIRM 안 보임")
        }
        kind := BotWarpAlertKind(&info)
        MacroLog("botwarp", "Space 뒤 알림: " kind " (" info ")")
        if (kind != "start_job") {
            if (kind = "quit")
                return BotWarpQuitSeen()
            if (kind = "unavailable")
                return BotWarpUnavailable()
            ; 작업 확인창이 아니면 Enter 하지 않고 Backspace(취소·No)로 닫는다. 그새 quit 로고로 바뀌었으면 그것도 보내지 않는다
            r := BotWarpKeyOnAlert("Backspace", "*")
            return BotWarpFail("작업 확인창이 아닌 알림이라 " (r = "sent" ? "Backspace 로 닫고 " : "") "멈춤: 직접 확인하세요", "CONFIRM 아님: " kind " (" info ")")
        }
    }
    ; CONFIRM 에 Enter. 키가 씹혔으면 CONFIRM 이 남아 있으니 한 번 더(두 번까지). 보낼 때마다 알림이 떠 있는지와 종류를 새로 본다
    Loop 2 {
        if (!WaitAbortable(s["BotWarpAlertEnterDelayMs"]))
            return BotWarpFail("중단: 작업 확인창이 떠 있으면 직접 Backspace(No)로 닫으세요", "CONFIRM Enter 앞에서 멈춤")
        r := BotWarpKeyOnAlert("Enter", ["start_job"])
        if (r = "gone" && A_Index > 1)
            break    ; 앞의 Enter 가 늦게 먹었다
        if (r != "sent")
            return BotWarpNotSent(r, "CONFIRM")
        if (BotWarpWaitAlertGone(2500))
            break
        if (gAbort || !IsGTAActive())
            return BotWarpFail("중단: 작업이 시작됐는지 화면을 직접 확인하세요", "중단: CONFIRM 뒤")
        if (A_Index = 2) {
            kind := BotWarpAlertKind(&info)
            if (kind = "unavailable")
                return BotWarpUnavailable()
            return BotWarpFail("작업 확인창이 Enter 두 번에도 닫히지 않아 멈춤: 직접 확인하세요", "CONFIRM 안 닫힘: " kind " (" info ")")
        }
        MacroLog("botwarp", "Enter 뒤에도 알림이 남음 → 종류를 다시 보고 한 번 더")
    }
    BotWarpSetStep("작업 로딩")
    if (!WaitAbortable(s["BotWarpAfterConfirmMs"]))
        return BotWarpFail("중단: 작업이 로딩 중이니 봇에 직접 Join Game 하거나 작업을 나가세요", "중단: 작업 로딩")

    ; 3) 스팀: 봇에 Join Game
    BotWarpSetStep("스팀 Join Game")
    if (!BotWarpSteamJoin(chat, &why)) {
        if (gAbort)
            return BotWarpFail("중단: 작업이 로딩 중이니 봇에 직접 Join Game 하거나 작업을 나가세요", "중단: 스팀 단계")
        return BotWarpFail("스팀 단계 실패(" why "): 작업이 로딩 중이니 봇에 직접 Join Game 하거나 작업을 나가세요", "스팀: " why)
    }

    ; 4) GTA: 참가 알림마다 Enter, 도착 확인
    return BotWarpJoinAlerts()
}

; Join Game 뒤. 참가 알림(다른 세션 참가 → [조준 모드] → incompatible assets)을 이 순서로 판정해 Enter 하고, 체력 막대가 보이면 도착으로 본다.
; 순서에 없는 알림·quit 로고·사용자의 키보드 입력이 보이면 키를 더 보내지 않고 멈춘다.
BotWarpJoinAlerts() {
    global config, gAbort
    s := config["Settings"]
    BotWarpSetStep("GTA 로 복귀")
    if (!BringGTAToFront())
        return BotWarpFail("GTA 를 앞으로 가져오지 못함: 직접 GTA 로 가서 알림마다 Enter (마지막은 Continue)", "GTA 복귀 실패")
    BotWarpSetStep("참가 알림 대기")
    joinStart := A_TickCount
    quietSince := A_TickCount   ; 이 뒤의 물리 키보드 입력은 사용자가 손댄 것. 매크로가 키를 보낼 때마다 옮긴다
    deadline := joinStart + s["BotWarpJoinAlertTimeoutMs"]
    done := Map(), last := "", hud := 0, refocus := 0
    Loop {
        if (gAbort)
            return BotWarpFail("중단: 남은 알림은 직접 Enter (마지막은 Continue)", "중단: 참가 알림")
        if (BotWarpUserTyped(quietSince))
            return BotWarpFail("키보드 입력이 있어 넘겨받은 것으로 보고 멈춤: 남은 알림은 직접 확인하세요", "참가 단계 사용자 키 입력 (Enter " BotWarpDoneText(done) ")")
        if (!IsGTAActive()) {
            ; 스팀이 창을 하나 더 띄웠을 수 있다. 두 번까지만 되찾는다
            if (refocus >= 2 || !BringGTAToFront())
                return BotWarpFail("GTA 가 앞에 없어 멈춤: 남은 알림은 직접 Enter (마지막은 Continue)", "참가 단계 포커스 이탈")
            refocus += 1
            quietSince := A_TickCount
            continue
        }
        if (A_TickCount > deadline) {
            MacroLog("botwarp", "시간 초과 화면값: " BotWarpScreenDump())
            if (done.Count = 0)
                return BotWarpFail("Join Game 뒤 참가 알림이 안 뜸 (봇이 게임 중이 아니거나 메뉴를 잘못 눌렀을 수 있음). 작업은 로딩 중", "참가 알림 안 뜸")
            return BotWarpFail("도착을 확인하지 못함: 화면을 직접 확인하세요", "도착 확인 시간 초과 (Enter " BotWarpDoneText(done) ")")
        }
        if (BotWarpAlertVisible()) {
            hud := 0
            Sleep(250)
            if (!BotWarpAlertVisible())
                continue
            kind := BotWarpAlertKind(&info)
            MacroLog("botwarp", "참가 알림: " kind " (" info ", Join Game 뒤 " Round((A_TickCount - joinStart) / 1000, 1) "초)")
            if (kind = "quit")
                return BotWarpQuitSeen()
            if (!BotWarpJoinNext(kind, done, last))
                return BotWarpFail("예상과 다른 알림(" kind ")이라 키를 보내지 않고 멈춤: 직접 확인하세요", "참가 단계 다른 알림: " kind " (" info ", 앞서 Enter " BotWarpDoneText(done) ")")
            if (!done.Has(kind) && done.Count >= s["BotWarpMaxJoinAlerts"])
                return BotWarpFail("알림이 더 떠서 멈춤: 직접 확인하세요", "알림 상한 넘음: " kind)
            BotWarpSetStep("알림 " kind " Enter")
            ; 기다리는 동안 전체 멈춤·포커스 이탈·키보드 입력이 있으면 맨 위에서 처리한다
            if (!WaitAbortable(s["BotWarpAlertEnterDelayMs"]) || BotWarpUserTyped(quietSince))
                continue
            r := BotWarpKeyOnAlert("Enter", [kind])
            if (r = "gone" || r = "abort")
                continue
            if (r != "sent")
                return BotWarpNotSent(r, "참가 알림")
            quietSince := A_TickCount
            done[kind] := done.Get(kind, 0) + 1
            last := kind
            deadline := A_TickCount + s["BotWarpArriveTimeoutMs"]
            BotWarpSetStep(kind = "incompatible" ? "도착 대기" : "다음 알림 대기")
            BotWarpWaitAlertGone(3000)
            continue
        }
        if (done.Count && BotWarpHudVisible()) {
            hud += 1
            if (hud >= 2) {
                if (!done.Has("incompatible"))
                    return BotWarpFail("incompatible assets 알림 없이 게임 화면으로 돌아옴: 봇 세션에 들어갔을 수 있으니 위치를 직접 확인하세요", "incompatible 없이 도착 (Enter " BotWarpDoneText(done) ")")
                ShowTooltip("✅ 스팀 작텔 완료 (작업 출발점 확인). 이 세션에서 다시 작업을 시작하면 막히니 다음 작텔은 "
                    . KeyLabelFor("InviteOnlySession") " 두 번으로 세션을 옮긴 뒤", 5000)
                return "완료 (알림 Enter " BotWarpDoneText(done) ", Join Game 뒤 " Round((A_TickCount - joinStart) / 1000) "초)"
            }
            Sleep(700)
            continue
        }
        hud := 0
        Sleep(300)
    }
}

; 참가 단계에서 kind 알림에 Enter 해도 되는지. 순서는 join_session → [targeting] → incompatible 이고 종류마다 한 번.
; 방금 Enter 한 알림이 그대로 다시 보이면(키가 씹힘) 그 알림에만 한 번 더 보낸다.
BotWarpJoinNext(kind, done, last) {
    if (kind = last)
        return done[kind] < 2
    if (done.Has(kind))
        return false
    if (kind = "join_session")
        return done.Count = 0
    if (kind = "targeting")
        return done.Has("join_session") && !done.Has("incompatible")
    if (kind = "incompatible")
        return done.Has("join_session")
    return false
}

BotWarpDoneText(done) {
    t := ""
    for kind in ["join_session", "targeting", "incompatible"] {
        if (done.Has(kind))
            t .= (t = "" ? "" : " → ") kind (done[kind] > 1 ? " x" done[kind] : "")
    }
    return t = "" ? "없음" : t
}

; since 뒤에 사람이 키보드를 눌렀으면 true. 단축키가 키보드 훅($)을 쓰므로 A_TimeIdleKeyboard 는 물리 입력만 센다.
; 매크로가 키를 보낼 때마다 since 를 옮기므로, 훅이 없어 매크로 키까지 세더라도 제 키 때문에 멈추지는 않는다.
BotWarpUserTyped(since) => A_TimeIdleKeyboard < A_TickCount - since

; === 스팀 ===

; 봇 줄 우클릭 → Join Game. 실패하면 false 와 까닭(why).
BotWarpSteamJoin(chat, &why) {
    global config, BOTWARP_FILTER_OFS, BOTWARP_BOT_OFS, BOTWARP_JOIN_OFS, BOTWARP_JOIN_SEARCH, BOTWARP_FILTER_TEXT, BOTWARP_STEAM_EXE, BOTWARP_CHAT_W, BOTWARP_CHAT_H
    s := config["Settings"]
    step := s["BotWarpSteamStepMs"]
    why := ""
    if (!WinExist("ahk_id " chat)) {
        why := "채팅 창이 닫힘"
        return false
    }
    ; GTA 가 앞이면 커서를 게임 창에 가둬(ClipCursor) 클릭이 안 먹는다. 스팀 창을 먼저 앞으로 가져온다
    if (!BotWarpActivate(chat)) {
        why := "채팅 창을 앞으로 가져오지 못함"
        return false
    }
    ; 앞으로 오면서 창이 움직였을 수 있어 자리를 다시 맞추고, 실제 자리를 기준으로 누른다
    if (!BotWarpPlaceChat(chat, &wx, &wy, &why))
        return false
    if (!BotWarpSteamWait(step)) {
        why := "중단"
        return false
    }
    chatWin := "ahk_id " chat
    ; 멤버 필터: 이미 적혀 있어도 Ctrl+A 로 덮어쓴다. 글자는 유니코드로 보내 한글 입력기 상태와 상관없게 한다
    if (!BotWarpSteamClick(wx + BOTWARP_FILTER_OFS[1], wy + BOTWARP_FILTER_OFS[2], "Left", chatWin, &why))
        return false
    Sleep(150)
    if (BotWarpStopPressed() || !WinActive(chatWin)) {
        why := BotWarpStopPressed() ? "중단" : "스팀 창이 앞에 없음"
        return false
    }
    Send("{Blind}^a")
    Sleep(100)
    for ch in StrSplit(BOTWARP_FILTER_TEXT) {
        if (BotWarpStopPressed() || !WinActive(chatWin)) {
            why := BotWarpStopPressed() ? "중단" : "스팀 창이 앞에 없음"
            return false
        }
        Send("{Blind}{U+" Format("{:04X}", Ord(ch)) "}")
    }
    if (!BotWarpSteamWait(s["BotWarpSteamFilterMs"])) {
        why := "중단"
        return false
    }
    ; 필터 결과에는 이름에 CCYXJ 가 든 일반 회원도 섞여(0926 18:11 에 CCYXJ_299 가 맨 위) 줄 순서가 바뀐다.
    ; 그래서 봇 이름 이미지(steam\bot<줄>.png)를 멤버 목록에서 찾은 자리를 누른다. 이름은 게임 중일 때 초록색이라 오프라인이면 안 찾힌다.
    n := Min(Max(Integer(s["BotWarpBotRow"]), 1), BOTWARP_BOT_OFS.Length)
    found := BotWarpSteamRef("bot" n, wx + BOTWARP_CHAT_W // 2, wy + BOTWARP_FILTER_OFS[2], wx + BOTWARP_CHAT_W - 1, wy + BOTWARP_CHAT_H - 1, &rx, &ry)
    if (found = 0) {
        why := "멤버 목록에 봇 " n " 이 안 보임 (게임 중이 아니거나 오프라인)"
        return false
    }
    if (found = -1) {
        row := BOTWARP_BOT_OFS[n]
        rx := wx + row[1], ry := wy + row[2]
        MacroLog("botwarp", "bot" n ".png 가 없어 줄 자리로 누름")
    }
    if (!BotWarpSteamClick(rx, ry, "Right", chatWin, &why))
        return false
    if (!BotWarpSteamWait(step)) {
        why := "중단"
        return false
    }
    ; 메뉴 항목은 봇 상태(게임 중인지·온라인인지)에 따라 달라진다. 좌표로 누르지 않고 "Join Game" 글자를 찾은 자리만 누른다
    jx := rx + BOTWARP_JOIN_OFS[1], jy := ry + BOTWARP_JOIN_OFS[2], d := BOTWARP_JOIN_SEARCH
    found := BotWarpSteamRef("join_game", jx - d, jy - d, jx + d, jy + d, &fx, &fy)
    if (found != 1) {
        why := found = 0 ? "메뉴에 Join Game 이 안 보임 (봇이 게임 중이 아니거나 다른 줄을 눌렀을 수 있음)" : "join_game.png 가 없음"
        return false
    }
    ; 컨텍스트 메뉴는 따로 뜬 창일 수 있어 스팀 창이면 어느 것이 앞이어도 된다
    if (!BotWarpSteamClick(fx, fy, "Left", "ahk_exe " BOTWARP_STEAM_EXE, &why))
        return false
    MacroLog("botwarp", "Join Game 누름 (" fx "," fy ", 예상 자리에서 " (fx - jx) "," (fy - jy) ", 봇 줄 " s["BotWarpBotRow"] ")")
    if (!BotWarpSteamWait(300)) {
        why := "중단"
        return false
    }
    return true
}

; 채팅 창이 없을 때 초대 링크로 연다. 버튼은 참조 이미지로 찾은 자리만 누르고(좌표로 누르지 않는다), 창마다 기다린다. 하나라도 안 되면 0.
BotWarpOpenChat() {
    global BOTWARP_INVITE_URL, BOTWARP_CHAT_TITLE
    BotWarpSetStep("스팀 채팅 열기")
    ; 친구 목록 창이 한 번도 안 떴으면 초대 페이지의 Open in Steam 을 눌러도 아무 일이 없다(0926 18:09 실측, 두 번 눌러도 무반응).
    ; 그래서 친구 목록부터 띄운다
    if (!BotWarpFindSteamWindow("Friends List")) {
        try Run("steam://open/friends")
        if (!BotWarpWaitSteamWindow("Friends List", 10000))
            return BotWarpOpenFail("친구 목록 창이 안 뜸")
    }
    try {
        Run(BOTWARP_INVITE_URL)
    } catch as e {
        return BotWarpOpenFail("초대 링크 실행: " e.Message)
    }
    ; Steam 메인 창에 초대 페이지가 뜬다 → "Open in Steam"
    main := BotWarpWaitSteamWindow("Steam", 10000)
    if (!main || !BotWarpActivate(main) || !BotWarpSteamWait(3000))
        return BotWarpOpenFail("Steam 메인 창")
    BotWarpWinRect(main, &mx, &my, &mw, &mh)
    if (BotWarpSteamRef("open_in_steam", mx, my, mx + mw - 1, my + mh - 1, &bx, &by) != 1)
        return BotWarpOpenFail("Open in Steam 버튼이 안 보임")
    if (!BotWarpSteamClick(bx, by, "Left", "ahk_id " main, &why))
        return BotWarpOpenFail("Open in Steam 클릭: " why)
    ; 주 모니터 가운데에 "Invite" 창 → "Join Group Chat"
    inv := BotWarpWaitSteamWindow("Invite", 10000)
    if (!inv || !BotWarpActivate(inv) || !BotWarpSteamWait(800))
        return BotWarpOpenFail("Invite 창")
    BotWarpWinRect(inv, &ix, &iy, &iw, &ih)
    if (BotWarpSteamRef("join_group_chat", ix, iy, ix + iw - 1, iy + ih - 1, &jx, &jy) != 1)
        return BotWarpOpenFail("Join Group Chat 버튼이 안 보임")
    if (!BotWarpSteamClick(jx, jy, "Left", "ahk_id " inv, &why))
        return BotWarpOpenFail("Join Group Chat 클릭: " why)
    chat := BotWarpWaitSteamWindow(BOTWARP_CHAT_TITLE, 15000)
    if (!chat)
        return BotWarpOpenFail("채팅 창이 안 뜸")
    MacroLog("botwarp", "초대 링크로 채팅 창을 엶")
    return chat
}

BotWarpOpenFail(where) {
    MacroLog("botwarp", "초대 링크로 채팅 창 열기 실패: " where)
    return 0
}

; 채팅 창을 GTA 가 없는 모니터 오른쪽 위의 잰 자리·크기로 옮긴다. 성공하면 실제 창 왼쪽 위(물리 픽셀)를 &wx, &wy 로.
BotWarpPlaceChat(hwnd, &wx, &wy, &why) {
    global BOTWARP_CHAT_W, BOTWARP_CHAT_H, BOTWARP_CHAT_DPI
    wx := 0, wy := 0, why := ""
    if (!BotWarpChatTarget(&tx, &ty, &why))
        return false
    try {
        if (WinGetMinMax("ahk_id " hwnd) != 0) {
            ; 앞으로 가져오지 않고 편다(SW_SHOWNOACTIVATE). 시작 전에는 GTA 가 앞에 있어야 한다. 그래도 안 펴지면 WinRestore
            DllCall("ShowWindow", "ptr", hwnd, "int", 4)
            Sleep(300)
            if (WinGetMinMax("ahk_id " hwnd) != 0) {
                WinRestore("ahk_id " hwnd)
                Sleep(300)
            }
        }
    } catch {
        why := "채팅 창이 닫힘"
        return false
    }
    Loop 5 {
        BotWarpWinRect(hwnd, &x, &y, &w, &h)
        if (Abs(x - tx) <= 3 && Abs(y - ty) <= 3 && Abs(w - BOTWARP_CHAT_W) <= 3 && Abs(h - BOTWARP_CHAT_H) <= 3) {
            wx := x, wy := y
            return true
        }
        if (A_Index = 5)
            break
        ; 배율이 다른 모니터에서 넘어오면 창이 배율 변경에 맞춰 스스로 크기를 바꾼다.
        ; 그래서 처음엔 위치만 옮겨 그 변화를 먼저 끝내고, 같은 모니터 안에서 크기를 맞춘다.
        if (A_Index = 1 && BotWarpWindowDpi(hwnd) != BOTWARP_CHAT_DPI)
            BotWarpWinMove(hwnd, tx, ty)
        else
            BotWarpWinMove(hwnd, tx, ty, BOTWARP_CHAT_W, BOTWARP_CHAT_H)
        Sleep(400)
    }
    why := "창이 " x "," y " " w "x" h " 에 남음 (목표 " tx "," ty " " BOTWARP_CHAT_W "x" BOTWARP_CHAT_H ")"
    return false
}

; 채팅 창을 둘 자리(물리 픽셀). GTA 창 가운데가 들어 있지 않은 첫 모니터의 오른쪽 위. 배율이 잰 값(175%)과 다르면 false.
BotWarpChatTarget(&tx, &ty, &why) {
    global GTA_WIN, BOTWARP_CHAT_DPI, BOTWARP_CHAT_W, BOTWARP_CHAT_H, BOTWARP_CHAT_RIGHT_GAP, BOTWARP_CHAT_TOP_GAP
    tx := 0, ty := 0, why := ""
    prev := BotWarpDpiPhys()
    try {
        hasGta := false, gx := 0, gy := 0
        if (g := WinExist(GTA_WIN)) {
            WinGetPos(&x, &y, &w, &h, "ahk_id " g)
            gx := x + w // 2, gy := y + h // 2, hasGta := true
        }
        pick := 0
        Loop MonitorGetCount() {
            MonitorGet(A_Index, &l, &t, &r, &b)
            if (hasGta && gx >= l && gx < r && gy >= t && gy < b)
                continue
            pick := A_Index
            break
        }
        if (!pick) {
            why := "GTA 가 없는 모니터가 없음 (노트북 화면이 꺼져 있나?)"
            return false
        }
        MonitorGet(pick, &l, &t, &r, &b)
        dpi := BotWarpMonitorDpi((l + r) // 2, (t + b) // 2)
        if (dpi != BOTWARP_CHAT_DPI) {
            why := "노트북 화면 배율이 " Round(dpi / 0.96) "% (좌표는 " Round(BOTWARP_CHAT_DPI / 0.96) "% 에서 잼)"
            return false
        }
        tx := r - BOTWARP_CHAT_RIGHT_GAP - BOTWARP_CHAT_W
        ty := t + BOTWARP_CHAT_TOP_GAP
        if (tx < l || ty + BOTWARP_CHAT_H > b) {
            why := "노트북 화면(" (r - l) "x" (b - t) ")이 채팅 창보다 작음"
            return false
        }
        return true
    } finally {
        BotWarpDpiRestore(prev)
    }
}

; 스팀 창을 앞으로. WinActivate 가 안 먹으면 AFK 방지의 GTA 전면화와 같은 방식(앞 창 입력 스레드에 잠깐 붙기)으로 한 번 더.
BotWarpActivate(hwnd) {
    try {
        if (WinGetMinMax("ahk_id " hwnd) = -1)
            WinRestore("ahk_id " hwnd)
        WinActivate("ahk_id " hwnd)
    }
    if (WinWaitActive("ahk_id " hwnd, , 1.5))
        return true
    fg := DllCall("GetForegroundWindow", "ptr")
    fgThread := DllCall("GetWindowThreadProcessId", "ptr", fg, "ptr", 0, "uint")
    myThread := DllCall("GetCurrentThreadId", "uint")
    DllCall("AttachThreadInput", "uint", myThread, "uint", fgThread, "int", 1)
    DllCall("BringWindowToTop", "ptr", hwnd)
    DllCall("SetForegroundWindow", "ptr", hwnd)
    DllCall("AttachThreadInput", "uint", myThread, "uint", fgThread, "int", 0)
    return WinWaitActive("ahk_id " hwnd, , 1.5) != 0
}

; 물리 좌표 (x, y) 를 누른다. 누르기 전에 전체 멈춤과 앞 창(activeTitle)을 보고, 커서가 실제로 그 자리에 갔는지 확인한다.
BotWarpSteamClick(x, y, button, activeTitle, &why) {
    why := ""
    if (BotWarpStopPressed()) {
        why := "중단"
        return false
    }
    if (!WinActive(activeTitle)) {
        why := "스팀 창이 앞에 없음"
        return false
    }
    if (!BotWarpCursorTo(x, y)) {
        ; GTA 가 걸어 둔 커서 가둠(ClipCursor)이 남아 있으면 풀고 한 번 더
        DllCall("ClipCursor", "ptr", 0)
        if (!BotWarpCursorTo(x, y)) {
            why := "커서를 " x "," y " 로 옮기지 못함"
            return false
        }
    }
    Sleep(80)
    ; 대기 중 End나 창 전환이 끼어들면 이미 시작한 호출도 입력 없이 끝낸다.
    if (BotWarpStopPressed()) {
        why := "중단"
        return false
    }
    if (!WinActive(activeTitle)) {
        why := "스팀 창이 앞에 없음"
        return false
    }
    Click(button)   ; 지금 커서 자리에서
    MacroLog("botwarp", "스팀 " button " 클릭 " x "," y)
    return true
}

BotWarpCursorTo(x, y) {
    prev := BotWarpDpiPhys()
    try {
        DllCall("SetCursorPos", "int", x, "int", y)
        pt := Buffer(8, 0)
        DllCall("GetCursorPos", "ptr", pt)
        return Abs(NumGet(pt, 0, "int") - x) <= 2 && Abs(NumGet(pt, 4, "int") - y) <= 2
    } finally {
        BotWarpDpiRestore(prev)
    }
}

BotWarpFindChat() {
    global BOTWARP_CHAT_TITLE
    return BotWarpFindSteamWindow(BOTWARP_CHAT_TITLE)
}

; 제목이 정확히 title 인 보이는 스팀 창 (부분 일치로 찾으면 같은 이름이 든 다른 창을 잡을 수 있다)
BotWarpFindSteamWindow(title) {
    global BOTWARP_STEAM_EXE
    for hwnd in WinGetList("ahk_exe " BOTWARP_STEAM_EXE) {
        t := ""
        try t := WinGetTitle("ahk_id " hwnd)
        if (t == title)
            return hwnd
    }
    return 0
}

BotWarpWaitSteamWindow(title, timeoutMs) {
    deadline := A_TickCount + timeoutMs
    Loop {
        if (hwnd := BotWarpFindSteamWindow(title))
            return hwnd
        if (A_TickCount >= deadline || !BotWarpSteamWait(250))
            return 0
    }
}

; 스팀 단계의 대기. GTA 가 앞이 아니라 End 단축키가 안 잡히므로 키 상태를 직접 본다. 중단이면 false.
BotWarpSteamWait(ms) {
    deadline := A_TickCount + ms
    while (A_TickCount < deadline) {
        if (BotWarpStopPressed())
            return false
        Sleep(50)
    }
    return !BotWarpStopPressed()
}

; 작텔 도중에만 전체 멈춤 키([Hotkeys] StopAll)를 모든 창에서 받는다. ~ 라 키는 앞 창에도 그대로 간다.
; GTA 창 전용 StopAll 단축키와 같은 키의 다른 변형(HotIf 없음)이라 GTA 가 앞일 때는 원래 단축키가 먼저 잡힌다.
BotWarpAbortKeys(on) {
    global config
    HotIf()
    for key in StrSplit(config["Hotkeys"].Get("StopAll", ""), ",", " `t") {
        if (key = "")
            continue
        try Hotkey("~*" key, BotWarpAbortKey, on ? "On" : "Off")
        catch as e
            MacroLog("botwarp", "중단 키 " key " 등록 실패: " e.Message)
    }
}

BotWarpAbortKey(hk) {
    global gAbort, botWarpRunning
    if (botWarpRunning && !gAbort) {
        gAbort := true
        MacroLog("botwarp", hk " 눌림 → 중단")
    }
}

; 전체 멈춤 신호가 있거나 전체 멈춤 키([Hotkeys] StopAll)가 눌려 있으면 true
BotWarpStopPressed() {
    global gAbort, config
    if (gAbort)
        return true
    for key in StrSplit(config["Hotkeys"].Get("StopAll", ""), ",", " `t") {
        try {
            if (key != "" && GetKeyState(key, "P")) {
                gAbort := true
                MacroLog("botwarp", "스팀 단계에서 " key " 눌림 → 중단")
                return true
            }
        }
    }
    return false
}

BotWarpSteamImage(name) => A_ScriptDir "\Images\BotWarp\steam\" name ".png"

; 스팀 화면 참조 이미지(Images\BotWarp\steam\<name>.png)를 물리 좌표 사각형 안에서 찾는다. 없으면 -1, 못 찾으면 0, 찾으면 1 과 가운데 자리.
BotWarpSteamRef(name, x1, y1, x2, y2, &fx, &fy) {
    fx := 0, fy := 0
    img := BotWarpSteamImage(name)
    if (!FileExist(img))
        return -1
    prev := BotWarpDpiPhys()
    try {
        CoordMode("Pixel", "Screen")
        if (!ImageSearch(&ix, &iy, x1, y1, x2, y2, "*50 *Trans0xFF00FF " img))
            return 0
    } catch as e {
        MacroLog("botwarp", "ImageSearch 오류 steam\" name ": " e.Message)
        return 0
    } finally {
        BotWarpDpiRestore(prev)
    }
    BotWarpImageSize(img, &iw, &ih)
    fx := ix + iw // 2, fy := iy + ih // 2
    return 1
}

BotWarpImageSize(img, &w, &h) {
    w := 0, h := 0
    try {
        hbm := LoadPicture(img)
        bm := Buffer(32, 0)   ; BITMAP (64비트)
        DllCall("GetObject", "ptr", hbm, "int", bm.Size, "ptr", bm)
        w := NumGet(bm, 4, "int"), h := NumGet(bm, 8, "int")
        DllCall("DeleteObject", "ptr", hbm)
    }
}

; === 창·모니터 좌표 (물리 픽셀) ===
; 노트북 패널(175%)과 외장(100%)이 섞여 있어 기본 문맥(시스템 DPI 96)에서는 패널 좌표가 줄어들어 보인다.
; 그래서 창·모니터·커서 좌표는 잠깐 PER_MONITOR_AWARE_V2 문맥으로 바꿔서 다룬다 (인형 뽑기와 같은 방식). 바꾼 채로 Sleep 하지 않는다.
BotWarpDpiPhys() => DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")

BotWarpDpiRestore(prev) {
    if (prev)
        DllCall("SetThreadDpiAwarenessContext", "ptr", prev, "ptr")
}

BotWarpWinRect(hwnd, &x, &y, &w, &h) {
    x := 0, y := 0, w := 0, h := 0
    prev := BotWarpDpiPhys()
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    } catch {
        ; 창이 닫혔으면 0 으로 둔다 (호출한 쪽의 자리 비교가 실패한다)
    } finally {
        BotWarpDpiRestore(prev)
    }
}

BotWarpWinMove(hwnd, x, y, w := "", h := "") {
    prev := BotWarpDpiPhys()
    try {
        if (w = "")
            WinMove(x, y, , , "ahk_id " hwnd)
        else
            WinMove(x, y, w, h, "ahk_id " hwnd)
    } catch as e {
        MacroLog("botwarp", "창 옮기기 실패: " e.Message)
    } finally {
        BotWarpDpiRestore(prev)
    }
}

BotWarpWindowDpi(hwnd) => DllCall("GetDpiForWindow", "ptr", hwnd, "uint")

; 물리 좌표 (x, y) 가 든 모니터의 배율 DPI (100% = 96, 175% = 168). 물리 문맥 안에서 부른다.
BotWarpMonitorDpi(x, y) {
    hMon := DllCall("MonitorFromPoint", "int64", (y << 32) | (x & 0xFFFFFFFF), "uint", 2, "ptr")
    dx := 0, dy := 0
    if (DllCall("Shcore\GetDpiForMonitor", "ptr", hMon, "int", 0, "uint*", &dx, "uint*", &dy, "int") != 0)
        return 0
    return dx
}

; === GTA 화면 판정 ===

; 판정 값은 16:9 화면에서 잰 비율이다. 게임 화면(클라이언트)이 16:9 가 아니면 false 와 까닭
BotWarpScreenOk(&why) {
    why := ""
    hwnd := IsGTAActive()
    if (!hwnd) {
        why := "GTA 가 앞에 없어 시작하지 않음"
        return false
    }
    cw := 0, ch := 0
    prev := BotWarpDpiPhys()
    try {
        WinGetClientPos(, , &cw, &ch, "ahk_id " hwnd)
    } catch {
        cw := 0, ch := 0
    } finally {
        BotWarpDpiRestore(prev)
    }
    if (ch > 0 && Abs(cw / ch - 16 / 9) <= 0.02)
        return true
    why := "게임 화면이 " cw "x" ch " 라 시작하지 않음: 알림 판정 값은 16:9 화면에서 잰 것"
    return false
}

; 알림 화면(검은 바탕 + 가운데 노란 로고 + 그 아래 흰 글자)이 떠 있으면 true
BotWarpAlertVisible() {
    global BOTWARP_BLACK_POINTS, BOTWARP_BLACK_MAX, BOTWARP_LOGO_AREA, BOTWARP_TEXT_AREA, BOTWARP_YELLOW, BOTWARP_YELLOW_VAR, BOTWARP_WHITE_VAR
    hwnd := IsGTAActive()
    if (!hwnd)
        return false
    prev := BotWarpDpiPhys()
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        CoordMode("Pixel", "Screen")
        for p in BOTWARP_BLACK_POINTS {
            c := Integer(PixelGetColor(cx + Round(cw * p[1]), cy + Round(ch * p[2])))
            if (((c >> 16) & 0xFF) > BOTWARP_BLACK_MAX || ((c >> 8) & 0xFF) > BOTWARP_BLACK_MAX || (c & 0xFF) > BOTWARP_BLACK_MAX)
                return false
        }
        a := BOTWARP_LOGO_AREA, t := BOTWARP_TEXT_AREA
        if (!PixelSearch(&fx, &fy, cx + Round(cw * a[1]), cy + Round(ch * a[2]), cx + Round(cw * a[3]), cy + Round(ch * a[4]), BOTWARP_YELLOW, BOTWARP_YELLOW_VAR))
            return false
        return PixelSearch(&fx, &fy, cx + Round(cw * t[1]), cy + Round(ch * t[2]), cx + Round(cw * t[3]), cy + Round(ch * t[4]), 0xFFFFFF, BOTWARP_WHITE_VAR)
    } finally {
        BotWarpDpiRestore(prev)
    }
}

; timeoutMs 안에 알림이 (250ms 사이 두 번 연달아) 보이면 "seen", 시간이 다 되면 "timeout", 전체 멈춤·포커스 이탈이면 "abort"
BotWarpWaitAlert(timeoutMs) {
    global gAbort
    deadline := A_TickCount + timeoutMs
    Loop {
        if (gAbort || !IsGTAActive())
            return "abort"
        if (BotWarpAlertVisible()) {
            Sleep(250)
            if (BotWarpAlertVisible())
                return "seen"
        }
        if (A_TickCount >= deadline)
            return "timeout"
        Sleep(150)
    }
}

; 알림이 사라지면(두 번 연달아 안 보이면) true. 시간이 다 됐어도 방금 한 번 안 보였으면 한 번 더 보고 정한다.
; 시간 초과·전체 멈춤·포커스 이탈이면 false. false 여도 알림이 떠 있다는 뜻은 아니니, 키를 보내기 전에는 BotWarpKeyOnAlert 로 다시 본다.
BotWarpWaitAlertGone(timeoutMs) {
    global gAbort
    deadline := A_TickCount + timeoutMs
    misses := 0
    Loop {
        if (gAbort || !IsGTAActive())
            return false
        misses := BotWarpAlertVisible() ? 0 : misses + 1
        if (misses >= 2)
            return true
        if (A_TickCount >= deadline && misses = 0)
            return false
        Sleep(200)
    }
}

; 알림에 key 를 보내기 직전의 마지막 확인. GTA 가 앞이고, 알림이 250ms 사이 두 번 보이고, 그 종류가 want(배열)에 있을 때만 보낸다.
; want 가 "*" 이면 quit 로고만 아니면 된다. quit 로고에는 무엇을 넘겨도 보내지 않는다.
; 돌려주는 값: "sent", "gone"(알림이 사라짐), "abort"(전체 멈춤·포커스 이탈), 그 밖에는 지금 뜬 알림의 종류(키를 보내지 않았다)
BotWarpKeyOnAlert(key, want) {
    global gAbort
    Loop 2 {
        if (gAbort || !IsGTAActive())
            return "abort"
        if (!BotWarpAlertVisible())
            return "gone"
        if (A_Index = 1)
            Sleep(250)
    }
    kind := BotWarpAlertKind(&info)
    ok := kind != "quit"
    if (ok && Type(want) != "String") {
        ok := false
        for w in want {
            if (kind = w)
                ok := true
        }
    }
    if (!ok) {
        MacroLog("botwarp", key " 직전 확인: 지금 알림이 " kind " (" info ") 라 보내지 않음")
        return kind
    }
    if (gAbort || !IsGTAActive())
        return "abort"
    PressKey(key)
    MacroLog("botwarp", key " 보냄: " kind " (" info ")")
    return "sent"
}

; 지금 뜬 알림의 종류: quit / unavailable / start_job / join_session / targeting / incompatible, 못 가르면 "?".
; 참조 이미지가 있으면 먼저 보고, 없으면 로고 폭과 흰 구분선 폭으로 가른다. quit 로고는 어느 쪽으로든 보이면 quit.
; info 에는 로그용으로 잰 값을 담는다.
BotWarpAlertKind(&info := "") {
    global BOTWARP_LOGO_AREA, BOTWARP_TEXT_AREA, BOTWARP_ALERT_LINES, BOTWARP_LINE_TOL
    logo := BotWarpLogoWidthPct(), line := BotWarpLineWidthPct()
    head := BotWarpLogoKind(logo)
    info := "로고 " head " " Format("{:.2f}", logo) "%, 구분선 " Format("{:.2f}", line) "%"
    if (head = "quit" || BotWarpRef("logo_quit", BOTWARP_LOGO_AREA) = 1)
        return "quit"
    for kind in ["unavailable", "start_job", "join_session", "targeting", "incompatible"] {
        if (BotWarpRef("txt_" kind, BOTWARP_TEXT_AREA) = 1)
            return kind
    }
    for a in BOTWARP_ALERT_LINES {
        if (head = a[2] && Abs(line - a[3]) <= BOTWARP_LINE_TOL)
            return a[1]
    }
    return "?"
}

; 로고 폭(%)으로 가른 머리글: quit / alert / confirm, 범위 밖이면 "?"
BotWarpLogoKind(pct) {
    global BOTWARP_LOGO_KINDS
    for k in BOTWARP_LOGO_KINDS {
        if (pct >= k[2] && pct <= k[3])
            return k[1]
    }
    return "?"
}

; GTA 참조 이미지 Images\BotWarp\<클라이언트 가로>x<세로>\<name>.png 를 area(클라이언트 비율) 안에서 찾는다. 없으면 -1, 못 찾으면 0, 찾으면 1.
BotWarpRef(name, area) {
    hwnd := IsGTAActive()
    if (!hwnd)
        return 0
    prev := BotWarpDpiPhys()
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        img := A_ScriptDir "\Images\BotWarp\" cw "x" ch "\" name ".png"
        if (!FileExist(img))
            return -1
        CoordMode("Pixel", "Screen")
        return ImageSearch(&fx, &fy, cx + Round(cw * area[1]), cy + Round(ch * area[2]),
            cx + Round(cw * area[3]) - 1, cy + Round(ch * area[4]) - 1, "*50 *Trans0xFF00FF " img) ? 1 : 0
    } catch as e {
        MacroLog("botwarp", "ImageSearch 오류 " name ": " e.Message)
        return 0
    } finally {
        BotWarpDpiRestore(prev)
    }
}

; 노란 로고의 가로 폭(클라이언트 폭 %). 못 찾으면 0.
; PixelSearch 는 줄 단위로 훑어 첫 점이 가장 왼쪽이라는 보장이 없어, x 범위를 반씩 줄여 가장 왼쪽·오른쪽을 찾는다.
BotWarpLogoWidthPct() {
    global BOTWARP_LOGO_AREA, BOTWARP_YELLOW, BOTWARP_YELLOW_VAR
    hwnd := IsGTAActive()
    if (!hwnd)
        return 0
    prev := BotWarpDpiPhys()
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        CoordMode("Pixel", "Screen")
        a := BOTWARP_LOGO_AREA
        x1 := cx + Round(cw * a[1]), y1 := cy + Round(ch * a[2]), x2 := cx + Round(cw * a[3]), y2 := cy + Round(ch * a[4])
        if (!PixelSearch(&fx, &fy, x1, y1, x2, y2, BOTWARP_YELLOW, BOTWARP_YELLOW_VAR))
            return 0
        lo := x1, hi := x2
        while (lo < hi) {
            mid := (lo + hi) // 2
            if (PixelSearch(&fx, &fy, x1, y1, mid, y2, BOTWARP_YELLOW, BOTWARP_YELLOW_VAR))
                hi := mid
            else
                lo := mid + 1
        }
        left := lo
        lo := left, hi := x2
        while (lo < hi) {
            mid := (lo + hi + 1) // 2
            if (PixelSearch(&fx, &fy, mid, y1, x2, y2, BOTWARP_YELLOW, BOTWARP_YELLOW_VAR))
                lo := mid
            else
                hi := mid - 1
        }
        return Round((lo - left + 1) * 100 / cw, 2)
    } catch {
        return 0
    } finally {
        BotWarpDpiRestore(prev)
    }
}

; 로고 아래 흰 구분선의 가로 폭(클라이언트 폭 %). 못 찾으면 0.
; 띠를 위에서부터 줄 단위로 훑어 처음 만나는 흰 점은 그 줄의 왼쪽 끝이다(선은 문장보다 양옆으로 길고, 로고는 노랗다).
; 같은 줄을 오른쪽에서부터 훑어 오른쪽 끝을 찾고, 그 사이 아홉 점이 모두 희면 선으로 본다. 글자 줄이면(사이가 끊기면)
; 그 아래 줄부터 다시 훑는다. 윗선이 흐리게 그려져도 아랫선(폭이 같다)에서 잰다.
; 0926 원본 캡처(1920x1080)에 같은 방식을 돌려 68.02%·38.44% 가 나왔다(부분 픽셀까지 센 값 68.04·38.44).
BotWarpLineWidthPct() {
    global BOTWARP_LINE_BAND, BOTWARP_WHITE_VAR
    hwnd := IsGTAActive()
    if (!hwnd)
        return 0
    prev := BotWarpDpiPhys()
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        CoordMode("Pixel", "Screen")
        b := BOTWARP_LINE_BAND
        x1 := cx + Round(cw * b[1]), y1 := cy + Round(ch * b[2]), x2 := cx + Round(cw * b[3]), y2 := cy + Round(ch * b[4])
        low := 255 - BOTWARP_WHITE_VAR
        top := y1
        Loop 80 {
            if (top > y2 || !PixelSearch(&lx, &ly, x1, top, x2, y2, 0xFFFFFF, BOTWARP_WHITE_VAR))
                return 0
            top := ly + 1
            if (!PixelSearch(&rx, &ry, x2, ly, x1, ly, 0xFFFFFF, BOTWARP_WHITE_VAR) || rx - lx < cw // 10)
                continue
            solid := true
            Loop 9 {
                c := Integer(PixelGetColor(lx + (rx - lx) * A_Index // 10, ly))
                if (((c >> 16) & 0xFF) < low || ((c >> 8) & 0xFF) < low || (c & 0xFF) < low) {
                    solid := false
                    break
                }
            }
            if (solid)
                return Round((rx - lx + 1) * 100 / cw, 2)
        }
        return 0
    } catch {
        return 0
    } finally {
        BotWarpDpiRestore(prev)
    }
}

; 판정이 안 될 때 로그에 남길 화면값 (검은 점들의 색, 노란 로고·흰 글자 발견 여부, 로고·구분선 폭)
BotWarpScreenDump() {
    global BOTWARP_BLACK_POINTS, BOTWARP_LOGO_AREA, BOTWARP_TEXT_AREA, BOTWARP_YELLOW, BOTWARP_YELLOW_VAR, BOTWARP_WHITE_VAR
    hwnd := IsGTAActive()
    if (!hwnd)
        return "GTA 가 앞에 없음"
    prev := BotWarpDpiPhys()
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        CoordMode("Pixel", "Screen")
        out := cw "x" ch " 검은 점:"
        for p in BOTWARP_BLACK_POINTS
            out .= " " PixelGetColor(cx + Round(cw * p[1]), cy + Round(ch * p[2]))
        a := BOTWARP_LOGO_AREA, t := BOTWARP_TEXT_AREA
        yellow := PixelSearch(&fx, &fy, cx + Round(cw * a[1]), cy + Round(ch * a[2]), cx + Round(cw * a[3]), cy + Round(ch * a[4]), BOTWARP_YELLOW, BOTWARP_YELLOW_VAR)
        white := PixelSearch(&fx, &fy, cx + Round(cw * t[1]), cy + Round(ch * t[2]), cx + Round(cw * t[3]), cy + Round(ch * t[4]), 0xFFFFFF, BOTWARP_WHITE_VAR)
        out .= " 노란 로고=" yellow " 흰 글자=" white
    } catch as e {
        return "화면값 읽기 실패: " e.Message
    } finally {
        BotWarpDpiRestore(prev)
    }
    return out " 로고 폭 " Format("{:.2f}", BotWarpLogoWidthPct()) "% 구분선 폭 " Format("{:.2f}", BotWarpLineWidthPct()) "%"
}

; 왼쪽 아래 체력 막대가 보이면 true (로딩·알림·일시정지 화면에서는 안 보인다)
BotWarpHudVisible() {
    global BOTWARP_HUD_BAR, BOTWARP_HUD_GREEN
    hwnd := IsGTAActive()
    if (!hwnd)
        return false
    prev := BotWarpDpiPhys()
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        CoordMode("Pixel", "Screen")
        a := BOTWARP_HUD_BAR
        return PixelSearch(&fx, &fy, cx + Round(cw * a[1]), cy + Round(ch * a[2]), cx + Round(cw * a[3]), cy + Round(ch * a[4]), BOTWARP_HUD_GREEN, 30)
    } finally {
        BotWarpDpiRestore(prev)
    }
}

; === 멈춤 처리 ===

BotWarpSetStep(text) {
    global gBotWarpStep, gBotWarpStartTick
    gBotWarpStep := text
    MacroLog("botwarp", "단계: " text " (+" (A_TickCount - gBotWarpStartTick) "ms)")
}

; 알림 키를 보내지 않은 까닭(r: BotWarpKeyOnAlert 가 돌려준 값)에 맞춰 멈춘다
BotWarpNotSent(r, where) {
    if (r = "quit")
        return BotWarpQuitSeen()
    if (r = "unavailable")
        return BotWarpUnavailable()
    if (r = "abort")
        return BotWarpFail("중단: 화면을 직접 확인하세요", "중단: " where)
    if (r = "gone")
        return BotWarpFail("알림이 사라져 멈춤: 화면을 직접 확인하세요", where " 알림 사라짐")
    return BotWarpFail("예상과 다른 알림(" r ")이라 키를 보내지 않고 멈춤: 직접 확인하세요", where " 다른 알림: " r)
}

; "Currently unavailable." (Cancel 뿐): 그 알림이 지금 떠 있는지 다시 보고 Backspace 로 닫은 뒤 멈춘다
BotWarpUnavailable() {
    r := BotWarpKeyOnAlert("Backspace", ["unavailable"])
    return BotWarpFail("이 세션에서는 작업 시작이 막힘(Currently unavailable" (r = "sent" ? "" : ", 알림은 직접 닫으세요") "): "
        . KeyLabelFor("InviteOnlySession") " 두 번(초대 전용 세션)으로 옮긴 뒤 다시 누르세요", "Currently unavailable (Backspace " (r = "sent" ? "보냄" : "안 보냄: " r) ")")
}

; 종료 확인창(quit 로고: 게임 종료·세션 나가기·스토리 모드)에는 아무 키도 보내지 않는다
BotWarpQuitSeen() {
    return BotWarpFail("종료 확인창(quit)이 보여 아무 키도 보내지 않고 멈춤: 직접 Cancel(Backspace)로 닫으세요", "quit 로고")
}

; 멈춘 까닭을 툴팁·로그로 알리고 로그용 결과 문자열을 돌려준다
BotWarpFail(msg, reason) {
    global gAbort
    ShowTooltip((gAbort ? "⏹ " : "⚠ ") "스팀 작텔: " msg, 6000)
    MacroLog("botwarp", "멈춤: " reason)
    return "멈춤: " reason
}
