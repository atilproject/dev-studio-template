# ADR-0040: Cross-repo PR auto-close pattern — `scripts/cross-repo-close.sh` (Option B)

## Status
Proposed

## Date
2026-06-23

## Deciders
- @architect (drafted per Issue #293 v2 design, 2026-06-23T11:38Z comment by orchestrator)
- @orchestrator (design owner)
- @owner (approver — CI workflow change is owner-only territory per file ownership matrix)
- @developer (impl — Sprint 6 #293 Phase 3)
- @tester (regression — Sprint 6 d035)

## Context

Sprint 5 retrospective (PR #292, 2026-06-23) captured a **cross-repo PR auto-close** gap:

- Sprint 5 PRs in `atilcan65/dev-studio-template` referenced AtilCalc issues via "Closes #N" syntax.
- **Cross-repo PRs cannot auto-close issues in a different repo** (GitHub limitation — `gh` close only works in the same repo).
- Orchestrator had to **manually close** 2 AtilCalc issues (#272, #287) post-merge with explanatory comments.
- Sprint 6 will have ≥2 more cross-repo items (#290 template port + #291 dev impl sub-task). Sprint 7+ has more (full template parity is a stated goal per RETRO-003).

Issue #293 (P2, status:backlog, agent:orchestrator) proposed 3 options:
- **Option A**: Manual close + comment convention (status quo, document)
- **Option B**: Bridge script `scripts/cross-repo-close.sh` with multi-repo PAT
- **Option C**: External issue tracker convention

Architect arch review on #293 (comment 4778493438) recommended **Option B** with 5 security caveats. Orchestrator adopted Option B (comment 4778117427 second iteration at 2026-06-23T11:38Z).

## Decision

We will adopt **Option B**: `scripts/cross-repo-close.sh` bridge script that reads "Closes <repo>#N" syntax from PR body, uses a dedicated `CROSS_REPO_CLOSE_TOKEN` PAT, and runs in CI on `pull_request.closed` events.

### Script contract

**Invocation**:
```bash
# Triggered automatically by CI workflow on PR merge
bash scripts/cross-repo-close.sh

# Manual dry-run
bash scripts/cross-repo-close.sh --dry-run
```

**Inputs**:
- PR body: looks for `Closes <org>/<repo>#N` and `Fixes <org>/<repo>#N` patterns
- Environment: `CROSS_REPO_CLOSE_TOKEN` (dedicated PAT), `PR_NUMBER`, `REPO`, `ORGs`

**Outputs**:
- For each foreign-repo issue referenced: `gh api -X PATCH /repos/{org}/{repo}/issues/{N}` with `state: closed`
- Audit log entry: `/var/log/dev-studio/cross-repo-close.log`
- PR comment: confirms auto-close actions

### Security caveats (5, architect-mandated)

#### 1. Dedicated PAT (CRITICAL)

```yaml
# In .github/workflows/cross-repo-close.yml
env:
  CROSS_REPO_CLOSE_TOKEN: ${{ secrets.CROSS_REPO_CLOSE_TOKEN }}
```

- **NOT** the main `PROJECT_TOKEN`. Create separate `CROSS_REPO_CLOSE_TOKEN`.
- Scoped: `contents:write` + `issues:write` only (NOT `repo` admin).
- Per-repo access: AtilCalc + dev-studio-template only.
- Rotation: quarterly (calendar reminder).
- Audit: every close action writes to log.

#### 2. CI-only execution

- Script runs in GitHub Actions workflow on `pull_request.closed` event with `action: closed`.
- **NOT** in agent runtime — avoid agent-side PAT leakage.
- CI workflow file: `.github/workflows/cross-repo-close.yml` (owner-only territory per file ownership matrix).

#### 3. Idempotent guard

```bash
STATE=$(gh issue view "$ISSUE_NUM" --repo "$FOREIGN_REPO" --json state --jq '.state')
if [[ "$STATE" == "CLOSED" ]]; then
  echo "[skip] $FOREIGN_REPO#$ISSUE_NUM already closed"
  exit 0
fi
```

Prevents double-close race in parallel merges.

#### 4. Graceful degradation

```bash
if [[ -z "$CROSS_REPO_CLOSE_TOKEN" ]]; then
  echo "[warn] CROSS_REPO_CLOSE_TOKEN missing — manual close needed"
  gh pr comment "$PR_NUMBER" --body "⚠️ cross-repo close deferred: $ISSUE_REFS. Manual close required."
  exit 0  # NOT exit 1 — never block PR merge
fi
```

Never blocks PR merge on cross-repo close failure.

#### 5. Dry-run mode

```bash
if [[ "$1" == "--dry-run" ]]; then
  echo "[dry-run] Would close: $ISSUE_REFS"
  exit 0
fi
```

Useful for PR review (lists what would close without executing).

### d035 regression test plan (6 TUs)

| TU | Scenario | Expected |
|---|---|---|
| 1 | Template PR closes AtilCalc issue (normal case) | Both closed, audit log entry |
| 2 | AtilCalc PR closes template issue (reverse direction) | Both closed, audit log entry |
| 3 | Multi-PR same issue (idempotency) | First closes, second is no-op |
| 4 | Missing PAT (graceful degradation) | Warning logged, manual close comment, exit 0 |
| 5 | Rate-limit hit (HTTP 429) | Warning logged, retry once, then manual close comment |
| 6 (bonus) | Dry-run mode | Lists actions without executing |

### CI workflow design (owner-only territory)

```yaml
# .github/workflows/cross-repo-close.yml
name: cross-repo-close
on:
  pull_request:
    types: [closed]
jobs:
  cross-repo-close:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/cross-repo-close.sh
        env:
          CROSS_REPO_CLOSE_TOKEN: ${{ secrets.CROSS_REPO_CLOSE_TOKEN }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
          REPO: ${{ github.repository }}
```

**File ownership**: `.github/workflows/` is human-only territory per `.claude/CLAUDE.md`. Owner must approve + apply this workflow file.

## Consequences

### Positive

1. **Constant-overhead solution** — Sprint 6 has ≥2 cross-repo items, Sprint 7+ more. Bridge script overhead is **constant** (zero per-PR work after initial setup).
2. **Eliminates manual close ops** — Sprint 5 had 2 manual close ops (5 min orchestrator time). Sprint 6+ will scale.
3. **Belt + suspenders** — Companion to existing "Cross-ref: org/repo#N" comment convention from Option A. Both layers needed (script automation + convention documentation).
4. **Idempotent + graceful** — Safe to run on every merge without race conditions or merge-blocking failures.

### Negative

1. **Multi-repo PAT is a security surface** — Dedicated `CROSS_REPO_CLOSE_TOKEN` must be:
   - Quarterly rotated (calendar reminder)
   - Audited (every close logged)
   - Scoped minimally (no `repo` admin)
2. **CI workflow is owner-only territory** — Per file ownership matrix (`.github/workflows/`). Owner must approve + apply. Slower than agent-authored.
3. **Test fixture complexity** — d035 TUs need cross-repo test fixtures. Tester needs both repos accessible in CI.
4. **GitHub API rate-limit dependency** — Per-issue API call. Cross-repo PRs with N references = N API calls. Mitigation: batch operations where possible; degrade gracefully on rate-limit.

### Follow-up tickets

- Issue #293 (P2, orchestrator + architect + developer) — Sprint 6 phased impl
- Issue #290 (P1, developer) — template port of `cross-repo-close.sh`
- Issue #272 + #287 — already manually closed in Sprint 5, will be retroactively covered by d035 TUs
- d035 regression — 6 TUs (5 + 1 bonus)
- Owner action: provision `CROSS_REPO_CLOSE_TOKEN` PAT, apply `.github/workflows/cross-repo-close.yml`

## Doctrinal alignment

- **Issue #293** (orchestrator design, status:backlog) — implements this ADR
- **PR #272** (template #57, Sprint 5) — first observed case of cross-repo close gap
- **PR #287** (template #56, Sprint 5) — second observed case
- **Issue #238** (P0 doctrine chain, closed) — auto-claim + doctrine combo exposed the gap
- **RETRO-003** (Sprint 3 retro) — full template parity stated goal
- **RETRO-004** (Sprint 4 retro, PR #282) — Sprint 5 template port work
- **PR #292** (Sprint 5 close summary) — captured the lesson formally

## Sprint 6 phasing (1.5 SP total)

| Phase | Item | Owner | SP | Status |
|---|---|---|---|---|
| 1 | Architect recommends Option A/B/C | architect | 0.25 | ✅ Done (comment 4778493438) |
| 2 | **ADR-NNNN-cross-repo-close.md (this ADR)** | architect | 0.25 | ✅ Done (this document) |
| 3 | Implement `scripts/cross-repo-close.sh` | developer | 0.5 | ⏳ Sprint 6 |
| 4 | Wire to CI workflow + provision PAT | owner | 0.25 | ⏳ Owner gate |
| 5 | d035 regression 6/6 PASS | tester | 0.25 | ⏳ Sprint 6 |

## References

- Issue #293 (orchestrator design + 3 options)
- Arch review comments: 4778493438 (Option B recommendation + 5 security caveats), 4778117427 (sister #289 review)
- Orchestrator ack: 2026-06-23T11:38Z comment (Option B adopted)
- Sprint 5 cross-repo PRs: #57, #56 (template → AtilCalc)
- Sprint 5 manual closes: #272, #287 (orchestrator post-merge)
- File ownership matrix: `.claude/CLAUDE.md` §File ownership matrix

— @architect, 2026-06-23T13:00Z, drafted per Issue #293 v2 design + arch review 4778493438 + orchestrator ack 2026-06-23T11:38Z.