#!/usr/bin/env bash
# statusLine command (settings.json statusLine.command). Runs via Git Bash.
# Reads session JSON on stdin; prints: model | branch | worktree-name | :PORT.
# ASCII-only. Fail-safe to model/$PWD. Exit 0 always.
set -u

STDIN_JSON="$(cat 2>/dev/null || true)"

read -r MODEL CWD <<EOF
$(printf '%s' "$STDIN_JSON" | python3 -c "import json,sys
try:
    d=json.load(sys.stdin)
    m=d.get('model',{})
    name=m.get('display_name') or m.get('id') or 'model'
    print(name.replace(' ','_'), d.get('cwd',''))
except Exception:
    print('model', '')" 2>/dev/null || printf 'model \n')
EOF
MODEL="$(printf '%s' "$MODEL" | tr '_' ' ')"
[ -z "$CWD" ] && CWD="$PWD"

# Normalize any path form (C:\..., C:/..., /c/...) to a Git-Bash path.
CWD="$(cygpath -u "$CWD" 2>/dev/null || printf '%s' "$CWD")"

BRANCH="$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

WT_NAME="main"
case "$CWD" in *"/.claude/worktrees/"*) WT_NAME="$(basename "$CWD")" ;; esac

PORT="3100"
if [ -f "$CWD/.env.local" ]; then
  P="$(grep '^PORT=' "$CWD/.env.local" 2>/dev/null | head -1 | cut -d= -f2)"
  [ -n "$P" ] && PORT="$P"
fi

printf '%s | %s | %s | :%s\n' "$MODEL" "$BRANCH" "$WT_NAME" "$PORT"
exit 0
