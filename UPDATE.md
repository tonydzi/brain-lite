# Установка, обновление и откат

Этот рецепт выполняет **помощник владельца** по его прямой просьбе: «установи лайт»,
«обнови лайт» или «откати лайт» (пункт 11 в [RULES.md](RULES.md)). Человеку ничего
печатать в Терминале не нужно. Помощник выполняет блоки как есть, по порядку,
и останавливается на любой ошибке.

Что получится на компьютере:

```
Second-Brain-Lite/      в домашней папке владельца
  lite/        текущая версия, только для чтения
  lite-prev/   прошлая версия, для отката
  My-Work/     личные файлы владельца; рецепт их не читает и никуда не отправляет
```

Источник один: релизы `https://github.com/tonydzi/brain-lite/releases`. В каждом релизе:
`brain-lite.zip` (библиотека), `SHA256SUMS.txt` (контрольная сумма архива), `UPDATE.md` (этот рецепт)
и `VERSION` (номер версии, для ежедневной проверки). Новые релизы выходят сами, когда мы улучшаем
закон, скиллы или шаблоны; ставит их у себя только владелец, после своего «да».

**Жёсткие правила для помощника:**

- Любой `СТОП`: ничего не заменять, показать владельцу вывод. Проверки не отключать,
  не обходить, не скачивать «откуда-то ещё», источник в блоках не менять.
- Перед заменой показать владельцу вывод шага 1 (версии, изменённые файлы, начало
  `CHANGELOG.md`) и дождаться его «да».
- `My-Work` не читать, не менять и не удалять. Создать её можно, только если её нет.
- Никаких других программ, служб, расписаний и синхронизации этот рецепт не ставит.
- Помощника не держать открытым внутри `lite` или `lite-prev`: на Windows такую папку
  нельзя переименовать. Работать из `My-Work` или из `Second-Brain-Lite`.

Что честно даёт проверка суммы: архив скачан целым и совпадает с тем, что выложено в релизе.
Она не защищает, если кто-то получит доступ к самому репозиторию и подменит оба файла;
поэтому сумма каждой версии ещё и записана в описании релиза, а CI пересобирает архив
из тега и сверяет.

Этот же файл лежит третьим файлом в каждом релизе (`.../releases/latest/download/UPDATE.md`),
поэтому рецепт и архив всегда одной версии.

Нужна не последняя, а конкретная версия: в строке `BASE=` (или `$Base =`) замените
`releases/latest/download` на `releases/download/v1.1.0` (нужный тег; закон, мозг и проверка
обновлений есть начиная с v1.1.0).
Папка установки не `~/Second-Brain-Lite`: поменяйте строку `ROOT=` (или `$Root =`)
во всех блоках одинаково.

## Mac и Linux

Блоки работают в bash, zsh и sh.

### Шаг 1. Скачать, проверить, показать

```sh
set -eu
ROOT="$HOME/Second-Brain-Lite"
BASE="https://github.com/tonydzi/brain-lite/releases/latest/download"
case "$BASE" in https://github.com/tonydzi/brain-lite/releases/*) ;; *) echo "СТОП: чужой источник $BASE"; exit 1 ;; esac
HERE=$(pwd -P)
ROOTP=$( (cd "$ROOT" 2>/dev/null && pwd -P) || echo "$ROOT" )
case "$HERE/" in "$ROOTP/lite/"*|"$ROOTP/lite-prev/"*) echo "СТОП: помощник открыт внутри lite, откройте его в My-Work"; exit 1 ;; esac
echo "Папка установки: $ROOT"
echo "Источник: $BASE"
mkdir -p "$ROOT"
cd "$ROOT"
[ -d lite ] || echo "Папки lite ещё нет: это первая установка"
rm -rf _dl
mkdir _dl
cd _dl
curl -fsSL --proto '=https' --proto-redir '=https' -o SHA256SUMS.txt "$BASE/SHA256SUMS.txt"
curl -fsSL --proto '=https' --proto-redir '=https' -o brain-lite.zip "$BASE/brain-lite.zip"
grep -E '[ *]brain-lite[.]zip$' SHA256SUMS.txt > zip.sha256 || { echo "СТОП: в SHA256SUMS.txt нет строки архива"; exit 1; }
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 -c zip.sha256 || { echo "СТОП: контрольная сумма не совпала"; exit 1; }
else
  sha256sum -c zip.sha256 || { echo "СТОП: контрольная сумма не совпала"; exit 1; }
fi
LIST=$(unzip -Z1 brain-lite.zip) || { echo "СТОП: не могу прочитать список архива"; exit 1; }
BAD=$(printf '%s\n' "$LIST" | grep -vE '^lite/' || true)
SLIP=$(printf '%s\n' "$LIST" | grep -E '(^|/)[.][.](/|$)' || true)
[ -z "$BAD$SLIP" ] || { echo "СТОП: подозрительные пути в архиве:"; echo "$BAD$SLIP"; exit 1; }
TYPES=$(unzip -Z brain-lite.zip) || { echo "СТОП: не могу прочитать список архива"; exit 1; }
if printf '%s\n' "$TYPES" | grep -q '^l'; then echo "СТОП: в архиве ссылки на чужие файлы"; exit 1; fi
unzip -q brain-lite.zip -d new
if [ -n "$(find new -type l)" ]; then rm -rf new; echo "СТОП: в архиве ссылки на чужие файлы"; exit 1; fi
for f in VERSION RULES.md UPDATE.md CHANGELOG.md templates/My-Work-AGENTS.md; do
  [ -f "new/lite/$f" ] || { rm -rf new; echo "СТОП: в архиве нет lite/$f"; exit 1; }
done
echo "Новая версия: $(cat new/lite/VERSION)"
if [ -d ../lite ]; then
  echo "Текущая версия: $(cat ../lite/VERSION 2>/dev/null || echo неизвестна)"
  echo "Изменённые файлы:"
  diff -rq ../lite new/lite || true
fi
echo "Начало CHANGELOG:"
head -n 20 new/lite/CHANGELOG.md
```

