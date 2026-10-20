#!/usr/bin/env bash
# make_release.sh: выпустить версию brain-lite одной командой.
#
# Вход:  tools/make_release.sh v1.0.0 [--dry-run]   (из любой папки внутри репо)
# Выход: аннотированный тег, релиз на GitHub с brain-lite.zip, SHA256SUMS.txt, UPDATE.md и VERSION; в --dry-run только файлы в dist/.
# Кто зовёт: Антон или его агент, после того как правка смержена в main и CI на ней зелёный.
# Что ломается без него: друзья не получают обновление; ручная сборка забывает сумму или кладёт лишнее.
# Порядок: страж и тесты локально -> main совпадает с origin/main -> CI на этом коммите зелёный ->
# тег -> архив -> пуш тега -> релиз. Любая проверка не прошла: тег не ставится и не пушится.
# Архив детерминирован: TZ=UTC git archive -0 (без сжатия и без местного пояса), время = время коммита.
# CI на Ubuntu пересобирает его из тега той же командой и сверяет сумму с опубликованной.
# Зависимости: git, python3, zip, shasum или sha256sum; gh (не нужен в --dry-run).
# рельса: локально, без LLM.
set -euo pipefail

TAG="${1:?usage: make_release.sh vX.Y.Z [--dry-run]}"
DRY="${2:-}"
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$ROOT"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "СТОП: тег должен быть vX.Y.Z"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "СТОП: есть незакоммиченные изменения"; git status --short; exit 1; }
[ "v$(cat VERSION)" = "$TAG" ] || { echo "СТОП: VERSION=$(cat VERSION), тег $TAG"; exit 1; }

python3 tools/lite_guard.py --tag "$TAG"
bash tests/test_guard.sh >/dev/null || { echo "СТОП: tests/test_guard.sh красный"; exit 1; }
bash tests/test_update.sh >/dev/null || { echo "СТОП: tests/test_update.sh красный"; exit 1; }
echo "страж и тесты: зелёные"

if [ "$DRY" != "--dry-run" ]; then
  command -v gh >/dev/null || { echo "СТОП: нет gh, тег не ставлю"; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "СТОП: gh не залогинен, тег не ставлю"; exit 1; }
  [ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "СТОП: релиз только с ветки main"; exit 1; }
  git fetch -q origin main
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "СТОП: main не совпадает с origin/main, сначала push/pull"; exit 1; }
  SHA="$(git rev-parse HEAD)"
  CI="$(gh run list --workflow lite-guard.yml --commit "$SHA" --json status,conclusion --jq 'map(select(.status=="completed")) | map(.conclusion) | unique | join(",")')"
  [ "$CI" = success ] || { echo "СТОП: CI на $SHA не зелёный (сейчас: '${CI:-нет завершённых прогонов}'), дождитесь"; exit 1; }
  if gh release view "$TAG" >/dev/null 2>&1; then echo "СТОП: релиз $TAG уже есть"; exit 1; fi
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  [ "$(git rev-list -n1 "$TAG")" = "$(git rev-parse HEAD)" ] || { echo "СТОП: тег $TAG стоит не на HEAD"; exit 1; }
elif [ "$DRY" != "--dry-run" ]; then
  git tag -a "$TAG" -m "brain-lite $TAG"
fi
REF="$TAG"; git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || REF=HEAD

rm -rf dist && mkdir dist
TZ=UTC git archive --format=zip -0 --prefix=lite/ -o dist/brain-lite.zip "$REF"
if command -v shasum >/dev/null; then SUM="shasum -a 256"; else SUM="sha256sum"; fi
(cd dist && $SUM brain-lite.zip > SHA256SUMS.txt && $SUM -c SHA256SUMS.txt)
git show "$REF:UPDATE.md" > dist/UPDATE.md
git show "$REF:VERSION" > dist/VERSION
HASH="$(cut -d' ' -f1 dist/SHA256SUMS.txt)"
echo "архив: $(unzip -Z1 dist/brain-lite.zip | grep -vc '/$') файлов, $(wc -c < dist/brain-lite.zip | tr -d ' ') байт, sha256 $HASH"

if [ "$DRY" = "--dry-run" ]; then echo "dry-run: релиз не создан, файлы в dist/"; exit 0; fi

git push origin "$TAG"
trap 'echo "ВНИМАНИЕ: тег $TAG уже на GitHub, а релиз не создан. Друзей это не задевает (latest остаётся прежним). Повторите эту же команду: она продолжит с релиза."' ERR
NOTES="$(awk '/^## /{n++} n==1' CHANGELOG.md)

SHA256 brain-lite.zip: \`$HASH\`

Обновиться: скажите своему помощнику «обнови лайт» (рецепт в UPDATE.md)."
gh release create "$TAG" dist/brain-lite.zip dist/SHA256SUMS.txt dist/UPDATE.md dist/VERSION --title "brain-lite $TAG" --notes "$NOTES" --latest
echo "релиз $TAG опубликован"
