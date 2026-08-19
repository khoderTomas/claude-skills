#!/usr/bin/env bash
# ~/.claude/skills/merge/lib/pr-merge.sh <PR-number>
# Univerzální FÁZE A globálního /merge skillu: race-safe sync + squash merge.
# Repo se autodetekuje (gh repo view) — funguje v libovolném repu/worktree.
#
# Spouštěj na feature branchi daného PR (ať už v main checkoutu, nebo ve worktree).
# NEdeployuje — deploy řeší projektový tail (skill, krok 3).
#
# Proč: GitHub merge queue / "require up-to-date" jsou na free planu + privátním
# repu zamčené (403). Race "main se pohnul" proto: rebase na origin/main → green
# CI → hned squash merge. Solo dev + serializace merge → prakticky eliminováno.
#
# STOP (nikdy neforcuje): rebase konflikt (exit 2), červené CI (exit 3).
set -euo pipefail

PR="${1:?Usage: pr-merge.sh <PR-number>}"
step() { echo ""; echo "==> $*"; }
fail() { echo "✗ $*" >&2; exit "${2:-1}"; }

command -v gh >/dev/null || fail "gh CLI není v PATH" 1
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner) || fail "Nejsem v git repu s gh remote." 1

# 0. Čistý strom
[ -z "$(git status --porcelain)" ] || fail "Dirty tree — commitni/stashni před merge." 1

# 1. Branch z PR + ověř, že na ní reálně jsme
BRANCH=$(gh pr view "$PR" --repo "$REPO" --json headRefName -q .headRefName)
CUR=$(git rev-parse --abbrev-ref HEAD)
[ "$CUR" = "$BRANCH" ] || fail "Jsi na '$CUR', ale PR #$PR je '$BRANCH'. Přepni se na branch toho PR." 1
step "$REPO  PR #$PR  branch=$BRANCH  cwd=$(pwd)"

# 2. Rebase na nejnovější origin/main — STOP na konfliktu
step "Fetch + rebase na origin/main"
git fetch origin main
if ! git rebase origin/main; then
  git rebase --abort
  fail "REBASE KONFLIKT — vyřeš ručně (git rebase origin/main → resolve → --continue), pak /merge znovu. Rebase abortnut." 2
fi

# 3. Push rebasnuté hlavy (force-with-lease = bezpečné)
step "Push --force-with-lease"
git push --force-with-lease origin "$BRANCH"

# 4. Green CI na rebasnuté hlavě — vázané na PŘESNÝ HEAD SHA.
#    Pozor: `gh pr checks --watch` umí těsně po force-pushi vrátit STALE výsledky
#    předchozího SHA (GitHub nový běh ještě neregistroval) → merge by proběhl bez
#    potvrzeného CI přesně toho kódu (reálný incident po rebase konfliktu).
#    Proto vlastní poll na check-runs commitu: čeká, až pro HEAD SHA existuje
#    aspoň jeden check-run a žádný není pending; červený → STOP.
HEAD_SHA=$(git rev-parse HEAD)

# Docs-only PR? GitHub `paths-ignore` v mnoha repech přeskočí celý CI workflow pro
# čistě dokumentační/meta diff → žádný check-run se NIKDY nevytvoří a klasické čekání
# by zbytečně vyčerpalo celý 15min timeout a spadlo exitem 3 (reálný incident:
# docs-only PR, CI přeskočeno přes paths-ignore, skript timeoutnul). Když všechny
# změněné soubory vypadají docs/meta, zkrať čekání na krátké grace okno:
# neobjeví-li se v něm check-run = záměrný skip → merguj. Objeví-li se (repo, které CI
# na docs spouští), přepni zpět na plnou smyčku — gate se tím NEobejde.
CHANGED=$(git diff --name-only origin/main...HEAD)
# Prázdný seznam = fail-CLOSED. Původně se prázdný `CHANGED` protočil smyčkou bez
# jediné iterace a nechal DOCS_ONLY=1, takže PR, u kterého diff nešel spočítat
# (odlišná merge-base, shallow clone, commity už v mainu), dostal 60s grace a
# mergnul se bez potvrzeného CI. Neznámý diff musí čekat plný strop — grace okno
# je výjimka pro doloženě docs-only změnu, ne default.
if [ -z "$CHANGED" ]; then
  DOCS_ONLY=0
  echo "  Prázdný diff proti origin/main — grace okno se NEuplatní (čekám na CI plně)."
