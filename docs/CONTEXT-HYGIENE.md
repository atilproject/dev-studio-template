# Context Hygiene & Re-priming Doctrine

**Status:** Active
**Scope:** Multi-agent dev studio template
**Owner:** Architect (doctrine updates), Human (operational triggers)

---

## 1. Why This Document Exists

Agents are long-running Claude Code instances. Two slow-burn problems can
silently degrade behavior over multi-day sessions:

1. **Doctrine drift** — A new ADR or role-doc patch is merged to `main`,
   but the agent's loaded system prompt is still the old version. The
   agent keeps acting on stale rules until it's re-primed or restarted.
2. **Post-compaction state drift** — When Claude Code auto-compacts the
   conversation (~200K token threshold), short-term memory of recent
   actions ("I just commented on PR #X") can blur. The role identity
   (CLAUDE.md + role doc) is preserved by the system prompt, but the
   agent should re-read GitHub state instead of trusting its memory.

Note: agent identity does **not** disappear on compaction. CLAUDE.md and
the role doc live in the system prompt slot, which compaction does not
touch. This document is about *aligning to new doctrine* and *trusting
the source of truth*, not about preventing identity loss.

## 2. Single Source of Truth (Doctrine Restatement)

For any operational decision, the agent reads in this priority order:

1. **GitHub** (issues, PRs, labels, comments) — live, always authoritative.
2. **`agent-state.sh` JSON** — local watermark/dedup state, written by the
   watcher loop, never by the agent's chat memory.
3. **CLAUDE.md + role doc** (`.claude/agents/<role>.md`) — identity,
   behavior, doctrine.

The agent **never** acts on its chat history alone. Examples of forbidden
inferences:

- "I think I already commented on this PR." → re-query the PR.
- "The architect probably finished review." → re-read PR labels.
- "Last time the label was X." → re-read the issue.

## 3. When to Re-prime

Trigger a re-prime when any of these is true:

| Trigger | Severity | Action |
|---------|----------|--------|
| New ADR merged to `main` | High | Re-prime all affected roles. |
| Role doc patched on `main` | High | Re-prime that role. |
| `CLAUDE.md` patched on `main` | High | Re-prime **all** roles. |
| Agent visibly confused (wrong label, wrong action) | Critical | Re-prime that role; if no `[REPRIME ACK]` within one polling cycle, full restart (§ 4.2). |
| Routine, end of day | Low | Optional — re-prime any role that worked >4h. |

Compaction itself is **not** a trigger. Compaction is automatic and safe;
re-priming is for *doctrine alignment*, not memory hygiene.

## 4. How to Re-prime

### 4.1 Soft re-prime (default)

```bash
bash scripts/reprime-agent.sh <role>
```

`<role>` is one of: `orchestrator`, `product-manager`, `architect`,
`developer`, `tester`.

This is the **only operation you normally need.** It is fully automatic:

- Sends an enqueued `[REPRIME]` message to the role's tmux pane.
- The agent finishes its in-flight work unit, then re-reads
  `.claude/CLAUDE.md` and its role doc.
- The agent acknowledges with `[REPRIME ACK] <role>: <summary>` and
  resumes under the refreshed doctrine.
- **No human action between send and ack.** No restart, no manual relaunch.

See § 5 for the timing & work-in-progress contract.

### 4.2 Full session restart (fallback, rare)

Use only when:

- Soft re-prime did not produce `[REPRIME ACK]` within one polling cycle, OR
- Multiple agents are confused at once and you cannot wait, OR
- The tmux session itself is broken (panes died, watchers detached, etc.).

```bash
bash scripts/dev-studio-start.sh stop
bash scripts/dev-studio-start.sh start
```

This kills all 5 agents and respawns the whole session cleanly. There is
**no per-role restart**, by design — the launcher only exposes
`start | attach | stop`. We do not add a per-role kill path because
"selective restart" historically causes more drift bugs than it fixes
("çalışan şeyi bozmayalım").

There is no manual relaunch step. The launcher handles everything.

## 5. Re-prime Timing & Work-in-progress

Soft re-prime is **enqueued**, never interrupting. The contract:

1. The re-prime message is queued as the agent's next chat input.
2. The agent finishes its **current conversation turn** (usually seconds).
3. If the agent is mid-way through a larger work unit (writing a PR,
   running tests, drafting an ADR), it completes that work unit too.
   The re-prime applies on the **next** task start.
4. The agent acknowledges with `[REPRIME ACK] <role>: <summary>`, then
   proceeds with the new doctrine in effect.

**This means:**
- ✅ No work is lost or left half-done.
- ✅ The re-prime always takes effect before the agent's next decision.
- ⚠️ If the agent is in the middle of a long task (e.g. a 20-minute
  story implementation), the re-prime may apply 20 minutes later.

If you cannot wait, escalate to full restart (§ 4.2) — but understand
that full restart abandons all in-flight work across all 5 agents.

## 6. What Does NOT Need Re-priming

- Compaction events (auto-handled by Claude Code).
- Minor PR comment exchanges.
- Scheduled idle time (agent does nothing → cannot drift).
- Token rate-limit pauses (Claude Code resumes correctly).

## 7. Agent-side Protocol

Each role doc (`.claude/agents/*.md`) carries a **REPRIME Protocol**
section that defines exactly how an agent must respond when it receives
a `[REPRIME]` message. The expected acknowledgment format is:

```
[REPRIME ACK] <role>: <one-line summary of any doctrine change noticed, or "no change">
```

If you do not see this acknowledgment within one polling cycle, escalate
to full restart (§ 4.2).

---

## See Also

- `scripts/reprime-agent.sh` — implementation (soft re-prime).
- `scripts/dev-studio-start.sh` — launcher (full restart path).
- `.claude/agents/*.md` — per-role REPRIME Protocol section.
- `docs/decisions/` — ADRs that may trigger re-prime when merged.
- `.claude/CLAUDE.md` — agent identity & project context.
