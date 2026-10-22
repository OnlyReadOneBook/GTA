#Requires -Version 5.1
<#
tools\steam-launch\launch-gta.ps1 의 localconfig.vdf 수정과 실행 분기를 임시 폴더에서만 검사한다.
실제 Steam·GTA 실행, 실제 userdata, 실제 로그 파일은 건드리지 않는다.
#>
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $repositoryRoot 'tools\steam-launch\launch-gta.ps1') -LibraryOnly

$script:count = 0
function Check([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL $Name" }
    $script:count++
}
function Throws([scriptblock]$Block) {
    try { & $Block; return $false } catch { return $true }
}

$nl = "`n"
$plain = @(
    '"UserLocalConfigStore"', '{',
    "`t`"Broadcast`"", "`t{", "`t`t`"Permissions`"`t`t`"1`"", "`t}",
    "`t`"WebStorage`"", "`t{",
    "`t`t`"UIStoreLocalSteamUIState`"`t`t`"{\`"News\`":{\`"NotifyAvailableGames\`":1}}`"",
    "`t`t`"Path`"`t`t`"C:\\Steam\\`"",
    "`t}",
    "`t`"friends`"", "`t{", "`t`t`"News`"", "`t`t{", "`t`t`t`"NotifyAvailableGames`"`t`t`"1`"", "`t`t}", "`t}",
    '}', ''
) -join $nl

$first = Set-SteamMarketingOff $plain
Check $first.Changed 'missing News block is added'
Check ($first.Text.EndsWith("`t`"news`"$nl`t{$nl`t`t`"NotifyAvailableGames`"`t`t`"0`"$nl`t}$nl}$nl")) 'lowercase news block is inserted as the last top-level child'
Check ($first.Text.StartsWith($plain.Substring(0, $plain.LastIndexOf('}')))) 'everything before the root close is kept byte for byte'
Check ($first.Text.Contains("`t`t`t`"NotifyAvailableGames`"`t`t`"1`"")) 'a nested News block is not top-level and stays untouched'
Check ($first.Text.Contains('{\"News\":{\"NotifyAvailableGames\":1}}')) 'quoted JSON with braces and escaped quotes is not parsed as structure'
$again = Set-SteamMarketingOff $first.Text
Check (-not $again.Changed -and $again.Text -ceq $first.Text) 'second pass is a no-op'

$on =($plain.Substring(0, $plain.LastIndexOf('}'))) + "`t`"News`"$nl`t{$nl`t`t`"NotifyAvailableGames`"`t`t`"1`"$nl`t}$nl}$nl"
$off = Set-SteamMarketingOff $on
Check $off.Changed 'enabled marketing value is switched off'
Check ($off.Text -ceq $on.Replace("`t`t`"NotifyAvailableGames`"`t`t`"1`"$nl`t}$nl}", "`t`t`"NotifyAvailableGames`"`t`t`"0`"$nl`t}$nl}")) 'only the top-level value changes'

$alreadyOff = $on.Replace("`t`"News`"$nl`t{$nl`t`t`"NotifyAvailableGames`"`t`t`"1`"", "`t`"news`"$nl`t{$nl`t`t`"notifyavailablegames`"`t`t`"0`"")
$same = Set-SteamMarketingOff $alreadyOff
Check (-not $same.Changed -and $same.Text -ceq $alreadyOff) 'keys match case-insensitively like Steam KeyValues'

$otherKey = ($plain.Substring(0, $plain.LastIndexOf('}'))) + "`t`"News`"$nl`t{$nl`t`t`"LastSeen`"`t`t`"5`"$nl`t}$nl}$nl"
$added = Set-SteamMarketingOff $otherKey
Check ($added.Changed -and $added.Text.Contains("`t`"News`"$nl`t{$nl`t`t`"NotifyAvailableGames`"`t`t`"0`"$nl`t`t`"LastSeen`"`t`t`"5`"")) 'existing News block gains the key'
Check (([regex]::Matches($added.Text, '(?i)"news"')).Count -eq 2) 'no duplicate top-level News block is added'

$crlf = $plain.Replace("`n", "`r`n")
$crlfOut = Set-SteamMarketingOff $crlf
Check ($crlfOut.Text.EndsWith("`t`"news`"`r`n`t{`r`n`t`t`"NotifyAvailableGames`"`t`t`"0`"`r`n`t}`r`n}`r`n")) 'CRLF files keep CRLF'

Check (Throws { Set-SteamMarketingOff ('"UserLocalConfigStore"' + $nl + '{' + $nl + "`t`"A`"`t`"open") }) 'unterminated string refuses to patch'
Check (Throws { Set-SteamMarketingOff ('"UserLocalConfigStore"' + $nl + '{' + $nl + "`t`"A`"`t`t`"1`"") }) 'unclosed root refuses to patch'
Check (Throws { Set-SteamMarketingOff ('"UserLocalConfigStore"' + $nl + '{' + $nl + "`tbare`t`"1`"" + $nl + '}') }) 'unquoted token refuses to patch'
Check (Throws { Set-SteamMarketingOff '' }) 'empty file refuses to patch'

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('steam-launch-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
$savedTemp = $env:TEMP
try {
    $env:TEMP = $fixture
    $config = Join-Path $fixture 'localconfig.vdf'
    [IO.File]::WriteAllText($config, $plain, (New-Object Text.UTF8Encoding($false)))
    Check (Update-SteamLocalConfig $config) 'file update reports a change'
    $bytes = [IO.File]::ReadAllBytes($config)
    Check (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)) 'no BOM is added to a BOM-less Steam file'
    Check ([IO.File]::ReadAllText($config) -ceq $first.Text) 'file content matches the in-memory patch'
    Check ([IO.File]::ReadAllText($config + '.steam-launch.bak') -ceq $plain) 'original file is kept as backup'
    Check (-not (Test-Path -LiteralPath ($config + '.steam-launch.tmp'))) 'temporary file does not remain'
    $stamp = (Get-Item -LiteralPath $config).LastWriteTimeUtc
    Check (-not (Update-SteamLocalConfig $config)) 'already patched file reports no change'
    Check ((Get-Item -LiteralPath $config).LastWriteTimeUtc -eq $stamp) 'already patched file is not rewritten'

    $bomConfig = Join-Path $fixture 'bom.vdf'
    [IO.File]::WriteAllText($bomConfig, $plain, (New-Object Text.UTF8Encoding($true)))
    Check (Update-SteamLocalConfig $bomConfig) 'BOM file is patched'
    $bomBytes = [IO.File]::ReadAllBytes($bomConfig)
    Check ($bomBytes[0] -eq 0xEF -and $bomBytes[1] -eq 0xBB -and $bomBytes[2] -eq 0xBF -and $bomBytes[3] -eq [byte][char]'"') 'existing BOM is kept once'

    $broken = Join-Path $fixture 'broken.vdf'
    [IO.File]::WriteAllText($broken, '"UserLocalConfigStore"' + $nl + '{', (New-Object Text.UTF8Encoding($false)))
    Check (Throws { Update-SteamLocalConfig $broken }) 'broken file throws'
    Check ([IO.File]::ReadAllText($broken) -ceq ('"UserLocalConfigStore"' + $nl + '{') -and -not (Test-Path -LiteralPath ($broken + '.steam-launch.bak'))) 'broken file is left untouched'

    # 실행 분기: Steam 실행 여부·실행 파일·프로세스 시작을 가짜로 바꿔 부른다.
    $steamRoot = Join-Path $fixture 'Steam'
    $userConfig = Join-Path $steamRoot 'userdata\12345\config'
    $null = New-Item -ItemType Directory -Force -Path $userConfig
    $userFile = Join-Path $userConfig 'localconfig.vdf'
    $script:fakeSteamExe = Join-Path $steamRoot 'steam.exe'
    $script:fakeRunning = $true
    $script:started = @()
    function Get-SteamExe { $script:fakeSteamExe }
    function Get-Process { param([string]$Name, $ErrorAction) if ($Name -eq 'steam' -and $script:fakeRunning) { [pscustomobject]@{ Name = 'steam' } } }
    function Start-Process { param([string]$FilePath, [string[]]$ArgumentList) $script:started += , @($FilePath, ($ArgumentList -join ' ')) }

    [IO.File]::WriteAllText($userFile, $plain, (New-Object Text.UTF8Encoding($false)))
    Invoke-GtaLaunch
    Check ([IO.File]::ReadAllText($userFile) -ceq $plain) 'running Steam leaves localconfig.vdf alone'
    Check ($script:started.Count -eq 1 -and $script:started[0][0] -eq $script:fakeSteamExe -and $script:started[0][1] -eq '-- steam://rungameid/3240220') 'running Steam gets the same launch as the old .url shortcut'

    $script:fakeRunning = $false
    Invoke-GtaLaunch
    Check ([IO.File]::ReadAllText($userFile) -ceq $first.Text) 'closed Steam gets marketing messages off before start'
    Check ($script:started.Count -eq 2 -and $script:started[1][1] -eq '-silent -- steam://rungameid/3240220') 'closed Steam starts silently with the GTA launch URL'

    [IO.File]::WriteAllText($userFile, '"UserLocalConfigStore"' + $nl + '{', (New-Object Text.UTF8Encoding($false)))
    Invoke-GtaLaunch
    Check ($script:started.Count -eq 3) 'a config that cannot be patched does not block the game launch'
    $log = [IO.File]::ReadAllText((Join-Path $fixture 'gta-macro.log'))
    Check ($log.Contains('[steam-launch]') -and $log.Contains('못 고침')) 'patch failure is logged to the macro log'
} finally {
    $env:TEMP = $savedTemp
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "PASS steam launch cases=$script:count (fixture only; no Steam or GTA process started)"