Помощник показывает этот вывод владельцу и ждёт «да». Нет «да»: удалить только `_dl`, ничего больше.

### Шаг 2. Заменить версию (после «да»)

```sh
set -eu
ROOT="$HOME/Second-Brain-Lite"
HERE=$(pwd -P)
ROOTP=$( (cd "$ROOT" 2>/dev/null && pwd -P) || echo "$ROOT" )
case "$HERE/" in "$ROOTP/lite/"*|"$ROOTP/lite-prev/"*) echo "СТОП: помощник открыт внутри lite, откройте его в My-Work"; exit 1 ;; esac
cd "$ROOT"
[ ! -e _swap ] || { echo "СТОП: остался _swap от прерванного отката, см. «Если не получилось»"; exit 1; }
[ ! -e _old ] || { echo "СТОП: осталась _old от прерванной замены, см. «Если не получилось»"; exit 1; }
[ -f _dl/new/lite/VERSION ] || { echo "СТОП: сначала шаг 1"; exit 1; }
if [ -d lite ]; then mv lite _old; fi
mv _dl/new/lite lite
if [ -d _old ]; then rm -rf lite-prev; mv _old lite-prev; fi
rm -rf _dl
mkdir -p My-Work
[ -e My-Work/AGENTS.md ] || cp lite/templates/My-Work-AGENTS.md My-Work/AGENTS.md
[ -e My-Work/CLAUDE.md ] || printf '@AGENTS.md\n' > My-Work/CLAUDE.md
if [ -f lite/AGENTS-CORE.md ] && ! grep -q 'AGENTS-CORE' My-Work/AGENTS.md; then
  printf '\n<!-- brain-lite: AGENTS-CORE -->\nВ начале каждого чата прочитай ../lite/AGENTS-CORE.md и действуй по нему.\n' >> My-Work/AGENTS.md
  echo "В памятку My-Work/AGENTS.md добавлена строка про ../lite/AGENTS-CORE.md"
fi
if [ -d lite/brain ] && [ ! -e My-Work/Brain ]; then cp -R lite/brain My-Work/Brain; echo "Второй мозг создан: My-Work/Brain"; fi
echo "Готово: lite $(cat lite/VERSION)"
if [ -d lite-prev ]; then echo "Для отката: lite-prev $(cat lite-prev/VERSION 2>/dev/null || echo неизвестна)"; fi
```

Старая версия удаляется только после того, как новая уже стоит на месте.

### Откат

