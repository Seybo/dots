#!/usr/bin/env bash
# commit-gate.sh
# PreToolUse hook (matcher: Bash). When the command creates a git commit, checks
# the staged diff for the temporary-stub marker and asks for confirmation if any
# staged addition still carries it. Enforces .ai/rules/placeholder-stubs.md.
# Intentionally active in all permission modes: deferring a stub must be an
# explicit user decision, so auto modes do not bypass this gate.

set -uo pipefail

MARKER='SHOULD BE HANDLED/REMOVED BEFORE MERGE'

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)

[ -z "$command" ] && exit 0

# Only inspect commands that actually run `git commit` (with optional -C <dir>).
printf '%s' "$command" | grep -qE '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit([[:space:]]|$)' || exit 0

# Honor an explicit -C <dir>; otherwise use the tool call's cwd.
repo_dir=$(printf '%s' "$command" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+).*[[:space:]]commit.*/\1/p')
[ -z "$repo_dir" ] && repo_dir="${cwd:-.}"

hits=$(git -C "$repo_dir" diff --cached -U0 2>/dev/null | grep -E '^\+' | grep -Fc "$MARKER")
[ "${hits:-0}" -eq 0 ] && exit 0

files=$(git -C "$repo_dir" diff --cached -G"$MARKER" --name-only 2>/dev/null | head -10 | tr '\n' ' ')
reason="Staged diff still adds the temporary-stub marker (${hits} hit(s): ${files}). Implement or remove the stubs before committing, or confirm to defer them explicitly."
jq -cn --arg reason "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$reason}}'
exit 0
