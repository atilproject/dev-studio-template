# ADR-0004 — Bootstrap Auto-Kickoff (Template-Grade Agent Activation)

**Status:** Accepted 2026-06-10
**Context:** Multi-agent dev-studio, Claude Code TUI panes, tmux session

## Background

In PR-C (Event Model v2), we proved that watchers can detect and route events. But on 2026-06-10 22:18Z, after PR #26 merged, the orchestrator/architect/product-manager/developer panes were found in Claude Code's "Welcome back!" interactive screen — their **role definition had never been loaded**, and the kickoff prompt had never been sent.

Root cause: `scripts/.tmux-bootstrap/<role>.sh` invoked `claude --dangerously-skip-permissions` with **no `--agent` flag and no positional prompt**. The bootstrap banner claimed "Soul: .claude/agents/<role>.md zaten diskte, bellekte yüklenecek" — but Claude Code does NOT auto-load subagent definitions; they must be invoked via `--agent` or `/agent <name>`.

## Decision

Every bootstrap script MUST invoke Claude Code with **both**:
1. `--agent <role>` — loads `.claude/agents/<role>.md` as the active subagent contract
2. Positional kickoff prompt — read from `scripts/kickoff/<role>.txt` (committed file)

```bash
claude --dangerously-skip-permissions --agent "${role}" "$KICKOFF_PROMPT"
```

## Guarantees (template-grade)

1. **Idempotent stop/start.** `./scripts/dev-studio-start.sh stop && start` produces a fully-functional 5-agent system. Zero manual intervention.
2. **Role loaded on tick zero.** Agent's first action is reading its role file + state file + watcher log. No "Welcome back" zombie state.
3. **Kickoff is version-controlled.** `scripts/kickoff/<role>.txt` lives in the repo. Changes to bootstrap behaviour are PR-reviewable.
4. **Fallback is safe.** If kickoff file is missing, a generic prompt is injected. System still boots, just with less context.
5. **Cross-project reusable.** Other projects using the dev-studio template only need to:
   - Drop in their own `.claude/agents/<role>.md` files
   - Drop in their own `scripts/kickoff/<role>.txt` files
   - Bootstrap mechanism is unchanged.

## Consequences

**Positive:**
- Human is no longer required to paste role definitions on session start
- Restart-after-crash works correctly (e.g. agent-state.sh missing recovery)
- Future PR-E (systemd watcher resilience) builds on this — watchers + bootstrap both survive arbitrary process death

**Negative / risks:**
- `--agent` flag depends on Claude Code v2+ subagent feature. Older versions would silently ignore the flag and fall back to default agent. Mitigation: pin Claude Code version in `CLAUDE.md` requirements.
- Kickoff prompt becomes a "soft contract" between bootstrap + role file. If they drift (e.g. role file moves, kickoff still says "read .claude/agents/<role>.md"), agent will produce a confusing first action. Mitigation: lint in CI (D5 future scope).

## Related

- PR-C / ADR-0003: Event Model v2 (silent stall prevention) — this ADR extends to "silent activation failure"
- PR-D D2 (future): post-merge lifecycle events
- PR-D D4 (future): systemd watcher resilience

## Reviewed by

Architect (this ADR), Human (atilcan65), Orchestrator (via runtime observation 2026-06-10).
