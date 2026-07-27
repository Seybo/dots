#!/usr/bin/env bash
# block-shell-substitution.sh
# PreToolUse hook (matcher: Bash). Flags any Bash command containing
# command substitution $(...), backticks, or process substitution <(...) / >(...)
# and asks for confirmation before running it.
# Replaces the skipped glob-based permissions.deny rules that tried to do this.

set -uo pipefail

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
permission_mode=$(printf '%s' "$input" | jq -r '.permission_mode // "default"' 2>/dev/null)

# Respect Claude's explicit automatic permission modes. The normal permission
# rules and classifier still apply; this hook must not force an interactive ask.
case "$permission_mode" in
  auto|dontAsk|bypassPermissions) exit 0 ;;
esac

# Can't read a command -> defer to the normal permission flow.
[ -z "$command" ] && exit 0

if printf '%s' "$command" | grep -qE '\$\(|`|<\(|>\('; then
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"This command uses command substitution $(...), backticks, or process substitution <(...) / >(...). Confirm before running."}}
JSON
  exit 0
fi

exit 0
