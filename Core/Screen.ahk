; === 화면 템플릿 확인 (공용) ===
; Images\<folder>\<가로>x<세로>\<name>.png 를 GTA 클라이언트 영역 안에서 찾는다. 해상도 폴더에 템플릿이 없으면 false(찾지 못함)로 본다.
; 템플릿의 FF00FF 칸은 투명으로 친다(반투명 메뉴 바탕 위 글자는 글자와 어두운 바탕만 남기고 가장자리는 투명으로 떠 둔다).
global gImageRoot := A_ScriptDir "\Images"   ; 템플릿 폴더 뿌리 (시험 스크립트가 바꿔 쓸 수 있게 전역)
; 원본 템플릿이 안 맞을 때 차례로 찾아볼 밝기 사본 배율.
; 1010 실측: HDR 화면이 예전 템플릿보다 채널마다 약 1.55배 밝았다(템플릿 값 165 이상은 255로 포화).
; 이 배율 사본으로 MCT·벙커·DJ·창고 템플릿 16종이 차이 0~8로 맞았고, 다른 화면에는 맞지 않았다.
global gTemplateGains := ["1.55"]

; 실측 체력 막대의 가로 연속성. HUD 존재만 확인하며 전화·메뉴 제외는 소비자가 수행한다.
HealthHudVisible() {
    hwnd := IsGTAActive()
    if (!hwnd)
        return false
    previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        if (cw != 1920 || ch != 1080)
            return false
        CoordMode("Pixel", "Screen")
        ; 미니맵 나침반의 N 아이콘이 카메라 방향에 따라 막대 위(x 60~76 근처)로 돌아와 앞쪽 16점(x 40~85) 중 6점을 가렸다
        ; (1010 07:46 실측: MCT 앞에서 회전·메뉴가 'HUD 미확인'으로 반복 실패). 초록 막대 전체(x 40~164)를 4px 간격으로 본다.
        colors := []
        Loop 32
            colors.Push(PixelGetColor(cx + 40 + (A_Index-1)*4, cy + 1053))
        return HealthHudColors(colors)
    } catch {
        return false
    } finally {
        if (previous)
            DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
    }
}

HealthHudColors(colors) {
    if (colors.Length < 16)
        return false
    green := 0
    for color in colors {
        r := (color >> 16) & 255, g := (color >> 8) & 255, b := color & 255
        green += g >= 100 && g-r >= 40 && g-b >= 40 && Abs(r-b) <= 25
    }
    return green * 4 >= colors.Length * 3
}

