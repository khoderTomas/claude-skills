#!/usr/bin/env bash
# Safe worktree cleanup: bash ~/.claude/skills/feature/lib/wt-remove.sh <name>
# Runs via Git Bash on Windows. ASCII-only.
#
# CRITICAL: `git worktree remove` does a recursive delete that FOLLOWS the
# node_modules junction and would WIPE the MAIN repo's node_modules. This script
# removes the junction link FIRST (cmd /c rmdir = link only, target untouched),
# THEN removes the worktree, THEN drops the registry row. Always use this instead
# of a raw `git worktree remove` on a junction-provisioned worktree.
#
# The same discipline extends to two other leftovers, WITHOUT reordering
# the guard above:
#   (0) stop processes owned by THIS worktree (a live `next dev` keeps the
#       directory locked -> "Directory not empty"). Targeting is per-worktree
#       (cmdline path + dev PORT), never a blanket node/next kill - sibling
#       worktrees run their own dev servers.
#   (2) unlink every REMAINING reparse point under the worktree before deleting
#       anything recursively. Next.js copies junctions into .next/node_modules and
#       .next/dev/node_modules that point into the MAIN node_modules, so a naive
#       `rm -rf .next` is the very footgun this script exists to prevent.
#   (3) only then delete .next (can be GBs) as plain directories.
#
# Steps (0) and (2) need the PowerShell helpers in _shared/ next to this file;
# without them those steps are skipped (the junction guard still applies).
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
# PowerShell helpers live next to this file (works from main checkout or any worktree).
PSDIR="$(cd "$(dirname "$0")/_shared" 2>/dev/null && pwd || true)"

if [ ! -d "$WT_PATH" ]; then
  echo "worktree not found: $WT_PATH" >&2
  exit 1
fi

# Capture the worktree's branch BEFORE removal (for the cleanup hint).
BR="$(git -C "$WT_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

PS_EXE="$(command -v powershell 2>/dev/null || command -v powershell.exe 2>/dev/null || true)"
WIN_WT="$(cygpath -w "$WT_PATH" 2>/dev/null || printf '%s' "$WT_PATH")"

# 0) Stop processes that belong to THIS worktree (dev server + its workers).
#    Without this the directory stays locked and every delete below fails.
if [ -n "$PS_EXE" ] && [ -n "$PSDIR" ] && [ -f "$PSDIR/wt-find-processes.ps1" ]; then
  WT_PORT="$(grep '^PORT=' "$WT_PATH/.env.local" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '\r')"
  case "$WT_PORT" in
    ''|*[!0-9]*) WT_PORT=0 ;;
  esac
  PROCS="$("$PS_EXE" -NoProfile -NonInteractive -ExecutionPolicy Bypass \
    -File "$(cygpath -w "$PSDIR/wt-find-processes.ps1" 2>/dev/null || printf '%s' "$PSDIR/wt-find-processes.ps1")" \
    -Root "$WIN_WT" -Port "$WT_PORT" 2>/dev/null || true)"
  if [ -n "$PROCS" ]; then
    printf '%s\n' "$PROCS" | tr -d '\r' | while IFS="$(printf '\t')" read -r P PNAME PREASON; do
      [ -z "$P" ] && continue
      taskkill //PID "$P" //T //F >/dev/null 2>&1 || true
      echo "killed pid $P ($PNAME, $PREASON)"
    done
  else
    echo "no worktree processes running"
  fi
fi

# 1) Remove node_modules junction link FIRST (link only; target safe).
if [ -e "$NM" ]; then
  WIN_NM="$(cygpath -w "$NM" 2>/dev/null || printf '%s' "$NM")"
  cmd //c rmdir "$WIN_NM" >/dev/null 2>&1 || true
  echo "removed node_modules junction"
fi

# 2) Unlink any REMAINING reparse point (e.g. .next/node_modules/* -> main repo)
#    BEFORE anything is deleted recursively. The scan never descends into a link.
if [ -n "$PS_EXE" ] && [ -n "$PSDIR" ] && [ -f "$PSDIR/wt-find-reparse-points.ps1" ]; then
  LINKS="$("$PS_EXE" -NoProfile -NonInteractive -ExecutionPolicy Bypass \
    -File "$(cygpath -w "$PSDIR/wt-find-reparse-points.ps1" 2>/dev/null || printf '%s' "$PSDIR/wt-find-reparse-points.ps1")" \
    -Root "$WIN_WT" 2>/dev/null || true)"
  LINK_COUNT=0
  if [ -n "$LINKS" ]; then
    while IFS= read -r LINK; do
      LINK="$(printf '%s' "$LINK" | tr -d '\r')"
      [ -z "$LINK" ] && continue
      cmd //c rmdir "$LINK" >/dev/null 2>&1 || true
      LINK_COUNT=$((LINK_COUNT + 1))
    done <<EOF
$LINKS
EOF
  fi
  [ "$LINK_COUNT" -gt 0 ] && echo "unlinked $LINK_COUNT reparse point(s) (link only, targets safe)"
fi

# 3) Drop the .next build output (can be GBs). Safe now: no reparse point is left,
#    so this recursion cannot reach outside the worktree.
if [ -d "$WT_PATH/.next" ]; then
  rm -rf "$WT_PATH/.next" 2>/dev/null || true
  if [ -d "$WT_PATH/.next" ]; then
    echo "warning: .next could not be fully removed (locked handle?)" >&2
  else
    echo "removed .next build output"
  fi
fi

# 4) Now it is safe to remove the worktree.
if git -C "$MAIN_ROOT" worktree remove "$WT_PATH" --force 2>/dev/null; then
  echo "removed worktree $NAME"
elif sleep 2 && git -C "$MAIN_ROOT" worktree remove "$WT_PATH" --force; then
  echo "removed worktree $NAME (second attempt)"
else
  echo "git worktree remove failed - a handle is still open on $WT_PATH" >&2
  echo "check what holds it, then re-run: bash ~/.claude/skills/feature/lib/wt-remove.sh $NAME" >&2
  exit 1
fi

# 5) Drop the registry row for this worktree (idempotent).
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
