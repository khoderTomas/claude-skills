# claude-skills

Sbírka mých [Claude Code](https://claude.com/claude-code) skillů. Každá podsložka je jeden skill, který jde nainstalovat samostatně.

## Skilly

| Skill | Popis |
|-------|-------|
| [`zaznamenej`](zaznamenej/) | Session wrap-up — audit změn od posledního zápisu do dokumentace a draft updatů do projektových `.md` souborů (CLAUDE.md, docs/). Spouští se ručně na konci práce přes `/zaznamenej`. |

## Instalace

Zkopíruj složku skillu do `~/.claude/skills/` (globálně pro všechny projekty) nebo do `.claude/skills/` v konkrétním projektu:

```bash
cp -r zaznamenej ~/.claude/skills/
```

Pak v Claude Code spusť `/zaznamenej`.

## Poznámka

Skilly můžou v textu odkazovat na další moje skilly (např. `/handover`), které nejsou součástí tohoto repa — takové odkazy jsou označené jako volitelné a skill funguje i bez nich.

## Licence

[MIT](LICENSE)
