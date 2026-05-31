# LootLink data generator — Wowhead-accurate edition (DEV ONLY).
#
# Source of loot rates/items/names/quality/world-drop flag:
#   LootCodex (Coldnova), GPL v3 — Wowhead-cache-derived DB.  Credit/keep its license.
# Source of spawn map (for continent/instance partitioning):
#   CMaNGOS-TBC `creature` table.
#
# Emits, keeping LootLink's architecture:
#   * Per-region LoadOnDemand partition files: d[npc] = { specificCount, id,rate, ... }
#     (specific drops first, then generic world-drop pool; rates are Wowhead %).
#   * Data/LootLinkItems.lua : inline item names+quality and npc names.
param(
    # Prefer the stashed build-input copy (so the LootCodex addon can be uninstalled);
    # fall back to the live addon if the stash is absent.
    [string] $CodexDB  = "E:\World of Warcraft\_anniversary_\Interface\AddOns\LootLink\tools\lootcodex\LootCodexDB.lua",
    [string] $Sql      = "E:\World of Warcraft\_anniversary_\Interface\AddOns\LootLink\tools\cmangos\tbcdb.sql",
    [string] $AddonsDir= "E:\World of Warcraft\_anniversary_\Interface\AddOns",
    [string] $ItemsOut = "E:\World of Warcraft\_anniversary_\Interface\AddOns\LootLink\Data\LootLinkItems.lua"
)
if (-not (Test-Path $CodexDB)) {
    $live = "E:\World of Warcraft\_anniversary_\Interface\AddOns\LootCodex\LootCodexDB.lua"
    if (Test-Path $live) { $CodexDB = $live } else { throw "LootCodexDB not found (stash or live addon): $CodexDB" }
}
if (-not (Test-Path $Sql) -and (Test-Path "$Sql.gz")) {
    $in = [System.IO.File]::OpenRead("$Sql.gz")
    $gz = New-Object System.IO.Compression.GzipStream($in, [System.IO.Compression.CompressionMode]::Decompress)
    $o = [System.IO.File]::Create($Sql); $gz.CopyTo($o); $o.Close(); $gz.Close(); $in.Close()
}
if (-not (Test-Path $Sql)) { throw "CMaNGOS SQL not found (needed for spawn->continent mapping): $Sql" }

