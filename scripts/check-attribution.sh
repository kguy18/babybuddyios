#!/bin/sh
# Fails if the given text (file argument or stdin) carries coding-agent
# attribution. Canonical copy lives in kguydev/app-template; the commit-msg
# hook, the attribution workflow and the agent guard all call it.
pattern='^(co-authored-by|signed-off-by):.*(claude|anthropic|codex|openai|chatgpt|copilot|cursor|gemini|aider|devin|windsurf)|generated (with|by) .*(claude|codex|copilot|cursor|gemini|ai\b)|claude\.(com|ai)/(claude-)?code|noreply@anthropic\.com|🤖'

if [ -n "$1" ]; then text=$(cat "$1"); else text=$(cat); fi

hits=$(printf '%s\n' "$text" | grep -v '^#' | grep -inE "$pattern")
if [ -n "$hits" ]; then
  echo "Agent attribution is not allowed:" >&2
  echo "$hits" >&2
  exit 1
fi
