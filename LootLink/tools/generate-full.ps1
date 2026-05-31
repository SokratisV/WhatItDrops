# LootLink FULL loot generator (DEV ONLY — not shipped to players' clients
# beyond the produced data file). Builds a complete npc -> loot table from the
# CMaNGOS-TBC world DB, resolving reference_loot_template and computing an
# effective per-kill drop % using mangos group / equal-chance rules.
#
# Chances are CMaNGOS approximations of original TBC, NOT Wowhead-Classic exact.
#
# Usage:  pwsh tools/generate-full.ps1
param(
    [string] $Sql     = "E:\World of Warcraft\_anniversary_\Interface\AddOns\LootLink\tools\cmangos\tbcdb.sql",
    [string] $OutFile = "E:\World of Warcraft\_anniversary_\Interface\AddOns\LootLink_Full\LootLinkFull.lua",
    [double] $MinPct  = 0.01   # drop rows below this effective % (noise floor)
)

if (-not (Test-Path $Sql) -and (Test-Path "$Sql.gz")) {
    Write-Host "Decompressing $Sql.gz ..."
    $in  = [System.IO.File]::OpenRead("$Sql.gz")
    $gz  = New-Object System.IO.Compression.GzipStream($in, [System.IO.Compression.CompressionMode]::Decompress)
    $out = [System.IO.File]::Create($Sql)
    $gz.CopyTo($out); $out.Close(); $gz.Close(); $in.Close()
}
if (-not (Test-Path $Sql)) {
    throw "SQL not found: $Sql`nDownload it first, e.g.:`n  curl -L -o `"$Sql.gz`" https://raw.githubusercontent.com/cmangos/tbc-db/master/Full_DB/TBCDB_1.10.0_ReturnOfTheVengeance.sql.gz"
}

# Tuple prefix: (entry,item,chance,group,mincountOrRef,maxcount,condition,'comment'
# We capture the 6 numeric fields we need and stop at the comment's opening quote.
$rx = [regex]"\((\d+),(\d+),(-?\d+(?:\.\d+)?),(\d+),(-?\d+),(\d+),\d+,'"

function Parse-Table([string]$tableName) {
    $store = New-Object 'System.Collections.Generic.Dictionary[int,System.Collections.Generic.List[double[]]]'
    $needle = "INSERT INTO ``$tableName`` VALUES"
    foreach ($line in [System.IO.File]::ReadLines($Sql)) {
        if (-not $line.StartsWith($needle)) { continue }
        foreach ($m in $rx.Matches($line)) {
            $entry = [int]$m.Groups[1].Value
            $row = [double[]]@(
                [double]$m.Groups[2].Value,   # 0 item
                [double]$m.Groups[3].Value,   # 1 chance (may be negative = quest)
                [double]$m.Groups[4].Value,   # 2 groupid
                [double]$m.Groups[5].Value,   # 3 mincountOrRef (<0 = reference id)
                [double]$m.Groups[6].Value    # 4 maxcount (ref repeat count)
            )
            $list = $null
            if (-not $store.TryGetValue($entry, [ref]$list)) {
                $list = New-Object 'System.Collections.Generic.List[double[]]'
                $store[$entry] = $list
            }
            $list.Add($row)
        }
    }
    return $store
}

Write-Host "Parsing creature_loot_template ..."
$clt = Parse-Table 'creature_loot_template'
Write-Host ("  creatures with loot: {0}" -f $clt.Count)
Write-Host "Parsing reference_loot_template ..."
$rlt = Parse-Table 'reference_loot_template'
Write-Host ("  reference tables: {0}" -f $rlt.Count)

# Expand a row list into item -> probability (0..1) for ONE processing pass.
$refCache = @{}
function Expand([System.Collections.Generic.List[double[]]]$rows, [int]$depth) {
    $result = @{}
    if ($null -eq $rows -or $depth -gt 6) { return $result }

    function Combine($res, $item, $p) {
        if ($p -le 0) { return }
        if ($p -gt 1) { $p = 1 }
        $prev = if ($res.ContainsKey($item)) { $res[$item] } else { 0 }
        $res[$item] = 1 - (1 - $prev) * (1 - $p)
    }
    function AddRow($res, $row, $p, $depth) {
        if ($row[3] -lt 0) {                     # reference
            $refId = [int](-$row[3])
            $reps  = [math]::Max([int]$row[4], 1)
            $sub   = $null
            if ($refCache.ContainsKey($refId)) { $sub = $refCache[$refId] }
            else {
                $rrows = $null; [void]$script:rlt.TryGetValue($refId, [ref]$rrows)
                $sub = Expand $rrows ($depth + 1)
                $refCache[$refId] = $sub
            }
            foreach ($kv in $sub.GetEnumerator()) {
                $pItem = $p * (1 - [math]::Pow(1 - $kv.Value, $reps))
                Combine $res ([int]$kv.Key) $pItem
            }
        } else {
            Combine $res ([int]$row[0]) $p
        }
    }

    # Ungrouped (groupid == 0): each rolls independently with its own chance.
    foreach ($row in $rows) {
        if ($row[2] -ne 0) { continue }
        $p = [math]::Abs($row[1]) / 100.0
        AddRow $result $row $p $depth
    }

    # Groups (groupid > 0): exactly one outcome per group; explicit chances
    # roll first, equal-chance (0) rows split the remaining probability.
    $groups = @{}
    foreach ($row in $rows) {
        $g = [int]$row[2]
        if ($g -le 0) { continue }
        if (-not $groups.ContainsKey($g)) { $groups[$g] = New-Object 'System.Collections.Generic.List[double[]]' }
        $groups[$g].Add($row)
    }
    foreach ($g in $groups.Keys) {
        $members = $groups[$g]
        $sumExpl = 0.0; $nEqual = 0
        foreach ($row in $members) {
            if ($row[1] -ne 0) { $sumExpl += [math]::Abs($row[1]) } else { $nEqual++ }
        }
        $remainder = [math]::Max(0.0, 100.0 - $sumExpl)
        $eqp = if ($nEqual -gt 0) { ($remainder / 100.0) / $nEqual } else { 0 }
        foreach ($row in $members) {
            $gp = if ($row[1] -ne 0) { [math]::Abs($row[1]) / 100.0 } else { $eqp }
            AddRow $result $row $gp $depth
        }
    }
    return $result
}

Write-Host "Computing effective drop chances ..."
$outDir = Split-Path $OutFile
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("-- AUTO-GENERATED by tools/generate-full.ps1 — do not edit by hand.")
[void]$sb.AppendLine("-- Source: CMaNGOS-TBC world DB (creature_loot_template + reference_loot_template).")
[void]$sb.AppendLine("-- Effective per-kill drop % via mangos group/equal-chance rules. Approximate, not Wowhead-exact.")
[void]$sb.AppendLine("LootLinkFull = LootLinkFull or {}")
[void]$sb.AppendLine("local d = LootLinkFull")
[void]$sb.AppendLine("")

$nNpc = 0; $nRows = 0
foreach ($entry in ($clt.Keys | Sort-Object)) {
    if ($entry -le 0) { continue }                 # entry 0 = player insignia loot
    $probs = Expand $clt[$entry] 0
    if ($probs.Count -eq 0) { continue }
    $pairs = $probs.GetEnumerator() |
        Where-Object { $_.Key -gt 0 -and ($_.Value * 100) -ge $MinPct } |
        Sort-Object Value -Descending
    if (-not $pairs) { continue }
    $nNpc++
    $parts = foreach ($p in $pairs) {
        $nRows++
        "{{{0},{1}}}" -f ([int]$p.Key), ([math]::Round($p.Value * 100, 2))
    }
    [void]$sb.AppendLine(("d[{0}] = {{{1}}}" -f $entry, ($parts -join ",")))
}

[System.IO.File]::WriteAllText($OutFile, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Host ("Wrote {0} NPCs / {1} item rows -> {2}" -f $nNpc, $nRows, $OutFile)
Write-Host ("Output size: {0:N2} MB" -f ((Get-Item $OutFile).Length / 1MB))
