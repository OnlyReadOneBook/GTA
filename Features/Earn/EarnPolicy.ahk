; 벙커 구매 계획. 화면 판독값으로 다음 20% 소모 경계를 고른다.
; 기본 1680초는 한 칸(20%) 소모마다 산다. 칸당 가격이 같아 자주 사도 손해가 없고,
; 경계 하나를 놓쳐도 다음 경계가 한 칸 뒤라 보급이 비지 않는다. 남은 보급으로 약 10분 배송 동안 생산을 잇는다.
; waitMs는 실제 잔량에 따른 관측 간격이다. 생산 속도로 구매 시각을 외삽하지 않는다.
; buy=true도 결제 허가는 아니다. 배송 중이 아닌지 확인하고, 확인창의 실제
; 가격을 EarnBunkerPriceAllowed로 검사한 뒤에만 결제한다.
EarnBunkerOrderPlan(supplyFraction, stockFraction, requestedSeconds := 1680) {
    if (!IsNumber(supplyFraction) || !IsNumber(stockFraction)
        || supplyFraction < 0 || supplyFraction > 1 || stockFraction < 0 || stockFraction > 1)
        return {buy: false, bars: 0, waitMs: 300000, reason: "invalid_read"}
    if (!IsNumber(requestedSeconds) || requestedSeconds < 1680 || requestedSeconds > 8400
        || Mod(requestedSeconds, 1680) != 0)
        return {buy: false, bars: 0, waitMs: 300000, reason: "invalid_interval"}

    ; 기존 MCT 막대 판독의 가득 참 기준을 유지한다. 생산 중단 중에는 구매하지 않는다.
    if (stockFraction >= 0.97)
        return {buy: false, bars: 0, waitMs: 300000, reason: "stock_full"}

    requestedBars := Round(requestedSeconds / 1680)
    missing := 1 - supplyFraction
    nearestBars := Round(missing * 5)
    boundaryLag := missing - nearestBars / 5
    ; 소모 경계에 도달한 뒤의 작은 후행 오차만 허용한다. 경계보다 먼저 사지 않는다.
    ; 현재 막대는 3px 간격 130표본이며 20%는 26표본이다. 이 판독값은 내부 보급량이
    ; 아니므로 실제 가격 검사도 필요하다. 빈 경계는 0 판독을 요구한다.
    atBoundary := nearestBars >= requestedBars && nearestBars <= 5
        && (nearestBars = 5 ? supplyFraction = 0 : boundaryLag >= -1.0e-9 && boundaryLag <= 0.003)
    if (atBoundary)
        return {buy: true, bars: nearestBars, waitMs: 0, reason: "boundary", supply: supplyFraction}

    ; 75%/55%처럼 이미 경계를 지나쳤다면 비싼 올림값으로 사지 않고 다음 경계를 기다린다.
    nextBars := Min(5, Max(requestedBars, Floor(missing * 5) + 1))
    remainingFraction := Max(0, nextBars / 5 - missing)
    nearBoundary := remainingFraction <= 0.03 + 1.0e-9
    return {buy: false, bars: nextBars, waitMs: nearBoundary ? 10000 : 60000, nearBoundary: nearBoundary, reason: "wait_boundary", supply: supplyFraction}
}

; OCR/화면 판독이 정확한 정수 금액을 돌려줄 때만 허용한다.
; 할인·이벤트 가격도 추측으로 허용하지 않는다. 알려진 가격 계약을 별도로 갱신해야 한다.
EarnBunkerPriceAllowed(price, bars) {
    return IsNumber(price) && IsNumber(bars) && bars >= 1 && bars <= 5
        && Mod(bars, 1) = 0 && price = bars * 15000
}

