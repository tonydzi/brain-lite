#!/bin/sh
# install.sh: установщик-спутник brain-lite для Mac и Linux. Лежит в релизе рядом с brain-lite.zip, в архив не входит.
#
# Вход:  sh install.sh prepare [started_at]   из папки Second-Brain-Lite, после того как блок «Шаг 1» из UPDATE.md
#        скачал в _staging/ файлы brain-lite.zip, SHA256SUMS.txt, VERSION и этот файл и сверил его сумму.
#        sh install.sh apply                  после отдельного «да» владельца (блок «Шаг 2»).
# Выход: prepare: проверенная распаковка в _staging/new/lite, _staging/STATE, вывод для владельца; ничего не заменяет.
#        apply:   lite = новая версия, lite-prev = прошлая, недостающие служебные файлы в My-Work.
#        Строки событий с реальным временем UTC пишутся в lite-install.log (для квитанции lite-check).
# Кто зовёт: помощник владельца по UPDATE.md. Человеку ничего печатать не нужно.
# Что ломается без него: помощник переписывал бы длинные блоки руками и обрезал шаги.
# Правила: сети нет (всё скачано до запуска); ничего не удаляет: старое переносится в _archive/;
# My-Work не читает и не меняет, только создаёт недостающие служебные файлы; любой СТОП оставляет lite как было.
# рельса: POSIX sh + unzip + shasum/sha256sum, без LLM.
set -eu

ROOT=$(pwd -P)
ST="$ROOT/_staging"
LOG="$ROOT/lite-install.log"
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
stop() { echo "СТОП: $*"; exit 1; }
event() { printf '%s %s %s\n' "$(now)" "$1" "${2:-}" >> "$LOG"; }
stamp() { date -u +%Y%m%dT%H%M%SZ; }
stash() { # stash <path> <name>: перенести в _archive/<name>-<время>, ничего не удаляя
  [ -e "$1" ] || return 0
  mkdir -p "$ROOT/_archive"
  dest="$ROOT/_archive/$2-$(stamp)-$$"
  mv "$1" "$dest"
  echo "Перенесено в архив: ${dest#"$ROOT"/}"
}
sha() {
  if command -v shasum >/dev/null 2>&1; then LC_ALL=C shasum -a 256 "$1" | cut -d' ' -f1
  else sha256sum "$1" | cut -d' ' -f1; fi
}
sum_of() { # sum_of <имя файла>: ожидаемая сумма из _staging/SHA256SUMS.txt
  grep -E "[ *]$1\$" "$ST/SHA256SUMS.txt" | head -n 1 | cut -d' ' -f1
}
state() { grep -E "^$1=" "$ST/STATE" | head -n 1 | cut -d= -f2-; }
archive_note() {
  [ -d "$ROOT/_archive" ] || return 0
  n=$(find "$ROOT/_archive" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
  echo "В _archive папок: $n. Рецепт ничего не удаляет; лишнее владелец может удалить сам."
}

prepare() {
  started="${1:-$(now)}"
  [ -f "$ST/brain-lite.zip" ] && [ -f "$ST/SHA256SUMS.txt" ] && [ -f "$ST/VERSION" ] || stop "в _staging нет скачанного релиза, сначала блок «Шаг 1»"
  ver=$(head -n 1 "$ST/VERSION")
  case "$ver" in [0-9]*.[0-9]*.[0-9]*) ;; *) stop "VERSION релиза не похож на версию: $ver" ;; esac
  for junk in "$ST/new" "$ST/unpack" "$ST/STATE"; do stash "$junk" "staging-$(basename "$junk")"; done
  expected=$(sum_of 'brain-lite[.]zip')
  [ -n "$expected" ] || stop "в SHA256SUMS.txt нет строки архива"
  [ "$(sha "$ST/brain-lite.zip")" = "$expected" ] || stop "контрольная сумма не совпала"
  LIST=$(unzip -Z1 "$ST/brain-lite.zip") || stop "не могу прочитать список архива"
  BAD=$(printf '%s\n' "$LIST" | grep -vE '^lite/' || true)
  SLIP=$(printf '%s\n' "$LIST" | grep -E '(^|/)[.][.](/|$)' || true)
  [ -z "$BAD$SLIP" ] || { echo "СТОП: подозрительные пути в архиве:"; echo "$BAD$SLIP"; exit 1; }
  TYPES=$(unzip -Z "$ST/brain-lite.zip") || stop "не могу прочитать список архива"
  if printf '%s\n' "$TYPES" | grep -q '^l'; then stop "в архиве ссылки на чужие файлы"; fi
  unzip -q "$ST/brain-lite.zip" -d "$ST/unpack"
  [ -z "$(find "$ST/unpack" -type l)" ] || stop "в архиве ссылки на чужие файлы"
  for f in VERSION RULES.md UPDATE.md CHANGELOG.md templates/My-Work-AGENTS.md; do
    [ -f "$ST/unpack/lite/$f" ] || stop "в архиве нет lite/$f"
  done
  [ "$(head -n 1 "$ST/unpack/lite/VERSION")" = "$ver" ] || stop "версия в архиве $(head -n 1 "$ST/unpack/lite/VERSION") не равна версии релиза $ver"
  mv "$ST/unpack" "$ST/new"
  id="$(stamp)-$$"
  {
    echo "install_id=$id"
    echo "version=$ver"
    echo "zip_sha256=$expected"
    echo "started_at=$started"
    echo "archive_verified_at=$(now)"
  } > "$ST/STATE"
  event started "id=$id at=$started"
  event archive_verified "id=$id version=$ver zip_sha256=$expected"
  echo "Новая версия: $ver"
  echo "Сумма архива: $expected"
  if [ -d "$ROOT/lite" ]; then
    echo "Текущая версия: $(cat "$ROOT/lite/VERSION" 2>/dev/null || echo неизвестна)"
    echo "Изменённые файлы:"
    diff -rq "$ROOT/lite" "$ST/new/lite" || true
  else
    echo "Папки lite ещё нет: это первая установка"
  fi
  echo "Начало CHANGELOG:"
  head -n 20 "$ST/new/lite/CHANGELOG.md"
  event consent_shown "id=$id"
  echo "ШАГ 1 ЗАКОНЧЕН, ничего не заменено. Покажите это владельцу и спросите «да». Просьба обновить за «да» не считается."
}

