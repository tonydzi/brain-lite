# install.ps1: brain-lite companion installer for Windows. Ships next to brain-lite.zip in the release, not inside it.
#
# In:  powershell -NoProfile -ExecutionPolicy Bypass -File _staging/install.ps1 prepare [started_at]
#      run from the Second-Brain-Lite folder after the UPDATE.md "Step 1" block downloaded brain-lite.zip,
#      SHA256SUMS.txt, VERSION and this file into _staging/ and verified this file's checksum.
#      ... install.ps1 apply   after the owner's separate "yes" (the "Step 2" block).
# Out: prepare: verified unpack in _staging/new/lite for display, _staging/STATE, output for the owner; replaces nothing.
#      apply:   re-checks the archive against STATE, unpacks and checks it again and installs only that fresh unpack;
#      lite-prev = previous one, missing service files in My-Work.
#      Event lines with real UTC time go to lite-install.log (for the lite-check receipt).
# Caller: the owner's assistant, following UPDATE.md. The person types nothing.
# Rules: no network (everything is downloaded before); deletes nothing, old folders move to _archive/;
# My-Work is not read or changed, only missing service files are created; any STOP leaves lite as it was.
# ASCII only on purpose: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
# rail: Windows PowerShell 5.1 or PowerShell 7, no LLM.
param([Parameter(Position = 0)][string]$Cmd, [Parameter(Position = 1)][string]$StartedAt)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}

