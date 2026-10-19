#!/usr/bin/env bash
# test_guard.sh: страж lite_guard.py обязан быть зелёным на чистом репо и КРАСНЫМ на каждой поломке.
# Каждая мутация делается в отдельном временном клоне HEAD и коммитится там (страж смотрит git archive HEAD).
set -uo pipefail
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
W="$(mktemp -d "${TMPDIR:-/tmp}/brain-lite-guard.XXXXXX")"
trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0; N=0
case_() { # case_ <expected rc> <name> <shell mutation run inside clone>
  N=$((N+1)); local c="$W/c$N"
  git clone -q "$ROOT" "$c"
  (cd "$c" && eval "$3" && git add -A && git -c user.name=t -c user.email=t@t commit -qm m --allow-empty) >/dev/null 2>&1
  python3 "$ROOT/tools/lite_guard.py" --root "$c" >"$W/out" 2>&1; local rc=$?
  if [ "$rc" = "$1" ]; then PASS=$((PASS+1)); echo "  ok   $2 (rc=$rc)"
  else FAIL=$((FAIL+1)); echo "  FAIL $2: rc=$rc, ждали $1"; cat "$W/out"; fi
}
case_ 0 "чистый репо" "true"
case_ 1 "в набор попал скрипт .py" "echo 'print(1)' > evil.py"
case_ 1 "в набор попал .sh внутри скиллов" "echo 'rm -rf ~' > .claude/skills/lite-plan/run.sh"
case_ 1 "токен GitHub в тексте" "echo 'token ghp_abcdefghijklmnopqrstuvwxyz0123456789' >> RULES.md"
case_ 1 "приватный ключ" "printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\n' >> FIRST-TASK.md"
case_ 1 "личный путь Антона" "echo 'см. /Users/anton/secret' >> README.md"
case_ 1 "битая ссылка" "echo '[x](NOPE.md)' >> README.md"
case_ 1 "из UPDATE.md вырезана сверка суммы" "grep -v 'shasum -a 256 -c zip.sha256' UPDATE.md > u && mv u UPDATE.md"
case_ 1 "из PowerShell вырезано сравнение суммы" "grep -v 'expected -ne' UPDATE.md > u && mv u UPDATE.md"
case_ 1 "кириллица в PowerShell-блоке" "sed -i.bak 's/No lite folder yet: first install/Первая установка/' UPDATE.md && rm UPDATE.md.bak"
case_ 1 "снято ограничение https" "sed -i.bak \"s/--proto '=https' --proto-redir '=https' //\" UPDATE.md && rm UPDATE.md.bak"
case_ 1 "e-mail в тексте" "echo 'пишите friend@example.com' >> FIRST-TASK.md"
case_ 1 "путь к шарам ~/.claude" "echo 'см. ~/.claude/scripts' >> README.md"
case_ 1 "вырезана проверка симлинков" "grep -v 'find new -type l' UPDATE.md > u && mv u UPDATE.md"
case_ 1 "VERSION не совпадает с CHANGELOG" "echo 9.9.9 > VERSION"
case_ 1 "больше 30 файлов" "mkdir -p junk && for i in \$(seq 1 20); do echo x > junk/\$i.md; done"
case_ 1 "больше 200 КБ" "python3 -c \"open('big.md','w').write('a'*210000)\""
case_ 1 "скилл без name" "sed -i.bak '/^name:/d' .claude/skills/lite-check/SKILL.md && rm .claude/skills/lite-check/SKILL.md.bak"
case_ 1 "нет памятки My-Work" "git rm -q templates/My-Work-AGENTS.md"
case_ 1 "битая ссылка-сноска" "printf '\\n[x]: no-such-file.md\\n' >> README.md"
case_ 1 "из PowerShell вырезана проверка симлинков" "grep -v 'ReparsePoint' UPDATE.md > u && mv u UPDATE.md"
case_ 1 "симлинк в наборе" "ln -s /etc/passwd link.md"
case_ 0 "tools/ и tests/ не едут в набор (export-ignore)" "echo 'print(1)' > tools/extra.py"
N=$((N+1)); c="$W/c$N"; git clone -q "$ROOT" "$c"
(cd "$c" && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m next && git tag "v$(cat VERSION)" HEAD~1) >/dev/null 2>&1
if python3 "$ROOT/tools/lite_guard.py" --root "$c" --tag "v$(cat "$c/VERSION")" >"$W/out" 2>&1; then FAIL=$((FAIL+1)); echo "  FAIL тег не на HEAD прошёл"; else grep -q 'не на HEAD' "$W/out" && { PASS=$((PASS+1)); echo "  ok   тег не на HEAD (rc=1)"; } || { FAIL=$((FAIL+1)); echo "  FAIL тег не на HEAD: не та причина"; cat "$W/out"; }; fi
echo "ИТОГ: $PASS ok, $FAIL FAIL"
[ "$FAIL" -eq 0 ]
