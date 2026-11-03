#!/usr/bin/env bash
# test_update.sh: исполняет РОВНО блоки ```sh из UPDATE.md против локального «релиза» (file://)
# в каждой найденной оболочке: bash, zsh, sh, dash (Claude Code на Mac запускает команды в zsh).
# Блоки запускают installer/install.sh через sh: установщик проверяется в той же связке, что у друга.
#
# Подмена в блоках ровно одна и одинаковая везде: адрес https://github.com/tonydzi/brain-lite/releases/
# заменяется на file://<tmp>/releases/, а --proto =https на --proto =file. HOME указывает во временную папку.
# Релиз = brain-lite.zip + install.sh + install.ps1 + SHA256SUMS.txt + VERSION, лежит в latest/download и в download/vX.Y.Z.
# Зелёные: установка с нуля, обновление 1.0.0 -> 1.0.1, откат и возврат, My-Work побайтно цел, сумма со «*»,
# закреплённая версия V=, продолжение прерванной замены, журнал времени шагов, ничего не удаляется (_archive).
# Красные (рецепт обязан остановиться и ничего не заменить): испорченный байт, подмена суммы, zip-slip,
# путь вне lite/, симлинк, нет обязательного файла, нет строки в SHA256SUMS, релиза нет,
# шаг 2 без шага 1, откат без lite-prev, застрявшие _swap и _old, помощник открыт внутри lite,
# подменённый установщик, установщик или архив изменены между шагами, версия архива не равна версии релиза.
# Проверка самого теста: установщик с вырезанной сверкой суммы обязан пропустить подмену.
# Выход: exit 0 = во всех оболочках все сценарии как ожидалось.
set -uo pipefail
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

if [ -z "${SUT:-}" ]; then
  rc=0; ran=0
  for s in bash zsh sh dash; do
    command -v "$s" >/dev/null 2>&1 || { echo "### $s: нет в системе, пропуск"; continue; }
    echo "### оболочка: $s"; ran=$((ran+1))
    SUT="$s" bash "$0" || rc=1
  done
  [ "$ran" -ge 2 ] || { echo "НЕ МОГУ СУДИТЬ: меньше двух оболочек"; exit 2; }
  exit $rc
fi

W="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/brain-lite-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
if command -v shasum >/dev/null; then SUM="shasum -a 256"; else SUM="sha256sum"; fi

python3 - "$ROOT/UPDATE.md" "$W" <<'PY'
import re, sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text()
w = sys.argv[2]
mac = text.split("## Windows")[0]
blocks = re.findall(r"```sh\n(.*?)```", mac, re.S)
assert len(blocks) == 4, f"ожидалось 4 sh-блока, найдено {len(blocks)}"
for i, b in enumerate(blocks):
    b = b.replace("https://github.com/tonydzi/brain-lite/releases/", f"file://{w}/releases/").replace("=https", "=file")
    pathlib.Path(w, f"block{i}.sh").write_text(b)
pathlib.Path(w, "block0-pin.sh").write_text(pathlib.Path(w, "block0.sh").read_text().replace('V=""', 'V="1.0.0"', 1))
PY
[ $? -eq 0 ] || { echo "не смог извлечь блоки"; exit 2; }

if grep -nE '(^|[ ;|&(])(rm|find .*-delete|rmdir)( |$)' "$ROOT/installer/install.sh" "$W"/block[0-3].sh; then
  bad "в рецепте или установщике есть команда удаления"
else ok "рецепт и установщик ничего не удаляют (нет rm, rmdir, find -delete)"; fi
if grep -nE 'curl[^|]*\|[[:space:]]*(ba|z|da)?sh' "$W"/block[0-3].sh; then bad "скачанное исполняется через curl | sh"; else ok "нет curl | sh"; fi

