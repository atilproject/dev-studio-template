# ADR-0033 — Auto-Ping Dual-Channel Doctrine (notify.sh --wake + scripts/agent-wake.sh)

**Status:** Proposed
**Date:** 2026-06-21
**Supersedes:** (partial) `CLAUDE.md §Auto-Ping Hard-Rule` single-channel assumption
**Related:** ADR-0002 (GitHub-Native Autonomy), ADR-0032 (RCA-18 dedup buffer TTL — sister ADR), Issue #216 (RCA-18 filing), Issue #221 (this ADR's implementation tracker), Sprint 4 P0 chain

---

## Context

`scripts/notify.sh` currently writes only to Telegram (the human-only channel). When an agent calls `scripts/notify.sh -l <role> "<msg>"` to ping a peer agent, the message goes to Telegram but **agents do not read Telegram**. The peer agent only wakes up via the GitHub-native `agent-watch.sh` polling loop, which is independent of `notify.sh`.

This gap has been observed 3+ times in Sprint 4 Day 1:
- **RCA-18 unblock** (Issue #216): the architect's RCA findings were posted as Telegram pings; developer + orchestrator did not pick them up until the next 60s poll cycle
- **PR #217 / PR #219 merge follow-ups**: orchestrator merge notifications went to Telegram; downstream agents learned about the merge via the next periodic_backlog_scan
- **Issue #213 Layer 3 wake**: atilcan's 19:24Z "şimdi yaz sprint 5 değil" directive went to Telegram (via human channel); architect's wake happened via the next poll cycle (~60s lag)

The **orchestrator's RCA-18 stall diagnosis** (Issue #216 comments, 2026-06-21T20:42Z) identified that the single-channel assumption was the root cause of cross-agent wake latency. The fix is **doctrine-level**: every Auto-Ping must reach both channels — Telegram for human awareness AND tmux pane for agent wake.

### Why this is a separate ADR from ADR-0032 (RCA-18)

- ADR-0032 fixes the **dedup buffer pollution** (a different gap; closed Issue #216's primary observation)
- ADR-0033 fixes the **Auto-Ping single-channel gap** (the orchestrator's diagnosis; this is the *preventive* companion to ADR-0032's *reactive* fix)
- Both stem from RCA-18, but address different layers of the stack

## Decision

**Every Auto-Ping from an agent to a peer agent MUST use the dual-channel invocation**:

```bash
scripts/notify.sh -l <level> -w -r <role> "<message>"
```

This posts to Telegram (human mirror) AND injects the message into the target agent's tmux pane (agent wake) in <5s.

### New flag doctrine (`-w` / `-r`)

| Flag | Type | Default | Required when | Purpose |
|---|---|---|---|---|
| `-l` | string | `info` | always | Log level: `info`, `warn`, `error`, `ok`. Same as before. |
| `-r` | string | (none) | `-w` is set | Target role for tmux wake: `orchestrator`, `product-manager`, `architect`, `developer`, `tester`. NOT human — humans are Telegram-only. |
| `-w` / `--wake` | bool | false | opt-in | When set, after Telegram post, calls `scripts/agent-wake.sh -r <role> "<message>"`. |

**Backward compatibility**: when `-w` is NOT set, behavior is unchanged (Telegram only). Existing callers (agent-context-monitor.sh, agent-doctor.sh, status-action-driver.sh, deploy-runner.sh, health-check.sh) continue to work without modification.

**Required-when rule**: if `-w` is set but `-r` is missing, exit 2 with "ERROR: -w requires -r <role>". This prevents silent channel-skew (Telegram post + no wake = confused peer).

### New script: `scripts/agent-wake.sh`

Extracts `wake_pane_for_role` logic from `scripts/agent-watch.sh` lines 1089-1134 into a standalone CLI:

```bash
scripts/agent-wake.sh -r <role> "<message>"
```

Behavior:
- Looks up tmux pane by title (uppercase role) in `TMUX_SESSION` (default: `dev-studio`)
- Falls back to deterministic index map if title lookup fails (matches dev-studio-start.sh layout: orchestrator=main.0, pm=main.1, architect=main.2, developer=main.3, tester=main.4)
- Composes a heredoc-safe prompt with `🔔 INBOX (auto-wake from agent-watch loop):` header + the message body + the standard `Lütfen pickup et: review yap, label flip et, peer'i bilgilendir, sonra standby.` footer
- Injects via `tmux send-keys -t <pane> -l "<prompt>"` (literal mode so backticks/quotes survive)
- Sends Enter key after the prompt
- Silent no-op if: tmux unavailable, session missing, role unknown, pane not found
- Exit codes: 0 (success OR silent no-op), 2 (usage error)

### notify.sh amend (developer-owned per Issue #221)

`scripts/notify.sh` adds `-w` and `-r` flags:

```bash
# Pseudo-code (≤30 lines, no production code in this ADR)
WAKE=false
ROLE=""
while getopts "l:r:wh" opt; do
  case "$opt" in
    l) LEVEL="$OPTARG" ;;
    r) ROLE="$OPTARG" ;;
    w) WAKE=true ;;
    # ... h, error handling
  esac
done

# After Telegram POST succeeds:
if [ "$WAKE" = true ]; then
  if [ -z "$ROLE" ]; then
    echo "ERROR: -w requires -r <role>" >&2
    exit 2
  fi
  "$SCRIPT_DIR/agent-wake.sh" -r "$ROLE" "$MSG" || true
fi
```

### CLAUDE.md §Auto-Ping Hard-Rule update

Add to the format table:

```
| Auto-Ping (peer-agent) | Telegram (mirror) + tmux pane (wake) | dual-channel, required for agent targets | `notify.sh -w -r <role> "msg"` |
```

Add to the "What you do NOT need to ask" section:

```
- ❌ "Telegram yeterli mi, tmux wake gerekiyor mu?" — Hayır, agent peer'ları için her zaman dual-channel (`-w -r <role>`). Telegram tek başına insan kanalıdır.
```

Add a new "Escalation istisnaları" clause:

```
- Auto-Ping to peer agent MUST use dual-channel. Telegram-only pings to agents
  are a **silent-drop risk** (peer doesn't see Telegram; wakes only on next
  poll cycle, ~60s lag). This is the doctrine gap closed by ADR-0033 (Issue #221).
```

### Test contract (`scripts/tests/d024-agent-wake.sh`)

7 test cases:
1. `agent-wake.sh -r developer "test"` → tmux send-keys called with dev pane id, Enter injected
2. `agent-wake.sh -r developer "test"` (no tmux) → silent no-op, exit 0
3. `agent-wake.sh -r nonexistent "test"` → silent no-op, exit 0
4. `agent-wake.sh` (no args) → usage error, exit 2
5. `notify.sh -w -r developer "test"` → Telegram post + agent-wake.sh call (mock)
6. `notify.sh -w` (no -r) → exit 2, error message
7. `notify.sh -w -r developer "test with backticks `echo hi`"` → tmux send-keys literal mode preserves backticks (verify no expansion)

## Consequences

### Positive

- **Cross-agent wake latency drops from ~60s to <5s.** The watcher poll interval is 60s; the dual-channel path bypasses it via direct tmux injection.
- **Doctrine is explicit and enforceable.** The CLAUDE.md update + ADR-0033 + d024 regression make "single-channel to agent" a clear violation, not a habit.
- **Backward compatible.** Existing single-channel callers continue to work; opt-in via `-w`.
- **Human channel unaffected.** Telegram stays the single channel for human notifications (`-l human "msg"` — note: `-r human` is invalid because humans aren't in tmux).

### Negative

- **Tighter coupling to tmux topology.** `agent-wake.sh` is coupled to the 5-pane dev-studio-start.sh layout (orch/pm/arch/dev/tester). Layout changes require index-map updates in `agent-wake.sh`. Mitigation: title-based lookup with index-map fallback covers most layout changes; explicit error in CI test if layout shifts beyond fallback.
- **More CI surface to maintain.** d024 adds 7 TCs to the regression suite. Mitigation: tests are small (each <30 lines), modeled on d015+d019 patterns.
- **Risk of "ping-storm" if misused.** An agent calling `-w -r developer` for every trivial event could flood the developer pane. Mitigation: existing discipline (ADR-0002 §Trigger → action mapping) limits when pings are appropriate; this ADR doesn't change that discipline, only the channel.

### Out of scope

- **Template port** to atilcan65/dev-studio-template (follow-up issue, per Issue #221 §Out of scope)
- **Multi-pane broadcast** (`-r all` to wake all 5 panes): considered, rejected — too easy to misuse; explicit single-role targeting is the correct discipline
- **Replacing Telegram** with another human channel: considered, rejected — Telegram works fine for humans; the gap was agent-side, not human-side

## Implementation handoff

Per Issue #221 §Owner table:

- **@architect** (this ADR + CLAUDE.md update): 0.5 SP ✅ (this PR + companion PR)
- **@developer** (scripts/agent-wake.sh + scripts/notify.sh amend + d024): 2 SP (separate PR)
- **@tester** (d024 sign-off): 0.5 SP
- **Total**: 3 SP

This PR = architect's 0.5 SP. Developer's 2 SP + tester's 0.5 SP = separate PRs.

## Sprint 4 impact

- Sprint 4 commitment: was 21.0 SP, now **21.5 SP** (+0.5 SP for ADR-0033 + CLAUDE.md update, architect-authored)
- Buffer: 13.5-23.5 SP (was 14.0-24.0 SP, still healthy)
- Sprint 4 P0 chain: 4 P0 stories + Issue #213 (closed) + Issue #221 (this story, in flight)

## Pending

- Owner (@atilcan65) approves ADR-0033 (Proposed → Accepted)
- Architect opens companion PR for CLAUDE.md §Auto-Ping Hard-Rule update
- Developer opens impl PR for `scripts/agent-wake.sh` + `scripts/notify.sh` amend + d024
- Tester signs off on d024
- Owner merges all PRs

— @architect, 2026-06-21T20:50:00Z

## Verification log (2026-06-24 — Issue #320 closure + dual-channel end-to-end)

End-to-end verification of the dual-channel mechanism per Issue #320 expanded scope:

- **PM**: ✅ 2/2 ACK (send-keys + paste-buffer both routes land)
- **DEV**: ✅ 1/1 ACK (3s latency, end-to-end dual-channel confirmed)
- **ARCH**: ✅ 1/1 ACK (mechanism canonical, no other changes needed)
- **TEST**: ✅ 1/1 ACK (verdict channel also functional)
- **Total**: 5/5 — dual-channel works both directions

**Latency budget** (idle-pane delivery):
- send-keys + Enter: 3-5s
- paste-buffer: 1-2s (faster, no key-by-key latency)

**Latency budget** (busy-pane delivery):
- Spinner-state messages queue but Enter is no-op; submitted on agent's next idle prompt.
- Worst-case observed: ~100s for context-saturated agent (5m+ thinking).

**PRs that closed Issue #320 chain**:
- PR #325 — `scripts/ping.sh` wrapper (canonical entry point) + notify.sh `-l <role>` deprecation guard
- PR #332 (PR-A) — soul-sed: 4 tracked soul files (`product-manager`, `architect`, `developer`, `tester`) migrated to `scripts/ping.sh <role>` invocation
- PR #333 (PR-B) — `.claude/agents/orchestrator.md` tracked (was gitignored) + ADR-0041 orchestrator role contract
- Issue #320 — closed

**Owner-only follow-up (NOT in this PR)**:
- Issue #335 — 3 stale `notify.sh -l <role>` refs in orchestrator.md (`.claude/` human-only territory per CLAUDE.md §File ownership matrix)

— @orchestrator, 2026-06-24T12:04:00+03:00
