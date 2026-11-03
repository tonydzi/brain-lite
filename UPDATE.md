# Установка, обновление и откат

Этот рецепт выполняет **помощник владельца** по его прямой просьбе: «установи лайт»,
«обнови лайт» или «откати лайт» (пункт 11 в [RULES.md](RULES.md)). Человеку ничего
печатать в Терминале не нужно. Помощник выполняет блоки как есть, по порядку,
и останавливается на любой ошибке.

Что получится на компьютере:

```
Second-Brain-Lite/      в домашней папке владельца
  lite/              текущая версия, только для чтения
  lite-prev/         прошлая версия, для отката
  My-Work/           личные файлы владельца; рецепт их не читает и никуда не отправляет
  _archive/          то, что рецепт убрал с дороги; он ничего не удаляет, лишнее владелец удаляет сам
  lite-install.log   время каждого шага установки (для квитанции, без содержания заметок)
```

Источник один: релизы `https://github.com/tonydzi/brain-lite/releases`. В каждом релизе:
`brain-lite.zip` (библиотека), `install.sh` и `install.ps1` (установщик), `SHA256SUMS.txt`
(контрольные суммы архива и установщика), `UPDATE.md` (этот рецепт) и `VERSION` (номер версии).
Новые релизы выходят сами, когда мы улучшаем закон, скиллы или шаблоны; ставит их у себя только
владелец, после своего «да».

**Как устроено.** Блок «Шаг 1» один раз узнаёт номер последней версии и дальше берёт все файлы
только из релиза с этим номером, поэтому архив и установщик не могут прийти из разных версий.
Он сверяет сумму установщика и запускает его фазу `prepare`: проверка архива, распаковка в
`_staging`, показ изменений. Скачанное сам себя не запускает: нет `curl | sh`. Блок «Шаг 2»
после отдельного «да» снова сверяет сумму того же установщика и запускает фазу `apply`.
Установщик в сеть не ходит и ничего не удаляет: прошлое переносится в `_archive`.

**Жёсткие правила для помощника:**

- Любой `СТОП`: ничего не заменять, показать владельцу вывод. Проверки не отключать,
  не обходить, не скачивать «откуда-то ещё», источник в блоках не менять.
- Перед заменой показать владельцу вывод шага 1 (версии, изменённые файлы, начало
  `CHANGELOG.md`) и дождаться его «да».
  Просьба «обнови лайт» или «установи лайт» это «да» не заменяет: шаг 1 и шаг 2 всегда
  в разных ответах, между ними отдельное «да» владельца. Сама просьба разрешает только шаг 1:
  скачать, проверить и показать.
- `My-Work` не читать, не менять и не удалять. Создать её можно, только если её нет. Шаг 2 добавляет
  туда только недостающие служебные файлы: памятку и настройку, которая разрешает Claude Code читать `../lite`.
- Никаких других программ, служб, расписаний и синхронизации этот рецепт не ставит.
- Помощника не держать открытым внутри `lite` или `lite-prev`: на Windows такую папку
  нельзя переименовать. Работать из `My-Work` или из `Second-Brain-Lite`.

Что честно даёт проверка суммы: архив и установщик скачаны целыми и совпадают с тем, что выложено
в релизе. Она не защищает, если кто-то получит доступ к самому репозиторию и подменит все файлы;
поэтому сумма архива каждой версии ещё и записана в описании релиза, а CI пересобирает архив
и установщик из тега и сверяет. Установщик не добавляет доверия по сравнению с блоками прошлых
версий: это тот же репозиторий, просто один файл вместо длинных блоков.

Этот же файл лежит в каждом релизе (`.../releases/download/vX.Y.Z/UPDATE.md`),
поэтому рецепт, архив и установщик всегда одной версии.

Нужна не последняя, а конкретная версия: в строке `V=""` (или `$V = ''`) впишите номер,
например `V="1.2.0"`. Установщик есть в релизах начиная с той версии, где появился этот текст;
для более старых версий берите `UPDATE.md` из их релиза.
Папка установки не `~/Second-Brain-Lite`: поменяйте строку `ROOT=` (или `$Root =`)
во всех блоках одинаково.

