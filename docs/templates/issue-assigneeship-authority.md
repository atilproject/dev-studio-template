# Template — Issue assigneeship authority (label > body text)

**Source**: Session 2026-06-19 — Developer stalled on Issue #71/#72/#74 (STORY-009/010/012 P1/P2) because issue body said `agent:tester cc:developer` (PM-planning template text) but issue labels said `agent:developer`. Developer waited for tester handoff that was already done — 3 P1 stories blocked for ~2 hours of agent idle + 1 user correction.

**Reusable for**: Any agent who picks up work from `agent-watch.sh` queue and needs to decide "is this mine right now?" — the answer must come from labels, not from the issue body.

---

## TL;DR

> **Issue assigneeship = `agent:*` label authority. Issue body text is informational, possibly stale, and NEVER the source of truth for "is this mine".**

If `agent:<role>` is on the issue, it's that role's queue — period. Start work (or explicitly acknowledge + defer). Do not wait for additional handoff signals (PR ownership, body-text `cc:` mentions, other roles commenting) — those are review/awareness, not ownership.

---

## Why this exists (the failure mode this template fixes)

PM templates (`/workspace/docs/backlog/STORY-NNN.md` + the GitHub issue template at `.github/ISSUE_TEMPLATE/`) historically included a section like:

```
## Handoff discipline
- agent:tester cc:tester — test plan first. Spec AC1-AC7. After test plan:
  flip to agent:developer cc:developer.
```

This text was **planning-state intent**, not the **current ownership state**. After the tester wrote the test plan and the issue label was flipped to `agent:developer`, the body text was stale. Agents reading the body concluded "tester still owns it" and waited for a handoff signal that already happened.

Symptoms observed in the wild:
- `agent-watch.sh` query showed `agent:developer` on the issue, but the developer agent didn't act on it (because no PR event fired).
- The developer read the issue body, saw "handoff: agent:tester → agent:developer after test plan", and concluded "test plan is done but handoff didn't happen yet".
- Developer waited → idle → user had to nudge → ~2 hours of stalled P1 work.

The 4-cat invariant (ADR-0012) already made `agent:*` label the **authoritative** ownership signal. The body text was contradicting it.

---

## The rule (soul-file clause template)

Insert under "Operating Principles" in each of the 5 soul files (`.claude/agents/{developer,architect,tester,product-manager,orchestrator}.md`):

> **Issue assigneeship = label authority (per ADR-0012 4-cat invariant).** When deciding whether an issue is in your queue, the **labels are the source of truth** — not the issue body. If `agent:<your-role>` is on the issue, it's yours. The body text is informational and may be stale (e.g., PM-planning templates include "handoff: agent:tester → agent:developer after test plan" — that text describes intent, not current state). **Action rule**: when you see `agent:<your-role>` on an open issue with `status:ready` (or `status:in-progress`), treat it as a wake event and start work — read the spec, open a branch, TDD red→green, draft PR. If you think the body contradicts the label, prefer the label and add a comment noting "body text seems stale, working from spec + label".

---

## Per-soul-file instantiations

The clause text is **identical** across all 5 soul files — only the role name in `<your-role>` changes. Keep the text uniform so all agents share the same mental model.

### `.claude/agents/developer.md`

Insert under "Operating Principles" (before "TDD where it pays"):

> **Issue assigneeship = label authority (per ADR-0012 4-cat invariant).** When deciding whether an issue is in your queue, the **labels are the source of truth** — not the issue body. If `agent:developer` is on the issue, it's yours. The body text is informational and may be stale (e.g., PM-planning templates include "handoff: agent:tester → agent:developer after test plan" — that text describes intent, not current state). **Action rule**: when you see `agent:developer` on an open issue with `status:ready` (or `status:in-progress`), treat it as a wake event and start work — read the spec, open a branch, TDD red→green, draft PR. If you think the body contradicts the label, prefer the label and add a comment noting "body text seems stale, working from spec + label".

### `.claude/agents/architect.md`

Substitute `agent:developer` → `agent:architect`. Same clause.

### `.claude/agents/tester.md`

Substitute `agent:developer` → `agent:tester`. Same clause. Testers especially hit this because test-plan-first handoffs (tester writes TDD red → flips to developer) leave stale body text.

### `.claude/agents/product-manager.md`

Substitute `agent:developer` → `agent:product-manager`. Same clause.

### `.claude/agents/orchestrator.md`

Substitute `agent:developer` → `agent:orchestrator`. Same clause.

