; === 수익 자동화 공통: 화면 확인 · 상호작용 메뉴 · 스폰 위치 · 세션 재접속 ===
; 이 파일의 함수는 게임에 키를 하나 보낼 때마다 "지금 화면에 무엇이 보이는지" 를 템플릿(Images\Earn\<가로>x<세로>\*.png)으로 확인한다.
; 확인이 안 되면 그 자리에서 false 를 돌려주고 더 누르지 않는다. 되돌리는 키는 Backspace·M 만 쓴다(Esc 금지: 런처 종료창).
; 템플릿은 1920x1080 테두리 없는 창에서 뜬 것이다. 해상도가 다르면 그 해상도 폴더에 같은 이름으로 떠 넣어야 동작한다(없으면 멈춘다).
global gEarnBusy := false        ; 수익 자동화가 게임에 키를 보내는 중. AFK 방지가 이 동안 쉰다
global gEarnFail := ""           ; 마지막으로 멈춘 까닭 (오버레이·설정 창·로그에 보인다)
global gEarnCleanupNoScreen := false  ; 마지막 MCT 정리가 "열린 MCT 화면 없음"으로 실패했는가
global gEarnCleanupTimedOut := false  ; 마지막 MCT 정리가 아무 화면도 못 알아본 채 마감됐는가(목록을 다 못 훑은 경우 포함)
global gEarnSkipOcr := false      ; 카메라 회전 중에는 판독마다 1~2초 걸리는 OCR 대체 경로를 건너뛴다(끝난 뒤 최종 확인이 OCR 을 쓴다)
global gEarnRetryIn := 0          ; 작업이 지정한 재시도 간격. 0이면 스케줄러의 기본 backoff를 쓴다

; 상호작용 메뉴가 차지하는 영역(클라이언트 비율). 제목·줄 템플릿은 여기서만 찾는다
global EARN_MENU_AREA := [0, 0, 0.27, 0.55]
; 체력 막대(왼쪽 아래 초록 0x4C8F4C, 1920x1080 에서 y 1049~1057) 확인 영역과 색. 로딩 끝 판정에 쓴다 (0926 실측)
global EARN_HUD_BAR := [0.021, 0.972, 0.05, 0.978]
global EARN_HUD_GREEN := 0x4C8F4C
; 왼쪽 위 도움말 안내(Press E to ...) 영역
global EARN_PROMPT_AREA := [0, 0, 0.3, 0.1]

EarnLog(msg) {
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " msg "`n", A_Temp "\gta-earn.log", "UTF-8")
}

; 멈춘 까닭을 남기고 false 를 돌려준다. 호출한 쪽은 그대로 return 하면 된다.
EarnFail(reason) {
    global gEarnFail
    gEarnFail := reason
    EarnLog("멈춤: " reason)
    ; MCT 진입·정리 실패는 로그만으로는 화면이 어땠는지 알 수 없다(1009: HDR 자동 OFF 반영 뒤 "화면이 안 열림"·"알려진 화면 확인
    ; 시간 초과"가 하루 40회 반복됐는데 Steam 녹화가 꺼져 있어 증거가 없었다). 실패 순간의 GTA 클라이언트를 그대로 남긴다.
    if (InStr(reason, "MCT") = 1)
        EarnSnapFail(reason)
    return false
}

; 매크로를 다시 띄워도 남아야 하는 관측값(DJ 인기도 하락 시각·창고 생산 속도)을 %TEMP%\gta-earn-state.txt 에 key=value 로 둔다.
; 1005 에 재시작이 잦아 메모리에만 둔 창고 속도가 매번 지워졌고, 창고를 하루 종일 10분마다 확인했다.
EarnStateGet(key, default := "") {
    try {
        for line in StrSplit(FileRead(A_Temp "\gta-earn-state.txt", "UTF-8"), "`n", "`r")
            if (InStr(line, key "=") = 1)
                return SubStr(line, StrLen(key) + 2)
    }
    return default
}

EarnStateSet(key, value) {
    path := A_Temp "\gta-earn-state.txt", text := "", out := ""
    try text := FileRead(path, "UTF-8")
    for line in StrSplit(text, "`n", "`r")
        if (line != "" && InStr(line, key "=") != 1)
            out .= line "`n"
    try {
        f := FileOpen(path, "w", "UTF-8-RAW")
        f.Write(out key "=" value "`n")
        f.Close()
    }
}

EarnUnixNow() => DateDiff(A_NowUTC, "19700101000000", "Seconds")

; 거래 입력 전에 지속 상태를 확인한다. 저장 실패면 요청 자체를 보내지 않는다.
EarnTransactionBegin(id, reason) {
    EarnStateSet("pending_" id, reason)
    return EarnStateGet("pending_" id) = reason || EarnFail("거래 대기 상태 저장 실패: " id)
}

EarnTransactionConfirmed(id) {
    EarnStateSet("pending_" id, "")
}

; 거래 금액·완료 근거를 확정 원장에 남긴 뒤 기존 pending 상태를 정리한다.
EarnTransactionCashConfirmed(id, direction, amount, source, evidence, path := "") {
    global gEarnHeld
    if (EarnStateGet("pending_" id) = "") {
        reason := "원장 거래 확인 도중 pending 상태 누락, 실제 결과 확인 필요"
        EarnStateSet("pending_" id, reason)
        if (EarnStateGet("pending_" id) = reason)
            EarnLog("원장: " id " 거래의 pending 누락. 재요청 방지를 위해 보류 상태를 저장함")
        else {
            if (IsSet(gEarnHeld) && IsObject(gEarnHeld))
                gEarnHeld[id] := reason
            EarnLog("원장: " id " 거래의 pending 누락과 보류 상태 저장 실패. 거래를 재요청하지 말고 결과 확인 필요")
        }
        return false
    }
    if (!EarnLedgerRecord(direction, amount, id, source, evidence, path)) {
        EarnLog("원장: " id " 기록 실패. pending 상태를 유지해 거래 재요청을 막음")
        return false
    }
    EarnTransactionConfirmed(id)
    if (EarnStateGet("pending_" id) != "") {
        EarnLog("원장: " id " 행은 기록했지만 pending 정리를 확인하지 못함. 거래 재요청 금지")
        return false
    }
    return true
}

; 작업이 화면에서 읽은 상태로 다음 확인까지의 시간을 정한다. 작업이 성공으로 끝날 때만 스케줄러가 이 값을 쓴다.
EarnScheduleNext(id, ms) {
    global gEarnNextDue
    if (ms > 0 && IsSet(gEarnNextDue))
        gEarnNextDue[id] := A_TickCount + ms
    return true
}

; 전체 멈춤(End) 또는 GTA 가 앞이 아님
; 길찾기·재접속처럼 위험하지 않은 실패: 스케줄러를 끄지 않고 retryMin 분 뒤에 같은 작업을 다시 하게 한다 (캐릭터는 그 자리에 서 있을 뿐이다)
EarnSoftFail(reason, retryMin) {
    global gEarnRetryIn
    gEarnRetryIn := retryMin * 60000
    return EarnFail(reason)
}

; 전체 멈춤(End)·GTA 가 앞이 아님·스케줄러가 꺼짐(F9 두 번). 시험 스크립트(earntest.ahk)는 gEarnOn 이 없어 IsSet 으로 본다
EarnAborted() {
    global gAbort, gEarnOn, gEarnInputGuard, gEarnAFKCleanup, gEarnManualCleanupActive
    if (IsSet(gEarnInputGuard) && !gEarnInputGuard.Call())
        return true
    ; AFK 방지의 MCT 정리는 스케줄러가 꺼져 있어도 돈다(꺼진 채 MCT 화면에 방치되는 것이 그 정리가 막을 사고다).
    return gAbort || !IsGTAActive() || (IsSet(gEarnOn) && !gEarnOn
        && !(IsSet(gEarnAFKCleanup) && gEarnAFKCleanup)
        && !(IsSet(gEarnManualCleanupActive) && gEarnManualCleanupActive))
}

