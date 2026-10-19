#!/usr/bin/env bash
# test_update.sh: исполняет РОВНО блоки ```sh из UPDATE.md против локального «релиза» (file://)
# в каждой найденной оболочке: bash, zsh, sh, dash (Claude Code на Mac запускает команды в zsh).
#
# Подмена в блоках ровно одна и одинаковая везде: адрес https://github.com/tonydzi/brain-lite/releases/
# заменяется на file://<tmp>/releases/, а --proto =https на --proto =file. HOME указывает во временную папку.
# Зелёные: установка с нуля, обновление 1.0.0 -> 1.0.1, откат и возврат, My-Work побайтно цел, сумма со «*».
# Красные (рецепт обязан остановиться и ничего не заменить): испорченный байт, подмена суммы, zip-slip,
# путь вне lite/, симлинк, нет обязательного файла, нет строки в SHA256SUMS, релиза нет,
# шаг 2 без шага 1, откат без lite-prev, застрявшие _swap и _old, помощник открыт внутри lite.
# Проверка самого теста: рецепт с вырезанной сверкой суммы обязан пропустить подмену.
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
assert len(blocks) == 3, f"ожидалось 3 sh-блока, найдено {len(blocks)}"
for i, b in enumerate(blocks):
    b = b.replace("https://github.com/tonydzi/brain-lite/releases/", f"file://{w}/releases/").replace("=https", "=file")
    pathlib.Path(w, f"block{i}.sh").write_text(b)
PY
[ $? -eq 0 ] || { echo "не смог извлечь блоки"; exit 2; }

mkrel() { # mkrel <dir> <version> : релиз из HEAD с подменённой версией
  local d="$1" v="$2"; local src="$W/src-$v"
  rm -rf "$src" "$d"; mkdir -p "$src" "$d"
  git -C "$ROOT" archive --format=tar --prefix=lite/ HEAD | tar -x -C "$src"
  echo "$v" > "$src/lite/VERSION"
  (cd "$src" && zip -qrX "$d/brain-lite.zip" lite)
  (cd "$d" && $SUM brain-lite.zip > SHA256SUMS.txt)
}
mkdir -p "$W/home"
H="$W/home/Second-Brain-Lite"
run() { # run <block#> [release dir] [recipe dir] [cwd]
  rm -rf "$W/releases/latest/download"; mkdir -p "$W/releases/latest/download"
  [ -n "${2:-}" ] && cp -R "$2"/. "$W/releases/latest/download/"
  (cd "${4:-$W}" && HOME="$W/home" "$SUT" "${3:-$W}/block$1.sh") >"$W/last.log" 2>&1
}
tree_hash() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 $SUM) | $SUM | cut -d' ' -f1; }

echo "Зелёные сценарии"
mkrel "$W/r100" 1.0.0
mkrel "$W/r101" 1.0.1
run 0 "$W/r100" && run 1 && [ "$(cat "$H/lite/VERSION")" = 1.0.0 ] && [ ! -d "$H/lite-prev" ] \
  && [ -f "$H/My-Work/AGENTS.md" ] && grep -qx '@AGENTS.md' "$H/My-Work/CLAUDE.md" \
  && [ -f "$H/lite/.claude/skills/lite-check/SKILL.md" ] && [ ! -e "$H/_dl" ] \
  && ok "установка с нуля: lite 1.0.0, My-Work с памяткой" || { bad "установка с нуля"; cat "$W/last.log"; }
echo "моё" > "$H/My-Work/mine.txt"; echo "свой AGENTS" > "$H/My-Work/AGENTS.md"
MW="$(tree_hash "$H/My-Work")"
run 0 "$W/r101" && grep -q 'Новая версия: 1.0.1' "$W/last.log" && grep -q 'Текущая версия: 1.0.0' "$W/last.log" \
  && grep -q 'VERSION differ' "$W/last.log" && grep -q 'Источник: file://' "$W/last.log" && [ "$(cat "$H/lite/VERSION")" = 1.0.0 ] \
  && ok "шаг 1 обновления показывает источник, версии и diff, ничего не меняет" || { bad "шаг 1 обновления"; cat "$W/last.log"; }