## Mac и Linux

Блоки работают в bash, zsh и sh.

### Шаг 1. Скачать, проверить, показать

```sh
set -eu
ROOT="$HOME/Second-Brain-Lite"
V=""
STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "started_at=$STARTED"
HERE=$(pwd -P)
ROOTP=$( (cd "$ROOT" 2>/dev/null && pwd -P) || echo "$ROOT" )
case "$HERE/" in "$ROOTP/lite/"*|"$ROOTP/lite-prev/"*) echo "СТОП: помощник открыт внутри lite, откройте его в My-Work"; exit 1 ;; esac
REL="https://github.com/tonydzi/brain-lite/releases/"
if [ -z "$V" ]; then V=$(curl -fsSL --proto '=https' --proto-redir '=https' "${REL}latest/download/VERSION" | head -n 1) || { echo "СТОП: не могу узнать последнюю версию (нет сети или релиза)"; exit 1; }; fi
case "$V" in [0-9]*.[0-9]*.[0-9]*) ;; *) echo "СТОП: не похоже на номер версии: $V"; exit 1 ;; esac
BASE="${REL}download/v$V"
case "$BASE" in https://github.com/tonydzi/brain-lite/releases/download/v*) ;; *) echo "СТОП: чужой источник $BASE"; exit 1 ;; esac
echo "Папка установки: $ROOT"
echo "Источник: $BASE"
mkdir -p "$ROOT"
cd "$ROOT"
if [ -e _staging ]; then mkdir -p _archive; A="_archive/staging-$(date -u +%Y%m%dT%H%M%SZ)-$$"; while [ -e "$A" ]; do A="$A-x"; done; mv _staging "$A"; fi
mkdir _staging
for f in SHA256SUMS.txt VERSION install.sh brain-lite.zip; do
  curl -fsSL --proto '=https' --proto-redir '=https' -o "_staging/$f" "$BASE/$f" || { echo "СТОП: не скачался $f"; exit 1; }
done
WANT=$(grep -E '[ *]install[.]sh$' _staging/SHA256SUMS.txt | head -n 1 | cut -d' ' -f1)
[ -n "$WANT" ] || { echo "СТОП: в SHA256SUMS.txt нет строки install.sh"; exit 1; }
if command -v shasum >/dev/null 2>&1; then GOT=$(LC_ALL=C shasum -a 256 _staging/install.sh | cut -d' ' -f1); else GOT=$(sha256sum _staging/install.sh | cut -d' ' -f1); fi
[ "$GOT" = "$WANT" ] || { echo "СТОП: контрольная сумма install.sh не совпала"; exit 1; }
echo "Установщик: $ROOT/_staging/install.sh sha256 $GOT"
sh _staging/install.sh prepare "$STARTED"
```

Помощник показывает этот вывод владельцу и ждёт «да». Нет «да»: ничего не делать, `_staging`
уйдёт в `_archive` при следующем шаге 1.

### Шаг 2. Заменить версию (после «да»)

```sh
set -eu
ROOT="$HOME/Second-Brain-Lite"
HERE=$(pwd -P)
ROOTP=$( (cd "$ROOT" 2>/dev/null && pwd -P) || echo "$ROOT" )
case "$HERE/" in "$ROOTP/lite/"*|"$ROOTP/lite-prev/"*) echo "СТОП: помощник открыт внутри lite, откройте его в My-Work"; exit 1 ;; esac
cd "$ROOT"
[ -f _staging/install.sh ] && [ -f _staging/SHA256SUMS.txt ] || { echo "СТОП: сначала шаг 1"; exit 1; }
WANT=$(grep -E '[ *]install[.]sh$' _staging/SHA256SUMS.txt | head -n 1 | cut -d' ' -f1)
if command -v shasum >/dev/null 2>&1; then GOT=$(LC_ALL=C shasum -a 256 _staging/install.sh | cut -d' ' -f1); else GOT=$(sha256sum _staging/install.sh | cut -d' ' -f1); fi
[ -n "$WANT" ] && [ "$GOT" = "$WANT" ] || { echo "СТОП: установщик изменился после шага 1, повторите шаг 1"; exit 1; }
sh _staging/install.sh apply
```

