; 바인우드 앱의 모든 사업장 금고를 확인한다. 사업장에 걷거나 재접속하지 않는다.
; 금고마다 한도와 게임 하루(48분) 최대 입금이 다르다. 다음 입금이 한도를 넘길 수 있는 금고만 수거한다.
; 값은 1004 조사(timesaver.gg 등 공략 정리). 출처마다 다르거나 업그레이드로 바뀌는 값은 일찍 수거하는 쪽으로 잡았다.
EarnSafeLimits() {
    static limits := Map(
        "Nightclub", [250000, 50000],         ; 1003 실측: 17:38 $195,000 → 18:12 $245,000
        "Arcade", [100000, 5000],
        "Agency", [250000, 20000],
        "Salvage Yard", [100000, 24000],      ; 벽 금고 업그레이드가 있으면 한도 $250,000. 확인 전이라 작게
        "Bail Office", [100000, 20000],       ; 요원 둘이 각각 최대 $10,000 (앱 직원 파견이 보낸다)
        "Garment Factory", [100000, 2500],   ; 1004 실측: 06:51 $49,750 → 11:34 $61,150, 48분당 약 $2,400
        "Hands On Car Wash", [100000, 100000]) ; 수입 변동을 고려해 양수 잔액은 매 관측 회수한다. docs/earner-policy.md
    return limits
}

EarnVinewoodSafeTask(manageMCT := true) {
    safes := EarnSafeLimits()
    if (!EarnVinewoodOpen(manageMCT))
        return false
    lines := EarnReadScreen([25,15,450,850])
    if (!IsObject(lines) || !EarnFindText(lines, "i)^THE VINEWOOD CLUB APP$"))
        return false
    if (EarnFindText(lines, "i)^No earnings to claim\.?$")) {
        EarnLog("금고: 바인우드 앱에 수거할 수익 없음")
        return EarnVinewoodClose()
    }
    ; 앱 메인과 수익 하위 목록은 제목이 같다. 이미 하위 목록이면 다시 Enter를 보내지 않는다.
    if (EarnFindText(lines, "i)^Claim Business Earnings$")) {
        row := EarnSelectText("i)^Claim Business Earnings$", "i)^THE VINEWOOD CLUB APP$", 6)
        if (!row || !EarnPress("Enter") || !EarnSleep(700))
            return EarnFail("금고: 수익 목록 진입 실패")
    }
    ; 목록은 맨 아래에서 Down 을 누르면 맨 위로 돈다(1004 실측: 7개 행). 처음 본 행이 다시 선택되면 한 바퀴다.
    seen := Map()
    Loop 12 {
        lines := EarnVinewoodReadSelected(&name, &amount)
        if (!IsObject(lines))
            return false
        if (name = "") {
            EarnLog("금고: 판독한 줄 " EarnVinewoodAmountDebug(lines))
            return EarnFail("금고: 수익 목록에서 선택한 사업장을 확인하지 못함")
        }
        if (seen.Has(name))
            break
        seen[name] := true
        if (!safes.Has(name)) {
            ; 모르는 사업장은 한도를 모르므로 금액만 남기고 수거하지 않는다.
            EarnLog("금고: 모르는 사업장 " name (amount >= 0 ? " $" amount : "") ", 수거 안 함")
        } else if (amount < 0 || amount > safes[name][1]) {
            EarnLog("금고: " name " 금액 판독 실패. 판독한 줄 " EarnVinewoodAmountDebug(lines))
        } else {
            EarnLog("금고: " name " $" amount)
            if (amount > 0 && EarnVinewoodSafeClaimDue(amount, safes[name]*)) {
                if (!EarnVinewoodClaim(name, amount))
                    return false
            }
        }
        if (!EarnPress("Down") || !EarnSleep(700))
            return false
    }
    if (!seen.Count)
        return EarnFail("금고: 수익 목록이 비어 있음")
    return EarnVinewoodClose()
}

