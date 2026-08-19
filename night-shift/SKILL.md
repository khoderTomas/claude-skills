---
name: night-shift
description: Autonomní overnight smyčka nad agent-ready plánem v GitHub issues — jedno issue s checklistem, epic s odkazy na sub-issues, nebo seznam issues. Tenký supervisor spouští na každou jednotku worker subagenta s čerstvým kontextovým oknem, po green verify commit + odškrtnutí; failure policy s BLOCKED markery, context guard a řízený stop s push notifikací. Použij, když má owner dlouhou, jasně naplánovanou práci (desítky položek, např. stránky frontendu dle zadání) a chce ji nechat běžet bez dozoru, typicky přes noc. Nepoužívej na běžnou interaktivní feature práci ani na práci bez hotového plánu v issues.
argument-hint: <issue#> [<issue#>…] [--model opus|sonnet|fable] [--max N]
user-invocable: true
---

# /night-shift — autonomní noční směna nad issue plánem

Cíl: `/night-shift <issue#>` večer → ráno je hotové maximum jednotek plánu,
každá ověřená a commitnutá, blocked označené s důvodem, draft PR čeká na
review. Ty jsi **supervisor**: malý, stálý, levný. Veškerou implementaci
dělají **worker subagenti** — každý startuje s čerstvým kontextovým oknem,
takže session nepotřebuje /clear ani /handover uprostřed noci. /clear si model
zavolat neumí; tenhle skill ho nahrazuje tím, že hlavní okno nikdy nenaroste.

## Invarianty supervisora (drž celou noc)

1. **NIKDY nečteš zdrojáky, nespouštíš build/testy, needituješ kód.** Všechno
   deleguj workerům. Sám smíš jen levné stavové příkazy: `git log --oneline -n 3`,
   `git status -s`, `gh issue view/edit/comment`, `gh issue create`,
   `gh pr create --draft` — a Edit issue body přes scratchpad. I „rychlý pohled
   do souboru" je porušení; na to je retry worker.
2. **Tvůj kontext je palivo na celou noc.** Výstupy tool calls drž minimální
   (`--json` s výčtem fieldů, žádné diffy, žádné logy workerů). Bodies
   sub-issues NIKDY nedržíš v kontextu — worker si je čte sám, audit dělá
   audit subagent.
3. **Stav světa = řídicí issue + git, ne konverzace.** Po každé jednotce je
   issue aktuální → pád session nic neztratí, resume je stateless.
4. Po preflightu **žádné AskUserQuestion** — nikdo u stroje není. Nejasnost =
   BLOCKED marker, ne otázka do prázdna. (Jediná výjimka: permission gate,
   krok 0 preflightu — ten se ptá, dokud je owner u stroje.)
5. **V noci nesmí vyskočit ŽÁDNÝ permission prompt. Nikdy. Žádný** (reálná
   noc: session s ~20 prompty skončila jako nepoužitelná). Prompt za běhu =
   selhání setupu, ne něco k proklikání; jistotu dává jen bypass režim,
   vynucuje krok 0.

## Vstup

- `$1…$n` = číslo/čísla issue v aktuálním repu. Tři tvary, všechny vedou na
  jeden **řídicí checklist**:
  1. **Jedno issue s checklistem** → ono je řídicí; položky = jednotky práce.
  2. **Epic**: checklist řídicího issue odkazuje na sub-issues
     (`- [ ] #123 …`) → jednotka = celé sub-issue. Zadání workera = title +
     body sub-issue; případný checklist UVNITŘ sub-issue je DoD workera, ne
     další jednotky (granularita: 1 sub-issue = 1 worker = 1 čerstvý kontext).
  3. **Seznam** (`/night-shift 43 44 45`) → preflight vytvoří řídicí epic
     `gh issue create --title "night-shift <YYYY-MM-DD>"` s checklistem
     `- [ ] #43` atd. a **od té chvíle se celá session chová jako tvar 2
     s epic číslem** — každý wakeup prompt i resume používá `/night-shift
     <epic#>`, nikdy původní seznam (jinak by resume založil druhý epic).
  - Mix inline položek a `#N` odkazů v jednom checklistu je v pořádku — typ se
    určuje per položka. Issue v seznamu bez vlastního checklistu = 1 jednotka
    jako celek.
- `--model` = model workerů, default **opus** (nejnovější Opus). `--model
  sonnet` na jednoduché mechanické položky, `fable` na nejtěžší. Supervisor
  běží na session modelu.