run 1 && [ "$(cat "$H/lite/VERSION")" = 1.0.1 ] && [ "$(cat "$H/lite-prev/VERSION")" = 1.0.0 ] \
  && [ "$(tree_hash "$H/My-Work")" = "$MW" ] && [ ! -e "$H/_old" ] \
  && ok "обновление 1.0.0 -> 1.0.1, откат в lite-prev, My-Work побайтно цел" || { bad "обновление"; cat "$W/last.log"; }
run 2 && [ "$(cat "$H/lite/VERSION")" = 1.0.0 ] && [ "$(cat "$H/lite-prev/VERSION")" = 1.0.1 ] \
  && ok "откат: lite 1.0.0" || { bad "откат"; cat "$W/last.log"; }
run 2 && [ "$(cat "$H/lite/VERSION")" = 1.0.1 ] && [ "$(tree_hash "$H/My-Work")" = "$MW" ] \
  && ok "повторный откат возвращает 1.0.1, My-Work цел" || { bad "повторный откат"; cat "$W/last.log"; }
mkrel "$W/rstar" 1.0.6; (cd "$W/rstar" && sed 's/  brain-lite.zip/ *brain-lite.zip/' SHA256SUMS.txt > s && mv s SHA256SUMS.txt)
run 0 "$W/rstar" && grep -q 'Новая версия: 1.0.6' "$W/last.log" && ok "сумма в формате со * принимается" || { bad "сумма со *"; cat "$W/last.log"; }
mkrel "$W/rextra" 1.0.7; echo "0000000000000000000000000000000000000000000000000000000000000000  other-asset.txt" >> "$W/rextra/SHA256SUMS.txt"
run 0 "$W/rextra" && grep -q 'Новая версия: 1.0.7' "$W/last.log" && ok "лишняя строка в SHA256SUMS не мешает" || { bad "лишняя строка в SHA256SUMS"; cat "$W/last.log"; }
rm -rf "$H/_dl"

