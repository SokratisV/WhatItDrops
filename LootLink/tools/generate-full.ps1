# LootLink FULL loot generator (DEV ONLY).
# Builds complete npc -> loot tables from the CMaNGOS-TBC world DB, then:
#   * FLAT format:  d[npc] = { specificCount, item,pct, item,pct, ... }
#       - the first `specificCount` pairs are mob-specific loot,
#       - the remainder are generic "World Drop" pool items (toggle-able in-game).
#   * PARTITIONED by spawn map into per-continent / per-instance LoadOnDemand
#     addons, so the client only parses the region you're actually in.
#
# Chances are CMaNGOS approximations (mangos group/equal-chance rules), not
# Wowhead-exact. World-drop references are tagged via their 'World Drop' comment.
param(
    [string] $Sql       = "E:\World of Warcraft\_anniversary_\Interface\AddOns\LootLink\tools\cmangos\tbcdb.sql",
    [string] $AddonsDir = "E:\World of Warcraft\_anniversary_\Interface\AddOns",
    [double] $MinPct    = 0.01
)

if (-not (Test-Path $Sql) -and (Test-Path "$Sql.gz")) {
    Write-Host "Decompressing $Sql.gz ..."
    $in  = [System.IO.File]::OpenRead("$Sql.gz")
    $gz  = New-Object System.IO.Compression.GzipStream($in, [System.IO.Compression.CompressionMode]::Decompress)
    $out = [System.IO.File]::Create($Sql); $gz.CopyTo($out); $out.Close(); $gz.Close(); $in.Close()
}
if (-not (Test-Path $Sql)) { throw "SQL not found: $Sql" }

$rxLoot  = [regex]"\((\d+),(\d+),(-?\d+(?:\.\d+)?),(\d+),(-?\d+),(\d+),\d+,'"
$rxWorld = [regex]"\(\d+,\d+,-?\d+(?:\.\d+)?,\d+,(-\d+),\d+,\d+,'[^']*World Drop"
$rxSpawn = [regex]"\((\d+),(\d+),(\d+),"

function Parse-Loot([string]$table) {
    $store = New-Object 'System.Collections.Generic.Dictionary[int,System.Collections.Generic.List[double[]]]'
    $needle = "INSERT INTO ``$table`` VALUES"
    foreach ($line in [System.IO.File]::ReadLines($Sql)) {
        if (-not $line.StartsWith($needle)) { continue }
        foreach ($m in $rxLoot.Matches($line)) {
            $e = [int]$m.Groups[1].Value
            $row = [double[]]@($m.Groups[2].Value, $m.Groups[3].Value, $m.Groups[4].Value, $m.Groups[5].Value, $m.Groups[6].Value)
            $list = $null
            if (-not $store.TryGetValue($e, [ref]$list)) { $list = New-Object 'System.Collections.Generic.List[double[]]'; $store[$e] = $list }
            $list.Add($row)
        }
    }
    return $store
}

# Set of reference-table IDs that are generic World Drop pools (by comment).
function Collect-WorldRefs {
    $set = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($table in @('creature_loot_template','reference_loot_template')) {
        $needle = "INSERT INTO ``$table`` VALUES"
        foreach ($line in [System.IO.File]::ReadLines($Sql)) {
            if (-not $line.StartsWith($needle)) { continue }
            foreach ($m in $rxWorld.Matches($line)) { [void]$set.Add([int](-[int]$m.Groups[1].Value)) }
        }
    }
    return $set
}

# entry -> set of partition names, from the creature spawn table's map column.
function Parse-Spawns {
    $map = @{}
    $needle = "INSERT INTO ``creature`` VALUES"
    foreach ($line in [System.IO.File]::ReadLines($Sql)) {
        if (-not $line.StartsWith($needle)) { continue }
        foreach ($m in $rxSpawn.Matches($line)) {
            $id  = [int]$m.Groups[2].Value
            $mid = [int]$m.Groups[3].Value
            $part = switch ($mid) { 0 {'EasternKingdoms'} 1 {'Kalimdor'} 530 {'Outland'} default {'Instances'} }
            if (-not $map.ContainsKey($id)) { $map[$id] = New-Object 'System.Collections.Generic.HashSet[string]' }
            [void]$map[$id].Add($part)
        }
    }
    return $map
}

Write-Host "Scanning World Drop references ..."; $worldRefs = Collect-WorldRefs
Write-Host ("  world-drop ref tables: {0}" -f $worldRefs.Count)
Write-Host "Parsing creature_loot_template ..."; $clt = Parse-Loot 'creature_loot_template'
Write-Host ("  creatures with loot: {0}" -f $clt.Count)
Write-Host "Parsing reference_loot_template ..."; $rlt = Parse-Loot 'reference_loot_template'
Write-Host "Parsing creature spawns ..."; $spawns = Parse-Spawns
Write-Host ("  creatures with spawns: {0}" -f $spawns.Count)

