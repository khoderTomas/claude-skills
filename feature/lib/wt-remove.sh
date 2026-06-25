#!/usr/bin/env bash
# Safe worktree cleanup: bash ~/.claude/skills/feature/lib/wt-remove.sh <name>
# Runs via Git Bash on Windows. ASCII-only.
#
# CRITICAL: `git worktree remove` does a recursive delete that FOLLOWS the
# node_modules junction and would WIPE the MAIN repo's node_modules. This script
# removes the junction link FIRST (cmd /c rmdir = link only, target untouched),
# THEN removes the worktree, THEN drops the registry row. Always use this instead
# of a raw `git worktree remove` on a junction-provisioned worktree.
set -u

NAME="${1:-}"
if [ -z "$NAME" ]; then
  echo "usage: bash ~/.claude/skills/feature/lib/wt-remove.sh <worktree-name>" >&2
  exit 1
fi

# Resolve main repo root from anywhere (git-common-dir parent).
CWD="$PWD"
MAIN_ROOT=""
GCD="$(git -C "$CWD" rev-parse --git-common-dir 2>/dev/null || true)"
if [ -n "$GCD" ]; then
  case "$GCD" in
    [A-Za-z]:[\\/]*) GCD="$(cygpath -u "$GCD" 2>/dev/null || printf '%s' "$GCD")" ;;
  esac
  case "$GCD" in
    /*) ABS_GCD="$GCD" ;;
    *)  ABS_GCD="$CWD/$GCD" ;;
  esac
  MAIN_ROOT="$(cd "$ABS_GCD/.." 2>/dev/null && pwd || true)"
fi
[ -z "$MAIN_ROOT" ] && MAIN_ROOT="$CWD"

WT_PATH="$MAIN_ROOT/.claude/worktrees/$NAME"
NM="$WT_PATH/node_modules"
REGISTRY="$MAIN_ROOT/.claude/worktree-registry.md"

if [ ! -d "$WT_PATH" ]; then
  echo "worktree not found: $WT_PATH" >&2
  exit 1
fi

# Capture the worktree's branch BEFORE removal (for the cleanup hint).
BR="$(git -C "$WT_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

# 1) Remove node_modules junction link FIRST (link only; target safe).
if [ -e "$NM" ]; then
  WIN_NM="$(cygpath -w "$NM" 2>/dev/null || printf '%s' "$NM")"
  cmd //c rmdir "$WIN_NM" >/dev/null 2>&1 || true
  echo "removed node_modules junction"
fi

# 2) Now it is safe to remove the worktree.
git -C "$MAIN_ROOT" worktree remove "$WT_PATH" --force && echo "removed worktree $NAME"

# 3) Drop the registry row for this worktree (idempotent).
if [ -f "$REGISTRY" ]; then
  tmpf="$REGISTRY.tmp"
  grep -v "^| $NAME |" "$REGISTRY" > "$tmpf" 2>/dev/null && mv "$tmpf" "$REGISTRY"
  echo "removed registry row for $NAME"
fi

# Branch je `worktree-<name>` (EnterWorktree) nebo `feature/<name>` (manual) - smaz po merge.
if [ -n "$BR" ] && [ "$BR" != "HEAD" ]; then
  echo "done. branch '$BR' zustava - smaz po merge: git branch -d $BR"
else
  echo "done. branch zustava - smaz po merge: git branch -d <branch>"
fi
exit 0
