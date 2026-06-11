# ADR-0009 — PR-Open `pr_labeled` Fanout (Closes ADR-0008 § 8.2 Loop)

**Status:** Accepted
**Date:** 2026-06-11
**Deciders:** @architect
**Implements:** Issue #47 (D2.2)
**Closes:** [ADR-0008](./ADR-0008-label-conditional-fanout.md) § 8.2 ("PR-open / PR-review-requested routing path" — declared future work, now realised).
**Depends on:** ADR-0007 (label cleanup — unchanged), ADR-0008 (label-conditional `pr_merged` fanout — pattern template).

---

## 1. Context

ADR-0008 § 8.2 explicitly identified that `pr_merged` fanout is the **wrong**
event for waking architect and tester, because:

1. The label that authorises the wake (`needs-architect-review`,
   `needs-tester-signoff`) is transient — ADR-0007 strips it within ~12s of merge.
2. The architect/tester's actual work happens during the **PR-open**
   lifecycle, not at merge time.
3. The HWM side-channel (D2.1.2) still advances, so architect/tester never see
   `pr_merged` events, which means they never wake at all for human-decision
   work.

This is the "documented-but-unimplemented loop" ADR-0008 § 9 references as
**D2.2 — PR-open / PR-review-requested routing**. Issue #47 formalises it as a
deliverable.

### Empirical trigger