$cacheFull = @{}; $cacheSpec = @{}
function Expand([System.Collections.Generic.List[double[]]]$rows, [int]$depth, [bool]$excludeWorld) {
    $result = @{}
    if ($null -eq $rows -or $depth -gt 6) { return $result }
    function Combine($res, $item, $p) {
        if ($p -le 0) { return }; if ($p -gt 1) { $p = 1 }
        $prev = if ($res.ContainsKey($item)) { $res[$item] } else { 0 }
        $res[$item] = 1 - (1 - $prev) * (1 - $p)
    }
    function AddRow($res, $row, $p, $depth, $excludeWorld) {
        if ($row[3] -lt 0) {
            $refId = [int](-$row[3])
            if ($excludeWorld -and $script:worldRefs.Contains($refId)) { return }
            $reps = [math]::Max([int]$row[4], 1)
            $cache = if ($excludeWorld) { $script:cacheSpec } else { $script:cacheFull }
            $sub = $null
            if ($cache.ContainsKey($refId)) { $sub = $cache[$refId] }
            else {
                $rr = $null; [void]$script:rlt.TryGetValue($refId, [ref]$rr)
                $sub = Expand $rr ($depth + 1) $excludeWorld
                $cache[$refId] = $sub
            }
            foreach ($kv in $sub.GetEnumerator()) { Combine $res ([int]$kv.Key) ($p * (1 - [math]::Pow(1 - $kv.Value, $reps))) }
        } else { Combine $res ([int]$row[0]) $p }
    }
    foreach ($row in $rows) { if ($row[2] -eq 0) { AddRow $result $row ([math]::Abs($row[1]) / 100.0) $depth $excludeWorld } }
    $groups = @{}
    foreach ($row in $rows) { $g = [int]$row[2]; if ($g -gt 0) { if (-not $groups.ContainsKey($g)) { $groups[$g] = New-Object 'System.Collections.Generic.List[double[]]' }; $groups[$g].Add($row) } }
    foreach ($g in $groups.Keys) {
        $members = $groups[$g]; $sumExpl = 0.0; $nEq = 0
        foreach ($row in $members) { if ($row[1] -ne 0) { $sumExpl += [math]::Abs($row[1]) } else { $nEq++ } }
        $eqp = if ($nEq -gt 0) { ([math]::Max(0.0, 100.0 - $sumExpl) / 100.0) / $nEq } else { 0 }
        foreach ($row in $members) {
            $gp = if ($row[1] -ne 0) { [math]::Abs($row[1]) / 100.0 } else { $eqp }
            AddRow $result $row $gp $depth $excludeWorld
        }
    }
    return $result
}

Write-Host "Computing + partitioning ..."
$ALL = 'EasternKingdoms','Kalimdor','Outland','Instances','Misc'
$buf = @{}; foreach ($p in $ALL) { $buf[$p] = [System.Text.StringBuilder]::new() }
$counts = @{}; foreach ($p in $ALL) { $counts[$p] = 0 }

foreach ($entry in ($clt.Keys | Sort-Object)) {
    if ($entry -le 0) { continue }
    $full = Expand $clt[$entry] 0 $false
    if ($full.Count -eq 0) { continue }
    $spec = Expand $clt[$entry] 0 $true
    $specOrdered = $spec.GetEnumerator() | Where-Object { ($full[$_.Key] * 100) -ge $MinPct } | Sort-Object { $full[$_.Key] } -Descending
    $worldOrdered = $full.GetEnumerator() | Where-Object { -not $spec.ContainsKey($_.Key) -and ($_.Value * 100) -ge $MinPct } | Sort-Object Value -Descending
    $specCount = @($specOrdered).Count
    $flat = New-Object System.Collections.Generic.List[string]
    [void]$flat.Add([string]$specCount)
    foreach ($p in $specOrdered)  { [void]$flat.Add(("{0},{1}" -f [int]$p.Key, [math]::Round($full[$p.Key] * 100, 2))) }
    foreach ($p in $worldOrdered) { [void]$flat.Add(("{0},{1}" -f [int]$p.Key, [math]::Round($p.Value * 100, 2))) }
    if ($flat.Count -le 1) { continue }
    $line = "d[{0}]={{{1}}}" -f $entry, ($flat -join ",")
    $parts = if ($spawns.ContainsKey($entry)) { $spawns[$entry] } else { @('Misc') }
    foreach ($p in $parts) { [void]$buf[$p].AppendLine($line); $counts[$p]++ }
}

foreach ($p in $ALL) {
    $dir = Join-Path $AddonsDir ("LootLink_" + $p)
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $lua = "-- AUTO-GENERATED by tools/generate-full.ps1 — do not edit.`r`n" +
           "-- Partition: $p. CMaNGOS-TBC effective drop %. Flat: d[npc]={specificCount,item,pct,...}.`r`n" +
           "LootLinkFull = LootLinkFull or {}`r`nlocal d = LootLinkFull`r`n`r`n" + $buf[$p].ToString()
    [System.IO.File]::WriteAllText((Join-Path $dir ("LootLink_$p.lua")), $lua, [System.Text.UTF8Encoding]::new($false))
    $toc = "## Interface: 20505`r`n## Title: LootLink |cff66ccff$p Data|r`r`n## Notes: CMaNGOS loot for $p. Loaded on demand by LootLink.`r`n## Version: 1.0`r`n## LoadOnDemand: 1`r`n`r`nLootLink_$p.lua`r`n"
    [System.IO.File]::WriteAllText((Join-Path $dir ("LootLink_$p.toc")), $toc, [System.Text.UTF8Encoding]::new($false))
    $kb = ((Get-Item (Join-Path $dir ("LootLink_$p.lua"))).Length / 1KB)
    Write-Host ("  LootLink_{0,-16} {1,6} npcs  {2,8:N0} KB" -f $p, $counts[$p], $kb)
}
Write-Host "Done."
