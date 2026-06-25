# claude-skills

Sbírka mých [Claude Code](https://claude.com/claude-code) skillů. Každá podsložka je jeden skill, který jde nainstalovat samostatně.

## Skilly

| Skill | Popis |
|-------|-------|
| [`zaznamenej`](zaznamenej/) | Session wrap-up — audit změn od posledního zápisu a draft updatů do vrstvené dokumentace: rolling stav (CLAUDE.md), aktivní okno (HISTORY.md), durable lekce (LESSONS.md), tematické docs/. Spouští se ručně přes `/zaznamenej`. |
| [`merge`](merge/) | Race-safe merge → deploy jednoho PR: rebase na `origin/main`, čekání na green CI, squash-merge + smazání branche, pak deploy tail dle konvence projektu. Náhrada za merge queue zamčenou na free planu + privátním repu (403). |
| [`handover`](handover/) | Sepíše ready-to-paste prompt pro novou Claude Code session, aby navázala bez ztráty kontextu — stav repa, foundation skip-list, příští úkol. Default inline, u velkého kontextu soubor v `~/.claude/plans/`. |
| [`feature`](feature/) | Rozjede izolovanou práci na funkci v git worktree přímo v session (EnterWorktree → provisioning → práce → bezpečný cleanup). Cílí na Node/Windows: node_modules junction + unikátní dev PORT, ať běží víc oken paralelně. |

## Instalace

Zkopíruj složku skillu do `~/.claude/skills/` (globálně pro všechny projekty) nebo do `.claude/skills/` v konkrétním projektu:

```bash
cp -r zaznamenej ~/.claude/skills/
```

Pak v Claude Code spusť `/zaznamenej` (resp. `/merge`, `/handover`).

## Poznámky

- Skilly můžou v textu odkazovat na další moje skilly (např. `/handover`), které mají vlastní podsložku v tomto repu, nebo na skilly mimo repo — takové odkazy jsou označené jako volitelné a skill funguje i bez nich.
- **`merge`** počítá s několika konvencemi a doplaď si je dle svého setupu:
  - repo nastavené na **squash merge + delete branch**;
  - deploy tail buď `scripts/post-merge-deploy.sh` v projektu, nebo `.github/workflows/deploy.yml` (auto-deploy přes Actions), jinak manuální;
  - `allowed-tools` v `merge/SKILL.md` odkazuje na `~/.claude/skills/merge/lib/pr-merge.sh` — pokud skill nainstaluješ jinam, cestu uprav;
  - používá in-session nástroj `ExitWorktree` (volitelné, jen při práci v git worktree).
- **`feature`** cílí na **Node projekty na Windows** — provisioning skripty v `feature/lib/` vytváří node_modules junction přes `mklink /J` a dev PORT v `.env.local`. Na jiném OS/stacku uprav `wt-*.sh` (workflow zůstává). Pozn.:
  - `wt-remove.sh` používej **vždy** místo holého `git worktree remove` — ten na Windows následuje junction a smaže node_modules v main repu;
  - cesty v `allowed-tools` a SKILL.md míří na `~/.claude/skills/feature/lib/` — při jiné instalaci uprav;
  - statusline (`model | branch | worktree | :PORT`) aktivuješ přes `statusLine.command` v settings.json: `bash ~/.claude/skills/feature/lib/wt-statusline.sh`.

## Licence

[MIT](LICENSE)
