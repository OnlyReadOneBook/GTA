; 1920x1080 영어 나이트클럽 웹 UI. 판매 탭은 수량을 읽는 데만 쓴다.
; 재고는 OCR, 직원 연결은 선택된 품목의 사람 아이콘으로 각각 확인한다.
EarnWarehouseTask(manageSession := true) {
    if (manageSession && !EarnTaskMCTBegin())
        return false
    try {
        ok := EarnWarehouseManage()
    } finally {
        ended := manageSession ? EarnTaskMCTEnd() : true
    }
    return ok && ended
}

EarnWarehouseManage() {
    if (!EarnUIClick("mct_nightclub_card", 520, 525)
        || !EarnWaitSeen("nc_dj_menu", "", 5000))
        return EarnFail("창고: 나이트클럽 진입 실패")
    ; 한 번에 직원 하나를 옮기고, 다음 계획은 바뀐 전체 화면에서 새로 만든다.
    Loop 6 {
        goods := EarnWarehouseObserve(&stockOnly)
        if (!goods)
            return false
        EarnWarehouseSellNotice(goods)
        if (stockOnly) {
            EarnLog("창고: 전부 만재이거나 지난 확인과 수량·용량이 같음, 직원 관리 화면 생략")
            return EarnWarehouseReturn()
        }
        try moves := EarnWarehousePlan(goods)
        catch as e
            return EarnFail("창고: " e.Message)
        EarnLog("창고: 표준 판매주기 모델 " moves.modelReason ", 후보 " moves.modelCandidates
            . ", 보수점수 변화 $" Round(moves.modelGain) " (3품목 알림·판매 0~15분, 실제 수익 보장 아님)")
        if (!moves.Length) {
            EarnLog("창고: 현재 계획 유지, 추가 재배정 없음")
            return EarnWarehouseReturn()
        }
        if (A_Index = 6)
            return EarnFail("창고: 직원 5명 재배정 뒤 상태 불일치")
        move := moves[1]
        ; 옮긴 뒤 다음 관찰은 재고가 그대로여도 직원 화면을 다시 읽어 남은 이동을 계획한다.
        EarnWarehouseNeedStaff("reset")
        if (!EarnWarehouseMove(move, goods))
            return false
        EarnLog("창고: 직원 " move.technician " " move.from " → " move.to " 배정 확인")
    }
    return false
}

; 생산 정지 감지용 값. 만재가 아닌 품목이 하나도 없으면 생산이 멈춘 게 정상이라 빈 문자열이다.
EarnWarehouseStockKey(goods) {
    key := "", producing := false
    for row in goods {
        key .= (key = "" ? "" : " ") row.count "/" row.capacity
        if (row.count < row.capacity)
            producing := true
    }
    return producing ? key : ""
}