; name 템플릿(Images\Earn\<해상도>\<name>.png)이 area(클라이언트 비율 [x1, y1, x2, y2]) 안에 보이면 true. 찾은 자리(화면 좌표)는 &fx, &fy.
EarnSeen(name, area := "", &fx := 0, &fy := 0, variation := 40) {
    ; 1015 12:33 배송 확인 뒤 녹화의 벙커 로고 차이는 76이었다. 확인창·DJ·MCT는 같은 영역에서 217 이상이다.
    if (name = "bunker_page")
        variation := Max(variation, 80)
    ; 1015 데스크톱 실측: 재고용 버튼이 40에서 실패하고 55에서 일치했다.
    if (name = "dj_rebook_10k" || name = "dj_rebook_10k_right")
        variation := Max(variation, 55)
    ; 1015 13:59 GDI에서 직원2·4·5는 밝기 사본도55에서 실패하고65에서 일치했다.
    if (RegExMatch(name, "^warehouse_staff_[1-5]$"))
        variation := Max(variation, 65)
    ; 실제 밝은 전화 홈의 제목 변형. 다른 메뉴의 허용 오차를 넓히지 않는다.
    if (name = "ph_joblist_sel" || name = "ph_vinewood_sel")
        return TemplateSeen("Earn", name, area, &fx, &fy, Max(variation, 70))
            || TemplateSeen("Earn", name "_live", area, &fx, &fy, name = "ph_joblist_sel" ? Max(variation, 50) : variation)
    ; 저택 MCT는 'Press ... to access' 대신 메뉴형 안내를 표시한다.
    ; 템플릿이 흰 글자만 보므로 밝은 하늘 위에서는 아무 데나 맞는다(1003 23:44 실측: 선 채 하늘을 볼 때 앉은 안내로 오판해
    ; Enter 만 보내다 멈춤, 녹화 프레임에서 1,500자리 넘게 일치). 맞은 자리의 글자 밖 바탕이 안내 상자처럼 어두워야 인정한다.
    if (name = "mct_seated") {
        ; 저택 안내 글자는 같은 자리에서도 차이 55 까지 벌어진다(1010 00:44 실측: 앉아서 안내가 떠 있는데 40 으로 못 찾아 정리 실패가 반복됨).
        ; 같은 원점의 바탕을 함께 확인한다. 저택 반투명 바탕은 천장 조명선이 겹친 실제 GDI에서 차이 107이었다(1015 13:38).
        for part in ["mct_seated_mansion", "mct_seated"]
            if (TemplateSeen("Earn", part, area, &fx, &fy, part = "mct_seated_mansion" ? Max(variation, 60) : variation) && TemplateAt("Earn", part "_bg", fx, fy, part = "mct_seated_mansion" ? 110 : 90))
                return true
        return (TemplateSeen("Earn", "mct_seated_hdr", area, &fx, &fy, variation)
            && TemplateAt("Earn", "mct_seated_hdr_bg", fx, fy))
            || (!gEarnSkipOcr && EarnMCTSeatedOcrMatches(EarnOcrLines("prompt", [0, 0, 576, 108], false)))
    }
    ; 메뉴 제목 배너는 반투명이라 뒤 풍경이 밝은 낮에는 같은 자리에서도 차이가 80 까지 벌어진다(1010 04:35 실측: 메뉴가 열려 있는데
    ; 40 으로 못 찾아 사장 해제가 '메뉴가 열리지 않음'으로 반복 실패, 85 에서는 같은 자리 36,120 에서 맞음).
    if (name = "m_title")
        return TemplateSeen("Earn", name, area, &fx, &fy, Max(variation, 85))
    if (name = "mct_title")
        return TemplateSeen("Earn", "mct_title", area, &fx, &fy, variation)
            || (TemplateSeen("Earn", "mct_title_hdr", area, &fx, &fy, Max(variation, 55))
            && TemplateAt("Earn", "mct_title_hdr_bg", fx, fy))
            || (!gEarnSkipOcr && EarnMCTTitleOcrMatches(EarnOcrLines("title", [576, 0, 768, 108], false)))
    ; "Press E to sit down" 도 같은 흰 글자 템플릿이라 밝은 벽 앞에서 맞는다(1005 22:55 길가에서 MC 판매를 돕던 중 글자 차이 30~33 으로
    ; 맞아 E 를 누르고 앉기를 기다리다 꺼짐. 그때 글자 밖 바탕 밝기 231, 진짜 안내는 7). 바탕이 어두워야 인정한다.
    if (name = "mct_sit")
        return (TemplateSeen("Earn", "mct_sit", area, &fx, &fy, variation) && TemplateAt("Earn", "mct_sit_bg", fx, fy))
            || (TemplateSeen("Earn", "mct_sit_hdr", area, &fx, &fy, variation) && TemplateAt("Earn", "mct_sit_hdr_bg", fx, fy))
            || (TemplateSeen("Earn", "mct_sit_hdr_alt", area, &fx, &fy, variation) && TemplateAt("Earn", "mct_sit_hdr_alt_bg", fx, fy))
            || (TemplateSeen("Earn", "mct_sit_hdr_bright", area, &fx, &fy, variation) && TemplateAt("Earn", "mct_sit_hdr_bright_bg", fx, fy))
            || (TemplateSeen("Earn", "mct_sit_hdr_box", area, &fx, &fy, variation) && TemplateAt("Earn", "mct_sit_hdr_box_bg", fx, fy, 40))
            || (!gEarnSkipOcr && EarnMCTSitOcrSeen())
    ; 테러바이트 안내는 CEO 여부에 따라 두 모양이다. CEO 일 때는 'Touchscreen computer / Master Control Terminal'.
    ; 반투명 상자라 뒤 배경에 따라 픽셀이 바뀌고, 남은 커서가 한 줄을 가릴 수 있다(1003 17:15 실측).
    ; 그래서 세 줄 중 하나만 맞아도 인정하고 허용 오차를 60으로 둔다.
    if (name = "mct_terrorbyte") {
        for part in ["mct_terrorbyte", "mct_terrorbyte_reg", "mct_terrorbyte_ceo"]
            if (TemplateSeen("Earn", part, IsObject(area) ? area : [0,0,0.3,0.25], &fx, &fy, Max(variation, 60)))
                return true
        ; 1016 GDI 두 시점에서 원본 Access 줄은 배경 차이 63/67로 실패했다.
        return (TemplateSeen("Earn", "mct_terrorbyte_access_native", IsObject(area) ? area : [0,0,0.3,0.25], &fx, &fy, 40)
            && TemplateAt("Earn", "mct_terrorbyte_access_native_bg", fx, fy, 60))
            || (TemplateSeen("Earn", "mct_terrorbyte_ceo_native", IsObject(area) ? area : [0,0,0.3,0.25], &fx, &fy, 40)
            && TemplateAt("Earn", "mct_terrorbyte_ceo_native_bg", fx, fy, 60))
    }
    ; 보스 메뉴는 작텔과 같은 검증된 템플릿을 공유한다.
    static bossNames := Map("m_boss",1,"m_boss_sel",1,"m_ceo_sel",1,"m_start_org_sel",1,
        "m_securo",1,"m_securo_sel",1,"m_retire_sel",1,"m_sub_boss",1,"m_sub_securo",1)
    if (bossNames.Has(name))
        ; 메뉴 패널은 반투명이라 뒤 풍경이 밝은 낮에는 같은 자리에서도 차이가 80 쯤 벌어진다(1010 04:42 실측: m_securo_sel 이 40 에서는
        ; 안 맞고 80 에서 같은 자리 37,123 에 맞음). 줄마다 글자가 달라 허용치를 넓혀도 서로 섞이지 않는다.
        return TemplateSeen("JobWarp", name, area, &fx, &fy, Max(variation, 85))
    ; MCT 웹 화면의 고정 위치만 검색한다. 투명 글자 템플릿의 전체 화면 검색은 매우 느리다.
    static mctAreas := Map(
        "mct_need_ceo", [0,0,0.3,0.1],
        "mct_terrorbyte", [0,0,0.3,0.25],
        "mct_bunker_card", [0.42,0.20,0.58,0.25],
        "mct_nightclub_card", [0.23,0.20,0.32,0.25],
        "bunker_page", [0.15,0.01,0.35,0.12],
        "bunker_entry", [0.42,0.56,0.56,0.62],
        "bunker_resupply", [0.16,0.43,0.25,0.49],
        "bunker_buy", [0.41,0.70,0.51,0.75],
        "bunker_confirm", [0.36,0.42,0.64,0.47],
        "bunker_pending", [0.35,0.43,0.65,0.49],
        "nc_dj_menu", [0.16,0.68,0.26,0.73],
        "nc_home", [0.16,0.53,0.23,0.58],
        "dj_solomun", [0.45,0.22,0.54,0.27],
        "dj_confirm_solomun", [0.30,0.46,0.69,0.53],
        "dj_confirm_tale", [0.30,0.46,0.70,0.53])
    if (!IsObject(area) && mctAreas.Has(name))
        area := mctAreas[name]
    if (name = "mct_need_ceo")
        return TemplateSeen("Earn", name, area, &fx, &fy, variation)
            || (!gEarnSkipOcr && EarnMCTNeedCeoOcrMatches(EarnOcrLines("prompt", [0, 0, 576, 108], false)))
    ; HDR 카드 제목은 글자 내부와 같은 자리의 바탕을 함께 확인한다.
    if (name = "mct_bunker_card" || name = "mct_nightclub_card")
        return TemplateSeen("Earn", name, area, &fx, &fy, variation)
            || (TemplateSeen("Earn", name "_hdr", area, &fx, &fy, variation)
            && TemplateAt("Earn", name "_hdr_bg", fx, fy, 40))
    ; 구매 버튼 글자는 가격과 함께 가운데 정렬이라 보급 칸 수에 따라 1~2px 씩 밀리고 글자 가장자리가 달라진다.
    ; 1004 03:20 실측: $60,000 에서 8초 동안 버튼이 보였는데 오차 40으로는 못 찾았다. 다른 화면은 이 자리에서 오차 226 이상이다.
    if (name = "bunker_buy")
        variation := Max(variation, 100)
    ; 통화 종료 아이콘은 녹화에서 오차 12여도 실제 데스크톱에서는 55였다(1007 실측).
    ; 이 아이콘만 60으로 허용한다. 전화 없는 같은 영역은 오차 178로 구분된다.
    if (name = "phone_call_end") {
        ; 21:22 실제 화면의 28x12 아이콘은 기존 26x11 템플릿과 형태도 달랐다.
        ; 전체 허용치를 더 올리지 않고 별도 실측 변형을 기본 오차로 확인한다.
        return TemplateSeen("Earn", name, area, &fx, &fy, Max(variation, 60))
            || TemplateSeen("Earn", "phone_call_end_live", area, &fx, &fy, variation)
    }
    ; MCT·나이트클럽 웹 화면은 고정 위치의 평평한 그림이라 허용치를 60 으로 넓혀도 다른 화면과 섞이지 않는다(차이 130 이상).
    ; 창 모드·캡처 압축으로 글자 가장자리 몇 픽셀이 40 을 살짝 넘는다(1010 04:50 실측: dj_solomun 607픽셀 중 2개가 42 차이로 40 에서만 실패).
    if (mctAreas.Has(name))
        variation := Max(variation, 60)
    return TemplateSeen("Earn", name, area, &fx, &fy, variation)
}

; HDR 실화면에서는 창틀이 반투명 안내의 E 키 문자를 가려 OCR이 "Press"와 "to sit down"으로 나눈다.
; 두 조각의 위치와 문구를 함께 확인하고, 반복 화면 확인에서는 OCR 프로세스를 짧게 제한한다.
EarnMCTSitOcrSeen() {
    static lastRead := 0, lastResult := false
    age := A_TickCount - lastRead
    if (lastRead && age < (lastResult ? 150 : 2200))
        return lastResult
    lastRead := A_TickCount
    lines := EarnReadScreen([0, 0, 576, 108], true)
    lastResult := EarnMCTSitOcrMatches(lines)
    return lastResult
}

; 화면 밝기가 템플릿을 만들 때와 달라지면 흰 글자 템플릿이 통째로 안 맞는다(1010 01:50 실측: 안내 글자의 흰색이
; 템플릿은 205, 화면은 255). 글자 안내는 템플릿이 실패했을 때만 OCR 로 내용을 읽어 밝기와 무관하게 판정한다.
; 같은 영역을 여러 판정이 잇달아 읽으므로 1초 동안 결과를 나눠 쓴다. 한 번 읽는 데 약 1초 걸린다.
EarnOcrLines(key, area, whiteText) {
    static cache := Map()
    if (cache.Has(key) && A_TickCount - cache[key].tick < 1000)
        return cache[key].lines
    lines := EarnReadScreen(area, whiteText)
    cache[key] := {tick: A_TickCount, lines: lines}
    return lines
}

EarnOcrHas(lines, pattern) {
    if (!IsObject(lines))
        return false
    for row in lines
        if (IsObject(row) && row.HasOwnProp("text") && RegExMatch(row.text, pattern))
            return true
    return false
}

; 저택 MCT에 앉으면 'Master Control Terminal / Security Cameras / Stand up' 세 줄이 뜬다.
; 테러바이트 안내에도 'Master Control Terminal' 줄이 있으므로 앉아 있을 때만 있는 'Stand up' 을 함께 본다.
EarnMCTSeatedOcrMatches(lines) {
    return EarnOcrHas(lines, "i)^\W*Master\h+Control\h+Terminal\W*$") && EarnOcrHas(lines, "i)^\W*Stand\h+up\W*$")
}

; 사업장 카드를 고르면 뜨는 CEO 등록 안내. MC 사업장 안내('start a Motorcycle Club')와는 구분한다.
EarnMCTNeedCeoOcrMatches(lines) {
    return EarnOcrHas(lines, "i)You\h+need\h+to\h+be\h+a\h+CEO") && EarnOcrHas(lines, "i)register\h+as\h+a\h+CEO")
}

EarnMCTTitleOcrMatches(lines) {
    return EarnOcrHas(lines, "i)MASTER\W*CONTROL\W*TERMINAL")
}

EarnMCTSitOcrMatches(lines) {
    if (!IsObject(lines))
        return false
    press := false, sit := false, pressY := 0, sitY := 0
    for row in lines {
        if (!IsObject(row) || !row.HasOwnProp("text") || !row.HasOwnProp("x") || !row.HasOwnProp("y"))
            continue
        ; 창틀이 E 키 문자를 가리지 않으면 OCR 이 키 문자만 빼고 한 줄로 읽는다(1010 17:24 저택 MCT 앞 실측:
        ; 'Press to sit down.' 한 줄이라 두 조각 판정이 못 맞아 MCT 작업이 모두 '앞에 서 있지 않음'으로 실패).
        if (row.x < 320 && row.y < 70 && RegExMatch(row.text, "i)^\h*Press\h+(?:E\h+)?to\h+sit\h+down\W*$"))
            return true
        if (row.x < 180 && row.y < 70 && RegExMatch(row.text, "i)^\h*Press\h*$"))
            press := true, pressY := row.y
        else if (row.x >= 80 && row.x < 320 && row.y < 70
            && RegExMatch(row.text, "i)^\h*to\h+sit\h+down[.!]?\h*$"))
            sit := true, sitY := row.y
    }
    return press && sit && Abs(pressY - sitY) <= 16
}
; timeoutMs 안에 name 이 보이면 true. 전체 멈춤·포커스 이탈이면 바로 false.
EarnWaitSeen(name, area, timeoutMs) {
    started := A_TickCount, deadline := started + timeoutMs, reads := 0, lastSeen := "unread"
    Loop {
        if (EarnAborted()) {
            reason := "aborted"
            break
        }
        reads++
        lastSeen := EarnSeen(name, area)
        if (lastSeen)
            return true
        if (A_TickCount >= deadline) {
            reason := "timeout"
            break
        }
        Sleep(200)
    }
    if (name = "dj_resident" || name = "dj_resident_right" || name = "mct_seated") {
        ; 마지막 판독값을 기록한다. 실패 뒤 새 화면을 읽으면 당시 결과와 섞인다.
        areaText := "default"
        if (IsObject(area)) {
            areaText := ""
            for index, value in area
                areaText .= (index = 1 ? "" : ",") Format("{:g}", value)
        }
        try EarnLog("[wait-seen] target=" name " area=" areaText " reason=" reason
            " elapsed_ms=" (A_TickCount - started) " limit_ms=" timeoutMs " reads=" reads " last_seen=" lastSeen
            " dpi_context=" DllCall("GetThreadDpiAwarenessContext", "ptr") " script=" A_ScriptFullPath)
    }
    return false
}

; timeoutMs 안에 name 이 사라지면 true.
EarnWaitGone(name, area, timeoutMs) {
    deadline := A_TickCount + timeoutMs
    Loop {
        if (EarnAborted())
            return false
        if (!EarnSeen(name, area))
            return true
        if (A_TickCount >= deadline)
            return false
        Sleep(200)
    }
}

