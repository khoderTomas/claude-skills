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

# 4. Green CI na rebasnuté hlavě
step "Čekám na CI (gh pr checks --watch)…"
gh pr checks "$PR" --repo "$REPO" --watch --fail-fast || fail "CI červené — STOP, nemerguju." 3

# 5. Squash merge + smazat remote branch
step "Squash merge + delete branch"
gh pr merge "$PR" --repo "$REPO" --squash --delete-branch

echo ""
echo "✓ FÁZE A: PR #$PR zmergován do main (repo $REPO, branch $BRANCH)."