; 나이트클럽 창고 직원 재배정. 입력은 7품목의 현재 화면 판독 결과이며 변경하지 않는다.
; 각 행: {id, count, capacity, unlocked: 0/1, technician: 0..5}.
; 누락/중복/범위 오류는 ValueError. capacity는 화면값을 사용하고 저장층 수를 추정하지 않는다.
; 3품목 만재 알림 후 15분 이내 전량 판매하는 표준 계획 모델을 비교한다.
; 현재 배정 유지와 최대 21개 초기 조합만 비교하며 임의 중간 교대의 전역 최적화는 아니다.
; 모델 가정/생산 진행 경계/판매시간 민감도는 EarnWarehouseCycleChoice 및 docs/earner-policy.md 참조.
EarnWarehousePlan(goods) {
    priority := EarnWarehousePriority()
    if (!(goods is Array) || goods.Length != priority.Length)
        throw ValueError("EarnWarehousePlan: exactly seven goods are required")

    known := Map(), rows := Map(), assigned := Map()
    for id in priority
        known[id] := true
    for row in goods {
        if (!IsObject(row))
            throw ValueError("EarnWarehousePlan: each good must be an object")
        for field in ["id", "count", "capacity", "unlocked", "technician"] {
            if (!row.HasProp(field))
                throw ValueError("EarnWarehousePlan: missing " field)
        }
        if (Type(row.id) != "String" || !known.Has(row.id) || rows.Has(row.id))
            throw ValueError("EarnWarehousePlan: unknown or duplicate good")
        if (!IsInteger(row.count) || !IsInteger(row.capacity) || row.capacity <= 0
            || row.count < 0 || row.count > row.capacity)
            throw ValueError("EarnWarehousePlan: invalid count/capacity for " row.id)
        if (!IsInteger(row.unlocked) || (row.unlocked != 0 && row.unlocked != 1))
            throw ValueError("EarnWarehousePlan: unlocked must be 0 or 1")
        if (!IsInteger(row.technician) || row.technician < 0 || row.technician > 5)
            throw ValueError("EarnWarehousePlan: technician must be 0 through 5")
        if (row.technician && assigned.Has(row.technician))
            throw ValueError("EarnWarehousePlan: a technician is assigned more than once")
        if (row.technician)
            assigned[row.technician] := true
        ; 계획 작성 중에는 이 사본만 변경한다. 호출자의 관측 결과는 보존한다.
        rows[row.id] := {id: row.id, count: row.count, capacity: row.capacity,
            unlocked: row.unlocked, technician: row.technician}
    }

    choice := EarnWarehouseCycleChoice(rows, assigned.Count)
    wanted := Map()
    for id in choice.order {
        row := rows[id]
        if (wanted.Count < assigned.Count && row.unlocked && row.count < row.capacity)
            wanted[id] := true
    }
    ; 옮길 직원: 만재 품목을 비싼 순으로 먼저, 다음으로 목적 밖에서 생산 중인 품목을 싼 순으로.
    sources := []
    for id in priority
        if (rows[id].technician && rows[id].count >= rows[id].capacity)
            sources.Push(id)
    Loop priority.Length {
        id := priority[priority.Length - A_Index + 1]
        if (rows[id].technician && rows[id].count < rows[id].capacity && !wanted.Has(id))
            sources.Push(id)
    }
    moves := []
    for targetId in priority {
        target := rows[targetId]
        if (!wanted.Has(targetId) || target.technician || !sources.Length)
            continue
        source := rows[sources.RemoveAt(1)]
        moves.Push({technician: source.technician, from: source.id, to: targetId})
        target.technician := source.technician
        source.technician := 0
    }
    moves.modelReason := choice.reason
    moves.modelGain := choice.gain
    moves.modelCandidates := choice.candidates
    return moves
}

EarnWarehousePriority() {
    return ["south_american", "pharmaceutical", "cash", "cargo", "sporting", "organic", "printing"]
}

; 같은 최신 관측으로 생성한 첫 이동만 실행한다. 낮은 고정 순위로의 유효한 주기 계획도 허용한다.
EarnWarehouseMoveJustified(move, goods) {
    try {
        proposal := EarnWarehousePlan(goods)
        return proposal.Length && move.technician = proposal[1].technician
            && move.from = proposal[1].from && move.to = proposal[1].to
    } catch {
        return false
    }
}

