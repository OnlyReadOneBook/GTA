; 시험용 HUD 격자. Core\Screen.ahk HealthHudGrid 와 같은 모양(15줄 x 265칸, 줄 1 = y 1046, 칸 1 = x 32)을 실측 색으로 만든다.
; healthPct 만큼 체력 칸(1~132)이 밝은 초록 4D8F4B, 나머지는 깎인 어두운 초록 24562D(1030 실측). armorPct 는 방어구 칸(137~265) 1A4B67.
; gain 은 HDR 밝기 배율(1010 실측 1.55, 255 포화). nIcon 이면 나침반 N 아이콘(검정 원·흰 글자)이 체력 칸 x 60~76 을 가린다(1010 실측).
; flash 는 빈사 깜빡임의 붉은 막대. hidden 이면 HUD 없는 어두운 바탕만 돌려준다.
FakeHudGrid(healthPct := 100, gain := 1.0, armorPct := 100, nIcon := false, flash := false, hidden := false) {
    scale(c) {
        r := Min(255, Round(((c >> 16) & 255) * gain)), g := Min(255, Round(((c >> 8) & 255) * gain)), b := Min(255, Round((c & 255) * gain))
        return (r << 16) | (g << 8) | b
    }
    frame := scale(0x0B1821), bright := scale(flash ? 0x8F2A2A : 0x4D8F4B), dark := scale(0x24562D)
    blue := scale(0x1A4B67), blueDark := scale(0x1E2A39), gap := scale(0x0D1923)
    healthCols := Round(132 * healthPct / 100), armorCols := Round(129 * armorPct / 100)
    grid := []
    Loop 15 {
        y := A_Index, row := []
        Loop 265 {
            x := A_Index
            if (hidden || y < 4 || y > 12)
                c := frame
            else if (x <= 132)
                c := x <= healthCols ? bright : dark
            else if (x <= 136)
                c := gap
            else
                c := x - 136 <= armorCols ? blue : blueDark
            if (!hidden && nIcon && x >= 29 && x <= 45 && y >= 2 && y <= 14)
                c := (x >= 34 && x <= 40 && y >= 6 && y <= 10) ? 0xFFFFFF : 0x000000
            row.Push(c)
        }
        grid.Push(row)
    }
    return grid
}
