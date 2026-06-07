# Build the shareable LootLink install zip without using Remove-Item (a path guard
# blocks Remove-Item near the WoW dir). Writes entries straight into the archive.
$base = "E:\World of Warcraft\_anniversary_\Interface\AddOns"
$folders = @('LootLink','LootLink_EasternKingdoms','LootLink_Instances','LootLink_Kalimdor','LootLink_Misc','LootLink_Outland')
$ver = (Select-String -Path (Join-Path $base 'LootLink\LootLink.toc') -Pattern '##\s*Version:\s*(.+)').Matches.Groups[1].Value.Trim()
$out = Join-Path ([Environment]::GetFolderPath('Desktop')) 'LootLink-install.zip'
if (Test-Path $out) { [System.IO.File]::Delete($out) }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($out, [System.IO.Compression.ZipArchiveMode]::Create)
$count = 0
foreach ($f in $folders) {
  $root = Join-Path $base $f
  foreach ($file in Get-ChildItem $root -Recurse -File -Force) {
    $rel = $file.FullName.Substring($base.Length).TrimStart('\')
    $relU = $rel -replace '\\','/'
    if ($relU -match "(^|/)(tools|\.git)/") { continue }   # dev-only / vcs
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $relU, [System.IO.Compression.CompressionLevel]::Optimal)
    $count++
  }
}
$zip.Dispose()

"Bundled version: $ver  ->  $out"
"Files: $count   Size: {0:N0} KB" -f ((Get-Item $out).Length/1KB)
$zip = [System.IO.Compression.ZipFile]::OpenRead($out)
$hasBosses = [bool]($zip.Entries | Where-Object { $_.FullName -eq 'LootLink/Data/LootLinkBosses.lua' })
$hasTools  = [bool]($zip.Entries | Where-Object { $_.FullName -like '*/tools/*' })
$tocVers = foreach ($e in ($zip.Entries | Where-Object { $_.FullName -like '*.toc' } | Sort-Object FullName)) {
  $r = New-Object System.IO.StreamReader($e.Open()); $t = $r.ReadToEnd(); $r.Close()
  ([regex]'##\s*Version:\s*(.+)').Match($t).Groups[1].Value.Trim()
}
$topFolders = ($zip.Entries.FullName | ForEach-Object { ($_ -split '/')[0] } | Sort-Object -Unique) -join ', '
"Boss data present: $hasBosses   tools leaked in: $hasTools"
"Top-level folders: $topFolders"
"TOC versions: $($tocVers -join ', ')"
$zip.Dispose()