; area 는 클라이언트 비율 [x1, y1, x2, y2] (0~1). 찾은 자리(화면 좌표)는 &fx, &fy.
TemplateSeen(folder, name, area := "", &fx := 0, &fy := 0, variation := 40) {
    global gImageRoot
    ; 보스 메뉴 줄(JobWarp\m_*)도 남긴다. 1024 22:14 SecuroServ CEO 줄이 떠 있는데 못 찾아 해제를 건너뛰었을 때 비교 기록이 없었다.
    probe := (folder = "Earn" && RegExMatch(name, "^(mct_seated_mansion(_bg)?|dj_resident(_right)?|warehouse_person_(full_)?foot)$"))
        || (folder = "JobWarp" && RegExMatch(name, "^m_"))
    hwnd := IsGTAActive()
    if (!hwnd) {
        if (probe)
            try MacroLog("screen-probe", "method=seen target=" name " active=0")
        return false
    }
    rect := "unread", roi := "unread", img := "unread", exists := "unread", dpi := "unread", original := "unread", found := false
    ; 배율이나 모니터가 바뀌어도 창 크기 조회와 이미지 검색을 같은 물리 픽셀 좌표로 한다 (인형 뽑기와 같은 방식)
    prev := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        if (probe)
            rect := cx "," cy "," cw "," ch
        img := gImageRoot "\" folder "\" cw "x" ch "\" name ".png"
        exists := FileExist(img)
        if (!exists) {
            ; 같은 템플릿은 한 번만 적는다 (선택/비선택 두 벌 중 하나만 있는 줄 템플릿처럼 없는 게 정상인 경우가 있다)
            static missing := Map()
            if (!missing.Has(img)) {
                missing[img] := 1
                MacroLog("screen", "템플릿 없음: " folder "\" cw "x" ch "\" name ".png")
            }
            return false
        }
        a := IsObject(area) ? area : [0, 0, 1, 1]
        CoordMode("Pixel", "Screen")
        found := false
        x1 := cx + Round(cw * a[1]), y1 := cy + Round(ch * a[2])
        x2 := cx + Round(cw * a[3]) - 1, y2 := cy + Round(ch * a[4]) - 1
        if (probe) {
            roi := x1 "," y1 "," x2 "," y2
            dpi := DllCall("GetThreadDpiAwarenessContext", "ptr")
        }
        try {
            found := ImageSearch(&fx, &fy, x1, y1, x2, y2, "*" variation " *Trans0xFF00FF " img)
            original := found
        } catch as e {
            MacroLog("screen", "ImageSearch 오류 " folder "\" name ": " e.Message)
        }
        if (!found) {
            ; 화면 밝기가 템플릿을 뜰 때와 다르면 같은 그림을 밝힌 사본으로 한 번 더 찾는다.
            for gainImg in TemplateGainImages(folder, cw "x" ch, name) {
                try found := ImageSearch(&fx, &fy, x1, y1, x2, y2, "*" variation " *Trans0xFF00FF " gainImg)
                if (found && TemplateGainBackgroundOK(gainImg, fx, fy))
                    break
                found := false
            }
        }
        return found
    } finally {
        if (prev)
            DllCall("SetThreadDpiAwarenessContext", "ptr", prev, "ptr")
        if (probe)
            try MacroLog("screen-probe", "method=seen target=" name " hwnd=" hwnd " client=" rect " roi=" roi
                " image=" img " exists=" (exists != "unread" ? !!exists : exists) " variation=" variation
                " dpi_search=" dpi " dpi_previous=" prev " original=" original " final=" found " xy=" fx "," fy)
    }
}

; TemplateSeen 이 찾은 자리(x, y)에서 name 템플릿이 정확히 같은 자리에 맞는지 본다.
; 글자만 남긴 템플릿 짝(<name>_bg: 글자에서 떨어진 바탕만 검정)으로 안내 상자의 어두운 바탕을 확인하는 데 쓴다.
TemplateAt(folder, name, x, y, variation := 90) {
    global gImageRoot
    probe := folder = "Earn" && RegExMatch(name, "^(mct_seated_mansion(_bg)?|dj_resident(_right)?|warehouse_person_(full_)?foot)$")
    hwnd := IsGTAActive()
    if (!hwnd) {
        if (probe)
            try MacroLog("screen-probe", "method=at target=" name " active=0")
        return false
    }
    rect := "unread", roi := "unread", img := "unread", exists := "unread", dpi := "unread", original := "unread", found := false
    originalX := "", originalY := "", originalAt := 0, gainX := "", gainY := "", originProbe := "not-needed"
    prev := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        if (probe)
            rect := cx "," cy "," cw "," ch
        img := gImageRoot "\" folder "\" cw "x" ch "\" name ".png"
        exists := FileExist(img)
        if (!exists)
            return false
        CoordMode("Pixel", "Screen")
        if (probe) {
            roi := x "," y "," Min(x + cw - 1, cx + cw - 1) "," Min(y + 60, cy + ch - 1)
            dpi := DllCall("GetThreadDpiAwarenessContext", "ptr")
        }
        ; 검색은 한 줄씩 왼쪽부터라, 같은 자리에서 맞으면 첫 결과가 바로 (x, y)다.
        try {
            ; HDR MCT title backgrounds are 536px wide. The old 401px search
            ; rectangle could never contain them. Keep the exact-origin check.
            original := ImageSearch(&fx, &fy, x, y, Min(x + cw - 1, cx + cw - 1), Min(y + 60, cy + ch - 1),
                "*" variation " *Trans0xFF00FF " img)
            originalAt := A_TickCount
            if (original)
                originalX := fx, originalY := fy
            if (original && fx = x && fy = y) {
                found := true
                return true
            }
        } catch as e {
            MacroLog("screen", "ImageSearch 오류 " folder "\" name ": " e.Message)
        }
        for gainImg in TemplateGainImages(folder, cw "x" ch, name) {
            try {
                gainFound := ImageSearch(&fx, &fy, x, y, Min(x + cw - 1, cx + cw - 1), Min(y + 60, cy + ch - 1),
                    "*" variation " *Trans0xFF00FF " gainImg)
                if (gainFound)
                    gainX := fx, gainY := fy
                if (gainFound && fx = x && fy = y
                    && TemplateGainBackgroundOK(gainImg, fx, fy)) {
                    found := true
                    return true
                }
            }
        }
        if (folder = "Earn" && name = "mct_seated_mansion_bg" && original = 1 && (originalX != x || originalY != y)) {
            try originProbe := TemplateOriginProbe(img, x, y, variation, originalAt)
            catch as e
                originProbe := "error=" e.Message
        }
        return false
    } finally {
        if (prev)
            DllCall("SetThreadDpiAwarenessContext", "ptr", prev, "ptr")
        if (probe)
            try MacroLog("screen-probe", "method=at target=" name " hwnd=" hwnd " client=" rect " roi=" roi
                " image=" img " exists=" (exists != "unread" ? !!exists : exists) " variation=" variation
                " dpi_search=" dpi " dpi_previous=" prev " original=" original " final=" found
                " origin=" x "," y " original_xy=" originalX "," originalY " gain_xy=" gainX "," gainY " origin_probe=" originProbe)
    }
}

; This is a later sample in the same process, not ImageSearch's internal frame.
TemplateOriginProbe(img, x, y, variation, searchedAt) {
    static nextSample := 0
    if (A_TickCount < nextSample)
        return "cooldown"
    nextSample := A_TickCount + 30000
    started := A_TickCount
    pixels := TemplateOriginPixels(img, x, y)
    stats := TemplateMaskStats(pixels.template, pixels.screen, pixels.w, pixels.h, variation)
    bitmap := A_Temp "\gta-mct-origin-followup.bmp"
    try TemplateOriginSave(pixels.screen, pixels.w, pixels.h, bitmap)
    catch as e
        bitmap := "error=" e.Message
    return ("followup sample_delta_ms=" (pixels.sampleAt - searchedAt) " elapsed_ms=" (A_TickCount - started)
        " mask=" stats.count " exceeded=" stats.exceeded " max_rgb=" stats.r "," stats.g "," stats.b
        " max_diff=" stats.diff " worst_xy=" (x + stats.x) "," (y + stats.y)
        " worst_rgb=" Format("{:06X}", stats.rgb) " size=" pixels.w "," pixels.h " bmp=" bitmap)
}

TemplateOriginSave(screen, w, h, path) {
    header := TemplateBitmapHeader(w, h, screen.Size)
    bitmapFile := FileOpen(path, "w", "UTF-8-RAW")
    try {
        if (bitmapFile.RawWrite(header) != header.Size || bitmapFile.RawWrite(screen) != screen.Size)
            throw Error("incomplete bitmap write")
    } finally {
        bitmapFile.Close()
    }
}

TemplateBitmapHeader(w, h, bytes) {
    if (w < 1 || h < 1 || bytes != w * h * 4 || bytes > 0xFFFFFFFF - 54)
        throw Error("invalid bitmap dimensions")
    header := Buffer(54, 0)
    NumPut("ushort", 0x4D42, header, 0)
    NumPut("uint", 54 + bytes, header, 2)
    NumPut("uint", 54, header, 10)
    NumPut("uint", 40, "int", w, "int", -h, "ushort", 1, "ushort", 32, header, 14)
    NumPut("uint", bytes, header, 34)
    return header
}

TemplateOriginPixels(img, x, y) {
    hbm := 0, hdc := 0, mdc := 0, capture := 0, old := 0
    try {
        hbm := LoadPicture(img)
        bm := Buffer(A_PtrSize = 8 ? 32 : 24, 0)
        if (!hbm || !DllCall("GetObject", "ptr", hbm, "int", bm.Size, "ptr", bm))
            throw Error("template bitmap unavailable")
        w := NumGet(bm, 4, "int"), h := NumGet(bm, 8, "int")
        if (w != 240 || h != 24)
            throw Error("unexpected mansion background size")
        bi := Buffer(40, 0)
        NumPut("uint", 40, "int", w, "int", -h, "ushort", 1, "ushort", 32, bi)
        template := Buffer(w * h * 4)
        hdc := DllCall("GetDC", "ptr", 0, "ptr")
        if (!hdc || DllCall("GetDIBits", "ptr", hdc, "ptr", hbm, "uint", 0, "uint", h, "ptr", template, "ptr", bi, "uint", 0) != h)
            throw Error("template pixels unavailable")
        mdc := DllCall("CreateCompatibleDC", "ptr", hdc, "ptr")
        bits := 0
        capture := DllCall("CreateDIBSection", "ptr", hdc, "ptr", bi, "uint", 0, "ptr*", &bits, "ptr", 0, "uint", 0, "ptr")
        if (!mdc || !capture || !bits)
            throw Error("capture buffer unavailable")
        old := DllCall("SelectObject", "ptr", mdc, "ptr", capture, "ptr")
        if (!old || old = -1)
            throw Error("capture selection failed")
        sampleAt := A_TickCount
        if (!DllCall("BitBlt", "ptr", mdc, "int", 0, "int", 0, "int", w, "int", h, "ptr", hdc, "int", x, "int", y, "uint", 0x00CC0020))
            throw Error("capture failed")
        DllCall("GdiFlush")
        screen := Buffer(w * h * 4)
        DllCall("RtlMoveMemory", "ptr", screen, "ptr", bits, "uptr", screen.Size)
        return {template: template, screen: screen, w: w, h: h, sampleAt: sampleAt}
    } finally {
        if (old && old != -1)
            DllCall("SelectObject", "ptr", mdc, "ptr", old)
        if (capture)
            DllCall("DeleteObject", "ptr", capture)
        if (mdc)
            DllCall("DeleteDC", "ptr", mdc)
        if (hdc)
            DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
        if (hbm)
            DllCall("DeleteObject", "ptr", hbm)
    }
}

TemplateMaskStats(template, screen, w, h, variation) {
    if (w < 1 || h < 1 || template.Size != w * h * 4 || screen.Size != template.Size)
        throw Error("invalid mask buffers")
    stats := {count: 0, exceeded: 0, r: 0, g: 0, b: 0, diff: -1, x: 0, y: 0, rgb: 0}
    Loop w * h {
        off := (A_Index - 1) * 4
        expected := NumGet(template, off, "uint") & 0xFFFFFF
        if (expected = 0xFF00FF)
            continue
        actual := NumGet(screen, off, "uint") & 0xFFFFFF
        r := (actual >> 16) & 255, g := (actual >> 8) & 255, b := actual & 255
        diff := Max(Abs(r - ((expected >> 16) & 255)), Abs(g - ((expected >> 8) & 255)), Abs(b - (expected & 255)))
        stats.count++, stats.exceeded += diff > variation
        stats.r := Max(stats.r, r), stats.g := Max(stats.g, g), stats.b := Max(stats.b, b)
        if (diff > stats.diff)
            stats.diff := diff, stats.x := Mod(A_Index - 1, w), stats.y := (A_Index - 1) // w, stats.rgb := actual
    }
    if (!stats.count)
        throw Error("empty template mask")
    return stats
}

; 원본 템플릿 대신 찾아볼 밝기 사본들의 경로. 사본은 %TEMP%\gta-template-gain\<배율>\<folder>\<해상도> 에
; 폴더 단위로 한 번 만들고, 원본 폴더의 파일 수·최근 수정 시각이 바뀌면 다시 만든다.
TemplateGainImages(folder, res, name) {
    global gImageRoot, gTemplateGains
    static ready := Map()
    out := []
    if (!IsSet(gTemplateGains) || !(gTemplateGains is Array))
        return out
    for gain in gTemplateGains {
        dst := A_Temp "\gta-template-gain\" gain "\" folder "\" res
        if (!ready.Has(dst))
            ready[dst] := TemplateGainBuild(gImageRoot "\" folder "\" res, dst, gain)
        if (ready[dst] && FileExist(dst "\" name ".png"))
            out.Push(dst "\" name ".png")
    }
    return out
}

TemplateGainBuild(src, dst, gain) {
    if (!DirExist(src))
        return false
    count := 0, newest := ""
    Loop Files src "\*.png" {
        count++
        if (StrCompare(A_LoopFileTimeModified, newest) > 0)
            newest := A_LoopFileTimeModified
    }
    stamp := "v2|" count "|" newest "|" gain  ; v2: 순백 사본의 바탕 표본(.bg)
    marker := dst "\.stamp"
    try {
        if (FileExist(marker) && FileRead(marker, "UTF-8") = stamp)
            return true
    }
    SplitPath(A_LineFile, , &coreDir)
    command := '"' A_WinDir '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "'
        . coreDir '\TemplateGain.ps1" -Source "' src '" -Destination "' dst '" -Gain ' gain
    try exitCode := RunWait(command, , "Hide")
    catch as e {
        MacroLog("screen", "밝기 사본 생성 실패 " dst ": " e.Message)
        return false
    }
    if (exitCode != 0) {
        MacroLog("screen", "밝기 사본 생성 실패 " dst ": exit=" exitCode)
        return false
    }
    try FileDelete(marker)
    try FileAppend(stamp, marker, "UTF-8")
    MacroLog("screen", "밝기 사본 생성 " dst)
    return true
}

; 흰 글자만 남긴 템플릿은 밝힌 사본이 순백 덩어리라 흰 벽·하늘에도 맞는다(1010 실측: 밝은 방 벽에서 mct_sit 사본이 맞음).
; TemplateGain.ps1 이 남긴 바탕 표본(<사본>.bg, 글자에서 떨어진 투명 칸)을 찾은 자리에서 읽어 3/4 이상이 순백이 아니어야 인정한다.
; 진짜 안내는 어둡거나 색 있는 바탕(검정·보라·빨강 버튼) 위에 있다. 표본 파일이 없는 사본은 글자 외 픽셀이 구별해 주므로 그대로 인정한다.
TemplateGainBackgroundOK(gainImg, fx, fy) {
    static cache := Map()
    bgFile := gainImg ".bg"
    if (!cache.Has(bgFile)) {
        points := []
        if (FileExist(bgFile)) {
            Loop Parse FileRead(bgFile), "`n", "`r" {
                if (A_LoopField = "")
                    continue
                xy := StrSplit(A_LoopField, ",")
                if (xy.Length = 2 && IsInteger(xy[1]) && IsInteger(xy[2]))
                    points.Push([Integer(xy[1]), Integer(xy[2])])
            }
        }
        cache[bgFile] := points
    }
    points := cache[bgFile]
    if (!points.Length)
        return true
    dark := 0
    for point in points {
        try c := PixelGetColor(fx + point[1], fy + point[2])
        catch
            return false
        if (Min((c >> 16) & 255, (c >> 8) & 255, c & 255) < 200)
            dark++
    }
    return dark * 4 >= points.Length * 3
}
