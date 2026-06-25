---
name: zaznamenej
description: Session wrap-up pro libovolný projekt — audit změn od posledního zápisu, draft updatů do vrstvené projektové dokumentace (CLAUDE.md = rolling stav, HISTORY.md = aktivní okno, LESSONS.md = durable lekce, docs/), apply po schválení. Invoke explicit (`/zaznamenej`) na konci work session. Pokud má projekt vlastní kopii skillu, použije ji; tahle je generický fallback.
---

# /zaznamenej — generický session wrap-up

Cíl: zachytit, co se v session udělalo, do souborů, které budoucí session auto-loaduje (CLAUDE.md) nebo snadno najde (docs/). Ne jen do git logu — ten neuchová dvě věci: **proč** se rozhodnutí udělalo a **co dělat příště** (durable lekce).

> ⚠️ **Token-tax pravidlo**: root CLAUDE.md se loaduje do každé session. Detail patří do `docs/*.md`, CLAUDE.md jen current state + pointery. Doktrína: CLAUDE.md = rozcestník, ne knihovna.

## Vrstvy dokumentace

Rozděl zápis podle životnosti — co je rolling stav, co aktivní historie, co durable poučení. Co projekt nemá, nevytvářej bez návrhu (viz fallback níže).

| Vrstva | Typický soubor | Co drží |
|---|---|---|
| **Rolling stav** | `CLAUDE.md` (Status) | current state + posledních ~5 zápisů, každý 1 věta + odkaz |
| **Aktivní okno** | `docs/HISTORY.md` (či CHANGELOG) | plné zápisy aktuálního období + index všech |
| **Archiv** | `docs/history/*.md` | staré zápisy, **needitovat** (vznikne až když HISTORY naroste) |
| **Durable lekce** | `docs/LESSONS.md` | tematicky tříděné poučení napříč zápisy |
| **Klient changelog** (volitelné) | `content/novinky.md` ap. | jen klient-viditelné změny |

**Rolling window**: status v CLAUDE.md drží přesně N posledních zápisů (např. 5) — nový dovnitř, nejstarší ven (plné znění zůstává v HISTORY.md). Tím status neroste do nekonečna.

**Fallback** (projekt tuhle strukturu nemá): zapiš aspoň do CLAUDE.md (current state) + git. Pokud session přinesla trvalé poznatky a projekt CLAUDE.md nemá, navrhni založit minimální (~1 KB): stack one-liner, deploy postup, klíčové gotchas. Novou vrstvu (HISTORY.md, LESSONS.md) zakládej jen po návrhu userovi.

## Workflow

1. **Audit změn.** `git log` od posledního commitu, který sahal na dokumentaci (`git log -1 --format=%H -- CLAUDE.md docs/`); když projekt nemá git, shrň z paměti session. 0 změn → oznám a stop.
2. **Klasifikuj per commit.** Trivial (typo/format) / doc-only → skip. Feature / bugfix / infra / migrace → kandidát na zápis. **Rozhodnutí** → zachyť **proč** (commit message to nemá); load-bearing ∧ kontraintuitivní rozhodnutí → kandidát na ADR (`docs/decisions/`). Bug fix / gotcha → kandidát na durable lekci.
3. **Draft zápisu** (kompaktní formát níže) do aktivní vrstvy + **rolling window update** v CLAUDE.md (přidej 1-větný bullet, dropni nejstarší).
4. **Draft durable lekcí.** Co se rozbilo/zjistilo a co dělat jinak → `docs/LESSONS.md` do tematické sekce (formát níže). Zápis v HISTORY drží jen jednořádkový pointer na lekci.
5. **Najdi další dotčené docs.** Tematické `docs/*.md` dle scope změny (architektura, deploy, API…), `.env.example` u nového env varu. Co projekt nemá, nevytvářej bez návrhu.
6. **Draft proposal.** Ukaž stručně: které soubory, jaké změny, plné znění nových odstavců. Texty piš věcně — žádný AI-marketing sloh (případně prožeň skillem na humanizaci, máš-li). V auto mode aplikuj rovnou a referuj.
7. **Apply po OK.** Commit dokumentace zvlášť (`docs: zaznamenej YYYY-MM-DD — <shrnutí>`). Nedodělky → `gh issue create` (pokud projekt používá GitHub), jinak TODO sekce v docs. Práce pokračuje → nabídni handover prompt (máš-li skill `/handover`).
8. **Memory.** Poznatek přesahující projekt (infra vzor, preference uživatele) → navrhni zápis do `~/.claude/memory/` + řádek do MEMORY.md indexu.

## Formát zápisu (kompaktní, cíl ≤20 řádků)

```markdown
## <YYYY-MM-DD> — <5-15slovní titulek>

<2-4 věty: co se udělalo a proč, jaký je výsledek/stav.>

- [#PR1](link) — <co, 1 řádek>
- [#PR2](link) — <co, 1 řádek>
- <případný incident / pivot, 1-2 řádky>

Lekce → LESSONS.md#<sekce>: <3-8slovní shrnutí>. Memory: `slug`. Migrace: žádná / NNNN. Closes #N.
```

Detail patří do PR descriptions a GH issues, ne do zápisu.

## Durable lekce — formát

Append do tematické sekce `docs/LESSONS.md` (např. `## Deploy & provoz`, `## Data & DB`, `## Frontend`, `## Workflow & AI`, `## Integrace & API`):

```markdown
- **<úderný titulek>** — <1-3 řádky: co se rozbilo/zjistilo a co dělat jinak; samonosné bez čtení historie>. *(<YYYY-MM-DD> / #PR)*
```

Lekce se **nemažou** — jen append / merge duplicit. Oddělení od timeline je záměr: timeline = „co se stalo kdy", LESSONS = „co dělat příště".

## Boundary

- Jen `.md` soubory (+ `.env.example`), žádný produkční kód.
- Nepřepisuj historické zápisy ani archiv — jen append / aktualizace current state + rolling window.
- Nový auto-loaded CLAUDE.md (root nebo `**/CLAUDE.md`) = separátní rozhodnutí usera, ne automatika.
- Vždy draft proposal před apply (mimo auto mode).