# Split a Lua table body into top-level fields (respects nested {} and "strings" with \" escapes).
function SplitTop([string]$s) {
    $f = New-Object System.Collections.Generic.List[string]
    $depth = 0; $inStr = $false; $start = 0
    for ($i = 0; $i -lt $s.Length; $i++) {
        $c = $s[$i]
        if ($inStr) {
            if ($c -eq '\') { $i++ } elseif ($c -eq '"') { $inStr = $false }
        } elseif ($c -eq '"') { $inStr = $true }
        elseif ($c -eq '{') { $depth++ } elseif ($c -eq '}') { $depth-- }
        elseif ($c -eq ',' -and $depth -eq 0) { $f.Add($s.Substring($start, $i - $start)); $start = $i + 1 }
    }
    $f.Add($s.Substring($start))
    return $f
}

# 1) NPC -> partition(s) from CMaNGOS creature spawns.
Write-Host "Parsing creature spawns ..."
$rxSpawn = [regex]"\((\d+),(\d+),(\d+),"
$spawns = @{}
$needle = "INSERT INTO ``creature`` VALUES"
foreach ($line in [System.IO.File]::ReadLines($Sql)) {
    if (-not $line.StartsWith($needle)) { continue }
    foreach ($m in $rxSpawn.Matches($line)) {
        $id = [int]$m.Groups[2].Value; $mid = [int]$m.Groups[3].Value
        $part = switch ($mid) { 0 {'EasternKingdoms'} 1 {'Kalimdor'} 530 {'Outland'} default {'Instances'} }
        if (-not $spawns.ContainsKey($id)) { $spawns[$id] = New-Object 'System.Collections.Generic.HashSet[string]' }
        [void]$spawns[$id].Add($part)
    }
}
Write-Host ("  spawn-mapped npcs: {0}" -f $spawns.Count)

# 2) Parse LootCodexDB.
Write-Host "Parsing LootCodexDB ..."
$rxHeader = [regex]"^\s*\[(\d+)\]\s*=\s*\{\s*--\s*(.*)$"
$rxRow    = [regex]"^\s*\{(.+)\},?\s*$"
$ALL = 'EasternKingdoms','Kalimdor','Outland','Instances','Misc'
$buf = @{}; foreach ($p in $ALL) { $buf[$p] = [System.Text.StringBuilder]::new() }
$counts = @{}; foreach ($p in $ALL) { $counts[$p] = 0 }
$itemName = @{}; $itemQual = @{}; $npcName = @{}

$curNpc = 0; $spec = $null; $world = $null
function FlushNpc {
    if ($script:curNpc -le 0) { return }
    if (($script:spec.Count + $script:world.Count) -eq 0) { return }
    $script:spec  | Sort-Object -Property r -Descending | Out-Null
    $sOrd = @($script:spec  | Sort-Object -Property r -Descending)
    $wOrd = @($script:world | Sort-Object -Property r -Descending)
    $flat = New-Object System.Collections.Generic.List[string]
    [void]$flat.Add([string]$sOrd.Count)
    foreach ($e in $sOrd) { [void]$flat.Add(("{0},{1}" -f $e.id, $e.r)) }
    foreach ($e in $wOrd) { [void]$flat.Add(("{0},{1}" -f $e.id, $e.r)) }
    $line = "d[{0}]={{{1}}}" -f $script:curNpc, ($flat -join ",")
    $parts = if ($script:spawns.ContainsKey($script:curNpc)) { $script:spawns[$script:curNpc] } else { @('Misc') }
    foreach ($p in $parts) { [void]$script:buf[$p].AppendLine($line); $script:counts[$p]++ }
}

foreach ($line in [System.IO.File]::ReadLines($CodexDB)) {
    $h = $rxHeader.Match($line)
    if ($h.Success) {
        FlushNpc
        $curNpc = [int]$h.Groups[1].Value
        $spec = New-Object System.Collections.Generic.List[object]
        $world = New-Object System.Collections.Generic.List[object]
        $nm = $h.Groups[2].Value.Trim()
        if ($nm) { $npcName[$curNpc] = $nm.Replace('\','\\').Replace('"','\"') }
        continue
    }
    if ($curNpc -le 0) { continue }
    $rm = $rxRow.Match($line)
    if (-not $rm.Success) { continue }
    $f = SplitTop $rm.Groups[1].Value
    if ($f.Count -lt 3) { continue }
    $id = [int]$f[0].Trim()
    $rate = [math]::Round([double]$f[2].Trim(), 2)
    if ($id -le 0 -or $rate -le 0) { continue }
    $isWorld = ($f.Count -ge 6) -and ($f[5].Trim() -eq '1')
    $rec = [pscustomobject]@{ id = $id; r = $rate }
    if ($isWorld) { $world.Add($rec) } else { $spec.Add($rec) }
    if (-not $itemName.ContainsKey($id)) {
        $itemName[$id] = $f[1].Trim()           # already a "...\"..." Lua literal
        if ($f.Count -ge 4) { $itemQual[$id] = [int]$f[3].Trim() }
    }
}
FlushNpc

# 3) Write partition addons.
Write-Host "Writing partitions ..."
foreach ($p in $ALL) {
    $dir = Join-Path $AddonsDir ("LootLink_" + $p)
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $lua = "-- AUTO-GENERATED by tools/generate-from-lootcodex.ps1 — do not edit.`r`n" +
           "-- Partition: $p. Wowhead rates via LootCodex (GPL v3). Flat: d[npc]={specificCount,item,pct,...}.`r`n" +
           "LootLinkFull = LootLinkFull or {}`r`nlocal d = LootLinkFull`r`n`r`n" + $buf[$p].ToString()
    [System.IO.File]::WriteAllText((Join-Path $dir "LootLink_$p.lua"), $lua, [System.Text.UTF8Encoding]::new($false))
    $toc = "## Interface: 20505`r`n## Title: LootLink |cff66ccff$p Data|r`r`n## Notes: Wowhead loot for $p (via LootCodex GPLv3). Loaded on demand by LootLink.`r`n## Version: 1.0`r`n## LoadOnDemand: 1`r`n`r`nLootLink_$p.lua`r`n"
    [System.IO.File]::WriteAllText((Join-Path $dir "LootLink_$p.toc"), $toc, [System.Text.UTF8Encoding]::new($false))
    Write-Host ("  LootLink_{0,-16} {1,6} npcs  {2,8:N0} KB" -f $p, $counts[$p], ((Get-Item (Join-Path $dir "LootLink_$p.lua")).Length / 1KB))
}

# 4) Write names/quality file.
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("-- AUTO-GENERATED by tools/generate-from-lootcodex.ps1 — do not edit.")
[void]$sb.AppendLine("-- Inline item names+quality and npc names (via LootCodex GPLv3).")
[void]$sb.AppendLine("LootLinkItemName = {")
foreach ($id in ($itemName.Keys | Sort-Object)) { [void]$sb.AppendLine(("[{0}]={1}," -f $id, $itemName[$id])) }
[void]$sb.AppendLine("}")
[void]$sb.AppendLine("LootLinkItemQuality = {")
foreach ($id in ($itemQual.Keys | Sort-Object)) { [void]$sb.AppendLine(("[{0}]={1}," -f $id, $itemQual[$id])) }
[void]$sb.AppendLine("}")
[void]$sb.AppendLine("LootLinkNpcName = {")
foreach ($id in ($npcName.Keys | Sort-Object)) { [void]$sb.AppendLine(("[{0}]=`"{1}`"," -f $id, $npcName[$id])) }
[void]$sb.AppendLine("}")
[System.IO.File]::WriteAllText($ItemsOut, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Host ("Names file: {0:N0} items, {1:N0} npcs, {2:N0} KB" -f $itemName.Count, $npcName.Count, ((Get-Item $ItemsOut).Length / 1KB))
Write-Host "Done."
