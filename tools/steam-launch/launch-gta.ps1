#Requires -Version 5.1
<#
GTA 바로가기(바탕화면·시작 메뉴)가 launch-gta.ahk 를 거쳐 부르는 실행기.
Steam 부팅 자동 실행을 끈 뒤(1022)로는 GTA 바로가기가 Steam 을 새로 켜는데, steam://rungameid 로 켜지면
Steam 메인 창과 Special Offers 창이 같이 뜬다. GTA 에는 둘 다 필요 없다.
- Special Offers: Steam 설정 > 인터페이스 "Notify me about additions or changes to my games..."
  (enable_marketing_messages) 가 끄는데, 값은 userdata\<계정>\config\localconfig.vdf 의 News\NotifyAvailableGames 다.
  Steam 은 끌 때 메모리 값으로 이 파일을 덮어쓰므로 Steam 이 꺼져 있을 때만 고친다.
- 메인 창: 바로가기와 같은 steam://rungameid 실행에 -silent 만 더해 띄우면 트레이에만 뜬다(Steam 의
  "컴퓨터 시작 시 실행"이 쓰는 그 플래그. 9/24~10/8 -silent 로 켜진 다섯 번은 logs\webhelper.txt 에 메인 창이
  숨겨진 채로만 있고 Special Offers 도 안 열렸다).
Steam 이 이미 켜져 있으면 설정 파일은 건드리지 않고 바로가기와 똑같이 GTA 실행만 넘긴다. 게임 입력·창 조작은 없다.
#>
[CmdletBinding()]
param([switch]$LibraryOnly)

$ErrorActionPreference = 'Stop'
$script:GtaAppId = '3240220'
$script:Utf8NoBom = New-Object Text.UTF8Encoding($false)

function Write-SteamLaunchLog([string]$Message) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' [steam-launch] ' + $Message + "`n"
    try { [IO.File]::AppendAllText((Join-Path $env:TEMP 'gta-macro.log'), $line, $script:Utf8NoBom) } catch { }
}

