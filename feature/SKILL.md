---
name: feature
description: Rozjeď novou funkci v izolovaném git worktree přímo v této session (bez terminálu, bez nového okna). Vytvoří + vstoupí do worktree přes EnterWorktree, naprovisionuje (node_modules junction + dev PORT na Windows/Node) a pak pracuje na zadání. Použij když chceš začít paralelní/izolovanou práci na feature.
argument-hint: <worktree-name> <co se má udělat>
allowed-tools: Bash(bash ~/.claude/skills/feature/lib/wt-provision.sh:*), Bash(bash ~/.claude/skills/feature/lib/wt-remove.sh:*), Bash(git worktree list:*), Bash(git rev-parse:*), Bash(git branch:*)
---

# /feature — izolovaná práce na funkci v této session

Cíl: napíšeš `/feature <name> <zadání>` a tahle session se sama přepne do izolovaného
git worktree a začne pracovat. Žádný terminál, žádné druhé okno.

> **Stack**: provisioning skripty cílí na **Node projekty na Windows** (node_modules junction
> přes `mklink /J`, dev PORT v `.env.local`). Na jiném OS/stacku uprav `lib/wt-*.sh` — samotný
> workflow (worktree → provision → práce → bezpečný cleanup) platí univerzálně.

## Vstup
- `$1` = jméno worktree (kebab-case, např. `add-csv-export`). Když chybí, zeptej se.
- zbytek `$ARGUMENTS` = co se má v tom worktree udělat (zadání funkce).

## Krok 1 — vstup do worktree (EnterWorktree)
Zavolej nástroj **`EnterWorktree`** s `name: "<$1>"`. Vytvoří worktree v
`.claude/worktrees/<$1>/` na branchi `worktree-<$1>` (z lokálního HEAD, `baseRef=head`)
a **přepne tuhle session dovnitř**. `.worktreeinclude` (pokud ho máš) automaticky
zkopíruje gitignored soubory jako `.env.local` + `.claude/settings.local.json`.

## Krok 2 — provisioning (junction + PORT + registr)
EnterWorktree NEspouští SessionStart hook, takže doprovision ručně. Spusť:
```
bash ~/.claude/skills/feature/lib/wt-provision.sh "<popis ze zbytku $ARGUMENTS>"
```
Vytvoří node_modules **junction** na main repo (instant, bez kopírování), přiřadí
unikátní dev **PORT** (3110–3199), zapíše řádek do registru `.claude/worktree-registry.md`
(gitignored, sdílený napříč okny) a vypíše přehled ostatních worktrees.

## Krok 3 — pracuj na zadání
Pokračuj v `$ARGUMENTS`. Pro plánování přejdi do Plan mode (ve VS Code: klikni na mode
indikátor dole v promptu; v CLI: Shift+Tab). Dev server (Node): `npm run dev -- -p <PORT z kroku 2>`.

## Krok 4 — úklid (až po commitu + push/PR)
🛑 **NEpoužívej `ExitWorktree action:"remove"` dokud existuje node_modules junction** — interně
volá `git worktree remove`, který na Windows **následuje junction a smaže node_modules v main
repu** (ověřeno). Bezpečné pořadí:

1. `ExitWorktree` s `action: "keep"` → vrátí session zpět do main (junction nechá být).
2. Z main spusť: `bash ~/.claude/skills/feature/lib/wt-remove.sh <$1>` → odstraní junction PRVNÍ (link, ne cíl), pak worktree, pak řádek registru.
3. Branch po merge: `git branch -d worktree-<$1>`.

🚨 **Po PR merge spusť tu sekvenci hned** ve **stejné** session (neodkládat na příští).
Worktree dirs, co přežijí session boundary, akumulují staged WIP / stash / orphan commits,
které jiné sessions vidí jako „tajemný neznámý stav".

(Když měníš v worktree dependencies a chceš izolaci místo junction: `cmd //c rmdir node_modules` + `npm ci`.)

## Krok 5 — session končí mid-work? (CONDITIONAL)

Pokud session končí PŘED PR merge (owner pauzuje, kontext bobtná, atd.):

1. **Commit-able state** → `git commit -m "WIP: <kontext>"` + push branch. Branch survives, žádný stash chaos.
2. **Genuine WIP** co nechceš commitnout → `git stash push -m "<wt-name> WIP YYYY-MM-DD — <stručný kontext>"`. Pojmenovaný stash = dohledatelný; anonymní `stash@{0}` v cizí worktree je záhada.
3. **NIKDY nenech staged uncommitted WIP** přes session boundary — index survives, příští session vidí staged change jako svou + může commitnout nebo přepsat.

Máš-li skill `/handover`, ten při invoke scanuje worktrees na pending state — ale úklid je tvoje odpovědnost před session-end.

## Alternativa bez této session (terminál / CLI)
`claude --worktree <name>` v terminálu spustí izolovanou TUI session. Provisioning si tam
zařiď SessionStart hookem (settings.json `hooks.SessionStart`), který spustí ekvivalent
`wt-provision.sh`, nebo skript spusť ručně po startu.

## Statusline (volitelné)
`lib/wt-statusline.sh` vypíše do statusline `model | branch | worktree | :PORT` — užitečné
když běží víc oken paralelně. Aktivace: settings.json `statusLine.command`. Viz README.
