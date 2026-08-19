#!/usr/bin/env bash
# statusLine command (settings.json statusLine.command). Runs via Git Bash.
# Reads session JSON on stdin; prints:
#   model | branch | worktree-name | :PORT | ctx N% (Xk) | $cost
# Context discipline: >=250k tokens appends "-> /handover?", >=400k appends
# "!! HANDOVER" -- long sessions balloon silently and cache reads of that
# history dominate token spend. ASCII-only. Fail-safe to model/$PWD. Exit 0 always.
set -u

STDIN_JSON="$(cat 2>/dev/null || true)"

# node instead of python3: on Windows `python3` is often only the App-Execution-
# Alias stub (empty output), which makes the statusline silently fall back to
# "model"/no-ctx/no-cost -- the >=250k handover hint then never fires. node is
# already on PATH in a Node project.
read -r MODEL CWD <<EOF
$(printf '%s' "$STDIN_JSON" | node -e '
let c=[];process.stdin.on("data",d=>c.push(d)).on("end",()=>{
  let o={};try{o=JSON.parse(Buffer.concat(c).toString("utf8"))}catch{}
  const m=o.model||{};
  const name=(m.display_name||m.id||"model").replace(/ /g,"_");
  const cwd=(o.cwd==null?"":String(o.cwd)).replace(/\s+/g," ");
  process.stdout.write(name+" "+cwd);
});' 2>/dev/null || printf 'model \n')
EOF
MODEL="$(printf '%s' "$MODEL" | tr '_' ' ')"
[ -z "$CWD" ] && CWD="$PWD"

# ctx % + used tokens + session cost from the same stdin JSON. used_percentage
# is pre-computed by the harness; used tokens derived from current_usage when
# present, else from pct*window. All fields optional -> -1 sentinel = hide.
read -r PCT USEDK COST <<EOF
$(printf '%s' "$STDIN_JSON" | node -e '
let c=[];process.stdin.on("data",d=>c.push(d)).on("end",()=>{
  let o={};try{o=JSON.parse(Buffer.concat(c).toString("utf8"))}catch{}
  const cw=o.context_window||{};
  const pct=cw.used_percentage;
  const size=cw.context_window_size||0;
  const cu=cw.current_usage||{};
  let used=null;
  if(cu&&Object.keys(cu).length){used=(cu.input_tokens||0)+(cu.cache_read_input_tokens||0)+(cu.cache_creation_input_tokens||0);}
  if(used===null&&pct!=null&&size){used=Math.trunc(size*Number(pct)/100);}
  const cost=(o.cost||{}).total_cost_usd;
  const pOut=(pct!=null)?Math.round(Number(pct)):-1;
  const uOut=(used!==null)?Math.trunc(used/1000):-1;
  const cOut=(cost!=null)?Number(cost).toFixed(2):-1;
  process.stdout.write(pOut+" "+uOut+" "+cOut);
});' 2>/dev/null || printf -- '-1 -1 -1\n')
EOF

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

LINE="$MODEL | $BRANCH | $WT_NAME | :$PORT"
if [ "$PCT" -ge 0 ] 2>/dev/null; then
  CTX="ctx ${PCT}%"
  [ "$USEDK" -ge 0 ] 2>/dev/null && CTX="ctx ${PCT}% (${USEDK}k)"
  if [ "$USEDK" -ge 400 ] 2>/dev/null; then CTX="$CTX !! HANDOVER"
  elif [ "$USEDK" -ge 250 ] 2>/dev/null; then CTX="$CTX -> /handover?"
  fi
  LINE="$LINE | $CTX"
fi
case "$COST" in
  -1|"") : ;;
  *) LINE="$LINE | \$$COST" ;;
esac

printf '%s\n' "$LINE"
exit 0
