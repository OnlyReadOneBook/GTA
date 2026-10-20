#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'check-selection.ps1')
$checks = 0
function Check($ok, [string]$message) {
    $script:checks++
    if (-not $ok) { throw "FAIL $message" }
}

$staff = Get-CiCheckPlan @('Features/Earn/EarnStaff.ahk')
Check (-not $staff.Full) 'staff source should be targeted'
Check (($staff.Suites -join ',') -eq 'test-earner,test-earnvinewood,test-earnstaff') 'staff source selects its dependent suites'
Check ($staff.PackageRequired) 'macro source requires package validation'

$safe = Get-CiCheckPlan @('Features/Earn/EarnVinewood.ahk')
Check (($safe.Suites -join ',') -eq 'test-earner,test-earnvinewood,test-earnstaff') 'Vinewood changes test vault, scheduler, and shared staff close path'

$testOnly = Get-CiCheckPlan @('tools/earn-test/test-earnstaff.ps1')
Check (($testOnly.Suites -join ',') -eq 'test-earnstaff') 'single suite change runs the matching test'
Check (-not $testOnly.PackageRequired) 'test-only changes do not package macro sources'

$docs = Get-CiCheckPlan @('docs/earner-policy.md')
Check ($docs.Suites.Count -eq 0 -and -not $docs.PackageRequired) 'documentation-only change skips regression suites and packaging'

$djTest = Get-CiCheckPlan @('tools/earn-test/test-dj-templates.ps1')
Check (-not $djTest.Full -and ($djTest.Suites -join ',') -eq 'test-dj-templates') 'DJ template regression selects itself'
$djTemplate = Get-CiCheckPlan @('Images/Earn/1920x1080/dj_confirm_tale.png')
Check (-not $djTemplate.Full -and ($djTemplate.Suites -join ',') -eq 'test-dj-templates' -and $djTemplate.PackageRequired) 'DJ confirmation pixels select their visual regression and package'
$earnCore = Get-CiCheckPlan @('Features/Earn/EarnCore.ahk')
Check ($earnCore.Suites -contains 'test-dj-templates') 'EarnSeen search-area changes include DJ pixel regression'
Check ($earnCore.Suites -contains 'test-earnledger') 'transaction wrapper changes include ledger persistence regression'
$otherImage = Get-CiCheckPlan @('Images/Earn/1920x1080/unknown.png')
Check ($otherImage.Suites -contains 'test-dj-templates') 'other shared image changes preserve DJ regression coverage'
foreach ($path in @('Images/Earn/1920x1080/afk_vinewood_title.png', 'Images/Earn/1920x1080/afk_phone_frame.png',
    'tools/earn-test/build-afk-overlay-templates.ps1', 'tools/earn-test/afk-overlay-fixtures/afk_vinewood_title-raw.png')) {
    $overlay = Get-CiCheckPlan @($path)
    Check (-not $overlay.Full -and ($overlay.Suites -join ',') -eq 'test-afk-overlays') "overlay source selects visual regression: $path"
    Check ($overlay.PackageRequired -eq $path.StartsWith('Images/')) "only deployable overlay pixels require packaging: $path"
}

$ci = Get-CiCheckPlan @('tools/ci/run-checks.ps1')
Check ($ci.Full -and $ci.Suites.Count -eq 42 -and $ci.PackageRequired) 'CI harness change runs full suite and package validation'

$workflow = Get-CiCheckPlan @('.github/workflows/ci.yml')
Check ($workflow.Full -and $workflow.Suites.Count -eq 42 -and $workflow.PackageRequired) 'workflow change runs full suite and package validation'

$gitStylePath = Get-CiCheckPlan @('./Features/Earn/EarnStaff.ahk')
Check (($gitStylePath.Suites -join ',') -eq 'test-earner,test-earnvinewood,test-earnstaff') 'leading ./ is normalized without losing dot-prefixed paths'

$unknown = Get-CiCheckPlan @('Features/NewFeature.ahk')
Check ($unknown.Full -and $unknown.Suites.Count -eq 42) 'unknown production paths conservatively run all suites'
$ledger = Get-CiCheckPlan @('Features/Earn/EarnLedger.ahk')
Check (-not $ledger.Full -and ($ledger.Suites -join ',') -eq 'test-earner,test-earnledger') 'ledger source selects transaction and scheduler checks'
$ledgerTest = Get-CiCheckPlan @('tools/earn-test/test-earnledger.ps1')
Check (($ledgerTest.Suites -join ',') -eq 'test-earnledger') 'ledger test selects its registered suite'

$frameWatch = Get-CiCheckPlan @('tools/frame-watch/frame-watch.ps1')
Check (-not $frameWatch.Full -and ($frameWatch.Suites -join ',') -eq 'test-perf-watch') 'frame watcher selects performance regressions'
$hud = Get-CiCheckPlan @('Features/DiscordHUD.ahk')
Check (-not $hud.Full -and ($hud.Suites -join ',') -eq 'test-earner,test-discord-hud,test-discordhud-launch' -and $hud.PackageRequired) 'HUD source selects lifecycle, visibility, and launch regressions'
$earner = Get-CiCheckPlan @('Features/Earn/Earner.ahk')
Check (($earner.Suites -join ',') -eq 'test-earner,test-discord-hud') 'scheduler hooks select HUD regression'
$hudTest = Get-CiCheckPlan @('tools/earn-test/test-discord-hud.ps1')
Check (($hudTest.Suites -join ',') -eq 'test-discord-hud') 'HUD test selects its registered suite'
$hudLaunchTest = Get-CiCheckPlan @('tools/earn-test/test-discordhud-launch.ps1')
Check (($hudLaunchTest.Suites -join ',') -eq 'test-discordhud-launch') 'HUD launch test selects its registered suite'
$statusOverlay = Get-CiCheckPlan @('Features/Overlay.ahk')
Check (-not $statusOverlay.Full -and ($statusOverlay.Suites -join ',') -eq 'test-earner,test-overlay-place' -and $statusOverlay.PackageRequired) 'status overlay selects content consumer and geometry regression'
$positionTest = Get-CiCheckPlan @('tools/earn-test/test-overlay-place.ps1')
Check (($positionTest.Suites -join ',') -eq 'test-overlay-place') 'position test selects its registered suite'
Write-Output "PASS CI check selection cases=$checks"
