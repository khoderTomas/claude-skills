---
name: merge
description: Race-safe merge → deploy jednoho PR v libovolném projektu. Rebasne feature branch na nejnovější origin/main, počká na green CI, squash-merguje a smaže branch, pak spustí projektový deploy tail podle konvence — s jasnými STOP body (rebase konflikt, červené CI, preflight fail). Použij když je feature hotová a chceš ji bezpečně domergovat a nasadit. Náhrada za GitHub merge queue, který je na free planu + privátním repu zamčený (403).
argument-hint: <PR-number>
user-invocable: true
allowed-tools: Bash(bash ~/.claude/skills/merge/lib/pr-merge.sh:*), Bash(bash scripts/post-merge-deploy.sh:*), Bash(gh pr view:*), Bash(gh pr checks:*), Bash(gh repo view:*), Bash(git rev-parse:*), Bash(git status:*), Bash(git checkout:*), Bash(git pull:*), Bash(git branch:*), ExitWorktree
---

# /merge — race-safe merge → deploy (globální)

Cíl: `/merge <PR#>` z branche, kde jsi feature dodělal → bezpečně rebase na main,
green CI, squash merge, pak projektový deploy podle konvence. Funguje ve všech
repech nastavených na squash-only + delete-branch. Univerzální merge část je
deterministický skript; tenhle skill je orchestrátor, který umí **zastavit** a předat
ownerovi, řeší přechod worktree↔main (nástroj `ExitWorktree`) a vybírá deploy tail
dle projektu.

Proč skill místo nativního řešení: merge queue / "require up-to-date" jsou na
privátních repech na free planu zamčené (403).

## Autorizace (čti první)
Invokace `/merge` **JE** explicitní, trvalý souhlas s **merge i následným deployem** —
deploy je očekávaná, neoddělitelná část toku, ne samostatné rozhodnutí. **NEvkládej
potvrzovací gate** („chceš deployovat?", „opravdu na produkci?", „pustit nasazení?")
ani `AskUserQuestion` o povolení nasadit. Jeď fázemi A → deploy bez ptaní. Jediné
zastávky jsou **hard-stopy správnosti** (rebase konflikt, červené CI, preflight fail) —
ty jsou o korektnosti, ne o povolení. Jediný případ dotazu: aktuální větev **nemá
žádnou** otevřenou PR (např. stojíš na `main`) → zeptej se „kterou PR". Jinak NIKDY
neptej — ani na deploy, ani „kterou PR", ani nenabízej zadat číslo.

## Vstup
- **Holé `/merge` je norma — mergni PR AKTUÁLNÍ větve** (`gh pr view --json number`).
  Být na feature větvi = právě jedna její PR = featura, na které děláme. Číslo
  **NEvyžaduj ani nenabízej** (žádné „/merge <num>" rady) — je zbytečné. Rovnou jeď.
- `$1` (volitelné) = jen když owner chce mergnout JINOU PR, než je větev, na které stojí.
- Jediný dotaz: aktuální větev nemá žádnou otevřenou PR → „kterou PR". Jinak se neptej.

## Předpoklad
Jsi **na feature branchi toho PR** (v main checkoutu nebo ve worktree), strom čistý,
PR existuje. Když ne → nejdřív commit + `gh pr create`.

## Krok 1 — FÁZE A: sync + merge (univerzální)
Spusť (repo si skript autodetekuje):
```
bash ~/.claude/skills/merge/lib/pr-merge.sh <PR#>
```
Dělá: čistota → rebase na `origin/main` → push `--force-with-lease` →
`gh pr checks --watch` → `gh pr merge --squash --delete-branch`.

🛑 **STOP, když skript skončí non-zero:**
- exit 2 = **rebase konflikt** → vyřeš ručně (`git rebase origin/main` → resolve → `--continue`), pak `/merge <PR#>` znovu. NIKDY neřeš konflikt na slepo.
- exit 3 = **červené CI** → oprav příčinu, push, spusť znovu. Nedeployuj.
- jiné → přečti hlášku, předej ownerovi.

Když exit 0, ulož si `BRANCH` z výstupu a pokračuj.

## Krok 2 — zpět do main
- **Jsi ve worktree** (`git rev-parse --show-toplevel` obsahuje `/.claude/worktrees/`)?
  Zavolej nástroj **`ExitWorktree`** s `action: "keep"` (junction necháváme — `remove`
  by na Windows přes junction smazal node_modules v main repu; úklid dělá tail).
- **Jsi v main checkoutu?** `git checkout main`.

Pak: `git pull --ff-only origin main`.

## Krok 3 — deploy tail podle konvence projektu
Vyber PRVNÍ, co platí:

1. **Existuje `scripts/post-merge-deploy.sh`** → projekt má vlastní
   deploy + úklid, spusť:
   ```
   bash scripts/post-merge-deploy.sh <BRANCH-z-fáze-A>
   ```
   🛑 STOP na non-zero (typicky preflight fail) — předej ownerovi.

2. **Jinak existuje `.github/workflows/deploy.yml`** → deploy řeší
   GitHub Actions automaticky po merge. Nasazovat ručně NEsmíš. Místo toho:
   - smaž lokální branch: `git branch -d <BRANCH>` (remote už smazán merge);
   - připomeň ownerovi sledovat run Actions / smoke test workflow.

3. **Jinak** → deploy je manuální/neznámý. Zastav, řekni ownerovi že merge proběhl,
   ale deploy si musí spustit sám (a navrhni doplnit `scripts/post-merge-deploy.sh`).

## Krok 4 — smoke + watch (ty, ne skript)
- **Smoke-check sám** přes Playwright harness (capture konzole + network do souboru,
  přečti výsledek) na 1–2 klíčových routách (dotčená feature + home). Chyby ber z capture, ne z dialogů.
- Připomeň **post-deploy watch** dle konvence projektu (např. sledování chyb v monitoringu, smoke test ve workflow).
- Vypiš shrnutí: PR #, repo, co nasazeno, výsledek smoke.

## Co NIKDY neautomatizovat
Rozřešení rebase konfliktu, deploy při červeném CI/monitoringu, jakékoli `git push --force`
(jen `--force-with-lease`), merge bez green CI, manuální deploy když projekt deployuje
přes Actions. Při pochybě zastav a zeptej se.
