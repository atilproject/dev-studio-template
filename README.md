# atilprojects

Multi-agent development studio powered by Claude Code + Codex CLI with GitHub Scrum workflow.

## Architecture

- **5 Claude Code agents** (Orchestrator, PM, Architect, Developer, Tester) via MiniMax subscription
- **Codex CLI** for test runner + incident bot
- **GitHub Projects v2** as Scrum board
- **systemd timer** for health checks (30 min cadence)
- **Discord webhook** for notifications

## Repository Structure

\`\`\`
.
├── .claude/          # Agent definitions, slash commands, project memory
│   ├── agents/       # Subagent soul files (orchestrator, pm, architect, developer, tester)
│   ├── commands/     # Slash commands (/sprint-start, /standup)
│   └── CLAUDE.md     # Project-wide context for Claude Code
├── .github/          # Issue/PR templates, CI workflows
│   ├── ISSUE_TEMPLATE/
│   └── workflows/
├── docs/             # Architecture decisions, setup guides, runbooks
├── src/              # Application source code
├── tests/            # Test suites
├── scripts/          # Health-check, notification scripts
└── systemd/          # systemd service & timer units
\`\`\`

## Quick Start

See \`docs/SETUP.md\` for full setup instructions.

## License

Private — internal use only.
