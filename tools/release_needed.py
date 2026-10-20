#!/usr/bin/env python3
"""release_needed: нужен ли новый релиз, и если да, поднять версию.

Вход:  git-репозиторий brain-lite с тегами vX.Y.Z.
       check          : печатает изменённые с последнего тега файлы НАБОРА (то, что едет другу),
                        exit 0 = релиз нужен, exit 3 = не нужен, exit 4 = VERSION уже поднята
                        вручную (идёт ручной релиз make_release.sh, автоматика не вмешивается),
                        exit 2 = не могу судить.
       bump --date D  : поднимает patch в VERSION и пишет запись CHANGELOG со списком файлов.
Выход: изменённые VERSION и CHANGELOG.md (только bump), печать новой версии.
Кто зовёт: .github/workflows/autorelease.yml после sync_upstream.py.
Что ломается без него: релиз выходил бы на каждый прогон (шум) или не выходил бы вовсе.
Набор = файлы без export-ignore (тот же источник, что git archive). VERSION и CHANGELOG.md
изменения сами по себе релиза не требуют.
рельса: stdlib + git, без LLM.
"""
import argparse
import io
import pathlib
import re
import subprocess
import sys
import tarfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


def git(*a):
    return subprocess.run(["git", "-C", str(ROOT), *a], capture_output=True, text=True, check=True).stdout


def last_tag():
    tags = [t for t in git("tag", "--list", "v*", "--sort=-v:refname").split() if re.fullmatch(r"v\d+\.\d+\.\d+", t)]
    return tags[0] if tags else None


def shipped_set(ref):
    # Ровно то, что отдаёт git archive (export-ignore на папке check-attr не видит, archive видит).
    out = subprocess.run(["git", "-C", str(ROOT), "archive", "--format=tar", ref], capture_output=True, check=True).stdout
    with tarfile.open(fileobj=io.BytesIO(out)) as t:
        return {m.name for m in t.getmembers() if not m.isdir()}


NOT_A_REASON = ("VERSION", "CHANGELOG.md", "UPSTREAM.md")  # меняются вместе с настоящими изменениями, сами релиз не требуют


def shipped_changes(tag):
    names = [n for n in git("diff", "--name-only", f"{tag}..HEAD").splitlines() if n]
    head, old = shipped_set("HEAD"), shipped_set(tag)
    changed = {n for n in names if n in head | old}
    changed |= head ^ old  # файл начал или перестал ехать (например, правка export-ignore)
    return sorted(n for n in changed if n not in NOT_A_REASON)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check")
    b = sub.add_parser("bump")
    b.add_argument("--date", required=True)
    a = ap.parse_args()
    tag = last_tag()
    if not tag:
        print("НЕ МОГУ СУДИТЬ: нет ни одного тега vX.Y.Z")
        return 2
    if subprocess.run(["git", "-C", str(ROOT), "merge-base", "--is-ancestor", tag, "HEAD"]).returncode != 0:
        print(f"НЕ МОГУ СУДИТЬ: последний тег {tag} не в истории HEAD (тег уехал без main?)")
        return 2
    changes = shipped_changes(tag)
    cur = (ROOT / "VERSION").read_text().strip()
    if f"v{cur}" != tag:
        print(f"VERSION {cur} не равна последнему тегу {tag}: ручной релиз в процессе, автоматика пропускает ход")
        return 4
    if a.cmd == "check":
        print(f"с {tag} изменено в наборе: {len(changes)}")
        for c in changes:
            print(f"  {c}")
        return 0 if changes else 3
    if not changes:
        print("bump не нужен: набор не менялся")
        return 3
    x, y, z = map(int, cur.split("."))
    new = f"{x}.{y}.{z + 1}"
    (ROOT / "VERSION").write_text(new + "\n")
    import json
    synced = set(json.loads((ROOT / "tools/upstream.json").read_text())["files"].values())
    upstream = [c for c in changes if c in synced]
    own = [c for c in changes if c not in upstream]
    lines = [f"## {new} ({a.date})", ""]
    if upstream:
        lines.append("- Автообновление из second-brain-starter-kit: " + ", ".join(f"`{c}`" for c in upstream) + ".")
    if own:
        lines.append("- Изменено в brain-lite: " + ", ".join(f"`{c}`" for c in own) + ".")
    ch = ROOT / "CHANGELOG.md"
    text = ch.read_text()
    m = re.search(r"^## ", text, re.M)
    entry = "\n".join(lines) + "\n\n"
    ch.write_text(text[:m.start()] + entry + text[m.start():] if m else text.rstrip("\n") + "\n\n" + entry)
    print(new)
    return 0


if __name__ == "__main__":
    sys.exit(main())