; 키 하나. 보내기 전에 전체 멈춤·포커스를 보고, 보낸 뒤 EarnKeyDelay 만큼 기다린다.
EarnPress(key) {
    global config
    if (EarnAborted())
        return false
    PressKey(key)
    Sleep(config["Settings"]["EarnKeyDelay"])
    return true
}

; ms 동안 기다리되 전체 멈춤·포커스 이탈이면 false
EarnSleep(ms) {
    deadline := A_TickCount + ms
    while (A_TickCount < deadline) {
        if (EarnAborted())
            return false
        Sleep(Min(100, Max(1, deadline - A_TickCount)))
    }
    return true
}

; key 를 한 번씩 누르며 name(선택된 줄 템플릿)이 보일 때까지 최대 maxPress 번. 처음부터 보이면 누르지 않는다.
; 메뉴에 들어간 직후 첫 키가 씹히는 일이 잦아(0926 실측) 몇 번 눌렀는지가 아니라 화면으로 판정한다.
EarnSelectRow(name, area, key, maxPress) {
    if (EarnSeen(name, area))
        return true
    Loop maxPress {
        if (!EarnMenuIsOpen())
            return EarnFail("선택 이동: 상호작용 메뉴 제목을 확인하지 못함")
        if (!EarnPress(key))
            return false
        if (EarnSeen(name, area))
            return true
    }
    return false
}

; === 상호작용 메뉴 ===
; 제목 줄 템플릿: m_title = "INTERACTION MENU", m_pref_title = "PREFERENCES"
EarnMenuIsOpen() {
    global EARN_MENU_AREA
    return EarnSeen("m_title", EARN_MENU_AREA) || EarnSeen("m_pref_title", EARN_MENU_AREA)
        || EarnSeen("m_sub_boss", EARN_MENU_AREA) || EarnSeen("m_sub_securo", EARN_MENU_AREA)
}

EarnMenuOpen() {
    global EARN_MENU_AREA
    if (EarnSeen("m_title", EARN_MENU_AREA))
        return true
    if (EarnMenuIsOpen())
        return false          ; 하위 메뉴에 들어가 있는 상태는 모른 채 이어 가지 않는다
    if (!EarnHudVisible())
        return EarnFail("상호작용 메뉴: 게임 HUD를 확인하지 못함")
    if (!EarnPress("m"))
        return false
    return EarnWaitSeen("m_title", EARN_MENU_AREA, 2500)
}

; 열려 있으면 M 으로 닫고 닫혔는지 본다. 하위 메뉴에서도 M 한 번에 전체가 닫힌다.
EarnMenuClose() {
    ; GTA 가 앞이 아니면 메뉴가 안 보이는 것은 닫혔다는 뜻이 아니다. M 도 다른 창으로 간다.
    ; 닫힌 것으로 돌려주자 메뉴가 열린 채 남아 모든 작업이 막혔다(1023 12:33:51). 다음 작업 시작이 다시 보고 닫는다.
    if (!IsGTAActive())
        return false
    ; 다시 그려지는 동안 잠깐 접힌 메뉴를 닫힌 것으로 보지 않게 0.6초 뒤 한 번 더 본다(1004 18:11 녹화).
    if (!EarnMenuIsOpen()) {
        Sleep(600)
        if (!EarnMenuIsOpen())
            return IsGTAActive() ? true : false   ; 읽는 사이 포커스를 잃었으면 닫힘을 확인한 것이 아니다
    }
    if (!EarnPress("m"))
        return false
    deadline := A_TickCount + 2500
    while (A_TickCount < deadline) {
        if (!EarnMenuIsOpen())
            return IsGTAActive() ? true : false
        Sleep(150)
    }
    return false
}

; 중단으로 남은 상호작용 메뉴가 MCT 안내와 전화 화면을 가리면 위치 확인·HUD 확인이 끝없이 실패한다(1023 12:33~13:10).
; 작업을 시작하기 전에 메뉴가 보이면 M 으로 닫는다. GTA 가 앞이 아니면 아무것도 하지 않고 작업 쪽 중단 판정에 맡긴다.
EarnCloseLeftoverMenu() {
    if (!IsGTAActive() || !EarnMenuIsOpen())
        return true
    EarnLog("남은 상호작용 메뉴를 M 으로 닫음")
    if (EarnMenuClose())
        return true
    ; 바로 다시 하면 매 틱 M 이 들어가 메뉴가 열렸다 닫혔다 한다. MCT 위치 미확인처럼 30초 뒤 다시 본다.
    return EarnSoftFail("남은 상호작용 메뉴를 닫지 못함", 0.5)
}

; 상호작용 메뉴 → Preferences → Spawn Location 을 place 로 바꾼다. place 는 템플릿 이름 뒷부분(spawn_<place>).
; 값은 dir(Left/Right) 로 한 칸씩 넘기며 화면의 값 글자를 확인한다. 목록은 약 35개이고 한 방향으로 45번이면 한 바퀴를 넘는다.
EarnSetSpawn(place, dir := "Left") {
    global EARN_MENU_AREA
    ok := false
    try {
        if (!EarnMenuOpen())
            return EarnFail("스폰 변경: 상호작용 메뉴가 열리지 않음")
        if (!EarnSelectRow("m_pref_sel", EARN_MENU_AREA, "Up", 18))
            return EarnFail("스폰 변경: Preferences 줄을 찾지 못함")
        if (!EarnPress("Enter"))
            return false
        if (!EarnWaitSeen("m_pref_title", EARN_MENU_AREA, 2500))
            return EarnFail("스폰 변경: Preferences 하위 메뉴가 안 열림")
        if (!EarnSelectRow("m_spawn_sel", EARN_MENU_AREA, "Up", 10))
            return EarnFail("스폰 변경: Spawn Location 줄을 찾지 못함")
        if (!EarnSelectRow("spawn_" place, EARN_MENU_AREA, dir, 45))
            return EarnFail("스폰 변경: 값 " place " 을(를) 찾지 못함")
        ok := true
        EarnLog("스폰 위치 = " place)
    } finally {
        if (!EarnMenuClose() && ok)
            ok := EarnFail("스폰 변경: 메뉴가 닫히지 않음")
    }
    return ok
}

; === 세션 재접속과 도착 확인 ===
; 초대 전용 세션으로 다시 들어가면(세션 이동 매크로) 로딩 한 번에 스폰 위치의 부동산 안에서 시작한다.
; 도착 판정: 체력 막대(화면 왼쪽 아래 초록)가 두 번 연달아 보이면 상호작용 메뉴를 열어 맨 윗줄 "<부동산> Management" 를 확인한다.
EarnReloadInto(place, dir := "Left") {
    if (!EarnSetSpawn(place, dir))
        return false
    if (!EarnSleep(800))
        return false
    EarnLog("세션 재접속 시작 → " place)
    return EarnRejoin(place)
}
; 상호작용 메뉴 맨 윗줄로 지금 있는 부동산을 확인한다. 선택 여부에 따라 줄 바탕이 달라 두 템플릿(_sel / 없음)을 본다.
EarnCheckPlace(place) {
    global EARN_MENU_AREA
    if (!EarnMenuOpen())
        return EarnFail("위치 확인: 상호작용 메뉴가 열리지 않음")
    here := EarnSeen("mgmt_" place, EARN_MENU_AREA) || EarnSeen("mgmt_" place "_sel", EARN_MENU_AREA)
    if (!EarnMenuClose())
        return EarnFail("위치 확인: 메뉴가 닫히지 않음")
    if (!here)
        return EarnFail("위치 확인: " place " 안이 아님 (메뉴 맨 윗줄 불일치)")
    EarnLog("도착 확인: " place)
    return true
}

; 체력 막대(왼쪽 아래 미니맵 밑 초록 막대)가 보이면 true. 로딩 화면·일시정지 메뉴·전화기 화면에서는 안 보인다.
EarnHudVisible() {
    hwnd := IsGTAActive()
    if (!hwnd)
        return false
    WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
    CoordMode("Pixel", "Screen")
    ; 화면이 템플릿보다 밝으면(1010 실측 약 1.55배) 체력 막대 색도 같은 배율로 밝아진다. 밝기 사본 배율로 함께 찾는다.
    for color in EarnHudGreens()
        if (PixelSearch(&fx, &fy, cx + Round(cw * EARN_HUD_BAR[1]), cy + Round(ch * EARN_HUD_BAR[2]),
            cx + Round(cw * EARN_HUD_BAR[3]), cy + Round(ch * EARN_HUD_BAR[4]), color, 30))
            return true
    ; HDR 톤 매핑은 채널마다 배율이 달라 막대가 5AC854 처럼 나오기도 한다(1010 04:41 실측: 원색 4C8F4C 와 단일 배율로 못 맞춤).
    ; 색이 안 맞으면 체력 막대 모양 판정으로 한 번 더 본다.
    return HealthHudVisible()
}

EarnHudGreens() {
    global gTemplateGains
    colors := [EARN_HUD_GREEN]
    if (IsSet(gTemplateGains) && gTemplateGains is Array)
        for gain in gTemplateGains {
            r := Min(255, Round(((EARN_HUD_GREEN >> 16) & 255) * gain))
            g := Min(255, Round(((EARN_HUD_GREEN >> 8) & 255) * gain))
            b := Min(255, Round((EARN_HUD_GREEN & 255) * gain))
            colors.Push((r << 16) | (g << 8) | b)
        }
    return colors
}

; "w:1800,d:600" 처럼 적은 순서대로 키를 누르고 있다가 뗀다. 이동 중에도 전체 멈춤·포커스를 본다.
EarnWalk(path) {
    for step in StrSplit(path, ",", " `t") {
        if (step = "")
            continue
        parts := StrSplit(step, ":")
        key := parts[1], ms := parts.Length > 1 ? Integer(parts[2]) : 300
        if (EarnAborted())
            return false
        if (!EarnHudVisible())
            return EarnFail("걷기: 게임 HUD를 확인하지 못함")
        if (MacroKeyPhysicallyHeld(key))
            return false
        Send("{Blind}{" key " down}")
        try ok := EarnSleep(ms)
        finally ReleaseMacroKey(key)
        if (!ok)
            return false
        Sleep(250)
    }
    return true
}
; === 미니맵 길찾기 ===
; 미니맵은 카메라 방향이 위다. 블립(아이콘)을 색 덩어리로 찾아 플레이어 화살표 기준 각도(0=정면, +=오른쪽)·거리(px)를 낸다.
; 아이콘은 그릴 때마다 가장자리·크기가 1px 씩 달라 템플릿이 안 맞는다(0926 실측: 노트북 화면 6줄/7줄). safe = 빨간 $ 덩어리,
; laptop = 흰 화면 덩어리 높이 5~7줄(사무실·기획실 노트북), mct = 높이 8~10줄(마스터 컨트롤 터미널 모니터). 테두리 12px 안쪽만 보고 화살표 둘레 10px 은 뺀다.
; W 는 카메라 방향으로 걷기 때문에 "블립을 각도 a 에 두고 W" = 블립 기준으로 정한 방향으로 걷기다. 부동산 안의 고정 블립(사무실 노트북·금고·MCT)을 기준으로 쓴다.
; 1920x1080 에서 미니맵은 (20, 860) 290x190, 화살표 가운데는 (164, 1005) (0926 실측).
global EARN_MINIMAP := [20, 860, 310, 1050]
global EARN_ARROW := [164, 1005]

EarnBlip(name, &ang, &dist) {
    global EARN_MINIMAP, EARN_ARROW
    ang := 0, dist := 0
    hwnd := IsGTAActive()
    if (!hwnd)
        return false
    prev := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
    } finally {
        if (prev)
            DllCall("SetThreadDpiAwarenessContext", "ptr", prev, "ptr")
    }
    sx := cw / 1920, sy := ch / 1080
    mx := cx + Round(EARN_MINIMAP[1] * sx), my := cy + Round(EARN_MINIMAP[2] * sy)
    w := Round((EARN_MINIMAP[3] - EARN_MINIMAP[1]) * sx), h := Round((EARN_MINIMAP[4] - EARN_MINIMAP[2]) * sy)
    buf := EarnGrab(mx, my, w, h)
    return EarnBlipFromPixels(name, buf, w, h, sx, sy, &ang, &dist)
}

