---
name: merge
description: Race-safe merge → deploy jednoho PR v libovolném projektu. Rebasne feature branch na nejnovější origin/main, počká na green CI, squash-merguje a smaže branch, pak spustí projektový deploy tail podle konvence — s jasnými STOP body (rebase konflikt, červené CI, preflight fail). Použij když je feature hotová a chceš ji bezpečně domergovat a nasadit. Náhrada za GitHub merge queue, který je na free planu + privátním repu zamčený (403).
argument-hint: '[PR-number] [--review|--no-review]'
user-invocable: true
allowed-tools: Bash(bash ~/.claude/skills/merge/lib/pr-merge.sh:*), Bash(bash ~/.claude/skills/merge/lib/review-gate.sh:*), Agent, Bash(bash scripts/post-merge-deploy.sh:*), Bash(gh pr view:*), Bash(gh pr checks:*), Bash(gh repo view:*), Bash(git rev-parse:*), Bash(git status:*), Bash(git checkout:*), Bash(git pull:*), Bash(git branch:*), Bash(git diff:*), Bash(git fetch:*), ExitWorktree
---

# /merge — race-safe merge → deploy (globální)

Cíl: `/merge <PR#>` z branche, kde jsi feature dodělal → bezpečně rebase na main,
green CI, squash merge, pak projektový deploy podle konvence. Funguje ve všech
repech nastavených na squash-only + delete-branch. Univerzální merge část je
deterministický skript; tenhle skill je orchestrátor, který umí **zastavit** a předat
ownerovi, řeší
přechod worktree↔main (nástroj `ExitWorktree`) a vybírá deploy tail dle projektu.

Proč skill místo nativního řešení: merge queue / "require up-to-date" jsou na
privátních repech na free planu zamčené (403).