# localconfig.vdf 본문에서 최상위 News\NotifyAvailableGames 를 "0" 으로 맞춘 본문을 돌려준다.
# 따옴표 안의 { } 와 \" (WebStorage 의 JSON 값)는 구조로 세지 않는다. 구조가 예상과 다르면 던져서 파일을 쓰지 않게 한다.
function Set-SteamMarketingOff {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $depth = 0
    $key = $null
    $inNews = $false
    $newsBodyStart = -1
    $rootClose = -1
    $values = [Collections.Generic.List[object]]::new()
    $i = 0
    while ($i -lt $Text.Length) {
        $c = $Text[$i]
        if ([char]::IsWhiteSpace($c)) { $i++; continue }
        if ($c -eq '/' -and $i + 1 -lt $Text.Length -and $Text[$i + 1] -eq '/') {
            $end = $Text.IndexOf("`n", $i)
            $i = if ($end -lt 0) { $Text.Length } else { $end + 1 }
            continue
        }
        if ($c -eq '"') {
            $start = $i
            $i++
            while ($i -lt $Text.Length -and $Text[$i] -ne '"') { if ($Text[$i] -eq '\') { $i++ }; $i++ }
            if ($i -ge $Text.Length) { throw 'localconfig.vdf: 닫히지 않은 따옴표' }
            $i++
            $token = $Text.Substring($start + 1, $i - $start - 2)
            if ($null -eq $key) { $key = $token; continue }
            if ($inNews -and $depth -eq 2 -and $key -eq 'NotifyAvailableGames') {
                $values.Add([pscustomobject]@{ Start = $start; Length = $i - $start; Value = $token })
            }
            $key = $null
            continue
        }
        if ($c -eq '{') {
            if ($null -eq $key -and $depth -gt 0) { throw 'localconfig.vdf: 이름 없는 블록' }
            if ($depth -eq 1 -and $key -eq 'News' -and $newsBodyStart -lt 0) { $inNews = $true; $newsBodyStart = $i + 1 }
            $depth++
            $key = $null
            $i++
            continue
        }
        if ($c -eq '}') {
            if ($null -ne $key) { throw 'localconfig.vdf: 값 없는 키' }
            $depth--
            if ($depth -lt 0) { throw 'localconfig.vdf: 여는 괄호 없이 닫힘' }
            if ($depth -eq 1) { $inNews = $false }
            if ($depth -eq 0) { $rootClose = $i }
            $i++
            continue
        }
        throw ('localconfig.vdf: 예상하지 못한 문자 ' + $c)
    }
    if ($depth -ne 0 -or $rootClose -lt 0) { throw 'localconfig.vdf: 최상위 블록이 닫히지 않음' }

    if ($values.Count) {
        $result = $Text
        for ($n = $values.Count - 1; $n -ge 0; $n--) {
            $v = $values[$n]
            if ($v.Value -ne '0') { $result = $result.Remove($v.Start, $v.Length).Insert($v.Start, '"0"') }
        }
        return [pscustomobject]@{ Text = $result; Changed = ($result -cne $Text) }
    }
    $entry = "`t`t`"NotifyAvailableGames`"`t`t`"0`""
    if ($newsBodyStart -ge 0) {
        return [pscustomobject]@{ Text = $Text.Insert($newsBodyStart, $newline + $entry); Changed = $true }
    }
    # 지금 클라이언트의 설정 이름이 news\NotifyAvailableGames 라 새 블록은 소문자로 만든다(찾을 때는 대소문자를 가리지 않는다).
    $block = "`t`"news`"" + $newline + "`t{" + $newline + $entry + $newline + "`t}" + $newline
    return [pscustomobject]@{ Text = $Text.Insert($rootClose, $block); Changed = $true }
}

# 파일 하나를 고친다. 바뀔 때만 같은 폴더의 임시 파일로 쓰고 원본은 .steam-launch.bak 으로 남긴 채 바꿔 넣는다.
function Update-SteamLocalConfig([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = $script:Utf8NoBom.GetString($bytes, $(if ($hasBom) { 3 } else { 0 }), $bytes.Length - $(if ($hasBom) { 3 } else { 0 }))
    $patch = Set-SteamMarketingOff $text
    if (-not $patch.Changed) { return $false }
    $temp = $Path + '.steam-launch.tmp'
    try {
        [IO.File]::WriteAllText($temp, $patch.Text, (New-Object Text.UTF8Encoding($hasBom)))
        [IO.File]::Replace($temp, $Path, $Path + '.steam-launch.bak')
    } catch {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        throw
    }
    return $true
}

function Get-SteamExe {
    $exe = $null
    try { $exe = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -Name SteamExe -ErrorAction Stop).SteamExe } catch { }
    if ($exe) { $exe = $exe.Replace('/', '\') }
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { $exe = Join-Path ${env:ProgramFiles(x86)} 'Steam\steam.exe' }
    return $exe
}

function Invoke-GtaLaunch {
    $steamExe = Get-SteamExe
    $arguments = @('--', ('steam://rungameid/' + $script:GtaAppId))
    if (Get-Process -Name steam -ErrorAction SilentlyContinue) {
        Write-SteamLaunchLog 'Steam 이 켜져 있어 설정 파일은 그대로 두고 GTA 실행만 넘김'
    } else {
        $arguments = @('-silent') + $arguments
        $userdata = Join-Path (Split-Path -Parent $steamExe) 'userdata'
        foreach ($config in @(Get-ChildItem -Path (Join-Path $userdata '*\config\localconfig.vdf') -File -ErrorAction SilentlyContinue)) {
            try {
                if (Update-SteamLocalConfig $config.FullName) { Write-SteamLaunchLog ('Special Offers 끔: ' + $config.FullName) }
            } catch {
                Write-SteamLaunchLog ('Special Offers 설정을 못 고침(' + $config.FullName + '): ' + $_.Exception.Message)
            }
        }
    }
    Start-Process -FilePath $steamExe -ArgumentList $arguments
    Write-SteamLaunchLog ('실행: "' + $steamExe + '" ' + ($arguments -join ' '))
}

if (-not $LibraryOnly) { Invoke-GtaLaunch }
