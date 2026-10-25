#Requires -Version 5.1
<#
Read-only tests of the production stock parser. stock.tsv contains only the
23 OCR lines from earn-warehouse-stock.png, crop (728,130,880,420), Scale=2.
No image, account name, desktop capture, game process or UI input is needed.
#>
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")

$ErrorActionPreference = 'Stop'
$sourceFile = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\Features\Earn\EarnWarehouseRead.ahk'))
$fixtureFile = Join-Path $PSScriptRoot 'test-earnwarehouse-read-fixtures\stock.tsv'
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global testChecks := 0
try {
    RunWarehouseReadTests()
    FileAppend("PASS EarnWarehouseRead cases=" testChecks " (no game input)`n", "*")
    ExitApp(0)
} catch as testFailure {
    FileAppend("FAIL EarnWarehouseRead: " testFailure.Message "`n", "**")
    ExitApp(1)
}

RunWarehouseReadTests() {
    Check(!EarnWarehouseReadStock(false), "failed OCR is rejected")
    Check(!EarnWarehouseReadStock(Map()), "non-array is rejected")
    Check(!EarnWarehouseReadStock([]), "empty array is rejected")
    rows := LoadRows()
    goods := EarnWarehouseReadStock(rows)
    Check(goods is Array && goods.Length = 7, "actual OCR reads exactly seven goods")
    expected := [["cargo",29,50],["sporting",51,100],["south_american",10,10],
        ["pharmaceutical",16,20],["organic",70,80],["printing",44,60],["cash",29,40]]
    for index, item in expected {
        parsed := goods[index]
        Check(parsed.id = item[1] && parsed.count = item[2] && parsed.capacity = item[3]
            && parsed.unlocked = 0 && parsed.technician = 0, "actual stock " item[1])
    }
    Check(rows.Length = 23 && rows[1].text = "Cargo and Shipments" && !rows[1].HasOwnProp("id"), "parser preserves input")
    reversed := []
    for item in rows
        reversed.InsertAt(1, item)
    reversedGoods := EarnWarehouseReadStock(reversed)
    Check(reversedGoods.Length = 7 && reversedGoods[1].count = 29 && reversedGoods[7].id = "cash", "OCR line order does not join unrelated tiles")

    rows := LoadRows()
    RemoveText(rows, "Cargo and Shipments")
    Check(!EarnWarehouseReadStock(rows), "missing name is rejected")
    rows := LoadRows()
    RemoveText(rows, "29/50")
    Check(!EarnWarehouseReadStock(rows), "missing quantity is rejected")
    rows := LoadRows()
    rows.Push(FindRow(rows, "Cargo and Shipments").Clone())
    Check(!EarnWarehouseReadStock(rows), "duplicate name is rejected")
    rows := LoadRows()
    rows.Push(StockRow("Cargo and Shipments", 1300, 162))
    Check(!EarnWarehouseReadStock(rows), "known name duplicated into another tile is rejected")
    rows := LoadRows()
    rows.Push(FindRow(rows, "29/50").Clone())
    Check(!EarnWarehouseReadStock(rows), "identical duplicate quantity is rejected")
    rows := LoadRows()
    rows.Push(StockRow("30/50"))
    Check(!EarnWarehouseReadStock(rows), "conflicting duplicate quantity is rejected")
    ; 1025 13:11 실제 OCR(방치 중): 이름 한 글자가 틀려도 위치·수량으로 읽는다. 이전에는 82회 연속 판독 실패였다.
    rows := LoadRows()
    FindRow(rows, "Cargo and Shipments").text := "Cargo & Shipments"
    goods := EarnWarehouseReadStock(rows)
    Check(goods && goods[1].count = 29, "garbled name with the same first word is read")
    rows := LoadRows()
    FindRow(rows, "Sporting Goods").text := "Sportina Goods"
    goods := EarnWarehouseReadStock(rows)
    Check(goods && goods[2].count = 51, "Sportina Goods is read")
    rows := LoadRows()
    RemoveText(rows, "51/100")
    FindRow(rows, "Sporting Goods").text := "Sportin$uSterJ243 51/100"
    goods := EarnWarehouseReadStock(rows)
    Check(goods && goods[2].count = 51 && goods[2].capacity = 100, "quantity glued to a garbled name is read")
    rows := LoadRows()
    RemoveText(rows, "51/100")
    FindRow(rows, "Sporting Goods").text := "3:4751/100"
    Check(!EarnWarehouseReadStock(rows), "quantity glued to digits is rejected")
    rows := LoadRows()
    FindRow(rows, "Sporting Goods").text := "Xportin Goods"
    Check(!EarnWarehouseReadStock(rows), "name with a different first word is rejected")
    rows := LoadRows()
    FindRow(rows, "Cargo and Shipments").text := "cargo and shipments"
    Check(!EarnWarehouseReadStock(rows), "name matching is exact")
    rows := LoadRows()
    FindRow(rows, "29/50").x := 1552
    Check(!EarnWarehouseReadStock(rows), "quantity in another tile is rejected")
    rows := LoadRows()
    FindRow(rows, "Cargo and Shipments").y := 700
    Check(!EarnWarehouseReadStock(rows), "special-order name cannot replace normal name")
    for invalid in ["51/50", "0/0", "-1/50", "29/5O", "29/5000", "29/50 1", "029/50"] {
        rows := LoadRows()
        FindRow(rows, "29/50").text := invalid
        Check(!EarnWarehouseReadStock(rows), "invalid quantity " invalid)
    }
    rows := LoadRows()
    FindRow(rows, "29/50").text := "0 / 1"
    goods := EarnWarehouseReadStock(rows)
    Check(goods && goods[1].count = 0 && goods[1].capacity = 1, "actual positive capacity is observed rather than inferred")
    rows := LoadRows()
    rows.Push(StockRow("Cargo and Shipments", 900, 650), StockRow("6/6", 1550, 650),
        StockRow("South American Imports", 1300, 700), StockRow("2/2", 1550, 700))
    goods := EarnWarehouseReadStock(rows)
    Check(goods && goods[1].count = 29 && goods[3].count = 10, "special orders are ignored")
    RemoveText(rows, "29/50")
    Check(!EarnWarehouseReadStock(rows), "special-order quantity cannot replace normal stock")
    rows := LoadRows()
    FindRow(rows, "29/50").DeleteProp("x")
    Check(!EarnWarehouseReadStock(rows), "missing coordinate is rejected")
    rows := LoadRows()
    FindRow(rows, "29/50").x := "1108"
    Check(!EarnWarehouseReadStock(rows), "text coordinate is rejected")
    rows := LoadRows()
    FindRow(rows, "29/50").h := 0
    Check(!EarnWarehouseReadStock(rows), "nonpositive OCR dimensions are rejected")
    rows := LoadRows()
    rows.Push(0)
    Check(!EarnWarehouseReadStock(rows), "non-object line is rejected")
    rows := LoadRows()
    FindRow(rows, "$290,000").text := "$99,999,999"
    goods := EarnWarehouseReadStock(rows)
    Check(goods && goods[1].count = 29, "sale prices are not stock counts")
}