; 선택한 행의 금고를 수거하고 같은 행의 빈 금고 문구를 확인한다. 다른 사업장이나 Claim All 은 고르지 않는다.
EarnVinewoodClaim(name, amount) {
    if (EarnAborted())
        return false
    EarnVinewoodReadSelected(&again, &againAmount)
    if (EarnAborted())
        return false
    if (again != name || againAmount != amount)
        return EarnFail("금고: 수거 직전 " name " $" amount " 선택 미확인")
    if (!EarnTransactionBegin("safe", name " $" amount " 수거 요청 결과 확인 필요"))
        return false
    ; 서버 응답이 늦어도 같은 요청을 재전송하지 않는다. 요청·OCR·대기에 하나의 기한을 쓴다.
    requestedAt := A_TickCount, deadline := requestedAt + 60000, delayed := false
    if (!EarnPress("Enter") || !EarnSleep(1000))
        return false
    Loop {
        if (EarnAborted())
            return false
        if (A_TickCount >= deadline)
            break
        lines := EarnVinewoodReadSelected(&after, &left, deadline, name)
        ; 느린 판독 도중 생긴 사용자 입력·포커스 이탈이나 기한 초과도 성공보다 먼저 검사한다.
        if (EarnAborted())
            return false
        if (A_TickCount >= deadline)
            break
        if (after != "" && after != name)
            return EarnFail("금고: " name " 수거 결과 확인 중 다른 사업장 선택. 다음 차례에 다시 읽음")
        if (IsObject(lines) && after = name && left = 0) {
            if (!EarnTransactionCashConfirmed("safe", "income", amount, name, "OCR 금액과 수거 뒤 빈 금고 확인"))
                return EarnFail("금고: 확인된 수입의 원장 저장 실패. 다음 차례에 다시 읽음")
            EarnLog("금고: " name " $" amount " 수거 뒤 빈 금고 확인 (요청 후 " (A_TickCount - requestedAt) "ms)")
            return true
        }
        if (!delayed && A_TickCount - requestedAt >= 15000) {
            delayed := true
            EarnLog("금고: " name " 수거 응답 대기 연장. 추가 요청 없이 최대 60초까지 확인")
        }
        ; 일시적인 OCR 누락도 읽기만 재시도한다. 모르는 확인창에서 Enter를 다시 보내지 않는다.
        if (!EarnSleep(Min(300, Max(1, deadline - A_TickCount))))
            return false
    }
    return EarnFail("금고: " name " 수거 후 60초 내 $0 미확인. 다음 차례에 다시 읽음")
}

; 다음 입금이 한도를 넘길 수 있으면 지금 수거한다. 꽉 찰 때까지 기다리면 넘치는 입금이 버려진다.
EarnVinewoodSafeClaimDue(amount, cap := 250000, daily := 50000) {
    return amount + daily > cap
}

; 선택한 행의 사업장 이름과 그 금고 금액을 읽는다. 한 번의 판독이 깨지면(1003 19:22 실측) 흰 글자 전처리와 재판독으로 세 번까지 본다.
; 테러바이트처럼 밝은 배경 위의 반투명 설명은 일반 OCR 이 깨뜨린다(1003 17:28 실측: "yOürNightclub").
EarnVinewoodReadSelected(&name, &amount, deadlineTick := 0, expectedName := "") {
    name := "", amount := -1, lines := false
    Loop 3 {
        for white in [false, true] {
            if (EarnAborted() || (deadlineTick && A_TickCount >= deadlineTick))
                return false
            read := EarnReadScreen([25,15,450,850], white, deadlineTick)
            if (EarnAborted() || (deadlineTick && A_TickCount >= deadlineTick))
                return false
            if (!IsObject(read))
                continue
            lines := read
            name := EarnVinewoodSelectedSafe(read)
            amount := name = "" ? -1 : EarnVinewoodSafeAmountOf(read, name)
            if (amount >= 0 || (expectedName != "" && name != "" && name != expectedName))
                return read
        }
        remaining := deadlineTick ? deadlineTick - A_TickCount : 500
        if (A_Index = 3 || remaining <= 0 || !EarnSleep(Min(500, remaining)))
            break
    }
    return lines
}