; 단가는 실제 OCR stock.tsv의 판매액/수량. 주기는 표준 장비 업그레이드 분/개.
; 현재 이벤트 배수/공개 세션 보너스/특별 주문을 추정해 기본값에 섞지 않는다.
EarnWarehouseProductionModel() {
    return Map("south_american", [27000,120], "pharmaceutical", [11475,60],
        "cash", [4725,30], "cargo", [10000,70], "sporting", [5000,40],
        "organic", [2025,20], "printing", [1350,15])
}

EarnWarehouseCycleChoice(rows, staff) {
    base := [], full := 0
    ; 유지 후보: 생산 중 직원은 유지하고 만재로 빈 자리만 고정 수익 순위로 채운다.
    for id in EarnWarehousePriority() {
        row := rows[id]
        full += row.count >= row.capacity
        if (row.technician && row.unlocked && row.count < row.capacity)
            base.Push(id)
    }
    for id in EarnWarehousePriority()
        if (!EarnWarehouseOrderHas(base, id))
            base.Push(id)
    hold := {order: base, reason: "hold_model_score", gain: 0, candidates: 0}
    ; 3-full 이후는 판매 대기일 뿐 자동 중단이 아니다. 생산 중 직원은 보존하고 빈 직원만 보충한다.
    if (staff != 5 || full >= 3) {
        hold.reason := full >= 3 ? "sale_notice_continue" : "observed_staff_only"
        return hold
    }
    orders := EarnWarehouseCycleOrders(rows)
    if (!orders.Length)
        return hold
    model := EarnWarehouseProductionModel(), empty := Map()
    for id, row in rows
        empty[id] := {count: 0, capacity: row.capacity, unlocked: row.unlocked}
    emptyOrders := EarnWarehouseCycleOrders(empty)
    emptyCycles := [], rates := []
    for order in emptyOrders {
        sale := EarnWarehouseCycleRun(empty, order, model, false)
        if (sale.reached && sale.time > 0)
            emptyCycles.Push({time: sale.time, net: EarnWarehouseCycleNet(sale.counts, model)})
    }
    ; 주기가 1/2, 표준, 2배인 민감도. 현재 배속을 측정했다는 뜻은 아니다.
    for scale in [0.5, 1, 2] {
        for saleMinutes in [0, 15] {
            rho := 0
            for cycle in emptyCycles
                rho := Max(rho, cycle.net / (scale * cycle.time + saleMinutes))
            if (!rho)
                return hold
            rates.Push({scale: scale, saleMinutes: saleMinutes, rho: rho})
        }
    }
    baseline := EarnWarehouseCycleBounds(rows, base, model)
    if (!baseline)
        return hold
    baselineScore := EarnWarehouseCycleScore(baseline, rates)
    best := hold, bestScore := baselineScore
    for order in orders {
        bound := EarnWarehouseCycleBounds(rows, order, model)
        if (!bound)
            continue
        score := EarnWarehouseCycleScore(bound, rates)
        if (score > bestScore + 0.01) {
            bestScore := score
            best := {order: order, reason: "cycle_model_maximin", gain: score - baselineScore, candidates: orders.Length}
        }
    }
    best.candidates := orders.Length
    return best
}

; 각 후보와 유지 후보에 동일한 보수점수를 적용한다. 후보 하한 > 유지 상한의 무손해 판정은 아니다.
; 판매 중 새 생산 없음/판매 뒤 빈 재고·진행0의 계획모형이다. 판매 0/15분과 속도 3종의 6개 시나리오다.
; 각 시나리오의 판매시간은 빈 주기와 현재 후보에 동일하게 적용한다. 참조 후보별 점수가 판매시간에 단조라 양끝으로 중간 최저점을 포함한다.
; 실제 후보별 판매시간 차이까지 감싸는 보증은 아니다.
; 이미 쌓인 재고를 남은 시간만으로 나누지 않고 같은 빈 재고 주기의 rho를 기준으로 전환 가치를 비교한다.
EarnWarehouseCycleScore(bound, rates) {
    score := 1.0e30
    for rate in rates
        score := Min(score, bound.lowNet - rate.rho * (rate.scale * bound.slow + rate.saleMinutes))
    return score
}

