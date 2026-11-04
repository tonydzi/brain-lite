# test_update.ps1: runs EXACTLY the ```powershell blocks of UPDATE.md against a local file:// "release".
# The blocks start installer/install.ps1 in a child PowerShell of the same kind, as on a friend's computer.
# ASCII only on purpose: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
# The only substitution in the blocks: https://github.com/tonydzi/brain-lite/releases/ -> file:///<tmp>/releases/,
# '=https' -> '=file', and Join-Path $HOME -> Join-Path '<tmp home>'.
# A release = brain-lite.zip + install.sh + install.ps1 + SHA256SUMS.txt + VERSION, in latest/download and download/vX.Y.Z.
# Green: install, update 1.0.0 -> 1.0.1, rollback twice, My-Work untouched, real git-archive zip with dir entries,
# old lite-prev moved to _archive (nothing deleted), pinned $V, resume after an interrupted update, event log.
# Red (recipe must stop and change nothing): swapped checksum, swapped installer, zip-slip, path outside lite/,
# LITE/ case trick, missing required file, stale _swap/_old, step 2 before step 1, run from inside lite,
# installer or archive changed between the steps.
# Self-check: installer with the checksum comparison removed must let the swapped archive through.
# Run: pwsh tests/test_update.ps1  or  powershell -NoProfile -ExecutionPolicy Bypass -File tests/test_update.ps1
$ErrorActionPreference = 'Stop'
$Repo = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$W = Join-Path ([IO.Path]::GetTempPath()) ('brain-lite-ps-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $W | Out-Null
$W = (Resolve-Path $W).Path
$script:Pass = 0; $script:Fail = 0
function Ok($m) { $script:Pass++; "  ok   $m" }
function Bad($m) { $script:Fail++; "  FAIL $m" }
Add-Type -AssemblyName System.IO.Compression.FileSystem

$HomeDir = Join-Path $W 'home'; New-Item -ItemType Directory $HomeDir | Out-Null
$RelRoot = Join-Path $W 'releases'
$RelUrl = [Uri]::new($RelRoot + [IO.Path]::DirectorySeparatorChar).AbsoluteUri

$text = [IO.File]::ReadAllText((Join-Path $Repo 'UPDATE.md'), [Text.Encoding]::UTF8)
$win = $text.Substring($text.IndexOf('## Windows'))
$blocks = @([regex]::Matches($win, '```powershell\r?\n(.*?)```', 'Singleline') | ForEach-Object { $_.Groups[1].Value })
if ($blocks.Count -ne 4) { throw "expected 4 powershell blocks, found $($blocks.Count)" }
for ($i = 0; $i -lt 4; $i++) {
  $b = $blocks[$i].Replace('https://github.com/tonydzi/brain-lite/releases/', $RelUrl).Replace('=https', '=file').Replace('Join-Path $HOME', "Join-Path '$HomeDir'")
  if ($b -match '[^\x00-\x7F]') { throw "block $i has non-ASCII characters (breaks Windows PowerShell 5.1)" }
  [IO.File]::WriteAllText((Join-Path $W "block$i.ps1"), $b)
}
[IO.File]::WriteAllText((Join-Path $W 'block0pin.ps1'), ([IO.File]::ReadAllText((Join-Path $W 'block0.ps1')).Replace("`$V = ''", "`$V = '1.0.0'")))
$Inst = [IO.File]::ReadAllText((Join-Path $Repo 'installer/install.ps1'))
if ($Inst -match '[^\x00-\x7F]') { throw 'installer/install.ps1 has non-ASCII characters (breaks Windows PowerShell 5.1)' }
if (($Inst + ($blocks -join "`n")) -match 'Remove-Item|\brm\b|\brmdir\b|\bdel\b') { Bad 'recipe or installer deletes something' } else { Ok 'recipe and installer delete nothing (no Remove-Item)' }
if (($blocks -join "`n") -match '\|\s*(iex|Invoke-Expression)') { Bad 'downloaded code piped into iex' } else { Ok 'no irm | iex' }

function Sha($p) { (Get-FileHash $p -Algorithm SHA256).Hash.ToLower() }
function Write-Sums($dir) {
  $lines = foreach ($f in 'brain-lite.zip', 'install.sh', 'install.ps1') { if (Test-Path (Join-Path $dir $f)) { "$(Sha (Join-Path $dir $f))  $f" } }
  [IO.File]::WriteAllText((Join-Path $dir 'SHA256SUMS.txt'), (($lines -join "`n") + "`n"))
}
function Add-Installer($dir) {
  Copy-Item (Join-Path $Repo 'installer/install.sh'), (Join-Path $Repo 'installer/install.ps1') $dir
  if (-not (Test-Path (Join-Path $dir 'VERSION'))) { [IO.File]::WriteAllText((Join-Path $dir 'VERSION'), "9.9.9`n") }
  Write-Sums $dir
}
function New-Release($dir, $version) {
  $src = Join-Path $W "src-$version"; New-Item -ItemType Directory -Force $src, $dir | Out-Null
  $tmp = Join-Path $W "a-$version.zip"
  git -C $Repo archive --format=zip --prefix=lite/ -o $tmp HEAD
  [IO.Compression.ZipFile]::ExtractToDirectory($tmp, $src)
  [IO.File]::WriteAllText((Join-Path $src 'lite/VERSION'), "$version`n")
  # Build entries by hand with forward slashes: on .NET Framework (PS 5.1) CreateFromDirectory writes 'lite\x'.
  $z = [IO.Compression.ZipFile]::Open((Join-Path $dir 'brain-lite.zip'), 'Create')
  $base = (Resolve-Path $src).Path
  foreach ($f in Get-ChildItem (Join-Path $src 'lite') -Recurse -File -Force) {
    $name = $f.FullName.Substring($base.Length + 1).Replace('\', '/')
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, $f.FullName, $name)
  }
  $z.Dispose()
  [IO.File]::WriteAllText((Join-Path $dir 'VERSION'), "$version`n")
  Add-Installer $dir
}
function New-EvilZip($dir, $names) {
  New-Item -ItemType Directory -Force $dir | Out-Null
  $z = [IO.Compression.ZipFile]::Open((Join-Path $dir 'brain-lite.zip'), 'Create')
  foreach ($n in $names) { $e = $z.CreateEntry($n); $s = New-Object IO.StreamWriter($e.Open()); $s.Write('9.9.9'); $s.Dispose() }
  $z.Dispose(); Add-Installer $dir
}
function Publish {
  if (Test-Path $RelRoot) { Remove-Item -Recurse -Force $RelRoot }
  $latest = Join-Path $RelRoot 'latest/download'; New-Item -ItemType Directory -Force $latest | Out-Null
  $first = $true
  foreach ($r in $args) {
    if ($first) { Copy-Item (Join-Path $r '*') $latest; $first = $false }
    $vf = Join-Path $r 'VERSION'
    $v = if (Test-Path $vf) { "$(Get-Content $vf -TotalCount 1)".Trim() } else { '' }
    if ($v -match '^\d+\.\d+\.\d+$') { $d = Join-Path $RelRoot "download/v$v"; New-Item -ItemType Directory -Force $d | Out-Null; Copy-Item (Join-Path $r '*') $d }
  }
}
$H = Join-Path $HomeDir 'Second-Brain-Lite'
$Log = Join-Path $W 'last.log'
function Run($n, $relDir, $recipeDir = $W, $cwd = $W) {
  if ($relDir) { Publish $relDir }
  $here = Get-Location
  Set-Location $cwd
  try { & (Join-Path $recipeDir "block$n.ps1") *> $Log; return $true }
  catch { $_.ToString() | Add-Content $Log; return $false }
  finally { Set-Location $here }
}
function MwHash { (Get-ChildItem "$H/My-Work" -Recurse -File -Force | Where-Object { $_.Name -notin 'AGENTS.md', '.lite-last-check' } | Sort-Object FullName | ForEach-Object { Sha $_.FullName }) -join ',' }
function TreeHash($p) { (Get-ChildItem $p -Recurse -File -Force | Sort-Object FullName | ForEach-Object { Sha $_.FullName }) -join ',' }
function LogText { if (Test-Path $Log) { [IO.File]::ReadAllText($Log) } else { '' } }
function Ver($p) { (Get-Content (Join-Path $H "$p/VERSION") -ErrorAction SilentlyContinue | Select-Object -First 1) }

try {
  'Green'
  New-Release (Join-Path $W 'r100') '1.0.0'; New-Release (Join-Path $W 'r101') '1.0.1'
  if ((Run 0 "$W/r100") -and (Run 1 $null) -and ((Ver lite) -eq '1.0.0') -and (Test-Path "$H/My-Work/AGENTS.md") -and (Test-Path "$H/lite/.claude/skills/lite-check/SKILL.md") -and -not (Test-Path "$H/_staging") -and (@(Get-ChildItem "$H/My-Work/Brain" -Recurse -Filter README.md).Count -eq 12) -and (Test-Path "$H/lite/law/FLOOR.md")) { Ok 'fresh install with law and 11-layer brain' } else { Bad 'fresh install'; LogText }
  if ((Get-Content "$H/My-Work/AGENTS.md" -Raw) -match 'AGENTS-CORE') { Ok 'fresh memo points to AGENTS-CORE' } else { Bad 'fresh memo lacks AGENTS-CORE' }
  if ((Get-Content "$H/My-Work/.claude/settings.json" -Raw | ConvertFrom-Json).permissions.additionalDirectories -contains '../lite') { Ok 'Claude Code may read ../lite' } else { Bad 'no settings for ../lite' }
  $ev = @(Get-Content "$H/lite-install.log" | ForEach-Object { ($_ -split ' ')[1] }) -join ','
  $tsOk = @(Get-Content "$H/lite-install.log" | Where-Object { ($_ -split ' ')[0] -notmatch '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$' }).Count -eq 0
  if (($ev -eq 'started,archive_verified,consent_shown,consent_given,installed') -and $tsOk) { Ok 'event log: five steps with real UTC time' } else { Bad "event log: $ev"; Get-Content "$H/lite-install.log" }
  [IO.File]::WriteAllText("$H/My-Work/AGENTS.md", "old style memo`n")
  [IO.File]::WriteAllText("$H/My-Work/mine.txt", 'mine')
  [IO.File]::WriteAllText("$H/My-Work/Brain/03-Insights/2026-10-19-lesson.md", 'my note')
  [IO.File]::AppendAllText("$H/My-Work/Brain/README.md", 'edit')
  $mw = MwHash
  if ((Run 0 "$W/r101") -and ((LogText) -match 'New version: 1.0.1') -and ((LogText) -match 'Source: file:.*/download/v1\.0\.1') -and ((LogText) -match 'Installer: .*sha256') -and ((LogText) -match 'VERSION') -and ((Ver lite) -eq '1.0.0')) { Ok 'step 1 shows pinned source, installer hash, version, changed files; changes nothing' } else { Bad 'step 1 update'; LogText }
  if ((Run 1 $null) -and ((Ver lite) -eq '1.0.1') -and ((Ver lite-prev) -eq '1.0.0') -and ((MwHash) -eq $mw) -and -not (Test-Path "$H/_old") -and ((Get-Content "$H/My-Work/AGENTS.md" -First 1) -eq 'old style memo') -and (@(Select-String -Path "$H/My-Work/AGENTS.md" -Pattern 'AGENTS-CORE').Count -eq 2)) { Ok 'update: lite-prev kept, brain and files byte-identical, old memo got the AGENTS-CORE line' } else { Bad 'update'; LogText }
  if ((Run 2 $null) -and ((Ver lite) -eq '1.0.0')) { Ok 'rollback' } else { Bad 'rollback'; LogText }
  if ((Run 2 $null) -and ((Ver lite) -eq '1.0.1') -and ((MwHash) -eq $mw)) { Ok 'second rollback returns 1.0.1' } else { Bad 'second rollback'; LogText }
  New-Release (Join-Path $W 'r102') '1.0.2'
  Run 0 "$W/r102" | Out-Null
  $prevArc = @(Get-ChildItem "$H/_archive" -Directory -Filter 'lite-prev-*' -ErrorAction SilentlyContinue).Count
  if ((Run 1 $null) -and ((Ver lite-prev) -eq '1.0.1') -and (@(Get-ChildItem "$H/_archive" -Directory -Filter 'lite-prev-*').Count -eq $prevArc + 1) -and ((LogText) -match 'Folders in _archive')) { Ok 'third version: old lite-prev moved to _archive, not deleted' } else { Bad 'lite-prev to _archive'; LogText }
  $real = Join-Path $W 'rreal'; New-Item -ItemType Directory $real | Out-Null
  git -C $Repo archive --format=zip -0 --prefix=lite/ -o (Join-Path $real 'brain-lite.zip') HEAD
  [IO.File]::WriteAllText((Join-Path $real 'VERSION'), "$((git -C $Repo show HEAD:VERSION).Trim())`n"); Add-Installer $real
  if (Run 0 $real) { Ok 'real git-archive zip (with directory entries) passes path checks' } else { Bad 'real git-archive zip rejected'; LogText }
  $extra = Join-Path $W 'rextra'; New-Item -ItemType Directory $extra | Out-Null; Copy-Item "$W/r101/*" $extra
  Add-Content (Join-Path $extra 'SHA256SUMS.txt') ('0' * 64 + '  other-asset.txt')
  if (Run 0 $extra) { Ok 'extra line in SHA256SUMS is ignored' } else { Bad 'extra line in SHA256SUMS'; LogText }
  Publish "$W/r101" "$W/r100"
  if ((Run 0pin $null) -and ((LogText) -match 'New version: 1.0.0') -and ((LogText) -match 'download/v1\.0\.0')) { Ok 'pinned V=1.0.0 while latest is 1.0.1: exactly the pinned tag' } else { Bad 'pinned version'; LogText }

  'Interrupted update and changes between the steps'
  Run 0 "$W/r101" | Out-Null; Move-Item "$H/lite" "$H/_old"
  if ((Run 1 $null) -and ((Ver lite) -eq '1.0.1') -and ((Ver lite-prev) -eq '1.0.2') -and -not (Test-Path "$H/_old") -and ((LogText) -match 'Resuming an interrupted update')) { Ok 'update interrupted after lite -> _old: step 2 resumes, nothing lost' } else { Bad 'resume after _old'; LogText }
  Run 0 "$W/r102" | Out-Null; $l = TreeHash "$H/lite"; Add-Content "$H/_staging/install.ps1" '# extra line'
  if (Run 1 $null) { Bad 'installer changed between steps, step 2 went on' } elseif (((LogText) -match 'installer changed after step 1') -and ((TreeHash "$H/lite") -eq $l)) { Ok 'installer changed between steps: stop, lite intact' } else { Bad 'installer swap: wrong reason'; LogText }
  Run 0 "$W/r102" | Out-Null; Add-Content "$H/_staging/new/lite/AGENTS-CORE.md" 'tampered line'
  if ((Run 1 $null) -and ((Ver lite) -eq '1.0.2') -and ((Sha "$H/lite/AGENTS-CORE.md") -eq (Sha "$W/src-1.0.2/lite/AGENTS-CORE.md"))) { Ok 'display unpack tampered between steps: step 2 installs a fresh unpack of the verified archive' } else { Bad 'tampered unpack reached lite'; LogText }
  Run 2 $null | Out-Null; $l = TreeHash "$H/lite"
  Move-Item "$H/My-Work/Brain" "$W/brain-away"; New-Item -ItemType Directory -Force "$H/My-Work/.brain-copy/00-Inbox" | Out-Null
  if ((Run 0 "$W/r102") -and (Run 1 $null) -and (@(Get-ChildItem "$H/My-Work/Brain" -Recurse -Filter README.md).Count -eq 12) -and -not (Test-Path "$H/My-Work/.brain-copy") -and @(Get-ChildItem "$H/_archive" -Directory -Filter 'brain-partial-*').Count) { Ok 'cut brain copy is not taken for a finished one: archived, brain copied whole' } else { Bad 'cut brain copy'; LogText }
  Move-Item "$H/My-Work/Brain" "$W/brain-fresh"; Move-Item "$W/brain-away" "$H/My-Work/Brain"; Run 2 $null | Out-Null
  if ((TreeHash "$H/lite") -ne $l) { Bad 'setup for the next cases: lite did not come back' }
  # Stopped after "new lite in place", before _old moved: lite is compared with the archive, not trusted by VERSION.
  Run 0 "$W/r102" | Out-Null; Move-Item "$H/lite" "$H/_old"; Copy-Item -Recurse "$H/_staging/new/lite" "$H/lite"; Add-Content "$H/lite/AGENTS-CORE.md" 'tampered line'
  if (Run 1 $null) { Bad 'resume accepted a tampered lite by VERSION alone'; LogText } elseif (((LogText) -match 'does not match the verified archive') -and (Test-Path "$H/_old")) { Ok 'resume: tampered lite with the same VERSION refused, _old intact' } else { Bad 'resume with tamper: wrong reason'; LogText }
  Move-Item "$H/lite" "$W/lite-tampered"; Copy-Item -Recurse "$H/_staging/new/lite" "$H/lite"
  if ((Run 1 $null) -and ((Ver lite) -eq '1.0.2') -and ((Ver lite-prev) -eq '1.0.1') -and -not (Test-Path "$H/_old") -and ((LogText) -match 'matches the archive')) { Ok 'resume: whole lite of the same version accepted, _old became lite-prev' } else { Bad 'resume without tamper'; LogText }
  Run 2 $null | Out-Null
  # Swap done, stopped later (brain copy): rerunning step 2 keeps lite-prev, the rollback point survives.
  Run 0 "$W/r102" | Out-Null; New-Item -ItemType Directory -Force "$W/arch-sim" | Out-Null; Move-Item "$H/lite-prev" "$W/arch-sim/"; Move-Item "$H/lite" "$H/lite-prev"; Copy-Item -Recurse "$H/_staging/new/lite" "$H/lite"; Add-Content "$H/_staging/STATE" 'swapped=yes'
  if ((Run 1 $null) -and ((Ver lite) -eq '1.0.2') -and ((Ver lite-prev) -eq '1.0.1') -and ((LogText) -match 'the swap is done')) { Ok 'rerun of step 2 after a later stop: lite-prev stays the previous version' } else { Bad 'rerun moved the rollback point'; LogText }
  Run 2 $null | Out-Null
  if (((Ver lite) -ne '1.0.1') -or ((Ver lite-prev) -ne '1.0.2')) { Bad 'setup: rollback did not return 1.0.1/1.0.2' }
  $l = TreeHash "$H/lite"
  Run 0 "$W/r102" | Out-Null; [IO.File]::AppendAllText("$H/_staging/brain-lite.zip", 'x')
  if (Run 1 $null) { Bad 'archive changed between steps, step 2 went on' } elseif (((LogText) -match 'archive changed after step 1') -and ((TreeHash "$H/lite") -eq $l)) { Ok 'archive changed between steps: stop, lite intact' } else { Bad 'archive swap: wrong reason'; LogText }

  # Codex sandbox on Windows (acceptance run 03.11): no OS variable, and Windows PowerShell 5.1 has no $IsWindows,
  # so 'curl' became Invoke-WebRequest and step 1 stopped. curl.exe is now chosen by presence.
  $savedOS = $env:OS; Remove-Item Env:OS -ErrorAction SilentlyContinue
  $okNoOS = (Run 0 "$W/r102") -and ((LogText) -match 'New version: 1.0.2')
  $env:OS = $savedOS
  if ($okNoOS) { Ok 'step 1 without the OS variable (Codex sandbox): curl.exe found by presence' } else { Bad 'step 1 without OS variable'; LogText }
  # Acceptance 03.11: the CHANGELOG preview came out garbled in Windows PowerShell 5.1 (BOM-less UTF-8 read as ANSI).
  $word = -join [char[]](0x0418, 0x0437, 0x043C, 0x0435, 0x043D, 0x0435, 0x043D, 0x0438, 0x044F)
  Run 0 "$W/r102" | Out-Null
  $prev = Join-Path $W 'preview.txt'
  $PSExe = (Get-Process -Id $PID).Path
  Push-Location $H; & cmd /c "`"$PSExe`" -NoProfile -ExecutionPolicy Bypass -File _staging\install.ps1 prepare > `"$prev`" 2>&1"; Pop-Location
  if ([IO.File]::ReadAllText($prev, [Text.Encoding]::UTF8).Contains($word)) { Ok 'CHANGELOG preview is readable UTF-8 (Cyrillic not garbled)' } else { Bad 'CHANGELOG preview garbled'; Get-Content $prev -TotalCount 15 }
  # Same PowerShell process, same second: archive names must not collide (CI 03.11 put _staging inside an older archive).
  # Deterministic: the block runs in this process, so its name is staging-<second>-$PID; occupy the next 20 seconds.
  $t0 = [DateTime]::UtcNow
  0..20 | ForEach-Object { New-Item -ItemType Directory -Force (Join-Path $H ('_archive/staging-' + $t0.AddSeconds($_).ToString('yyyyMMddTHHmmssZ') + "-$PID")) | Out-Null }
  Publish "$W/r102"; 1..3 | ForEach-Object { Run 0 $null | Out-Null }
  $nested = @(Get-ChildItem "$H/_archive" -Directory | ForEach-Object { Get-ChildItem $_.FullName -Directory -Filter '*staging*' -ErrorAction SilentlyContinue })
  if (-not $nested.Count) { Ok 'step 1 three times in a row: each old _staging is its own folder in _archive' } else { Bad "step 1 in a row nested a folder: $($nested.FullName -join ', ')" }
  'Update check'
  if ((Run 3 "$W/r101") -and ((LogText) -match 'No updates, installed 1.0.1') -and (Test-Path "$H/My-Work/.lite-last-check")) { Ok 'check: same version' } else { Bad 'check: same'; LogText }
  New-Release (Join-Path $W 'r120') '1.2.0'
  if ((Run 3 "$W/r120") -and ((LogText) -match 'Update available: 1.0.1 -> 1.2.0') -and ((Ver lite) -eq '1.0.1')) { Ok 'check: newer version, nothing installed' } else { Bad 'check: newer'; LogText }
  if ((Run 3 "$W/r102") -and ((LogText) -match 'rolled back')) { Ok 'check: rolled back from latest' } else { Bad 'check: rollback'; LogText }
  New-Item -ItemType Directory -Force "$W/rnocheck" | Out-Null
  if ((Run 3 "$W/rnocheck") -and ((LogText) -match 'Could not check')) { Ok 'check without network: polite' } else { Bad 'check offline'; LogText }
  New-Item -ItemType Directory -Force "$W/rjunk" | Out-Null; [IO.File]::WriteAllText("$W/rjunk/VERSION", '<html>')
  if ((Run 3 "$W/rjunk") -and ((LogText) -match 'Could not check')) { Ok 'check: junk is not a version' } else { Bad 'check junk'; LogText }

  'Red'
  function ExpectStop($name, $relDir, $pattern) {
    $before = TreeHash "$H/lite"
    if (Run 0 $relDir) { Bad "${name}: recipe did NOT stop"; LogText }
    elseif ((LogText) -notmatch $pattern) { Bad "${name}: stopped for a different reason"; LogText }
    elseif (((TreeHash "$H/lite") -ne $before) -or (Test-Path "$H/_staging/new")) { Bad "${name}: something was extracted or replaced" }
    else { Ok $name }
  }
  New-Item -ItemType Directory "$W/rswap" | Out-Null; Copy-Item "$W/r100/brain-lite.zip", "$W/r100/install.sh", "$W/r100/install.ps1", "$W/r100/VERSION" "$W/rswap/"; Copy-Item "$W/r101/SHA256SUMS.txt" "$W/rswap/"
  ExpectStop 'valid archive, checksum of another' "$W/rswap" 'checksum mismatch'
  New-Item -ItemType Directory "$W/rbadinst" | Out-Null; Copy-Item "$W/r101/*" "$W/rbadinst/"; Add-Content "$W/rbadinst/install.ps1" "'swapped'"
  ExpectStop 'swapped installer is not started' "$W/rbadinst" 'install.ps1 checksum mismatch'
  New-EvilZip "$W/rslip" @('lite/VERSION', 'lite/../evil.md'); ExpectStop 'zip-slip' "$W/rslip" 'suspicious paths'
  New-EvilZip "$W/rout" @('lite/VERSION', 'other/x.md'); ExpectStop 'path outside lite/' "$W/rout" 'suspicious paths'
  New-EvilZip "$W/rupper" @('lite/VERSION', 'LITE/x.md'); ExpectStop 'LITE/ in other case' "$W/rupper" 'suspicious paths'
  New-EvilZip "$W/rbslash" @('lite/VERSION', 'lite\..\..\evil.md'); ExpectStop 'backslash zip-slip' "$W/rbslash" 'suspicious paths'
  New-EvilZip "$W/rnotpl" @('lite/VERSION', 'lite/RULES.md', 'lite/UPDATE.md', 'lite/CHANGELOG.md'); ExpectStop 'missing required file' "$W/rnotpl" 'archive has no lite/templates'
  New-Item -ItemType Directory -Force "$W/rlink" | Out-Null
  $z = [IO.Compression.ZipFile]::Open((Join-Path "$W/rlink" 'brain-lite.zip'), 'Create')
  $e = $z.CreateEntry('lite/VERSION'); $sw = New-Object IO.StreamWriter($e.Open()); $sw.Write('9.9.9'); $sw.Dispose()
  $e = $z.CreateEntry('lite/CHANGELOG.md'); $e.ExternalAttributes = [int](0xA1FF -shl 16); $sw = New-Object IO.StreamWriter($e.Open()); $sw.Write('/etc/hosts'); $sw.Dispose()
  $z.Dispose(); Add-Installer "$W/rlink"; ExpectStop 'symlink entry in archive' "$W/rlink" 'links to outside files'
  New-Item -ItemType Directory "$W/rnone" | Out-Null; ExpectStop 'no release (no VERSION)' "$W/rnone" 'cannot get the latest version'

  Move-Item "$H/_staging" "$W/staging-away"
  if (Run 1 $null) { Bad 'step 2 before step 1 did not stop' } elseif ((LogText) -match 'run step 1 first') { Ok 'step 2 before step 1: stop' } else { Bad 'step 2 before step 1: wrong reason'; LogText }
  foreach ($junk in '_swap', '_old') {
    New-Item -ItemType Directory "$H/$junk" | Out-Null
    Run 0 "$W/r100" | Out-Null
    if (Run 1 $null) { Bad "step 2 with stale $junk did not stop" } elseif ((LogText) -match $junk) { Ok "step 2 with stale ${junk}: stop" } else { Bad "step 2 ${junk}: wrong reason"; LogText }
    if (Run 2 $null) { Bad "rollback with stale $junk did not stop" } elseif ((LogText) -match $junk) { Ok "rollback with stale ${junk}: stop" } else { Bad "rollback ${junk}: wrong reason"; LogText }
    Move-Item "$H/$junk" "$W/away$junk"
  }
  if (((Ver lite) -eq '1.0.1') -and ((Ver lite-prev) -eq '1.0.2')) { Ok 'after all stops lite 1.0.1 and lite-prev 1.0.2 intact' } else { Bad "stops damaged lite: $(Ver lite) / $(Ver lite-prev)" }
  if (Run 0 "$W/r100" $W "$H/lite/.claude") { Bad 'step 1 from inside lite did not stop' } elseif ((LogText) -match 'open inside lite') { Ok 'step 1 from inside lite: stop' } else { Bad 'inside lite: wrong reason'; LogText }

  'Self-check'
  $mut = Join-Path $W 'rmut'; New-Item -ItemType Directory $mut | Out-Null; Copy-Item "$W/rswap/*" $mut
  $m = $Inst.Replace("if ((Sha `$zipPath) -ne `$expected) { Stop-Here 'checksum mismatch' }", '')
  if ($m -eq $Inst) { Bad 'mutant equals the installer: the checksum line was not found' }
  [IO.File]::WriteAllText("$mut/install.ps1", $m)
  $sums = @(Get-Content "$mut/SHA256SUMS.txt" | Where-Object { $_ -notmatch 'install\.ps1$' }) + "$(Sha "$mut/install.ps1")  install.ps1"
  [IO.File]::WriteAllText("$mut/SHA256SUMS.txt", (($sums -join "`n") + "`n"))
  if (Run 0 $mut) { Ok 'mutant without checksum check lets the swap through: test is sensitive' } else { Bad 'mutant also stopped'; LogText }
  if (Run 0 "$W/rswap") { Bad 'real recipe let the swap through' } else { Ok 'real recipe catches the same swap' }
}
finally {
  Set-Location $Repo
  Remove-Item -Recurse -Force $W -ErrorAction SilentlyContinue
}
"TOTAL ($($PSVersionTable.PSVersion)): $script:Pass ok, $script:Fail FAIL"
if ($script:Fail) { exit 1 } else { exit 0 }