- `--max N` = strop jednotek zpracovaných **touto session**, default 40
  (context guard; resume po stopu počítá od nuly).

Re-invokace s řídicím číslem = **resume** (i po wakeupu): preflight kroky 1–3
zkrať na kontrolu, smyčka naváže na první neodškrtnutou ne-BLOCKED jednotku.

## FÁZE 0 — Preflight (večer, owner je ještě u stroje)

Pořadí záměrné — nejdřív levné kontroly, pak drahé:

0. **Permission gate (tvrdá podmínka, PRVNÍ krok)**: směna smí běžet JEN
   v session s `bypassPermissions` — start `claude --settings
   ~/.claude/night-settings.json` (profil si vytvoř: bypass + deny na secrets
   a force push), případně selector ručně přepnutý na Bypass. Režim nejde
   zjistit introspekcí → `AskUserQuestion`: „Běží tahle session v bypass
   permissions (night profil / selector)?" — **Ano** → pokračuj; **Ne /
   nejistota** → 🛑 STOP s pokynem: restartuj `claude --settings
   ~/.claude/night-settings.json` a spusť `/night-shift <N>` znovu (resume je
   stateless, nic se neztratí). Auto režim NENÍ dost — classifier eskaluje
   prompty nezávisle na allowlistu. Gate platí pro každou **novou session**
   (první invokaci v konverzaci); wakeup resume v téže session ho přeskakuje —
   režim se sám nezmění.