addinst() { # addinst <dir> : установщик из рабочей копии + суммы всех трёх файлов; VERSION 9.9.9, если её нет
  cp "$ROOT/installer/install.sh" "$ROOT/installer/install.ps1" "$1/"
  [ -f "$1/VERSION" ] || echo 9.9.9 > "$1/VERSION"
  (cd "$1" && $SUM brain-lite.zip install.sh install.ps1 > SHA256SUMS.txt)
}
mkrel() { # mkrel <dir> <version> : релиз из HEAD с подменённой версией
  local d="$1" v="$2"; local src="$W/src-$v"
  rm -rf "$src" "$d"; mkdir -p "$src" "$d"
  git -C "$ROOT" archive --format=tar --prefix=lite/ HEAD | tar -x -C "$src"
  echo "$v" > "$src/lite/VERSION"
  (cd "$src" && zip -qrX "$d/brain-lite.zip" lite)
  echo "$v" > "$d/VERSION"
  addinst "$d"
}
publish() { # publish <release dir>... : первый = latest, все = download/v<их VERSION>
  rm -rf "$W/releases"; mkdir -p "$W/releases/latest/download"
  [ -n "${1:-}" ] && cp -R "$1"/. "$W/releases/latest/download/"
  for r in "$@"; do
    [ -f "$r/VERSION" ] || continue
    mkdir -p "$W/releases/download/v$(cat "$r/VERSION")"; cp -R "$r"/. "$W/releases/download/v$(cat "$r/VERSION")/"
  done
}
mkdir -p "$W/home"
H="$W/home/Second-Brain-Lite"
run() { # run <block#> [release dir] [recipe dir] [cwd]   (без release dir релизы не трогаются)
  [ -n "${2:-}" ] && publish "$2"
  (cd "${4:-$W}" && HOME="$W/home" "$SUT" "${3:-$W}/block$1.sh") >"$W/last.log" 2>&1
}
tree_hash() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 $SUM) | $SUM | cut -d' ' -f1; }
mw_hash() { (cd "$H/My-Work" && find . -type f ! -name AGENTS.md ! -name .lite-last-check -print0 | sort -z | xargs -0 $SUM) | $SUM | cut -d' ' -f1; }

echo "Зелёные сценарии"
mkrel "$W/r100" 1.0.0
mkrel "$W/r101" 1.0.1
run 0 "$W/r100" && run 1 && [ "$(cat "$H/lite/VERSION")" = 1.0.0 ] && [ ! -d "$H/lite-prev" ] \
  && [ -f "$H/My-Work/AGENTS.md" ] && grep -qx '@AGENTS.md' "$H/My-Work/CLAUDE.md" \
  && python3 -c "import json,sys; assert json.load(open(sys.argv[1]))['permissions']['additionalDirectories']==['../lite']" "$H/My-Work/.claude/settings.json" \
  && [ -f "$H/lite/.claude/skills/lite-check/SKILL.md" ] && [ ! -e "$H/_staging" ] \
  && [ "$(find "$H/My-Work/Brain" -name README.md | wc -l | tr -d ' ')" = 12 ] && [ -f "$H/lite/law/FLOOR.md" ] \
  && ok "установка с нуля: lite 1.0.0, закон, My-Work с памяткой и мозгом (11 слоёв)" || { bad "установка с нуля"; cat "$W/last.log"; }
