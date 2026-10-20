#!/usr/bin/env bash
# test_release.sh: архив релиза обязан быть побайтно одинаковым при любом часовом поясе сборщика,
# иначе CI-сверка «опубликованный архив == git archive тега» будет краснеть на честных релизах.
# Проверка самого теста: та же сборка без TZ=UTC при разных поясах обязана дать разные суммы.
# Плюс make_release.sh --dry-run во временном клоне: проходит и кладёт ровно 13 файлов.
set -uo pipefail
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
W="$(mktemp -d "${TMPDIR:-/tmp}/brain-lite-rel.XXXXXX")"
trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
if command -v shasum >/dev/null; then SUM="shasum -a 256"; else SUM="sha256sum"; fi
CMD=$(grep -o 'TZ=UTC git archive --format=zip -0 --prefix=lite/' "$ROOT/tools/make_release.sh" | head -1)
[ -n "$CMD" ] || { echo "НЕ МОГУ СУДИТЬ: в make_release.sh нет команды сборки с TZ=UTC"; exit 2; }
grep -q 'TZ=UTC git archive --format=zip -0 --prefix=lite/' "$ROOT/.github/workflows/lite-guard.yml" \
  && ok "CI пересобирает той же командой" || bad "CI собирает иначе, чем make_release.sh"
build() { (cd "$ROOT" && env TZ="$1" sh -c "${2}git archive --format=zip -0 --prefix=lite/ HEAD") | $SUM | cut -d' ' -f1; }
a=$(build America/Los_Angeles "TZ=UTC "); b=$(build Asia/Tokyo "TZ=UTC "); c=$(build Europe/Lisbon "TZ=UTC ")
[ "$a" = "$b" ] && [ "$b" = "$c" ] && ok "TZ=UTC: одна сумма в трёх поясах ($a)" || bad "TZ=UTC: суммы разные $a $b $c"
x=$(build America/Los_Angeles ""); y=$(build Asia/Tokyo "")
[ "$x" != "$y" ] && ok "без TZ=UTC суммы разные: тест чувствителен" || bad "без TZ=UTC суммы совпали: тест ничего не доказывает"
git clone -q "$ROOT" "$W/c"
if (cd "$W/c" && bash tools/make_release.sh "v$(cat VERSION)" --dry-run) >"$W/log" 2>&1; then
  n=$(unzip -Z1 "$W/c/dist/brain-lite.zip" | grep -vc '/$')
  want=$(git -C "$W/c" archive HEAD | tar -t | grep -vc '/$')
  [ "$n" = "$want" ] && ok "make_release --dry-run: $n файлов, как в git archive, сумма сходится" || bad "в архиве $n файлов, ждали $want"
  cmp -s "$W/c/dist/VERSION" "$W/c/VERSION" && ok "VERSION идёт отдельным файлом релиза" || bad "dist/VERSION нет или другой"
  cmp -s "$W/c/dist/UPDATE.md" "$W/c/UPDATE.md" && ok "UPDATE.md идёт третьим файлом релиза, тот же, что в теге" || bad "dist/UPDATE.md нет или другой"
  unzip -Z1 "$W/c/dist/brain-lite.zip" | grep -qE '^lite/(tools|tests|\.github)/' && bad "в архив попала мастерская" || ok "tools/tests/.github в архив не попали"
else bad "make_release --dry-run упал"; cat "$W/log"; fi
echo "ИТОГ: $PASS ok, $FAIL FAIL"
[ "$FAIL" -eq 0 ]
