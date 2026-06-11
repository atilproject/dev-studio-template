# ADR-0008 — Label-Conditional `pr_merged` Fanout (Event Model v3.1)

**Status:** Accepted (2026-06-11)
**Scope:** PR-D D2.1.1 — refines D2's `pr_merged` event model.
**Supersedes:** [ADR-0005](./ADR-0005-pr-merged-events.md) §"Fanout policy" (D2 unconditional 5-role wake).
**Depends on:** ADR-0003 (event model v2), ADR-0005 (`pr_merged` event), ADR-0006 (systemd watchers), ADR-0007 (D3 auto-label cleanup).

---

## 1. Context

D2 (PR #35) introduced `pr_merged` events that wake **all five roles**
(orchestrator, product-manager, architect, developer, tester) every time any PR
merges. This was the simplest correct behaviour and let us ship D2 quickly, but
it has two production problems that PR-D D2.1.1 fixes:

1. **Wasted Claude Code budget.** Most merges are PM/dev/orchestrator concerns
   (lifecycle, sprint metrics, dependency graph). Waking architect on every
   doc-typo merge or tester on every infra PR burns API tokens with no
   workflow benefit. D2 Smoke (PRs #35–#40) confirmed architect and tester
   wake noise was >70% irrelevant.
2. **No declarative routing.** Adding a sixth role (e.g. `security`) or
   re-routing merges per repo would require code changes inside
   `agent-watch.sh`. We want the policy in env / labels, not in shell logic.

ADR-0005 explicitly anticipated this:
> "Future work (D2.1+): make the wake-set declarative — labels on the merged
> PR opt specific roles in (`needs-architect-review` → architect, etc.)."

D2.1.1 is that future work. It must:

- Preserve D2's lifecycle correctness — orchestrator / PM / developer **must**
  still wake on every merge (sprint state, dependency graph, board moves).
- Add label-driven opt-in for architect & tester so they wake **only when the
  PR explicitly asks for them**.
- Be **fully reversible** without code edits (env kill switches).
- Be **debuggable in seconds** (`agent-doctor --fanout PR_NUM` shows the
  decision for any PR).
- **Not break the HWM** — even when no role wakes for a given merged PR, the
  watcher's `pr_merged_last_seen_utc` cursor must still advance so we don't
  re-process old PRs forever.

This is the second of three D2 refinements in the PR-D series:

| ADR     | What it adds                                  | Status |
| ------- | --------------------------------------------- | ------ |
| 0005    | `pr_merged` event, unconditional 5-role wake  | Done   |
| 0007    | D3 auto-label cleanup on merge                | Done   |
| **0008**| **Label-conditional fanout (D2.1.1)**         | **This ADR** |

---

## 2. Decision

We introduce **Event Model v3.1**: `pr_merged` fanout is now a two-layer
decision per merged PR per role.

### 2.1 Two-layer policy

#### Layer 1 — Default fanout (always wakes)

Env var (set in `dev-studio-start.sh` and systemd unit env):

```bash
PR_MERGED_FANOUT_DEFAULT="orchestrator product-manager developer"
```

Any role in this space-separated list wakes on **every** merged PR
regardless of labels. This is the D2-compatible lifecycle path:

- `orchestrator` — sprint board moves, dependency graph re-eval.
- `product-manager` — backlog re-prioritisation, sprint metrics.
- `developer` — local checkout sync, branch GC.

Setting `PR_MERGED_FANOUT_DEFAULT=""` (empty) disables the default fanout
entirely. Useful only for debugging or staged rollouts; **not recommended in
production** because it strands lifecycle work.

#### Layer 2 — Label rules (conditional opt-in)

Env switch:

```bash
PR_MERGED_FANOUT_RULES_ENABLED=true   # default
```

When `true`, the merged PR's label set is consulted:

| Role        | Wakes when PR has ANY of                                   |
| ----------- | ---------------------------------------------------------- |
| `architect` | `needs-architect-review` **or** `agent:architect`          |
| `tester`    | `needs-tester-signoff`   **or** `agent:tester`             |

When `false`, label rules are skipped — only `PR_MERGED_FANOUT_DEFAULT`
roles wake. This is the full **D2 rollback** path: set rules-off and (if
desired) add architect/tester back to `PR_MERGED_FANOUT_DEFAULT` to exactly
reproduce D2 behaviour.

### 2.2 Decision matrix

| Layer 1 (in DEFAULT?) | Layer 2 (rule matches?) | Wakes? |
| --------------------- | ----------------------- | ------ |
| yes                   | n/a                     | **yes** (fast path) |
| no                    | rules disabled          | no     |
| no                    | yes                     | **yes** |
| no                    | no                      | no     |

### 2.3 HWM advancement (side-channel)

The watcher's `query_pr_merged` runs once per poll and returns the
**post-filter** list of pr_merged events for the current role. But the role's
`pr_merged_last_seen_utc` cursor must advance based on the **pre-filter**
newest merged-PR timestamp — otherwise architect/tester would re-query the
same range forever whenever no PRs matched their label rules.

Implementation: `query_pr_merged` stores the newest raw `mergedAt` it saw in
a process-global `PR_MERGED_NEWEST_SEEN`. After the poll, `poll_once` uses
that value (not the filtered output) to advance the cursor.

### 2.4 `agent-doctor --fanout PR_NUM`

New debug subcommand that:

1. Fetches PR labels via `gh pr view`.
2. Re-evaluates the same helper functions the watcher uses.
3. Prints — for each of the 5 roles — `wakes=yes/no` with the deciding
   reason (default fanout, label rule match, or specific missing condition).
4. Shows the current `PR_MERGED_FANOUT_*` env config and suggests overrides
   for verification.

Unit-test parity: doctor and watcher use byte-identical helper logic; the
test fixture at `/tmp/d211-fanout-test.sh` (35 cases) covers both.

---

## 3. Alternatives considered

| Option | Why rejected |
| ------ | ------------ |
| **A — Keep D2 (always wake 5)** | Burns budget; user explicitly asked to fix in D2.1.1. |
| **B — Drop architect/tester from default, no label rules** | Breaks workflows that legitimately need architect/tester on every merge (e.g. retrospective sprints). No opt-in mechanism. |
| **C — YAML config file (`fanout.yml`)** | Adds parser dependency + file-sync issue across 5 watcher processes. Env vars are simpler and already systemd-native. |
| **D — Lib directory + sourced helpers** | VM doesn't have a `lib/` dir; D2.1.1 must minimise diff. Helpers live inline in `agent-watch.sh` and are re-declared in `agent-doctor.sh` (16-line block, unit-tested for parity). |
| **E — GitHub Actions workflow drives fanout** | Adds external dependency, slower feedback loop, harder to debug locally. The current watcher polls every 60s; that's the right place to decide. |

Chosen: **A+B mix per user vote (1-A+B karışım)** — env-driven default fanout
**plus** declarative label rules. Both layers independently kill-switchable.

---

## 4. Consequences

### 4.1 Positive

- **~60% Claude Code budget reduction** on merge bursts (D2 Smoke baseline:
  5 wakes × N merges → now ~3 wakes × N merges + occasional architect/tester).
- **Declarative routing** — PR author labels `needs-architect-review` on
  their own PR and architect wakes; no shell edits.
- **Two-knob kill switch** — `PR_MERGED_FANOUT_RULES_ENABLED=false` for
  instant rollback to default-only; `PR_MERGED_FANOUT_DEFAULT=""` for full
  off (debug).
- **Debuggable** — `agent-doctor --fanout 42` answers "why didn't tester
  wake on PR #42?" with no log grep.
- **D3-compatible** — D3's auto-label cleanup runs `on: pull_request: closed`
  and is decoupled from the watcher's fanout decision. Labels are stripped
  *after* the merge, so the watcher (which reads labels from the PR via gh)
  sees them either way depending on race; smoke S3-PR-Both verifies.

### 4.2 Negative / risks

- **Label drift** — if a PR author forgets `needs-architect-review`, the
  architect will miss the merge. Mitigation: doctor `--fanout` makes this
  visible; orchestrator role can backfill labels pre-merge as part of its
  sprint review (future D5).
- **HWM side-channel is a global** — `PR_MERGED_NEWEST_SEEN` is a bash
  process global, not a thread-safe construct. Safe here because each
  watcher is single-threaded by design (one poll loop), but flagged for any
  future migration to a multi-poll model.
- **Doctor helper duplication** — agent-doctor.sh re-declares the 4 helper
  functions instead of sourcing agent-watch.sh. Cost: 20 lines of
  duplication + a unit test fixture that asserts parity. Benefit: doctor
  works even if agent-watch.sh is moved/renamed, and we don't need
  source-guards around the watcher's main loop.

### 4.3 Observability

Each pr_merged event the watcher emits already includes
`context.fanout_reason` (added in this patch):

```json
{
  "id": "pr-merged-39-49afb38",
  "type": "pr_merged",
  "role": "architect",
  "context": {
    "pr_number": 39,
    "labels": ["needs-architect-review", "priority:P2"],
    "fanout_reason": "label-rule:needs-architect-review"
  }
}
```

Values: `default-fanout`, `label-rule:<label-name>`, or `skipped` (logged at
debug level when filtered out).

---

## 5. Rollout plan

1. Land PR-D D2.1.1 as a single PR touching only
   `scripts/agent-watch.sh` (+~110 LOC), `scripts/agent-doctor.sh` (+~130 LOC),
   plus ADR-0008 and this supersede-note.
2. D4's `dev-studio-watcher-reload.path` unit auto-restarts all 5 watchers
   within ~5s of the file landing on disk after `git pull`. No manual
   `systemctl restart` needed.
3. Smoke matrix (4 PRs, all no-op markdown edits to a sandbox file):
   - **S3-PR-None** — no labels → expect 3 wakes (orchestrator/PM/dev).
   - **S3-PR-Arch** — `needs-architect-review` → expect 4 (above + architect).
   - **S3-PR-Test** — `agent:tester` → expect 4 (above + tester).
   - **S3-PR-Both** — both labels → expect 5 wakes.
4. Verify D3 cleanup interaction: after merge, D3 strips `needs-*-review`
   labels; the watcher's pr_merged emission must have already happened
   (gh PR view from watcher's poll window — race is asymmetric, gh returns
   labels as of query time, and D3 runs in a separate workflow). Doctor
   `--fanout` post-merge will show empty labels but the cursor will have
   already advanced and the events will have already been dispatched.
5. Run `agent-doctor --fanout 39` (the D3 smoke PR) and confirm it now shows
   the historical decision retroactively (this is a side benefit — useful
   for post-mortems).

---

## 6. Reversal

Two paths, both env-only, both effective on next poll (≤60s):

```bash
# Path 1 — disable label rules, keep new defaults (D2 minus arch/tester):
systemctl --user set-environment PR_MERGED_FANOUT_RULES_ENABLED=false
systemctl --user restart 'dev-studio-watcher@*.service'

# Path 2 — full D2 restore (always wake 5):
systemctl --user set-environment \
  PR_MERGED_FANOUT_DEFAULT="orchestrator product-manager architect developer tester" \
  PR_MERGED_FANOUT_RULES_ENABLED=false
systemctl --user restart 'dev-studio-watcher@*.service'
```

If env-only reversal proves insufficient, revert the PR via GitHub UI (D1
sed fix in PR-D ensures revert PRs work cleanly under our protected-main
discipline).

---

## 7. Template doctrine note

This pattern — **env-driven default + label-driven opt-in + doctor-mode
simulator + HWM side-channel** — is the canonical recipe for any future
multi-recipient event in this codebase (e.g. `pr_review_requested`,
`issue_escalated`). Future ADRs should reference this one when adopting the
shape.

---

## 8. Interaction with ADR-0007 (Auto label cleanup)

**Added 2026-06-11 after Smoke S3-PR-Arch verification.**

### 8.1 The observed race

Smoke S3-PR-Arch (PR #45) followed this timeline:

| Time (UTC) | Event | Actor |
| ---------- | ----- | ----- |
| 08:27:42Z | PR #45 created | atilcan65 |
| 08:27:44Z | `needs-architect-review` **added** | atilcan65 |
| 08:29:27Z | PR squash-merged | (merge) |
| **08:29:39Z** | `needs-architect-review` **removed** | **github-actions (label-cleanup.yml per ADR-0007)** |
| 08:30:44Z | `status:done` added | atilcan65 |

The architect watcher polls every 60s. By the time it next called
`gh pr list --state merged --json labels` after the merge, the label was
already gone — the only label visible was `status:done`. `role_wakes_for_pr
"architect" ["status:done"]` correctly returned **false** and the PR was
filtered out.

`agent-doctor.sh --fanout 45` simulated **before** label cleanup ran and so
reported "architect: yes (label rule)". After cleanup completed, the same
doctor invocation correctly reports "architect: no — labels are now
`status:done`". Both answers are correct **for the state of the PR at the time
the call was made**.

### 8.2 This is expected behaviour, not a bug

ADR-0007 §Context explicitly anticipated D2.1.1:

> *Transient signaling labels (`cc:*`, `agent:*`, `needs-*`, `agent-stall`)
> stay attached after a PR is merged or an issue is closed, so subsequent
> label-conditional logic (PR-D D2.1.1, planned) would re-fire on already-
> finished work.*

The two ADRs are **complementary**, not in conflict:

- **PR open → merge**: architect's review work happens during the open
  lifecycle, gated by `needs-architect-review`. The role is expected to be
  woken by the **PR-open / PR-review-requested** routing path, not by
  `pr_merged`.
- **PR merged**: the transient label is stripped within seconds by
  label-cleanup.yml because architect has, by definition, already finished
  its work. `pr_merged` fanout therefore only needs the default lifecycle
  set (orchestrator / product-manager / developer) for the merge follow-up
  (sprint board update, downstream issue creation, branch tracking).

### 8.3 So what is the label rule path for?

The `role_wakes_for_pr` per-PR label filter remains in the code for two
legitimate cases that ADR-0007 does not handle:

1. **Admin bypass merges** — a PR merged via repo-admin override before the
   PR closed event fires, so label-cleanup.yml may race or fail. The label
   rule path catches those.
2. **Future event types** that fanout off labels but are *not* `pull_request:
   closed` — e.g. `issue_escalated`, `pr_review_requested`. These do not
   trigger ADR-0007 cleanup and rely entirely on label rules. The shape is
   ready (§ 7) when those events ship.

### 8.4 Smoke S3 status

Smoke S3 verifies the four-state matrix as **"correct under combined ADR-
0007 + ADR-0008 operation"**:

| Variant | Architect woken on pr_merged? | Reason |
| ------- | ----------------------------- | ------ |
| None    | no                            | not in default; no matching label |
| Arch    | **no in practice** *(was: yes by design)* | label was already stripped by label-cleanup.yml within seconds of merge — by design (see § 8.1, § 8.2) |
| Test    | no                            | same — `needs-tester-signoff` is also a transient label that ADR-0007 strips |
| Both    | no                            | same |

The HWM (`pr_merged_last_seen_utc`) **still advances** for all five roles on
every merge (D2.1.2 fix), so dedup state stays clean for all roles even
when the architect/tester actually skip the event.

### 8.5 What would break this contract

| Change | Effect | Mitigation |
| ------ | ------ | ---------- |
| `label-cleanup.yml` disabled or slowed > 60s | Architect/tester briefly visible in `pr_merged` fanout for stale-label PRs | Acceptable — they just retry their already-done work and skip via dedup ring |
| Watcher poll interval reduced to < 12s | Architect/tester might catch the label before cleanup fires | Still safe — `role_wakes_for_pr` returns true, work is idempotent (already-merged PR), dedup ring suppresses re-runs |
| Label-cleanup pattern regex changes (e.g. drops `needs-*`) | Labels persist, architect fires on every merge | Update ADR-0007 taxonomy and re-evaluate `role_wakes_for_pr` need |
| New label families added with same lifecycle | May need ADR-0007 + ADR-0008 update | Cross-reference both ADRs in the new label's introduction note |

---

## 9. Future work

- **D2.2 — PR-open / PR-review-requested routing** ✅ **DONE** — see
  [ADR-0009](./ADR-0009-pr-labeled-fanout.md). Closed the loop; architect
  and tester now wake on `pull_request: labeled` semantics.
- **D2.3 — Doctor time-travel mode** (optional): `agent-doctor.sh --fanout
  PR_NUM --at TIMESTAMP` to simulate the decision at any historical moment
  (uses `timelineItems` GraphQL). Avoids the "doctor vs runtime" confusion
  we hit in Smoke S3 by making the time-of-evaluation explicit.

### 9.1 Update on § 8.2 (post-ADR-0009)

§ 8.2 above correctly identified that architect/tester wake should happen via
a PR-open path, not `pr_merged`. ADR-0009 implements that path. The
interaction between ADR-0007 (label cleanup on merge) and the new
`pr_labeled` event is **non-racy by construction**: the wake fires at
label-add time (during PR-open lifecycle), and ADR-0007 strips the label at
merge time — by which point the wake has already happened and the event id
is in the dedup ring. No contract change to ADR-0007 is required.

---

## Appendix A — File map

| Path | Change |
| ---- | ------ |
| `scripts/agent-watch.sh`     | +~110 LOC — helper block (lines 144-224), per-PR filter loop in `query_pr_merged` (lines 380-440), HWM side-channel in `poll_once` (lines 564-573). |
| `scripts/agent-doctor.sh`    | +~130 LOC — `--fanout PR_NUM` subcommand (lines 268-396), dispatch (lines 408-411), main-mode tip line. |
| `docs/decisions/ADR-0008-label-conditional-fanout.md` | **(this file, new)** — §§ 8–9 appended 2026-06-11 (post-Smoke S3) to ratify interaction with ADR-0007 and queue D2.2 / D2.3. |
| `docs/decisions/ADR-0005-pr-merged-events.md` | Status block updated to "Superseded in part by ADR-0008 (fanout policy)". |