; 선택 막대가 걸린 행의 이름. 왼쪽 끝이 기호로 읽힐 때가 있다(1003 19:38 실측: ": Nightclub").
; 아는 사업장 이름은 대소문자를 무시하고 표준 이름으로 돌려준다.
EarnVinewoodSelectedSafe(lines) {
    safes := EarnSafeLimits()
    if (!IsObject(lines) || !EarnFindText(lines, "i)^THE VINEWOOD CLUB APP$"))
        return ""
    for line in lines {
        text := Trim(RegExReplace(line.text, "^[^A-Za-z0-9$]+"))
        if (text = "" || RegExMatch(text, "i)^(the vinewood club|claim |your )") || !EarnMenuRowSelected(line))
            continue
        for known in safes
            if (text = known)
                return known
        return text
    }
    ; 빈 금고의 회색 선택 행은 OCR에서 빠질 수 있다(1007 세차장 실측).
    ; 정확히 하나의 빈 금고 설명만 있을 때 이름을 복원한다. Claim 문구로 수거 대상을 추측하지 않는다.
    emptyCount := 0
    for line in lines {
        if (RegExMatch(line.text, "i)^Claim\b"))
            return ""
        emptyCount += RegExMatch(line.text, "i)^Your\b") > 0
    }
    if (emptyCount != 1)
        return ""
    found := ""
    for known in safes {
        if (EarnVinewoodSafeAmountOf(lines, known) != 0)
            continue
        if (found != "")
            return ""
        found := known
    }
    return found
}

; 금액을 다른 사업장의 설명이나 이름 옆의 임의 숫자에서 추측하지 않는다. 선택한 행과 같은 사업장 문구 하나만 쓴다.
; "your" 는 반투명 배경에서 깨지거나 앞 단어에 붙는다(1003·1004 실측: "ydÜr", "fromyour"). 금액과 "<사업장> safe." 는 그대로 요구한다.
; 긴 이름은 문구가 두 줄로 넘어간다(1004 실측: "Claim $35720 from your Garment Factory" / "safe.").
EarnVinewoodSafeAmountOf(lines, name) {
    if (!IsObject(lines) || name = "")
        return -1
    claimed := "i)^Claim \$[0-9,]+ from\s*\S+\s*\Q" name "\E safe\.$"
    ; 빈 금고 문구는 마침표가 빠져 읽힐 때가 있다(1006 06:51 녹화: 수거 성공 뒤 "Your Bail Office safe is empty" 만 26초 내내 읽혀
    ; 자동화가 꺼졌다). 문구가 통째로 맞아야 하고 뒤에 다른 글자는 없어야 하므로 마침표만 없어도 된다.
    empty := "i)^Your \Q" name "\E safe is empty\.?$"
    amount := -1, matches := 0
    for i, line in lines {
        texts := [line.text]
        if (i < lines.Length)
            texts.Push(line.text " " lines[i + 1].text)
        for text in texts {
            if (RegExMatch(text, empty)) {
                amount := 0, matches += 1
            } else if (RegExMatch(text, claimed)) {
                amount := EarnReadDollars(text), matches += 1
            }
        }
    }
    return matches = 1 ? amount : -1
}

; 이전 시험·로그와 같은 이름으로 나이트클럽 금액만 읽는다.
EarnVinewoodNightclubAmount(lines) {
    return EarnVinewoodSelectedSafe(lines) = "Nightclub" ? EarnVinewoodSafeAmountOf(lines, "Nightclub") : -1
}

; 실패 원인을 녹화 없이도 가릴 수 있게 앱 제목·선택 행·금고 문구만 한 줄로 남긴다.
EarnVinewoodAmountDebug(lines) {
    if (!IsObject(lines))
        return "(OCR 실패)"
    out := ""
    for line in lines {
        if (!RegExMatch(line.text, "i)vinewood club app|claim|safe") && !EarnMenuRowSelected(line))
            continue
        out .= (out = "" ? "" : " | ") line.text (EarnMenuRowSelected(line) ? "[선택]" : "")
    }
    return out = "" ? "(해당 줄 없음)" : out
}

