# test_update.ps1: runs EXACTLY the ```powershell blocks of UPDATE.md against a local file:// "release".
# ASCII only on purpose: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
# The only substitution in the blocks: https://github.com/tonydzi/brain-lite/releases/ -> file:///<tmp>/releases/,
# '=https' -> '=file', and Join-Path $HOME -> Join-Path '<tmp home>'.
# Green: install, update 1.0.0 -> 1.0.1, rollback twice, My-Work untouched, real git-archive zip with dir entries.
# Red (recipe must stop and change nothing): swapped checksum, zip-slip, path outside lite/, LITE/ case trick,
# missing required file, stale _swap/_old, step 2 before step 1, run from inside lite.
# Self-check: recipe with the checksum comparison removed must let the swapped archive through.
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
$Rel = Join-Path $W 'releases/latest/download'
$RelUrl = [Uri]::new((Join-Path $W 'releases') + [IO.Path]::DirectorySeparatorChar).AbsoluteUri

$text = [IO.File]::ReadAllText((Join-Path $Repo 'UPDATE.md'), [Text.Encoding]::UTF8)
$win = $text.Substring($text.IndexOf('## Windows'))
$blocks = @([regex]::Matches($win, '```powershell\r?\n(.*?)```', 'Singleline') | ForEach-Object { $_.Groups[1].Value })
if ($blocks.Count -ne 3) { throw "expected 3 powershell blocks, found $($blocks.Count)" }
for ($i = 0; $i -lt 3; $i++) {
  $b = $blocks[$i].Replace('https://github.com/tonydzi/brain-lite/releases/', $RelUrl).Replace('=https', '=file').Replace('Join-Path $HOME', "Join-Path '$HomeDir'")
  if ($b -match '[^\x00-\x7F]') { throw "block $i has non-ASCII characters (breaks Windows PowerShell 5.1)" }
  [IO.File]::WriteAllText((Join-Path $W "block$i.ps1"), $b)
}

function Sha($p) { (Get-FileHash $p -Algorithm SHA256).Hash.ToLower() }
function Write-Sums($dir) { [IO.File]::WriteAllText((Join-Path $dir 'SHA256SUMS.txt'), "$(Sha (Join-Path $dir 'brain-lite.zip'))  brain-lite.zip`n") }
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
  Write-Sums $dir
}
function New-EvilZip($dir, $names) {
  New-Item -ItemType Directory -Force $dir | Out-Null
  $z = [IO.Compression.ZipFile]::Open((Join-Path $dir 'brain-lite.zip'), 'Create')
  foreach ($n in $names) { $e = $z.CreateEntry($n); $s = New-Object IO.StreamWriter($e.Open()); $s.Write('9.9.9'); $s.Dispose() }
  $z.Dispose(); Write-Sums $dir
}
$H = Join-Path $HomeDir 'Second-Brain-Lite'
$Log = Join-Path $W 'last.log'
function Run($n, $relDir, $recipeDir = $W, $cwd = $W) {
  if (Test-Path $Rel) { Remove-Item -Recurse -Force $Rel }
  New-Item -ItemType Directory -Force $Rel | Out-Null
  if ($relDir) { Copy-Item (Join-Path $relDir '*') $Rel }
  $here = Get-Location
  Set-Location $cwd
  try { & (Join-Path $recipeDir "block$n.ps1") *> $Log; return $true }
  catch { $_.ToString() | Add-Content $Log; return $false }
  finally { Set-Location $here }
}
function TreeHash($p) { (Get-ChildItem $p -Recurse -File -Force | Sort-Object FullName | ForEach-Object { Sha $_.FullName }) -join ',' }
function LogText { if (Test-Path $Log) { [IO.File]::ReadAllText($Log) } else { '' } }
function Ver($p) { (Get-Content (Join-Path $H "$p/VERSION") -ErrorAction SilentlyContinue | Select-Object -First 1) }

