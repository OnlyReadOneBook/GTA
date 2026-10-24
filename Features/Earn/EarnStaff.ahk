; Vinewood 앱 직원 파견. 화면의 선택·상세 문구와 파견 후 상태를 함께 확인한다.
EarnVinewoodStaffTask() {
    global config
    s := config["Settings"]
    bail := s["EarnBailAgents"], cargo := s["EarnCargoStaff"], hangar := s.Get("EarnHangarStaff", 0)
    if (!bail && !cargo && !hangar)
        return true
    if (!EarnVinewoodOpen(false))
        return false
    root := EarnStaffRoot()
    if (!root)
        return false
    if (root = "idle") {
        EarnLog("직원: 직원 관리 메뉴 회색(모든 직원 작업 중), 건너뜀")
    } else {
        ; 목록 맨 윗줄 Hangar 를 먼저 보낸다. 창고·요원 단계가 중단돼도 격납고는 이 회차에 빠지지 않는다(1013 03:14 회차는 창고에서 멈춰 격납고를 건너뛰었다).
        if (hangar) {
            if (!EarnStaffHangar())
                return false
        }
        if (cargo) {
            if (!EarnStaffRoot() || !EarnStaffCargoWarehouses())
                return false
        }
        if (bail) {
            if (!EarnStaffRoot() || !EarnStaffBailAgents())
                return false
        }
    }
    return EarnVinewoodClose()
}

; 직원 관리 목록(Hangar·Warehouse·Bail Office)인지 본다. 요원이 모두 나가 Bail Office 가 회색이면
; 일반 판독은 "pail Office", 흰 글자 판독은 줄을 빠뜨린다(1004 15:04 녹화 실측). Hangar 줄은 이 목록에만 있어 대신 쓴다.
EarnStaffAllBusy() {
    footer := EarnReadScreen([25,392,450,70])
    return IsObject(footer) && EarnStaffUniqueRow(footer, "i)^All of your staff members are currently")
}

; 직원이 모두 나간 회색 줄을 고르면 목록 아래에 "Your <사업장> staff member(s) are currently busy." 가 뜬다.
; 이때 바로 위 줄 판독이 깨진다(1006 20:04 녹화: Bail Office 를 고르자 Warehouse 가 "Wareho se"). 줄 이름 대신 이 문구로 본다.
; 판독은 글자가 빠진다("Your Bai Office staff member"). 글자만 남겨 "your" 로 시작하고 "<word>staffmember" 가 든 줄을 찾는다.
EarnStaffSectionBusy(word) {
    for white in [false, true] {
        lines := EarnReadScreen([25,280,450,80], white)
        if (!IsObject(lines))
            continue
        for row in lines {
            text := StrLower(RegExReplace(row.text, "[^A-Za-z]"))
            if (SubStr(text, 1, 4) = "your" && InStr(text, word "staffmember"))
                return true
        }
    }
    return false
}

; 직원 목록 줄 이름은 뒤 배경이 밝으면(MCT 앞이 아닌 빈 화면에서 연 앱) 글자가 빠지거나 바뀐다(1006 녹화: 20:35
; "Warehou e"·"Bail Offic", 21:30 "Warehous"·"ail Office", 그 밖에 "Wareho se"·"Warehoåse"). 모양을 하나씩 더하는 대신
; "~이름" 패턴으로 편집 거리 비교한다(EarnStaffTextMatch). 회색 Bail Office 는 흰 글자 판독에서 줄이 빠지는 것으로 먼저 거른다.
; 셋 중 두 줄이면 직원 목록이다. 바쁜 Bail Office 를 고르면 Warehouse 판독이 깨진다(1006 20:04 "Wareho se").
EarnStaffListSeen(lines) => EarnStaffUniqueRow(lines, "~Warehouse")
    && (EarnStaffUniqueRow(lines, "~Bail Office") || EarnStaffUniqueRow(lines, "~Hangar"))
    || EarnStaffUniqueRow(lines, "~Hangar") && EarnStaffUniqueRow(lines, "~Bail Office")

; 확인한 앱 메뉴만 거슬러 올라간다. 알 수 없는 화면에는 Backspace를 보내지 않는다.
EarnStaffRoot() {
    unread := 0
    Loop 6 {
        lines := EarnReadScreen([25,125,450,263])
        if (!EarnStaffUniqueRow(lines, "i)^THE VINEWOOD CLUB APP$"))
            return EarnFail("직원: Vinewood 앱 제목 미확인")
        if (!EarnStaffUniqueRow(lines, "i)^Manage Staff Members$")
            && !EarnStaffListSeen(lines)
            && !EarnStaffBailIdentity(lines, 1) && !EarnStaffBailIdentity(lines, 2)) {
            white := EarnReadScreen([25,125,450,263], true)
            if (!EarnStaffUniqueRow(white, "i)^THE VINEWOOD CLUB APP$"))
                return EarnFail("직원: Vinewood 앱 제목 재확인 실패")
            ; 작업 중인 요원 행은 밝은 막대 위 회색 글자라 일반 판독이 깨진다(1004 02:01 실측: "I Agent 2").
            if (EarnStaffUniqueRow(white, "i)^Manage Staff Members$")
                || EarnStaffListSeen(white)
                || EarnStaffBailIdentity(white, 1) || EarnStaffBailIdentity(white, 2))
                lines := white
        }
        if (EarnStaffListSeen(lines))
            return true
        ; 회색 Manage Staff Members 가 선택되면 아래에 "All of your staff members are currently busy." 가 뜨고 Enter 는 무시된다
        ; (1005 02:16 캡처). 회색 줄은 판독이 정확할 때도 깨질 때도 있어 이 문구를 먼저 본다.
        if (EarnStaffAllBusy())
            return "idle"
        if (EarnStaffUniqueRow(lines, "i)^Manage Staff Members$")) {
            if (!EarnStaffSelectEnter("i)^Manage Staff Members$", 6)) {
                ; 회색 줄로 옮겨 Enter 가 무시되면 그때 하단에 모든 직원 작업 중 문구가 뜬다(1005 11:36 실측).
                if (EarnStaffAllBusy())
                    return "idle"
                return EarnFail("직원: 직원 관리 목록 진입 실패")
            }
            continue
        }
        if ((EarnStaffBailIdentity(lines, 1) || EarnStaffBailIdentity(lines, 2)
            || EarnStaffBailBusyFrame(lines, 1) || EarnStaffBailBusyFrame(lines, 2))
            || IsObject(EarnStaffReadCargo())) {
            if (!EarnPress("Backspace") || !EarnSleep(700))
                return false
            continue
        }
        ; 직원이 모두 일하러 나가면 첫 메뉴의 Manage Staff Members 줄이 회색이 되고 판독이 "Manage Staff Mempers" 로 깨진다
        ; (1005 01:59 캡처: 흰 줄 밝기 240, 회색 줄 155). 밝은 글자가 아니면 들어갈 수 없는 메뉴이므로 건너뛴다.
        dim := EarnStaffDimManageRow(lines)
        if (dim && !EarnWarehouseBrightLabel(dim))
            return "idle"
        ; 회색 줄이 아예 안 읽히는 프레임도 있다(1006 02:24 녹화: 26초 중 3프레임). 입력 없이 다시 읽는다.
        if (++unread < 3 && EarnSleep(600))
            continue
        ; 다시 읽어도 안 읽히면 첫 메뉴(Claim Business Earnings 가 보임)의 여섯째 줄 자리 밝기로 회색 글자인지 본다(1006 03:05).
        heading := EarnStaffUniqueRow(lines, "i)^THE VINEWOOD CLUB APP$")
        if (heading && EarnStaffUniqueRow(lines, "i)^Claim Business Earnings$")
            && EarnWarehouseGreyLabel({x: 185, y: heading.y + 37 * 6, w: 290, h: 20}))
            return "idle"
        return EarnFail("직원: 직원 관리 메뉴 위치 미확인")
    }
    return EarnFail("직원: 직원 관리 메뉴 복귀 제한")
}

