#!/usr/bin/env bash
# SessionStart hook — see README.md in this directory.
#
# SessionStart was chosen for the starter because it needs no stdin/JSON
# parsing (works on the base image without jq) and its stdout is injected
# into the session context.
echo "Container environment and pre-installed tools: /root/.claude/rules/container.md"