; 생산/판매로 수량이나 용량이 바뀌면 부분재고의 판매주기 후보가 달라질 수 있어 실제 배정을 다시 읽는다.
; 지난 확인과 같은 재고이거나 전부 만재면 직원 관리 화면에 들어가지 않고 stockOnly로 알린다.
EarnWarehouseObserve(&stockOnly := false) {
    stockOnly := false
    if (!EarnUIClick("nc_dj_menu", 500, 920) || !EarnSleep(400))
        return false
    ; 방치 중 30프레임 제한에서는 400ms 뒤에도 Sell Goods 가 덜 그려져 있다. 같은 화면을 1021 녹화 프레임으로
    ; 다시 읽으면 통과했는데 실행 중에는 304회 연속 실패했다. 입력 없이 0.7초 간격으로 최대 6번 읽는다.
    Loop 6 {
        lines := EarnReadScreen([728,130,880,420])
        goods := EarnWarehouseReadStock(lines)
        if (goods)
            break
        if (A_Index = 6) {
            if (IsObject(lines)) {
                texts := ""
                for line in lines
                    texts .= (texts = "" ? "" : " | ") line.x "," line.y " " line.text
                EarnLog("창고 OCR: " texts)
            }
            return EarnFail("창고: 7품목 현재/최대 재고 판독 실패")
        }
        if (!EarnSleep(700))
            return false
    }
    stockKey := EarnWarehouseStockKey(goods)
    EarnProductionObserve("nightclub", stockKey, stockKey != "")
    EarnLog("창고 재고: " EarnWarehouseGoodsSummary(goods))
    if (!EarnWarehouseNeedStaff(goods)) {
        stockOnly := true
        return goods
    }
    if (!EarnUIClick("nc_dj_menu", 500, 840)
        || !EarnWaitSeen("warehouse_title", [0.37,0.13,0.58,0.19], 3000))
        return EarnFail("창고: 직원 관리 화면 미확인")
    Loop 5 {
        technician := A_Index
        if (!EarnWarehouseSelect(technician))
            return false
        selected := EarnWarehouseSelectedGood()
        if (!selected)
            return EarnFail("창고: 직원 " technician "의 담당 품목 미확인")
        for row in goods {
            if (row.id = selected) {
                if (row.technician)
                    return EarnFail("창고: 같은 품목에 직원이 중복 판독됨")
                row.technician := technician
                row.unlocked := 1
            }
        }
    }
    ; 미배정 목적지는 글자가 밝고, 사람/체크 아이콘이 없는 활성 타일만 허용한다.
    lines := EarnReadScreen([728,548,876,264])
    if (!lines)
        return false
    for row in goods {
        if (!row.technician && row.count < row.capacity)
            row.unlocked := EarnWarehouseAvailable(row.id, lines) ? 1 : 0
    }
    EarnWarehouseKnownFull(goods)
    EarnWarehouseNeedStaff(goods, true)
    ; 재배정 판단의 근거가 로그에 남게 7품목의 재고와 담당을 적는다(1023: 만재 품목에 남은 직원이 자리 부족 탓인지 점검 간격 탓인지 수치로 못 가렸다).
    EarnLog("창고 직원: " EarnWarehouseGoodsSummary(goods, true))
    return goods
}

; "south_american 100/100 만재 직원3 | cash 20/60 직원1 | sporting 0/80 잠김" 꼴. staff=false 면 판매 탭 재고만 적는다.
EarnWarehouseGoodsSummary(goods, staff := false) {
    text := ""
    for row in goods {
        part := row.id " " row.count "/" row.capacity
        if (row.count >= row.capacity)
            part .= " 만재"
        if (staff)
            part .= row.technician ? " 직원" row.technician : row.unlocked ? " 비어있음" : " 잠김"
        text .= (text = "" ? "" : " | ") part
    }
    return text
}

; 만재 직원의 실제 담당을 읽은 긍정 근거만 보존한다. 그 직원을 옮긴 뒤에도 판매 후 빈 주기의 참조모형이 흔들리지 않는다.
; 열린 품목은 매번 현재 UI 판독이 우선이며, 과거 근거로 재배정 목적지를 허용하지 않는다.
EarnWarehouseKnownFull(goods) {
    static known := Map()
    for row in goods {
        if (row.count < row.capacity) {
            if (known.Has(row.id))
                known.Delete(row.id)
        } else if (row.technician && row.unlocked) {
            known[row.id] := row.capacity
        } else if (known.Has(row.id) && known[row.id] = row.capacity) {
            row.unlocked := 1
        }
    }
}

; 판매 탭 재고만 보고 직원 화면이 필요한지 정한다. checked=true 는 직원 화면을 막 읽었다는 표시다.
; 처음 보거나 수량/용량이 달라지면 필요하다. 전부 만재면 옮길 곳이 없다.
EarnWarehouseNeedStaff(goods, checked := false) {
    static last := ""
    if (goods = "reset") {
        last := ""
        return true
    }
    counts := Map(), open := 0
    for row in goods {
        counts[row.id] := row
        open += row.count < row.capacity
    }
    if (checked) {
        last := Map()
        for row in goods
            last[row.id] := {count: row.count, capacity: row.capacity}
        return true
    }
    if (!open)
        return false
    if (!IsObject(last))
        return true
    for id, prev in last {
        if (!counts.Has(id))
            return true
        row := counts[id]
        if (row.count != prev.count || row.capacity != prev.capacity)
            return true
    }
    return false
}

