# scripts/

Operational scripts for Dev Studio.

## notify.sh — Telegram notifications

Sends notifications to Telegram via Bot API.

### Setup

1. Create a Telegram bot via [@BotFather](https://t.me/BotFather), copy the token.
2. Get your chat ID (DM `@userinfobot` or use `getUpdates` for groups).
3. Add to `~/.dev-studio-env`:

       export TELEGRAM_BOT_TOKEN="..."
       export TELEGRAM_CHAT_ID="..."

4. `chmod 600 ~/.dev-studio-env`
5. Source from `~/.bashrc`: `[ -f ~/.dev-studio-env ] && source ~/.dev-studio-env`

### Usage

    ./scripts/notify.sh "Plain message"
    ./scripts/notify.sh -l info "Sprint 1 started"
    ./scripts/notify.sh -l warn "CI flaky on PR #42"
    ./scripts/notify.sh -l error "P0 blocker: prod down"
    ./scripts/notify.sh -l ok "Deploy succeeded"

### Levels

| Flag | Icon | When |
|------|------|------|
| info (default) | ℹ️ | Standard updates |
| warn | ⚠️ | Non-blocking issues |
| error | 🚨 | P0/P1 blockers, paging |
| ok | ✅ | Success confirmations |

### Used by

- `.claude/agents/orchestrator.md` — Escalation on blockers
- `.claude/commands/standup.md` — Daily standup digest
- `scripts/health-check.sh` (planned) — Agent heartbeat alerts
- `systemd/dev-studio-health.timer` (planned) — 30-min health check