try {
  'Green'
  New-Release (Join-Path $W 'r100') '1.0.0'; New-Release (Join-Path $W 'r101') '1.0.1'
  if ((Run 0 "$W/r100") -and (Run 1 $null) -and ((Ver lite) -eq '1.0.0') -and (Test-Path "$H/My-Work/AGENTS.md") -and (Test-Path "$H/lite/.claude/skills/lite-check/SKILL.md") -and -not (Test-Path "$H/_dl")) { Ok 'fresh install' } else { Bad 'fresh install'; LogText }
  [IO.File]::WriteAllText("$H/My-Work/mine.txt", 'mine'); $mw = TreeHash "$H/My-Work"
  if ((Run 0 "$W/r101") -and ((LogText) -match 'New version: 1.0.1') -and ((LogText) -match 'Source: file:') -and ((LogText) -match 'VERSION') -and ((Ver lite) -eq '1.0.0')) { Ok 'step 1 shows source, version, changed files; changes nothing' } else { Bad 'step 1 update'; LogText }
  if ((Run 1 $null) -and ((Ver lite) -eq '1.0.1') -and ((Ver lite-prev) -eq '1.0.0') -and ((TreeHash "$H/My-Work") -eq $mw) -and -not (Test-Path "$H/_old")) { Ok 'update, lite-prev kept, My-Work byte-identical' } else { Bad 'update'; LogText }
  if ((Run 2 $null) -and ((Ver lite) -eq '1.0.0')) { Ok 'rollback' } else { Bad 'rollback'; LogText }
  if ((Run 2 $null) -and ((Ver lite) -eq '1.0.1') -and ((TreeHash "$H/My-Work") -eq $mw)) { Ok 'second rollback returns 1.0.1' } else { Bad 'second rollback'; LogText }
  $real = Join-Path $W 'rreal'; New-Item -ItemType Directory $real | Out-Null
  git -C $Repo archive --format=zip -0 --prefix=lite/ -o (Join-Path $real 'brain-lite.zip') HEAD; Write-Sums $real
  if (Run 0 $real) { Ok 'real git-archive zip (with directory entries) passes path checks' } else { Bad 'real git-archive zip rejected'; LogText }
  $extra = Join-Path $W 'rextra'; New-Item -ItemType Directory $extra | Out-Null; Copy-Item "$W/r101/*" $extra
  Add-Content (Join-Path $extra 'SHA256SUMS.txt') ('0' * 64 + '  other-asset.txt')
  if (Run 0 $extra) { Ok 'extra line in SHA256SUMS is ignored' } else { Bad 'extra line in SHA256SUMS'; LogText }
  Remove-Item -Recurse -Force "$H/_dl"

  'Red'
  function ExpectStop($name, $relDir, $pattern) {
    $before = TreeHash "$H/lite"
    if (Run 0 $relDir) { Bad "${name}: recipe did NOT stop"; LogText }
    elseif ((LogText) -notmatch $pattern) { Bad "${name}: stopped for a different reason"; LogText }
    elseif (((TreeHash "$H/lite") -ne $before) -or (Test-Path "$H/_dl/new")) { Bad "${name}: something was extracted or replaced" }
    else { Ok $name }
  }
  New-Item -ItemType Directory "$W/rswap" | Out-Null; Copy-Item "$W/r100/brain-lite.zip" "$W/rswap/"; Copy-Item "$W/r101/SHA256SUMS.txt" "$W/rswap/"
  ExpectStop 'valid archive, checksum of another' "$W/rswap" 'checksum mismatch'
  New-EvilZip "$W/rslip" @('lite/VERSION', 'lite/../evil.md'); ExpectStop 'zip-slip' "$W/rslip" 'suspicious paths'
  New-EvilZip "$W/rout" @('lite/VERSION', 'other/x.md'); ExpectStop 'path outside lite/' "$W/rout" 'suspicious paths'
  New-EvilZip "$W/rupper" @('lite/VERSION', 'LITE/x.md'); ExpectStop 'LITE/ in other case' "$W/rupper" 'suspicious paths'
  New-EvilZip "$W/rbslash" @('lite/VERSION', 'lite\..\..\evil.md'); ExpectStop 'backslash zip-slip' "$W/rbslash" 'suspicious paths'
  New-EvilZip "$W/rnotpl" @('lite/VERSION', 'lite/RULES.md', 'lite/UPDATE.md', 'lite/CHANGELOG.md'); ExpectStop 'missing required file' "$W/rnotpl" 'archive has no lite/templates'
  New-Item -ItemType Directory -Force "$W/rlink" | Out-Null
  $z = [IO.Compression.ZipFile]::Open((Join-Path "$W/rlink" 'brain-lite.zip'), 'Create')
  $e = $z.CreateEntry('lite/VERSION'); $sw = New-Object IO.StreamWriter($e.Open()); $sw.Write('9.9.9'); $sw.Dispose()
  $e = $z.CreateEntry('lite/CHANGELOG.md'); $e.ExternalAttributes = [int](0xA1FF -shl 16); $sw = New-Object IO.StreamWriter($e.Open()); $sw.Write('/etc/hosts'); $sw.Dispose()
  $z.Dispose(); Write-Sums "$W/rlink"; ExpectStop 'symlink entry in archive' "$W/rlink" 'links to outside files'
  New-Item -ItemType Directory "$W/rnone" | Out-Null; ExpectStop 'no release (download fails)' "$W/rnone" 'download of SHA256SUMS.txt failed'

  if (Run 1 $null) { Bad 'step 2 before step 1 did not stop' } elseif ((LogText) -match 'run step 1 first') { Ok 'step 2 before step 1: stop' } else { Bad 'step 2 before step 1: wrong reason'; LogText }
  foreach ($junk in '_swap', '_old') {
    New-Item -ItemType Directory "$H/$junk" | Out-Null
    Run 0 "$W/r100" | Out-Null
    if (Run 1 $null) { Bad "step 2 with stale $junk did not stop" } elseif ((LogText) -match $junk) { Ok "step 2 with stale ${junk}: stop" } else { Bad "step 2 ${junk}: wrong reason"; LogText }
    if (Run 2 $null) { Bad "rollback with stale $junk did not stop" } elseif ((LogText) -match $junk) { Ok "rollback with stale ${junk}: stop" } else { Bad "rollback ${junk}: wrong reason"; LogText }
    Remove-Item "$H/$junk"; Remove-Item -Recurse -Force "$H/_dl"
  }
  if (((Ver lite) -eq '1.0.1') -and ((Ver lite-prev) -eq '1.0.0')) { Ok 'after all stops lite 1.0.1 and lite-prev 1.0.0 intact' } else { Bad 'stops damaged lite' }
  if (Run 0 "$W/r100" $W "$H/lite/.claude") { Bad 'step 1 from inside lite did not stop' } elseif ((LogText) -match 'open inside lite') { Ok 'step 1 from inside lite: stop' } else { Bad 'inside lite: wrong reason'; LogText }

  'Self-check'
  $mut = Join-Path $W 'mut'; New-Item -ItemType Directory $mut | Out-Null; Copy-Item "$W/block*.ps1" $mut
  $m = [IO.File]::ReadAllText("$W/block0.ps1") -replace "if \(\`$expected -ne \`$actual\) \{ throw 'STOP: checksum mismatch' \}", ''
  [IO.File]::WriteAllText("$mut/block0.ps1", $m)
  if (Run 0 "$W/rswap" $mut) { Ok 'mutant without checksum check lets the swap through: test is sensitive' } else { Bad 'mutant also stopped'; LogText }
  if (Run 0 "$W/rswap") { Bad 'real recipe let the swap through' } else { Ok 'real recipe catches the same swap' }
}
finally {
  Set-Location $Repo
  Remove-Item -Recurse -Force $W -ErrorAction SilentlyContinue
}
"TOTAL ($($PSVersionTable.PSVersion)): $script:Pass ok, $script:Fail FAIL"
if ($script:Fail) { exit 1 } else { exit 0 }
