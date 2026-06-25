---
name: zaznamenej
description: Session wrap-up pro libovolný projekt — audit commitů/změn od posledního zápisu, draft updates do projektové dokumentace (CLAUDE.md, docs/), apply po schválení. Invoke explicit (`/zaznamenej`) na konci work session. Pokud má projekt vlastní kopii skillu, použije ji; tahle je generický fallback.
---

# /zaznamenej — generický session wrap-up

Cíl: zachytit, co se v session udělalo, do souborů, které budoucí session auto-loaduje (CLAUDE.md) nebo snadno najde (docs/). Ne jen do git logu.

> ⚠️ **Token-tax pravidlo**: root CLAUDE.md se loaduje do každé session. Detail patří do `docs/*.md`, CLAUDE.md jen current state + pointery. Pokud projekt CLAUDE.md nemá a session přinesla trvalé poznatky, navrhni založit minimální (~1 KB): stack one-liner, deploy postup, klíčové gotchas.

## Workflow

1. **Audit změn.** `git log` od posledního commitu, který sahal na dokumentaci (`git log -1 --format=%H -- CLAUDE.md docs/`); když projekt nemá git, shrň z paměti session. 0 změn → oznám a stop.
2. **Klasifikuj.** Trivial (typo/format) → skip. Feature / bugfix / infra / rozhodnutí → kandidát na zápis. U rozhodnutí zachyť **proč** (commit message to nemá).
3. **Najdi cílové soubory.** Postupně: projektový CLAUDE.md („kde najdeš co" tabulka, status sekce) → `docs/HISTORY.md` či ekvivalent → `docs/` tematický soubor. Co projekt nemá, nevytvářej bez návrhu userovi.
4. **Draft proposal.** Ukaž stručně: které soubory, jaké změny, plné znění nových odstavců. Texty piš věcně — žádný AI-marketing sloh (případně prožeň skillem na humanizaci textu, máš-li).
5. **Apply po OK.** V auto mode aplikuj rovnou a referuj. Commit dokumentace zvlášť (`docs: zaznamenej YYYY-MM-DD — <shrnutí>`).
6. **Follow-upy.** Nedodělky → `gh issue create` (pokud projekt používá GitHub), jinak TODO sekce v docs. Pokud práce pokračuje v nové session, nabídni sepsání handover promptu pro navazující session (máš-li skill `/handover`).
7. **Memory.** Pokud session přinesla poznatek přesahující projekt (infra vzor, preference uživatele), navrhni zápis do `~/.claude/memory/` + řádek do MEMORY.md indexu.

## Boundary

- Jen `.md` soubory (+ `.env.example`), žádný produkční kód.
- Nepřepisuj historické zápisy — jen append/aktualizace current state.
- Nový auto-loaded CLAUDE.md = separátní rozhodnutí usera, ne automatika.