```sh
set -eu
ROOT="$HOME/Second-Brain-Lite"
HERE=$(pwd -P)
ROOTP=$( (cd "$ROOT" 2>/dev/null && pwd -P) || echo "$ROOT" )
case "$HERE/" in "$ROOTP/lite/"*|"$ROOTP/lite-prev/"*) echo "СТОП: помощник открыт внутри lite, откройте его в My-Work"; exit 1 ;; esac
cd "$ROOT"
[ ! -e _swap ] || { echo "СТОП: остался _swap от прерванного отката, см. «Если не получилось»"; exit 1; }
[ ! -e _old ] || { echo "СТОП: осталась _old от прерванной замены, см. «Если не получилось»"; exit 1; }
[ -f lite-prev/VERSION ] || { echo "СТОП: прошлой версии нет"; exit 1; }
[ -f lite/VERSION ] || { echo "СТОП: нет текущей lite, см. «Если не получилось»"; exit 1; }
mv lite _swap
mv lite-prev lite
mv _swap lite-prev
echo "Теперь lite $(cat lite/VERSION), в lite-prev $(cat lite-prev/VERSION)"
```

Откат обратим: повторный откат возвращает версию назад.

### Проверка обновления (раз в день, ничего не меняет)

```sh
ROOT="$HOME/Second-Brain-Lite"
URL="https://github.com/tonydzi/brain-lite/releases/latest/download/VERSION"
CUR=$(cat "$ROOT/lite/VERSION" 2>/dev/null || echo нет)
PREV=$(cat "$ROOT/lite-prev/VERSION" 2>/dev/null || echo нет)
NEW=$(curl -fsSL --proto '=https' --proto-redir '=https' --max-time 20 "$URL" 2>/dev/null | head -n 1 || true)
[ -d "$ROOT/My-Work" ] && date +%Y-%m-%d > "$ROOT/My-Work/.lite-last-check" 2>/dev/null || true
case "$NEW" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "Проверить обновление не получилось (нет сети?). Установлено: $CUR"; exit 0 ;;
esac
if [ "$NEW" = "$CUR" ]; then echo "Обновлений нет, установлено $CUR"
elif [ "$NEW" = "$PREV" ]; then echo "Последняя версия $NEW, вы откатились с неё на $CUR"
else echo "Есть обновление: $CUR -> $NEW. Скажите «обнови лайт»"; fi
```

Помощник сообщает владельцу одну строку и ничего не скачивает и не меняет.

## Windows (PowerShell)

Встроенные `curl.exe`, `Get-FileHash` и `Expand-Archive` есть в Windows 10 и 11; ставить ничего не надо.
Блоки написаны только латиницей, поэтому кодировка файла их не ломает. Вставлять блок
в PowerShell целиком, или сохранить его в `.ps1` и запустить
`powershell -NoProfile -ExecutionPolicy Bypass -File <файл>.ps1` (политика меняется только
для этого запуска). Сообщения блоков по-английски: `STOP: ...` значит то же, что `СТОП`.

### Шаг 1. Скачать, проверить, показать

