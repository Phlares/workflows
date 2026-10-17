# shellcheck shell=bash
# Paths Claude Code reads from the repo folder at start-up: hooks, MCP
# servers, instructions. Same list as claude-code-action's restore-config.ts.
# shellcheck disable=SC2034 # used by the scripts that source this file
CONFIG_PATHS=(.claude .mcp.json .claude.json .gitmodules .ripgreprc CLAUDE.md CLAUDE.local.md .husky)
