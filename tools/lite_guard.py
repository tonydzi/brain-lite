#!/usr/bin/env python3
"""lite_guard: страж того, что уезжает друзьям в brain-lite.zip.

Вход:  корень git-репозитория brain-lite (по умолчанию папка над tools/), опционально --tag vX.Y.Z.
Выход: печать проверок, exit 0 = всё чисто, exit 1 = есть нарушения, exit 2 = не могу судить.
Кто зовёт: CI (.github/workflows/lite-guard.yml) на каждый push/PR/тег, tools/make_release.sh перед релизом.
Что ломается без него: в архив друга может уехать скрипт, секрет, личный путь, битая ссылка
или UPDATE.md без проверки суммы.
Набор = ровно то, что отдаёт `git archive HEAD` с учётом export-ignore (тот же источник, что и релиз).
рельса: локальный python3, без LLM.
"""
import argparse
import io
import json
import pathlib
import posixpath
import re
import subprocess
import tarfile
import sys

MAX_FILES = 60
MAX_BYTES = 400_000
ALLOWED_NAMES = {"VERSION", "LICENSE"}
ALLOWED_SUFFIXES = {".md"}
SECRET_PATTERNS = [
    r"AKIA[0-9A-Z]{16}",
    r"gh[pousr]_[A-Za-z0-9]{30,}",
    r"github_pat_[A-Za-z0-9_]{30,}",
    r"sk-[A-Za-z0-9_-]{20,}",
    r"xox[abpr]-[A-Za-z0-9-]{10,}",
    r"AIza[0-9A-Za-z_-]{30,}",
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    r"\b\d{9,10}:AA[0-9A-Za-z_-]{30,}",  # telegram bot token
]
PRIVATE_PATTERNS = [
    r"/Users/anton\b",
    r"[A-Z]:\\(Obsidian|Users)\\",
    r"Anton-Knowledge",
    r"\bsecrets[\\/]",
    r"~/(artusha|\.claude|lab)\b",
    r"-100\d{9,}",
    r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}",  # любой e-mail: в набор друзьям адресов не кладём
]
REQUIRED_FILES = ["VERSION", "LICENSE", "README.md", "START.md", "UPDATE.md", "RULES.md",
                  "FIRST-TASK.md", "CHANGELOG.md", "templates/My-Work-AGENTS.md",
                  "law/CORE.md", "law/FLOOR.md", "brain/README.md", "UPSTREAM.md", "AGENTS-CORE.md",
                  "templates/notes/daily-note.md", "templates/notes/weekly-review.md"]
LITE_SKILLS = ["lite-plan", "lite-recall", "lite-check", "lite-handoff", "lite-retro", "lite-ingest", "lite-brain", "lite-decide"]
# Что исполняет или читает как закон помощник друга: здесь не должно быть команд, нашей инфраструктуры и заглушек.
POLICY_SCOPE = ("law/", ".claude/skills/", "templates/", "brain/")
POLICY_PATTERNS = [
    (r"\|\s*(sh|bash|zsh|iex)\b", "команда через конвейер в оболочку"),
    (r"\b(curl|wget)\s", "сетевая команда"),
    (r"Invoke-WebRequest|Invoke-Expression|\biex\b", "сетевая или исполняющая команда PowerShell"),
    (r"base64\s+(-d|--decode)", "раскодирование base64"),
    (r"mcp__", "инструмент MCP нашего флота"),
    (r"\$(OBSIDIAN_VAULT|USERPROFILE|IMPORTS_ROOT)", "переменная путей нашего флота"),
    (r"\{\{|<%", "заглушка сборки или Templater"),
    (r"\bnpx\s", "установка пакета"),
    (r"authored_by:|canon-proposals|_machine-bus", "служебная разметка нашего флота"),
    (r"(?i)ignore (all|previous|the) (instructions|rules)|игнорируй (правила|floor|закон|инструкции)", "попытка отменить правила"),
]
REQUIRED_IN_UPDATE = [
    "LC_ALL=C shasum -a 256 -c zip.sha256 || ",
    'find "$1" -delete; }',
    "sha256sum -c zip.sha256 || ",
    "pwd -P",
    "ReparsePoint",
    "-band 0xF000) -eq 0xA000",
    "grep -vE '^lite/'",
    "grep -q '^l'",
    "find new -type l",
    "--proto '=https' --proto-redir '=https'",
    "if ($expected -ne $actual) { throw 'STOP: checksum mismatch' }",
    "-cnotlike 'lite/*'",
    "case \"$BASE\" in https://github.com/tonydzi/brain-lite/releases/*)",
    "-notlike 'https://github.com/tonydzi/brain-lite/releases/*'",
    "lite-prev",
]
LINK_RE = re.compile(r"\]\(([^)\s]+)\)|^\s*\[[^\]]+\]:\s*(\S+)|<([^>\s]+\.md(?:#[^>]*)?)>", re.M)


