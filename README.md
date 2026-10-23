# brain-lite

**RU.** Лёгкий вход во флот второго мозга для своего помощника (Claude Code или Codex): закон метода,
9 приёмов, скелет второго мозга и шаблоны. Около 30 текстовых файлов, без скриптов, служб и
синхронизации, без чужих данных. Когда мы улучшаем закон, скиллы или шаблоны, выходит новый релиз;
помощник раз в день видит это и говорит владельцу, а «обнови лайт» ставит его: сверяет контрольную
сумму, показывает изменения и кладёт новую версию рядом со старой. Личные записи никуда не уходят.

Начать: **[START.md](START.md)**. Обновить или откатить: **[UPDATE.md](UPDATE.md)**.

**EN.** A tiny receive-only library of rules and four text skills for your own coding agent
(Claude Code or Codex): the method's law, 9 skills, a second-brain skeleton and note templates,
about 30 text files, no scripts, no daemons, no sync, no data of ours. New releases are cut
automatically when the parent kit improves; the agent checks once a day and the owner applies. Updates come as a
GitHub release zip with `SHA256SUMS.txt`; your agent verifies, shows the diff and swaps
`lite/` with `lite-prev/` for rollback. Your own work lives in `My-Work/` and never leaves your machine.
Start in English: [START.en.md](START.en.md) (Russian: [START.md](START.md)). The update recipe [UPDATE.md](UPDATE.md) is bilingual in its STOP messages.

```
Second-Brain-Lite/
  lite/        current version, read-only reference
  lite-prev/   previous version, for rollback
  My-Work/     your files and Brain/; never synced anywhere
```

| Файл | Зачем |
|---|---|
| [START.md](START.md) | Первый запуск: один блок в чат помощника |
| [UPDATE.md](UPDATE.md) | Установка, обновление и откат (Mac и Windows) |
| [RULES.md](RULES.md) | Границы помощника |
| [law/](law/) | Закон метода: FLOOR (пол безопасности) и CORE (как работаем) |
| [brain/](brain/README.md) | Скелет второго мозга, ставится в `My-Work/Brain` |
| [templates/notes/](templates/notes/) | Шаблоны заметок и обзоров |
| [UPSTREAM.md](UPSTREAM.md) | Что приезжает из starter-kit и с какого коммита |
| [FIRST-TASK.md](FIRST-TASK.md) | Первая задача и её проверка |
| [AGENTS-CORE.md](AGENTS-CORE.md) | Что помощник делает в начале каждого чата (закон, приёмы, проверка обновления) |
| [.claude/skills/](.claude/skills/) | 9 приёмов: lite-plan, lite-check, lite-handoff, continue, lite-ingest, lite-recall, lite-brain, lite-decide, lite-retro |
| [templates/My-Work-AGENTS.md](templates/My-Work-AGENTS.md) | Памятка помощнику для личной папки |
| [CHANGELOG.md](CHANGELOG.md) · [VERSION](VERSION) | Что менялось и какая версия |

Источник метода: [second-brain-starter-kit](https://github.com/tonydzi/second-brain-starter-kit). MIT.