echo "Красные сценарии (рецепт обязан остановиться)"
expect_stop() { # expect_stop <name> <release dir> <pattern>
  local before; before="$(tree_hash "$H/lite")"
  if run 0 "$2"; then bad "$1: рецепт НЕ остановился"; cat "$W/last.log"
  elif ! grep -q "$3" "$W/last.log"; then bad "$1: остановился не по той причине"; cat "$W/last.log"
  elif [ "$(tree_hash "$H/lite")" != "$before" ] || [ -d "$H/_dl/new" ]; then bad "$1: что-то распаковано или заменено"
  else ok "$1"; fi
}
mkrel "$W/rcorrupt" 1.0.2
python3 - "$W/rcorrupt/brain-lite.zip" <<'PY'
import sys; p=sys.argv[1]; b=bytearray(open(p,'rb').read()); b[len(b)//2]^=0xFF; open(p,'wb').write(b)
PY
expect_stop "испорченный байт архива" "$W/rcorrupt" "контрольная сумма не совпала"
mkdir -p "$W/rswap"; cp "$W/r100/brain-lite.zip" "$W/rswap/"; cp "$W/r101/SHA256SUMS.txt" "$W/rswap/"
expect_stop "целый архив, но сумма от другого" "$W/rswap" "контрольная сумма не совпала"
mkevil() { mkdir -p "$1"; python3 -c "$2" "$1/brain-lite.zip"; (cd "$1" && $SUM brain-lite.zip > SHA256SUMS.txt); }
mkevil "$W/rslip" 'import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],"w"); z.writestr("lite/VERSION","9.9.9\n"); z.writestr("lite/../evil.md","x"); z.close()'
expect_stop "путь с .. (zip-slip)" "$W/rslip" "подозрительные пути"
mkevil "$W/routside" 'import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],"w"); z.writestr("lite/VERSION","9.9.9\n"); z.writestr("other/x.md","x"); z.close()'
expect_stop "путь вне lite/" "$W/routside" "подозрительные пути"
mkdir -p "$W/rlink/src/lite" && (cd "$W/rlink/src" && echo 9.9.9 > lite/VERSION && ln -s /etc/hosts lite/CHANGELOG.md && zip -qry "$W/rlink/brain-lite.zip" lite) && (cd "$W/rlink" && $SUM brain-lite.zip > SHA256SUMS.txt)
expect_stop "симлинк в архиве" "$W/rlink" "ссылки на чужие файлы"
mkrel "$W/rnotpl" 1.0.5; (cd "$W/src-1.0.5" && rm lite/templates/My-Work-AGENTS.md && rm -f "$W/rnotpl/brain-lite.zip" && zip -qrX "$W/rnotpl/brain-lite.zip" lite) && (cd "$W/rnotpl" && $SUM brain-lite.zip > SHA256SUMS.txt)
expect_stop "в архиве нет обязательного файла" "$W/rnotpl" "нет lite/templates"
mkrel "$W/rnoline" 1.0.3; echo "deadbeef  something-else.zip" > "$W/rnoline/SHA256SUMS.txt"
expect_stop "в SHA256SUMS нет строки архива" "$W/rnoline" "нет строки архива"
mkdir -p "$W/rmissing"
expect_stop "релиза нет (404/нет файла)" "$W/rmissing" "."

if run 1; then bad "шаг 2 без шага 1 не остановился"; else grep -q 'сначала шаг 1' "$W/last.log" && ok "шаг 2 без шага 1: стоп" || { bad "шаг 2 без шага 1: не та причина"; cat "$W/last.log"; }; fi
for junk in _swap _old; do
  mkdir -p "$H/$junk"
  run 0 "$W/r100" >/dev/null
  if run 1; then bad "шаг 2 при застрявшем $junk не остановился"; else grep -q "$junk" "$W/last.log" && ok "шаг 2 при застрявшем $junk: стоп" || bad "шаг 2 $junk: не та причина"; fi
  if run 2; then bad "откат при застрявшем $junk не остановился"; else grep -q "$junk" "$W/last.log" && ok "откат при застрявшем $junk: стоп" || bad "откат $junk: не та причина"; fi
  rmdir "$H/$junk"; rm -rf "$H/_dl"
done
[ "$(cat "$H/lite/VERSION")" = 1.0.1 ] && [ "$(cat "$H/lite-prev/VERSION")" = 1.0.0 ] && ok "после всех стопов lite 1.0.1 и lite-prev 1.0.0 целы" || bad "стопы испортили lite"
if run 0 "$W/r100" "" "$H/lite/.claude"; then bad "шаг 1 изнутри lite не остановился"; else grep -q 'открыт внутри lite' "$W/last.log" && ok "шаг 1 изнутри lite: стоп" || { bad "изнутри lite: не та причина"; cat "$W/last.log"; }; fi
ln -s "$H/lite" "$W/via-link"
if run 0 "$W/r100" "" "$W/via-link/.claude"; then bad "вход в lite через симлинк не остановлен"; else grep -q 'открыт внутри lite' "$W/last.log" && ok "вход в lite через симлинк: стоп" || { bad "симлинк-вход: не та причина"; cat "$W/last.log"; }; fi
H2="$W/home2"; mkdir -p "$H2/Second-Brain-Lite/lite"; echo 1 > "$H2/Second-Brain-Lite/lite/VERSION"
if (cd "$W" && HOME="$H2" "$SUT" "$W/block2.sh") >"$W/last.log" 2>&1; then bad "откат без lite-prev не остановился"; else grep -q 'прошлой версии нет' "$W/last.log" && ok "откат без lite-prev: стоп" || bad "откат без lite-prev: не та причина"; fi

echo "Проверка самого теста: рецепт без сверки суммы обязан пропустить подмену"
mkdir -p "$W/mut"; cp "$W"/block*.sh "$W/mut/"
sed -E 's/^  (shasum|sha256sum) .*$/  true/' "$W/block0.sh" > "$W/mut/block0.sh"
if run 0 "$W/rswap" "$W/mut"; then ok "мутант без сверки суммы пропускает подмену: тест чувствителен"
else bad "мутант тоже остановился: тест не доказывает, что ловит именно сумма"; cat "$W/last.log"; fi
if run 0 "$W/rswap"; then bad "настоящий рецепт пропустил ту же подмену"; else ok "настоящий рецепт ловит ту же подмену"; fi

echo "ИТОГ ($SUT): $PASS ok, $FAIL FAIL"
[ "$FAIL" -eq 0 ]