EarnWarehouseTiles() {
    static tiles := Map(
        "cargo", [728,548,282,78,"Cargo and Shipments"],
        "sporting", [1025,548,282,78,"Sporting Goods"],
        "south_american", [1322,548,282,78,"South American Imports"],
        "pharmaceutical", [728,641,282,78,"Pharmaceutical Research"],
        "organic", [1025,641,282,78,"Organic Produce"],
        "printing", [1322,641,282,78,"Printing & Copying"],
        "cash", [728,734,282,78,"Cash Creation"])
    return tiles
}

EarnWarehouseSelect(technician) {
    if (technician < 1 || technician > 5)
        return false
    x := 728 + (technician-1)*179
    area := [x/1920,228/1080,(x+166)/1920,392/1080]
    ; 보유 중인 다섯 직원의 얼굴을 확인한다. 고용 버튼이나 금액에는 클릭하지 않는다.
    if (!EarnUIReady("warehouse_title", [0.37,0.13,0.58,0.19])
        || !EarnSeen("warehouse_staff_" technician, area))
        return EarnFail("창고: 보유 직원 " technician " 화면 미확인")
    return EarnUIClick("warehouse_title", x+80, 300, [0.37,0.13,0.58,0.19])
        && EarnSleep(200)
}

EarnWarehouseSelectedGood() {
    if (!EarnUIReady("warehouse_title", [0.37,0.13,0.58,0.19])) {
        try EarnLog("[warehouse-read] stage=title hits=none templates=unread")
        return ""
    }
    selected := "", observed := ""
    for id, tile in EarnWarehouseTiles() {
        ; 사람 아이콘 하단은 체크/만재 느낌표의 원보다 아래에 있다.
        ; 만재 품목의 선택된 사람은 회색이고 느낌표가 겹친다. 관측한 하단 모양을 별도로 확인한다.
        area := [(tile[1]+230)/1920,(tile[2]+43)/1080,
            (tile[1]+270)/1920,(tile[2]+70)/1080]
        ; 1015 실패 GDI의 Sporting 발은 밝기 사본 한 픽셀 차이66, 다른 타일은180 이상이었다.
        normal := EarnSeen("warehouse_person_foot", area, , , 66)
        full := normal ? "skipped" : EarnSeen("warehouse_person_full_foot", area, , , 45)
        observed .= (observed = "" ? "" : ";") id ":normal=" normal ",full=" full
        if (normal || full) {
            if (selected != "") {
                try EarnLog("[warehouse-read] stage=multiple hits=" selected "," id " templates=" observed)
                return ""
            }
            selected := id
        }
    }
    if (selected = "") {
        try EarnLog("[warehouse-read] stage=none hits=none templates=" observed)
        try EarnWarehouseSnapReadFailure()
    }
    return selected
}


; 실패한 Main의 발 중앙색과 원본 크기 격자를 정리 입력 전에 보존한다. 고정 파일 두 개만 덮어쓴다.
EarnWarehouseSnapReadFailure() {
    hwnd := IsGTAActive()
    if (!hwnd)
        return
    started := A_TickCount
    previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        if (cw != 1920 || ch != 1080)
            return
        CoordMode("Pixel", "Screen")
        pixels := "time=" FormatTime(, "yyyy-MM-dd HH:mm:ss") " tick=" started
            . " client=" cx "," cy "," cw "," ch "`n"
        for id, tile in EarnWarehouseTiles() {
            ; 관측한 15x17 발의 가운데 한 줄만 읽는다. 총 105픽셀로 정리 지연을 제한한다.
            y := tile[2] + 57
            pixels .= id " y=" y " x=" (tile[1]+241) " colors="
            Loop 15 {
                x := tile[1] + 240 + A_Index
                pixels .= (A_Index = 1 ? "" : ",") Format("{:06X}", PixelGetColor(cx+x, cy+y))
            }
            pixels .= "`n"
        }
        path := A_Temp "\gta-warehouse-read-fail-pixels.txt"
        file := FileOpen(path, "w", "UTF-8")
        file.Write(pixels "elapsed_ms=" (A_TickCount-started) "`n")
        file.Close()
        if (!IsGTAActive())
            return
        SplitPath(A_LineFile, , &sourceDir)
        captureScript := sourceDir "\..\..\Core\ScreenCapture.ps1"
        result := RunWait('"' A_WinDir '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "'
            captureScript '" -Name "gta-warehouse-read-fail-grid" -X ' (cx+728) ' -Y ' (cy+548) ' -W 876 -H 264 -Scale 1', , "Hide")
        EarnLog("[warehouse-capture] exit=" result " elapsed_ms=" (A_TickCount-started)
            " pixels=" path " grid=" A_Temp "\claude\gta-warehouse-read-fail-grid.png")
    } finally DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
}