Smoke S3-PR-Arch (PR #45) demonstrated the race timeline in § 8.1 of ADR-0008.
The architect was correctly skipped on `pr_merged` (label already stripped),
but was also never woken for the actual review — confirming the loop is open.

### Goal

Add a **new event kind** `pr_labeled` that wakes architect and tester at the
moment a PR author or orchestrator signals them via a recognised label,
**before merge**. Close the loop on ADR-0008 § 8.2.

---

## 2. Decision

We extend Event Model to v3.2: add a new query `query_pr_labeled` that wakes
architect/tester on `pull_request: labeled` semantics (modelled as "open PR
that currently carries a wake-trigger label, whose `updatedAt` is newer than
the role's HWM cursor"). The implementation reuses the ADR-0008 helper
pattern (`role_wakes_for_pr`, HWM side-channel) and the D2.1.2 side-channel
fix verbatim.

### 2.1 Wake-trigger labels

Wake the role when an **open** PR carries **any** of the following labels:

| Role        | Wake-trigger labels                                                         |
| ----------- | --------------------------------------------------------------------------- |
| `architect` | `needs-architect-review`, `cc:architect`, `agent:architect`                  |
| `tester`    | `needs-tester-signoff`,  `cc:tester`,    `agent:tester`                     |

**Correction to issue #47 AC:** the issue proposed regex
`^needs-(architect|tester)-review$`. That regex would match
`needs-architect-review` but **miss** the actual tester label
`needs-tester-signoff` (which is not `-review` suffixed). We use **exact-name
membership** instead, parallel to `role_wakes_for_pr` (agent-watch.sh
L214/L219). This also subsumes `cc:<role>` and `agent:<role>` so the standard
Handoff Label Discipline signals all work on the new event type.

### 2.2 Event shape

```json
{
  "id": "pr-labeled-39-2026-06-11T12:34:56Z",
  "kind": "pr_labeled",
  "number": 39,
  "title": "...",
  "url": "https://github.com/.../pull/39",
  "updated_at": "2026-06-11T12:34:56Z",
  "context": {
    "labels": ["needs-architect-review", "type:feature"],
    "wake_reason": "label:needs-architect-review",
    "pr_state": "open"
  }
}
```

`id` is unique per (PR, HWM-emitted-tick). On a quiet tick where the same PR
is re-evaluated, dedup ring suppresses re-emission. The `updated_at` field is
the PR's `updatedAt` (proxy for "any change since last poll", same trick
`query_board_changes` already uses).

### 2.3 HWM cursor (D2.1.2 pattern verbatim)

`query_pr_labeled` stores the newest `updatedAt` it **saw** (across all open
PRs in the window, regardless of label filter) in a process-global
`PR_LABELED_NEWEST_SEEN` and bumps the role's `pr_labeled_last_seen_utc`
state field before filtering. This is byte-identical to the D2.1.2 fix for
`pr_merged` and solves the same problem: cursor must advance even when
**no** PR matches the filter, otherwise the next poll re-queries forever.

Backfill: on first run, `pr_labeled_last_seen_utc` is initialised to
`now - 60s` (one poll window) to prevent the mass-wake on rollout (every
open PR with a wake-trigger label would otherwise flood the panes).

### 2.4 Decision matrix (per role per open PR)

| In `PR_LABELED_FANOUT`? | Wake label present? | PR open? | Wakes? |
| ----------------------- | ------------------- | -------- | ------ |
| n/a (no list set)       | no                  | n/a      | no     |
| yes                     | n/a                 | no       | no     |
| yes                     | yes                 | yes      | **yes** |

(Architect and tester are **never** in `PR_MERGED_FANOUT_DEFAULT` per ADR-0008
§ 2.1 Layer 1. So for them, the pr_labeled path is the only wake path during
the open lifecycle. This is intentional — architect and tester are
human-decision roles that should not be woken for lifecycle-default work.)

### 2.5 `agent-doctor.sh --fanout PR_NUM`

The doctor subcommand is extended with a third "would wake on `pr_labeled`"
column per role, using the same helper as the watcher. The label-state is
read **live** from `gh pr view` (post-D2.3's `--at TIMESTAMP`, this becomes
historical). Doctor unit-test parity preserved (16-line helper block stays
duplicated between watcher and doctor per ADR-0008 § 4.2 risk-2 rationale).

#### 2.5.1 `agent-doctor.sh --check-env` parity

The doctor's existing `--check-env` subcommand (per ADR-0008) is extended
to verify the new `PR_LABELED_FANOUT` env var. If unset, default is
`"architect tester"`. If set to empty, doctor **warns loudly** (the parallel
to D-2.1.1's architect-skipped-on-merge case we just fixed): empty default
= silent no-op landmine for human-decision roles. Matches the existing
`PR_MERGED_FANOUT_DEFAULT=""` warning.

Sample output:

```
$ agent-doctor.sh --fanout 39
PR #39: feat(autonomy): add PR-open routing
  state: OPEN
  labels: needs-architect-review, type:feature, priority:P2
  pr_merged fanout (would wake on merge):
    orchestrator    yes (default-fanout)
    product-manager yes (default-fanout)
    developer       yes (default-fanout)
    architect       no  (not in default; label rule: needs-architect-review would match — see pr_labeled)
    tester          no  (not in default; no matching label)
  pr_labeled fanout (waking NOW on current label set):
    architect       yes (label:needs-architect-review)
    tester          no
```

### 2.6 `scripts/tests/d211-fanout-test.sh` extension

Add 5 new test cases (S4-PR-Open series) to the existing 35-case fixture:

- **S4-PR-Open-1** open PR with `needs-architect-review` → expect 1 pr_labeled wake (architect).
- **S4-PR-Open-2** open PR with `needs-tester-signoff` → expect 1 pr_labeled wake (tester).
- **S4-PR-Open-3** open PR with both → expect 2 pr_labeled wakes.
- **S4-PR-Open-4** closed PR with `needs-architect-review` (shouldn't happen under ADR-0007, but guard anyway) → expect 0 wakes.
- **S4-PR-Open-5** open PR with `cc:architect` only → expect 1 pr_labeled wake (architect, via `cc:`).

---

## 3. Alternatives considered

| Option | Why rejected |
| ------ | ------------ |
| **A — Subscribe to GitHub webhooks** | Adds external dependency (webhook receiver). Watcher's 60s poll is the agreed wake cadence (ADR-0002). Rejected for consistency. |
| **B — Use Issues events API (`/repos/.../issues/N/events`)** | Returns precise label-event timestamps but needs 1 API call per PR. With 50 PRs in the window, that's 50 extra round-trips per poll per watcher. Rejected for cost; same data modelled with PR's `updatedAt` is sufficient (dedup handles noise). |
| **C — Reuse `query_review_requests` (the existing `pr_review_requested` handler)** | Different semantics: that wakes on `cc:*` and `needs-*` labels **plus** explicit `gh pr edit --add-reviewer`. The two queries would conflate signal sources. Rejected — keep the channels separate. |
| **D — Drive everything off `cc:*` only, drop `needs-*` from this path** | Would break the issue's stated contract (the issue's AC explicitly says "wake on `needs-architect-review` added"). Also loses the value of the existing `needs-*` labels as a public signal to humans reading the PR. Rejected. |
| **E — Trigger doctor automatically when this lands** | Outside scope; doctor is invoked manually. Rejected. |

Chosen: **B-style data, A-style query** — use `gh pr list --state open --json
updatedAt,labels` (cheap, cached) with the PR's `updatedAt` as the HWM proxy
and the dedup ring to suppress noise from non-label updates.

---

## 4. Consequences

### 4.1 Positive

- **ADR-0008 § 8.2 loop closed.** Architect and tester wake on the actual
  review work, not on `pr_merged` (which is structurally wrong for them).
- **No interaction with ADR-0007 cleanup.** The wake fires at label-add time
  (PR-open lifecycle). The cleanup at merge time is a no-op for `pr_labeled`
  because by then the wake has already happened and the dedup ring has
  recorded the event id. No race.
- **Declarative, label-driven.** PR author labels their PR; architect wakes.
  No shell edits, no manual coordination. Aligns with ADR-0008 § 7
  ("canonical recipe for any future multi-recipient event").
- **Reuses tested primitives.** `role_wakes_for_pr` (existing),
  `processed_event_ids` dedup ring (existing), HWM side-channel pattern
  (D2.1.2 — proven on `pr_merged`). Net new code: ~70 LOC in
  `agent-watch.sh`, ~50 LOC in `agent-doctor.sh`, ~60 LOC of test cases.
- **Reversible.** `PR_LABELED_FANOUT=""` disables for the role; watcher
  restart picks up the new value within ~5s (systemd path unit, ADR-0006).

### 4.2 Negative / risks

- **HWM cursor is the PR's `updatedAt`, not the label-event timestamp.** A
  PR that gets a label added, then a force-push within the same 60s window,
  will be re-evaluated on the next poll. Mitigated by dedup ring (event id is
  stable per PR per wake-tick). Acceptable.
- **First-run backfill window of 60s prevents mass-wake** — but if the
  watcher was down for >60s and a PR opened with the label, it will be
  missed. Same trade-off as `pr_merged`. Documented in rollout.
- **Wake is "current label set"**, not "label-event stream". If a label is
  added and removed within one poll window (60s), the wake never fires.
  Acceptable — that's also faster than human reaction.
- **No mention-based fallback** — if a PR author `@architect`-mentions
  without adding the label, the existing `query_pr_mentions` query still
  fires. So the wake is robust to label-discipline sloppiness.

### 4.3 Observability

Each `pr_labeled` event includes `context.wake_reason`:
`"label:<exact-label-name>"`. Watcher state file gains a new field
`pr_labeled_last_seen_utc` (per role). Doctor reports the decision live and
post-D2.3 will be able to simulate at any historical timestamp.

**Suppression counter** — watcher also emits a structured log line
`pr_labeled_suppressed_quick_removal` (per role) when a label is added and
removed within a single 60s poll window without firing the wake (the
race in § 4.2 risk-2). This is the **measurement instrument for TD-002**:
when suppression rate exceeds 5% of polled PRs, the TD-002 payoff
trigger fires and we switch from the `updatedAt` proxy to the Issues
events API.

### 4.4 Tech-debt delta

- **TD-002** — `pr_labeled` query reads PR's `updatedAt` instead of the
  label-event timestamp. Severity: L. Payoff trigger: when dedup-ring churn
  exceeds 5% of polled PRs (currently 0%). Owner: @architect (next
  retrospective). Resolution path: switch to Issues events API in a future
  D-series refinement (D2.2.1).

---

## 5. Rollout plan

1. Land D2.2 in a single PR touching:
   - `scripts/agent-watch.sh` — add `query_pr_labeled` (~70 LOC), extend
     `poll_once` to call it, add `PR_LABELED_FANOUT` env var
     (default `"architect tester"`).
   - `scripts/agent-doctor.sh` — extend `--fanout` with pr_labeled column
     (~50 LOC), reuse existing helper.
   - `scripts/tests/d211-fanout-test.sh` — add S4-PR-Open 1-5 cases.
   - `docs/decisions/ADR-0009-pr-labeled-fanout.md` — **this file**.
   - `docs/decisions/ADR-0008-label-conditional-fanout.md` — § 8.2 updated
     with a one-line "OUTDATED: closed by ADR-0009" pointer.
   - `docs/decisions/INDEX.md` — add ADR-0009 row.
2. Watchers auto-restart within ~5s of merge (ADR-0006 `.path` unit). First
   poll after restart uses the 60s backfill window — no mass-wake.
3. Smoke matrix: open 4 PRs in sandbox (one per label combination), verify
   architect and tester wake within 60s, verify HWM advances, verify
   `agent-doctor --fanout` reports the new column.
4. Run `agent-doctor --fanout <real PR>` to confirm doctor parity.

---

## 6. Reversal

```bash
# Disable pr_labeled fanout for both human-decision roles
systemctl --user set-environment PR_LABELED_FANOUT=""
systemctl --user restart 'dev-studio-watcher@*.service'
```

Reverts architect/tester to the pre-D2.2 state (no wake at all on PR-open
labelling). All other event types unaffected. If this is insufficient, revert
the PR via GitHub UI.

---

## 7. Template doctrine

This is the **second instance** of the "label-conditional fanout" pattern
(ADR-0008 being the first). It confirms § 7 of ADR-0008 holds: the recipe
generalises to new event types without per-event code redesign. Future
multi-recipient events (`issue_escalated`, `pr_blocked`, etc.) should
reference **both** ADR-0008 and ADR-0009 as the canonical pattern.

---

## 10. Agent-side adoption contract (BUG-3 closure)

**Added 2026-06-11 after BUG-3 / issue #56.**

### 10.1 The gap

ADR-0009 introduced `needs-tester-signoff` (and re-emphasised
`needs-architect-review`) as `pr_labeled` wake labels in § 2.1. The
**producer** (the watcher's `query_pr_labeled`) landed in PR #49. The
**consumer** (the agent prompts + `.claude/CLAUDE.md` Label semantik
sözlüğü) was **not updated atomically**. As a result, agents following
the pre-D2.2 playbook would clean up the wake labels along with the
`cc:*` labels they already knew about, breaking the D2.2 wake pipeline
in production (tester never wakes when architect pre-emptively removes
`needs-tester-signoff`).

### 10.2 The contract

Every protocol change that introduces a new wake label — whether
`pr_labeled` (this ADR), `pr_merged` (ADR-0008), or future event types
— must update the **consumer side atomically** with the producer side.
Specifically:

| File | Must reference | Why |
|------|----------------|-----|
| `.claude/CLAUDE.md` | All wake labels for all roles | The Label semantik sözlüğü is the canonical registry |
| `.claude/agents/{role}.md` | The role's own wake labels + anti-pattern "do not remove other roles' wake labels" | The soul file is what an agent reads on session start |
| `scripts/kickoff/{role}.txt` | The role's own wake labels | The bootstrap prompt for new Claude Code sessions |

For D2.2 (ADR-0009), the mandatory wake-label references are:

| Role | Wake labels to reference in their prompt/contract |
|------|--------------------------------------------------|
| `architect` | `needs-architect-review`, `cc:architect`, `agent:architect` |
| `tester`    | `needs-tester-signoff`, `cc:tester`, `agent:tester` |
| `developer` | `needs-tester-signoff` (add when PR ready for test) + all others (as anti-pattern: do not remove) |
| `pm`        | All wake labels (for board hygiene / routing decisions) |
| `orchestrator` | All wake labels (for routing logic) |

### 10.3 Required anti-pattern: "do not remove other roles' wake labels"

Every agent's Handoff Discipline table must include an explicit
**anti-pattern** row:

> ❌ Other roles' wake label'lerini kaldırmak (`needs-architect-review`,
> `needs-tester-signoff`, `cc:*`, `agent:*`). Bu label'lar o rolün
> `pr_labeled` wake'i. Sen kaldırırsan, o rol uyanmaz. ADR-0009 § 2.1
> + § 10.

The original pre-D2.2 anti-pattern was just "don't leave the queue in
limbo" — it didn't distinguish between "your queue" and "another
role's queue." D2.2 added a new category of label (wake labels for
other roles) that must be treated as off-limits to anyone but the
tester/architect signing off on their own work.

### 10.4 Producer-consumer atomicity (template lesson)

This bug class will recur every time a new wake label is introduced
into the watcher. The right long-term answer is **producer-consumer
atomicity at the PR level**: a protocol-change PR is not complete
until both the producer (watcher event) and the consumer (agent
prompts + handoff contract) land. The PR's acceptance criteria should
explicitly list both sides. Concretely:

1. **PR body checklist** — add "agent prompt updated" + "CLAUDE.md
   label dictionary updated" as explicit AC items, not afterthoughts.
2. **Pre-merge test** — run a smoke that verifies the wake label
   actually wakes the right role on a test PR, end-to-end. If the
   label is missing from the prompt, the role won't know to keep it
   on the PR, and the wake will be lost.
3. **PR template** — `.github/PULL_REQUEST_TEMPLATE.md` (or equivalent)
   should include a "Protocol change? Update producer + consumer
   atomically" reminder.

This is a **template-grade lesson** and will be captured more fully
in a future ADR-0010 (proposed scope: "Multi-agent protocol change
discipline — producer-consumer atomicity").

### 10.5 Specific file changes required to close BUG-3

(To be applied by the respective file owners per the project File
ownership matrix; architect provides the **exact text** to drop in.)

#### 10.5.1 `.claude/CLAUDE.md` (owner: human) — Label semantik sözlüğü

Insert a new row in the table (around line 204):

```
| `needs-tester-signoff` | Tester sign-off bekliyor (`pr_labeled` wake — D2.2) | developer (PR ready iken) veya architect (review sonrası, label kalır) | tester (APPROVED verdict ile birlikte) |
```

#### 10.5.2 `.claude/agents/architect.md` (owner: human) — Handoff Discipline

Line 153 — change the 🟢 OK row to use `needs-tester-signoff` as the
forward signal instead of `cc:tester`:

```
| `needs-architect-review` label'lı PR'a review yazdın (🟢 OK) | `--remove-label needs-architect-review --remove-label cc:architect` (do NOT remove `needs-tester-signoff`) | `[ARCH→TEST] PR #N design OK, tests gözden geçirebilirsin` |
```

Add an anti-pattern row (after the existing `❌ Design review yazıp
cc:architect veya needs-architect-review etiketini bırakmak` row at
line 167):

```
| ❌ `needs-tester-signoff` veya `cc:tester` label'larını kaldırmak (architect olarak) — bunlar tester'ın `pr_labeled` wake'i; sen kaldırırsan tester uyanmaz. ADR-0009 § 2.1, § 10.3 |
```

#### 10.5.3 `.claude/agents/tester.md` (owner: human) — Handoff Discipline

Add a new "Wake labels I respond to" section:

```
## Wake labels I respond to (D2.2)

- `needs-tester-signoff` — explicit sign-off ask, fires `pr_labeled` event
- `cc:tester` — active queue pointer
- `agent:tester` — story ownership signal

When ANY of these labels is added to a PR where I'm `agent:tester` (or
no `agent:*` is set), the watcher emits a `pr_labeled` event for me.

On 🟢 APPROVED: `--remove-label needs-tester-signoff --add-label status:ready`
On 🔴 CHANGES REQUESTED: `--remove-label needs-tester-signoff --add-label cc:developer`
On 🟡 NEEDS DISCUSSION: `--remove-label needs-tester-signoff --add-label cc:architect`
```

#### 10.5.4 `.claude/agents/developer.md` (owner: human) — queue activation

Add to the developer's queue-activation rules:

```
When opening a PR ready for tester review:
- Add `needs-tester-signoff` (D2.2 wake label — wake path is `pr_labeled`)
- Optionally also add `cc:tester` (legacy wake path; redundant but explicit)
```

#### 10.5.5 `scripts/kickoff/{role}.txt` (owner: each agent / dev) — bootstrap

Each kickoff file should reference the role's wake labels in the
"OPERATING MODE" section. For architect.txt (which the architect
amends themselves):

```
- Your watcher polls GitHub every 60s for: PRs labeled "cc:architect",
  "needs-architect-review", OR "agent:architect" (any of these wakes
  you via pr_labeled or pr_review_requested). See ADR-0009 § 2.1 for
  the full wake set. Do NOT remove `needs-tester-signoff` from PRs —
  that's tester's wake, not yours.
```

For tester.txt, developer.txt, pm.txt, orchestrator.txt — analogous
additions per the role's own wake set.

#### 10.5.6 Smoke test S5-Handoff (owner: developer) — verify the loop

Add a smoke test in `scripts/tests/` that exercises the full D2.2 path:

1. Open a sandbox PR with `needs-tester-signoff`.
2. Verify watcher's `query_pr_labeled` emits an event for the tester
   role with `wake_reason: "label:needs-tester-signoff"`.
3. Verify the tester pane wakes within 60s.
4. Verify the tester's first action includes `--remove-label
   needs-tester-signoff --add-label status:ready` (the test handoff).
5. Negative: if a different role (e.g. architect) removes
   `needs-tester-signoff` before the tester acts, the test SHOULD
   fail with "tester never woke" — this is the BUG-3 reproduction.

### 10.6 File ownership and apply path

| Change | Owner | Apply path |
|--------|-------|-----------|
| § 10.5.1 (CLAUDE.md label dictionary) | **human** | direct edit (file is human-only) |
| § 10.5.2 (architect.md Handoff Discipline) | **human** | direct edit (file is human-only) |
| § 10.5.3 (tester.md Wake labels section) | **human** | direct edit |
| § 10.5.4 (developer.md queue rules) | **human** | direct edit |
| § 10.5.5 (kickoff files) | **each agent / developer** | per agent's own PR (low priority — affects new sessions only) |
| § 10.5.6 (S5-Handoff smoke test) | **developer** | new PR |
| **This ADR § 10** | **architect** | this PR (already drafted) |

The split reflects the file ownership matrix: `.claude/` is
human-only and must be applied by the human; `scripts/kickoff/` and
test files can be applied by the respective agents or developer.

### 10.7 Cross-references

- **Issue #56** (this bug) — BUG-3
- **PR #49** — D2.2 producer-side landed (this is the producer; § 10
  is the consumer update)
- **PRs #51, #54, #55** — D2.2 follow-ups; all 3 affected by BUG-3
  in production today
- **ADR-0008 § 7** — pre-existing template doctrine; § 10 extends it
  with producer-consumer atomicity
- **Future ADR-0010** (proposed) — cross-cutting "protocol change
  discipline" ADR; will reference this section as the D2.2 case
  study

---

## 8. Out of scope (deferred)

- **D2.3** — Doctor `--at TIMESTAMP` time-travel mode. Issue #47 explicitly
  defers this.
- **D2.2.1** — Switch `pr_labeled` to Issues events API for label-event
  precision (TD-002 above). Tracked as tech-debt; no implementation date.
- **Reverse — fire on label *removal***. Today, removing `needs-architect-review`
  after review is silent. We could add `pr_labeled_removed` as a separate
  event type. Not required by any current workflow.

---

## 9. BUG-1 sibling closure (issue #52)

The kill-switch idiom in § 6 (`PR_LABELED_FANOUT=""` to disable) uses
`${VAR-default}` (unset-only fallback) precisely because the bash
`${VAR:-default}` operator would silently re-default on empty string and
break the documented contract. This is a **template-grade lesson**: every
fanout env var in the watcher/doctor must use the same form.

**BUG-1 (PR #49, commit 6823193)**: applied the lesson to
`PR_LABELED_FANOUT` in this ADR's reference impl. Fixed.

**BUG-1 sibling (issue #52)**: the pre-existing
`PR_MERGED_FANOUT_DEFAULT="${PR_MERGED_FANOUT_DEFAULT:-orchestrator product-manager developer}"`
at `scripts/agent-watch.sh:179` and `scripts/agent-doctor.sh:294` carried
the same landmine. The user-facing contract in
`agent-doctor.sh:476` (`PR_MERGED_FANOUT_DEFAULT=""` → "rules-only mode")
was broken by the implementation. Fixed in the follow-up PR for issue #52
(same one-line `:-` → `-` change as BUG-1, applied to both sites).

**TD-003** (added retroactively): audit ALL bash env-var defaults in
`scripts/agent-watch.sh` and `scripts/agent-doctor.sh` for `${VAR:-default}`
patterns where the env var is documented as a kill switch. Any other
instances are landmines of the same shape. Owner: @architect (next retro).
Resolution: either fix (if kill-switch) or document (if default fallback is
the intended contract).