; 메뉴·전화·앱이 없는 맨 게임 화면. 일반 HUD 는 물리·원격 입력이 모두 오래 없을 때만 허용한다.
; MCT 의 '앉기' 안내는 정상 기립을 직접 확인하므로 원격 매크로 입력 직후에도 허용하되, 물리 입력과 아래 오버레이 배제는 유지한다.
EarnVinewoodFreeHud(&mctStanding := false) {
    global config
    idleMs := config["Settings"]["EarnUserIdleSec"] * 1000
    others := A_TimeIdle
    try others := %"AFKOthersIdleMs"%()
    mctStanding := EarnSeen("mct_sit", [0,0,0.3,0.1])
    if (A_TimeIdlePhysical < idleMs || (!mctStanding && (others < idleMs || !(EarnHudVisible() || EarnVinewoodHealthHud()))))
        return false
    ; HDR 에서 전화기 테두리 템플릿이 사라져도 제목 OCR 로 열린 홈을 식별한다.
    if (EarnVinewoodPhoneTitle() != "")
        return false
    for name in ["afk_phone_frame", "ph_joblist_sel", "ph_vinewood_sel"]
        if (EarnSeen(name, [0.83,0.58,0.98,0.73]))
            return false
    for name in ["afk_vinewood_title", "m_title", "m_pref_title", "mct_title"]
        if (EarnSeen(name, name = "mct_title" ? [0.3,0,0.7,0.1] : [0,0,0.27,0.55]))
            return false
    return true
}

; CEO 메뉴가 닫힌 직후 MCT 기립 안내가 한 박자 늦게 돌아올 수 있다. 입력 없이 짧게 기다려 준비 화면만 다시 판독한다.
; 판독에 걸린 시간도 timeoutMs 안에 포함하고, 성공한 MCT 안내 결과를 호출자가 다시 판독하지 않게 전달한다.
EarnVinewoodWaitFreeHud(timeoutMs := 3000, &mctStanding := false) {
    mctStanding := false
    deadline := A_TickCount + Max(0, timeoutMs)
    Loop {
        if (EarnAborted())
            return false
        if (EarnVinewoodFreeHud(&seenMCT)) {
            mctStanding := seenMCT
            return true
        }
        remainingMs := deadline - A_TickCount
        if (remainingMs <= 0)
            return false
        if (!EarnSleep(Min(200, remainingMs)))
            return false
    }
}

; HDR 에서 전화기 프레임 템플릿이 맞지 않을 때 홈 제목을 상태 앵커로 사용한다.
EarnVinewoodPhoneTitle() {
    ; 화면이 밝으면 파란 바탕 위 흰 제목이 'Job-L' 처럼 잘려 읽힌다(1010 01:41 실측, 같은 영역을 흰 글자 모드로 읽으면 'Job List').
    ; 그래서 흰 글자 모드를 먼저 읽고, 못 알아보면 원래 방식으로 한 번 더 읽는다.
    for whiteText in [true, false] {
        lines := EarnReadScreen([1580,710,300,100], whiteText)
        if (!IsObject(lines))
            return ""
        for title in ["Texts", "Job List", "Internet", "Contacts", "Email", "Mail", "Camera", "Snapmatic", "Settings", "Quick Save", "Radio"]
            if (EarnFindText(lines, "i)^" title "$"))
                return title
        ; Vinewood 앱 제목은 흰 글자 모드에서 'Vlnewood Club'·'vqnewood Club' 처럼 앞 글자가 흔들린다(1010 02:00 실측).
        if (EarnFindText(lines, "i)^\W*\w{1,3}n[eo]wood\h*Club\W*$"))
            return "Vinewood Club"
    }
    return ""
}

; 전화 홈에서 Vinewood Club 앱이 선택됐는지. 선택 템플릿이 밝기 때문에 안 맞아도 제목 글자로 확인한다.
EarnVinewoodWaitSelected(timeoutMs) {
    deadline := A_TickCount + timeoutMs
    nextTitleRead := 0
    Loop {
        if (EarnAborted())
            return false
        if (EarnSeen("ph_vinewood_sel", [0.83,0.66,0.98,0.73]))
            return true
        if (A_TickCount >= nextTitleRead) {
            if (EarnVinewoodPhoneTitle() = "Vinewood Club")
                return true
            nextTitleRead := A_TickCount + 300
        }
        if (A_TickCount >= deadline || !EarnSleep(200))
            return false
    }
}