EarnStaffBailAgents() {
    ; 회색 Bail Office 는 흰 글자 판독에서 줄째 빠진다(1004 15:04 실측). 그 줄을 고르려 들면 진입 실패로 멈추므로 먼저 거른다.
    white := EarnReadScreen([25,125,450,263], true)
    if (IsObject(white) && EarnStaffUniqueRow(white, "~Warehouse") && !EarnStaffUniqueRow(white, "~Bail Office")) {
        EarnLog("직원: 보석 사무소 회색(요원 모두 작업 중), 건너뜀")
        return true
    }
    if (!EarnStaffSelectEnter("~Bail Office", 3)) {
        if (EarnStaffSectionBusy("office")) {
            EarnLog("직원: 보석 사무소 작업 중 문구 확인, 건너뜀")
            return true
        }
        return EarnFail("직원: 보석 사무소 목록 진입 실패")
    }
    ; 두 요원이 모두 작업 중이면 Bail Office 줄이 회색이고 Enter 가 무시된다(1003 17:39 실측).
    ; 그대로 Agent 1 을 찾으면 Down 이 다른 줄로 넘어가므로, 목록이 그대로면 건너뛴다.
    if (!EarnStaffMenuTarget("i)^Agent [1Il]$") && (EarnStaffSectionBusy("office")
        || EarnStaffMenuTarget("~Warehouse") && EarnStaffMenuTarget("~Bail Office"))) {
        EarnLog("직원: 보석 사무소 비활성(요원 모두 작업 중), 건너뜀")
        return true
    }
    Loop 2 {
        agent := A_Index
        if (!EarnStaffSelectText(agent = 1 ? "i)^Agent [1Il]$" : "i)^Agent 2$", 2))
            return EarnFail("직원: 보석 집행 요원 " agent " 선택 실패")
        state := EarnStaffReadBail(agent)
        if (state = "busy") {
            EarnLog("직원: 보석 집행 요원 " agent " 작업 중, 건너뜀")
            continue
        }
        if (state != "ready")
            return EarnFail("직원: 보석 집행 요원 " agent " 준비 문구 미확인")
        if (EarnStaffReadBail(agent) != "ready")
            return EarnFail("직원: 보석 집행 요원 " agent " 파견 직전 상태 변경")
        deadline := A_TickCount + 60000
        if (!EarnTransactionBegin("staff", "보석 집행 요원 " agent " 파견 결과 확인 필요"))
            return false
        if (!EarnPress("Enter") || !EarnSleep(700))
            return false
        if (!EarnStaffWaitBusy("bail", agent, deadline))
            return EarnFail("직원: 보석 집행 요원 " agent " 파견 결과 미확인, 재요청 중단")
        EarnTransactionConfirmed("staff")
        EarnLog("직원: 보석 집행 요원 " agent " 파견 확인")
    }
    return true
}

