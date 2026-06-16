#!/bin/bash
# fix-statusline.sh — ensures ~/.claude/settings.json has correct statusLine.command
# Idempotent, silent on success. Called by PostToolUse hook after cc switch runs.
#
# External tools like `cc switch` or `cc update` will *overwrite*
# ~/.claude/settings.json and revert statusLine.command to a stale inline value
# (typically reading non-existent fields like .context_window.used_percentage),
# which causes the statusline to render as just a dim "[dir]" with no other info.
#
# Pair this with a project-level .claude/settings.local.json PostToolUse hook on
# Bash matcher to repair automatically after every Bash invocation.

set -u

SELF="$HOME/.claude/statusline.sh"
CFG="$HOME/.claude/settings.json"

[ -f "$CFG" ] || exit 0

# Check if already correct
jq -e --arg cmd "$SELF" '.statusLine.command == $cmd' "$CFG" >/dev/null 2>&1 && exit 0

# Fix it — merge, don't blast other fields
tmp=$(mktemp /tmp/fix-statusline.XXXXXX)
jq --arg cmd "$SELF" '.statusLine = {"type":"command","command":$cmd}' "$CFG" > "$tmp" 2>/dev/null && mv "$tmp" "$CFG" || rm -f "$tmp"