mywork() {
  cd "$ROOT"
  mkdir -p My-Work
  [ -e My-Work/AGENTS.md ] || cp lite/templates/My-Work-AGENTS.md My-Work/AGENTS.md
  [ -e My-Work/CLAUDE.md ] || printf '@AGENTS.md\n' > My-Work/CLAUDE.md
  mkdir -p My-Work/.claude
  [ -e My-Work/.claude/settings.json ] || printf '{\n  "permissions": {\n    "additionalDirectories": ["../lite"]\n  }\n}\n' > My-Work/.claude/settings.json
  if [ -f lite/AGENTS-CORE.md ] && ! grep -q 'AGENTS-CORE' My-Work/AGENTS.md; then
    printf '\n<!-- brain-lite: AGENTS-CORE -->\nВ начале каждого чата прочитай ../lite/AGENTS-CORE.md и действуй по нему.\n' >> My-Work/AGENTS.md
    echo "В памятку My-Work/AGENTS.md добавлена строка про ../lite/AGENTS-CORE.md"
  fi
  if [ -d lite/brain ] && [ ! -e My-Work/Brain ]; then cp -R lite/brain My-Work/Brain; echo "Второй мозг создан: My-Work/Brain"; fi
}

apply() {
  cd "$ROOT"
  [ ! -e _swap ] || stop "остался _swap от прерванного отката, см. «Если не получилось»"
  [ -f "$ST/STATE" ] || stop "сначала шаг 1"
  ver=$(state version); id=$(state install_id); expected=$(state zip_sha256)
  [ -n "$ver" ] && [ -n "$expected" ] || stop "_staging/STATE неполный, повторите шаг 1"
  [ "$(sha "$ST/brain-lite.zip")" = "$expected" ] || stop "архив изменился после шага 1, повторите шаг 1"
  if [ -e _old ]; then
    # Прерванная замена: продолжаем, только если состояние однозначно.
    if [ ! -e lite ] && [ -f "$ST/new/lite/VERSION" ]; then
      echo "Продолжаю прерванную замену: _old на месте, lite ещё нет"
    elif [ -f lite/VERSION ] && [ "$(head -n 1 lite/VERSION)" = "$ver" ] && [ ! -e "$ST/new/lite" ]; then
      echo "Продолжаю прерванную замену: lite $ver уже стоит, _old ещё не перенесена"
    else
      stop "осталась _old от прерванной замены (lite: $(cat lite/VERSION 2>/dev/null || echo нет), _old: $(cat _old/VERSION 2>/dev/null || echo нет)), см. «Если не получилось»"
    fi
  elif [ -f "$ST/new/lite/VERSION" ]; then
    [ "$(head -n 1 "$ST/new/lite/VERSION")" = "$ver" ] || stop "распакованная версия не равна проверенной $ver, повторите шаг 1"
    event consent_given "id=$id"
    if [ -d lite ]; then mv lite _old; fi
  elif [ -f lite/VERSION ] && [ "$(head -n 1 lite/VERSION)" = "$ver" ]; then
    echo "lite $ver уже стоит: замена не нужна"
  else
    stop "сначала шаг 1"
  fi
  [ -e lite ] || mv "$ST/new/lite" lite
  if [ -d _old ]; then stash lite-prev lite-prev; mv _old lite-prev; fi
  mywork
  stash "$ST" staging
  event installed "id=$id version=$(cat lite/VERSION)"
  echo "Готово: lite $(cat lite/VERSION)"
  if [ -d lite-prev ]; then echo "Для отката: lite-prev $(cat lite-prev/VERSION 2>/dev/null || echo неизвестна)"; fi
  archive_note
  echo "Время событий для квитанции: lite-install.log"
}

case "${1:-}" in
  prepare) prepare "${2:-}" ;;
  apply) apply ;;
  *) echo "usage: sh install.sh prepare [started_at] | apply"; exit 2 ;;
esac