def shipped(root):
    """Список (путь, байты) ровно как в git archive HEAD."""
    out = subprocess.run(["git", "-C", str(root), "archive", "--format=tar", "HEAD"],
                         capture_output=True, check=True).stdout
    files = []
    with tarfile.open(fileobj=io.BytesIO(out)) as tar:
        for m in tar.getmembers():
            if m.isfile():
                files.append((m.name, tar.extractfile(m).read()))
            elif not m.isdir() and m.type != tarfile.XGLTYPE:
                files.append((m.name, b"\0NOT-A-REGULAR-FILE"))
    return files


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=str(pathlib.Path(__file__).resolve().parent.parent))
    ap.add_argument("--tag", help="ожидаемый тег релиза, например v1.0.0")
    a = ap.parse_args()
    root = pathlib.Path(a.root)
    try:
        files = shipped(root)
    except Exception as e:  # noqa: BLE001
        print(f"НЕ МОГУ СУДИТЬ: git archive не отработал: {e}")
        return 2
    problems = []
    names = {n for n, _ in files}
    total = sum(len(b) for _, b in files)
    print(f"набор: {len(files)} файлов, {total} байт")
    if not files:
        problems.append("набор пуст")
    if len(files) > MAX_FILES:
        problems.append(f"файлов {len(files)} > {MAX_FILES}")
    if total > MAX_BYTES:
        problems.append(f"размер {total} > {MAX_BYTES}")

    for req in REQUIRED_FILES:
        if req not in names:
            problems.append(f"нет обязательного файла {req}")

    for name, data in files:
        p = pathlib.PurePosixPath(name)
        if data == b"\0NOT-A-REGULAR-FILE":
            problems.append(f"{name}: не обычный файл (симлинк?)")
            continue
        if p.name not in ALLOWED_NAMES and p.suffix not in ALLOWED_SUFFIXES:
            problems.append(f"{name}: тип не разрешён (в набор едет только .md, VERSION, LICENSE)")
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            problems.append(f"{name}: не UTF-8 текст")
            continue
        for pat in SECRET_PATTERNS:
            if re.search(pat, text):
                problems.append(f"{name}: похоже на секрет ({pat})")
        for pat in PRIVATE_PATTERNS:
            if re.search(pat, text):
                problems.append(f"{name}: личный путь или адрес ({pat})")
        if p.suffix == ".md":
            prose = re.sub(r"`[^`\n]*`", "", re.sub(r"```.*?```", "", text, flags=re.S))
            for link in (next(g for g in m if g) for m in LINK_RE.findall(prose)):
                if re.match(r"^(https?:|mailto:|#)", link):
                    continue
                rel = posixpath.normpath(posixpath.join(str(p.parent), link.split("#")[0]))
                if not (rel in names or any(n.startswith(rel.rstrip("/") + "/") for n in names)):
                    problems.append(f"{name}: битая ссылка {link}")

    version = dict(files).get("VERSION", b"").decode().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        problems.append(f"VERSION не semver: {version!r}")
    changelog = dict(files).get("CHANGELOG.md", b"").decode()
    m = re.search(r"^## (\d+\.\d+\.\d+)", changelog, re.M)
    if not m or m.group(1) != version:
        problems.append(f"верхняя запись CHANGELOG ({m.group(1) if m else 'нет'}) != VERSION ({version})")
    if a.tag and a.tag != f"v{version}":
        problems.append(f"тег {a.tag} != v{version}")
    if a.tag:
        r = subprocess.run(["git", "-C", str(root), "rev-list", "-n1", a.tag], capture_output=True, text=True)
        head = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        if r.returncode == 0 and r.stdout.strip() != head:
            problems.append(f"тег {a.tag} стоит не на HEAD: страж проверял бы не то")

    update = dict(files).get("UPDATE.md", b"").decode()
    for must in REQUIRED_IN_UPDATE:
        if must not in update:
            problems.append(f"UPDATE.md: нет обязательной проверки «{must}»")

    for i, block in enumerate(re.findall(r"```sh\n(.*?)```", update, re.S)):
        if re.search(r"(^|[\s;&|(])rm\s+-[a-zA-Z]*[rf]", block, re.M):
            problems.append(f"UPDATE.md: sh-блок {i} с rm -rf/-f (песочница Codex отвергает рецепт целиком)")
    for i, block in enumerate(re.findall(r"```powershell\n(.*?)```", update, re.S)):
        if re.search(r"[^\x00-\x7F]", block):
            problems.append(f"UPDATE.md: powershell-блок {i} не только ASCII (сломается в Windows PowerShell 5.1)")
    if len(re.findall(r"```powershell\n", update)) != 4 or len(re.findall(r"```sh\n", update)) != 4:
        problems.append("UPDATE.md: ожидалось по 4 блока sh и powershell (шаг 1, шаг 2, откат, проверка)")

    skills = sorted(n for n in names if n.startswith(".claude/skills/") and n.endswith("/SKILL.md"))
    try:
        manifest = json.loads(subprocess.run(["git", "-C", str(root), "show", "HEAD:tools/upstream.json"],
                                             capture_output=True, check=True, text=True).stdout)
        expected_files = set(manifest["files"].values())
    except Exception as e:  # noqa: BLE001
        problems.append(f"не читается tools/upstream.json: {e}")
        expected_files = set()
    for ef in sorted(expected_files - names):
        problems.append(f"файл из upstream.json не в наборе: {ef}")
    expected_skills = {f".claude/skills/{n}/SKILL.md" for n in LITE_SKILLS} | {f for f in expected_files if f.startswith(".claude/skills/")}
    for miss in sorted(expected_skills - set(skills)):
        problems.append(f"нет скилла {miss}")
    for extra in sorted(set(skills) - expected_skills):
        problems.append(f"лишний скилл, не в списке: {extra}")
    brain_layers = {n.split("/")[1] for n in names if n.startswith("brain/") and n.count("/") == 2}
    if len(brain_layers) < 11:
        problems.append(f"в скелете мозга {len(brain_layers)} слоёв из 11")
    for s in skills:
        head = dict(files)[s].decode()
        dirname = s.split("/")[2]
        fm = re.match(r"^---\n(.*?)\n---\n", head, re.S)
        if not fm or not re.search(rf"^name: {re.escape(dirname)}$", fm.group(1), re.M):
            problems.append(f"{s}: frontmatter без name: {dirname}")
        if fm and not re.search(r"^description: *(?:[>|]-?\n(?: +\S.*\n?)+|\S.{9,})", fm.group(1) + "\n", re.M):
            problems.append(f"{s}: нет description")

    floor_pin = root / "tools" / "law-floor.sha256"
    if "law/FLOOR.md" in names:
        import hashlib
        got = hashlib.sha256(dict(files)["law/FLOOR.md"]).hexdigest()
        allowed = set(floor_pin.read_text().split()) if floor_pin.exists() else set()
        if got not in allowed:
            problems.append(f"law/FLOOR.md изменился ({got[:12]}): пол безопасности меняется только вручную, "
                            f"после чтения человеком; разрешённый хеш добавить в tools/law-floor.sha256")
    for name, data in files:
        if not name.startswith(POLICY_SCOPE):
            continue
        text = data.decode("utf-8", "replace")
        for pat, why in POLICY_PATTERNS:
            m = re.search(pat, text)
            if m:
                problems.append(f"{name}: {why} ({m.group(0)!r})")

    for prob in problems:
        print(f"FAIL {prob}")
    print("ИТОГ:", "OK" if not problems else f"{len(problems)} нарушений")
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())