; 화면 캡처와 분리한 픽셀 판독. 저장된 미니맵으로도 같은 검출기를 검사한다.
EarnBlipFromPixels(name, buf, w, h, sx, sy, &ang, &dist) {
    global EARN_MINIMAP, EARN_ARROW
    ang := 0, dist := 0
    ax := (EARN_ARROW[1] - EARN_MINIMAP[1]) * sx, ay := (EARN_ARROW[2] - EARN_MINIMAP[2]) * sy
    ; 테두리 3px 은 뺀다(둥근 모서리·프레임). 아래쪽은 8px: 체력 막대(초록)가 미니맵 바닥 줄에 걸친다(0927 실측)
    margin := Round(3 * sx), bottom := Round((name = "safe" ? 8 : 3) * sy)   ; 초록 판정만 체력 막대에 걸린다
    ; 후보 픽셀 표시
    mark := Buffer(w * h, 0)
    Loop h {
        y := A_Index - 1
        if (y < margin || y >= h - bottom)
            continue
        Loop w {
            x := A_Index - 1
            ; 가까운 MCT 화면도 화살표 옆에 놓인다. 위치 사각형으로 지우지 않고
            ; 아래의 화면 밀도·받침대/터치패드 모양 검사로 화살표를 제외한다.
            if (x < margin || x >= w - margin)
                continue
            off := (y * w + x) * 4
            b := NumGet(buf, off, "uchar"), g := NumGet(buf, off + 1, "uchar"), r := NumGet(buf, off + 2, "uchar")
            if (name = "safe")   ; $ 아이콘은 금고가 가득 차면 빨강(0xDE3030), 아니면 초록(0x72CC72) (0926~0927 실측)
                hit := (r > 150 && g < 90 && b < 90) || (g > 130 && g > r + 40 && g > b + 40)
            else
                hit := r >= 200 && g >= 200 && b >= 200
            if (hit)
                NumPut("uchar", 1, mark, y * w + x)
        }
    }
    ; 덩어리(4방향 연결)마다 테두리 상자를 잰다
    stack := Buffer(w * h * 4)
    best := 0, bestScore := 0
    Loop h {
        y0 := A_Index - 1
        Loop w {
            x0 := A_Index - 1
            if (NumGet(mark, y0 * w + x0, "uchar") != 1)
                continue
            minX := x0, maxX := x0, minY := y0, maxY := y0, n := 0
            NumPut("int", y0 * w + x0, stack, 0)
            sp := 1
            NumPut("uchar", 2, mark, y0 * w + x0)
            while (sp) {
                sp -= 1
                i := NumGet(stack, sp * 4, "int")
                px := Mod(i, w), py := i // w
                n += 1
                minX := Min(minX, px), maxX := Max(maxX, px), minY := Min(minY, py), maxY := Max(maxY, py)
                for d in [[1, 0], [-1, 0], [0, 1], [0, -1]] {
                    nx := px + d[1], ny := py + d[2]
                    if (nx < 0 || ny < 0 || nx >= w || ny >= h)
                        continue
                    if (NumGet(mark, ny * w + nx, "uchar") = 1) {
                        NumPut("uchar", 2, mark, ny * w + nx)
                        NumPut("int", ny * w + nx, stack, sp * 4)
                        sp += 1
                    }
                }
            }
            bw := maxX - minX + 1, bh := maxY - minY + 1
            ; 미니맵 범위 밖의 아이콘은 가장자리에 붙어 그려진다(잘릴 수 있다). 그때는 방향만 믿고 거리는 모름(999)으로 준다
            atEdge := minX <= 14 || maxX >= w - 15 || minY <= 14 || maxY >= h - 15
            if (name = "safe")
                ok := n >= 12 && bw <= 16 && bh <= 20
            else {
                ; 두 아이콘 모두 화면 높이가 7px일 수 있다. 하단 받침대/키보드 모양으로 구분한다.
                ; 가장자리도 몸체가 온전히 보이면 분류한다. 잘려서 구분할 수 없으면 쓰지 않는다.
                ok := bw >= Round(9 * sx) && bw <= Round(14 * sx)
                    && bh >= Round(5 * sy) && bh <= Round(10 * sy) && n >= bw * bh * 0.8
                    && EarnComputerBlipKind(buf, w, h, minX, maxX, maxY, sx, sy) = name
            }
            ; 안쪽에 온전한 아이콘이 있으면 그것을, 없으면 가장자리 것을 쓴다
            score := n + (atEdge ? 0 : 10000)
            if (ok && score > bestScore) {
                bestScore := score
                best := [(minX + maxX) / 2, (minY + maxY) / 2, atEdge]
            }
        }
    }
    if (!IsObject(best))
        return false
    dx := best[1] - ax, dy := best[2] - ay
    ang := ATan2Deg(dx, -dy)
    dist := best[3] ? 999 : Sqrt(dx * dx + dy * dy)
    return true
}

; 흰 화면 아래 MCT는 좁은 목과 양옆 빈틈, 노트북은 넓은 몸체와 흰 터치패드가 있다.
; 검은 윤곽과 밝은 빈틈을 둘 다 확인해 모양이 불명확하면 빈 문자열로 돌려준다.
EarnComputerBlipKind(buf, w, h, left, right, bottom, sx, sy) {
    center := Round((left + right) / 2)
    ; 아이콘 전체 폭의 경계를 확보한다. 잘린 화면도 폭 조건을 통과할 수 있다.
    if (center - Round(12 * sx) < 0 || center + Round(12 * sx) >= w
        || bottom + Round(8 * sy) >= h)
        return ""
    neck := 0, body := 0, pad := 0
    Loop 4 {
        row := A_Index + 1
        y := bottom + Round(row * sy)
        ; 화면 중심은 반 픽셀에 놓일 수 있다. 목 가장자리의 안티앨리어싱 1px은 허용하되
        ; 가운데 다섯 픽셀 중 네 개와 양쪽 밝은 빈틈을 함께 요구한다.
        darkCenterPixels := 0, darkCenterTotal := 0
        for dx in [-2, -1, 0, 1, 2] {
            level := EarnBlipPixelLevel(buf, w, center + Round(dx * sx), y, false)
            if (level < 70)
                darkCenterPixels += 1, darkCenterTotal += level
        }
        ; 근접 화면의 반투명 지도에서는 양옆 틈이 54~94까지 어두워진다.
        ; 고정 밝기 대신 검은 목보다 충분히 밝은지 확인한다. 노트북의 넓은 검은 몸체는 통과하지 않는다.
        sideMinimum := Max(45, (darkCenterPixels ? darkCenterTotal / darkCenterPixels : 70) + 40)
        sidesLight := EarnBlipPixelLevel(buf, w, center - Round(5 * sx), y, true) >= sideMinimum
            && EarnBlipPixelLevel(buf, w, center + Round(5 * sx), y, true) >= sideMinimum
        if (darkCenterPixels >= 4 && sidesLight)
            neck += 1
        if (row <= 4 && EarnBlipPixelLevel(buf, w, center - Round(5 * sx), y, false) < 70
            && EarnBlipPixelLevel(buf, w, center + Round(5 * sx), y, false) < 70)
            body += 1
    }
    Loop 4 {
        y := bottom + Round((A_Index + 3) * sy)
        bright := 0
        for dx in [-1, 0, 1]
            bright += EarnBlipPixelLevel(buf, w, center + Round(dx * sx), y, true) >= 180 ? 1 : 0
        if (bright >= 2)
            pad += 1
    }
    if (neck >= 2 && body < 2)
        return "mct"
    if (!neck && body >= 2 && pad >= 1)
        return "laptop"
    return ""
}

EarnBlipPixelLevel(buf, w, x, y, minimum) {
    off := (y * w + x) * 4
    b := NumGet(buf, off, "uchar"), g := NumGet(buf, off + 1, "uchar"), r := NumGet(buf, off + 2, "uchar")
    return minimum ? Min(r, g, b) : Max(r, g, b)
}

ATan2Deg(x, y) {
    ; atan2(x, y) 을 도로 (y 가 위쪽 양수). AHK 에는 ATan2 가 없다
    if (y > 0)
        a := ATan(x / y)
    else if (y < 0)
        a := ATan(x / y) + (x >= 0 ? 3.14159265 : -3.14159265)
    else
        a := x > 0 ? 1.5707963 : x < 0 ? -1.5707963 : 0
    return a * 180 / 3.14159265
}

; 카메라를 가로로 units 만큼 돌린다(양수 = 오른쪽). GTA 는 원시 입력을 읽으므로 상대 이동이 카메라를 돌린다. 한 번에 크게 움직이면 가속이 붙어 작게 나눠 보낸다.
; 천천히 돌린다: 60단위/10ms(≈200도/초) 이상으로 돌리면 게임이 미니맵을 축소해 아이콘이 가장자리에 붙어 몇 초 동안 위치를 못 읽는다.
; 20단위/15ms(≈46도/초)에서는 그대로다(0927 실측: 20u/15ms 정상, 40u/12ms·60u/10ms 축소). 90도에 약 2초 걸린다
; 돌리는 동안에도 전체 멈춤·포커스를 본다. GTA 가 뒤로 가면 상대 이동이 바탕화면 커서를 날린다
EarnTurn(units, pitchUnits := 0, hdrMCTRecovery := false) {
    global gEarnSkipOcr
    if (EarnAborted())
        return false
    gEarnSkipOcr := hdrMCTRecovery
    try {
        return EarnTurnLoop(units, pitchUnits, hdrMCTRecovery)
    } finally {
        gEarnSkipOcr := false
    }
}

EarnTurnLoop(units, pitchUnits, hdrMCTRecovery) {
    n := Max(1, Round(Max(Abs(units), Abs(pitchUnits)) / 20))
    step := Round(units / n), pitchStep := Round(pitchUnits / n)
    ; 화면 판독 한 번이 밝기 사본·OCR 때문에 수 초 걸린다(1010 03:30 실측: 판독만으로 9초가 지나 거의 돌지 못함).
    ; 제한 시간은 돌리는 시간에만 9초를 주고, 판독에 쓴 시간은 더한다. 전체는 90초를 넘기지 않는다.
    ; 판독 간격도 걸음 수로 잡는다. 시계로 잡으면 판독이 끝나자마자 다음 판독이 돌아 판독 사이에 한 걸음씩만 간다.
    turnStart := A_TickCount, readMs := 0, recoveryDeadline := A_TickCount + 9000, nextHealthCheck := 0
    emittedMoves := 0, goalMs := 0, healthMs := 0, menuMs := 0, terminalMs := 0
    goalCalls := 0, healthCalls := 0, menuCalls := 0, stage := "abort-before-read"
    try {
        Loop n {
            if (EarnAborted())
                return false
            if (hdrMCTRecovery) {
                ; 목표 안내가 보이면 고정 각도를 채우려고 계속 돌지 않는다. 판독 지연도 간격에 포함한다.
                if (Mod(A_Index - 1, 16) = 0 || A_TickCount >= recoveryDeadline) {
                    readStart := A_TickCount
                    stage := "goal"
                    arrived := EarnMCTRecoveryArrived()
                    duration := A_TickCount - readStart
                    goalCalls++, goalMs += duration, readMs += duration
                    recoveryDeadline := turnStart + Min(90000, 9000 + readMs)
                    if (EarnAborted())
                        return false
                    if (arrived)
                        return true
                }
                if (A_TickCount >= recoveryDeadline)
                    return EarnFail("MCT 복귀 회전: 9초 제한 초과")
                ; 16개 PixelGetColor 판독도 실측 109~125ms다. 최근 판독은 250ms 동안 재사용한다.
                if (A_TickCount >= nextHealthCheck) {
                    readStart := A_TickCount
                    stage := "health"
                    healthOK := HealthHudVisible()
                    duration := A_TickCount - readStart
                    healthCalls++, healthMs += duration, readMs += duration
                    recoveryDeadline := turnStart + Min(90000, 9000 + readMs)
                    if (!healthOK)
                        return EarnFail("카메라: 게임 HUD를 확인하지 못함")
                    nextHealthCheck := A_TickCount + 250
                }
                ; HDR 판독 실측은 전체 배치 약 1초다. 매 이동 조각마다 반복하지 않는다.
                if (Mod(A_Index - 1, 90) = 0) {
                    readStart := A_TickCount
                    stage := "menu"
                    hudOK := EarnMCTRecoveryHud()
                    duration := A_TickCount - readStart
                    menuCalls++, menuMs += duration, readMs += duration
                    recoveryDeadline := turnStart + Min(90000, 9000 + readMs)
                    if (!hudOK)
                        return EarnFail("MCT 복귀 회전: 메뉴 없는 게임 HUD 미확인")
                }
                ; 메뉴 판독 중 오래된 HUD 판독은 움직이기 전에 갱신한다.
                if (A_TickCount >= nextHealthCheck) {
                    readStart := A_TickCount
                    stage := "health"
                    healthOK := HealthHudVisible()
                    duration := A_TickCount - readStart
                    healthCalls++, healthMs += duration, readMs += duration
                    recoveryDeadline := turnStart + Min(90000, 9000 + readMs)
                    if (!healthOK)
                        return EarnFail("카메라: 게임 HUD를 확인하지 못함")
                    nextHealthCheck := A_TickCount + 250
                }
                ; 느린 판독 중 들어온 사용자 입력·포커스 이탈과 시간 초과를 입력 전에 다시 확인한다.
                if (EarnAborted())
                    return false
                if (A_TickCount >= recoveryDeadline) {
                    ; 느린 메뉴 판독 중 제한에 닿아도 이미 도달한 목표를 실패로 덮지 않는다.
                    stage := "terminal-goal"
                    terminalStart := A_TickCount
                    arrived := EarnMCTRecoveryArrived()
                    terminalMs := A_TickCount - terminalStart
                    if (EarnAborted())
                        return false
                    return arrived ? true : EarnFail("MCT 복귀 회전: 9초 제한 초과")
                }
            }
            else if (!EarnHudVisible())
                return EarnFail("카메라: 게임 HUD를 확인하지 못함")
            stage := "input"
            DllCall("mouse_event", "uint", 1, "int", step, "int", pitchStep, "uint", 0, "uptr", 0)
            emittedMoves++
            Sleep(15)
            stage := "abort-before-read"
        }
        stage := "completed"
        return true
    } finally {
        if (hdrMCTRecovery) {
            elapsed := A_TickCount - turnStart
            try EarnLog("[mct-turn] stage=" stage " moves=" emittedMoves "/" n
                " requested=" units "," pitchUnits " emitted=" (emittedMoves * step) "," (emittedMoves * pitchStep)
                " elapsed_ms=" elapsed " read_ms=" readMs " goal=" goalCalls ":" goalMs
                " health=" healthCalls ":" healthMs " menu=" menuCalls ":" menuMs
                " terminal_ms=" terminalMs " budget_ms=" (recoveryDeadline - turnStart)
                " budget_kind=" (9000 + readMs >= 90000 ? "total-cap" : "nonread"))
        }
    }
}