EarnStaffCargoWarehouses() {
    if (!EarnStaffSelectEnter("~Warehouse", 3)) {
        if (EarnStaffSectionBusy("ehouse")) {
            EarnLog("직원: 창고 직원 작업 중 문구 확인, 건너뜀")
            return true
        }
        return EarnFail("직원: 스페셜 패키지 창고 목록 진입 실패")
    }
    ; 창고 직원이 모두 조달 중이면 Warehouse 줄이 회색이고 Enter 가 무시된다(1004 21:37 녹화:
    ; "Your Warehouse staff members are currently busy."). 보석 사무소처럼 목록이 그대로면 건너뛴다.
    current := EarnStaffReadCargo()
    if (!IsObject(current) && (EarnStaffSectionBusy("ehouse") || EarnStaffMenuTarget("~Warehouse")
        && (EarnStaffMenuTarget("~Bail Office") || EarnStaffMenuTarget("~Hangar")))) {
        EarnLog("직원: 창고 직원 모두 조달 중(Warehouse 비활성), 건너뜀")
        return true
    }
    if (!IsObject(current) || current.index != 1)
        return EarnFail("직원: 스페셜 패키지 첫 창고·목록 판독 실패")
    count := current.count, visited := Map()
    Loop count {
        if (A_Index > 1)
            current := EarnStaffReadCargo()
        ; 판독이 한 번 흔들리는 일이 있다(1005 06:07 실측, 바로 다음 회차는 정상). 이 줄에서는 아직 Enter 전이라
        ; 한 번 더 읽고, 그래도 어긋나면 남은 창고는 사지 않고 5분 뒤 다시 본다.
        if (A_Index > 1 && !EarnStaffCargoInOrder(current, A_Index, count, visited)) {
            if (!EarnSleep(500))
                return false
            current := EarnStaffReadCargo()
        }
        if (!EarnStaffCargoInOrder(current, A_Index, count, visited)) {
            EarnLog("직원: 스페셜 패키지 " A_Index "번째 창고 판독 어긋남, 남은 창고는 건너뜀")
            return EarnStaffCargoLeave()
        }
        if (current.name != "")
            visited[StrLower(current.name)] := true
        displayName := current.name = "" ? "창고 " A_Index " (이름 판독 불가)" : current.name
        ; 이름 OCR이 빠져도 순번·총 개수를 확인한 같은 선택 슬롯의 알림을 갱신한다.
        noticeKey := "cargo:" current.index
        if (current.state = "busy" || current.state = "full") {
            EarnLog("직원: " displayName (current.state = "busy" ? " 조달 중" : " 만재") ", 건너뜀")
            ; 조달 중이면 만재가 아니다. 판매 뒤 바로 조달을 보낸 창고의 알림이 남지 않게 지운다.
            if (current.state = "full")
                EarnNotifyStockFull(noticeKey, "스페셜 패키지 " displayName " 만재: 판매 필요")
            else
                EarnClearStockNotice(noticeKey)
        } else {
            if (current.state != "ready" || current.price != 7500)
                return EarnFail("직원: " current.name " 준비 문구 또는 $7,500 미확인")
            fresh := EarnStaffReadCargo()
            if (EarnStaffSameWarehouse(fresh, current) && fresh.state = "full") {
                EarnLog("직원: " displayName " 조달 직전 만재 확인, 이 창고는 사지 않고 건너뜀")
                EarnNotifyStockFull(noticeKey, "스페셜 패키지 " displayName " 만재: 판매 필요")
            } else if (!EarnStaffSameWarehouse(fresh, current) || fresh.state != "ready" || fresh.price != 7500) {
                EarnLog("직원: " current.name " 조달 직전 재확인 어긋남, 남은 창고는 사지 않고 건너뜀")
                return EarnStaffCargoLeave()
            } else {
                EarnClearStockNotice(noticeKey)
                deadline := A_TickCount + 60000
                if (!EarnTransactionBegin("staff", current.name " $7,500 조달 결과 확인 필요"))
                    return false
                if (!EarnPress("Enter") || !EarnSleep(700))
                    return false
                if (!EarnStaffWaitBusy("cargo", current, deadline, &resultState))
                    return EarnFail("직원: " current.name " 조달 결과 미확인, 재구매 중단")
                if (!EarnTransactionCashConfirmed("staff", "expense", current.price, current.name, "OCR 7,500달러 조달과 작업 중 상태 확인"))
                    return EarnFail("직원: 확인된 창고 조달의 원장 저장 실패. 다음 차례에 다시 읽음")
                if (resultState = "full") {
                    EarnLog("직원: " displayName " 조달 뒤 만재 확인, 다음 창고 계속")
                    EarnNotifyStockFull(noticeKey, "스페셜 패키지 " displayName " 만재: 판매 필요")
                } else {
                    EarnLog("직원: " current.name " $7,500 조달 확인")
                }
            }
        }
        if (A_Index < count && (!EarnPress("Down") || !EarnSleep(200)))
            return false
    }
    ; 끝까지 돌아도 마지막 만재 창고가 선택된 화면은 다음 EarnStaffRoot 판독이 자주 흔들린다(1005 11:01 실측).
    return EarnStaffCargoLeave()
}

; 주문 처리 중에는 준비 문구가 남을 수 있다. 한 번만 요청하고 최대 60초 관측한다.
EarnStaffWaitBusy(kind, target, deadline, &resultState := "") {
    resultState := ""
    deadline := Min(deadline, A_TickCount + 60000)
    glitches := 0
    Loop 121 {
        if (A_TickCount >= deadline || EarnAborted())
            return false
        if (kind = "bail") {
            state := EarnStaffReadBail(target, &identityValid, deadline, &identityRejected)
            if (!identityValid) {
                ; 요원 행·제목의 일시적인 OCR 누락은 선택 변경의 증거가 아니다. 다시 읽기만 한다.
                ; 다른 요원 선택을 실제로 관측했거나 6번 연속 신원을 잃었으면 보류한다.
                if (identityRejected || ++glitches >= 6
                    || !EarnSleep(Max(0, Min(500, deadline-A_TickCount))))
                    return false
                continue
            }
            glitches := 0
        } else {
            current := EarnStaffReadCargo(target, deadline)
            ; 판독이 한 번 흔들려 아무것도 못 읽은 것은 선택이 바뀐 증거가 아니다. 다시 읽기만 한다(Enter 는 다시 안 누른다).
            ; 1005 22:14:42 West Vinewood Backlot 을 이렇게 포기했는데, 녹화로는 1초 뒤 "currently out on a job" 이 떴다.
            ; 다른 창고가 읽히면 그대로 멈추고, 못 읽는 일이 6번 이어지면 화면을 잃은 것으로 본다.
            if (!IsObject(current) && ++glitches < 6 && EarnSleep(Max(0, Min(500, deadline-A_TickCount))))
                continue
            if (!EarnStaffSameWarehouse(current, target))
                return false
            glitches := 0
            state := current.state
        }
        if (A_TickCount >= deadline || EarnAborted())
            return false
        if (state = "busy" || kind = "cargo" && state = "full") {
            resultState := state
            return true
        }
        ; 같은 앱·대상 선택이 유지되면 일시적인 설명 OCR 실패에는 읽기만 재시도한다.
        if ((state != "ready" && state != "invalid") || !EarnSleep(Max(0, Min(500, deadline-A_TickCount))))
            return false
    }
    return false
}

