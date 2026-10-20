function Get-CiCheckPlan {
    param([string[]]$ChangedFiles, [switch]$Full)

    $suiteNames = @(
        'test-earner','test-earnledger','test-antiafk','test-altf4teleport','test-botwarp-stop','test-friendwarp','test-claw-stop','test-autoclick-stop','test-held-keys',
        'test-earnnav','test-earntasks','test-earnblip','test-earnpolicy','test-earnscreen','test-earnscreen-command',
        'test-earnvinewood','test-earnwarehouse-read','test-earnwarehouse','test-earnstaff',
        'test-afk-notification-command','test-afk-input-lock','test-arrow-color','test-cpuboost','test-discord-hud','test-discordhud-launch','test-overlay-place','test-memguard','test-earndj',
        'test-phone-call-template','test-earnocr','test-notification-dismiss','test-mct-seated-template',
        'test-bunker-templates','test-dj-templates','test-earnwarehouse-templates','test-afk-overlays','test-session-guard',
        'test-gui-input','test-perf-watch','test-fps-helper','test-screen-capture','test-gta-mode'
    )
    $selected = [Collections.Generic.List[object]]::new()
    $packageRequired = [bool]$Full
    $runFull = [bool]$Full
    $earnSuites = @('test-earner','test-earnnav','test-earntasks','test-earnblip','test-earnpolicy',
        'test-earnscreen','test-earnscreen-command','test-earnvinewood','test-earnwarehouse-read',
        'test-earnwarehouse','test-earnstaff','test-earnocr','test-earnledger','test-dj-templates','test-earnwarehouse-templates','test-phone-call-template')

    foreach ($rawPath in $ChangedFiles) {
        if ([string]::IsNullOrWhiteSpace($rawPath)) { continue }
        $path = $rawPath.Trim().Replace('\','/')
        while ($path.StartsWith('./')) { $path = $path.Substring(2) }
        if ($path -match '^tools/ci/' -or $path -match '^\.github/workflows/') {
            $runFull = $true
            $packageRequired = $true
            continue
        }
        if ($path -eq 'Main.ahk' -or $path -match '^Core/') {
            $runFull = $true
            $packageRequired = $true
            continue
        }
        if ($path -eq 'README.md' -or $path -match '^Core/' -or $path -match '^Features/.+\.ahk$' -or
            $path -match '^Images/.+\.(png|bmp|jpg|jpeg)$') { $packageRequired = $true }

        if ($path -match '^Features/Earn/') {
            switch -Regex ($path) {
                '^Features/Earn/EarnLedger\.ahk$' { $selected.AddRange(@('test-earnledger','test-earner')); break }
                '^Features/Earn/EarnStaff\.ahk$' { $selected.AddRange(@('test-earnstaff','test-earner','test-earnvinewood')); break }
                '^Features/Earn/EarnVinewood\.ahk$' { $selected.AddRange(@('test-earnvinewood','test-earner','test-earnstaff')); break }
                '^Features/Earn/Earner\.ahk$' { $selected.AddRange(@('test-earner','test-discord-hud')); break }
                '^Features/Earn/EarnWarehouse(Read)?\.ahk$' { $selected.AddRange(@('test-earnwarehouse-read','test-earnwarehouse','test-earnwarehouse-templates','test-earner')); break }
                default { $selected.AddRange($earnSuites); break }
            }
            continue
        }
        if ($path -match '^tools/earn-test/test-[^/]+\.ps1$') {
            $name = [IO.Path]::GetFileNameWithoutExtension($path)
            if ($suiteNames -contains $name) { $selected.Add($name) }
            else { $runFull = $true }
            continue
        }
        if ($path -match '^tools/tests/gta-perf-watch\.tests\.ps1$') { $selected.Add('test-perf-watch'); continue }
        if ($path -match '^tools/frame-watch/' -or $path -match '^tools/gta-perf-watch\.(ps1|vbs)$') { $selected.Add('test-perf-watch'); continue }
        if ($path -match '^tools/tests/fps-helper\.tests\.ps1$') { $selected.Add('test-fps-helper'); continue }
        if ($path -match '^tools/tests/screen-capture\.tests\.ps1$') { $selected.Add('test-screen-capture'); continue }
        if ($path -match '^tools/tests/gta-mode\.tests\.ps1$') { $selected.Add('test-gta-mode'); continue }
        if ($path -match '^Features/AntiAFK\.ahk$') {
            $selected.AddRange(@('test-antiafk','test-afk-overlays','test-afk-input-lock','test-afk-notification-command','test-notification-dismiss'))
            $packageRequired = $true
            continue
        }
        if ($path -match '^Features/AutoClick\.ahk$') { $selected.Add('test-autoclick-stop'); $packageRequired = $true; continue }
        if ($path -match '^Features/ClawMachine\.ahk$') { $selected.Add('test-claw-stop'); $packageRequired = $true; continue }
        if ($path -match '^Features/Teleport/AltF4Teleport\.ahk$') { $selected.Add('test-altf4teleport'); $packageRequired = $true; continue }
        if ($path -match '^Features/SessionSwitch\.ahk$') { $selected.Add('test-session-guard'); $packageRequired = $true; continue }
        if ($path -match '^Features/CpuBoost\.ahk$') { $selected.Add('test-cpuboost'); $packageRequired = $true; continue }
        if ($path -match '^Features/DiscordHUD\.ahk$') { $selected.AddRange(@('test-earner','test-discord-hud','test-discordhud-launch')); $packageRequired = $true; continue }
        if ($path -match '^Features/Overlay\.ahk$') { $selected.AddRange(@('test-earner','test-overlay-place')); $packageRequired = $true; continue }
        if ($path -match '^Features/MemoryGuard\.ahk$') { $selected.Add('test-memguard'); $packageRequired = $true; continue }
        if ($path -match '^Images/Earn/[^/]+/afk_(phone_frame|vinewood_title)\.png$' -or
            $path -eq 'tools/earn-test/build-afk-overlay-templates.ps1' -or $path -match '^tools/earn-test/afk-overlay-fixtures/') {
            $selected.Add('test-afk-overlays')
            if ($path.StartsWith('Images/')) { $packageRequired = $true }
            continue
        }
        if ($path -match '^Images/MCT/') { $selected.Add('test-mct-seated-template'); $packageRequired = $true; continue }
        if ($path -match '^Images/Bunker/') { $selected.Add('test-bunker-templates'); $packageRequired = $true; continue }
        if ($path -match '^Images/Earn/[^/]+/dj_confirm_(solomun|tale)\.png$') { $selected.Add('test-dj-templates'); $packageRequired = $true; continue }
        if ($path -match '^Images/') { $selected.AddRange(@('test-mct-seated-template','test-bunker-templates','test-dj-templates')); $packageRequired = $true; continue }
        if ($path -match '^README\.md$' -or $path -match '^docs/') { continue }
        if ($path -match '^tools/earn-test/') { $runFull = $true; continue }
        if ($path -match '^Features/') { $runFull = $true; $packageRequired = $true; continue }
        # Unknown paths within the repository are conservative: run all checks.
        $runFull = $true
    }

    if ($runFull) { $selected = [Collections.Generic.List[object]]::new(); $selected.AddRange($suiteNames) }
    $ordered = @($suiteNames | Where-Object { $selected -contains $_ })
    return [pscustomobject]@{ Full = $runFull; Suites = $ordered; PackageRequired = $packageRequired }
}