EarnMCTRecoveryArrived() {
    global EARN_PROMPT_AREA
    ; 기존 안내 글자+어두운 배경 검증과 메뉴 없는 HUD 조건을 모두 유지한다.
    return EarnSeen("mct_sit", EARN_PROMPT_AREA) && EarnMCTRecoveryHud()
}

; MCT에서 일어선 뒤 제자리 복귀 회전만 HDR 체력 막대 판정을 사용한다.
; 전화·앱·상호작용 메뉴·터미널이 보이면 체력 막대가 있어도 회전하지 않는다.
EarnMCTRecoveryHud() {
    global EARN_PROMPT_AREA
    if (!HealthHudVisible() || EarnMenuIsOpen())
        return false
    for name in ["afk_phone_frame", "ph_joblist_sel", "ph_vinewood_sel"]
        if (EarnSeen(name, [0.83,0.58,0.98,0.73]))
            return false
    ; Vinewood 제목 템플릿은 허용치 40 에서 'Press E to sit down' 상자에도 맞는다(1010 04:38 실측, 같은 자리 0,57). 실제 제목은 훨씬 가깝다.
    return !EarnSeen("afk_vinewood_title", [0,0,0.27,0.2], &vx, &vy, 15)
        && !EarnSeen("mct_title", [0.3,0,0.7,0.1])
        && !EarnSeen("mct_seated", EARN_PROMPT_AREA)
}

; 블립이 target 각도(±tol)에 올 때까지 카메라를 돌린다. 못 찾거나 maxIter 번 안에 못 맞추면 false.
EarnFace(name, target := 0, tol := 5, maxIter := 8) {
    global config
    k := config["Settings"]["EarnTurnUnitsPerDeg"]
    previousAngle := 0, previousUnits := 0
    Loop maxIter {
        if (EarnAborted())
            return false
        seen := false
        Loop 6 {
            if (EarnAborted())
                return false
            if (seen := EarnBlip(name, &a, &d))
                break
            Sleep(200)
        }
        if (!seen) {
            EarnLog("방향 정렬: " name " 블립 재판독 실패")
            return false
        }
        if (previousUnits) {
            turned := Mod(previousAngle - a + 540, 360) - 180
            if (Abs(turned) >= 2 && turned * previousUnits > 0) {
                k := Min(60, Max(8, Abs(previousUnits / turned)))
                config["Settings"]["EarnTurnUnitsPerDeg"] := k
            }
        }
        err := a - target
        if (err > 180)
            err -= 360
        if (err < -180)
            err += 360
        if (Abs(err) <= tol)
            return true
        ; 시점별 마우스 감도가 다르다. 작게 돌린 뒤 실제 블립 각도로 보정한다.
        previousAngle := a
        previousUnits := Round(Max(-45, Min(45, err)) * k)
        if (!EarnTurn(previousUnits))
            return false
        if (!EarnSleep(1300))
            return false
    }
    EarnLog("방향 정렬: " name " 반복 한도, 현재 " Round(a) "도 목표 " Round(target) "도")
    return false
}

; 블립을 향해(각도 target) 한 번에 stepMs 씩 걷는다. 거리가 stopDist 이하가 되거나 prompt 템플릿(왼쪽 위 안내)이 보이면 true.
; 두 번 연달아 거리가 줄지 않으면 막힌 것으로 보고 false (벽에 비비지 않는다).
EarnWalkTo(name, stopDist, prompt := "", stepMs := 600, maxSteps := 12, target := 0) {
    global EARN_PROMPT_AREA
    last := 9999, stuck := 0
    Loop maxSteps {
        if (EarnAborted())
            return false
        if (prompt != "" && EarnSeen(prompt, EARN_PROMPT_AREA))
            return true
        if (!EarnFace(name, target))
            return false
        EarnBlip(name, &a, &d)
        if (d <= stopDist && prompt = "")
            return true
        stuck := d > last - 2 ? stuck + 1 : 0
        if (stuck >= 2)
            return false
        last := d
        if (!EarnWalk("w:" stepMs))
            return false
        Sleep(300)
    }
    return prompt != "" && EarnSeen(prompt, EARN_PROMPT_AREA)
}

; 걷기 경로: "face:laptop:120,w:900,face:laptop:-40,w:700" 처럼 적는다. face 는 블립을 그 각도에 두기, 나머지는 EarnWalk 와 같은 키:ms.
EarnRoute(route) {
    for step in StrSplit(route, ",", " `t") {
        if (step = "")
            continue
        p := StrSplit(step, ":")
        if (p[1] = "face") {
            if (!EarnFace(p[2], p.Length > 2 ? Number(p[3]) : 0))
                return EarnFail("경로: " p[2] " 블립을 " (p.Length > 2 ? p[3] : 0) "도에 맞추지 못함 (" step ")")
        } else if (!EarnWalk(step)) {
            return false
        }
        Sleep(200)
    }
    return true
}
; === 미니맵 지도로 길 찾기 ===
; 실내 미니맵은 지금 층의 바닥이 밝은 회색(밝기 85~145), 벽·다른 층·바깥은 더 어둡다(0926 나이트클럽·아케이드 실측).
; 미니맵을 3px 칸으로 나눠 바닥 칸만 지나는 최단 경로를 찾고(너비 우선 탐색), 경로 위에서 벽에 안 걸리고 곧게 보이는 가장 먼 점을 향해
; 카메라를 돌려 조금 걷는다. 이것을 목표 블립에 닿거나(prompt 안내가 보이거나) 한도에 이를 때까지 되풀이한다.
; 블립이 벽에 붙어 있어도(금고) 닿을 수 있는 바닥 칸 중 블립에 가장 가까운 칸으로 간다. 블립이 미니맵 밖이거나 다른 층이면 false.
global EARN_NAV_CELL := 3

EarnGrab(x, y, w, h) {
    hdc := DllCall("GetDC", "ptr", 0, "ptr")
    mdc := DllCall("CreateCompatibleDC", "ptr", hdc, "ptr")
    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0), NumPut("int", w, bi, 4), NumPut("int", -h, bi, 8), NumPut("ushort", 1, bi, 12), NumPut("ushort", 32, bi, 14)
    bits := 0
    hbm := DllCall("CreateDIBSection", "ptr", mdc, "ptr", bi, "uint", 0, "ptr*", &bits, "ptr", 0, "uint", 0, "ptr")
    old := DllCall("SelectObject", "ptr", mdc, "ptr", hbm, "ptr")
    DllCall("BitBlt", "ptr", mdc, "int", 0, "int", 0, "int", w, "int", h, "ptr", hdc, "int", x, "int", y, "uint", 0x00CC0020)
    buf := Buffer(w * h * 4)
    DllCall("RtlMoveMemory", "ptr", buf, "ptr", bits, "uptr", w * h * 4)
    DllCall("SelectObject", "ptr", mdc, "ptr", old)
    DllCall("DeleteObject", "ptr", hbm)
    DllCall("DeleteDC", "ptr", mdc)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
    return buf
}