1. **Řídicí checklist**: seznam čísel → založ epic (tvar 3 výše). Pak
   `gh issue view <N> --json title,body,url` řídicího a vyparsuj checklist
   (`- [ ]` / `- [x]`; u položek rozliš inline text vs `#N` odkaz). Jedno
   issue bez checklistu a bez seznamu → 🛑 STOP („není co smyčkovat").
2. **Agent-ready audit**: worker nezná konverzaci — každá jednotka musí být
   self-contained: jednoznačný scope + odkaz na specku/soubor/sekci NEBO plný
   popis (v položce, resp. v body sub-issue). Audit **deleguj na levného
   read-only subagenta** (máš-li vlastního collector agenta, použij ho; jinak
   general-purpose s levnějším modelem): dostane seznam jednotek (u `#N` si
   bodies načte sám přes `gh issue view`), vrátí jen verdikt per jednotka
   (ready/vágní + proč). Vágní („dodělat zbytek") vypiš; víc než ⅓ vágních →
   🛑 STOP („doplň zadání, spusť znovu"); jinak je v této noci přeskakuj
   a uveď v závěrečném souhrnu.
3. **Git**: clean tree (dirty → 🛑 STOP — cizí WIP se v noci nestashuje).
   Na main → `git checkout -b feat/issue-<N>-night`; na feature branchi →
   použij ho. Zjisti, zda existuje `origin` → určuje PUSH_LINE v šabloně.
4. **Verify baseline**: deleguj na subagenta (máš-li vlastní verify agent,
   použij ho; jinak general-purpose s pokynem vrátit jen selhání) na aktuální
   stav. Červené už teď → 🛑 STOP — noc nad rozbitým repem nemá smysl.
   Z výstupu ulož **VERIFY_CMDS** (přesné příkazy: lint, testy, smoke harness)
   do worker šablony.
   **Ostrá data**: předepisuje-li projektový CLAUDE.md ověření nad kopií
   produkčních dat (sonda / probe skript), pak: (a) kopie chybí nebo je
   zastaralá → refresh ještě v preflightu (owner je u stroje, SSH/VPN projde) —
   selhání → 🛑 STOP; (b) sondu spusť a její výstup ulož jako **BASELINE** do
   `.claude/night-notes.md`; (c) sondu přidej do VERIFY_CMDS každé jednotky,
   které se týká (typicky finanční výpočty, projekce, scheduler). Taková
   jednotka bez běhu sondy NENÍ done, i se zelenými testy — vady distribuce
   ostrých dat fixtures nechytí.
5. **Prostředí** (Windows): `powercfg /q SCHEME_CURRENT SUB_SLEEP STANDBYIDLE`
   — AC index ≠ 0 znamená, že stroj v noci usne → varuj a navrhni
   `powercfg /x standby-timeout-ac 0` (sám neměň). Na jiném OS zkontroluj
   ekvivalent (sleep/suspend settings). Permission prompty řeší krok 0
   (bypass gate) — allowlist je jen záloha, na noc se NEspoléhá.
6. **Předávací zápisník**: založ `.claude/night-notes.md` (append-only,
   worker→worker: sdílené komponenty, pasti, konvence zjištěné za běhu)
   a commitni ho, pokud neexistuje.
7. Vypiš **preflight summary** (počet jednotek / model workerů / branch /
   push ano-ne / baseline výsledek / varování) a **rovnou spusť první
   jednotku** — invokace /night-shift je souhlas, žádný confirm gate.

## FÁZE 1 — Smyčka

Opakuj, dokud existují neodškrtnuté ne-BLOCKED jednotky a nepřekročils `--max`:

1. **Vyber jednotku**: první neodškrtnutá shora bez ⛔ markeru a bez vágní flagu.
2. **Spusť workera**: `Agent` s `run_in_background: true`, `model` dle
   `--model`, `description: "<i>/<total> <slug>"`, prompt = šablona níže
   s doplněnými placeholdery (ÚKOL dle typu jednotky).
3. **Fallback heartbeat**: `ScheduleWakeup(delaySeconds: 1800, prompt:
   "/night-shift <řídicí#> <flagy>", reason: "night-shift heartbeat — <slug>")`.
   Pak **ukonči turn**. Primární buzení je notifikace o dokončení workera;
   wakeup je pojistka proti zaseknutí.
4. **Po notifikaci workera** zpracuj jeho strukturovaný výsledek:
   - `STATUS: DONE` → ověř realitu, ne tvrzení: `git log --oneline -n 3`
     obsahuje nový commit a VERIFY sekce je green? → **odškrtni jednotku**
     v řídicím (postup níže); u sub-issue navíc `gh issue comment <M>`
     („✅ night-shift: hotovo, commit <hash> — zavře PR"), issue **NEzavírej**
     (zavře ho merge přes Closes). Pak krok 1.
   - `BLOCKED`, DONE bez commitu, nebo nesmyslný výstup → failure policy.
5. **Po wakeupu bez notifikace** (worker nejspíš stále běží): zkontroluj
   `TaskOutput` posledního workera. Jeví aktivitu → jen nový
   `ScheduleWakeup(1800)` a konec turnu. Druhý wakeup téhož workera bez
   pokroku (≈60 min) → `TaskStop` a ber to jako 1 selhání jednotky.
6. **Checkpoint**: po každých 10 dokončených jednotkách `gh issue comment`
   na řídicí s mezisouhrnem (done/blocked/zbývá + poslední commit hash) —
   owner to v noci vidí z mobilu a případný pád session nic neztratí.

**Odškrtnutí jednotky** — přesně takhle, jinak rozbiješ body issue; přes Bash
tool, ne PowerShell (encoding):
```
gh issue view <řídicí#> --json body --jq .body > <scratchpad>/issue-<N>.md
```
→ `Edit` na tom souboru: přesná záměna `- [ ] <text>` → `- [x] <text>`
(u BLOCKED: append ` ⛔ BLOCKED: <důvod> (<YYYY-MM-DD>)`, checkbox nech prázdný)
→ `gh issue edit <řídicí#> --body-file <týž soubor>`.

## Worker prompt šablona

Doplň `<ÚKOL>`, `<BRANCH>`, `<ŘÍDICÍ#>`, `<VERIFY_CMDS>`, `<PUSH_LINE>`.
`<ÚKOL>` podle typu jednotky:
- inline položka: plný text položky včetně odkazů na specku;
- sub-issue: `celé issue #<M> — zadání si načti sám: gh issue view <M> --json
  title,body. Checklist uvnitř toho issue (existuje-li) je tvůj DoD — hotovo
  znamená splněno vše.` (body sub-issue do promptu NEvkládej — šetři supervisora)

```
Jsi worker noční směny — autonomní, jednorázový, bez přístupu k předchozí
konverzaci. Repo: aktuální cwd, branch <BRANCH>. Děláš JEDNU jednotku
nočního plánu (řídicí issue #<ŘÍDICÍ#>):

ÚKOL: <ÚKOL>

Nejdřív čti: projektový CLAUDE.md (máš v kontextu), `.claude/night-notes.md`
(poznámky předchozích workerů — sdílené komponenty a pasti) a specku z úkolu.
Pokud úkol odkazuje na neexistující soubor/sekci nebo chybí předpoklad
(např. API endpoint), NIC neimplementuj a vrať BLOCKED s důvodem.

POSTUP:
1. Implementuj jednotku kompletně (frontend vždy mobil + desktop dle specky).
2. Verify: <VERIFY_CMDS>. Červené → oprav a opakuj; neopravitelné → BLOCKED,
   červený stav nikdy necommituj. Obsahuje-li VERIFY_CMDS sondu nad prod kopií
   dat, porovnej výstup s BASELINE v night-notes a před/po čísla uveď ve VERIFY
   („beze změny projekce" je taky výsledek — uveď ho explicitně).
3. Green → commit s popisnou zprávou končící `(#<číslo issue jednotky>)`.
   <PUSH_LINE>
4. Vytvořil jsi sdílenou komponentu nebo narazil na past? Přidej 1 řádek do
   `.claude/night-notes.md` a commitni společně s prací.

ZÁKAZY: deploy, merge, jakýkoli force push, DB migrace, mazání branchí,
zavírání issues, práce nad rámec jednotky (další mají vlastní workery), nové
dependencies jen když jednotka jinak nejde — pak důvod do night-notes.

NÁVRAT (finální zpráva, max 15 řádků, nic jiného):
STATUS: DONE | BLOCKED
COMMIT: <hash> | none
FILES: <max 8 cest>
VERIFY: <příkaz → green/red, počty testů>
NOTES: <1-2 řádky: co má supervisor vědět / proč BLOCKED>
```

`<PUSH_LINE>`: s originem = `Pak git push origin <BRANCH> (nikdy force).`;
bez originu = `Nepushuj.`

## Failure policy

- **1. selhání jednotky** (BLOCKED / DONE bez commitu / TaskStop): spusť
  JEDNOHO retry workera — do promptu přidej „Předchozí pokus selhal: <důvod
  z výsledku>. Nejdřív ověř příčinu, pak teprve implementuj."
- **2. selhání téže jednotky**: ⛔ marker do řídicího checklistu; u sub-issue
  navíc `gh issue comment <M>` s důvodem → další jednotka.
- **3× BLOCKED po sobě** (různé jednotky): to není smůla, to je systémový
  problém (rozbitá závislost, špatný plán) → **řízený stop**.
- **Worker vrátil null** (API/limit chyba): `ScheduleWakeup(3600)` a zopakuj
  týž krok; 3 marné pokusy → řízený stop.

**Řízený stop** = (1) `gh issue comment` na řídicí se stavem (done/blocked/
zbývá, poslední commit, důvod stopu), (2) `ToolSearch
"select:PushNotification"` → `PushNotification` s jednovětým souhrnem,
(3) konec smyčky BEZ dalšího wakeupu. Nic nerevertuj — ráno se naváže resumem.

## Context guard

Řízený stop taky když: v kontextu se objevila systémová sumarizace konverzace,
NEBO jsi zpracoval `--max` jednotek. Poslední commit je bezpečný bod — resume
je levnější než degradovaný supervisor. Prevence = invarianty 1 a 2.

## FÁZE 2 — Ukončení (vše done, nebo zbývají jen BLOCKED/vágní)

1. Finální **verify** celé branche (opět deleguj na subagenta). Červené →
   řízený stop s poznámkou (žádné noční opravy naslepo).
2. Origin + ≥1 done → **draft PR**: `gh pr create --draft`, titulek dle
   řídicího issue, body = souhrn noci + `Closes #<M>` za KAŽDÉ dokončené
   sub-issue; `Closes #<řídicí>` jen při kompletním checklistu. PR už
   existuje → jen doplň Closes řádky do body.
3. `gh issue comment` na řídicí: závěrečný souhrn (X done / Y blocked
   s důvody / Z přeskočeno vágních, rozsah commitů, PR link).
4. `PushNotification`: „night-shift #<N>: X/Y done, draft PR #<M> čeká na
   review".
5. Totéž vypiš do chatu. Deploy a merge NEděláš — ráno review + merge
   (máš-li skill `/merge`, použij ho).

## Co NIKDY (platí pro tebe i workery)

Deploy, merge, `git push --force` (ani with-lease), mazání branchí, zavírání
issues (zavře je merge PR přes Closes), DB migrace proti reálné DB, změny mimo
repo (výjimka: `~/.claude/plans/` a scratchpad), gh operace mimo issue
view/edit/comment/create + pr create --draft. Při pochybě → BLOCKED, ne
kreativita.
