#!/bin/bash
# statusline.sh — renders the Claude Code statusline
# Reads statusline JSON from stdin, outputs formatted statusline to stdout.
#
# Format: [dir] · model · plan/balance · ctx:used% (remaining%)
# Segments auto-hide when data is missing. Separator " · " tracks via $sep.
#
# Install:  cp statusline.sh statusline-plan.sh ~/.claude/ && chmod +x ~/.claude/statusline*.sh
# Pair with: ~/.claude/settings.json → statusLine.command = "$HOME/.claude/statusline.sh"

set -u

input=$(cat)
model=$(echo "$input" | jq -r '(.model.display_name // .model.id // empty)' 2>/dev/null)
tpath=$(echo "$input" | jq -r '(.transcript_path // empty)' 2>/dev/null)
cwd=$(echo "$input" | jq -r '(.workspace.current_dir // .cwd // empty)' 2>/dev/null)
if [ -n "$cwd" ]; then
  dir=$(basename "$cwd")
else
  dir=$(basename "$(pwd)")
fi

plan=$($HOME/.claude/statusline-plan.sh "$model" "${ANTHROPIC_BASE_URL:-}" "${ANTHROPIC_AUTH_TOKEN:-}" 2>/dev/null)

# ctx: compute from transcript_path — Claude Code's statusline JSON does NOT
# carry context_window fields, so we read the last "usage" line from the
# transcript JSONL and sum input + cache_read + cache_creation tokens.
maxctx=${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-200000}
used_tok=0
if [ -n "$tpath" ] && [ -f "$tpath" ]; then
  used_tok=$(awk '/"usage"/{last=$0} END{print last}' "$tpath" 2>/dev/null \
    | jq -r '(.message.usage // .usage)
             | (.input_tokens // 0)
               + (.cache_read_input_tokens // 0)
               + (.cache_creation_input_tokens // 0)' 2>/dev/null)
  case "$used_tok" in ''|*[!0-9]*) used_tok=0 ;; esac
fi

sep=""
out=""

# [dir]
out="${out}${sep}[${dir}]"
sep=" · "

# model
case "$model" in ""|null) ;; *)
  out="${out}${sep}${model}"
  ;;
esac

# plan/balance (from statusline-plan.sh)
if [ -n "$plan" ]; then
  out="${out}${sep}${plan}"
fi

# ctx:used% (remaining%)
if [ "$used_tok" -gt 0 ] && [ "$maxctx" -gt 0 ]; then
  pct=$(awk -v u="$used_tok" -v m="$maxctx" 'BEGIN{printf "%.0f", u*100/m}')
  rem=$((100 - pct))
  out="${out}${sep}ctx:${pct}% (${rem}%)"
fi

printf "\033[2m%s\033[0m" "$out"