## Autorizace (čti první)
Invokace `/merge` **JE** explicitní, trvalý souhlas s **merge i následným deployem** —
deploy je očekávaná, neoddělitelná část toku, ne samostatné rozhodnutí. **NEvkládej
potvrzovací gate** („chceš deployovat?", „opravdu na produkci?", „pustit nasazení?")
ani `AskUserQuestion` o povolení nasadit. Jeď fázemi A → deploy bez ptaní. Jediné
zastávky jsou **hard-stopy správnosti** (Codex review nálezy, rebase konflikt, červené CI, preflight fail) —
ty jsou o korektnosti, ne o povolení. Jediný případ dotazu: aktuální větev **nemá
žádnou** otevřenou PR (např. stojíš na `main`) → zeptej se „kterou PR". Jinak NIKDY
neptej — ani na deploy, ani „kterou PR", ani nenabízej zadat číslo.

## Vstup
- **Holé `/merge` je norma — mergni PR AKTUÁLNÍ větve** (`gh pr view --json number`).
  Být na feature větvi = právě jedna její PR = featura, na které děláme. Číslo
  **NEvyžaduj ani nenabízej** (žádné „/merge <num>" rady) — je zbytečné. Rovnou jeď.
- `$1` (volitelné) = jen když owner chce mergnout JINOU PR, než je větev, na které stojí.
- `--review` / `--no-review` (volitelné) = přebijí automatické rozhodnutí kroku 0
  (vynutit Codex review u drobnosti / přeskočit u velké PR, typicky re-run po opravě nálezů).
- Jediný dotaz: aktuální větev nemá žádnou otevřenou PR → „kterou PR". Jinak se neptej.

## Předpoklad
Jsi **na feature branchi toho PR** (v main checkoutu nebo ve worktree), strom čistý,
PR existuje. Když ne → nejdřív commit + `gh pr create`.

## Krok 0 — Codex review gate (volitelný, podle složitosti PR)
Před merge projde větší práce code review Codexem; drobnost (pár řádků) ne.
**Volitelné:** vyžaduje plugin `codex` (OpenAI, Claude Code marketplace) a agenta
`codex-reviewer` v `~/.claude/agents/`. Bez pluginu gate vrátí `TIER=skip` s
`REASON=codex-plugin-missing` a ty pokračuješ rovnou FÁZÍ A (není to stop, jen to
zmiň v souhrnu). Vypnout natvrdo: env `MERGE_REVIEW_GATE=off`.

O tom, co je „drobnost", rozhoduje deterministický skript, ne dojem:
```
bash ~/.claude/skills/merge/lib/review-gate.sh
```
Vrátí `TIER=skip|review|full` + `FILES`, `LINES`, `RISKY` (diff branche vs default
branch remotu, docs/locky/testy se nepočítají; prahy a rizikové cesty jsou v hlavičce
skriptu). `TIER=skip` s `REASON=` = gate neběžel (plugin chybí / vypnuto env).

| TIER | kdy | co spustit |
|---|---|---|
| `skip` | ≤3 souborů, ≤60 řádků, nic rizikového | nic — rovnou FÁZE A |
| `review` | vše mezi | `/codex:review` |
| `full` | ≥300 řádků, ≥10 souborů, nebo rizikové cesty (migrace, auth, platby, fakturace, deploy, workflows, secrets) | `/codex:review` **a** `/codex:adversarial-review` |

`--review` vynutí `review`, `--no-review` vynutí `skip` (řekni to v souhrnu).

**Spuštění:** commandy `/codex:*` mají `disable-model-invocation`, proto je NEvoláš
přes Skill. Review dělá subagent **`codex-reviewer`** (Agent tool), který spustí
companion skript ve foregroundu a vrátí výstup Codexu doslovně:
- `review` → jeden Agent call s `MODE=review`;
- `full` → dva Agent cally v jedné zprávě (`MODE=review`, `MODE=adversarial-review`
  s `FOCUS=` = jednovětý popis PR z jejího title). Když druhý spadne na „still
  running", pusť ho znovu až po prvním.

**Vyhodnocení výstupu** (ty, ne agent):
- 🛑 **STOP – nálezy:** adversarial `Verdict: needs-attention`, nebo native review
  hlásí konkrétní defekt (P0/P1, bug, regression, security). Vypiš nálezy doslovně,
  seřazené dle závažnosti, s cestami a řádky. **Nic neopravuj** — owner rozhodne:
  opraví → push → `/merge` znovu (gate proběhne znovu), nebo vědomě `/merge --no-review`.
- 🛑 **STOP – Codex nedostupný:** výstup začíná `CODEX-UNAVAILABLE` (auth, setup,
  pád skriptu). Předej hlášku, odkaž na `/codex:setup`; owner může pokračovat
  `--no-review`. Nikdy nenahrazuj Codex review vlastním.
- Jinak (bez nálezů / jen style) → pokračuj FÁZÍ A. Tier a výsledek review uveď
  v závěrečném souhrnu (krok 4).

Review běží nad nerebasnutou větví; rebase dělá až FÁZE A. Když FÁZE A skončí
konfliktem a owner ho vyřeší, re-run `/merge` gate zopakuje — to je záměr, konflikt
mění kód.

## Krok 1 — FÁZE A: sync + merge (univerzální)
Spusť (repo si skript autodetekuje):
```
bash ~/.claude/skills/merge/lib/pr-merge.sh <PR#>
```
Dělá: čistota → rebase na `origin/main` → push `--force-with-lease` →
`gh pr checks --watch` (ci-box) → `gh pr merge --squash --delete-branch` →
doclosování issues, které GitHub nezavře sám.

**Doclosování** (od 2026-08-18): GitHub reaguje jen na anglické keywordy
(`closes/fixes/resolves`). Česky psané „Uzavírá #913" vypadá jako uzávěr, ale
GitHub ho ignoruje a issue po mergi i po nasazení tiše zůstane otevřené — přesně
to potkalo PR #920 / issue #913 v Jipos Fakturaci. Skript proto porovná
`closingIssuesReferences` (co GitHub zavře sám) s českým uzavíracím záměrem
v textu PR a rozdíl dořeší:

- **jednoznačný uzávěr** („Uzavírá / Zavře / Uzavřeno" + `#N`) → zavře sám po
  mergi, s komentářem proč; zavírá jen to, co je v tu chvíli `OPEN`, takže
  zastaralá zmínka na už zavřené issue nic neudělá;
- **slabší formulace** („Řeší / Opravuje / Implementuje" + `#N`) → jen vypíše
  jako upozornění, protože můžou znamenat i částečné řešení.

Nic z toho merge neblokuje a všechno se vypisuje — když skript něco zavřel, je
to v jeho výstupu a `gh issue reopen` to vrátí.

🛑 **STOP, když skript skončí non-zero:**
- exit 2 = **rebase konflikt** → vyřeš ručně (`git rebase origin/main` → resolve → `--continue`), pak `/merge <PR#>` znovu. NIKDY neřeš konflikt na slepo.
- exit 3 = **červené CI** → oprav příčinu, push, spusť znovu. Nedeployuj.
- exit 4 = **stacked PR** — na branchi tohohle PR míří jako base další otevřená PR;
  smazání branche po squashi by ji nenávratně zavřelo (GitHub nedovolí ani reopen,
  jen novou PR). Skript merge NEPROVEDL. Oprava: `gh pr edit <navazující#> --base main`
  pro každé vypsané číslo, pak `/merge <PR#>` znovu.
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

1. **Existuje `scripts/post-merge-deploy.sh`** (např. reporting-saas) → projekt vlastní
   deploy + úklid, spusť:
   ```
   bash scripts/post-merge-deploy.sh <BRANCH-z-fáze-A>
   ```
   🛑 STOP na non-zero (typicky preflight fail) — předej ownerovi.

2. **Jinak existuje `.github/workflows/deploy.yml`** (např. Jipos) → deploy řeší
   GitHub Actions automaticky po merge. Nasazovat ručně NEsmíš. Místo toho:
   - smaž lokální branch: `git branch -d <BRANCH>` (remote už smazán merge);
   - připomeň ownerovi sledovat run Actions / smoke test workflow.

3. **Jinak** → deploy je manuální/neznámý. Zastav, řekni ownerovi že merge proběhl,
   ale deploy si musí spustit sám (a navrhni doplnit `scripts/post-merge-deploy.sh`).

## Krok 4 — smoke + watch (ty, ne skript)
- **Smoke-check proběhne vždy** — nežádej ownera o reprodukci. Deleguj ho:
  - existuje-li skriptovaný harness → subagent **`verify-run`** (`test:smoke`);
  - nekryje-li harness dotčenou routu → subagent **`pw-driver`** na 1–2 klíčové
    routy (dotčená feature + home).

  Oba vrací jen nálezy, ne snapshoty. Chyby ber z konzole/capture, **ne z dialogů** —
  dialog se zavře dřív, než ho stihneš přečíst.
- Připomeň **post-deploy watch** dle projektu (reporting-saas: 24h Sentry; Jipos: 14-bod smoke v Actions).
- Vypiš shrnutí: PR #, repo, review tier + výsledek (krok 0), co nasazeno, výsledek smoke.

## Co NIKDY neautomatizovat
Rozřešení rebase konfliktu, opravy nálezů z Codex review, deploy při červeném CI/Sentry, jakékoli `git push --force`
(jen `--force-with-lease`), merge bez green CI, manuální deploy když projekt deployuje
přes Actions. Při pochybě zastav a zeptej se.
