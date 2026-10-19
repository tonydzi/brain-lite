# brain-lite

**RU.** Маленькая библиотека правил и четырёх приёмов для своего помощника (Claude Code или Codex).
13 текстовых файлов, без скриптов, служб и синхронизации. Обновляется одной фразой
помощнику «обнови лайт»: он скачивает релиз, сверяет контрольную сумму, показывает, что изменилось,
и кладёт новую версию рядом со старой. Ваши личные результаты лежат отдельно и никуда не уходят.

Начать: **[START.md](START.md)**. Обновить или откатить: **[UPDATE.md](UPDATE.md)**.

**EN.** A tiny receive-only library of rules and four text skills for your own coding agent
(Claude Code or Codex). 13 text files, no scripts, no daemons, no sync. Updates come as a
GitHub release zip with `SHA256SUMS.txt`; your agent verifies, shows the diff and swaps
`lite/` with `lite-prev/` for rollback. Your own work lives in `My-Work/` and never leaves your machine.
Guide is in Russian: [START.md](START.md), [UPDATE.md](UPDATE.md).

```
Second-Brain-Lite/
  lite/        current version, read-only reference
  lite-prev/   previous version, for rollback
  My-Work/     your files; never synced anywhere
```

| Файл | Зачем |
|---|---|
| [START.md](START.md) | Первый запуск: один блок в чат помощника |
| [UPDATE.md](UPDATE.md) | Установка, обновление и откат (Mac и Windows) |
| [RULES.md](RULES.md) | Границы помощника |
| [FIRST-TASK.md](FIRST-TASK.md) | Первая задача и её проверка |
| [.claude/skills/](.claude/skills/) | Приёмы: lite-plan, lite-recall, lite-check, lite-handoff |
| [templates/My-Work-AGENTS.md](templates/My-Work-AGENTS.md) | Памятка помощнику для личной папки |
| [CHANGELOG.md](CHANGELOG.md) · [VERSION](VERSION) | Что менялось и какая версия |

Источник метода: [second-brain-starter-kit](https://github.com/tonydzi/second-brain-starter-kit). MIT.
