; === Features/Hacks/CasinoFingerprint.ahk ===
#Requires AutoHotkey v2.0

; 지문 스캐너 변수
global fingerprintRunning := false
global debugMode := false  ; 디버그 모드

; 좌표 설정 (1920x1080 기준)
global targetArea := {x: 950, y: 155, w: 385, h: 530}
global fingerprints := [
    {x: 482, y: 279, w: 102, h: 102, grid: {x: 0, y: 0}},  ; 왼쪽 위
    {x: 627, y: 279, w: 102, h: 102, grid: {x: 1, y: 0}},  ; 오른쪽 위
    {x: 482, y: 423, w: 102, h: 102, grid: {x: 0, y: 1}},  ; 왼쪽 중간 위
    {x: 627, y: 423, w: 102, h: 102, grid: {x: 1, y: 1}},  ; 오른쪽 중간 위
    {x: 482, y: 566, w: 102, h: 102, grid: {x: 0, y: 2}},  ; 왼쪽 중간 아래
    {x: 627, y: 566, w: 102, h: 102, grid: {x: 1, y: 2}},  ; 오른쪽 중간 아래
    {x: 482, y: 711, w: 102, h: 102, grid: {x: 0, y: 3}},  ; 왼쪽 아래
    {x: 627, y: 711, w: 102, h: 102, grid: {x: 1, y: 3}}   ; 오른쪽 아래
]

; 지문 패턴 체크 포인트 (각 지문의 고유 픽셀 위치)
; 흰색 라인이 있는 특정 위치들
GetFingerprintSignature(x, y, w, h) {
    ; 지문 중앙과 주변 몇 개 포인트의 픽셀 색상으로 시그니처 생성
    signature := ""
    
    ; 5x5 그리드로 샘플링
    gridSize := 5
    stepX := w // gridSize
    stepY := h // gridSize
    
    Loop gridSize {
        row := A_Index
        Loop gridSize {
            col := A_Index
            checkX := x + (col - 1) * stepX + stepX // 2
            checkY := y + (row - 1) * stepY + stepY // 2
            
            color := PixelGetColor(checkX, checkY, "RGB")
            
            ; 흰색 계열인지 체크 (0xC0C0C0 이상)
            if (color > 0xC0C0C0) {
                signature .= "1"
            } else {
                signature .= "0"
            }
        }
    }
    
    return signature
}

; 두 지문 시그니처 비교
CompareSignatures(sig1, sig2, tolerance := 5) {
    if (StrLen(sig1) != StrLen(sig2))
        return false
    
    differences := 0
    Loop Parse, sig1 {
        if (A_LoopField != SubStr(sig2, A_Index, 1))
            differences++
    }
    
    return differences <= tolerance
}

; 카지노 지문 스캐너 실행
ExecuteCasinoFingerprint() {
    global fingerprintRunning, debugMode
    
    if (fingerprintRunning || !IsGTAActive())
        return
    
    fingerprintRunning := true
    ShowTooltip("🔍 지문 스캔 시작...")
    
    ; 스크린 좌표 가져오기
    WinGetPos(&winX, &winY, &winW, &winH, "Grand Theft Auto V")
    
    ; 해상도 스케일 계산
    scaleX := winW / 1920
    scaleY := winH / 1080
    
    ; 타겟 지문 시그니처 가져오기
    targetX := winX + Round(targetArea.x * scaleX)
    targetY := winY + Round(targetArea.y * scaleY)
    targetW := Round(targetArea.w * scaleX)
    targetH := Round(targetArea.h * scaleY)
    
    ; 타겟 영역을 여러 섹션으로 나누어 시그니처 생성
    targetSig := GetFingerprintSignature(targetX, targetY, targetW, targetH)
    
    if (debugMode) {
        ShowTooltip("타겟 시그니처: " . SubStr(targetSig, 1, 20) . "...", 2000)
        Sleep(2000)
    }
    
    ; 매칭되는 지문 찾기
    matches := []
    
    for index, fp in fingerprints {
        fpX := winX + Round(fp.x * scaleX)
        fpY := winY + Round(fp.y * scaleY)
        fpW := Round(fp.w * scaleX)
        fpH := Round(fp.h * scaleY)
        
        fpSig := GetFingerprintSignature(fpX, fpY, fpW, fpH)
        
        if (CompareSignatures(targetSig, fpSig, 8)) {
            matches.Push(fp.grid)
            
            if (debugMode) {
                ShowTooltip("매치 발견: " fp.grid.x "," fp.grid.y, 1000)
                Sleep(1000)
            }
        }
        
        ; 4개 찾으면 중단
        if (matches.Length >= 4)
            break
    }
    
    ShowTooltip("🎯 " matches.Length "개 지문 발견", 1000)
    Sleep(500)
    
    ; 경로 생성 및 실행
    if (matches.Length > 0) {
        ExecuteFingerprintPath(matches)
    } else {
        ShowTooltip("❌ 매칭 지문을 찾을 수 없음", 2000)
    }
    
    fingerprintRunning := false
}

; 지문 선택 경로 실행
ExecuteFingerprintPath(matches) {
    currentX := 0
    currentY := 0
    
    for index, target in matches {
        ; 현재 위치에서 목표까지 이동
        xDiff := target.x - currentX
        yDiff := target.y - currentY
        
        ; 수평 이동
        if (xDiff > 0) {
            Loop xDiff {
                Send("{Blind}{d}")
                Sleep(25)
            }
        } else if (xDiff < 0) {
            Loop Abs(xDiff) {
                Send("{Blind}{a}")
                Sleep(25)
            }
        }
        
        ; 수직 이동
        if (yDiff > 0) {
            Loop yDiff {
                Send("{Blind}{s}")
                Sleep(25)
            }
        } else if (yDiff < 0) {
            Loop Abs(yDiff) {
                PressKey("w")
                Sleep(25)
            }
        }
        
        ; 선택
        Send("{Blind}{Enter}")
        Sleep(500)
        
        currentX := target.x
        currentY := target.y
    }
    
    ; 완료
    Sleep(200)
    Send("{Blind}{Tab}")
    ShowTooltip("✅ 지문 스캔 완료!", 2000)
}

; 디버그 모드 토글
ToggleFingerprintDebug() {
    global debugMode
    debugMode := !debugMode
    ShowTooltip(debugMode ? "🐛 디버그 모드 ON" : "디버그 모드 OFF", 1000)
}
