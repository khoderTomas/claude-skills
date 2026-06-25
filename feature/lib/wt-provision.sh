#!/usr/bin/env bash
# In-session worktree provisioning for the EnterWorktree path (VS Code panel or CLI).
# Usage (run from INSIDE the worktree, after EnterWorktree):
#   bash ~/.claude/skills/feature/lib/wt-provision.sh "<one-line description>"
#
# EnterWorktree honors .worktreeinclude (copies .env.local + settings.local.json) but does
# NOT run the SessionStart hook, so node_modules junction + dev PORT must be created here.
# Runs via Git Bash on Windows. ASCII-only. Idempotent. Exit 0 unless not in a worktree.
set -u

DESC="${1:-}"
CWD="$PWD"

case "$CWD" in
  *"/.claude/worktrees/"*) : ;;
  *) echo "wt-provision: not inside a worktree (.claude/worktrees/...). Run after EnterWorktree." >&2
     exit 1 ;;
esac
WT_NAME="$(basename "$CWD")"

# Main repo root = parent of git-common-dir (Windows path normalized via cygpath -u).
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

BRANCH="$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

# (0) Activate .githooks/ if the project uses them (pre-push checks etc.).
# Idempotent: git config returns 0 even when value already matches.
[ -d "$CWD/.githooks" ] && git -C "$CWD" config --local core.hooksPath .githooks 2>/dev/null || true

# (1) .env.local — normally copied by .worktreeinclude; defensive fallback copy from main.
if [ ! -f "$CWD/.env.local" ] && [ -f "$MAIN_ROOT/.env.local" ]; then
  cp "$MAIN_ROOT/.env.local" "$CWD/.env.local" 2>/dev/null && echo "copied .env.local from main"
fi

# (2) node_modules junction (MSYS_NO_PATHCONV=1 required so "/J" is not mangled).
JUNC="absent"
if [ ! -e "$CWD/node_modules" ] && [ -d "$MAIN_ROOT/node_modules" ]; then
  WIN_LINK="$(cygpath -w "$CWD/node_modules" 2>/dev/null || printf '%s' "$CWD/node_modules")"
  WIN_TARGET="$(cygpath -w "$MAIN_ROOT/node_modules" 2>/dev/null || printf '%s' "$MAIN_ROOT/node_modules")"
  MSYS_NO_PATHCONV=1 cmd /c mklink /J "$WIN_LINK" "$WIN_TARGET" >/dev/null 2>&1 || true
fi
[ -e "$CWD/node_modules" ] && JUNC="ok (junction -> main)"

# (3) deterministic unique dev PORT (3110-3199; avoids 3100 main local).
ENVF="$CWD/.env.local"
HASHNUM="$(printf '%s' "$WT_NAME" | cksum | awk '{print $1}')"
PORT=$(( 3110 + (HASHNUM % 90) ))
if [ -f "$ENVF" ]; then
  EXIST="$(grep '^PORT=' "$ENVF" 2>/dev/null | head -1 | cut -d= -f2)"
  if [ -n "$EXIST" ] && [ "$EXIST" -ge 3110 ] 2>/dev/null && [ "$EXIST" -le 3199 ] 2>/dev/null; then
    :
  elif grep -q '^PORT=' "$ENVF" 2>/dev/null; then
    tmpf="$ENVF.wt.tmp"; sed "s/^PORT=.*/PORT=$PORT/" "$ENVF" > "$tmpf" 2>/dev/null && mv "$tmpf" "$ENVF"
  else
    # ensure trailing newline (main .env.local may not end with one) before appending
    [ -n "$(tail -c1 "$ENVF" 2>/dev/null)" ] && printf '\n' >> "$ENVF"
    printf 'PORT=%s\n' "$PORT" >> "$ENVF"
  fi
else
  printf 'PORT=%s\n' "$PORT" > "$ENVF"
fi
EFF_PORT="$(grep '^PORT=' "$ENVF" 2>/dev/null | head -1 | cut -d= -f2)"
[ -z "$EFF_PORT" ] && EFF_PORT="$PORT"

# (4) registry upsert (main root, gitignored, shared across all windows).
REGISTRY="$MAIN_ROOT/.claude/worktree-registry.md"
if [ ! -f "$REGISTRY" ]; then
  {
    echo "# Worktree registr"
    echo ""
    echo "| Worktree | Branch | Na cem jede | Spusteno |"
    echo "|---|---|---|---|"
  } > "$REGISTRY"
fi
TODAY="$(date +%Y-%m-%d)"
grep -v "^| $WT_NAME |" "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
printf '| %s | %s | %s | %s |\n' "$WT_NAME" "$BRANCH" "${DESC:-(bez popisu)}" "$TODAY" >> "$REGISTRY"

# (5) human-readable summary + sibling worktrees.
echo ""
echo "Worktree provisioned: $WT_NAME"
echo "  branch:       $BRANCH"
echo "  dev PORT:     $EFF_PORT   (npm run dev -- -p $EFF_PORT)"
echo "  node_modules: $JUNC"
echo "  registr:      $REGISTRY"
echo ""
echo "Ostatni okna (git worktree list + posledni commit):"
git -C "$MAIN_ROOT" worktree list 2>/dev/null | while IFS= read -r line; do
  [ -z "$line" ] && continue
  WPATH="$(printf '%s' "$line" | awk '{print $1}')"
  BR="$(printf '%s' "$line" | sed -n 's/.*\[\(.*\)\].*/\1/p')"
  [ -z "$BR" ] && BR="(detached)"
  SUBJ="$(git -C "$WPATH" log -1 --format=%s 2>/dev/null || true)"
  printf '  - %-28s [%s]  %s\n' "$(basename "$WPATH")" "$BR" "$SUBJ"
done
exit 0