```powershell
$ErrorActionPreference = 'Stop'
$Root = Join-Path $HOME 'Second-Brain-Lite'
$Base = 'https://github.com/tonydzi/brain-lite/releases/latest/download'
if ($Base -notlike 'https://github.com/tonydzi/brain-lite/releases/*') { throw "STOP: foreign source $Base" }
$here = (Get-Location).ProviderPath.TrimEnd('\', '/')
foreach ($d in 'lite', 'lite-prev') { $p = (Join-Path $Root $d); if ($here -eq $p -or $here.StartsWith($p + [IO.Path]::DirectorySeparatorChar)) { throw 'STOP: the assistant is open inside lite, open it in My-Work' } }
"Install folder: $Root"
"Source: $Base"
$Curl = if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'curl.exe' } else { 'curl' }
New-Item -ItemType Directory -Force $Root | Out-Null
Set-Location $Root
if (-not (Test-Path lite)) { 'No lite folder yet: first install' }
if (Test-Path _dl) { Remove-Item -Recurse -Force _dl }
New-Item -ItemType Directory _dl | Out-Null
$ErrorActionPreference = 'Continue'  # PowerShell 5.1 turns curl's stderr into an exception before the check below
& $Curl -fsSL --proto '=https' --proto-redir '=https' -o _dl/SHA256SUMS.txt "$Base/SHA256SUMS.txt"; $rc1 = $LASTEXITCODE
if (-not $rc1) { & $Curl -fsSL --proto '=https' --proto-redir '=https' -o _dl/brain-lite.zip "$Base/brain-lite.zip"; $rc2 = $LASTEXITCODE }
$ErrorActionPreference = 'Stop'
if ($rc1) { throw 'STOP: download of SHA256SUMS.txt failed' }
if ($rc2) { throw 'STOP: download of brain-lite.zip failed' }
$line = Get-Content _dl/SHA256SUMS.txt | Where-Object { $_ -match '[ *]brain-lite\.zip$' } | Select-Object -First 1
if (-not $line) { throw 'STOP: no archive line in SHA256SUMS.txt' }
$expected = ($line -split '\s+')[0].ToLower()
$actual = (Get-FileHash _dl/brain-lite.zip -Algorithm SHA256).Hash.ToLower()
if ($expected -ne $actual) { throw 'STOP: checksum mismatch' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path _dl/brain-lite.zip).Path)
$bad = @($zip.Entries | Where-Object { $_.FullName -cnotlike 'lite/*' -or $_.FullName -match '(^|[\\/])\.\.([\\/]|$)' -or $_.FullName -match '^[\\/]|:' })
$links = @($zip.Entries | Where-Object { (($_.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000 })
$zip.Dispose()
if ($bad.Count) { throw "STOP: suspicious paths in archive: $($bad.FullName -join ', ')" }
if ($links.Count) { throw "STOP: links to outside files in archive: $($links.FullName -join ', ')" }
Expand-Archive _dl/brain-lite.zip -DestinationPath _dl/new
if (@(Get-ChildItem _dl/new -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { Remove-Item -Recurse -Force _dl/new; throw 'STOP: links to outside files in archive' }
foreach ($f in 'VERSION', 'RULES.md', 'UPDATE.md', 'CHANGELOG.md', 'templates/My-Work-AGENTS.md') {
  if (-not (Test-Path "_dl/new/lite/$f")) { Remove-Item -Recurse -Force _dl/new; throw "STOP: archive has no lite/$f" }
}
"New version: $(Get-Content _dl/new/lite/VERSION)"
function Get-Tree($p) { $r = (Resolve-Path $p).Path; Get-ChildItem $p -Recurse -File -Force | ForEach-Object { [pscustomobject]@{ File = $_.FullName.Substring($r.Length); Hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash } } }
if (Test-Path lite) {
  "Current version: $(Get-Content lite/VERSION -ErrorAction SilentlyContinue)"
  'Changed files:'
  Compare-Object @(Get-Tree lite) @(Get-Tree _dl/new/lite) -Property File, Hash | Select-Object -ExpandProperty File -Unique
}
'CHANGELOG head:'
Get-Content _dl/new/lite/CHANGELOG.md -TotalCount 20
```

### Шаг 2. Заменить версию (после «да»)

```powershell
$ErrorActionPreference = 'Stop'
$Root = Join-Path $HOME 'Second-Brain-Lite'
$here = (Get-Location).ProviderPath.TrimEnd('\', '/')
foreach ($d in 'lite', 'lite-prev') { $p = (Join-Path $Root $d); if ($here -eq $p -or $here.StartsWith($p + [IO.Path]::DirectorySeparatorChar)) { throw 'STOP: the assistant is open inside lite, open it in My-Work' } }
Set-Location $Root
if (Test-Path _swap) { throw 'STOP: _swap left from an interrupted rollback, see troubleshooting' }
if (Test-Path _old) { throw 'STOP: _old left from an interrupted update, see troubleshooting' }
if (-not (Test-Path _dl/new/lite/VERSION)) { throw 'STOP: run step 1 first' }
if (Test-Path lite) { Move-Item lite _old }
Move-Item _dl/new/lite lite
if (Test-Path _old) { if (Test-Path lite-prev) { Remove-Item -Recurse -Force lite-prev }; Move-Item _old lite-prev }
Remove-Item -Recurse -Force _dl
New-Item -ItemType Directory -Force My-Work | Out-Null
if (-not (Test-Path My-Work/AGENTS.md)) { Copy-Item lite/templates/My-Work-AGENTS.md My-Work/AGENTS.md }
if (-not (Test-Path My-Work/CLAUDE.md)) { Set-Content -Path My-Work/CLAUDE.md -Value '@AGENTS.md' }
if ((Test-Path lite/AGENTS-CORE.md) -and -not (Select-String -Path My-Work/AGENTS.md -Pattern 'AGENTS-CORE' -Quiet)) {
  Add-Content -Path My-Work/AGENTS.md -Value "`n<!-- brain-lite: AGENTS-CORE -->`nAt the start of every chat read ../lite/AGENTS-CORE.md and follow it."
  'Added a line about ../lite/AGENTS-CORE.md to My-Work/AGENTS.md'
}
if ((Test-Path lite/brain) -and -not (Test-Path My-Work/Brain)) { Copy-Item -Recurse lite/brain My-Work/Brain; 'Second brain created: My-Work/Brain' }
"Done: lite $(Get-Content lite/VERSION)"
if (Test-Path lite-prev) { "For rollback: lite-prev $(Get-Content lite-prev/VERSION -ErrorAction SilentlyContinue)" }
```

