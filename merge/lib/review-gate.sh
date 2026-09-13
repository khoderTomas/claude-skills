#!/usr/bin/env bash
# ~/.claude/skills/merge/lib/review-gate.sh
# Krok 0 globálního /merge: klasifikuje složitost PR (diff feature branche vs
# origin/main) a rozhodne, jestli před merge pustit Codex review.
#
# Výstup (stdout, řádky KEY=VALUE, exit vždy 0):
#   TIER=skip|review|full   skip = drobnost, review = /codex:review,
#                           full = /codex:review + /codex:adversarial-review
#   REASON=<důvod>  jen u skip bez klasifikace: codex-plugin-missing |
#                   gate-disabled-by-env (MERGE_REVIEW_GATE=off)
#   FILES=<n>   počet změněných kódových souborů (bez docs/lock)
#   LINES=<n>   přidané+smazané řádky v kódových souborech
#   RISKY=<seznam>  změněné soubory na rizikových cestách (migrace, auth, platby,
#                   fakturace, deploy, workflows, cron, webhook, secrets);
#                   testy se do RISKY nepočítají
#
# Prahy (heuristika, ladit tady, ne ve SKILL.md):
#   skip : FILES<=3 && LINES<=60 && RISKY prázdné
#   full : LINES>=300 || FILES>=10 || RISKY neprázdné
#   review: vše ostatní
set -euo pipefail

# Volitelnost: bez nainstalovaného pluginu `codex` (Claude Code plugin od OpenAI)
# gate nic nedělá — vrátí TIER=skip s důvodem, /merge pokračuje rovnou merge.
# Vypnout gate natvrdo: MERGE_REVIEW_GATE=off (env) — stejný výsledek.
COMPANION=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1 || true)
if [ "${MERGE_REVIEW_GATE:-on}" = "off" ]; then
  echo "TIER=skip"; echo "REASON=gate-disabled-by-env"; exit 0
fi
if [ -z "$COMPANION" ] || [ ! -f "$COMPANION" ]; then
  echo "TIER=skip"; echo "REASON=codex-plugin-missing"; exit 0
fi

if [ -n "${1:-}" ]; then
  BASE="$1"
else
  # default branch remotu (main/master), fallback origin/main
  DEF=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
  BASE="$DEF"
fi
git fetch -q origin "${BASE#origin/}" 2>/dev/null || true

# soubory, které do složitosti nepočítáme (docs, locky, generované)
IGNORE_RE='(\.md$|^docs/|^\.claude/|package-lock\.json$|pnpm-lock\.yaml$|yarn\.lock$|composer\.lock$|\.snap$|\.min\.(js|css)$)'
TEST_RE='(^|/)(tests?|__tests__|spec|e2e|fixtures)/|\.(test|spec)\.'
RISKY_RE='(migrat|schema|auth|login|session|permission|role|payment|platb|invoice|faktur|deploy|\.github/workflows|Dockerfile|cron|webhook|secret|\.env|billing|tenant)'

NUMSTAT=$(git diff --numstat "$BASE"...HEAD)
FILES=0; LINES=0; RISKY=""
while IFS=$'\t' read -r add del path; do
  [ -z "${path:-}" ] && continue
  if ! echo "$path" | grep -Eq "$TEST_RE" && echo "$path" | grep -Eiq "$RISKY_RE"; then
    RISKY="${RISKY:+$RISKY,}$path"
  fi
  echo "$path" | grep -Eq "$IGNORE_RE" && continue
  FILES=$((FILES+1))
  [ "$add" = "-" ] && add=0; [ "$del" = "-" ] && del=0   # binární
  LINES=$((LINES+add+del))
done <<< "$NUMSTAT"

if [ -n "$RISKY" ] || [ "$LINES" -ge 300 ] || [ "$FILES" -ge 10 ]; then
  TIER=full
elif [ "$FILES" -le 3 ] && [ "$LINES" -le 60 ]; then
  TIER=skip
else
  TIER=review
fi

echo "TIER=$TIER"
echo "FILES=$FILES"
echo "LINES=$LINES"
echo "RISKY=$RISKY"
