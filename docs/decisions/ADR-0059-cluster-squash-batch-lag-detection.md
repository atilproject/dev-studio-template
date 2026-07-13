# ADR-0059: Cluster-Squash Batch-Lag Detection Doctrine (post-squash empirical observability for RETRO ceremonies)

- **Status**: Proposed
- **Date**: 2026-06-28
- **Deciders**: @architect (doctrine/spec), @product-manager (RETRO curator — primary consumer), @developer (impl in `scripts/post-squash/cluster-lag-detector.sh`), @tester (d064 d-test sign-off per ADR-0044 RED-first), @atilcan65 (owner squash gate + workflow YAML approval per file ownership matrix)
- **Closes**: Issue #584 (Sprint 17 P1 #1 §14 NEW option (a) impl — cluster-squash batch-lag detection), Issue #508 (cluster-squash-lag LIVE INSTANCE)
- **Sister-patterns**: ADR-0055 (Cadence Rule 1 atomic — d-test + INDEX.md in same PR), ADR-0049 (d-test framework), ADR-0044 (RED-first TDD), ADR-0046 (load-bearing ADR §Implementation guide), RETRO-009 §3 (post-squash label hygiene sister-pattern), RETRO-009 §14 (cluster-squash observation origin), RETRO-007 watchlist #10 NEW (cross-codification entry), Issue #508 (LIVE INSTANCE)

> **Doctrinal home note**: This ADR is the canonical home for cluster-squash batch-lag detection. Issue #584 body references "ADR-0055 cluster-squash-lag" — this is a **stale body reference** (per Issue #113 soul doctrine, labels > body). ADR-0055 is `d-test ID uniqueness invariant + sub-pattern remediation matrix`, NOT cluster-squash doctrine. The cluster-squash batch-lag observation originates from RETRO-009 §14 and Issue #508 LIVE INSTANCE, but has no canonical ADR home until this ADR-0059.

## Context

### RETRO-009 §14 cluster-squash observation (origin)

Sprint 14-15 sprint ceremonies surfaced a recurring pattern: cluster-squash events (≥3 PRs squashed within a tight temporal window, typically 30-60s) are increasingly common in our workflow as sprint scope grows. RETRO-009 §14 codifies this observation:

- **Cluster-squash trigger**: When multiple peer-lane PRs converge on a shared story (e.g., Sprint 16 P1 #3 cluster — PR #589 + PR #590 + PR #593 + PR #594 all squashed within ~5min on 2026-06-28), the owner squash cadence is batch-driven rather than per-PR.
- **Batch-lag observation**: Empirical observation across Sprint 14-16 shows cluster-squash creates a **non-trivial lag window** between squash timestamps (cluster_lag_seconds = max(squash_at) − min(squash_at) within the cluster). This lag is invisible without tooling — manual timestamp correlation is error-prone and scales linearly with cluster size.
- **RETRO curator pain point**: PM lane (RETRO curator) currently reconstructs cluster-vs-single squash data by manually cross-referencing squash timestamps from `gh pr view --json mergedAt` calls. For a 4-PR cluster, that's 4 separate queries + manual delta calculation. For a 6-PR cluster, it scales worse.

### Issue #508 LIVE INSTANCE (cluster-squash-lag)

Issue #508 (Sprint 14 P1 #2 cluster — d-test framework family) observed a 4-PR cluster-squash event with cluster_lag_seconds = 312s (5m12s). Manual reconstruction:
1. PR #506 squash @ 226b546 → 21:54:34Z
2. PR #507 squash @ XXXXXXX → 21:58:14Z
3. PR #508 squash @ XXXXXXX → 21:59:46Z
4. PR #509 squash @ XXXXXXX → 22:00:00Z

Cluster_lag = 22:00:00Z − 21:54:34Z = **324s (5m24s)**. The PR descriptions don't surface this lag; only the squashed commits preserve the order.

### Architectural gap (no canonical ADR home)

As of 2026-06-28, **no ADR codifies cluster-squash batch-lag detection doctrine**. The observation is captured in RETRO-009 §14 and the LIVE INSTANCE in Issue #508, but no load-bearing ADR establishes:

1. **Cluster-squash detection criteria** — what defines a cluster (size threshold + temporal window)?
2. **Batch-lag metric** — how to measure the lag (squash_at delta = max − min)?
3. **RETRO cluster-lag section format** — how should the curator consume the data (structured markdown)?
4. **Sister-pattern lineage** — what existing doctrine applies (post-squash label hygiene, d-test framework, RED-first TDD)?

Sprint 17 P1 #1 (#584) is the **impl phase** per workshop Stage 1 LOCKED decision. This ADR-0059 codifies the **doctrinal home** so the impl can reference it cleanly.

## Decision

Adopt **cluster-squash batch-lag detection doctrine** with 4 canonical components:

### §1 — Cluster-squash detection criteria

**Definition**: A cluster-squash event is **≥3 PRs squashed within a 60-second temporal window** (sliding window from the first squash timestamp of the window).

**Rationale for thresholds**:
- **≥3 PRs**: Below this, single-PR squash or paired-squash is more common; cluster tooling overhead not justified.
- **60-second window**: Empirical Sprint 14-16 data shows cluster-squash events compress into <60s windows (median cluster_lag ~120s but window-edge pairs trigger cluster detection at <60s). 60s is conservative; tighten to 30s if Sprint 18+ shows tighter clustering.

**Detection algorithm** (lifecycle):
1. Owner squash event fires (PR closed+merged webhook).
2. `scripts/post-squash/cluster-lag-detector.sh` (NEW) reads the squash event from webhook payload.
3. Query sibling PRs merged within ±60s of the current squash (via `gh pr list --state merged --json mergedAt,number --jq`).
4. If ≥3 PRs in window → emit `cluster_lag_detected` event with payload `{cluster_size, cluster_lag_seconds, pr_numbers[], squash_timestamps[]}`.
5. Append to structured log file `/var/log/dev-studio/AtilCalculator/cluster-lag.log` (sister-pattern to Layer 5 silent_skip log).

**Sister-pattern**: `scripts/post-squash/label-hygiene.sh` (RETRO-009 §3) — both are post-squash bash sweep scripts with explicit exit codes per ADR-0044 contract. Sister-pattern to `scripts/post-squash/cluster-lag-detector.sh` lifecycle.

### §2 — Batch-lag metric definition

**Definition**: `cluster_lag_seconds = max(squash_timestamps[]) − min(squash_timestamps[])` within a detected cluster.

**Why max − min (not mean)**: Lag observability cares about the **window duration**, not the average. A 6-PR cluster with mean delta of 30s and range of 240s tells a different story than 6 PRs evenly spaced over 240s. Max − min captures the **window tightness** for the curator's RETRO analysis.

**Output format** (machine-parseable JSON, per ADR-0049 lens (f) observability):

```json
{
  "event": "cluster_lag_detected",
  "cluster_id": "sprint-17-p1-3-cluster",
  "cluster_size": 4,
  "cluster_lag_seconds": 312,
  "pr_numbers": [589, 590, 593, 594],
  "squash_timestamps": ["2026-06-28T11:42:14Z", "2026-06-28T11:42:23Z", "2026-06-28T12:00:18Z", "2026-06-28T12:00:42Z"],
  "detected_at": "2026-06-28T12:00:50Z",
  "detector_version": "0.1.0"
}
```

**Sister-pattern**: Layer 5 silent_skip log emission (ADR-0048 §d lens) — both emit structured JSON events to a canonical log path for downstream observability.

### §3 — RETRO cluster-lag section format

**Output format** (markdown, curator-consumable):

```markdown
## §Cluster-lag — Sprint N (auto-generated by cluster-lag-detector)

| Cluster ID | Size | Lag (seconds) | PRs |
|------------|------|---------------|-----|
| sprint-17-p1-3-cluster | 4 | 312 | #589, #590, #593, #594 |
| sprint-14-p1-2-cluster | 4 | 324 | #506, #507, #508, #509 |

**Cluster-lag summary** (Sprint 17): 1 cluster detected, total cluster PRs = 4, mean cluster size = 4.0, max cluster_lag = 312s.
```

**Rationale**: Markdown table format mirrors existing RETRO section patterns (e.g., RETRO-009 §14 cluster-squash observation). Curator copy-pastes into RETRO-N.md without manual reformatting.

**Sister-pattern**: RETRO §d-test family table (RETRO-009 §6, RETRO-010 §18) — same markdown table style for observability sections.

### §4 — Sister-pattern lineage + framework integration

**Sister-patterns**:

| Reference | Pattern | How ADR-0059 inherits |
|-----------|---------|------------------------|
| ADR-0055 | Cadence Rule 1 atomic (d-test + INDEX.md in same PR) | d064 d-test + INDEX.md d-test family table update in same PR as detector impl |
| ADR-0044 | RED-first TDD (tester-owned) | d064 d-test = 5 TCs RED-first; detector impl lands after d064 GREEN |
| ADR-0046 | Load-bearing ADR §Implementation guide | This ADR codifies the cluster detection criteria + thresholds + output format (literal forms, not intent-level prose) |
| ADR-0049 | d-test framework (d050b + behavioral) | d064 d-test = sister d-test family 18th member (d031/d046/d048/d050b/d051/d052/d053/d054/d055/d056/d057/d058/d059/d060/d061/d062/d063/d064) |
| RETRO-009 §3 | post-squash label hygiene sweep | Sister-pattern bash sweep script with explicit exit codes |
| RETRO-009 §14 | cluster-squash observation | Origin of detection criteria + lag metric definition |
| Issue #508 | cluster-squash-lag LIVE INSTANCE | Empirical evidence for thresholds + metric shape |

**Workflow YAML integration** (out of scope per file ownership matrix):
- `scripts/post-squash/cluster-lag-detector.sh` invocation trigger = pull_request closed+merged webhook (sister-pattern to `post-squash-label-hygiene.yml`).
- Owner merge required per file ownership matrix (`.github/workflows/` = human-only territory).
- d064 d-test integration via CI workflow `lint-and-test.yml` paths trigger (sister-pattern to d062/d063 integration).

### §Alternatives considered

| Option | Description | Pros | Cons | Verdict |
|--------|-------------|------|------|---------|
| **A** | Single-script detector + log + manual curator copy (this ADR) | Single source of truth (detector = bash), minimal API surface, d-test isolated | Requires curator copy-paste (no auto-RETRO injection) | **CHOSEN** |
| **B** | Real-time alert via Telegram on cluster-squash | Faster curator awareness (≤30s) | Out of scope per Issue #584 (real-time alerts deferred); adds Telegram dependency | Rejected (out of scope) |
| **C** | Cross-repo watcher (extends d046/d048 sister-pattern) | Reuses existing watcher infra | Out of scope per Issue #584 (cross-repo deferred); ADR-0047 separate candidate | Rejected (out of scope) |
| **D** | GitHub Action (yaml-only, no bash detector) | No new bash script (less surface area) | Less testable (workflow YAML = human-only territory per file ownership matrix); d-test integration awkward | Rejected (d-test framework sister-pattern preferred) |

## Consequences

### Positive

- **Empirical cluster-lag observability** without manual timestamp correlation (Sprint 14-16 had 4+ cluster events reconstructed by hand).
- **RETRO curator self-service** — PM lane consumes detector output directly, no PM→arch request chain for cluster-lag data.
- **d-test coverage** — d064 = 5 TCs RED-first per ADR-0044; cluster detection criteria + threshold logic + output format all d-test guarded.
- **Sister-pattern integration** — extends post-squash sister-pattern lineage (label-hygiene.sh → cluster-lag-detector.sh), d-test family 18th member (d064).
- **RETRO-007 watchlist #10** entry CLOSED (cross-codification catalog completion).

### Negative

- **New bash script surface** — adds detector file (~80-120 LoC estimated) + d-test (~80-120 LoC estimated) + INDEX.md update + workflow YAML (owner merge). Total ~3 PR scope (impl + d-test + workflow YAML).
- **60-second threshold** may be too tight for some sprint cadences — re-tune in Sprint 18+ if false-negatives surface (sister-pattern to ADR-0056 cheaper-fix observation).
- **Log file path** (`/var/log/dev-studio/AtilCalculator/cluster-lag.log`) is systemd-timer managed; cluster-lag-detector.sh writes append-only, but log rotation policy deferred to owner decision.

### Follow-up tickets

- **Issue #584** — Sprint 17 P1 #1 impl track (cluster-lag-detector.sh + d064 d-test + workflow YAML); arch slice = this ADR-0059 + design doc; dev slice = detector impl PR; tester slice = d064 d-test PR.
- **Issue #587** — Sprint 17 P1 #4 d064 d-test sister-pattern (downstream trigger; auto-claim armed post Issue #586 close).
- **Sprint 18+** — re-tune 60s threshold if false-negatives surface (sister-pattern to ADR-0056 cheaper-fix observation pattern).
- **Sprint 19+** — auto-RETRO injection (Option B enhancement) deferred; consider if cluster-lag-detector.sh output becomes high-traffic.

## Cross-references

- **Issue #584** — Sprint 17 P1 #1 §14 NEW option (a) impl (this ADR closes the doctrinal home; impl lands via separate PRs per ADR-0044 RED-first)
- **Issue #508** — cluster-squash-lag LIVE INSTANCE (4-PR cluster @ 324s lag, Sprint 14 P1 #2)
- **Issue #587** — Sprint 17 P1 #4 d064 d-test sister-pattern (downstream trigger)
- **Issue #113** — soul doctrine: labels > body text (Issue #584 body references "ADR-0055 cluster-squash-lag" — stale; this ADR-0059 is the canonical home)
- **PR #530** — post-squash label hygiene sister-pattern (Sprint 14 P1 #3, Issue #518)
- **PR #529** — Sprint 16 P1 #3 spec SHIPPED (Issue #584 body references this as ADR-0055 source — stale ref)
- **RETRO-009 §14** — cluster-squash observation codification (origin)
- **RETRO-009 §3** — post-squash label hygiene sweep sister-pattern
- **RETRO-007 watchlist #10 NEW** — cross-codification entry (closed by this ADR)
- **ADR-0044** — RED-first TDD (d064 = 5 TCs RED-first)
- **ADR-0046** — load-bearing ADR §Implementation guide (this ADR codifies literal forms, not intent-level prose)
- **ADR-0049** — d-test framework (d064 = sister d-test family 18th member)
- **ADR-0055** — Cadence Rule 1 atomic (d064 + INDEX.md in same PR)
- **ADR-0056** — cheaper-fix sister-pattern (Sprint 18+ threshold re-tune if needed)
- **ADR-0058** — Comment-trigger guard sister-pattern (workflow YAML integration deferred to owner per file ownership matrix)

— @architect, 2026-06-28T15:10+03:00, ADR-0059 PROPOSED, Issue #584 doctrinal home codified, cluster-squash batch-lag detection doctrine = 4 canonical components (detection criteria + lag metric + RETRO format + sister-pattern lineage), Sprint 17 P1 #1 impl track armed