; 블립 name 쪽으로 가는 다음 걸음의 각도(도, 0=정면)와 그 점까지 거리(px), 블립까지 남은 거리(px). 길이 없으면 false.
EarnNavPlan(name, &turnAng, &stepPx, &goalPx) {
    global EARN_MINIMAP, EARN_ARROW, EARN_NAV_CELL
    turnAng := 0, stepPx := 0, goalPx := 0
    hwnd := IsGTAActive()
    if (!hwnd)
        return false
    if (!EarnBlip(name, &ba, &bd))
        return false
    prev := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
    } finally {
        if (prev)
            DllCall("SetThreadDpiAwarenessContext", "ptr", prev, "ptr")
    }
    sx := cw / 1920, sy := ch / 1080
    mx := cx + Round(EARN_MINIMAP[1] * sx), my := cy + Round(EARN_MINIMAP[2] * sy)
    w := Round((EARN_MINIMAP[3] - EARN_MINIMAP[1]) * sx), h := Round((EARN_MINIMAP[4] - EARN_MINIMAP[2]) * sy)
    buf := EarnGrab(mx, my, w, h)
    c := EARN_NAV_CELL
    gw := w // c, gh := h // c
    ; 바닥 칸 표시 (1 = 걸을 수 있음). 아이콘(흰색·빨강)은 바닥 위에 그려진 것으로 친다
    raw := Buffer(gw * gh, 0)
    Loop gh {
        gy := A_Index - 1
        Loop gw {
            gx := A_Index - 1
            off := ((gy * c + c // 2) * w + gx * c + c // 2) * 4
            b := NumGet(buf, off, "uchar"), g := NumGet(buf, off + 1, "uchar"), r := NumGet(buf, off + 2, "uchar")
            v := (r + g + b) // 3
            ok := (v >= 85 && v < 150) || v >= 190 || (r > 150 && g < 90 && b < 90)
            NumPut("uchar", ok ? 1 : 0, raw, gy * gw + gx)
        }
    }
    ; 벽에서 한 칸 떨어지게 막힌 칸을 한 칸씩 넓힌다. 화살표 둘레 2칸은 늘 열어 둔다(화살표 테두리가 검다)
    grid := Buffer(gw * gh, 0)
    sgx := Round((EARN_ARROW[1] - EARN_MINIMAP[1]) * sx / c), sgy := Round((EARN_ARROW[2] - EARN_MINIMAP[2]) * sy / c)
    Loop gh {
        gy := A_Index - 1
        Loop gw {
            gx := A_Index - 1
            open := NumGet(raw, gy * gw + gx, "uchar")
            if (open) {
                for d in [[1, 0], [-1, 0], [0, 1], [0, -1]] {
                    nx := gx + d[1], ny := gy + d[2]
                    if (nx >= 0 && ny >= 0 && nx < gw && ny < gh && !NumGet(raw, ny * gw + nx, "uchar")) {
                        open := 0
                        break
                    }
                }
            }
            if (Abs(gx - sgx) <= 2 && Abs(gy - sgy) <= 2)
                open := 1
            NumPut("uchar", open, grid, gy * gw + gx)
        }
    }
    ; 블립 위치(칸)
    rad := ba * 3.14159265 / 180
    ; 가장자리에 붙은 블립(거리 999)은 그 방향으로 미니맵 끝까지를 목표로 삼는다
    reach := Min(bd, Max(w, h) / 2 + 20)
    tgx := sgx + (reach * Sin(rad)) / c, tgy := sgy - (reach * Cos(rad)) / c
    ; 너비 우선 탐색 (8방향)
    n := gw * gh
    par := Buffer(n * 4, 0xFF)   ; -1 = 방문 안 함
    q := Buffer(n * 4)
    start := sgy * gw + sgx
    NumPut("int", start, par, start * 4)
    NumPut("int", start, q, 0)
    head := 0, tail := 1
    best := start, bestD := 1e9
    while (head < tail) {
        cur := NumGet(q, head * 4, "int"), head += 1
        ux := Mod(cur, gw), uy := cur // gw
        dd := (ux - tgx) ** 2 + (uy - tgy) ** 2
        if (dd < bestD)
            bestD := dd, best := cur
        for d in [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]] {
            nx := ux + d[1], ny := uy + d[2]
            if (nx < 0 || ny < 0 || nx >= gw || ny >= gh)
                continue
            ni := ny * gw + nx
            if (!NumGet(grid, ni, "uchar") || NumGet(par, ni * 4, "int") != -1)
                continue
            ; 대각선은 양옆 칸이 둘 다 열려 있을 때만 (벽 모서리를 깎지 않게)
            if (d[1] && d[2] && (!NumGet(grid, uy * gw + nx, "uchar") || !NumGet(grid, ny * gw + ux, "uchar")))
                continue
            NumPut("int", cur, par, ni * 4)
            NumPut("int", ni, q, tail * 4), tail += 1
        }
    }
    goalPx := Sqrt(bestD) * c
    if (best = start) {
        EarnLog("길찾기: 출발 칸에서 더 가까워질 칸이 없음 (블립 " Round(ba) "도 " Round(bd) "px)")
        return false
    }
    ; 경로를 거꾸로 따라가며 출발점에서 곧게 보이는 가장 먼 점을 고른다
    path := []
    cur := best
    while (cur != start) {
        path.InsertAt(1, cur)
        cur := NumGet(par, cur * 4, "int")
    }
    pick := path[1]
    for i, cell in path {
        if (i > 16)
            break
        if (EarnNavLine(grid, gw, sgx, sgy, Mod(cell, gw), cell // gw))
            pick := cell
    }
    dx := (Mod(pick, gw) - sgx) * c, dy := (pick // gw - sgy) * c
    turnAng := ATan2Deg(dx, -dy)
    stepPx := Sqrt(dx * dx + dy * dy)
    return true
}

; 칸 (x0,y0)→(x1,y1) 직선이 열린 칸만 지나면 true
EarnNavLine(grid, gw, x0, y0, x1, y1) {
    steps := Max(Abs(x1 - x0), Abs(y1 - y0))
    if (steps = 0)
        return true
    previousX := x0, previousY := y0
    Loop steps {
        t := A_Index / steps
        x := Round(x0 + (x1 - x0) * t), y := Round(y0 + (y1 - y0) * t)
        if (!NumGet(grid, y * gw + x, "uchar"))
            return false
        ; BFS와 같은 모서리 조건을 지킨다. 지름길도 막힌 칸의 모서리를 가로지를 수 없다.
        if (x != previousX && y != previousY
            && (!NumGet(grid, previousY * gw + x, "uchar") || !NumGet(grid, y * gw + previousX, "uchar")))
            return false
        previousX := x, previousY := y
    }
    return true
}

; 블립 name 까지 미니맵 지도로 걸어간다. prompt(왼쪽 위 안내 템플릿)가 보이면 성공. prompt 가 없으면 블립까지 stopPx 안이면 성공.
; 걸음마다 남은 거리를 보고, 세 번 연달아 줄지 않으면 옆걸음으로 비켜 본 뒤 다시 한다(최대 3번).
EarnNavTo(name, prompt := "", stopPx := 12, maxSteps := 40) {
    global EARN_PROMPT_AREA, config
    k := config["Settings"]["EarnTurnUnitsPerDeg"]
    last := 9999, lastBlipDistance := 9999, flat := 0, dodges := 0
    bestMCTDistance := 9999, stalledMCTSteps := 0
    Loop maxSteps {
        if (EarnAborted())
            return EarnFail("길찾기: 멈춤·포커스 이탈")
        if (prompt != "" && (prompt != "mct_sit" || lastBlipDistance <= 24 || (EarnBlip("mct", &ma, &md) && md <= 24))
            && (EarnSeen(prompt, EARN_PROMPT_AREA)
            || (prompt = "safe_prompt" && EarnSeen("safe_close_prompt", EARN_PROMPT_AREA))))
            return true
        ; 카메라가 돌거나 걷는 동안 미니맵이 다시 그려져(축소·회전 애니메이션) 한두 프레임은 블립이 안 잡힌다(0927 실측). 잠깐 쉬고 몇 번 더 본다
        planned := false
        Loop 8 {
            if (EarnAborted())
                return EarnFail("길찾기: 멈춤·포커스 이탈")
            if (planned := EarnNavPlan(name, &ta, &sp, &gp))
                break
            Sleep(500)
        }
        if (!planned)
            return EarnFail("길찾기: " name " 블립까지 길이 안 보임")
        ; 진척은 블립까지 실제 거리(bd)로 잰다. gp 는 길 끝에서 블립까지 남는 거리라 걷는 동안 줄지 않는다(0927 실측: 26걸음 내내 4~11px)
        if (!EarnBlip(name, &ba, &bd))
            return EarnFail("길찾기: 이동 전 " name " 블립을 확인하지 못함")
        lastBlipDistance := bd
        if (prompt = "" && bd <= stopPx)
            return true
        ; MCT 단상 앞 난간은 미니맵 바닥으로 보일 수 있다. 작은 거리 출렁임을
        ; 진척으로 세어 임의 옆걸음을 반복하지 않고, 네 걸음 정체하면 멈춘다.
        if (name = "mct" && bd < 999) {
            if (bd <= bestMCTDistance - 3)
                bestMCTDistance := bd, stalledMCTSteps := 0
            else if (++stalledMCTSteps >= 4)
                return EarnFail("길찾기: MCT 접근이 네 걸음 동안 진전 없음 (" Round(bd) "px)")
        }
        EarnLog("길찾기 " name ": 걸음 " A_Index " 방향 " Round(ta) "도 " Round(sp) "px, 블립까지 " Round(bd) "px (길 끝 " Round(gp) "px)")
        ; 가장자리에 붙은 블립(거리 999)은 실제 거리를 모르니 길 끝까지 남은 거리(gp)로 진척을 잰다
        prog := bd >= 999 ? gp : bd
        flat := prog > last - 1.5 ? flat + 1 : 0
        last := prog
        if (flat >= 3 && name != "mct") {
            if (dodges >= 3)
                return EarnFail("길찾기: " name " 쪽으로 더 못 감 (블립까지 " Round(bd) "px)")
            dodges += 1, flat := 0
            if (!EarnWalk((Mod(dodges, 2) ? "a" : "d") ":450,s:300"))
                return false
            continue
        }
        if (Abs(ta) > 4 && !EarnFace(name, ba - ta))
            return EarnFail("길찾기: 경로 방향을 확인하지 못함")
        Sleep(250)
        ; 곧게 보이는 점(sp)까지 걷는다. 미니맵 20px ≈ 1초 걷기(0926 실측)이고, 블립 바로 앞에서는 짧게 끊는다
        ms := Round(Min(900, Max(250, Min(sp, Max(bd - stopPx, 6)) * 45)))
        if (!EarnWalk("w:" ms))
            return EarnFail("길찾기: 걷는 중 멈춤")
        Sleep(1300)   ; 걷는 동안 미니맵이 축소됐다가 멈춘 뒤 1초 넘게 걸려 되돌아온다(0927 실측). 그 전에 읽으면 블립이 가장자리에 붙어 안 잡힌다
    }
    if (prompt != "" && (prompt != "mct_sit" || lastBlipDistance <= 24 || (EarnBlip("mct", &ma, &md) && md <= 24))
        && (EarnSeen(prompt, EARN_PROMPT_AREA)
        || (prompt = "safe_prompt" && EarnSeen("safe_close_prompt", EARN_PROMPT_AREA))))
        return true
    return EarnFail("길찾기: " name " 에 " maxSteps "걸음 안에 못 닿음")
}
; === 마스터 컨트롤 터미널(MCT) ===
; 앞에 서면 "Press E to sit down" → E 로 앉으면 "Press Enter to access the Master Control Terminal" → Enter 로 화면이 열린다.
; 화면 안은 마우스 커서로 고른다: 커서를 버튼 위에 두고 Enter(0926 실측: 클릭은 안 먹고 Enter 가 먹는다). 뒤로는 Backspace, 일어서기는 마우스 오른쪽.
EarnMCTOpen() {
    global EARN_PROMPT_AREA, gEarnMCTOpenKind
    if (EarnSeen("mct_title", [0.3, 0, 0.7, 0.1]))
        return DiscordHUDMCTSet(true)
    if (EarnSeen("mct_terrorbyte"))
        return EarnTerrorbyteMCTOpen()
    ; 테러바이트 안에서는 앉을 일이 없다. 이 세션에서 테러바이트로 연 적이 있고 의자 안내도 안 보이면 의자 경로로 가지 않는다.
    ; 의자 경로의 실패 문구("Press E to sit down 안내 없음")가 테러바이트 상황에 찍히면 원인을 오독한다(1023 사용자 지시, test-earntasks 가 지킨다).
    if (IsSet(gEarnMCTOpenKind) && gEarnMCTOpenKind = "terrorbyte"
        && !EarnSeen("mct_sit", EARN_PROMPT_AREA) && !EarnSeen("mct_seated", EARN_PROMPT_AREA))
        return EarnTerrorbyteMCTOpen()
    return EarnChairMCTOpen()
}

EarnTerrorbyteMCTOpen() {
    global gEarnMCTOpenKind
    gEarnMCTOpenKind := "terrorbyte"
    if (!EarnSeen("mct_terrorbyte"))
        return EarnFail("MCT: 테러바이트 접근 안내 미확인 (Space 안내 없음)")
    if (!DiscordHUDMCTSet(true) || !EarnPress("Space"))
        return false
    if (!EarnWaitSeen("mct_title", [0.3,0,0.7,0.1], 8000)) {
        if (!EarnSeen("mct_terrorbyte") || !EarnPress("Space")
            || !EarnWaitSeen("mct_title", [0.3,0,0.7,0.1], 8000))
            return EarnFail("MCT: 테러바이트 화면이 안 열림")
    }
    return EarnSleep(800)
}

EarnChairMCTOpen() {
    global EARN_PROMPT_AREA, gEarnMCTOpenKind
    gEarnMCTOpenKind := "chair"
    if (!EarnSeen("mct_seated", EARN_PROMPT_AREA)) {
        ; CEO 메뉴가 닫힌 직후 접근 안내가 늦게 돌아올 수 있다.
        if (!EarnWaitSeen("mct_sit", EARN_PROMPT_AREA, 8000))
            return EarnFail("MCT: 앞에 서 있지 않음 (Press E to sit down 안내 없음)")
        if (!EarnPress("e"))
            return false
        ; 앉을 때 게임 알림(1003 23:24 실측: unclaimed Career Progress)이 같은 칸을 13초 가린 뒤에야 메뉴가 보였다.
        if (!EarnWaitSeen("mct_seated", EARN_PROMPT_AREA, 20000))
            return EarnFail("MCT: 앉았다는 안내가 안 뜸")
        ; 앉는 동작 중에도 앉은 안내가 먼저 뜬다. 그때 Enter 를 보내면 동작이 끊겨 다시 일어선다(1003 16:47 실측).
        if (!EarnSleep(1500))
            return false
    }
    if (!EarnSeen("mct_seated", EARN_PROMPT_AREA))
        return EarnFail("MCT: 열기 직전 앉은 상태 안내 없음")
    DiscordHUDMCTSet(true)
    if (!EarnPress("Enter"))
        return false
    if (!EarnWaitSeen("mct_title", [0.3, 0, 0.7, 0.1], 8000)) {
        ; 앉는 동작 중 Enter 가 씹히면 앉은 안내만 남는다(1003 16:37 실측). 그때만 한 번 더 보낸다.
        if (!EarnSeen("mct_seated", EARN_PROMPT_AREA) || !EarnPress("Enter")
            || !EarnWaitSeen("mct_title", [0.3, 0, 0.7, 0.1], 8000))
            return EarnFail("MCT: 화면이 안 열림")
    }
    Sleep(800)
    return true
}

; 열린 웹 화면만으로 종류를 추측하지 않는다. 닫힌 뒤 실제 안내로 매번 구분한다.
EarnMCTClose(requireChairPrompt := true, &terminalKind := "") {
    terminalKind := ""
    if (EarnAborted())
        return false
    kind := EarnMCTClosedKind()
    if (kind = "") {
        if (!EarnSeen("mct_title", [0.3,0,0.7,0.1]) && !EarnSeen("mct_need_ceo"))
            return EarnFail("MCT: 닫기 전 터미널 화면을 확인하지 못함")
        if (!EarnPress("Backspace"))
            return false
        kind := EarnMCTWaitClosed()
        if (kind = "")
            return EarnFail("MCT: 닫은 뒤 접근 안내 대기 시간 초과")
    }
    terminalKind := kind
    return kind = "terrorbyte" ? EarnTerrorbyteMCTClose() : EarnChairMCTClose(requireChairPrompt)
}

EarnMCTClosedKind() {
    global EARN_PROMPT_AREA, gEarnMCTOpenKind
    ; 테러바이트로 연 MCT 는 닫은 직후 1~2초 안내가 비는 동안 착석 템플릿이 잘못 맞아 의자 닫기(일어서기)로 갔다(1020 11:52 녹화).
    ; 테러바이트로 열었으면 테러바이트 안내만 기다린다.
    if (IsSet(gEarnMCTOpenKind) && gEarnMCTOpenKind = "terrorbyte")
        return EarnSeen("mct_terrorbyte") ? "terrorbyte" : ""
    ; 테러바이트 안내가 착석 템플릿에도 맞을 수 있어 전용 안내를 먼저 확인한다.
    if (EarnSeen("mct_terrorbyte"))
        return "terrorbyte"
    return EarnSeen("mct_seated", EARN_PROMPT_AREA) ? "chair" : ""
}

EarnMCTWaitClosed() {
    deadline := A_TickCount + 20000
    Loop {
        if (EarnAborted() || A_TickCount >= deadline)
            return ""
        kind := EarnMCTClosedKind()
        if (EarnAborted() || A_TickCount >= deadline)
            return ""
        if (kind != "")
            return kind
        if (!EarnSleep(Min(200, deadline - A_TickCount)))
            return ""
    }
}

EarnTerrorbyteMCTClose() {
    if (EarnAborted())
        return false
    if (EarnSeen("mct_title", [0.3,0,0.7,0.1])) {
        if (!EarnPress("Backspace") || !EarnWaitSeen("mct_terrorbyte", [0,0,0.3,0.25], 20000)
            || EarnAborted())
            return EarnFail("MCT: 테러바이트 닫기 안내 미확인")
    } else if (!EarnSeen("mct_terrorbyte"))
        return EarnFail("MCT: 테러바이트 닫기 전 화면 미확인")
    DiscordHUDMCTSet(false)
    return true
}

EarnTerrorbyteMCTReady() {
    return (EarnWaitSeen("mct_terrorbyte", [0,0,0.3,0.25], 8000) && !EarnAborted())
        || EarnFail("MCT: 테러바이트 접근 안내 미확인")
}

EarnMCTReturnReady(terminalKind) {
    if (EarnAborted())
        return false
    if (terminalKind = "terrorbyte")
        return EarnTerrorbyteMCTReady()
    if (terminalKind = "chair")
        return EarnMCTFindChairPrompt()
    return EarnFail("MCT: 종료 위치 종류 미확인")
}

EarnChairMCTClose(requireChairPrompt := true) {
    global EARN_PROMPT_AREA, config
    if (!EarnSeen("mct_seated", EARN_PROMPT_AREA))
        return EarnFail("MCT: 화면이 닫히지 않음")
    ; 웹 화면은 이미 닫혔다. 일어서기·의자 복귀·CEO 해제 동안은 디코를 다시 표시한다.
    DiscordHUDMCTSet(false)
    if (EarnAborted())
        return false
    Click("Right Down")
    Sleep(120)
    Click("Right Up")
    if (!EarnWaitGone("mct_seated", EARN_PROMPT_AREA, 8000))
        return EarnFail("MCT: 일어서지 못함")
    ; 일어서는 중 잠깐 뜨는 접근 안내로 완료를 판정하면 M 입력이 애니메이션에 씹힌다.
    if (!EarnSleep(3500))
        return false
    if (!EarnWaitCallEnd())
        return false
    ; CEO 해제는 의자에 다시 앉지 않는다. 일어선 HUD가 확인되면 즉시 메뉴로 진행한다.
    ; 의자 안내 재탐색은 시점 회전·걷기와 여러 화면 판독이 필요해 정리 시간을 늘린다.
    if (!requireChairPrompt) {
        deadline := A_TickCount + 3000
        Loop {
            if (EarnAborted())
                return false
            if (EarnMCTRecoveryHud())
                return true
            if (A_TickCount >= deadline || !EarnSleep(200))
                break
        }
        return EarnFail("MCT: 일어선 뒤 CEO 메뉴용 HUD 미확인")
    }
    return EarnMCTFindChairPrompt()
}

; CEO 해제 뒤 또는 의자 앞에서 계속 작업할 때만 안내를 다시 찾는다.
EarnMCTFindChairPrompt() {
    global EARN_PROMPT_AREA, config
    if (!EarnWaitSeen("mct_sit", EARN_PROMPT_AREA, 3000)) {
        ; 1인칭이면 저택 MCT에서 일어선 시선은 늘 의자 반대쪽 구석이고, 제자리 180도 회전만으로 접근 안내가 뜬다
        ; (1003 23:54~23:59 실측 7/7). 걷지 않으니 자리가 흐트러지지 않는다.
        ; 3인칭처럼 시선이 다를 때는 카메라를 90도씩 돌리며 W 를 짧게 눌러 캐릭터를 카메라 방향으로 세우고 안내를 찾는다.
        ; 저택 MCT는 미니맵 블립이 없어 길찾기를 못 쓴다. 한 번에 조금만 움직여 네 방향을 돌아도 의자 곁에 남는다.
        if (!EarnTurn(Round(180 * config["Settings"]["EarnTurnUnitsPerDeg"]), 0, true))
            return EarnFail("MCT: 일어선 뒤 접근 안내 미확인")
        found := EarnWaitSeen("mct_sit", EARN_PROMPT_AREA, 2000)
        Loop 4 {
            if (found)
                break
            if (!EarnWaitCallEnd())
                return false
            if (A_Index > 1 && !EarnTurn(Round(90 * config["Settings"]["EarnTurnUnitsPerDeg"]), 0, true))
                return EarnFail("MCT: 일어선 뒤 접근 안내 미확인")
            if (!EarnWalk("w:150"))
                return false
            found := EarnWaitSeen("mct_sit", EARN_PROMPT_AREA, 2000)
        }
        if (!found)
            return EarnFail("MCT: 일어선 뒤 접근 안내 미확인")
    }
    return true
}

; 게임 인물(Lester 등)의 전화가 오면 휴대폰이 오른쪽 아래를 가려 접근 안내를 못 찾는다(1004 17:41 실측:
; 일어선 직후 Lester 전화로 네 방향을 다 돌고 꺼짐). 전화가 보이면 Backspace 로 끊는다(거절·통화 종료 모두).
; 기다리면 통화 길이만큼 버리고, 끊어도 잃는 것은 그 소개 통화뿐이다. AFK 방지도 남은 전화를 같은 키로 닫는다.
; 연결된 통화는 휴대폰이 아래로 내려가 위 테두리 템플릿에 안 맞는다(1006 19:26 녹화: 차이 74~79). 그때는 오른쪽 아래
; 빨간 끊기 아이콘(phone_call_end, 같은 녹화에서 차이 0~8, 다른 화면 138 이상)으로 본다. 못 보면 네 방향을 걸어 다니다 꺼졌다.
EarnWaitCallEnd() {
    area := [0.83, 0.58, 0.98, 0.72], endArea := [0.9, 0.92, 0.99, 0.98]
    if (!EarnSeen("afk_phone_frame", area) && !EarnSeen("phone_call_end", endArea))
        return true
    EarnLog("MCT: 게임 전화가 와 Backspace 로 끊음")
    Loop 3 {
        if (!EarnPress("Backspace"))
            return false
        if (EarnWaitGone("afk_phone_frame", area, 3000) && EarnWaitGone("phone_call_end", endArea, 3000))
            return EarnSleep(1000)
    }
    return EarnFail("MCT: 게임 전화가 Backspace 3번에도 닫히지 않음")
}

; MCT 화면의 (x, y)(1920x1080 기준 좌표) 위에 커서를 두고, hover 템플릿이 area 안에 보이면 Enter. hover 가 "" 이면 확인 없이 Enter 하지 않는다.
EarnMCTPress(x, y, hover, area) {
    hwnd := IsGTAActive()
    if (!hwnd)
        return false
    WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
    DllCall("SetCursorPos", "int", cx + Round(x * cw / 1920) - 3, "int", cy + Round(y * ch / 1080) - 3)
    Sleep(80)
    DllCall("SetCursorPos", "int", cx + Round(x * cw / 1920), "int", cy + Round(y * ch / 1080))
    Sleep(500)
    if (!EarnSeen(hover, area))
        return EarnFail("MCT: 커서 아래 버튼(" hover ")을 확인하지 못함")
    return EarnPress("Enter")
}
; MCT 첫 화면 카드의 막대가 얼마나 찼는지(0~1). 막대 한 줄(1920x1080 기준 x1~x2, y)을 3px 간격으로 읽어 kind 색인 칸 비율을 낸다.
;   green = MCT 재고, blue = MCT 보급, orange = 벙커 내부 보급, pop = 나이트클럽 인기도
; 0926 실측 위치: 벙커 카드 재고 x 766~1154 y 555, 보급 y 577 / 나이트클럽 카드 인기도 x 340~708 y 471, 상품 재고 x 330~718 y 555
EarnBarFill(x1, x2, y, kind) {
    hwnd := IsGTAActive()
    if (!hwnd)
        return -1
    traceBar := x1 = 766 && x2 = 1154 && ((kind = "blue" && y = 577) || (kind = "green" && y = 555))
    tracePixels := "", traceRect := "unread", traceDpi := "unread", total := 0, full := 0
    traceStart := A_TickCount
    previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        CoordMode("Pixel", "Screen")
        if (traceBar) {
            traceRect := cx "," cy "," cw "," ch
            traceDpi := DllCall("GetThreadDpiAwarenessContext", "ptr")
        }
        sx := cw / 1920, sy := ch / 1080
        total := 0, full := 0
        x := x1
        while (x <= x2) {
            px := cx + Round(x * sx), py := cy + Round(y * sy)
            c := PixelGetColor(px, py)
            r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
            if (kind = "green")
                hit := g > 100 && g > r + 30 && g > b + 30
            else if (kind = "blue")
                hit := b > 110 && b > r + 30 && b > g + 30
            else if (kind = "orange")
                hit := r > 100 && r > g + 35 && g > b + 15
            else
                hit := Max(r, g, b) > 110
            if (traceBar)
                tracePixels .= (total ? " " : "") px "," py ":" Format("{:06X}", c) ":" (hit ? 1 : 0)
            full += hit ? 1 : 0
            total += 1
            x += 3
        }
        return total ? full / total : -1
    } finally {
        DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
        if (traceBar)
            try EarnLog("[bunker-bar] kind=" kind " rect=" traceRect " dpi_read=" traceDpi " dpi_previous=" previous
                " hits=" full "/" total " result=" (total ? full / total : -1)
                " elapsed_ms=" (A_TickCount - traceStart) " pixels=" tracePixels)
    }
}

; 진단용: 미니맵 영역을 %TEMP%\gta-earn-<tag>.png 로 저장한다 (스폰 자리 조사). 실패해도 흐름을 막지 않는다
EarnSnapMinimap(tag) {
    global EARN_MINIMAP
    try {
        hwnd := IsGTAActive()
        if (!hwnd)
            return
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        sx := cw / 1920, sy := ch / 1080
        x := cx + Round(EARN_MINIMAP[1] * sx), y := cy + Round(EARN_MINIMAP[2] * sy)
        w := Round((EARN_MINIMAP[3] - EARN_MINIMAP[1]) * sx), h := Round((EARN_MINIMAP[4] - EARN_MINIMAP[2]) * sy)
        ; 동기로 찍는다: 비동기(Run)로 하면 다음 단계(재접속의 P)가 먼저 눌려 일시정지 메뉴의 흐린 배경이 찍힌다(0927 실측)
        ; Main과 tools/earn-test 어느 진입점에서도 이 파일을 기준으로 런타임 도구를 찾는다.
        SplitPath(A_LineFile, , &sourceDir)
        captureScript := sourceDir "\..\..\Core\ScreenCapture.ps1"
        RunWait('"' A_WinDir '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "' captureScript '" -Name "gta-earn-' tag '" -X ' x ' -Y ' y ' -W ' w ' -H ' h ' -Scale 1', , "Hide")
    }
}

; 진단용: MCT 실패 순간의 GTA 클라이언트 전체를 %TEMP%\claude\gta-earn-fail-<시각>-<사유>.png 로 남긴다(절반 축소).
; 포커스를 바꾸지 않고 동기로 찍는다. 3초 안에 겹치는 실패는 한 장만 남기고, 오래된 것부터 지워 30장만 둔다. 실패해도 흐름을 막지 않는다.
EarnSnapFail(reason) {
    static lastTick := 0
    try {
        if (A_TickCount - lastTick < 3000)
            return
        hwnd := IsGTAActive()
        if (!hwnd)
            return
        lastTick := A_TickCount
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        tag := Trim(RegExReplace(SubStr(reason, 1, 40), "[^\p{L}\p{N}]+", "-"), "-")
        name := "gta-earn-fail-" FormatTime(, "yyyyMMdd-HHmmss") "-" tag
        SplitPath(A_LineFile, , &sourceDir)
        captureScript := sourceDir "\..\..\Core\ScreenCapture.ps1"
        RunWait('"' A_WinDir '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "' captureScript '" -Name "' name '" -X ' cx ' -Y ' cy ' -W ' cw ' -H ' ch ' -Scale 0.5', , "Hide")
        files := []
        Loop Files A_Temp "\claude\gta-earn-fail-*.png"
            files.Push(A_LoopFileFullPath)
        if (files.Length > 30) {
            sorted := ""
            for f in files
                sorted .= f "`n"
            sorted := Sort(RTrim(sorted, "`n"))
            n := files.Length - 30
            for f in StrSplit(sorted, "`n") {
                if (n <= 0)
                    break
                try FileDelete(f)
                n -= 1
            }
        }
    }
}

; === CEO 등록·해제 ===
; MCT 에서 벙커 보급·DJ 교체를 하려면 CEO(또는 MC 회장)여야 한다(0926 실측: "You need to be a CEO ... to manage this business").
; 사업장 습격을 피하려고 평소에는 해제해 두고, 작업 직전에 등록했다가 끝나면 바로 해제한다. 등록·해제 모두 상호작용 메뉴에서 줄 템플릿을 보고 고른다.
;   등록: M → Register as a Boss(m_boss_sel) → SecuroServ CEO(m_ceo_sel) → Enter → Start an Organization(m_start_org_sel) → Enter. 게임이 메뉴를 닫는다
;   해제: M → SecuroServ(m_securo_sel, 맨 위) → Enter → Retire(m_retire_sel, 맨 아래) → Enter. 확인창은 없다(0926 실측 예정)
;   확인: M 을 열어 맨 위 두 줄에 Register as a Boss 가 보이면 해제 상태, SecuroServ 가 보이면 등록 상태
EarnCEO(on) {
    global EARN_MENU_AREA
    ok := false
    try {
        ; 이미 CEO(조직 색 화살표, 색은 세션마다 다르다)면 메뉴를 열지 않는다. 해제 쪽은 쓰지 않는다: 해제는 MCT 앞에서 하는데
        ; 흰 노트북 아이콘이 화살표를 덮어 CEO 인데도 흰색으로 읽혀 해제를 건너뛰었다(1004 15:25 실측).
        if (on && EarnArrowCEOColor() = 1) {
            ok := true
            return true
        }
        if (!EarnMenuOpen())
            return EarnFail("CEO " (on ? "등록" : "해제") ": 상호작용 메뉴가 열리지 않음")
        if (on) {
            if (EarnSeen("m_securo_sel", EARN_MENU_AREA) || EarnSeen("m_securo", EARN_MENU_AREA)) {
                ok := true
                return true          ; 이미 CEO
            }
            if (!EarnSelectRow("m_boss_sel", EARN_MENU_AREA, "Down", 4))
                return EarnFail("CEO 등록: Register as a Boss 줄을 찾지 못함")
            if (!EarnPress("Enter"))
                return false
            if (!EarnSelectRow("m_ceo_sel", EARN_MENU_AREA, "Down", 3))
                return EarnFail("CEO 등록: SecuroServ CEO 줄을 찾지 못함")
            if (!EarnPress("Enter"))
                return false
            if (!EarnSelectRow("m_start_org_sel", EARN_MENU_AREA, "Down", 3))
                return EarnFail("CEO 등록: Start an Organization 줄을 찾지 못함")
            if (!EarnPress("Enter"))
                return false
            EarnSleep(2500)
            ok := EarnCEOIs(true)
            if (!ok)
                return EarnFail("CEO 등록: 등록 뒤 메뉴에 SecuroServ 가 안 보임")
            EarnLog("CEO 등록")
            return true
        }
        ; m_boss 는 허용 오차가 커서 테러바이트 CEO 메뉴의 다른 줄에도 맞았다(1003 17:13 실측).
        ; SecuroServ 줄이 보이면 CEO 이므로 그것부터 본다.
        ; CEO 면 SecuroServ 줄이 늘 맨 위에 있다. 해제 직후 맨션 안에서는 Register as a Boss 줄도 메뉴에서
        ; 빠지므로(1004 15:43 녹화: 맨 위가 Mansion Management, 11줄 중 보스 줄 없음) SecuroServ 가 없으면 해제로 본다.
        ; 둘 다 안 보이면 메뉴가 다시 그려지는 중일 수 있다. 열자마자 11줄이었다가 Register as a Boss 가 끼어 12줄로
        ; 다시 그려지며 잠깐 접힌다(1004 18:11 녹화). 그 순간 읽고 해제로 넘겨 메뉴가 열린 채 전화 키가 메뉴로 갔다.
        if (!EarnSeen("m_securo_sel", EARN_MENU_AREA) && !EarnSeen("m_securo", EARN_MENU_AREA)
            && !EarnSeen("m_boss_sel", EARN_MENU_AREA) && !EarnSeen("m_boss", EARN_MENU_AREA)) {
            if (!EarnSleep(1500))
                return false
        }
        if (!EarnSeen("m_securo_sel", EARN_MENU_AREA) && !EarnSeen("m_securo", EARN_MENU_AREA)) {
            ; 안 보인다는 판정은 GTA 가 앞에 있을 때 읽은 것만 믿는다. 포커스를 잃은 뒤 읽기로 이미 해제로 봤다(1023 12:33:51).
            if (EarnAborted())
                return false
            if (!EarnSeen("m_boss_sel", EARN_MENU_AREA) && !EarnSeen("m_boss", EARN_MENU_AREA))
                EarnLog("CEO 해제: 메뉴에 SecuroServ·Register as a Boss 둘 다 없음, 이미 해제로 봄")
            ok := true
            return true              ; 이미 해제
        }
        if (!EarnSelectRow("m_securo_sel", EARN_MENU_AREA, "Up", 4))
            return EarnFail("CEO 해제: SecuroServ 줄을 찾지 못함")
        if (!EarnPress("Enter"))
            return false
        if (!EarnSelectRow("m_retire_sel", EARN_MENU_AREA, "Up", 12))
            return EarnFail("CEO 해제: Retire 줄을 찾지 못함")
        if (!EarnPress("Enter"))
            return false
        ; 화살표가 흰색으로 돌아오면 메뉴를 다시 열지 않는다(녹화 실측: 메뉴 확인보다 3초 빠름). 판단이 안 서면 메뉴로 본다.
        deadline := A_TickCount + 4000
        Loop {
            if (!EarnSleep(300))
                return false
            if (EarnArrowCEOColor() = 0) {
                ok := true
                EarnLog("CEO 해제 (화살표 흰색)")
                return true
            }
            if (A_TickCount >= deadline)
                break
        }
        ok := EarnCEOIs(false)
        if (!ok)
            return EarnFail("CEO 해제: 해제 뒤 메뉴에 Register as a Boss 가 안 보임")
        EarnLog("CEO 해제")
        return true
    } finally {
        EarnMenuClose()
    }
}

; 미니맵 가운데 플레이어 화살표 색으로 CEO 여부를 본다. CEO 면 조직 색(세션마다 바뀐다. 1004 실측은 노랑), 아니면 흰색이다. 색상은 가리지 않고 채도만 본다.
; 1004 11:15~11:16 녹화 실측(150~178, 990~1020): CEO 동안 채도 높은 픽셀 24~31, 해제 뒤 0.
; MCT 노트북 아이콘(흰색)이 화살표에 겹쳐 흰 픽셀은 양쪽 다 있다. 1=조직 색, 0=흰 화살표뿐, -1=판단 못 함.
EarnArrowCEOColor() {
    hwnd := IsGTAActive()
    if (!hwnd)
        return -1
    prev := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
    } finally {
        if (prev)
            DllCall("SetThreadDpiAwarenessContext", "ptr", prev, "ptr")
    }
    if (cw != 1920 || ch != 1080)
        return -1
    w := 29, h := 31
    return EarnArrowColorOf(EarnGrab(cx + 150, cy + 990, w, h), w, h)
}

; 사장은 MCT 에서 벙커·DJ 를 만질 때만 필요하다. 작업이 못 끝나 정리가 사장 해제까지 못 갔을 때 켜진 채 남지 않도록,
; 조직 색 화살표가 확실히 켜져 있으면(1) 상호작용 메뉴로 해제한다.
; requireConfirmed=true는 CEO 해제가 확인돼야만 성공으로 처리하는 엄격한 확인 경로다.
; 이 때는 입력 불허나 화살표 판독 불가(-1)를 성공으로 간주하지 않고 복구에서 다시 확인한다.
EarnBossOffIfOn(requireConfirmed := false) {
    if (!EarnInputAllowed())
        return !requireConfirmed
    state := EarnArrowCEOColor()
    if (state != 1)
        return state = 0 || !requireConfirmed
    EarnLog("사장이 켜진 채 남아 있어 해제")
    return EarnCEO(false)
}

EarnArrowColorOf(buf, w, h) {
    sat := 0, white := 0
    Loop w * h {
        o := (A_Index - 1) * 4
        b := NumGet(buf, o, "UChar"), g := NumGet(buf, o + 1, "UChar"), r := NumGet(buf, o + 2, "UChar")
        hi := Max(r, g, b), lo := Min(r, g, b)
        if (hi >= 120 && hi - lo >= 60)
            sat += 1
        else if (lo >= 200)
            white += 1
    }
    return sat >= 12 ? 1 : sat = 0 && white >= 40 ? 0 : -1
}

; 상호작용 메뉴를 열어 등록 상태를 본다. want=true 면 SecuroServ 줄, false 면 Register as a Boss 줄이 보여야 true. 메뉴는 열어 둔 채 돌려준다(부르는 쪽이 닫는다)
EarnCEOIs(want) {
    global EARN_MENU_AREA
    if (!EarnMenuOpen())
        return false
    if (want)
        return EarnSeen("m_securo_sel", EARN_MENU_AREA) || EarnSeen("m_securo", EARN_MENU_AREA)
    return EarnSeen("m_boss_sel", EARN_MENU_AREA) || EarnSeen("m_boss", EARN_MENU_AREA)
}

; === 나이트클럽 인기도 읽기 ===
; 나이트클럽 안에서는 오른쪽 아래 HUD 에 POPULARITY 막대(칸 5개, 1920x1080 기준 x 1751~1880, y 1048)가 뜬다. 빈 칸은 어두운 회색(0x404040), 찬 칸은 밝다.
; 칸마다 찬 비율을 재서 평균 × 100 = %. 칸 안에서 조금씩 차는지(연속) 20% 단위로만 바뀌는지(계단)는 첫 교체 때 값으로 가린다(0926 실측 예정).
; MCT 첫 화면의 나이트클럽 카드에도 같은 막대(x 340~708, y 471)가 있다. HUD 가 없는 아케이드에서는 그것을 읽는다.
; 돌려주는 값: 0~100, 못 읽으면(HUD 없음·GTA 뒤) -1
EarnPopularityPct() {
    if (!EarnSeen("hud_safe_label", [0.82, 0.9, 0.95, 0.97]))
        return -1
    segs := [[1751, 1774], [1777, 1800], [1804, 1827], [1831, 1854], [1858, 1880]]
    sum := 0
    for s in segs {
        v := EarnBarFill(s[1], s[2], 1048, "pop")
        if (v < 0)
            return -1
        sum += v
    }
    return Round(sum / segs.Length * 100)
}

EarnPopularityMCTPct() {
    if (!EarnSeen("mct_title", [0.3, 0, 0.7, 0.1]))
        return -1
    v := EarnBarFill(340, 708, 471, "pop")
    return v < 0 ? -1 : Round(v * 100)
}