EarnWarehouseAvailable(id, lines) {
    if (!(lines is Array) || !EarnWarehouseTiles().Has(id))
        return false
    tile := EarnWarehouseTiles()[id], found := [], text := ""
    for row in lines {
        if (row.x >= tile[1]+5 && row.x <= tile[1]+222
            && row.y > tile[2]+6 && row.y < tile[2]+tile[4]-6) {
            text .= (text = "" ? "" : " ") row.text
            found.Push(row)
        }
    }
    if (text != tile[5] || !found.Length)
        return false
    for row in found
        if (!EarnWarehouseBrightLabel(row))
            return false
    return true
}

EarnWarehouseBrightLabel(row) {
    if (EarnAborted())
        return false
    previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        hwnd := IsGTAActive()
        if (!hwnd)
            return false
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        if (cw != 1920 || ch != 1080)
            return false
        CoordMode("Pixel", "Screen")
        bright := 0, total := 0
        y := Ceil(row.y-row.h/2)
        while (y < row.y+row.h/2) {
            x := Ceil(row.x-row.w/2)
            while (x < row.x+row.w/2) {
                color := PixelGetColor(cx+x, cy+y)
                bright += Min((color>>16)&255,(color>>8)&255,color&255) >= 210
                total += 1
                x += 2
            }
            y += 2
        }
        return total && bright >= 8 && bright/total >= 0.04
    } catch {
        return false
    } finally DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
}

; 판독이 글자를 하나도 못 내는 회색 글자 줄용. 흰 글자 픽셀(최소 채널 210 이상)이 없고, 무채색 회색(최소 채널 110~209,
; 채널 차 30 이하) 픽셀이 8% 넘으면 회색 글자가 있다고 본다. 1006 03:04 녹화: 회색 Manage Staff Members 자리는 21프레임 내내
; 판독 0줄이었고 흰 0·회색 22%, 바로 위 흰 글자 줄은 흰 12%였다.
EarnWarehouseGreyLabel(row) {
    if (EarnAborted())
        return false
    previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        hwnd := IsGTAActive()
        if (!hwnd)
            return false
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        if (cw != 1920 || ch != 1080)
            return false
        CoordMode("Pixel", "Screen")
        white := 0, grey := 0, total := 0
        y := Ceil(row.y-row.h/2)
        while (y < row.y+row.h/2) {
            x := Ceil(row.x-row.w/2)
            while (x < row.x+row.w/2) {
                color := PixelGetColor(cx+x, cy+y)
                r := (color>>16)&255, g := (color>>8)&255, b := color&255
                lo := Min(r, g, b), hi := Max(r, g, b)
                white += lo >= 210
                grey += lo >= 110 && lo < 210 && hi - lo <= 30
                total += 1
                x += 2
            }
            y += 2
        }
        return total && white = 0 && grey/total >= 0.08
    } catch {
        return false
    } finally DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
}

