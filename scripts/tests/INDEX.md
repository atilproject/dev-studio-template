# d-test INDEX — RETRO-008 §11 registry (tmpl local)

> **Sister-pattern home:** RETRO-008 §11 (d-test persistence), ADR-0049 (d-test framework), ADR-0044 (TDD RED contract).
> **Spec origin:** STORY-S28-003 AC4 forward-port (`scripts/tests/d983-s28-003-forward-port-parity.sh` registration).
> **Purpose:** Persistent registry of d-tests specific to STORY-S28-003 forward-port parity. Pre-existing d-tests (d015, d024, d025, d027, d028, d029, d031, d032, d033, d034, d046, d047, d068b, dreg, e2e-pilot, faz5-smoke, state-schema-smoke) are tracked locally but their full INDEX rows live in `AtilCalculator/scripts/tests/INDEX.md` (the originating sister-pattern project) — see calc INDEX for sister coverage.

## d983 — STORY-S28-003 forward-port parity ✅ ACTIVE

| Field | Value |
|---|---|
| **Story** | [STORY-S28-003 #983](https://github.com/atilproject/dev-studio-template/issues/...) *(closes on PR merge — fill post-merge)* |
| **Source-of-truth sister** | `AtilCalculator/scripts/tests/INDEX.md` d983 row |
| **Test file** | `scripts/tests/d983-s28-003-forward-port-parity.sh` |
| **TCs** | **5 TCs (RED-first sister-pattern to ADR-0049 ≥5 invariant):** TC1 tmpl `claim-next-ready.sh` declares `--wip-count-only` flag (Issue #552 dual mechanism — calc-specific); TC2 tmpl `claim-next-ready.sh` has `WIP_COUNT_ONLY` structural handling; TC3 tmpl `claim-next-ready.sh` LOC ≥ calc's (forward-port never strips — Sister Story SemVer invariant); TC4 tmpl `agent-watch.sh` has Event Model v4 marker `issue_comment_mention` (ADR-0017 sister-invariant); TC5 tmpl `agent-watch.sh` has Event Model v6.2 marker `issue_assigned_any_status` (Issue #113 silent-drop closure) |
| **Sister-pattern** | `d031-claim-next-ready.sh` (claim-next-ready base Layer 2 fake-gh factory — DIRECT sister, same `scripts/claim-next-ready.sh` interface); `d052-agent-watch-hardening.sh` (agent-watch hardening — sister scope, parallel tc pattern); ≥2 sister-pattern coverage per ADR-0049 §Sister-pattern met (d031 + d052 = 2 members) |
| **Run** | `bash scripts/tests/d983-s28-003-forward-port-parity.sh` |
| **Cadence Rule 1 atomic** | Single-commit cluster: `scripts/claim-next-ready.sh` (+270 LOC) + `scripts/agent-watch.sh` (+1039 LOC) + `scripts/tests/d983-s28-003-forward-port-parity.sh` (new, 135 LOC) + `scripts/tests/INDEX.md` (new, this entry) |

## Path-resolution decision (STORY-S28-003 open question owner: developer)

> **Decision:** Keep the literal `atilproject/AtilCalculator` references in
> `scripts/agent-watch.sh` line 96 (`# fallback ("atilproject/AtilCalculator")`)
> as a **template placeholder**. Projects cloned from tmpl override via:
>
> 1. `GITHUB_REPO=owner/name` env var (highest precedence), OR
> 2. `gh repo view --json nameWithOwner` auto-detection (works in CI), OR
> 3. `git remote get-url origin` parse (no API calls — works offline), OR
> 4. Hardcoded fallback (only triggers when 1-3 all fail — extremely rare).
>
> Rationale: the literal is downstream-render-stable (init.sh does not edit
> script content) and serves as a visible marker for projects to grep+replace
> post-clone. Calc continues to use the same literal (no drift, sister-pattern
> maintained). Future-proofing option (`${GITHUB_REPO:-atilproject/dev-studio-template}`)
> was considered but deferred — would change behavior for existing tmpl-script
> consumers and requires its own d-test per ADR-0044 RED-first.
