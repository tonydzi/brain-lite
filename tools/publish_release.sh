#!/usr/bin/env bash
# publish_release.sh: собрать и опубликовать релиз для УЖЕ запушенного тега, затем проверить скачиванием.
#
# Вход:  tools/publish_release.sh vX.Y.Z   (тег уже на GitHub; нужен gh с правом contents:write)
# Выход: релиз с brain-lite.zip, SHA256SUMS.txt, UPDATE.md, VERSION; печать суммы. exit 0 = опубликован
#        и скачанное совпало с собранным.
# Кто зовёт: .github/workflows/autorelease.yml (обычный выпуск и «досоздать потерянный релиз»).
# Идемпотентен: релиз уже есть = ничего не делает, exit 0.
# Архив детерминирован: TZ=UTC git archive -0 по тегу.
# рельса: git + gh, без LLM.
set -euo pipefail
TAG="${1:?usage: publish_release.sh vX.Y.Z}"
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
if gh release view "$TAG" >/dev/null 2>&1; then echo "релиз $TAG уже есть"; exit 0; fi
if command -v sha256sum >/dev/null; then SUM="sha256sum"; else SUM="shasum -a 256"; fi
rm -rf dist && mkdir dist
TZ=UTC git archive --format=zip -0 --prefix=lite/ -o dist/brain-lite.zip "$TAG"
(cd dist && $SUM brain-lite.zip > SHA256SUMS.txt)
git show "$TAG:UPDATE.md" > dist/UPDATE.md
git show "$TAG:VERSION" > dist/VERSION
HASH="$(cut -d' ' -f1 dist/SHA256SUMS.txt)"
NOTES="$(git show "$TAG:CHANGELOG.md" | awk '/^## /{n++} n==1')

SHA256 brain-lite.zip: \`$HASH\`

Обновиться: скажите своему помощнику «обнови лайт» (рецепт в UPDATE.md)."
LATEST="$(git tag --list 'v*' --sort=-v:refname | head -1)"
FLAG="--latest=false"; [ "$LATEST" = "$TAG" ] && FLAG="--latest"
gh release create "$TAG" dist/brain-lite.zip dist/SHA256SUMS.txt dist/UPDATE.md dist/VERSION \
  --verify-tag --title "brain-lite $TAG" --notes "$NOTES" "$FLAG"
rm -rf dist/check && mkdir dist/check
gh release download "$TAG" -D dist/check
(cd dist/check && $SUM -c SHA256SUMS.txt)
cmp dist/check/brain-lite.zip dist/brain-lite.zip
[ "$(cat dist/check/VERSION)" = "${TAG#v}" ]
echo "релиз $TAG опубликован и проверен скачиванием: sha256 $HASH"
