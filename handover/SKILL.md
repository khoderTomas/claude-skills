---
name: handover
description: Sepiš ready-to-paste prompt pre novou Claude Code session co navazuje na aktuální práci. Default inline (≤2000 znaků); pokud kontext příliš velký, vytvoř handover soubor v ~/.claude/plans/ + reference v inline promptu. Use when user invokes /handover.
allowed-tools:
  - Bash
  - Read
  - Write
  - Grep
  - Glob
  - AskUserQuestion
  - TodoWrite
---

# /handover — handover do nové session

Sesumarizuj aktuální session tak, že fresh Claude Code session dokáže navázat **bez ztráty kontextu**, jen z prompt textu (a optionálně 1 handover souboru).

Cíl: owner zavře tuhle session, otevře novou, paste-ne prompt, AI ví přesně co dělat — bez "co jsme dělali?" round-tripu.

## Vstup

- `/handover` — autodetect next task z conversation context (TodoWrite list, recent tool uses, just-shipped PRs, owner's last messages)
- `/handover <hint>` — owner manually nasměruje, např. `/handover pokračuje na #54 export do CSV` nebo `/handover begin next wave`

Pokud conversation context **je ambiguous** (multiple plausible next tasks, žádný TodoWrite, žádný obvious "next" signal) **A** hint chybí → použij AskUserQuestion s 2-3 návrhy. Jinak produce direct.

## Sběr kontextu (proveď nejdřív, paralelně přes single message)

1. `git log --oneline -10` — recent commits
2. `git branch --show-current` + `git status -s` — current state
3. `git worktree list` — active parallel work
4. **Sibling worktree health sweep**: pro každou non-current worktree (mimo main repo root) → `git -C <path> status --porcelain` + `git -C <path> stash list | wc -l`. Stale WIP v sibling worktree se snadno přehlédne — staged změny, které přežijí PR ship, se najdou jen forenzně. Pokud non-empty, zachyť do sekce 3.7 níže.
5. `gh pr list --state merged --limit 5 --json number,title,mergedAt --repo <owner>/<repo>` — recent ships
6. (volitelné) `gh issue list --state open --limit 8 --label severity:warn --repo <owner>/<repo>` — open work

Repo path = current working dir. Owner/repo extract z `git remote -v` pokud potřeba.

## Output strategy

**DEFAULT = inline only** (single fenced ` ```markdown ` block, ≤3500 znaků). Owner zkopíruje do nové session.

**Soubor JEN když**:
- inline prompt by byl >3500 znaků
- foundation skip-list má >8 položek (heavy multi-area context)
- next task má >5 file/pattern references (heavy planning state)
- session běžela v non-main worktree S 3+ pending issues (worktree context + pending list spotřebuje 1000+ znaků)

**Heavy-context projekty**: pokud má repo rozsáhlý historický index (velký `docs/HISTORY.md`) + mnoho aktivních worktrees, prefer **file mode jako default** i pod thresholdem — reálné handovery tam bývají >2 KB (timeline refs + worktree context + memory hints + multi-PR continuity).

**Soubor path**: `~/.claude/plans/handover-YYYY-MM-DD-<slug>.md` (slug = 3-5 word kebab-case z hlavního tématu, lowercase, ascii only).

V inline prompt reference handover soubor přes `Plný kontext: @~/.claude/plans/handover-YYYY-MM-DD-<slug>.md` (`@` syntax = Claude file mention, fresh session auto-loadne).

## Prompt struktura

Sections top-to-bottom (fresh session čte v pořadí):

### 1. Stav (1-2 věty)

*"Předchozí session právě dokončila [hlavní výstup]. Repo state: [clean / pending X / atd]."*

Konkrétní, ne fluffy. Příklad:
> "Předchozí session shippnula epik #42 follow-up — 3 PRs (#51, #52, #53) merged + deployed, feature flag dormant. Main je clean."

**Timeline-awareness**: pokud repo má historický index (např. `docs/HISTORY.md` s číslovanými milestones), odkaž na poslední položku — je to primary continuity index, bez něj je handover decoupled od project timeline. Detekce: `[ -f docs/HISTORY.md ]` → embed odkaz na poslední sekci.

**Uncommitted state**: pokud `git status -s` ukáže staged / untracked → cite je v Stav explicit ("3 untracked probe scriptů v scripts/, žádné staged"). Fresh session jinak začne na clean tree a nezachytí WIP z této session.

### 2. Foundation skip-list

*"Tyto patterns/files NEMUSÍŠ re-investigovat — jsou correct po aktuální práci:"*

- Cesta + 1-line popis (helper signature, flag name, cache tag, atd.)
- 3-8 bullets max. To nejvíc užitečné, NE všechno.

Příklad:
- [`lib/services/user-export.ts`](lib/services/user-export.ts) — `buildUserExport({orgId})` vrací stream řádků, flag `USER_EXPORT` dormant, tag `cache:user-export`
- Cache tag pattern: register v `lib/cache-tags.ts` + use `withOrgCache` HOF (compile-time tag check)

### 3. Pending follow-ups (volitelné)

*"Odložené out of this session:"*

- Issue / flag flip / gate refs + důvod proč pauznuté + kdy odemknout

Vynech sekci pokud nic není.

### 3.5. Worktree context (CONDITIONAL — když session běžela v non-main worktree)

`git worktree list` ukázal že session NEbyla v hlavní worktree (cwd uvnitř `.claude/worktrees/<name>/`)? Pak fresh session musí otevřít stejný worktree, jinak loaduje špatný kontext (sibling branches, .env.local PORT, registr).

Embed:

> **Worktree**: `<name>` (branch `worktree-<name>` nebo `feature/<name>`)
> **Open in fresh session**: `claude --worktree <name>` (CLI) nebo `EnterWorktree(<name>)` (in-session)
> **Cwd po otevření**: `.claude/worktrees/<name>/`

Projekty s mnoha paralelními worktrees — cwd je load-bearing, ne implicitní. Vynech sekci pokud session běžela v main (`git worktree list` ukáže jen jeden řádek nebo cwd je hlavní path).

### 3.7. Sibling worktree health (CONDITIONAL — když ne-current worktree má pending state)

Pokud krok 4 sběru kontextu odhalil non-empty status / stash v sibling worktree → embed warning:

> **Sibling worktree pending**:
> - `<name>` — N WIP files (M staged, K untracked) — co tam je: `<top 3 paths>`
> - `<name>` — N stash entries (poslední: `<stash@{0} message>`)
>
> **Action pre fresh session**: zvážit zda WIP commit / discard / ponechat pro pokračování. Pokud má zůstat pro budoucí pokračování → pojmenovat: `git -C <wt-path> stash push -m "<wt-name> WIP YYYY-MM-DD — <kontext>"` PŘED handover, jinak fresh session nebo SessionStart hook vyhodí cryptic warning bez kontextu.

Vynech sekci pokud všechny sibling worktrees clean.

### 4. Next concrete task (CORE — vždy)

*"Tvůj příští úkol: [konkrétní akce]"*

- **Goal** (1 sentence)
- **Files to start with** — explicit paths
- **Patterns to reuse** — explicit references co fungovalo v předchozí práci
- **Known gotchas** — pre-warnings z aktuální session (footguns, API quirks, flag coupling)

To je nejdůležitější sekce. Pokud něco vynecháš, NIKDY ne tuto.

### 5. Memory hints (volitelné, max 3)

Relevantní memory entries z `~/.claude/memory/MEMORY.md` — odkaz na slug, ne plný obsah (fresh session ho auto-loadne).

## Konvence

- **Tone** = clinical, technical. AI prompt, ne human chat.
- **Code refs** = markdown link `[name](path)`.
- **Issue/PR refs** = `#N` (clickable v GitHub).
- **Dates** = YYYY-MM-DD absolute, ne "yesterday".
- **Don't repeat CLAUDE.md** — fresh session ho auto-loadne, redundance plýtvá místem.
- **Lean** — Section 4 (next task) je core; Sekce 2+3 jsou shortcuts; Section 1+5 jsou bonus.

## Po vytvoření

Vypiš inline prompt jako fenced code block aby owner mohl jedním kliknutím copy-paste-ovat. Žádný surrounding chitchat — owner ví co dostal.

Pokud jsi vytvořil i handover soubor, vypiš path zvlášť (mimo code block) aby owner věděl co máš dispozice.

## Příklad výstupu

````markdown
```markdown
# Handover — 2026-06-07 (pokračuje na #54 export do CSV)

Předchozí session shippnula epik #42 — PRs #51 / #52 / #53 merged + deployed, feature flag dormant. Main je clean.

## Foundation (skip re-investigation)
- [`lib/services/user-export.ts`](lib/services/user-export.ts) — `buildUserExport({orgId})` vrací stream řádků, flag `USER_EXPORT` dormant. Tag `cache:user-export`.
- Cache tag pattern: register v `lib/cache-tags.ts` + use `withOrgCache` HOF.
- Feature flag pattern: `lib/feature-flags.ts` FLAGS const + JSDoc per flag + `.env.example` entry.

## Pending
- 2× flag dormant, flip po ověření continuity gate: `USER_EXPORT`, `BULK_DELETE`.
- Issue #50 admin alert — kanál doručení odložen.

## Next task: #54 Export do CSV (M, 2-3 dny)
**Goal**: Nová akce "Export" v `/dashboard/users` — stáhne CSV přes `buildUserExport`, respektuje aktivní filtry.

**Files to start with**:
- `lib/services/user-export.ts` — foundation consumer
- `app/dashboard/users/_actions/` — kde žijí server akce
- `lib/services/user-list.ts` — pattern pro list query + filtry

**Patterns to reuse**: cache tag + flag + Suspense widget z předchozí vlny (3× recently shipped, viz #51/#52/#53).

**Gotchas**: export běží mimo request cache — velké orgy (>50k řádků) streamuj, nepuš celý list do paměti.

**Memory**: relevantní slugy z `~/.claude/memory/MEMORY.md` (odkaz na slug, ne plný obsah).

Spusť přes `/feature export-csv — <full goal sentence>`.
```
````

(End of skill.)