Старая версия не удаляется: прошлая `lite-prev` переезжает в `_archive`, текущая становится `lite-prev`.

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
Блоки и установщик написаны только латиницей, поэтому кодировка файла их не ломает. Вставлять блок
в PowerShell целиком. Установщик блок запускает той же PowerShell, что и сам блок:
`-ExecutionPolicy Bypass` действует только на этот один запуск уже проверенного файла, политика
системы не меняется. Если политика компьютера (например, рабочего) запрещает и это, правильный
результат `STOP`: не снимать блокировку файла, не менять политику, не отключать защиту.
Сообщения по-английски: `STOP: ...` значит то же, что `СТОП`.

### Шаг 1. Скачать, проверить, показать

```powershell
$ErrorActionPreference = 'Stop'
$Root = Join-Path $HOME 'Second-Brain-Lite'
$V = ''
$Started = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
"started_at=$Started"
$here = (Get-Location).ProviderPath.TrimEnd('\', '/')
foreach ($d in 'lite', 'lite-prev') { $p = (Join-Path $Root $d); if ($here -eq $p -or $here.StartsWith($p + [IO.Path]::DirectorySeparatorChar)) { throw 'STOP: the assistant is open inside lite, open it in My-Work' } }
$Rel = 'https://github.com/tonydzi/brain-lite/releases/'
$Curl = if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'curl.exe' } else { 'curl' }
$ErrorActionPreference = 'Continue'  # PowerShell 5.1 turns curl's stderr into an exception before the check below
if (-not $V) { $V = "$(& $Curl -fsSL --proto '=https' --proto-redir '=https' "${Rel}latest/download/VERSION" | Select-Object -First 1)".Trim() }
$ErrorActionPreference = 'Stop'
if ($V -notmatch '^\d+\.\d+\.\d+$') { throw "STOP: cannot get the latest version (no network or release): $V" }
$Base = "${Rel}download/v$V"
if ($Base -notlike 'https://github.com/tonydzi/brain-lite/releases/download/v*') { throw "STOP: foreign source $Base" }
"Install folder: $Root"
"Source: $Base"
New-Item -ItemType Directory -Force $Root | Out-Null
Set-Location $Root
if (Test-Path _staging) { New-Item -ItemType Directory -Force _archive | Out-Null; $a = '_archive/staging-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + "-$PID"; while (Test-Path $a) { $a += '-x' }; Move-Item _staging $a }
New-Item -ItemType Directory _staging | Out-Null
foreach ($f in 'SHA256SUMS.txt', 'VERSION', 'install.ps1', 'brain-lite.zip') {
  $ErrorActionPreference = 'Continue'
  & $Curl -fsSL --proto '=https' --proto-redir '=https' -o "_staging/$f" "$Base/$f"; $rc = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($rc) { throw "STOP: download of $f failed" }
}
$line = Get-Content _staging/SHA256SUMS.txt | Where-Object { $_ -match '[ *]install\.ps1$' } | Select-Object -First 1
if (-not $line) { throw 'STOP: no install.ps1 line in SHA256SUMS.txt' }
$want = ($line -split '\s+')[0].ToLower()
$got = (Get-FileHash _staging/install.ps1 -Algorithm SHA256).Hash.ToLower()
if ($want -ne $got) { throw 'STOP: install.ps1 checksum mismatch' }
"Installer: $Root\_staging\install.ps1 sha256 $got"
$PS = (Get-Process -Id $PID).Path
& $PS -NoProfile -ExecutionPolicy Bypass -File _staging/install.ps1 prepare $Started
if ($LASTEXITCODE) { throw "STOP: installer prepare exited $LASTEXITCODE" }
```