### Откат

```powershell
$ErrorActionPreference = 'Stop'
$Root = Join-Path $HOME 'Second-Brain-Lite'
$here = (Get-Location).ProviderPath.TrimEnd('\', '/')
foreach ($d in 'lite', 'lite-prev') { $p = (Join-Path $Root $d); if ($here -eq $p -or $here.StartsWith($p + [IO.Path]::DirectorySeparatorChar)) { throw 'STOP: the assistant is open inside lite, open it in My-Work' } }
Set-Location $Root
if (Test-Path _swap) { throw 'STOP: _swap left from an interrupted rollback, see troubleshooting' }
if (Test-Path _old) { throw 'STOP: _old left from an interrupted update, see troubleshooting' }
if (-not (Test-Path lite-prev/VERSION)) { throw 'STOP: no previous version' }
if (-not (Test-Path lite/VERSION)) { throw 'STOP: no current lite, see troubleshooting' }
Move-Item lite _swap
Move-Item lite-prev lite
Move-Item _swap lite-prev
"Now lite $(Get-Content lite/VERSION), lite-prev $(Get-Content lite-prev/VERSION)"
```

### Проверка обновления (раз в день, ничего не меняет)

```powershell
$Root = Join-Path $HOME 'Second-Brain-Lite'
$Url = 'https://github.com/tonydzi/brain-lite/releases/latest/download/VERSION'
$Cur = (Get-Content (Join-Path $Root 'lite/VERSION') -ErrorAction SilentlyContinue | Select-Object -First 1); if (-not $Cur) { $Cur = 'none' }
$Prev = (Get-Content (Join-Path $Root 'lite-prev/VERSION') -ErrorAction SilentlyContinue | Select-Object -First 1)
$Curl = if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'curl.exe' } else { 'curl' }
$ErrorActionPreference = 'Continue'
$New = (& $Curl -fsSL --proto '=https' --proto-redir '=https' --max-time 20 $Url 2>$null | Select-Object -First 1)
if (Test-Path (Join-Path $Root 'My-Work')) { Set-Content -Path (Join-Path $Root 'My-Work/.lite-last-check') -Value (Get-Date -Format 'yyyy-MM-dd') }
if ("$New" -notmatch '^\d+\.\d+\.\d+$') { "Could not check for updates (no network?). Installed: $Cur" }
elseif ($New -eq $Cur) { "No updates, installed $Cur" }
elseif ($New -eq $Prev) { "Latest is $New, you rolled back from it to $Cur" }
else { "Update available: $Cur -> $New. Say: update lite" }
```

## Проверка после установки или обновления

1. `lite/VERSION` показывает ожидаемую версию.
2. Помощник, открытый в `My-Work`, читает `../lite/AGENTS-CORE.md` и называет приёмы из
   `../lite/.claude/skills`.
3. Квитанция владельцу: дата, было → стало, сумма сошлась, где лежит откат.

## Если не получилось

| Что видно | Что делать |
|---|---|
| `СТОП: контрольная сумма не совпала` / `STOP: checksum mismatch` | Ничего не заменено. Повторить позже; повторилось: написать Антону, архив не использовать |
| `curl: (22) ... 404` или `download ... failed` | Релиза ещё нет или нет сети. Проверить страницу релизов в браузере |
| `подозрительные пути`, `ссылки на чужие файлы`, `нет lite/...` (`suspicious paths`, `archive has no`) | Архив испорчен или подменён. Не использовать, написать Антону |
| `чужой источник` (`foreign source`) | Строку `BASE` кто-то поменял. Вернуть адрес из этого файла |
| `открыт внутри lite` | Открыть помощника в `My-Work` и повторить |
| Codex просит разрешение на сеть | Нормально: разрешить один раз для этой команды |
| Помощник отказывается скачивать | Попросите прямо: «обнови лайт по UPDATE.md» |
| После обновления стало хуже | «откати лайт» |
| `осталась _old` | Замена прервалась. Если `lite` нет: переименовать `_old` в `lite`. Если `lite` есть: удалить `lite-prev` и переименовать `_old` в `lite-prev`. Перед этим показать владельцу `VERSION` всех папок и дождаться «да» |
| `остался _swap` | Откат прервался. Если `lite` нет: переименовать `_swap` в `lite`. Если `lite-prev` нет: переименовать `_swap` в `lite-prev`. Перед этим показать владельцу `VERSION` всех папок и дождаться «да» |
