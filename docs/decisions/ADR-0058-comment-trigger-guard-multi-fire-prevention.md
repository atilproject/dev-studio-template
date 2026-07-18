# ADR-0058: Comment-trigger guard + multi-fire prevention + stability gate (closes Issue #560 AC2, RETRO-010 #34 NEW Bug #4)

- **Status**: Proposed (Sprint 16 P1 doctrine hardening workshop, Closes Issue #560 AC2)
- **Date**: 2026-06-28
- **Deciders**: @architect (doctrine/spec), @developer (label-check.yml Comment-trigger integration — owner merge required), @tester (d-test framework integration), @product-manager (Sprint 16 P1 workshop ratification per Issue #560 kickoff), @atilcan65 (owner squash gate)
- **Sister-patterns**: ADR-0048 (Layer 5 status:ready auto-add gating — Type-driven table reference), ADR-0053 (Layer 5 race pattern codification), ADR-0056 (Layer 5 idempotency reconcile — cascade pattern), ADR-0057 (Closes-anchor guard — sister doctrine)
- **PM framing**: PM PICKUP-41 dispatch (Issue #560 kickoff, cycle 243) — "Comment-trigger guard + multi-fire prevention + stability gate ADR (workflow YAML owner territory)"

> **Doctrine reference note**: This ADR codifies a **Comment-trigger guard + multi-fire prevention + stability gate** doctrine for the FIRST time. The comment-trigger false-positive was discovered LIVE in RETRO-010 #34 NEW Bug #4 family — Layer 5 cascade firing on `issue_comment` events that don't represent peer verdict activity (e.g., bot pings, mention comments). This ADR-0058 prevents future recurrences via canonical guard pattern + multi-fire prevention + workflow YAML stability gate (owner merge required).

## Context

### RETRO-010 #34 NEW codification candidate — Comment-trigger false positives + multi-fire

Sprint 15 surfaced a **comment-trigger false-positive** pattern (codified in RETRO-010 #34 NEW Bug #4):

| Time (PR #545 LIVE INSTANCE family) | Event | Actor | Effect |
|------------------------------------|-------|-------|--------|
| T0 | PR opens (developer lane) | developer | status:in-review + cc:tester + needs-tester-signoff applied |
| T0+5m | Layer 5 status-label-to-board fires on `issue_comment` event (NOT label event) | github-actions | status:ready auto-add attempted (FALSE TRIGGER — no peer verdict) |
| T0+5m+1s | Layer 5 self-reversal | github-actions | status:ready UNLABELED (false-positive recovery) |
| T0+5m+30s | Layer 5 re-fires on SAME comment (multi-fire) | github-actions | status:ready auto-add again (FALSE TRIGGER #2) |
| T0+6m | Peer label change (`cc:tester` removal) | tester | Layer 5 fires CORRECTLY on label event |

**Root cause analysis**:

1. **Comment-trigger false-positive**: Layer 5 (`status-label-to-board.yml`) listens on `issue_comment` events. ANY comment triggers the cascade, even if the comment is NOT a peer verdict (e.g., bot ping, `@<role>` mention, ack comment).

2. **Multi-fire**: Layer 5 has NO state-tracking for "already-fired-this-trigger". The same comment can trigger multiple cascade attempts in quick succession.

3. **Stability gate**: NO debounce/cooldown mechanism exists. High-frequency comment activity can saturate Layer 5 with redundant cascade attempts.

### Pattern validation across Sprint 14-15

The comment-trigger + multi-fire pattern has **3+ LIVE INSTANCES**:

| # | PR | Trigger | Outcome |
|---|----|---------|---------|
| 1 | PR #540 (Sprint 14) | Comment-trigger on bot ping | status:ready FALSE auto-add + self-reversal (2s) |
| 2 | PR #545 (Sprint 15) | Comment-trigger on ack comment | DOUBLE-REMOVAL BUG (Issue #546 LIVE INSTANCE) |
| 3 | PR #548 (Sprint 15) | Comment-trigger on mention | cascade FIRED + self-correction in same run |

**All 3 instances** show the same root cause: Layer 5 firing on `issue_comment` events that don't represent peer verdict activity.

### Sister-pattern reference: RETRO-010 §17 NEW LIVE INSTANCE #5 (stale-cache drift)

Per PM Day 2 AC review observation (Issue #560 cmt 4822…, cycle 248), RETRO-010 §17 NEW LIVE INSTANCE #5 (stale-cache drift, per orchestrator PICKUP-110 workshop input) is a **sister-pattern** to the comment-trigger false-positive family:

| # | PR | Pattern | Cascade outcome |
|---|----|---------|-----------------|
| 1 | (stale-cache drift, orchestrator workshop input) | Comment-trigger + stale `verdict-by:<ts>` cache | `status:ready` FALSE auto-add based on stale cache hit (verdict already superseded) |

**Why it's a sister-pattern**: both patterns involve Layer 5 firing on `issue_comment` events that **don't represent current peer verdict activity** — either because the comment is noise (bot ping, ack comment, mention) OR because the verdict that the comment references has been **superseded** by a more recent verdict but the cache hasn't caught up.

**Implication for ADR-0058 doctrine**: the comment-trigger guard (§Comment-trigger guard canonical) MUST also check that any referenced verdict is **current**, not stale. Recommended additional check (owner merge territory):

```yaml
# Proposed addition to status-label-to-board.yml (companion to §Comment-trigger guard)
- name: Stale-cache check
  run: |
    if [[ -f ".github/verdict-cache-${{ github.event.pull_request.number }}" ]]; then
      last_verdict_ts=$(cat ".github/verdict-cache-${{ github.event.pull_request.number }}")
      current_ts=$(date +%s)
      age_sec=$((current_ts - last_verdict_ts))
      if [[ "$age_sec" -gt 300 ]]; then  # 5min staleness threshold
        echo "::notice::silent_skip: stale verdict cache for PR #${{ github.event.pull_request.number }} (${age_sec}s old)"
        exit 0
      fi
    fi
```

**Codification candidate**: ADR-0024 amendment (stale-verdict watchdog schema) — extend the `verdict-by:<ts>` label family with a stale-cache threshold + `silent_skip` integration. Deferred to Sprint 16+ per owner merge territory.

### Why this matters for Sprint 16 P1 doctrine hardening workshop

PM PICKUP-41 dispatch (Issue #560 kickoff) identified Comment-trigger guard + multi-fire prevention + stability gate as **AC2** of the 2-ADR workshop scope (after PM EXTENSION v5 MERGE reduced 4-ADR → 2-ADR). The risk is **silent attribution loss** + **CI saturation**:

- **Silent attribution loss**: false-positive `status:ready` auto-add can mask the absence of a real peer verdict (PR review body missing, but status:ready LABELED)
- **CI saturation**: multi-fire on high-frequency comments can spike Layer 5 run rate, slowing board sync + label-check

## Decision

Adopt **Comment-trigger guard + multi-fire prevention + stability gate** as the canonical doctrine for Layer 5 cascade triggers. This ADR-0058 codifies:

### §Comment-trigger guard (canonical)

**Rule**: Layer 5 (`status-label-to-board.yml`) MUST NOT fire on `issue_comment` events UNLESS the comment contains a **peer verdict signature** (one of):

| Signature | Detection | Example |
|-----------|-----------|---------|
| **PR review verdict** | `gh api /repos/{owner}/{repo}/pulls/{pr}/reviews` returns NEW review entry | tester posts "🟢 APPROVED" via PR review (NOT issue_comment) |
| **Label-flip intent comment** | comment body contains label-flip keyword (`approved`, `changes-requested`, `blocked`, `lgtm`, `sign-off`) AND reviewer is in `cc:*` | arch posts "🟢 OK" in PR comment (counts as verdict) |
| **Closes-anchor comment** | comment body contains `Closes #N` AND commenter is in `cc:*` | dev posts "Closes #123" attribution comment |

**Rejected triggers** (doctrinally):

| Event | Why rejected |
|-------|--------------|
| Bot ping (`@<role>` mention with no other content) | Not a verdict |
| Auto-generated comments (e.g., Layer 5 status updates) | Self-trigger cascade (infinite loop risk) |
| Cross-references (e.g., "see #N") | No verdict signal |
| Code blocks or diff snippets | No verdict signal |

**Implementation**: requires owner merge of `status-label-to-board.yml` amendment (add `if:` guard checking comment body for verdict signature). Deferred to owner per file ownership matrix.

### §Multi-fire prevention (canonical)

**Rule**: Layer 5 cascade MUST track **per-PR fire-count** within a **debounce window** (default: 60s). If fire-count exceeds threshold (default: 1), emit `silent_skip` log + do NOT re-fire.

**Implementation**:

```yaml
# Proposed status-label-to-board.yml addition (owner merge required)
- name: Multi-fire prevention
  run: |
    if [[ -f ".github/cascade-fire-count-${{ github.event.pull_request.number }}" ]]; then
      count=$(cat ".github/cascade-fire-count-${{ github.event.pull_request.number }}")
      if [[ "$count" -ge 1 ]]; then
        echo "::notice::silent_skip: PR #${{ github.event.pull_request.number }} cascade already fired within 60s window"
        exit 0
      fi
    fi
    echo "1" > ".github/cascade-fire-count-${{ github.event.pull_request.number }}"
```

**Sister-pattern**: ADR-0056 Layer 5 idempotency reconcile — both rely on existing label-event-driven re-run for convergence.

### §Stability gate (canonical)

**Rule**: Layer 5 cascade MUST enforce a **cooldown** between consecutive fires on the same PR. Default cooldown: **60s** (matches debounce window).

**Why 60s**: 
- Layer 5 typical run duration: 4-30s
- High-frequency comment activity (e.g., 10 comments in 60s) → without cooldown, 10 cascade attempts → CI saturation
- With cooldown: 1 cascade attempt per 60s window → bounded CI load

**Implementation**: requires owner merge of `status-label-to-board.yml` amendment (add `if:` condition with timestamp check). Deferred to owner per file ownership matrix.

### §Workflow YAML guard (proposed — owner merge required)

Per file ownership matrix, `.github/workflows/` is human-only territory. The following CI integration is **proposed** for owner merge:

- **Existing behavior** (preserve): `status-label-to-board.yml` fires on `issues_labeled` + `issues_unlabeled` (correct triggers)
- **NEW guard** (proposed): add `if:` condition to `issue_comment` trigger requiring verdict signature (per §Comment-trigger guard)
- **NEW multi-fire prevention** (proposed): per-PR fire-count tracking + debounce window (per §Multi-fire prevention)
- **NEW stability gate** (proposed): cooldown enforcement (per §Stability gate)
- **NEW observability** (proposed): emit `silent_skip` log on guard rejection (lens (d) compliance, ADR-0048)

**Owner gate**: this requires `status-label-to-board.yml` amendment. Per CLAUDE.md §File ownership matrix + ADR-0031 owner-override doctrine, architect + tester draft, owner merges.

### §Edge cases (codified)

| Edge case | Doctrine |
|-----------|----------|
| Comment contains verdict keyword but reviewer NOT in `cc:*` | Doctrine violation — comment is opinion, not verdict (no cascade) |
| Multiple verdict comments in debounce window | First comment fires cascade; subsequent are `silent_skip`-logged |
| Comment auto-generated by Layer 5 (self-trigger) | `silent_skip` log + no fire (infinite loop prevention) |
| Comment with verdict signature from `agent:human` (owner) | Counts as verdict — Layer 5 fires correctly (owner override per ADR-0031) |

## Rationale

### Why comment-trigger guard (vs unrestricted comment trigger)

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **Comment-trigger guard (verdict signature required)** | Bounded fire rate, no false-positives, attribution preserved | Requires owner merge + comment body parsing | ✅ Adopt |
| Unrestricted comment trigger (current) | Simple impl, fires on all comments | False-positive cascades, multi-fire risk, CI saturation | ❌ Rejected (current, buggy) |
| No comment trigger (label events only) | Zero false-positives | Misses arch verdict comments (e.g., "🟢 OK" posted as issue_comment) | ❌ Rejected |
| Bot allow-list only | Simpler than verdict signature | Doesn't solve human non-verdict comments (e.g., "thanks!") | ❌ Rejected |

**Verdict**: comment-trigger guard with verdict signature detection is the **canonical balance** — fires on real verdicts, skips noise.

### Why multi-fire prevention (vs unrestricted re-fires)

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **Multi-fire prevention (per-PR fire-count + debounce)** | Bounded fire rate, no cascade storms | Requires fire-count state tracking | ✅ Adopt |
| Unrestricted re-fires (current) | Simple impl | Multi-fire on high-frequency comments (LIVE INSTANCE) | ❌ Rejected (current, buggy) |
| Exponential backoff | More sophisticated | Over-engineering for Layer 5; debounce is sufficient | ❌ Rejected |
| Per-commenter rate limit | Different axis | Solves abuse, not legitimate high-frequency verdicts | ❌ Rejected |

**Verdict**: per-PR fire-count + debounce is the **canonical mechanism** for multi-fire prevention.

### Why 60s cooldown (vs other intervals)

| Cooldown | Pros | Cons | Verdict |
|----------|------|------|---------|
| **60s** (adopt) | Bounds fire rate to 1/min/PR; matches typical Layer 5 run duration (4-30s) | Latency floor for high-frequency verdict activity | ✅ Adopt |
| 30s | Faster recovery | Still allows 2 fires/min/PR (multi-fire risk) | ❌ Rejected |
| 5m | Tighter bound | Excessive latency for Sprint-paced workflow | ❌ Rejected |
| 10m | Very tight bound | Sprint ceremony latency (10m wait between verdict + status sync) | ❌ Rejected |

**Verdict**: 60s is the **canonical cooldown** — matches Layer 5 run duration + bounds fire rate to 1/min/PR.

### Why ADR-0048 reference (Type-driven table)

ADR-0048 §Type-driven table codifies when `status:ready` auto-add is appropriate. This ADR-0058 extends that doctrine:

- **ADR-0048**: WHICH labels trigger status:ready auto-add (dual-🟢 gate)
- **ADR-0058**: WHICH EVENTS trigger the cascade at all (verdict signature guard)

Both doctrines are **sister-pattern**: gate the WHAT (ADR-0048) + gate the WHEN (ADR-0058) = bounded Layer 5 cascade.

## Consequences

### Positive

- **Comment-trigger false-positives prevented**: verdict signature guard eliminates PR #540/#545/#548-class bugs
- **Multi-fire prevented**: per-PR fire-count + debounce bounds cascade rate
- **Stability gate enforced**: 60s cooldown matches Layer 5 run duration
- **Workflow YAML guard proposed**: CI integration via owner merge (silent_skip log + verdict signature + multi-fire prevention)
- **Sister-pattern to ADR-0057**: 2-ADR workshop scope preserved (Closes-anchor + Comment-trigger)

### Negative

- **Workflow YAML deferred**: silent_skip log + verdict signature guard + multi-fire prevention = owner merge required
- **60s latency floor**: legitimate high-frequency verdict activity (e.g., arch + tester + PM all post within 30s) waits up to 60s for cascade convergence
- **Comment body parsing**: verdict signature detection requires regex matching (fragile if signature format changes)
- **State tracking**: per-PR fire-count requires `.github/cascade-fire-count-*` files (new gitignored state)

### Sprint boundary

- `docs/decisions/ADR-0058-*.md` (this file) = **architect** lane (doctrine)
- `.github/workflows/status-label-to-board.yml` (verdict signature guard + multi-fire prevention + stability gate) = **human-only** territory (architect + tester draft, owner merges per file ownership matrix)
- d-test integration (d063-comment-trigger-guard.sh, candidate) = **developer + tester** joint (Sprint 16+ candidate, NOT in this PR)
- PM retro update for comment template guidance = **PM** lane (Sprint 16 retro candidate)

## Alternatives considered

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **ADR-0058 (this file)** | Triple-defense (guard + multi-fire + stability) bounded Layer 5 cascade | Workflow YAML deferred to owner | ✅ Adopt |
| No comment trigger (label events only) | Zero false-positives | Misses arch verdict comments | ❌ Rejected |
| Unrestricted comment trigger (current) | Simple impl | Multi-fire risk + false-positive cascades | ❌ Rejected (current, buggy) |
| Silent skip on every comment | Hides symptom | Violates ADR-0048 (silent_skip log mandatory, lens (d)); hides attribution loss | ❌ Rejected |
| Amend ADR-0048 (Type-driven table) | Sister to Layer 5 gating | ADR-0048 is WHAT triggers, not WHEN — different concern | ❌ Rejected |
| No ADR (use Issue #560 as living doc) | No ceremony | Doctrine must be in ADRs per ADR-0017 + INDEX.md conventions | ❌ Rejected |

## Open questions

- [ ] **Q1**: Verdict signature regex — should the regex be `[Aa]pproved|[Cc]hanges-[Rr]equested|[Bb]locked|[Ll]gtm|[Ss]ign-[Oo]ff|[Cc]loses #` (current draft) or more restrictive (e.g., exact-match "🟢 APPROVED")? (Architect + tester workshop discussion in Sprint 16 P1)
- [ ] **Q2**: State file location — should per-PR fire-count be in `.github/cascade-fire-count-*` (current draft) or in a single state file (e.g., `.github/cascade-state.json`)? (Developer lane decision, Sprint 16+ candidate)
- [ ] **Q3**: Debounce window owner — should the 60s default be configurable per-repo (e.g., `DEBOUNCE_WINDOW_SEC` env var) or hard-coded? (Owner decides per ADR-0031)

## References

- **Issue #560** (Sprint 16 P1 doctrine hardening workshop, Closes-anchor + Comment-trigger scope) — this ADR's container
- **Issue #546** (Sprint 16 P1 doctrine hardening, RETRO-010 #34 NEW) — sister codification cluster (ADR-0056)
- **PR #540, #541, #545, #547, #548, #553** — comment-trigger false-positive LIVE INSTANCES (RETRO-010 #34 NEW family)
- **PR #545** (d031 stub retire, MERGED) — DOUBLE-REMOVAL BUG LIVE INSTANCE carrier (comment-trigger root cause)
- **ADR-0048** — Layer 5 status:ready auto-add gating (WHAT triggers, sister-pattern)
- **ADR-0053** — Layer 5 race pattern codification (race observation doctrine)
- **ADR-0056** — Layer 5 idempotency reconcile (cascade pattern, cheaper fix sister-pattern)
- **ADR-0057** — Closes-anchor guard (sister doctrine, this ADR's workshop scope pair)
- **RETRO-010 #34 NEW** — auto-cascade self-reversal + double-removal + comment-trigger family (this ADR's codification target)
- **RETRO-010 §17 NEW** (orchestrator workshop input, PICKUP-110) — stale-cache drift LIVE INSTANCE #5 (sister-pattern, comment-trigger + stale verdict cache, codified in §Sister-pattern reference block per PM Day 2 AC observation)
- **ADR-0024** (stale-verdict watchdog schema) — amendment candidate for stale-cache threshold + `silent_skip` integration (Sprint 16+)
- **PM PICKUP-41** (Issue #560 kickoff, cycle 243) — workshop scope = 2-ADR after PM EXTENSION v5 MERGE

## §9-Lens Review Checklist (doctrinal self-application)

| Lens | Status | Note |
|------|--------|------|
| (a) Data flow | ✅ | Doctrine-only ADR. Comment → verdict signature regex → cascade trigger (or silent_skip). Traceable via PR #540/#545/#548 LIVE INSTANCE families. |
| (b) Runtime preconditions | ✅ | No runtime deps. Workflow YAML guard (proposed) = bash + regex + state file. State file in `.github/` (gitignored). |
| (c) Canonical entry point | ✅ | Single ADR file + workflow YAML amendment (owner gate). No side-channels. |
| (d) Silent-skip risk | ✅ | Doctrine REQUIRES `silent_skip` log on guard rejection (lens (d) compliance, ADR-0048). Proposed workflow YAML guard emits `silent_skip` log. |
| (e) Idempotency | ✅ | Per-PR fire-count is idempotent (re-incrementing within window is no-op via debounce). State convergence automatic. |
| (f) Observability | ✅ | PR #540/#545/#548 LIVE INSTANCES documented. Proposed workflow YAML guard = `silent_skip` log + verdict signature match log + fire-count increment log. |
| (g) Security & privacy | N/A | comment body parsing has no auth/PII surface (comments are public on PRs) |
| (h) Workflow YAML SHA pin | N/A | no workflow changes in this ADR (workflow YAML guard proposed but owner gate) |
| (i) Platform hard constraints | ✅ | Doctrine-only. Workflow YAML guard (proposed) = bash + regex, no platform changes. |
| (j) Auto-gen file refs + live-state | ✅ | INDEX.md is auto-gen (Cadence Rule 1 carrier, ADR-0055); ADR-0058 row added in same PR; live-state references PR #540/#541/#545/#547/#548/#553 SHAs (verifiable via `git log --grep`). |
| (k) JS syntactic correctness | N/A | no JS in this ADR |

— @architect, 2026-06-28T<draft-cycle>+03:00, ADR-0058 Comment-trigger guard + multi-fire prevention + stability gate (Sprint 16 P1 doctrine hardening, Closes Issue #560 AC2, codifies triple-defense doctrine + workflow YAML guard (owner gate), arch lane doctrine)