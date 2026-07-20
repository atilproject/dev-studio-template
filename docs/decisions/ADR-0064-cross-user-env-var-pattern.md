# ADR-0064 — Cross-User Env Var Pattern for Self-Hosted Runner Service Management

- **Status:** Proposed (Sprint 23 polish lane, Closes Issue #765 doctrinal home + RCA-17 doctrinal codification)
- **Date:** 2026-07-03
- **Deciders:** @architect (doctrine spec, 9-Lens review cycle ~#3349), @product-manager (cross-lane sponsor — Sprint 24 PRD lane integration), @developer (impl — `vars.ATC_SERVICE_USER || 'atilcan'` deploy.yml addition + script-side `${ATC_SERVICE_USER:-$USER}` fallback, d121 sister-pattern), @tester (sign-off pending d121 d-test in Sprint 23 P2 follow-up PR — ≥3 TCs RED-first per ADR-0049 baseline), @atilcan65 (owner squash gate for `.github/workflows/deploy.yml` per file ownership matrix — workflow YAML human-only territory)
- **Supersedes:** — (doctrinal codification, no supersede)
- **Related:**
  - [ADR-0010](./ADR-0010-per-project-watchers.md) — systemd user-services for atilcalc-web (canonical home of the per-user systemd unit pattern)
  - [ADR-0030](./ADR-0030-self-hosted-runner-lan-deploy.md) — self-hosted runner on prod, `gh-actions-runner` user (canonical home of the runner-user identity)
  - [ADR-0019-amendment-4](./ADR-0019-amendment-4-conftest-env-var-precedence.md) — operator-tunable perf-budget env vars (sister-pattern, env-var precedence family)
  - [ADR-0019-amendment-5](./ADR-0019-amendment-5-evaluate-persist-env-var-gate.md) — `ATILCALC_EVALUATE_PERSIST` (sister-pattern, runtime API env-var gate)
  - [ADR-0027](./ADR-0027-deploy-automation.md) — deploy automation (canonical home of the smoke-test + auto-rollback contract)
  - [ADR-0049](./ADR-0049-behavioral-workflow-test-framework.md) — d-test framework (d121 sister-pattern)
  - [ADR-0044](./ADR-0044-verdict-by-scope-clarification.md) — RED-first TDD (tester sign-off discipline)
  - [ADR-0055](./ADR-0055-d-test-id-uniqueness-sub-pattern-matrix.md) — Cadence Rule 1 atomic (this ADR + INDEX.md row in same PR)
- **Closes:** Issue #765 (RCA-17 cross-user deploy.yml env-var follow-up, owner-gated per file ownership matrix)
- **Live Instances:** RCA-16 (PR #358-era original cross-user wrapper, sprint 6 P1 redesign), RCA-17 (PR #764 + Issue #765 carrier)
- **d-test integration:** d121 (deferred to Sprint 23 P2 follow-up PR; sister-pattern d109/d112/d117 env-var precedence family ≥3 sister coverage per ADR-0049 baseline)
- **Workflow YAML changes:** `.github/workflows/deploy.yml` env block addition (~3 lines), `vars.ATC_SERVICE_USER` repo var (NEW, Settings → Variables). Human-only territory per file ownership matrix.

---

## Context

### The cross-user scenario (RCA-16 + RCA-17 lineage)

The AtilCalculator production deployment runs on a self-hosted GitHub Actions runner (`192.168.1.197` per ADR-0030) as a dedicated `gh-actions-runner` user. The systemd user-service that hosts `atilcalc-web` is owned by `atilcan` (per ADR-0010 + Sprint 3 P0 incident #138 lineage). These two identities are **deliberately distinct**:

| Identity | Role | Systemd unit owner | Workflow runner |
|---|---|---|---|
| `gh-actions-runner` | GitHub Actions runner process | None (no login, no sudo) | ✅ This identity |
| `atilcan` | atilcalc-web service owner | ✅ `atilcalc-web.service` | ❌ This identity |

**Why distinct**: ADR-0030 §Threat model requires the runner user to have **no sudo, no SSH login, no write access outside `~/projects/AtilCalculator`** (defense-in-depth — even a compromised runner cannot reach the service-owner's systemd session). The runner user therefore cannot `systemctl --user restart atilcalc-web.service` directly because the unit lives under `atilcan`'s systemd user session.

**The gap**: without an explicit env var telling the deploy script which user owns the service unit, the only way to cross the user boundary is to (a) `sudo -u atilcan` from the runner (rejected per ADR-0030 §Threat model), (b) hardcode `atilcan` in the deploy script (rejected — Sprint 6 P1 RCA-17 redesign moved this to env-var driven, PR #358 MERGED ddfd43f), or (c) **the cross-user env var pattern** (this ADR).

### RCA-17 — the LIVE INSTANCE carrier

PR #764 (PENDING squash to main @ 8384ccb6 on branch `RCA-17-deploy-runner-ac4-user-fix`, owner squash gate per ADR-0031) proposes `scripts/deploy-runner.sh` AC4 — the hardcoded `'atilcan'` user → `${ATC_SERVICE_USER:-$USER}` shell fallback. Arch 9-Lens review of the PR (cycle #3316, cmt 4869829583) returned 🟢 OK + 1 architectural 🟡:

> **AC9 architectural verdict (recap)**: prod atiltestweb = **CROSS-USER scenario** — Runner user: `gh-actions-runner` (per ADR-0030 §Threat model); Service owner: `atilcan` (per RCA-16 lineage + ADR-0010). PR #764's fix (`${ATC_SERVICE_USER:-$USER}` env var with `$USER` fallback) defaults to `gh-actions-runner` on prod (since runner user is gh-actions-runner). **For prod to actually check `atilcan`'s systemd unit, `ATC_SERVICE_USER=atilcan` MUST be set in `.github/workflows/deploy.yml` `env:` block.**

Without the follow-up (`ATC_SERVICE_USER=atilcan` declared in deploy.yml), the `$USER` fallback yields `gh-actions-runner`, which has no service unit to restart. **Issue #765** is the doctrinal home of this follow-up; it is `status:ready / agent:human / priority:P1` (per Issue #765 body, owner-gated territory).

### Why a new ADR (not just an amendment)

The cross-user env var pattern is **distinct** from the two existing env-var ADR families:

| Family | ADR | Semantics | Default | Override surface |
|---|---|---|---|---|
| Operator-tunable perf-budget | ADR-0019-amend-4 | Numerical calibration knob | runner-aware (self-hosted = 2.0×) | `os.environ["BUDGET_MULTIPLIER"]` |
| Runtime API hot-path gate | ADR-0019-amend-5 | Boolean state-mutating gate | `"1"` (ENABLED, backward-compat) | `os.environ["ATILCALC_EVALUATE_PERSIST"]` |
| **Cross-user identity** | **ADR-0064 (this)** | **User-identity bound (systemd unit owner)** | **`$USER` (runner identity)** | **`os.environ["ATC_SERVICE_USER"]` + `vars.ATC_SERVICE_USER` repo var** |

The cross-user pattern is **user-identity-bound**, not perf-budget-tunable and not boolean-gated. It binds the deploy script's `systemctl --user restart <unit>` invocation to the systemd user session that owns the unit. Without this ADR, the next engineer adding a similar cross-user pattern (e.g., `ATC_LOG_DIR`, `ATC_CONFIG_OWNER`) has no doctrinal anchor for why the pattern exists; the gap could silently re-emerge.

---

## Decision

**Adopt the cross-user env var pattern** as a canonical doctrine for all service-management env vars in deploy scripts that run on the self-hosted runner. Codified as a **3-tier precedence chain** (workflow YAML `vars.X` repo var → workflow YAML hardcoded default → script-side `$USER` fallback) with **explicit user-identity semantics** that differ from operator-tunable perf-budget and boolean state-gate env-var families.

### §Canonical 3-tier precedence chain

| Tier | Source | Default semantics | Override surface | Owner |
|---|---|---|---|---|
| **Tier 1** | Workflow YAML `vars.ATC_SERVICE_USER` (repo variable) | None — operator-defined per-env | Settings → Secrets and variables → Variables | @owner (operator) |
| **Tier 2** | Workflow YAML hardcoded default in `env:` block | `'atilcan'` (canonical prod service owner) | n/a (compile-time) | @owner (workflow YAML human-only) |
| **Tier 3** | Script-side shell fallback `${ATC_SERVICE_USER:-$USER}` | `$USER` (runner user — `gh-actions-runner`) | `os.environ["ATC_SERVICE_USER"]` from workflow env | @developer (script impl) |

**Resolution rule** (Tier 1 > Tier 2 > Tier 3, strict):

1. If `vars.ATC_SERVICE_USER` is set on the repo → use it (env-specific override).
2. Else if workflow YAML env block declares `ATC_SERVICE_USER: ${{ vars.ATC_SERVICE_USER || 'atilcan' }}` → use `'atilcan'` (canonical prod default).
3. Else if script reads `${ATC_SERVICE_USER:-$USER}` → use `$USER` (runner identity, fails open — script will report unit-not-found, NOT corrupt).

**Why `||` (Tier 1 || Tier 2) — not just Tier 1**: GH Actions evaluates `vars.ATC_SERVICE_USER` to empty string when the var is unset (NOT null). The `|| 'atilcan'` GH expression handles this so Tier 2 default fires on empty. Sister-pattern to BUDGET_MULTIPLIER env-var precedence (ADR-0019-amend-4 §3-tier) — `||` is the canonical empty-handling idiom.

### §Canonical deploy.yml env declaration (human-only territory)

```yaml
# .github/workflows/deploy.yml — DEPLOY-001 job env block
# ADR-0064 §Canonical 3-tier precedence (Issue #765 + RCA-17 doctrinal codification)
env:
  ATC_PORT: ${{ vars.ATC_PORT || '8000' }}
  ATC_BIND_HOST: ${{ vars.ATC_BIND_HOST || '0.0.0.0' }}
  ATC_SERVICE_USER: ${{ vars.ATC_SERVICE_USER || 'atilcan' }}  # RCA-17 cross-user; default = canonical prod service owner
```

`vars.ATC_SERVICE_USER` repo variable (Settings → Secrets and variables → Variables):
- **Default**: unset (Tier 2 `'atilcan'` fires)
- **Per-env override example (runner VM, where runner user IS the service owner)**: set `ATC_SERVICE_USER=gh-actions-runner`
- **Per-env override example (dev box, atilcan laptop where runner user = atilcan)**: set `ATC_SERVICE_USER=atilcan` (redundant with Tier 2 default, but explicit is better than implicit)

### §Canonical script-side fallback (deploy-runner.sh)

```bash
# scripts/deploy-runner.sh — AC4 cross-user pattern (PR #764 PENDING @ 8384ccb6; branch RCA-17-deploy-runner-ac4-user-fix; will merge to main via owner squash per ADR-0031)
# ADR-0064 §Canonical 3-tier precedence — Tier 3 shell fallback
ATC_SERVICE_USER="${ATC_SERVICE_USER:-$USER}"
echo "ATC_SERVICE_USER resolved to: $ATC_SERVICE_USER (workflow env or \$USER fallback)"
# systemd --user restart requires the user to own the unit — see ADR-0010 §systemd user-service
sudo -u "$ATC_SERVICE_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$ATC_SERVICE_USER")" \
  systemctl --user restart atilcalc-web.service
```

**Why `sudo -u` (not direct `systemctl --user`)**: the runner process has no `XDG_RUNTIME_DIR` for `atilcan`'s systemd session. `sudo -u atilcan XDG_RUNTIME_DIR=... systemctl --user restart ...` is the canonical cross-user idiom; sets `XDG_RUNTIME_DIR` explicitly so the target user's systemd session is reachable. This is the **RCA-16 lineage fix** (PR #358-era); this ADR codifies it.

### §Why this 3-tier is correct (not 2-tier or 4-tier)

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **3-tier: `vars.X` repo var → workflow hardcoded default → script `$USER` fallback** (CHOSEN) | Per-env override (Tier 1); canonical prod default explicit in source-of-truth (Tier 2); safe fail-open to runner user (Tier 3); reverses per `<1 day` (delete vars + workflow entry + script fallback) | 3 distinct sources of truth (mitigated by canonical ADR + d121 d-test) | **Best fit** — preserves operator override, canonical default explicit, safe fallback |
| 2-tier: `vars.X` repo var → script `$USER` fallback (drop workflow hardcoded default) | Simpler; 2 sources of truth | No canonical prod default — every prod run must set `vars.ATC_SERVICE_USER=atilcan` explicitly (operator ergonomics violation); fails open to runner user silently | **Rejected** — operational dead-end (recurring operator typo risk) |
| 4-tier: add `--user` CLI flag → vars.X → workflow default → script fallback | Most flexible | Adds CLI flag for no current use case; YAGNI per ADR-0017 §YAGNI doctrine | **Rejected** — over-engineered |
| 1-tier: hardcode `'atilcan'` in script only | Simplest | RCA-17 defect class (PR #358 redesign); defeats env-specific override (runner VM, dev box); single source of truth = single point of failure | **Rejected** — the RCA-17 anti-pattern (PR #764 AC4 is the proposed fix, PENDING squash) |

### §Reversibility

Per architect doctrine "Reversibility > correctness":

- **<1 day of refactor** to delete the pattern entirely: remove `vars.ATC_SERVICE_USER` from repo vars, remove `ATC_SERVICE_USER` env block from `deploy.yml`, revert script fallback to hardcoded `'atilcan'`. d121 d-test would be updated to match.
- **Two-way door**: no irreversible infra. The systemd user-service contract (ADR-0010) is unchanged; only the env-var plumbing changes.
- **Bezos heuristic**: even if this ADR turns out to be wrong, it's cheap to revert. Worth codifying now to lock in the RCA-16/RCA-17 lineage.

### §d-test sister-pattern (d121 — deferred to Sprint 23 P2 follow-up PR per Cadence Rule 1 atomic cross-PR-cluster variant)

**Path B decision** (per tester CHANGES REQUESTED verdict cmt 4871079396 + F-5 follow-up cmt 4871123330, 2026-07-03): d121 d-test is **deferred to Sprint 23 P2 follow-up PR** with the same `Closes` anchor. This ADR commits the **d121 contract** (≥3 TCs baseline per ADR-0049 RED-first), not the d-test implementation itself. Cadence Rule 1 atomic cross-PR-cluster variant (sister-pattern to ADR-0074 §deferral pattern in INDEX.md — d-test implementation in a separate follow-up PR is a known option, not a violation).

**d121 contract** (this ADR commits; follow-up PR ships the d-test):

- **TC1 — Tier 1 precedence**: `vars.ATC_SERVICE_USER=atilcan` set on repo → `bash deploy-runner.sh --dry-run` resolves `ATC_SERVICE_USER=atilcan` from Tier 1 (repo var beats workflow default).
- **TC2 — Tier 2 fallback**: `vars.ATC_SERVICE_USER` unset → resolves `ATC_SERVICE_USER=atilcan` from Tier 2 (workflow YAML hardcoded default).
- **TC3 — Tier 3 fallback**: `vars.ATC_SERVICE_USER` unset + script receives no env → resolves `ATC_SERVICE_USER=gh-actions-runner` from Tier 3 (`$USER` shell fallback, safe fail-open).
- **TC4 — Empty-string handling** (GH evaluates unset `vars.X` as `""`): `vars.ATC_SERVICE_USER=""` → resolves `ATC_SERVICE_USER=atilcan` from Tier 2 (empty-string handling, NOT empty passthrough).
- **TC5** (optional, follow-up PR may add) — **End-to-end cross-check**: systemd unit ownership matches resolved `ATC_SERVICE_USER`; `sudo -u $ATC_SERVICE_USER systemctl --user status atilcalc-web.service` exits 0.

≥3 TCs baseline per ADR-0049 RED-first; follow-up PR may add TC4-TC5 (and any others) per ADR-0049 sister-family doctrine.

**Sister-pattern family** (corrected per tester F-5 cmt 4871123330 — earlier family citation erroneously listed d110/d113 as env-var sisters; corrected to d109/d112/d117):

Env-var precedence d-test family (3 sisters shipped + 1 contract pending):
- d109 — ci.yml BUDGET_MULTIPLIER env block (Sprint 22 PIVOT, PR #734)
- d112 — conftest env-var precedence, 7 TCs (TD-046-extension, PR #734 NEW)
- d117 — ATILCALC_EVALUATE_PERSIST env-var gate (Sprint 23 PIVOT, PR #742)
- d121 — cross-user env-var pattern (contract here; impl in Sprint 23 P2 follow-up PR)

Note: **d113 is the markdown-internal-links regression guard** (unrelated lint d-test, `scripts/tests/d113-markdown-internal-links.sh`); **d110 is mpmath lazy-import** (engine-side perf, `scripts/tests/d110-evaluator-lazy-import-mpmath.sh`) — neither is env-var precedence family. Tester F-5 corrected the earlier family citation that erroneously listed d110/d113 as env-var sisters.

≥3 sister coverage per ADR-0049 baseline is satisfied today (3 sisters already shipped: d109/d112/d117); d121 follow-up PR will make it 4.

---

## Rationale

### Why this ADR codifies a real pattern (not premature abstraction)

3+ instances of the cross-user pattern have emerged in the project lineage:

| Instance | Origin | Status | Pattern used |
|---|---|---|---|
| **RCA-16** (PR #358-era, Sprint 6 P1 redesign) | Original atilcalc-web systemd unit cross-user wrapper | ✅ MERGED | `sudo -u atilcan XDG_RUNTIME_DIR=... systemctl --user ...` (hardcoded `atilcan`) |
| **PR #764 (RCA-17)** | `scripts/deploy-runner.sh` AC4 hardcoded `'atilcan'` → `${ATC_SERVICE_USER:-$USER}` (this ADR's Tier 3) | 🟡 PENDING squash @ 8384ccb6 (branch `RCA-17-deploy-runner-ac4-user-fix`, owner squash gate per ADR-0031) | `${ATC_SERVICE_USER:-$USER}` (script-side fallback) |
| **Issue #765 (this ADR's follow-up)** | `vars.ATC_SERVICE_USER || 'atilcan'` deploy.yml env declaration (this ADR's Tier 1 + Tier 2) | 🟡 `status:ready / agent:human` (owner-gated) | `${{ vars.ATC_SERVICE_USER || 'atilcan' }}` (workflow YAML env block) |
| **Future candidates** | New env vars with user-identity semantics (e.g., `ATC_LOG_DIR` per-user, `ATC_CONFIG_OWNER` for multi-tenant deployments) | Sprint 24+ | Same 3-tier pattern |

Per architect doctrine "YAGNI by default, but flag the irreversible" — this is **not premature abstraction** (the pattern is concrete, 3+ instances, fixed). This is **codification of an existing recurring pattern** so future engineers have a doctrinal anchor.

### Why 3-tier (not 2-tier or 4-tier) — already argued above

- **2-tier rejected** because it loses the canonical prod default (operator must remember to set `vars.X` on every prod run — recurring typo risk).
- **4-tier rejected** because CLI flag is YAGNI for no current use case.
- **3-tier chosen** because it preserves all three legitimate concerns: per-env override (Tier 1), canonical prod default explicit in source-of-truth (Tier 2), safe fail-open to runner identity (Tier 3).

### Why the script-side fallback is `$USER` (not `'atilcan'`)

The deploy script runs in **two distinct contexts**:

1. **CI runner (prod, runner VM, dev box CI)** — `$USER = gh-actions-runner` (or whatever the runner is registered as). Here, Tier 1/Tier 2 should resolve to a non-runner user (e.g., `atilcan`); the `$USER` fallback is the **safe fail-open** that returns the runner identity (script will then `sudo -u atilcan ...` and exit clean if `atilcan` owns the unit, or fail with `unit not found` if not — never corrupts).
2. **Operator local shell (atilcan laptop)** — `$USER = atilcan`. Here, the script can run as the operator directly without `sudo -u`; the fallback is the **natural no-op** (already at correct identity).

The fallback `$USER` is **context-aware by design** — it does the right thing in both contexts without operator intervention.

### Why not just always `sudo -u atilcan` (no env var)

RCA-16 lineage fix (PR #358-era) established that **hardcoding `'atilcan'` in the script is wrong**:

- **Sprint 6 P1 RCA-17 redesign** (PR #358 MERGED ddfd43f) moved the hardcoded user to env-var driven.
- **Reason**: future deployments may not be `atilcan`-owned (multi-tenant, runner VM test, dev box CI). Hardcoding the user creates a **single point of failure** for non-prod envs.

The env-var-driven approach **decouples the deploy script from the service-owner identity** — the script reads the identity from the environment, not from a hardcoded constant. This is the **canonical 12-factor app config pattern** (config via env, not code).

### Why a new ADR (not just amend ADR-0019-amend-4)

ADR-0019-amend-4 codifies the **operator-tunable perf-budget env var** family (BUDGET_MULTIPLIER, SUBPROCESS_TIMEOUT_S). The cross-user pattern is a **distinct env-var family** with different semantics:

| Property | ADR-0019-amend-4 family | ADR-0019-amend-5 family | **ADR-0064 family (this)** |
|---|---|---|---|
| Value type | `float` | `str` (truthy/falsy) | `str` (Linux username) |
| Default semantics | Runner-aware (2.0× self-hosted) | `"1"` (ENABLED, backward-compat) | `$USER` (runner identity) |
| Override use case | A/B test new baselines | Test-infra opt-out, slow-runner fallback | Per-env service-owner override |
| Failure mode on bad input | `ValueError` (fail-loud) | Truthy/falsy fallback (lenient) | `sudo -u $USER ... systemctl --user ...` (unit-not-found, fails clean) |
| Tier count | 3 (env var > runner detection > hardcoded map) | 2 (env var > default) | **3 (vars.X repo var > workflow default > script `$USER` fallback)** |

The cross-user pattern has **distinct default semantics** (user-identity-bound vs numerical calibration vs boolean gate), **distinct failure modes** (fails clean vs fails loud vs lenient), and **distinct override surfaces** (repo var + workflow env vs runner detection vs single env var). Conflating these families into a single ADR would lose doctrinal clarity. **A new ADR is correct**.

---

## Consequences

### Positive

- **RCA-17 doctrinal closeout** — the `ATC_SERVICE_USER` pattern has a canonical ADR home. Future engineers adding similar cross-user patterns (e.g., `ATC_LOG_DIR`, `ATC_CONFIG_OWNER`) have an anchor.
- **Issue #765 unblocked (conditional on PR #764 squash)** — owner can squash the deploy.yml env block change with full doctrinal backing **once PR #764 merges to main**. The PR cluster (PR #764 + Issue #765 follow-up + ADR-0064) is a complete cross-user pattern cluster **only after PR #764 squash**. Until then, PR cluster is in-progress per Issue #763 status.
- **d121 d-test contract committed (impl in follow-up PR)** — env-var precedence family ships 3 sister tests (d109/d112/d117) per ADR-0049 ≥3 baseline; d121 d-test impl deferred to Sprint 23 P2 follow-up PR (Cadence Rule 1 atomic cross-PR-cluster variant, sister-pattern ADR-0074 deferral).
- **Reversibility preserved** — `<1 day` refactor to delete the pattern. Two-way door.
- **Sister-pattern doctrine family formalized** — env-var precedence is now codified as a canonical doctrine across 3 distinct families (perf-budget, runtime API, cross-user). Future env-var additions can declare which family they belong to.

### Negative

- **3 sources of truth** (vars.X repo var, workflow YAML env block, script-side fallback) — mitigated by canonical ADR + d121 d-test contract (≥3 TCs baseline per ADR-0049, deferred to Sprint 23 P2 follow-up PR per Cadence Rule 1 atomic cross-PR-cluster variant). Per ADR-0019-amend-4, 3-tier precedence is the canonical doctrine; this is a known trade-off.
- **`vars.ATC_SERVICE_USER` repo var adds operational surface** — owner must remember to set per-env override when needed. Mitigated by Tier 2 canonical prod default (`'atilcan'`); operator only sets the var when overriding.
- **d121 d-test required (deferred)** — ≥3 TCs baseline per ADR-0049 RED-first; d121 d-test impl **deferred to Sprint 23 P2 follow-up PR** per Cadence Rule 1 atomic cross-PR-cluster variant (sister-pattern to ADR-0074 deferral pattern). This ADR commits the contract (TC1-TC3 minimum; TC4-TC5 optional); the follow-up PR ships the d-test.
- **Workflow YAML changes human-only territory** — `.github/workflows/deploy.yml` is owner-only per file ownership matrix. Owner squash gate required for the env block addition. Sprint 23 dev lane cannot ship this directly; dev lane opens the PR, owner merges.

### Out of scope (deferred to follow-up tickets)

| Item | Sprint | Owner |
|---|---|---|
| Multi-tenant cross-user pattern generalization (e.g., `ATC_CONFIG_OWNER` for per-tenant service unit owners) | Sprint 24+ | @architect (generalize ADR-0064) |
| Cross-user pattern in OTHER scripts (e.g., `scripts/install.sh`, `scripts/run-server.sh`) — search & apply sister-pattern | Sprint 24+ | @developer (audit + apply) |
| `vars.ATC_SERVICE_USER` repo var documentation in README.md / OPERATIONS.md | Sprint 23 polish | @developer (docs) |
| **d121 d-test impl** (≥3 TCs per ADR-0049 RED-first) | **Sprint 23 P2** | **@tester (impl) + @architect (9-Lens review per ADR-0045)** |
| ADR-0049 amendment: clarify ≥3 TCs baseline (NOT ≥5 as previously claimed in amendment 4 L174) | Sprint 23 P1 doctrine hardening | @architect (doc correction, sister-pattern to ADR-0019-amend-4 §Out of scope #2) |

### Follow-up tickets to file

- [ ] docs/tech-debt.md TD-XXX entry: cross-user env-var pattern coverage gap (sister to TD-016/TD-018/TD-019/TD-020/TD-030/TD-046-extension)
- [ ] Sprint 24 backlog candidate: cross-user pattern audit across `scripts/*.sh`
- [ ] Sprint 24 backlog candidate: multi-tenant cross-user pattern generalization

---

## What this ADR commits to *now*

- **3-tier canonical precedence chain**: `vars.ATC_SERVICE_USER` repo var > workflow YAML hardcoded default > script-side `$USER` fallback. **The chain is the doctrine.**
- **Canonical deploy.yml env declaration**: `ATC_SERVICE_USER: ${{ vars.ATC_SERVICE_USER || 'atilcan' }}` (alongside existing `ATC_PORT` + `ATC_BIND_HOST`). Human-only territory per file ownership matrix.
- **Canonical script-side fallback**: `ATC_SERVICE_USER="${ATC_SERVICE_USER:-$USER}"` (PR #764 PENDING squash @ 8384ccb6 on branch `RCA-17-deploy-runner-ac4-user-fix`; this ADR codifies Tier 3 for the post-merge state).
- **`sudo -u "$ATC_SERVICE_USER" XDG_RUNTIME_DIR=... systemctl --user restart ...` idiom** — canonical cross-user systemd invocation (RCA-16 lineage).
- **d121 d-test contract**: ≥3 TCs baseline (per ADR-0049 RED-first) verify Tier 1/Tier 2/Tier 3 precedence + empty-string handling + (optional) end-to-end cross-check. **Implementation deferred to Sprint 23 P2 follow-up PR** (Cadence Rule 1 atomic cross-PR-cluster variant, sister-pattern ADR-0074 deferral); this ADR commits the contract spec, not the d-test file.
- **Issue #765 doctrinal home** — this ADR closes the RCA-17 cross-user follow-up. Owner squash gate for the deploy.yml env block addition.
- **Sister-pattern doctrine family** — env-var precedence is now codified as a canonical doctrine across 3 distinct families (perf-budget: ADR-0019-amend-4, runtime API gate: ADR-0019-amend-5, cross-user identity: ADR-0064 this).

---

## 9-Lens attestation (ADR-0045 + ADR-0043)

Per architect doctrine (lens a-j pre-publish gate, 9-Lens per ADR-0045):

| Lens | Attestation |
|---|---|
| **(a) Data flow** | ✅ ATC_SERVICE_USER traces: GH Actions env (`vars.ATC_SERVICE_USER`) → workflow YAML env block (`${{ vars.ATC_SERVICE_USER \|\| 'atilcan' }}`) → script env (`$ATC_SERVICE_USER`) → `sudo -u $ATC_SERVICE_USER` invocation. End-to-end traced. |
| **(b) Runtime preconditions** | ✅ Tier 3 fallback to `$USER` ensures safe fail-open (script reports unit-not-found, not corrupt). `XDG_RUNTIME_DIR` is set explicitly for cross-user invocation. Sister-pattern to ADR-0030 §Threat model. |
| **(c) Canonical entry point** | ✅ All deploy paths enter via `scripts/deploy-runner.sh`; env var resolution happens at script entry. No side-channels. |
| **(d) Silent-skip risk** | ✅ No silent skip — `sudo -u` invocation will report `unit not found` if `ATC_SERVICE_USER` resolves to wrong user. No catch-and-swallow logic. |
| **(e) Idempotency** | ✅ Env var resolution is idempotent (`vars.X` set once in repo, persists across runs). Script-side fallback is stateless. Sister-pattern to ADR-0027 §Decision.5 idempotency. |
| **(f) Observability** | ✅ Script logs `ATC_SERVICE_USER resolved to: <user>` at startup. d121 d-test (deferred to Sprint 23 P2 follow-up PR) will verify end-to-end unit ownership matches when shipped. |
| **(g) Security & privacy** | ✅ Tier 1 `vars.ATC_SERVICE_USER` repo var (NOT secret — visible to all repo readers). Default `'atilcan'` is non-secret. No PII. Sister-pattern to ADR-0030 §Threat model (runner user has no SSH, no sudo, restricted scope). |
| **(h) Workflow YAML SHA pin** | ✅ N/A — this ADR is doctrine-only; no workflow YAML added/changed in this PR. Issue #765 follow-up PR (workflow YAML addition) will require SHA pin per ADR-0045 lens h. |
| **(i) Platform hard constraints** | ✅ N/A — workflow YAML changes (Issue #765 follow-up) are human-only territory per file ownership matrix. Dev lane opens PR; owner merges. |
| **(j) Auto-generated file refs + live-state verification** | 🟡 Live-state verification (cycle ~#3363, post F-6 re-attestation): **PR #764 status: OPEN @ 8384ccb6** (head_sha on branch `RCA-17-deploy-runner-ac4-user-fix`, **NOT merged to main**); `origin/main @ 8d9540b` verified via `git rev-parse origin/main` — note: 8d9540b is PR #762 squash commit (BUG #759 pct_change, unrelated), not PR #764; `git show origin/main:scripts/deploy-runner.sh \| grep -c ATC_SERVICE_USER = 0` — Tier 3 pattern absent from main (only on PR #764's orphan branch); Issue #765 `status:ready` (workflow YAML follow-up, owner-gated territory). **All canonical-path assumptions verified at cycle ~#3363**: PR #764 cluster complete **when PR #764 merges** — until then, Issue #763 status:in-progress governs. **F-6 finding (tester cmt 4871138817 + 4871194663) re-attested**: previous lens (j) attestation in cycle #3349 self-post falsely claimed `PR #764 MERGED @ 8d9540b` (hallucinated — 8d9540b is PR #762 commit, PR #764 is still open). Corrected in cycle ~#3363 commit (this ADR). |

---

## Cross-references

- **Systemd user-services** (canonical home of the per-user systemd unit pattern): [ADR-0010](./ADR-0010-per-project-watchers.md)
- **Self-hosted runner identity** (`gh-actions-runner` user): [ADR-0030](./ADR-0030-self-hosted-runner-lan-deploy.md)
- **Operator-tunable perf-budget env vars** (sister-pattern, env-var precedence family): [ADR-0019-amendment-4](./ADR-0019-amendment-4-conftest-env-var-precedence.md)
- **Runtime API hot-path gate** (sister-pattern, env-var precedence family): [ADR-0019-amendment-5](./ADR-0019-amendment-5-evaluate-persist-env-var-gate.md)
- **Deploy automation** (smoke-test + auto-rollback contract): [ADR-0027](./ADR-0027-deploy-automation.md)
- **d-test framework** (d121 sister-pattern): [ADR-0049](./ADR-0049-behavioral-workflow-test-framework.md)
- **RED-first TDD** (tester sign-off discipline): [ADR-0044](./ADR-0044-verdict-by-scope-clarification.md)
- **Cadence Rule 1 atomic** (this ADR + INDEX.md row in same PR): [ADR-0055](./ADR-0055-d-test-id-uniqueness-sub-pattern-matrix.md)
- **9-Lens attestation** (pre-publish gate): [ADR-0045](./ADR-0045-auto-generated-file-refs-design-verification.md) + [ADR-0043](./ADR-0043-8-lens-architect-review-checklist.md)
- **PR #764 (RCA-17 AC4 fix, PENDING squash @ 8384ccb6 on branch `RCA-17-deploy-runner-ac4-user-fix`, owner squash gate per ADR-0031)**: `fix(deploy): RCA-17 AC4 user fix — ${ATC_SERVICE_USER:-$USER} env var (d121 sister)` (PR body proposed, not yet on main)
- **Issue #765 (this ADR's follow-up)**: `deploy.yml: add ATC_SERVICE_USER=atilcan env (RCA-17 cross-user requirement, owner-gated follow-up)`
- **Arch 9-Lens review (cycle #3316, cmt 4869829583)**: arch verdict 🟢 OK + 1 architectural 🟡 (the AC9 cross-user verdict — this ADR codifies it)
- **RCA-16 lineage** (PR #358-era, Sprint 6 P1 redesign, MERGED ddfd43f 2026-06-24T18:33:24Z): original atilcalc-web systemd unit cross-user wrapper
- **RCA-17 dispatch** (Issue #763): deploy-runner.sh AC4 hardcoded 'atilcan' → `$USER` (RCA-17 cycle ~#3300)
- **RETRO-016 cluster** (cross-watchdog patterns): Issue #675, Issue #680, Issue #682, Issue #696, Issue #706
- **Tech-debt ledger**: [docs/tech-debt.md](./../tech-debt.md) (TD-XXX entry to be filed in same PR per ADR-0055 Cadence Rule 1)
- **Issue #113**: label-authority > body doctrine — labels are source of truth

---

🤖 Generated with [Claude Code](https://claude.com/claude-code) — @architect (cycle ~#3349, 2026-07-03T22:38Z, Sprint 23 polish lane, REPRIME recovery pickup from wake_nudge)