---

## Companion fix: PM-planning template amendment

The root cause is partly the body text being **misleading**. Fix at the source by amending the PM-planning templates so they don't include ownership intent in body text. Recommended change to `.github/ISSUE_TEMPLATE/story.md` (or wherever PMs draft stories):

Replace this section in the body template:

```
## Handoff discipline
- agent:tester cc:tester — test plan first. Spec AC1-AC7. After test plan:
  flip to agent:developer cc:developer.
```

With this:

```
## Handoff discipline (planning intent — NOT current ownership)
- **Intent**: After sizing, the work flow is tester → developer → tester signoff.
  Labels are the source of truth for current ownership (per ADR-0012).
- **Initial labels** (set by PM at creation): agent:tester, cc:tester.
- **First handoff** (after test plan lands): tester flips to agent:developer, cc:tester.
- **Subsequent handoffs**: see ADR-0015 atomic 4-flag hand-off.
```

The intent stays in the body, but is **clearly labeled as intent**, not current state. Plus the labels are documented as the authoritative ownership signal.

---

## Mechanical application (for the human owner)

```bash
# Per agent role:
for ROLE in developer architect tester product-manager orchestrator; do
  SOUL_FILE=".claude/agents/${ROLE}.md"
  CLAUSE=$(cat <<EOF

**Issue assigneeship = label authority (per ADR-0012 4-cat invariant).** When deciding whether an issue is in your queue, the **labels are the source of truth** — not the issue body. If \`agent:${ROLE}\` is on the issue, it's yours. The body text is informational and may be stale (e.g., PM-planning templates include "handoff: agent:tester → agent:developer after test plan" — that text describes intent, not current state). **Action rule**: when you see \`agent:${ROLE}\` on an open issue with \`status:ready\` (or \`status:in-progress\`), treat it as a wake event and start work — read the spec, open a branch, TDD red→green, draft PR. If you think the body contradicts the label, prefer the label and add a comment noting "body text seems stale, working from spec + label".
EOF
)
  # Insert at marker line (human applies per file ownership matrix)
  echo "Append to $SOUL_FILE:"
  echo "$CLAUSE"
done

# Then amend .github/ISSUE_TEMPLATE/story.md per "Companion fix" section
```

---

## Cross-references

- **ADR-0012** (Required Label Set on Issue/PR Creation — the birth contract) — already establishes label as authoritative, but the soul files didn't propagate this rule to ownership decisions.
- **ADR-0015** (Atomic 4-flag hand-off) — the procedure for handoff. This template's clause complements it by clarifying that labels — not body text — are the trigger for "is this mine?".
- **Issue #109** (bounded standby doctrine + queue-empty detector) — companion concern. This template fixes "stale-body-text stall"; Issue #109 fixes "idle-with-P0-in-queue stall". Different failure modes, complementary fixes.

---

## Regression: what would have prevented the 2026-06-19 incident

The 2026-06-19 incident: developer agent stalled on Issue #71/#72/#74 for ~2 hours because issue body said `agent:tester cc:developer` (stale) but label said `agent:developer` (current). Developer waited for handoff signal that had already happened.

If the clause in this template had been in the developer soul file, the developer's first poll would have seen:
1. `agent:developer` label on issues #71/#72/#74 → my queue.
2. Body text says "handoff: agent:tester → agent:developer after test plan" → planning intent (stale wording).
3. Action rule says "prefer the label" → start work.

Total elapsed time: ~30 seconds instead of 2 hours.

---

## Test cases (future PR — agent-watch.sh should detect this scenario)

- T1: Issue with `agent:developer` label + body text mentioning `agent:tester` → developer agent wake event fires
- T2: Issue with `agent:developer` label + `status:ready` + `status:in-progress` → developer agent wake event fires (both states are actionable)
- T3: Issue with `agent:tester` label + body text mentioning `agent:developer` → developer agent DOES NOT fire wake event (correct — not developer's queue)
- T4: Issue with `cc:developer` label + NO `agent:developer` label → developer agent DOES NOT fire wake event (cc = review/awareness, not ownership)

These would be added to `scripts/agent-watch.sh` as a new `query_issue_assigned` function (separate from `query_pr_labeled`), with regression test in `scripts/tests/d013-issue-assigneeship-authority.sh`.

---

**Status**: Template ready. Apply on next soul-file PR cycle (currently waiting for Issue #109 reviewer approval — could bundle this amendment with that PR if the human owner approves).