else
  DOCS_ONLY=1
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
      *.md|docs/*|.claude/*|LICENSE|.gitignore|.gitattributes) ;;
      *) DOCS_ONLY=0; break ;;
    esac
  done <<<"$CHANGED"
fi

if [ "$DOCS_ONLY" = 1 ]; then
  DEADLINE=$(( $(date +%s) + 60 ))    # grace: check-run naskočí do sekund, nebo nikdy (paths-ignore)
  step "Docs-only diff — grace 60 s na CI (paths-ignore ho nejspíš přeskočí)"
else
  DEADLINE=$(( $(date +%s) + 900 ))   # 15 min strop
  step "Čekám na CI pro ${HEAD_SHA:0:10}…"
fi
# Doložil aspoň jeden ÚSPĚŠNÝ dotaz na check-runs, že tam nic není?
# Bez tohohle by síťový blip / rate-limit po celé grace okno vypadal stejně jako
# „CI záměrně přeskočeno" → merge bez CI kvůli chybě, o které nikdo neví.
API_OK=0
while :; do
  # [celkem, pending, červené] jedním callem; conclusion success/skipped/neutral = OK.
  COUNTS=$(gh api "repos/$REPO/commits/$HEAD_SHA/check-runs" --jq \
    '[(.check_runs|length),
      ([.check_runs[]|select(.status!="completed")]|length),
      ([.check_runs[]|select(.status=="completed" and ((.conclusion // "x") as $c | ($c=="success" or $c=="skipped" or $c=="neutral") | not))]|length)
     ] | @tsv' 2>/dev/null) || COUNTS=""
  if [ -n "$COUNTS" ]; then
    API_OK=1
    read -r N PENDING BAD <<<"$COUNTS"
    if [ "${BAD:-0}" -gt 0 ]; then
      gh pr checks "$PR" --repo "$REPO" || true
      fail "CI červené na $HEAD_SHA — STOP, nemerguju." 3
    fi
    if [ "${N:-0}" -gt 0 ] && [ "${PENDING:-0}" -eq 0 ]; then
      gh pr checks "$PR" --repo "$REPO" || true   # výpis pro člověka
      break
    fi
    # docs-only, ale check-run se objevil → repo CI běží i na docs; přepni na plný strop.
    if [ "$DOCS_ONLY" = 1 ] && [ "${N:-0}" -gt 0 ]; then
      DOCS_ONLY=0
      DEADLINE=$(( $(date +%s) + 900 ))
      step "CI se pro docs diff přesto spustilo — čekám na dokončení (${HEAD_SHA:0:10})…"
    fi
  fi
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    if [ "$DOCS_ONLY" = 1 ]; then
      [ "$API_OK" = 1 ] || fail "Docs-only diff, ale API na check-runs ani jednou neodpovědělo (gh auth / rate-limit / síť?) — neumím odlišit „CI přeskočeno" od „nevím". STOP, nemerguju." 3
      echo "  Žádný CI check-run pro docs-only diff (paths-ignore skip) — merguju bez čekání."
      break
    fi
    fail "CI pro $HEAD_SHA nedoběhlo do 15 min (runner spí?) — STOP, nemerguju." 3
  fi
  sleep 15
done

# 4b. Uzavírací záměr psaný česky
#
# GitHub zavírá issues jen na anglické keywordy (closes/fixes/resolves). České
# „Uzavírá #42" vypadá v PR jako uzávěr, ale GitHub ho ignoruje — issue po mergi
# i po nasazení tiše zůstane otevřené a nikdo si toho nevšimne, dokud ho o měsíc
# později někdo nenajde v backlogu (reálný incident).
#
# `closingIssuesReferences` je autoritativní odpověď na „co GitHub zavře sám";
# doplněk k němu je regex na český záměr. Rozděleno na dvě síly:
#   silné  = jednoznačný uzávěr → skript issue zavře sám po mergi,
#   slabé  = „řeší / opravuje" může být i částečné → jen upozorní, nezavírá.
#
# POZOR na regex: grep běží v C.UTF-8, kde bracket výraz ani `.` nematchují přes
# multibyte znak — `Uzav[íi]r[áa]` tiše nenajde nic. Proto celé literály.
STRONG_RE='(Uzavírá|uzavírá|Uzavírám|uzavírám|Uzavře|uzavře|Uzavřeno|uzavřeno|Zavírá|zavírá|Zavře|zavře|Zavřeno|zavřeno)[[:space:]]+(issue[[:space:]]+)?#[0-9]+'
WEAK_RE='(Řeší|řeší|Vyřeší|vyřeší|Vyřešeno|vyřešeno|Opravuje|opravuje|Implementuje|implementuje|Dodáno|dodáno)[[:space:]]+(issue[[:space:]]+)?#[0-9]+'

BODY=$(gh pr view "$PR" --repo "$REPO" --json body -q .body 2>/dev/null || echo "")
AUTO=$(gh pr view "$PR" --repo "$REPO" --json closingIssuesReferences \
        -q '[.closingIssuesReferences[].number]|join(" ")' 2>/dev/null || echo "")

nums() { printf '%s' "$BODY" | grep -oE "$1" | grep -oE '[0-9]+$' | sort -un || true; }
covered() { case " $AUTO " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

ORPHANS=""
for n in $(nums "$STRONG_RE"); do covered "$n" || ORPHANS="$ORPHANS $n"; done
WEAK_ORPHANS=""
for n in $(nums "$WEAK_RE"); do covered "$n" || WEAK_ORPHANS="$WEAK_ORPHANS $n"; done

# Pozn.: všechno níž schválně přes `if`, ne `[ … ] && echo`. Pod `set -e` vrací
# takový list status 1 a jako poslední příkaz skriptu by z úspěšného merge udělal
# exit 1 — skill by to přečetl jako selhání fáze A.
list() { for a in $1; do printf ' #%s' "$a"; done; }

if [ -n "$ORPHANS$WEAK_ORPHANS" ]; then
  step "Uzavírací záměr bez GitHub keywordu"
  if [ -n "$AUTO" ]; then         echo "  GitHub zavře sám:$(list "$AUTO")"; fi
  if [ -n "$ORPHANS" ]; then      echo "  Zavřu po mergi:$(list "$ORPHANS")"; fi
  if [ -n "$WEAK_ORPHANS" ]; then echo "  Jen upozornění (může být částečné, NEzavírám):$(list "$WEAK_ORPHANS")"; fi
fi

# 5. Squash merge + smazat remote branch
step "Squash merge + delete branch"
gh pr merge "$PR" --repo "$REPO" --squash --delete-branch

# 5b. Doclosování — až po mergi, ať se nezavře issue u PR, který neprošel.
#     Zavírá se jen to, co je pořád OPEN: mezitím ho mohl zavřít commit message.
for n in $ORPHANS; do
  STATE=$(gh issue view "$n" --repo "$REPO" --json state -q .state 2>/dev/null || echo "")
  case "$STATE" in
    OPEN)
      if gh issue close "$n" --repo "$REPO" \
           --comment "Dodáno v PR #$PR (squash merge). Zavřeno automaticky skriptem /merge — PR nesl uzavírací záměr česky, na což GitHub keyword nereaguje." >/dev/null 2>&1; then
        echo "  ✓ #$n zavřeno (PR text byl česky, GitHub ho sám nezavřel)"
      else
        echo "  ! #$n se zavřít nepodařilo — zavři ručně: gh issue close $n --repo $REPO" >&2
      fi
      ;;
    CLOSED) echo "  · #$n už zavřené" ;;
    *)      echo "  ! #$n: stav se nepodařilo zjistit — zkontroluj ručně" >&2 ;;
  esac
done

echo ""
echo "✓ FÁZE A: PR #$PR zmergován do main (repo $REPO, branch $BRANCH)."
if [ -n "$WEAK_ORPHANS" ]; then
  echo "  Zkontroluj ručně, jestli je zavřít:$(list "$WEAK_ORPHANS")"
fi
exit 0