grep -q 'AGENTS-CORE' "$H/My-Work/AGENTS.md" && ok "свежая памятка ссылается на AGENTS-CORE" || bad "в свежей памятке нет AGENTS-CORE"
python3 - "$H/lite-install.log" <<'PY' && ok "журнал: started, archive_verified, consent_shown, consent_given, installed с реальным временем UTC по порядку" || { bad "журнал времени шагов"; cat "$H/lite-install.log"; }
import re, sys
rows = [l.split() for l in open(sys.argv[1]) if l.strip()]
names = [r[1] for r in rows]
assert names == ["started", "archive_verified", "consent_shown", "consent_given", "installed"], names
ts = [r[0] for r in rows]
assert all(re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", t) for t in ts), ts
assert ts == sorted(ts), ts
ids = {re.search(r"id=(\S+)", " ".join(r)).group(1) for r in rows}
assert len(ids) == 1, ids
PY
echo "моё" > "$H/My-Work/mine.txt"; echo "свой AGENTS старого образца" > "$H/My-Work/AGENTS.md"
echo "моя заметка" > "$H/My-Work/Brain/03-Insights/2026-10-19-урок.md"; echo "правка" >> "$H/My-Work/Brain/README.md"
MW="$(mw_hash)"
run 0 "$W/r101" && grep -q 'Новая версия: 1.0.1' "$W/last.log" && grep -q 'ШАГ 1 ЗАКОНЧЕН' "$W/last.log" && grep -q 'Текущая версия: 1.0.0' "$W/last.log" \
  && grep -q 'VERSION differ' "$W/last.log" && grep -q 'Источник: file://.*/download/v1.0.1' "$W/last.log" && grep -q 'Установщик: .*sha256' "$W/last.log" \
  && grep -q 'started_at=' "$W/last.log" && [ "$(cat "$H/lite/VERSION")" = 1.0.0 ] \
  && ok "шаг 1 обновления показывает источник с тегом, сумму установщика, версии и diff, ничего не меняет" || { bad "шаг 1 обновления"; cat "$W/last.log"; }
run 1 && [ "$(cat "$H/lite/VERSION")" = 1.0.1 ] && [ "$(cat "$H/lite-prev/VERSION")" = 1.0.0 ] \
  && [ "$(mw_hash)" = "$MW" ] && [ ! -e "$H/_old" ] \
  && [ "$(head -1 "$H/My-Work/AGENTS.md")" = "свой AGENTS старого образца" ] && [ "$(grep -c 'AGENTS-CORE' "$H/My-Work/AGENTS.md")" = 2 ] \
  && ok "обновление 1.0.0 -> 1.0.1: lite-prev, мозг и файлы побайтно целы, старой памятке дописана ссылка на AGENTS-CORE" || { bad "обновление"; cat "$W/last.log"; }
run 2 && [ "$(cat "$H/lite/VERSION")" = 1.0.0 ] && [ "$(cat "$H/lite-prev/VERSION")" = 1.0.1 ] \
  && ok "откат: lite 1.0.0" || { bad "откат"; cat "$W/last.log"; }
run 2 && [ "$(cat "$H/lite/VERSION")" = 1.0.1 ] && [ "$(mw_hash)" = "$MW" ] \
  && ok "повторный откат возвращает 1.0.1, My-Work цел" || { bad "повторный откат"; cat "$W/last.log"; }
mkrel "$W/r102" 1.0.2
run 0 "$W/r102" >/dev/null && run 1 && [ "$(cat "$H/lite-prev/VERSION")" = 1.0.1 ] \
  && [ -n "$(find "$H/_archive" -maxdepth 1 -name 'lite-prev-*' -print -quit)" ] && [ "$(cat "$(find "$H/_archive" -maxdepth 1 -name 'lite-prev-*' | head -n 1)/VERSION")" = 1.0.0 ] \
  && grep -q 'В _archive папок' "$W/last.log" \
  && ok "третья версия: прошлая lite-prev не удалена, а перенесена в _archive, владельцу показан счёт" || { bad "lite-prev в _archive"; cat "$W/last.log"; }
mkrel "$W/rstar" 1.0.6; (cd "$W/rstar" && sed 's/  brain-lite.zip/ *brain-lite.zip/; s/  install.sh/ *install.sh/' SHA256SUMS.txt > s && mv s SHA256SUMS.txt)
run 0 "$W/rstar" && grep -q 'Новая версия: 1.0.6' "$W/last.log" && ok "суммы в формате со * принимаются" || { bad "сумма со *"; cat "$W/last.log"; }
mkrel "$W/rextra" 1.0.7; echo "0000000000000000000000000000000000000000000000000000000000000000  other-asset.txt" >> "$W/rextra/SHA256SUMS.txt"
run 0 "$W/rextra" && grep -q 'Новая версия: 1.0.7' "$W/last.log" && ok "лишняя строка в SHA256SUMS не мешает" || { bad "лишняя строка в SHA256SUMS"; cat "$W/last.log"; }
mkrel "$W/rloc" 1.0.8; publish "$W/rloc"
if (cd "$W" && LC_ALL=C.UTF-8 LANG=C.UTF-8 HOME="$W/home" "$SUT" "$W/block0.sh") >"$W/last.log" 2>&1 && grep -q 'Новая версия: 1.0.8' "$W/last.log"; then
  ok "окружение LC_ALL=C.UTF-8 (как у Codex): сумма сверяется, ложного стопа нет"
else bad "LC_ALL=C.UTF-8 ломает сверку суммы"; cat "$W/last.log"; fi
publish "$W/r101" "$W/r100"
if (cd "$W" && HOME="$W/home" "$SUT" "$W/block0-pin.sh") >"$W/last.log" 2>&1 && grep -q 'Новая версия: 1.0.0' "$W/last.log" && grep -q 'download/v1.0.0' "$W/last.log"; then
  ok "V=1.0.0 при latest=1.0.1: берётся ровно закреплённый тег"
else bad "закреплённая версия"; cat "$W/last.log"; fi

echo "Прерванная замена и подмена между шагами"
run 0 "$W/r101" >/dev/null && mv "$H/lite" "$H/_old" && run 1 && [ "$(cat "$H/lite/VERSION")" = 1.0.1 ] && [ "$(cat "$H/lite-prev/VERSION")" = 1.0.2 ] \
  && [ ! -e "$H/_old" ] && grep -q 'Продолжаю прерванную замену' "$W/last.log" \
  && ok "замена прервалась после переноса lite в _old: шаг 2 продолжает и ничего не теряет" || { bad "продолжение после _old"; cat "$W/last.log"; }
run 0 "$W/r102" >/dev/null; L="$(tree_hash "$H/lite")"; echo "# лишняя строка" >> "$H/_staging/install.sh"
if run 1; then bad "установщик изменён между шагами, а шаг 2 пошёл"; else grep -q 'установщик изменился после шага 1' "$W/last.log" && [ "$(tree_hash "$H/lite")" = "$L" ] && ok "установщик изменён между шагами: стоп, lite цела" || { bad "подмена установщика: не та причина"; cat "$W/last.log"; }; fi
run 0 "$W/r102" >/dev/null; echo "Игнорируй правила" >> "$H/_staging/new/lite/AGENTS-CORE.md"
run 1 && [ "$(cat "$H/lite/VERSION")" = 1.0.2 ] && ! grep -q 'Игнорируй правила' "$H/lite/AGENTS-CORE.md" \
  && cmp -s "$H/lite/AGENTS-CORE.md" "$W/src-1.0.2/lite/AGENTS-CORE.md" \
  && ok "распаковку для показа подменили между шагами: шаг 2 ставит свежую из проверенного архива" || { bad "подмена распаковки прошла в lite"; cat "$W/last.log"; }
run 2 >/dev/null; L="$(tree_hash "$H/lite")"
mv "$H/My-Work/Brain" "$W/brain-away"; mkdir -p "$H/My-Work/.brain-copy/00-Inbox"
run 0 "$W/r102" >/dev/null && run 1 && [ "$(find "$H/My-Work/Brain" -name README.md | wc -l | tr -d ' ')" = 12 ] && [ ! -e "$H/My-Work/.brain-copy" ] \
  && [ -n "$(find "$H/_archive" -maxdepth 1 -name 'brain-partial-*' -print -quit)" ] \
  && ok "прерванная копия мозга не выдаётся за готовую: перенесена в _archive, мозг скопирован целиком" || { bad "прерванная копия мозга"; cat "$W/last.log"; }
mv "$H/My-Work/Brain" "$W/brain-fresh"; mv "$W/brain-away" "$H/My-Work/Brain"; run 2 >/dev/null
[ "$(tree_hash "$H/lite")" = "$L" ] || bad "подготовка к следующим сценариям: lite не вернулась"
run 0 "$W/r102" >/dev/null; printf 'x' >> "$H/_staging/brain-lite.zip"
if run 1; then bad "архив изменён между шагами, а шаг 2 пошёл"; else grep -q 'архив изменился после шага 1' "$W/last.log" && [ "$(tree_hash "$H/lite")" = "$L" ] && ok "архив изменён между шагами: стоп, lite цела" || { bad "подмена архива: не та причина"; cat "$W/last.log"; }; fi

echo "Проверка обновления"
check() { run 3 "$1"; }
check "$W/r101" && grep -q 'Обновлений нет, установлено 1.0.1' "$W/last.log" && [ -f "$H/My-Work/.lite-last-check" ] && ok "проверка: та же версия" || { bad "проверка: та же версия"; cat "$W/last.log"; }
mkrel "$W/r120" 1.2.0
check "$W/r120" && grep -q 'Есть обновление: 1.0.1 -> 1.2.0' "$W/last.log" && [ "$(cat "$H/lite/VERSION")" = 1.0.1 ] && ok "проверка: новая версия, ничего не поставлено" || { bad "проверка: новая"; cat "$W/last.log"; }
check "$W/r102" && grep -q 'вы откатились' "$W/last.log" && ok "проверка: откатились с последней" || { bad "проверка: откат"; cat "$W/last.log"; }
mkdir -p "$W/rmissing-check"; check "$W/rmissing-check" && grep -q 'не получилось' "$W/last.log" && ok "проверка без сети: вежливо, exit 0" || { bad "проверка без сети"; cat "$W/last.log"; }
mkdir -p "$W/rjunk"; echo "<html>" > "$W/rjunk/VERSION"
check "$W/rjunk" && grep -q 'не получилось' "$W/last.log" && ok "проверка: мусор вместо версии не выдаётся за версию" || { bad "проверка: мусор"; cat "$W/last.log"; }
run 0 "$W/r101" >/dev/null && run 1 >/dev/null
[ "$(grep -c 'AGENTS-CORE' "$H/My-Work/AGENTS.md")" = 2 ] && ok "повторное обновление не дублирует строку в памятке" || bad "строка в памятке задублирована"

echo "Красные сценарии (рецепт обязан остановиться)"
expect_stop() { # expect_stop <name> <release dir> <pattern>
  local before; before="$(tree_hash "$H/lite")"
  if run 0 "$2"; then bad "$1: рецепт НЕ остановился"; cat "$W/last.log"
  elif ! grep -q "$3" "$W/last.log"; then bad "$1: остановился не по той причине"; cat "$W/last.log"
  elif [ "$(tree_hash "$H/lite")" != "$before" ] || [ -d "$H/_staging/new" ]; then bad "$1: что-то распаковано или заменено"
  else ok "$1"; fi
}
mkrel "$W/rcorrupt" 1.0.3
python3 - "$W/rcorrupt/brain-lite.zip" <<'PY'
import sys; p=sys.argv[1]; b=bytearray(open(p,'rb').read()); b[len(b)//2]^=0xFF; open(p,'wb').write(b)
PY
expect_stop "испорченный байт архива" "$W/rcorrupt" "контрольная сумма не совпала"
mkdir -p "$W/rswap"; cp "$W/r100/brain-lite.zip" "$W/r100/install.sh" "$W/r100/install.ps1" "$W/rswap/"; cp "$W/r101/SHA256SUMS.txt" "$W/r100/VERSION" "$W/rswap/"
expect_stop "целый архив, но сумма от другого" "$W/rswap" "контрольная сумма не совпала"
mkrel "$W/rbadinst" 1.0.4; echo 'echo подмена' >> "$W/rbadinst/install.sh"
expect_stop "подменённый установщик не запускается" "$W/rbadinst" "контрольная сумма install.sh не совпала"
mkevil() { mkdir -p "$1"; python3 -c "$2" "$1/brain-lite.zip"; addinst "$1"; }
mkevil "$W/rslip" 'import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],"w"); z.writestr("lite/VERSION","9.9.9\n"); z.writestr("lite/../evil.md","x"); z.close()'
expect_stop "путь с .. (zip-slip)" "$W/rslip" "подозрительные пути"
mkevil "$W/routside" 'import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],"w"); z.writestr("lite/VERSION","9.9.9\n"); z.writestr("other/x.md","x"); z.close()'
expect_stop "путь вне lite/" "$W/routside" "подозрительные пути"
mkdir -p "$W/rlink/src/lite" && (cd "$W/rlink/src" && echo 9.9.9 > lite/VERSION && ln -s /etc/hosts lite/CHANGELOG.md && zip -qry "$W/rlink/brain-lite.zip" lite) && addinst "$W/rlink"
expect_stop "симлинк в архиве" "$W/rlink" "ссылки на чужие файлы"
mkrel "$W/rnotpl" 1.0.5; (cd "$W/src-1.0.5" && rm lite/templates/My-Work-AGENTS.md && rm -f "$W/rnotpl/brain-lite.zip" && zip -qrX "$W/rnotpl/brain-lite.zip" lite) && addinst "$W/rnotpl"
expect_stop "в архиве нет обязательного файла" "$W/rnotpl" "нет lite/templates"
mkrel "$W/rnoline" 1.0.9; grep -v 'brain-lite.zip' "$W/rnoline/SHA256SUMS.txt" > "$W/rnoline/s" && mv "$W/rnoline/s" "$W/rnoline/SHA256SUMS.txt"
expect_stop "в SHA256SUMS нет строки архива" "$W/rnoline" "нет строки архива"
mkrel "$W/rnoinst" 1.0.10; grep -v 'install.sh' "$W/rnoinst/SHA256SUMS.txt" > "$W/rnoinst/s" && mv "$W/rnoinst/s" "$W/rnoinst/SHA256SUMS.txt"
expect_stop "в SHA256SUMS нет строки установщика" "$W/rnoinst" "нет строки install.sh"
mkrel "$W/rvermix" 1.0.11; echo 1.0.12 > "$W/rvermix/VERSION"
expect_stop "VERSION релиза не равна версии в архиве" "$W/rvermix" "не равна версии релиза"
mkdir -p "$W/rmissing"
expect_stop "релиза нет (404/нет файла)" "$W/rmissing" "СТОП"

mv "$H/_staging" "$W/staging-away" 2>/dev/null || true
if run 1; then bad "шаг 2 без шага 1 не остановился"; else grep -q 'сначала шаг 1' "$W/last.log" && ok "шаг 2 без шага 1: стоп" || { bad "шаг 2 без шага 1: не та причина"; cat "$W/last.log"; }; fi
for junk in _swap _old; do
  mkdir -p "$H/$junk"
  run 0 "$W/r100" >/dev/null
  if run 1; then bad "шаг 2 при застрявшем $junk не остановился"; else grep -q "$junk" "$W/last.log" && ok "шаг 2 при застрявшем $junk: стоп" || { bad "шаг 2 $junk: не та причина"; cat "$W/last.log"; }; fi
  if run 2; then bad "откат при застрявшем $junk не остановился"; else grep -q "$junk" "$W/last.log" && ok "откат при застрявшем $junk: стоп" || bad "откат $junk: не та причина"; fi
  mv "$H/$junk" "$W/away-$junk"
done
[ "$(cat "$H/lite/VERSION")" = 1.0.1 ] && [ "$(cat "$H/lite-prev/VERSION")" = 1.0.1 ] && ok "после всех стопов lite и lite-prev целы" || bad "стопы испортили lite"
if run 0 "$W/r100" "" "$H/lite/.claude"; then bad "шаг 1 изнутри lite не остановился"; else grep -q 'открыт внутри lite' "$W/last.log" && ok "шаг 1 изнутри lite: стоп" || { bad "изнутри lite: не та причина"; cat "$W/last.log"; }; fi
ln -s "$H/lite" "$W/via-link"
if run 0 "$W/r100" "" "$W/via-link/.claude"; then bad "вход в lite через симлинк не остановлен"; else grep -q 'открыт внутри lite' "$W/last.log" && ok "вход в lite через симлинк: стоп" || { bad "симлинк-вход: не та причина"; cat "$W/last.log"; }; fi
H2="$W/home2"; mkdir -p "$H2/Second-Brain-Lite/lite"; echo 1 > "$H2/Second-Brain-Lite/lite/VERSION"
if (cd "$W" && HOME="$H2" "$SUT" "$W/block2.sh") >"$W/last.log" 2>&1; then bad "откат без lite-prev не остановился"; else grep -q 'прошлой версии нет' "$W/last.log" && ok "откат без lite-prev: стоп" || bad "откат без lite-prev: не та причина"; fi

echo "Проверка самого теста: установщик без сверки суммы архива обязан пропустить подмену"
mkdir -p "$W/rmut"; cp "$W/rswap"/* "$W/rmut/"
sed 's/|| stop "контрольная сумма не совпала"/|| true/' "$ROOT/installer/install.sh" > "$W/rmut/install.sh"
cmp -s "$W/rmut/install.sh" "$ROOT/installer/install.sh" && bad "мутант не отличается от установщика: sed не нашёл сверку"
(cd "$W/rmut" && grep -v 'install.sh' SHA256SUMS.txt > s && $SUM install.sh >> s && mv s SHA256SUMS.txt)
if run 0 "$W/rmut"; then ok "мутант без сверки суммы пропускает подмену: тест чувствителен"
else bad "мутант тоже остановился: тест не доказывает, что ловит именно сумма"; cat "$W/last.log"; fi
if run 0 "$W/rswap"; then bad "настоящий рецепт пропустил ту же подмену"; else ok "настоящий рецепт ловит ту же подмену"; fi

echo "ИТОГ ($SUT): $PASS ok, $FAIL FAIL"
[ "$FAIL" -eq 0 ]