### Шаг 2. Заменить версию (после «да»)

```powershell
$ErrorActionPreference = 'Stop'
$Root = Join-Path $HOME 'Second-Brain-Lite'
$here = (Get-Location).ProviderPath.TrimEnd('\', '/')
foreach ($d in 'lite', 'lite-prev') { $p = (Join-Path $Root $d); if ($here -eq $p -or $here.StartsWith($p + [IO.Path]::DirectorySeparatorChar)) { throw 'STOP: the assistant is open inside lite, open it in My-Work' } }
Set-Location $Root
if (-not (Test-Path _staging/install.ps1) -or -not (Test-Path _staging/SHA256SUMS.txt)) { throw 'STOP: run step 1 first' }
$line = Get-Content _staging/SHA256SUMS.txt | Where-Object { $_ -match '[ *]install\.ps1$' } | Select-Object -First 1
$want = if ($line) { ($line -split '\s+')[0].ToLower() } else { '' }
$got = (Get-FileHash _staging/install.ps1 -Algorithm SHA256).Hash.ToLower()
if (-not $want -or $want -ne $got) { throw 'STOP: the installer changed after step 1, run step 1 again' }
$PS = (Get-Process -Id $PID).Path
& $PS -NoProfile -ExecutionPolicy Bypass -File _staging/install.ps1 apply
if ($LASTEXITCODE) { throw "STOP: installer apply exited $LASTEXITCODE" }
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
3. Квитанция владельцу по навыку `lite-check`: поля `release`, `archive_verified`, `start`
   и время шагов берутся из `lite-install.log`, а не по памяти.

## Если не получилось

| Что видно | Что делать |
|---|---|
| `СТОП: контрольная сумма не совпала` / `STOP: checksum mismatch` | Ничего не заменено. Повторить позже; повторилось: написать Антону, архив не использовать |
| `контрольная сумма install.sh не совпала` / `install.ps1 checksum mismatch` | То же: установщик не запускать, написать Антону |
| `не могу узнать последнюю версию`, `не скачался`, `download ... failed` | Релиза ещё нет или нет сети. Проверить страницу релизов в браузере |
| `подозрительные пути`, `ссылки на чужие файлы`, `нет lite/...` (`suspicious paths`, `archive has no`) | Архив испорчен или подменён. Не использовать, написать Антону |
| `установщик изменился после шага 1` / `archive changed after step 1` | Между шагами кто-то трогал `_staging`. Повторить шаг 1 и снова спросить «да» |
| `чужой источник` (`foreign source`) | Строку `REL` кто-то поменял. Вернуть адрес из этого файла |
| `открыт внутри lite` | Открыть помощника в `My-Work` и повторить |
| Codex просит разрешение на сеть | Нормально: разрешить один раз для команды шага 1. Шаг 2 сеть не нужна |
| Windows: запуск скриптов запрещён политикой | `STOP`. Политику и защиту не трогать; спросить того, кто управляет компьютером |
| Помощник отказывается скачивать | Попросите прямо: «обнови лайт по UPDATE.md» |
| После обновления стало хуже | «откати лайт» |
| `осталась _old` | Замена прервалась, а состояние неоднозначное (однозначное шаг 2 продолжает сам). Показать владельцу `VERSION` папок `lite`, `_old`, `lite-prev` и дождаться «да». Если `lite` нет: переименовать `_old` в `lite`. Если `lite` есть: перенести `lite-prev` в `_archive` и переименовать `_old` в `lite-prev` |
| `остался _swap` | Откат прервался. Если `lite` нет: переименовать `_swap` в `lite`. Если `lite-prev` нет: переименовать `_swap` в `lite-prev`. Перед этим показать владельцу `VERSION` всех папок и дождаться «да» |
| `_archive` растёт | Это прошлые версии и черновики шагов. Рецепт их не удаляет; владелец может удалить папки сам |
