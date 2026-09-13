# claude-skills

Sbírka mých [Claude Code](https://claude.com/claude-code) skillů. Každá podsložka je jeden skill, který jde nainstalovat samostatně.

## Skilly

| Skill | Popis |
|-------|-------|
| [`zaznamenej`](zaznamenej/) | Session wrap-up — audit změn od posledního zápisu a draft updatů do vrstvené dokumentace: rolling stav (CLAUDE.md), aktivní okno (HISTORY.md), durable lekce (LESSONS.md), tematické docs/. Spouští se ručně přes `/zaznamenej`. |
| [`merge`](merge/) | Race-safe merge → deploy jednoho PR: volitelný Codex review gate podle složitosti PR, rebase na `origin/main`, čekání na green CI vázané na přesný HEAD SHA (žádné stale výsledky po force-pushi; docs-only diff má grace okno), squash-merge + smazání branche, doclosování issues s česky psaným uzavíracím záměrem, pak deploy tail dle konvence projektu. Náhrada za merge queue zamčenou na free planu + privátním repu (403). |
| [`handover`](handover/) | Sepíše ready-to-paste prompt pro novou Claude Code session, aby navázala bez ztráty kontextu — stav repa, foundation skip-list, příští úkol. Default inline, u velkého kontextu soubor v `~/.claude/plans/`. |
| [`feature`](feature/) | Rozjede izolovanou práci na funkci v git worktree přímo v session (EnterWorktree → provisioning → práce → bezpečný cleanup). Cílí na Node/Windows: node_modules junction + unikátní dev PORT, ať běží víc oken paralelně. |
| [`night-shift`](night-shift/) | Autonomní noční směna nad plánem v GitHub issues (checklist / epic se sub-issues / seznam issues). Tenký supervisor drží minimální kontext a na každou jednotku spouští worker subagenta s čerstvým oknem; green verify → commit → odškrtnutí. Failure policy s BLOCKED markery, context guard, řízený stop s push notifikací, ráno draft PR. |

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
  - `allowed-tools` v `merge/SKILL.md` odkazuje na `~/.claude/skills/merge/lib/*.sh` — pokud skill nainstaluješ jinam, cestu uprav;
  - používá in-session nástroj `ExitWorktree` (volitelné, jen při práci v git worktree);
  - doclosování issues cílí na **česky** psané PR descriptions („Uzavírá #N") — pro jiný jazyk uprav `STRONG_RE`/`WEAK_RE` v `lib/pr-merge.sh`, nebo sekci 4b/5b odstraň (merge funguje i bez ní);
  - **Codex review gate (krok 0) je volitelný.** Vyžaduje plugin [`codex`](https://github.com/openai/codex-plugin-cc) od OpenAI (`/plugin install codex@openai-codex`, pak `/codex:setup`) a agenta `merge/agents/codex-reviewer.md` zkopírovaného do `~/.claude/agents/`. Bez pluginu `lib/review-gate.sh` vrátí `TIER=skip` a merge jede rovnou. Prahy složitosti (soubory, řádky, rizikové cesty) ladíš v hlavičce skriptu; vypnutí natvrdo `MERGE_REVIEW_GATE=off`, ruční override `/merge --review` / `--no-review`.
- **`feature`** cílí na **Node projekty na Windows** — provisioning skripty v `feature/lib/` vytváří node_modules junction přes `mklink /J` a dev PORT v `.env.local`. Na jiném OS/stacku uprav `wt-*.sh` (workflow zůstává). Pozn.:
  - `wt-remove.sh` používej **vždy** místo holého `git worktree remove` — ten na Windows následuje junction a smaže node_modules v main repu. Navíc před smazáním zastaví procesy patřící worktree (dev server drží adresář zamčený) a odlinkuje reparse pointy, které si Next.js kopíruje do `.next/` — na to potřebuje PowerShell helpery v `lib/_shared/`, kopíruj tedy celou složku `lib/`;
  - cesty v `allowed-tools` a SKILL.md míří na `~/.claude/skills/feature/lib/` — při jiné instalaci uprav;
  - statusline (`model | branch | worktree | :PORT | ctx N% | $cost`, od 250k tokenů hint na /handover) aktivuješ přes `statusLine.command` v settings.json: `bash ~/.claude/skills/feature/lib/wt-statusline.sh`; potřebuje `node` v PATH.
- **`night-shift`** předpokládá:
  - plán v **GitHub issues** (repo s `gh` CLI a auth) — checklist řídicího issue je jediný zdroj stavu, takže pád session nic neztratí;
  - session spuštěnou v **bypass permissions** přes settings profil (např. `~/.claude/night-settings.json`: bypass + deny na secrets a force push) — preflight se na to ptá a bez potvrzení nespustí smyčku; jediný permission prompt v noci znamená zaseknutou směnu do rána;
  - in-session nástroje `Agent`, `ScheduleWakeup`, `TaskOutput`/`TaskStop` a `PushNotification` (Claude Code je má built-in);
  - volitelně vlastní levné subagenty na audit zadání a verify běhy — bez nich skill říká, čím je nahradit.

## Licence

[MIT](LICENSE)