LoadRows() {
    rows := []
    for rawLine in StrSplit(FileRead(A_Args[1], "UTF-8"), "`n", "`r") {
        if (rawLine = "" || rawLine = "x`ty`tw`th`ttext")
            continue
        columns := StrSplit(rawLine, "`t")
        if (columns.Length != 5)
            throw Error("Invalid fixture column count")
        rows.Push({x: Integer(columns[1]), y: Integer(columns[2]), w: Integer(columns[3]),
            h: Integer(columns[4]), text: columns[5]})
    }
    return rows
}
FindRow(rows, text) {
    for item in rows
        if (item.text == text)
            return item
    throw Error("Missing fixture row: " text)
}
RemoveText(rows, text) {
    for index, item in rows {
        if (item.text == text) {
            rows.RemoveAt(index)
            return
        }
    }
    throw Error("Missing fixture row to remove: " text)
}
StockRow(text, x := 1108, y := 162) {
    return {x: x, y: y, w: 60, h: 20, text: text}
}
Check(condition, description) {
    global testChecks
    if (!condition)
        throw Error(description)
    testChecks++
}
'@

$testFile = Join-Path ([IO.Path]::GetTempPath()) ('gta-warehouse-read-test-' + [Guid]::NewGuid().ToString('N') + '.ahk')
[IO.File]::WriteAllText($testFile, $driver + "`n#Include " + $sourceFile + "`n", (New-Object Text.UTF8Encoding($true)))
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $AhkPath
$info.Arguments = '/ErrorStdOut /CP65001 "' + $testFile + '" "' + $fixtureFile + '"'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
$info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
$testProcess = [Diagnostics.Process]::Start($info)
try {
    if (-not $testProcess.WaitForExit(10000)) {
        $testProcess.Kill()
        $testProcess.WaitForExit()
        throw 'Warehouse read test timed out.'
    }
    $stdout = $testProcess.StandardOutput.ReadToEnd().Trim()
    $stderr = $testProcess.StandardError.ReadToEnd().Trim()
    if ($testProcess.ExitCode -ne 0 -or $stderr -ne '' -or $stdout -ne 'PASS EarnWarehouseRead cases=38 (no game input)') {
        throw "Warehouse read test failed (exit=$($testProcess.ExitCode))`nstdout: $stdout`nstderr: $stderr"
    }
    Write-Output $stdout
}
finally {
    if (-not $testProcess.HasExited) { $testProcess.Kill(); $testProcess.WaitForExit() }
    $testProcess.Dispose()
    if ([IO.File]::Exists($testFile)) { [IO.File]::Delete($testFile) }
}
