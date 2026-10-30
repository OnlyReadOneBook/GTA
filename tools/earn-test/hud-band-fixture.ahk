; 시험용 HUD 격자. Core\Screen.ahk HealthHudGrid 와 같은 모양(15줄 x 265칸, 줄 1 = y 1046, 칸 1 = x 32)을 실측 색으로 만든다.
; healthPct 만큼 체력 칸(1~132)이 밝은 초록 4D8F4B, 나머지는 깎인 어두운 초록 24562D(1030 실측). armorPct 는 방어구 칸(137~265) 1A4B67.
; gain 은 HDR 밝기 배율(1010 실측 1.55, 255 포화). nIcon 이면 나침반 N 아이콘(검정 원·흰 글자)이 체력 칸 x 60~76 을 가린다(1010 실측).
; flash 는 빈사 깜빡임의 붉은 막대. hidden 이면 HUD 없는 어두운 바탕만 돌려준다.
FakeHudGrid(healthPct := 100, gain := 1.0, armorPct := 100, nIcon := false, flash := false, hidden := false) {
    fhFrame := FakeHudScale(0x0B1821, gain)
    fhBright := FakeHudScale(flash ? 0x8F2A2A : 0x4D8F4B, gain)
    fhDark := FakeHudScale(0x24562D, gain)
    fhBlue := FakeHudScale(0x1A4B67, gain)
    fhBlueDark := FakeHudScale(0x1E2A39, gain)
    fhGap := FakeHudScale(0x0D1923, gain)
    fhHealthCols := Round(132 * healthPct / 100)
    fhArmorCols := Round(129 * armorPct / 100)
    fhGrid := []
    Loop 15 {
        fhY := A_Index
        fhRow := []
        Loop 265 {
            fhX := A_Index
            if (hidden || fhY < 4 || fhY > 12)
                fhColor := fhFrame
            else if (fhX <= 132)
                fhColor := fhX <= fhHealthCols ? fhBright : fhDark
            else if (fhX <= 136)
                fhColor := fhGap
            else
                fhColor := fhX - 136 <= fhArmorCols ? fhBlue : fhBlueDark
            if (!hidden && nIcon && fhX >= 29 && fhX <= 45 && fhY >= 2 && fhY <= 14)
                fhColor := (fhX >= 34 && fhX <= 40 && fhY >= 6 && fhY <= 10) ? 0xFFFFFF : 0x000000
            fhRow.Push(fhColor)
        }
        fhGrid.Push(fhRow)
    }
    return fhGrid
}

FakeHudScale(color, gain) {
    fhR := Min(255, Round(((color >> 16) & 255) * gain))
    fhG := Min(255, Round(((color >> 8) & 255) * gain))
    fhB := Min(255, Round((color & 255) * gain))
    return (fhR << 16) | (fhG << 8) | fhB
}