; 격납고 직원(Rooster McCraw)은 $25,000 를 받고 게임 하루 안팎에 항공 화물 1~2상자를 랜덤으로 가져온다.
; 직원 관리 목록 첫 줄 Hangar 에서 Enter 로 바로 보낸다. 같은 줄의 $25000 과 목록 아래 설명이 맞을 때만 보낸다
; (1004 21:36 녹화: 선택 시 "Hangar $25000", 설명 "Send your Hangar staff member out on a job.").
EarnStaffHangar() {
    if (!EarnStaffSelectText(EarnStaffHangarPattern(), 3))
        return EarnFail("직원: 격납고 줄 선택 실패")
    state := EarnStaffReadHangar()
    if (state = "busy" || state = "full" || state = "invalid") {
        ; 작업 중·만재 문구는 아직 실측 전이다. 모르는 상태에서는 사지 않고 5분 뒤 다시 본다.
        EarnLog("직원: 격납고 " (state = "busy" ? "조달 중" : state = "full" ? "만재" : "상태 미확인") ", 건너뜀")
        if (state = "full")
            EarnNotifyStockFull("hangar", "격납고 재고 만재: 판매 필요")
        else if (state = "busy")
            EarnClearStockNotice("hangar")
        return true
    }
    ; 재확인이 어긋나도 아직 Enter 전이라 산 것이 없다. 자동화를 끄지 않고 5분 뒤 다시 본다(1005 04:20 실측).
    recheck := EarnStaffReadHangar()
    if (recheck = "full") {
        EarnLog("직원: 격납고 조달 직전 만재 확인, 사지 않고 건너뜀")
        EarnNotifyStockFull("hangar", "격납고 재고 만재: 판매 필요")
        return true
    }
    if (recheck != "ready") {
        EarnLog("직원: 격납고 조달 직전 재확인 " recheck ", 사지 않고 건너뜀")
        return true
    }
    EarnClearStockNotice("hangar")
    deadline := A_TickCount + 60000
    if (!EarnTransactionBegin("staff", "격납고 $25,000 조달 결과 확인 필요"))
        return false
    if (!EarnPress("Enter") || !EarnSleep(700))
        return false
    ; 주문 처리 중에는 보내기 문구가 잠깐 남을 수 있다. 다시 누르지 않고 최대 60초(121번) 읽기만 한다.
    Loop 121 {
        if (A_TickCount >= deadline || EarnAborted())
            break
        state := EarnStaffReadHangar(deadline)
        if (state = "busy" || state = "full") {
            if (!EarnTransactionCashConfirmed("staff", "expense", 25000, "격납고 조달", "OCR 25,000달러 항목과 조달 완료 상태 확인"))
                return EarnFail("직원: 확인된 격납고 조달의 원장 저장 실패. 다음 차례에 다시 읽음")
            EarnLog("직원: 격납고 $25,000 조달 확인")
            if (state = "full")
                EarnNotifyStockFull("hangar", "격납고 재고 만재: 판매 필요")
            return true
        }
        if (!EarnSleep(500))
            return false
    }
    return EarnFail("직원: 격납고 조달 결과 미확인, 재요청 중단")
}

EarnStaffHangarPattern() => "i)^Hangar(?:\h+\$[0-9,]+)?$"

; 파견 뒤 회색 Hangar 이름이 일반/흰 글자 OCR에서 모두 사라진다(1008 실측). 격납고가 가득 차도 같다
; (1010 19:09 실측: 첫 행 글자 없이 "There is no more room to store cargo for / this property." 만 읽혀 줄 선택이 연속 실패).
; 직원 목록의 나머지 두 행과 첫 행 선택, 전체 작업 중·만재 문구를 함께 확인해 "busy"/"full" 을, 아니면 "" 을 돌려준다.
; 결제 판정에는 쓰지 않는다(두 상태 모두 Enter 를 누르지 않는다).
EarnStaffHangarBusyFrame(lines) {
    heading := EarnStaffUniqueRow(lines, "i)^THE VINEWOOD CLUB APP$")
    warehouse := EarnStaffUniqueRow(lines, "~Warehouse")
    bail := EarnStaffUniqueRow(lines, "~Bail Office")
    if (!heading || !warehouse || !bail || Abs(warehouse.y-heading.y-74) > 8
        || Abs(bail.y-heading.y-111) > 8 || !EarnMenuRowSelected({y:heading.y+37})
        || EarnMenuRowSelected(warehouse) || EarnMenuRowSelected(bail))
        return ""
    for row in lines
        if (Abs(row.y-heading.y-37) <= 10 && InStr(row.text, "$"))
            return ""
    detail := EarnStaffFooter(lines, {y:heading.y+111,h:22})
    text := StrLower(RegExReplace(detail, "[^A-Za-z]"))
    if (EarnStaffEditDistance(text, "yourhangarstaffmemberiscurrentlyoutonajob") <= 2)
        return "busy"
    if (EarnStaffEditDistance(text, "thereisnomoreroomtostorecargoforthisproperty") <= 2)
        return "full"
    return ""
}