EarnWarehouseMove(move, goods) {
    source := false, target := false
    for row in goods {
        if (row.id = move.from)
            source := row
        if (row.id = move.to)
            target := row
    }
    if (!source || !target || !EarnWarehouseMoveJustified(move, goods)
        || source.technician != move.technician || !target.unlocked
        || target.technician || target.count >= target.capacity)
        return EarnFail("창고: 재배정 조건 불일치")
    if (!EarnWarehouseSelect(move.technician) || EarnWarehouseSelectedGood() != move.from)
        return EarnFail("창고: 이동 직전 직원의 원래 담당 미확인")
    if (!EarnWarehouseAvailable(move.to, EarnReadScreen([728,548,876,264])))
        return EarnFail("창고: 이동 직전 목적지 활성 상태 미확인")
    tile := EarnWarehouseTiles()[move.to]
    if (!EarnUIClick("warehouse_title", tile[1]+120, tile[2]+38, [0.37,0.13,0.58,0.19]))
        return false
    ; 품목을 누르면 'Assign Technician' 확인창이 뜬다(1003 실측: Pharmaceutical → "accrue Meth?").
    ; 그 문구를 읽은 뒤에만 Confirm 을 한 번 누른다. 요청·확정은 다시 보내지 않는다.
    if (!EarnWarehouseAssignDialog(3000))
        return EarnFail("창고: 배정 확인창 미확인. 재배정 재전송 중단")
    if (!EarnWarehouseDialogClick(1160, 612))
        return false
    deadline := A_TickCount + 5000
    Loop {
        if (EarnWarehouseSelectedGood() = move.to)
            return true
        if (A_TickCount >= deadline || !EarnSleep(200)) {
            ; 확인창이 남아 있으면 Cancel 로 닫아 AFK 방지가 읽을 수 있는 화면으로 돌린다.
            if (EarnWarehouseAssignDialog(0))
                EarnWarehouseDialogClick(756, 612)
            return EarnFail("창고: 새 담당 품목 미확인. 재배정 재전송 중단")
        }
    }
}

; 확인창 영역 OCR 에 제목과 질문 문구가 함께 있어야 한다. waitMs=0 이면 한 번만 읽는다.
EarnWarehouseAssignDialog(waitMs) {
    deadline := A_TickCount + waitMs
    Loop {
        lines := EarnReadScreen([540,420,810,140])
        text := ""
        if (lines is Array)
            for row in lines
                text .= " " row.text
        if (InStr(text, "Assign Technician") && InStr(text, "assign this technician")) {
            EarnLog("창고: 배정 확인창 확인 (" Trim(text) ")")
            return true
        }
        if (A_TickCount >= deadline || !EarnSleep(200))
            return false
    }
}

; 확인창에는 템플릿 대신 위 OCR 확인을 쓴다. 좌표는 1920x1080 클라이언트 기준.
EarnWarehouseDialogClick(x, y) {
    if (EarnAborted())
        return false
    hwnd := IsGTAActive()
    if (!hwnd)
        return EarnFail("창고: 확인창 클릭 전 GTA 포커스 없음")
    previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        if (cw != 1920 || ch != 1080)
            return EarnFail("창고: 미지원 해상도")
        DllCall("SetCursorPos", "int", cx+x, "int", cy+y)
        if (!EarnSleep(80))
            return false
        SendEvent("{Blind}{LButton down}")
        try Sleep(100)
        finally SendEvent("{Blind}{LButton up}")
        DllCall("SetCursorPos", "int", cx+1880, "int", cy+1040)
        return EarnSleep(450)
    } finally {
        DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
    }
}

; 만재 품목이 3개 이상일 때만 판매 알림을 표시한다. 개수와 무관하게 생산 가능한 다른 품목으로의 직원 배정은 계속한다.
; 만재 수가 바뀔 때만 로그·툴팁을 다시 띄우고, 오버레이에는 계속 표시한다.
EarnWarehouseSellNotice(goods) {
    count := 0
    for row in goods {
        if (row.capacity && row.count >= row.capacity)
            count += 1
    }
    if (count >= 3)
        EarnNotifyStockFull("nightclub", "나이트클럽 창고 만재 " count "개: 판매 필요")
    else
        EarnClearStockNotice("nightclub")
    return count
}

EarnWarehouseReturn() {
    return EarnUIClick("nc_dj_menu", 500, 596) && EarnSleep(500)
        && EarnUIBackToMCT("nc_dj_menu", 1)
}