EarnVinewoodWaitJobList(timeoutMs) {
    deadline := A_TickCount + timeoutMs
    nextTitleRead := 0
    Loop {
        if (EarnAborted())
            return false
        if (EarnSeen("ph_joblist_sel", [0.83,0.66,0.98,0.73]))
            return true
        if (A_TickCount >= nextTitleRead) {
            if (EarnVinewoodPhoneTitle() = "Job List")
                return true
            nextTitleRead := A_TickCount + 300
        }
        if (A_TickCount >= deadline || !EarnSleep(200))
            return false
    }
}

; 앱 진입용 HUD 확인. 밝기가 바뀌어도 체력 막대의 녹색 우세와 가로 연속성을 본다.
; 전역 이동·로딩 판정의 색 허용치는 바꾸지 않는다.
EarnVinewoodHealthHud() {
    return HealthHudVisible()
}

EarnVinewoodHealthColors(colors) {
    return HealthHudColors(colors)
}

EarnVinewoodOpen(manageMCT := true) {
    lines := EarnReadScreen([25,15,450,500])
    if (!IsObject(lines))
        return false
    if (EarnFindText(lines, "i)^THE VINEWOOD CLUB APP$"))
        return !EarnGlitchNote("phone", false)
    phoneTitle := EarnVinewoodPhoneTitle()
    jobList := EarnSeen("ph_joblist_sel", [0.83,0.66,0.98,0.73]) || phoneTitle = "Job List"
    vinewood := EarnSeen("ph_vinewood_sel", [0.83,0.66,0.98,0.73]) || phoneTitle = "Vinewood Club"
    if (!jobList && !vinewood && phoneTitle = "") {
        if (manageMCT && EarnAtMCT() && !EarnMCTClose())
            return false
        atMCT := manageMCT && (EarnSeen("mct_sit", [0,0,0.3,0.1]) || EarnSeen("mct_terrorbyte"))
        ; MCT 앞이 아니어도 메뉴·전화 없는 맨 HUD 에서 손을 뗀 지 오래면 전화로 앱을 연다(1005 사용자 요청).
        ; 그때 CEO·MC 상태는 사용자가 정한 것이라 건드리지 않는다.
        waitedAtMCT := false
        if (!atMCT && !EarnVinewoodWaitFreeHud(3000, &waitedAtMCT)) {
            ; 아직 아무 입력도 안 보낸 단계다. MCT 작업처럼 끄지 않고 바로 다시 한다
            ; (1004 21:56 사용자가 일시정지 메뉴를 연 채 손을 떼자 MCT 작업은 미뤄졌는데 금고만 자동화를 껐다).
            global gEarnRetryIn
            gEarnRetryIn := 0
            return EarnFail("Vinewood 앱: 사용자 입력 유휴 또는 메뉴 없는 게임 HUD 미확인")
        }
        ; 대기 중 MCT 안내가 나타났다면 일반 금고 경로의 기존 CEO 정리 계약을 유지한다.
        if (!atMCT && manageMCT && waitedAtMCT)
            atMCT := true
        if (!atMCT)
            EarnLog("Vinewood 앱: 위치·보스 변경 없이 게임 HUD에서 전화로 앱을 연다")
        if ((atMCT && !EarnCEO(false)) || !EarnPress("Up") || !EarnSleep(700))
            return false
    }
    ; 전화 프레임 그림이 HDR 에서 누락돼도 화면 제목과 선택 앱으로 홈 상태를 판정한다.
    deadline := A_TickCount + 4000
    nextTitleRead := 0
    while (!jobList && !vinewood) {
        jobList := EarnSeen("ph_joblist_sel", [0.83,0.66,0.98,0.73])
        vinewood := EarnSeen("ph_vinewood_sel", [0.83,0.66,0.98,0.73])
        if (jobList || vinewood)
            break
        if (A_TickCount >= nextTitleRead) {
            phoneTitle := EarnVinewoodPhoneTitle()
            nextTitleRead := A_TickCount + 300
        }
        if (phoneTitle = "Job List") {
            jobList := true
            break
        }
        if (phoneTitle = "Vinewood Club") {
            vinewood := true
            break
        }
        if (phoneTitle = "Texts") {
            EarnLog("Vinewood 앱: 전화 홈 Texts 제목 확인 → Job List로 이동")
            if (!EarnPress("Down"))
                return false
            jobList := EarnVinewoodWaitJobList(1500)
            if (!jobList) {
                ; 화면이 Internet 이라고 확인된 경우에만 한 칸 위로 보정한다.
                phoneTitle := EarnVinewoodPhoneTitle()
                if (phoneTitle = "Internet") {
                    EarnLog("Vinewood 앱: Down 후 Internet 제목 확인 → Up으로 Job List 보정")
                    if (!EarnPress("Up") || !EarnVinewoodWaitJobList(1500))
                        return EarnFail("금고: Texts에서 Job List 이동 미확인")
                    jobList := true
                } else {
                    return EarnFail("금고: Texts에서 Job List 이동 미확인")
                }
            }
            break
        }
        if (phoneTitle = "Internet") {
            EarnLog("Vinewood 앱: 전화 홈 Internet 제목 확인 → Up으로 Job List 이동")
            if (!EarnPress("Up") || !EarnVinewoodWaitJobList(1500))
                return EarnFail("금고: Internet에서 Job List 이동 미확인")
            jobList := true
            break
        }
        ; Up 을 보냈는데 전화가 안 뜬 것이다. 게임 문제로 입력이 안 먹는 연속 횟수로 센다(EarnGlitchNote).
        if (A_TickCount >= deadline || !EarnSleep(200))
            return EarnFail("금고: 전화 홈 화면 미확인") || !EarnGlitchNote("phone", true)
    }
    if (jobList) {
        if (!EarnPress("Right"))
            return false
    }
    ; Right 뒤 선택이 안 보일 때가 있다(1005 06:30 실측, 바로 다음 회차는 정상). 앱에 들어가기 전이므로
    ; 전화를 닫고 바로 다시 한다.
    if (!EarnVinewoodWaitSelected(3000)) {
        if (!EarnPress("Backspace"))
            return false
        gEarnRetryIn := 0
        return EarnFail("금고: 전화 홈에서 Vinewood Club 앱 선택 미확인") || !EarnGlitchNote("phone", true)
    }
    if (!EarnPress("Enter") || !EarnSleep(700))
        return false
    return EarnFindText(EarnReadScreen([25,15,450,500]), "i)^THE VINEWOOD CLUB APP$")
        ? !EarnGlitchNote("phone", false) : (EarnFail("금고: Vinewood Club 앱이 열리지 않음") || !EarnGlitchNote("phone", true))
}