$Root = (Get-Location).ProviderPath
$St = Join-Path $Root '_staging'
$Log = Join-Path $Root 'lite-install.log'
function Now { [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
function Stamp { [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + $PID }
function Stop-Here($m) { Write-Output "STOP: $m"; exit 1 }
function Write-Event($name, $extra) { Add-Content -Path $Log -Value ("{0} {1} {2}" -f (Now), $name, $extra) -Encoding ascii }
function Move-ToArchive($path, $name) {
  if (-not (Test-Path -LiteralPath $path)) { return }
  $a = Join-Path $Root '_archive'
  New-Item -ItemType Directory -Force $a | Out-Null
  $dest = Join-Path $a ("$name-" + (Stamp))
  Move-Item -LiteralPath $path $dest
  "Moved to archive: _archive/" + (Split-Path $dest -Leaf)
}
function Sha($p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower() }
function Sum-Of($pattern) {
  $line = Get-Content (Join-Path $St 'SHA256SUMS.txt') | Where-Object { $_ -match $pattern } | Select-Object -First 1
  if ($line) { ($line -split '\s+')[0].ToLower() } else { '' }
}
function Read-State($key) {
  $line = Get-Content (Join-Path $St 'STATE') | Where-Object { $_ -like "$key=*" } | Select-Object -First 1
  if ($line) { $line.Substring($key.Length + 1) } else { '' }
}
function First-Line($p) { if (Test-Path -LiteralPath $p) { "$(Get-Content -LiteralPath $p -TotalCount 1)".Trim() } else { '' } }
function Show-Archive {
  $a = Join-Path $Root '_archive'
  if (Test-Path $a) { "Folders in _archive: $(@(Get-ChildItem $a -Force).Count). The recipe deletes nothing; the owner may delete them by hand." }
}

function Get-Tree($p) { $r = (Resolve-Path $p).Path; Get-ChildItem $p -Recurse -File -Force | ForEach-Object { [pscustomobject]@{ File = $_.FullName.Substring($r.Length); Hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash } } }
function Test-SameTree($a, $b) { -not (Compare-Object @(Get-Tree $a) @(Get-Tree $b) -Property File, Hash) }

function Expand-Checked($dest, $ver) {
  $zipPath = Join-Path $St 'brain-lite.zip'
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
  $bad = @($zip.Entries | Where-Object { $_.FullName -cnotlike 'lite/*' -or $_.FullName -match '(^|[\\/])\.\.([\\/]|$)' -or $_.FullName -match '^[\\/]|:' })
  $links = @($zip.Entries | Where-Object { (($_.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000 })
  $zip.Dispose()
  if ($bad.Count) { Stop-Here "suspicious paths in archive: $($bad.FullName -join ', ')" }
  if ($links.Count) { Stop-Here "links to outside files in archive: $($links.FullName -join ', ')" }
  Expand-Archive -LiteralPath $zipPath -DestinationPath $dest
  if (@(Get-ChildItem $dest -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { Stop-Here 'links to outside files in archive' }
  foreach ($f in 'VERSION', 'RULES.md', 'UPDATE.md', 'CHANGELOG.md', 'templates/My-Work-AGENTS.md') {
    if (-not (Test-Path (Join-Path $dest "lite/$f"))) { Stop-Here "archive has no lite/$f" }
  }
  $inner = First-Line (Join-Path $dest 'lite/VERSION')
  if ($inner -ne $ver) { Stop-Here "archive version $inner is not the release version $ver" }
}

function Invoke-Prepare {
  $started = if ($StartedAt) { $StartedAt } else { Now }
  foreach ($f in 'brain-lite.zip', 'SHA256SUMS.txt', 'VERSION') { if (-not (Test-Path (Join-Path $St $f))) { Stop-Here 'no downloaded release in _staging, run the Step 1 block first' } }
  $ver = First-Line (Join-Path $St 'VERSION')
  if ($ver -notmatch '^\d+\.\d+\.\d+$') { Stop-Here "release VERSION does not look like a version: $ver" }
  foreach ($j in 'new', 'unpack', 'fresh', 'STATE') { Move-ToArchive (Join-Path $St $j) "staging-$j" }
  $expected = Sum-Of '[ *]brain-lite\.zip$'
  if (-not $expected) { Stop-Here 'no archive line in SHA256SUMS.txt' }
  $zipPath = Join-Path $St 'brain-lite.zip'
  if ((Sha $zipPath) -ne $expected) { Stop-Here 'checksum mismatch' }
  Expand-Checked (Join-Path $St 'unpack') $ver
  $unpack = Join-Path $St 'unpack'
  Move-Item -LiteralPath $unpack (Join-Path $St 'new')
  $id = Stamp
  Set-Content -Path (Join-Path $St 'STATE') -Encoding ascii -Value @("install_id=$id", "version=$ver", "zip_sha256=$expected", "started_at=$started", "archive_verified_at=$(Now)")
  Write-Event 'started' "id=$id version=$ver at=$started"
  Write-Event 'archive_verified' "id=$id version=$ver zip_sha256=$expected"
  "New version: $ver"
  "Archive sha256: $expected"
  $lite = Join-Path $Root 'lite'
  if (Test-Path $lite) {
    "Current version: $(First-Line (Join-Path $lite 'VERSION'))"
    'Changed files:'
    Compare-Object @(Get-Tree $lite) @(Get-Tree (Join-Path $St 'new/lite')) -Property File, Hash | Select-Object -ExpandProperty File -Unique
  } else { 'No lite folder yet: first install' }
  'CHANGELOG head:'
  Get-Content (Join-Path $St 'new/lite/CHANGELOG.md') -TotalCount 20
  Write-Event 'consent_shown' "id=$id"
  'STEP 1 DONE, nothing replaced. Show this to the owner and ask for yes. The request to update is not a yes.'
}

function Set-MyWork {
  Set-Location $Root
  New-Item -ItemType Directory -Force My-Work | Out-Null
  if (-not (Test-Path My-Work/AGENTS.md)) { Copy-Item lite/templates/My-Work-AGENTS.md My-Work/AGENTS.md }
  if (-not (Test-Path My-Work/CLAUDE.md)) { Set-Content -Path My-Work/CLAUDE.md -Value '@AGENTS.md' -Encoding ascii }
  New-Item -ItemType Directory -Force -Path My-Work/.claude | Out-Null
  if (-not (Test-Path My-Work/.claude/settings.json)) { Set-Content -Path My-Work/.claude/settings.json -Value '{ "permissions": { "additionalDirectories": ["../lite"] } }' -Encoding ascii }
  # Migration of installs before 1.1.0 (as in 1.1.x): an old memo gets the AGENTS-CORE line once.
  if ((Test-Path lite/AGENTS-CORE.md) -and -not (Select-String -Path My-Work/AGENTS.md -Pattern 'AGENTS-CORE' -Quiet)) {
    Add-Content -Path My-Work/AGENTS.md -Value "`n<!-- brain-lite: AGENTS-CORE -->`nAt the start of every chat read ../lite/AGENTS-CORE.md and follow it."
    'Added a line about ../lite/AGENTS-CORE.md to My-Work/AGENTS.md'
  }
  # The brain is copied to a temporary folder and gets its name only when whole: a cut copy is never taken for a finished one.
  if ((Test-Path lite/brain) -and -not (Test-Path My-Work/Brain)) {
    Move-ToArchive (Join-Path $Root 'My-Work/.brain-copy') 'brain-partial'
    Copy-Item -Recurse lite/brain My-Work/.brain-copy
    Move-Item My-Work/.brain-copy My-Work/Brain
    'Second brain created: My-Work/Brain'
  }
}

function Invoke-Apply {
  Set-Location $Root
  if (Test-Path _swap) { Stop-Here '_swap left from an interrupted rollback, see troubleshooting' }
  if (-not (Test-Path (Join-Path $St 'STATE'))) { Stop-Here 'run step 1 first' }
  $ver = Read-State 'version'; $id = Read-State 'install_id'; $expected = Read-State 'zip_sha256'
  if (-not $ver -or -not $expected) { Stop-Here '_staging/STATE is incomplete, run step 1 again' }
  if ((Sha (Join-Path $St 'brain-lite.zip')) -ne $expected) { Stop-Here 'archive changed after step 1, run step 1 again' }
  # Install and compare only a fresh unpack of the same verified archive, not the one shown in step 1.
  $fresh = Join-Path $St 'fresh'
  Move-ToArchive $fresh 'staging-fresh'
  Expand-Checked $fresh $ver
  $freshLite = Join-Path $fresh 'lite'
  $place = $true
  if (Test-Path _old) {
    if (-not (Test-Path lite)) { 'Resuming an interrupted update: _old is there, lite is not yet' }
    elseif ((First-Line lite/VERSION) -eq $ver) {
      if (-not (Test-SameTree (Join-Path $Root 'lite') $freshLite)) { Stop-Here "lite $ver does not match the verified archive and _old is still there: show the owner VERSION of the folders, see troubleshooting" }
      "Resuming an interrupted update: lite $ver is in place and matches the archive, _old not moved yet"; $place = $false
    }
    else { Stop-Here "_old left from an interrupted update (lite: $(First-Line lite/VERSION), _old: $(First-Line _old/VERSION)), see troubleshooting" }
  } elseif ((Read-State 'swapped') -eq 'yes' -and (First-Line lite/VERSION) -eq $ver) {
    # The swap already happened in this apply and it stopped later: keep lite-prev, or the rollback point is lost.
    if (-not (Test-SameTree (Join-Path $Root 'lite') $freshLite)) { Stop-Here "lite $ver does not match the verified archive after an interrupted step 2, run step 1 again" }
    'Resuming an interrupted step 2: the swap is done, lite matches the archive'; $place = $false
  }
  if ($place) {
    Write-Event 'consent_given' "id=$id"
    if (Test-Path lite) { Move-Item lite _old }
    Move-Item -LiteralPath $freshLite lite
  }
  # Mark before moving _old: a rerun after any later stop does not shift lite-prev.
  if ((Read-State 'swapped') -ne 'yes') { Add-Content -Path (Join-Path $St 'STATE') -Value 'swapped=yes' -Encoding ascii }
  if (Test-Path _old) { Move-ToArchive (Join-Path $Root 'lite-prev') 'lite-prev'; Move-Item _old lite-prev }
  Set-MyWork
  Move-ToArchive $St 'staging'
  Write-Event 'installed' "id=$id version=$(First-Line lite/VERSION)"
  "Done: lite $(First-Line lite/VERSION)"
  if (Test-Path lite-prev) { "For rollback: lite-prev $(First-Line lite-prev/VERSION)" }
  Show-Archive
  'Event times for the receipt: lite-install.log'
}

switch ($Cmd) {
  'prepare' { Invoke-Prepare; exit 0 }
  'apply' { Invoke-Apply; exit 0 }
  default { 'usage: install.ps1 prepare [started_at] | apply'; exit 2 }
}