EarnWarehouseOrderHas(order, id) {
    for item in order
        if (item = id)
            return true
    return false
}

; 직원 5명: 초기 선택 C(7,5) 이하. 보충 순서는 모든 후보에서 공통 고정 수익 순위다.
; 실행되지 않는 미래 보충 순서를 따로 최적화하지 않는다. 매 관측의 첫 배정만 실행하고 다시 관측한다.
EarnWarehouseCycleOrders(rows) {
    available := [], orders := []
    for id in EarnWarehousePriority()
        if (rows[id].unlocked && rows[id].count < rows[id].capacity)
            available.Push(id)
    wanted := Min(5, available.Length)
    if (!wanted)
        return orders
    Loop (1 << available.Length) {
        mask := A_Index - 1, selected := [], rest := []
        for i, id in available {
            if (mask & (1 << (i - 1)))
                selected.Push(id)
            else
                rest.Push(id)
        }
        if (selected.Length != wanted)
            continue
        order := selected.Clone()
        for id in rest
            order.Push(id)
        orders.Push(order)
    }
    return orders
}

; 고정목록에서 최초 5작업의 완료시각이 빨라지면 6/7번째의 시작시각도 늦어지지 않는다.
; 모든 초기 부분진행을 0 또는 한 주기로 둔 두 실행이 고정시각의 재고/3-full 도달시각을 감싼다.
; 보충시 즉시 배정, 생산 정지 없음의 모델 경계이며 실제 UI 지연/판매 후 생산의 보증은 아니다.
EarnWarehouseCycleBounds(rows, order, model) {
    slow := EarnWarehouseCycleRun(rows, order, model, false)
    fast := EarnWarehouseCycleRun(rows, order, model, true)
    if (!slow.reached || !fast.reached)
        return false
    lowStock := EarnWarehouseCycleRun(rows, order, model, false, fast.time)
    highStock := EarnWarehouseCycleRun(rows, order, model, true, slow.time)
    return {slow: slow.time, fast: fast.time,
        lowNet: EarnWarehouseCycleNet(lowStock.counts, model),
        highNet: EarnWarehouseCycleNet(highStock.counts, model)}
}

; horizon=-1이면 최초 3-full에서 멈추고, 0 이상이면 그 고정시각의 재고를 계산한다.
; 실제 게임에 입력하거나 재고를 수정하지 않는 최대 8개 이벤트의 순수 계산이다.
EarnWarehouseCycleRun(rows, order, model, phaseHigh, horizon := -1) {
    counts := Map(), phase := Map(), time := 0
    for id, row in rows {
        counts[id] := row.count
        phase[id] := phaseHigh ? model[id][2] : 0
    }
    Loop 8 {
        full := 0, active := []
        for id, row in rows
            full += counts[id] >= row.capacity
        if (horizon < 0 && full >= 3)
            return {counts: counts, time: time, reached: true}
        if (horizon >= 0 && time >= horizon)
            return {counts: counts, time: time, reached: full >= 3}
        for id in order
            if (active.Length < 5 && rows[id].unlocked && counts[id] < rows[id].capacity)
                active.Push(id)
        if (!active.Length)
            return {counts: counts, time: horizon >= 0 ? horizon : time, reached: full >= 3}
        step := 1.0e30
        for id in active
            step := Min(step, (rows[id].capacity - counts[id]) * model[id][2] - phase[id])
        if (horizon >= 0)
            step := Min(step, horizon - time)
        if (step < 0)
            throw ValueError("EarnWarehouseCycleRun: invalid production step")
        for id in active {
            progress := phase[id] + step, period := model[id][2]
            units := Floor(progress / period)
            counts[id] := Min(rows[id].capacity, counts[id] + units)
            phase[id] := progress - units * period
        }
        time += step
    }
    throw ValueError("EarnWarehouseCycleRun: event bound exceeded")
}

EarnWarehouseCycleNet(counts, model) {
    gross := 0
    for id, count in counts
        gross += count * model[id][1]
    return gross - Min(gross * 0.1, 100000)
}