EarnVinewoodClose() {
    backCount := 0, closedReads := 0
    Loop 8 {
        lines := EarnReadScreen([25,15,450,850])
        if (!IsObject(lines))
            return false
        if (EarnFindText(lines, "i)^THE VINEWOOD CLUB APP$")
            || EarnSeen("ph_vinewood_sel", [0.83,0.66,0.98,0.73])
            || EarnSeen("ph_joblist_sel", [0.83,0.66,0.98,0.73])) {
            if (backCount >= 4 || !EarnPress("Backspace") || !EarnSleep(1000))
                return false
            backCount += 1
            continue
        }
        if (EarnSeen("mct_sit", [0,0,0.3,0.1]) || EarnSeen("mct_terrorbyte"))
            return true
        closedReads += 1
        ; 앱이 닫혀도 MCT 접근 안내가 약 1초 뒤 나타날 수 있다. 미확인 화면에는 입력하지 않는다.
        if (!EarnSleep(300))
            return false
    }
    ; 조달 직후에는 게임 알림이 왼쪽 위 안내 자리를 몇 초 덮는다(1005 08:40 실측: 격납고 조달 뒤 닫기 제한).
    ; 마지막까지 앱·전화가 안 보였으면 닫힌 것이다. 위치는 다음 작업이 시작할 때 다시 확인한다.
    if (closedReads >= 3) {
        EarnLog("Vinewood 앱: 앱·전화 닫힘 확인, MCT 위치 확인은 필요 없음")
        return true
    }
    return EarnFail("금고: 앱 메뉴 닫기 제한")
}
