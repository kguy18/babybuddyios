#!/bin/sh
# SessionStart hook: when this repo has not been set up for the mattpocock
# engineering skills yet, tells the agent to ask Kurtis to run the setup.
# The setup skill can only be started by a person, so the agent asks.
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
# The template itself (not yet bootstrapped) is not a project.
if [ -f scripts/bootstrap.sh ] && grep -qs 'AppName' project.yml; then exit 0; fi
[ -f docs/agents/domain.md ] && exit 0
cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"This repo is not set up for the mattpocock engineering skills yet (docs/agents/domain.md is missing). Before anything else in your first reply, tell Kurtis and ask him to type /mattpocock-skills:setup-matt-pocock-skills. Only he can start that skill. It writes docs/agents/ (issue tracker, triage labels, domain docs) and the Agent skills section of AGENTS.md."}}
JSON