; ready 는 선택된 Hangar 줄의 가격이 정확히 $25000 이고 설명이 보내기 문구일 때만이다.
EarnStaffReadHangar(deadline := 0) {
    for whiteText in [false, true] {
        lines := EarnReadScreen([25,125,450,300], whiteText, deadline)
        heading := EarnStaffUniqueRow(lines, "i)^THE VINEWOOD CLUB APP$")
        row := EarnStaffUniqueRow(lines, EarnStaffHangarPattern())
        if (!row && (frame := EarnStaffHangarBusyFrame(lines)))
            return frame
        if (!heading || !row || Abs(row.y-heading.y-37) > 8 || !EarnMenuRowSelected(row))
            continue
        price := -1
        for line in lines
            if (Abs(line.y-row.y) <= 10 && InStr(line.text, "$"))
                price := EarnReadDollars(line.text)
        detail := EarnStaffFooter(lines, {y:heading.y+37*3, h:22})
        ; 설명 문구는 한두 글자씩 깨져 읽힌다(1006 녹화: "Send yo r Hangar staff member out on a", "end your Hangar
        ; staff member outon a", "Send you Hangar staff membei oUton a"). 정확히 같아야 했던 탓에 그날 60번 모두 상태 미확인으로
        ; 건너뛰었다. 뒷부분은 통째로 빠지기도 해서("Fend yo r Hangar staff member out" / "jog.", 같은 날 22:17) "Hangar staff"
        ; 앞부분만 본다. 보내기는 "Send your", 작업 중은 "Your" 로 시작해 편집 거리 4 이상 떨어져 있다.
        letters := StrLower(RegExReplace(detail, "[^A-Za-z]"))
        at := InStr(letters, "hangarstaff")
        lead := at > 1 ? SubStr(letters, 1, at - 1) : ""
        if (lead != "" && EarnStaffEditDistance(lead, "sendyour") <= 2)
            return price = 25000 ? "ready" : "invalid"
        if (lead != "" && EarnStaffEditDistance(lead, "your") <= 2)
            return "busy"
        if (InStr(letters, "nomoreroom"))
            return "full"
    }
    return "invalid"
}

; 판독이 흔들려 창고 목록을 건너뛸 때는 그 목록 안에 있다는 것만은 확실하다. 다음 EarnStaffRoot 가
; 같은 줄을 다시 못 읽어 멈추지 않게(1005 08:59 실측) Backspace 한 번으로 직원 관리 목록에 돌아간다. 정상으로 끝까지 돈 뒤에도 같다.
EarnStaffCargoLeave() => EarnPress("Backspace") && EarnSleep(700)

EarnStaffCargoInOrder(current, index, count, visited) => IsObject(current) && current.index = index
    && current.count = count && !visited.Has(StrLower(current.name))

EarnStaffSameWarehouse(current, expected) {
    return IsObject(current) && IsObject(expected) && current.name = expected.name
        && current.index = expected.index && current.count = expected.count
}

; 선택 행의 흰 배경에서 이름과 가격을 읽는다. 회색인 작업 중/만재 행은 가격이 없어도 건너뛴다.
EarnStaffReadCargo(pending := false, deadline := 0) {
    heading := EarnStaffUniqueRow(EarnReadScreen([25,125,450,40], false, deadline), "i)^THE VINEWOOD CLUB APP$")
    if (!heading)
        return false
    selectedIndex := 0
    Loop 5 {
        if (EarnMenuRowSelected({y:heading.y + 37*A_Index})) {
            if (selectedIndex)
                return false
            selectedIndex := A_Index
        }
    }
    if (!selectedIndex)
        return false
    rowY := heading.y + 37*selectedIndex
    label := EarnStaffCargoLabel(EarnReadScreen([28,Round(rowY-17),434,35], false, deadline), rowY)
    detail := EarnStaffCargoDetail(EarnReadScreen([28,Round(heading.y+56),434,229], true, deadline), heading)
    if (!EarnMenuRowSelected({y:rowY}) || (deadline && A_TickCount >= deadline))
        return false
    if (!label) {
        ; 밝은 선택 막대에서 회색 이름이 사라져도 작업 중·만재는 결제 없이 건너뛴다.
        ; 요청 직후에는 이미 확인한 같은 인덱스·목록 크기일 때만 이전 이름을 유지한다.
        if (!detail || (detail.state != "busy" && detail.state != "full") || selectedIndex > detail.count)
            return false
        if (IsObject(pending) && (pending.index != selectedIndex || pending.count != detail.count))
            return false
        return {name:IsObject(pending) ? pending.name : "", price:-1, index:selectedIndex, count:detail.count, state:detail.state}
    }
    if (!detail) {
        if (IsObject(pending) && pending.name = label.name && pending.index = selectedIndex)
            return {name:label.name, price:label.price, index:selectedIndex, count:pending.count, state:"invalid"}
        return false
    }
    if (selectedIndex > detail.count)
        return false
    if (detail.state = "ready" && label.price != 7500) {
        if (!IsObject(pending) || pending.name != label.name || pending.index != selectedIndex || label.price != -1)
            return false
        detail.state := "invalid"
    }
    return {name:label.name, price:label.price, index:selectedIndex, count:detail.count, state:detail.state}
}

EarnStaffCargoLabel(lines, rowY) {
    if (!(lines is Array))
        return false
    name := "", price := -1
    for row in lines {
        if (Abs(row.y-rowY) > 10)
            return false
        if (InStr(row.text, "$")) {
            if (price != -1 || (price := EarnReadDollars(row.text)) < 0)
                return false
            if (RegExMatch(row.text, "^(.+?)\h+\$[0-9,]+$", &match)) {
                if (name != "")
                    return false
                name := match[1]
            } else if (!RegExMatch(row.text, "^\$[0-9,]+$") || row.x < 360)
                return false
        } else {
            if (name != "" || row.x >= 360)
                return false
            name := row.text
        }
    }
    if (!RegExMatch(name, "^[A-Za-z0-9][A-Za-z0-9 '&().-]*$"))
        return false
    return {name:name, price:price}
}

; 상세 첫 줄의 위치와 37px 행 간격으로 실제 1~5개 목록의 끝을 확인한다.
EarnStaffCargoDetail(lines, heading) {
    if (!(lines is Array) || !heading)
        return false
    found := false
    for row in lines {
        if (!RegExMatch(row.text, "^(?:Send your Warehouse|Your Warehouse|There is no more room)"))
            continue
        count := Round((row.y-heading.y-44)/37)
        if (found || count < 1 || count > 5 || Abs(row.y-heading.y-37*count-44) > 8)
            return false
        detail := EarnStaffFooter(lines, {y:heading.y+37*count,h:22})
        state := detail = "Send your Warehouse staff member out on a job." ? "ready"
            : detail = "Your Warehouse staff member is currently out on a job." ? "busy"
            : detail = "There is no more room to store cargo for this property." ? "full" : "invalid"
        if (state = "invalid")
            return false
        found := {state:state,count:count}
    }
    return found
}

EarnStaffReadBail(agent, &identityValid := false, deadline := 0, &identityRejected := false) {
    identityValid := false
    identityRejected := false
    lines := EarnStaffBailRows(agent, deadline)
    if (!EarnStaffBailIdentity(lines, agent)) {
        identityRejected := EarnStaffBailOtherSelected(lines, agent)
        full := EarnReadScreen([25,125,450,180], false, deadline)
        identityRejected := identityRejected || EarnStaffBailOtherSelected(full, agent)
        if (identityRejected)
            return "invalid"
        if (EarnStaffBailBusyFrame(full, agent)) {
            identityValid := true
            return "busy"
        }
        ; HDR에서 선택된 회색 요원명은 사라지고 일반 OCR의 작업 중 설명도 잘릴 수 있다.
        ; 같은 전체 영역을 흰 글자로 다시 읽어 작업 중 결과만 확인한다. 준비 상태로 추정하지 않는다.
        if (deadline && A_TickCount >= deadline)
            return "invalid"
        fullWhite := EarnReadScreen([25,125,450,180], true, deadline)
        identityRejected := EarnStaffBailOtherSelected(fullWhite, agent)
        if (identityRejected || (deadline && A_TickCount >= deadline))
            return "invalid"
        if (EarnStaffBailBusyFrame(fullWhite, agent)) {
            identityValid := true
            return "busy"
        }
        return "invalid"
    }
    identityValid := true
    last := EarnStaffBailLastRow(lines)
    detail := EarnReadScreen([28,Round(last.y+22),434,75], true, deadline)
    identityValid := EarnStaffBailIdentity(lines, agent)
    if (!identityValid)
        return "invalid"
    if (deadline && A_TickCount >= deadline)
        return "invalid"
    if (!(detail is Array))
        return "invalid"
    for row in detail
        lines.Push(row)
    return EarnStaffBailState(lines, agent)
}

EarnStaffBailOtherSelected(lines, agent) {
    if (agent != 1 && agent != 2)
        return true
    heading := EarnStaffUniqueRow(lines, "i)^THE VINEWOOD CLUB APP$")
    return heading && EarnMenuRowSelected({y:heading.y+37*(3-agent)})
}

; 작업 중으로 바뀐 선택 행은 밝은 막대 위 회색 글자라 일반 판독이 앞에 글자를 붙인다(1004 02:01 "I Agent 2", 05:24 "j Agent 2").
; 앱 제목은 읽혔는데 요원 행만 안 맞을 때 흰 글자 판독으로 한 번 더 본다.
EarnStaffBailRows(agent, deadline := 0) {
    lines := EarnReadScreen([25,125,450,115], false, deadline)
    if (EarnStaffBailIdentity(lines, agent) || !EarnStaffUniqueRow(lines, "i)^THE VINEWOOD CLUB APP$"))
        return lines
    white := EarnReadScreen([25,125,450,115], true, deadline)
    return EarnStaffBailIdentity(white, agent) ? white : lines
}

EarnStaffBailIdentity(lines, agent) {
    if (agent != 1 && agent != 2)
        return false
    heading := EarnStaffUniqueRow(lines, "i)^THE VINEWOOD CLUB APP$")
    if (!heading)
        return false
    observed := Map()
    for row in lines {
        if (!RegExMatch(row.text, "i)^Agent ([0-9]+|[Il])$", &match))
            continue
        ; 실제 밝은 화면의 Agent 1을 OCR이 Agent I로 읽는다. 행 위치·선택 검사는 그대로 둔다.
        agentNumber := RegExMatch(match[1], "i)^[Il]$") ? 1 : Integer(match[1])
        if (agentNumber < 1 || agentNumber > 2 || observed.Has(agentNumber) || Abs(row.y-heading.y-37*agentNumber) > 8)
            return false
        observed[agentNumber] := row
    }
    if (!observed.Has(agent) || !EarnMenuRowSelected(observed[agent])
        || EarnMenuRowSelected({y:heading.y+37*(agent = 1 ? 2 : 1)}))
        return false
    return true
}

; 비선택 회색 요원명이 OCR에서 빠져도 선택된 요원 신원과 고정된 두 행 구조는 확인한다.
EarnStaffBailLastRow(lines) {
    last := EarnStaffUniqueRow(lines, "i)^Agent 2$")
    if (last)
        return last
    heading := EarnStaffUniqueRow(lines, "i)^THE VINEWOOD CLUB APP$")
    return heading ? {y:heading.y+74,h:22} : false
}

EarnStaffBailState(lines, agent) {
    if (!EarnStaffBailIdentity(lines, agent))
        return "invalid"
    second := EarnStaffBailLastRow(lines)
    detail := EarnStaffFooter(lines, second)
    if (detail = "Send your Bail Office staff member out on a job.")
        return "ready"
    if (EarnStaffBailBusyText(detail))
        return "busy"
    return "invalid"
}

EarnStaffBailBusyText(detail) {
    text := StrLower(RegExReplace(detail, "[^A-Za-z]"))
    return EarnStaffEditDistance(text, "yourbailofficestaffmemberiscurrentlyoutonajob") <= 3
}

; 작업 중 판정만 허용한다. 이름이 사라진 행을 준비 상태나 결제 대상으로 추정하지 않는다.
EarnStaffBailBusyFrame(lines, agent) {
    if (agent != 1 && agent != 2)
        return false
    heading := EarnStaffUniqueRow(lines, "i)^THE VINEWOOD CLUB APP$")
    if (!heading || !EarnMenuRowSelected({y:heading.y+37*agent})
        || EarnMenuRowSelected({y:heading.y+37*(agent = 1 ? 2 : 1)}))
        return false
    for row in lines {
        if (RegExMatch(row.text, "i)^Agent ([0-9]+|[Il])$", &m)) {
            n := RegExMatch(m[1], "i)^[Il]$") ? 1 : Integer(m[1])
            if (n < 1 || n > 2 || Abs(row.y-heading.y-37*n) > 8)
                return false
        }
    }
    return EarnStaffBailBusyText(EarnStaffFooter(lines, {y:heading.y+74,h:22}))
}

; 회색 Manage Staff Members 줄은 판독이 매번 다르게 깨진다. "Mem ers"(1005 19:24), "SfaffMem>ers"·"Staff _Members"·
; "StaffMembers"·"S!affMembers"(같은 날 20:01 한 화면을 2초 간격으로 읽은 결과). 모양을 맞히는 대신 제목에서 여섯째 줄
; 자리(±12px)에 있고 글자만 남기면 "manag" 로 시작하는 줄 하나를 그 줄로 본다. 회색인지는 호출한 쪽이 밝기로 가린다.
; 첫 글자 M 이 빠진 "anageSta"·"anag+t" 도 있다(1006 02:24 녹화). 그래서 M 은 없어도 된다.
EarnStaffDimManageRow(lines) {
    heading := EarnStaffUniqueRow(lines, "i)^THE VINEWOOD CLUB APP$")
    if (!heading)
        return false
    found := false
    for row in lines {
        if (!row.HasOwnProp("y") || Abs(row.y - (heading.y + 37 * 6)) > 12)
            continue
        if (!RegExMatch(RegExReplace(row.text, "[^A-Za-z]"), "i)^m?anag"))
            continue
        if (found)
            return false
        found := row
    }
    return found
}

; 같은 이름의 행이 둘 이상이면 선택/금액 문맥을 특정할 수 없다.
; "~이름" 은 글자만 남겨 소문자로 비교해 편집 거리가 8글자 이상이면 2, 그보다 짧으면 1 이내일 때 맞다. 그 밖은 정규식이다.
EarnStaffTextMatch(text, pattern) {
    if (SubStr(pattern, 1, 1) != "~")
        return RegExMatch(text, pattern)
    want := StrLower(RegExReplace(SubStr(pattern, 2), "[^A-Za-z]"))
    got := StrLower(RegExReplace(text, "[^A-Za-z]"))
    return got != "" && EarnStaffEditDistance(got, want) <= (StrLen(want) >= 8 ? 2 : 1)
}

EarnStaffEditDistance(a, b) {
    prev := []
    Loop StrLen(b) + 1
        prev.Push(A_Index - 1)
    Loop Parse a {
        i := A_Index, ch := A_LoopField
        cur := [i]
        Loop StrLen(b)
            cur.Push(Min(prev[A_Index + 1] + 1, cur[A_Index] + 1, prev[A_Index] + (SubStr(b, A_Index, 1) == ch ? 0 : 1)))
        prev := cur
    }
    return prev[StrLen(b) + 1]
}

EarnStaffUniqueRow(lines, pattern) {
    if (!(lines is Array))
        return false
    found := false
    for row in lines {
        if (!IsObject(row) || !row.HasOwnProp("text"))
            return false
        if (EarnStaffTextMatch(row.text, pattern)) {
            if (found)
                return false
            found := row
        }
    }
    return found
}

; OCR은 가운데 좌표를 반환한다. 마지막 메뉴 행 아래의 설명만 위에서 아래로 합친다.
EarnStaffFooter(lines, lastRow) {
    if (!(lines is Array) || !IsObject(lastRow))
        return ""
    bottom := lastRow.y + lastRow.h / 2
    pieces := []
    for row in lines {
        if (row.y <= bottom + 8 || row.y >= bottom + 120)
            continue
        if (row.x - row.w / 2 < 25 || row.x + row.w / 2 > 475)
            return ""
        at := pieces.Length + 1
        Loop pieces.Length {
            if (row.y < pieces[A_Index].y) {
                at := A_Index
                break
            }
        }
        pieces.InsertAt(at, row)
    }
    detail := ""
    for row in pieces
        detail .= (detail = "" ? "" : " ") row.text
    return RegExReplace(Trim(detail), "\s+", " ")
}

; 이동 직후의 선택을 새 화면으로 다시 확인한 다음 Enter를 한 번 보낸다.
EarnStaffSelectEnter(pattern, maxPress) {
    if (!EarnStaffSelectText(pattern, maxPress))
        return false
    row := EarnStaffMenuTarget(pattern)
    if (!row || !EarnMenuRowSelected(row))
        return false
    return EarnPress("Enter") && EarnSleep(700)
}

; 투명 배경의 흰 메뉴 글자만 보완한다. 선택 행의 검정 글자는 일반 판독을 먼저 쓴다.
EarnStaffMenuTarget(pattern, &validMenu := false, &menuLines := "", &menuHeading := "") {
    validMenu := false
    for whiteText in [false,true] {
        ; 7번째 줄 자리(y=403)까지 읽어야 목록이 6줄에서 끝나는지 보이고, 위로 감아 도는 이동을 쓸 수 있다(1003 녹화: 맨 아래 Manage Staff Members 까지 Down 5번).
        lines := EarnReadScreen([25,125,450,300], whiteText)
        heading := EarnStaffUniqueRow(lines, "i)^THE VINEWOOD CLUB APP$")
        if (!heading)
            return false
        menuLines := lines, menuHeading := heading
        found := false
        for row in lines {
            if (!EarnStaffTextMatch(row.text, pattern))
                continue
            if (found)
                return false
            position := Round((row.y-heading.y)/37)
            if (position < 1 || position > 6 || Abs(row.y-heading.y-37*position) > 8)
                return false
            found := row
        }
        if (found) {
            validMenu := true
            return found
        }
    }
    validMenu := true
    return false
}

; 선택된 회색 행 글자가 사라진 직원 목록은 두 다른 이름·고정 위치와 유일 선택 막대로만 탐색한다.
; 목표 행 자체는 합성하지 않는다. Enter 직전에는 실제 목표 OCR과 선택을 다시 확인한다.
EarnStaffRootSlots(lines, heading) {
    if (!heading || !EarnStaffUniqueRow(lines, "i)^THE VINEWOOD CLUB APP$"))
        return false
    observed := 0, selectedSlot := 0, slots := []
    for index, name in ["Hangar", "Warehouse", "Bail Office"] {
        matches := 0
        for candidate in lines
            if (EarnStaffTextMatch(candidate.text, "i)^" name "$"))
                matches++
        if (matches > 1)
            return false
        row := EarnStaffUniqueRow(lines, "i)^" name "$")
        if (row) {
            if (Abs(row.y-heading.y-37*index) > 8)
                return false
            observed++
        }
        slot := {y:heading.y+37*index}
        if (EarnMenuRowSelected(slot)) {
            if (selectedSlot)
                return false
            selectedSlot := index
        }
        slots.Push(slot)
    }
    return observed >= 2 && selectedSlot ? slots : false
}

EarnStaffSelectText(pattern, maxPress) {
    Loop maxPress+1 {
        ; 키를 누른 직후 판독에서 앱 제목이 한 번 빠지면 메뉴가 아닌 것으로 보고 곧바로 꺼졌다(1007 04:00:49 「격납고 줄 선택 실패」,
        ; 녹화 1초 간격 프레임에는 제목이 다 보였다). 입력 없이 두 번 더 읽는다.
        row := false, lines := [], heading := false, validMenu := false, selectedVisible := false
        Loop 3 {
            row := EarnStaffMenuTarget(pattern, &validMenu, &lines, &heading)
            if (validMenu) {
                if (row && EarnMenuRowSelected(row))
                    return row
                if (IsObject(lines)) {
                    for candidate in lines {
                        if (EarnMenuRowSelected(candidate)) {
                            selectedVisible := true
                            break
                        }
                    }
                }
                ; 1008 04:37:55 Bail Office에서 제목은 읽혔지만 행이 0줄인데 Down이 전송됐다.
                ; 현재 선택 막대를 읽기 전에는 기본 Down을 보내지 말고 짧게 재판독한다.
                if (selectedVisible || A_Index = 3)
                    break
            }
            if (A_Index = 3 || !EarnSleep(400))
                break
        }
        agent := pattern = "i)^Agent [1Il]$" ? 1 : pattern = "i)^Agent 2$" ? 2 : 0
        verifiedBusyFrame := false
        verifiedBailRows := false
        if (validMenu && agent && !selectedVisible) {
            ; 파견된 현재 요원 글자는 HDR에서 사라질 수 있다. 현재 선택 슬롯의 작업 중 화면과
            ; 이동할 다른 요원의 실제 이름·고정 행 위치를 함께 확인한 뒤에만 두 행 탐색을 허용한다.
            for whiteText in [false,true] {
                full := EarnReadScreen([25,125,450,180], whiteText)
                fullHeading := EarnStaffUniqueRow(full, "i)^THE VINEWOOD CLUB APP$")
                currentAgent := EarnStaffBailBusyFrame(full, 1) ? 1 : EarnStaffBailBusyFrame(full, 2) ? 2 : 0
                if (!currentAgent || !fullHeading)
                    continue
                targetRow := EarnStaffUniqueRow(full, pattern)
                if (currentAgent != agent && (!targetRow || Abs(targetRow.y-fullHeading.y-37*agent) > 8))
                    continue
                lines := full, heading := fullHeading, row := targetRow
                verifiedBusyFrame := currentAgent = agent
                verifiedBailRows := true, selectedVisible := true
                break
            }
        }
        if (validMenu && !row && agent)
            verifiedBusyFrame := EarnStaffBailBusyFrame(lines, agent)
        if (validMenu && !row && !verifiedBusyFrame && pattern = EarnStaffHangarPattern())
            verifiedBusyFrame := EarnStaffHangarBusyFrame(lines)
        verifiedRootSlots := validMenu && row ? EarnStaffRootSlots(lines, heading) : false
        if (verifiedRootSlots)
            selectedVisible := true
        knownInitialRoot := row && pattern = "i)^Manage Staff Members$"
            && EarnStaffTextMatch(row.text, pattern)
        if (!validMenu || (!selectedVisible && !verifiedBusyFrame && !knownInitialRoot))
            return false
        ; 회색 직원 관리 행이 사라져도 전체 작업 중 설명을 발견한 자리에서 멈춘다.
        ; 다음 행으로 이동하면 설명도 사라져 Root의 작업 중 재확인이 실패한다(1008 실측).
        if (!row && pattern = "i)^Manage Staff Members$"
            && EarnStaffUniqueRow(lines, "i)^All of your staff members are currently"))
            return false
        if (row && EarnMenuRowSelected(row))
            return row
        ; 파견 후 글자가 사라진 선택 행은 작업 중 문구로만 유지한다. 이 결과로 결제하지 않는다.
        if (!row && agent && EarnStaffBailBusyFrame(lines, agent))
            return {y:heading.y+37*agent}
        if (!row && pattern = EarnStaffHangarPattern() && EarnStaffHangarBusyFrame(lines))
            return {y:heading.y+37}
        stepLines := lines
        if (verifiedRootSlots)
            stepLines := verifiedRootSlots
        if (verifiedBailRows)
            stepLines := [{y:heading.y+37},{y:heading.y+74}]
        if (row && EarnStaffListSeen(lines)) {
            ; 확인된 직원 목록은 Hangar·Warehouse·Bail Office 3줄이다. 회색 행 OCR 누락을 목록 끝으로
            ; 계산하면 Warehouse에서 Hangar로 가려 Down을 눌러 Bail Office로 간다(1007 13:08:41).
            ; 이동 방향은 실제 세 행의 선택 막대로 계산하고, 도착 확인은 위의 실제 OCR 목표 줄로 한다.
            stepLines := []
            Loop 3
                stepLines.Push({y:heading.y + 37*A_Index})
        }
        ; 앱 첫 화면은 맨 위 Claim Business Earnings에서 열리고 Manage Staff Members는 맨 아래다.
        ; 선택 막대 안의 검은 글자가 OCR에서 빠져 줄 위치 계산이 불완전해도 아래로 다섯 번 가지 않고 위로 한 번 돈다.
        uncertainKey := row && EarnStaffTextMatch(row.text, "i)^Manage Staff Members$") ? "Up" : "Down"
        key := EarnMenuStepKey(stepLines, heading, row, 425, &why, uncertainKey)
        if (A_Index = 1 && A_Index <= maxPress)
            EarnLog("앱 이동: " why)
        if (A_Index > maxPress || !EarnPress(key) || !EarnSleep(200))
            return false
    }
    return false
}
