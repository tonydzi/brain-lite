#!/usr/bin/env python3
"""sync_upstream: подтянуть в brain-lite свежие версии файлов из second-brain-starter-kit.

Вход:  tools/upstream.json (репо, ветка, карта «путь в наборе -> путь в brain-lite»);
       --source-dir DIR для тестов и офлайна (папка вместо скачивания), --sha для такого режима.
Выход: файлы обновлены на месте, UPSTREAM.md = провенанс (коммит набора, дата коммита, список файлов);
       печать: какие файлы изменились. exit 0 = синхронизировано (изменения или нет), 1 = ошибка.
Кто зовёт: .github/workflows/autorelease.yml дважды в сутки и вручную; дальше гейт lite_guard решает,
       можно ли это выпускать. Путь «наш шкаф -> starter-kit» делает хабовый публикатор набора.
Что ломается без него: друзья не получают наших улучшений закона, скиллов и шаблонов.
Детерминирован: без «текущего времени»; UPSTREAM.md переписывается только вместе с реальным изменением файлов.
Очистка при приёме (transforms в upstream.json): kit_footer срезает рекламный хвост, core_lite убирает
сборочные заглушки персоны. Структура источника изменилась и очистка не находит якорь: exit 1 (красный
прогон, человек смотрит). Файл выбыл из карты: удаляется здесь (по списку из прежнего UPSTREAM.md).
рельса: stdlib, без LLM.
"""
import argparse
import io
import json
import os
import pathlib
import re
import sys
import tarfile
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent


def fetch(url):
    headers = {"User-Agent": "brain-lite-sync", "Accept": "application/vnd.github+json"}
    if os.environ.get("GH_TOKEN") and "api.github.com" in url:
        headers["Authorization"] = f"Bearer {os.environ['GH_TOKEN']}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


class TransformError(Exception):
    pass


def kit_footer(text):
    """Срезать рекламный хвост набора (ссылки на npx, другие репо, контакты автора)."""
    if "<!--kit-footer-->" not in text:
        raise TransformError("нет маркера <!--kit-footer-->")
    return text.split("<!--kit-footer-->")[0].rstrip() + "\n"


def core_lite(text):
    """CORE набора рассчитан на сборку персоны: убрать заглушки {{...}}, абзац про сборку и §11 «подпись сессии»."""
    if not re.search(r"^\{\{FLOOR\}\}$", text, re.M):
        raise TransformError("нет заглушки {{FLOOR}}: структура CORE изменилась, нужна ручная проверка")
    text = re.sub(r"^\{\{[A-Z_]+\}\}\n?", "", text, flags=re.M)
    text = re.sub(r"\n## §11\. Подпись сессии\n.*?(?=\n## |\Z)", "\n", text, flags=re.S)
    text = re.sub(r"^> Этот файл СОБИРАЕТСЯ.*?\n(?:> .*ПРОФИЛЬ.*\n)?",
                  "> В лайте этот файл читают напрямую. Профиль владельца: его раздел в `My-Work/AGENTS.md`.\n",
                  text, flags=re.M)
    text = text.replace("(кто он — в блоке ПРОФИЛЬ ЧЕЛОВЕКА ниже)", "(кто он — в разделе владельца в `My-Work/AGENTS.md`)")
    if "{{" in text or "ПРОФИЛЬ" in text:
        raise TransformError("после очистки остались заглушки или ссылки на ПРОФИЛЬ")
    return text.rstrip() + "\n"


TRANSFORMS = {"kit_footer": kit_footer, "core_lite": core_lite}


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--source-dir")
    ap.add_argument("--sha", default="local")
    ap.add_argument("--date", default="")
    a = ap.parse_args()
    cfg = json.loads((ROOT / "tools/upstream.json").read_text())
    files = cfg["files"]
    got = {}
    if a.source_dir:
        src = pathlib.Path(a.source_dir)
        sha, date = a.sha, a.date
        for s in files:
            p = src / s
            if not p.is_file():
                print(f"ОШИБКА: в источнике нет {s}")
                return 1
            got[s] = p.read_bytes()
    else:
        try:
            meta = json.loads(fetch(f"https://api.github.com/repos/{cfg['repo']}/commits/{cfg['ref']}"))
            sha, date = meta["sha"], meta["commit"]["committer"]["date"]
            tar = tarfile.open(fileobj=io.BytesIO(fetch(f"https://codeload.github.com/{cfg['repo']}/tar.gz/{sha}")))
        except (urllib.error.URLError, OSError, KeyError, TypeError, ValueError) as e:
            print(f"ОШИБКА: не смог получить набор: {e}")
            return 1
        members = {m.name.split("/", 1)[1]: m for m in tar.getmembers() if "/" in m.name and m.isfile()}
        for s in files:
            if s not in members:
                print(f"ОШИБКА: в наборе {sha[:12]} нет {s}")
                return 1
            got[s] = tar.extractfile(members[s]).read()
    # Набор местами хранит CRLF; у нас всё LF (.gitattributes). Едут только .md, их и нормализуем.
    got = {k: (v.replace(b"\r\n", b"\n") if k.endswith(".md") else v) for k, v in got.items()}
    for s, names in cfg.get("transforms", {}).items():
        text = got[s].decode("utf-8")
        for n in names:
            try:
                text = TRANSFORMS[n](text)
            except TransformError as e:
                print(f"ОШИБКА очистки {s} ({n}): {e}")
                return 1
        got[s] = text.encode("utf-8")
    changed = []
    for s, dst in files.items():
        out = ROOT / dst
        if not out.exists() or out.read_bytes() != got[s]:
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(got[s])
            changed.append(dst)
    prov = ROOT / "UPSTREAM.md"
    old_targets = set(re.findall(r"^\| `([^`]+)` \|", prov.read_text(), re.M)) if prov.exists() else set()
    for stale in sorted(old_targets - set(files.values())):
        p = ROOT / stale
        if p.exists():
            p.unlink()
            changed.append(f"{stale} (удалён: больше не едет из набора)")
    if not changed and prov.exists():
        print(f"набор {sha[:12]}: изменено 0")
        return 0
    lines = [
        "# Откуда эти файлы",
        "",
        f"Часть библиотеки приезжает из [{cfg['repo']}](https://github.com/{cfg['repo']}) автоматически,",
        "когда там появляются улучшения. Остальное (приёмы `lite-*`, рецепт, скелет мозга) живёт здесь.",
        "",
        f"Коммит набора: `{sha}`" + (f" от {date}" if date else ""),
        "",
        "| Файл здесь | Источник в наборе |",
        "|---|---|",
    ] + [f"| `{dst}` | `{s}` |" for s, dst in files.items()]
    text = "\n".join(lines) + "\n"
    if not prov.exists() or prov.read_text() != text:
        prov.write_text(text)
        changed.append("UPSTREAM.md")
    print(f"набор {sha[:12]}: изменено {len(changed)}")
    for c in changed:
        print(f"  {c}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
