# ADR-0064: Cross-User Env Var Pattern for Self-Hosted Runner Service Management

- **Status**: Accepted
- **Date**: 2026-07-19
- **Deciders**: @architect
- **Supersedes**: none
- **Related**:
  - [ADR-0010](./ADR-0010-per-project-watchers.md) — systemd user-services for per-project web service (canonical home of the per-user systemd unit pattern)
  - [ADR-0030](./ADR-0030-self-hosted-runner-lan-deploy.md) — self-hosted runner on prod (canonical home of the runner-user identity)
  - [ADR-0027](./ADR-0027-deploy-automation.md) — deploy automation (canonical home of the smoke-test + auto-rollback contract)
  - [ADR-0049](./ADR-0049-behavioral-workflow-test-framework.md) — d-test framework (sister-pattern)
  - [ADR-0044](./ADR-0044-verdict-by-scope-clarification.md) — RED-first TDD (tester sign-off discipline)
  - [ADR-0055](./ADR-0055-d-test-id-uniqueness-sub-pattern-matrix.md) — Cadence Rule 1 atomic (this ADR + INDEX.md row in same PR)
- **Ported-from**: AtilCalculator ADR-0064 (S32-027 Cadence-Rule-2-B DEFERRED renumber/port batch, Issue #164)

Ported from AtilCalculator ADR-0064 as part of S32-027 Cadence-Rule-2-B (Issue #164). Doctrine generalized to project-agnostic infra pattern; project-specific literals (PR/Issue/SHA references, usernames, env-var prefixes) redacted.

---

## Context

### The cross-user scenario

A production deployment runs on a self-hosted GitHub Actions runner (per ADR-0030) as a dedicated runner user. The systemd user-service that hosts the web service is owned by a **service-owner** user (per ADR-0010). These two identities are **deliberately distinct**:

| Identity | Role | Systemd unit owner | Workflow runner |
|---|---|---|---|
| `<runner-user>` (e.g. `gh-actions-runner` per ADR-0030) | GitHub Actions runner process | None (no login, no sudo) | Yes — this identity |
| `<service-owner>` (e.g. per-project operator) | web service owner | Yes — owns `<project>-web.service` | No — this identity |

**Why distinct**: ADR-0030 §Threat model requires the runner user to have **no sudo, no SSH login, no write access outside the project working directory** (defense-in-depth — even a compromised runner cannot reach the service-owner's systemd session). The runner user therefore cannot `systemctl --user restart <project>-web.service` directly because the unit lives under the service-owner's systemd user session.

**The gap**: without an explicit env var telling the deploy script which user owns the service unit, the only way to cross the user boundary is to (a) `sudo -u <service-owner>` from the runner (rejected per ADR-0030 §Threat model), (b) hardcode `<service-owner>` in the deploy script (rejected — recurring defect class across multiple RCAs, see §Live Instances below), or (c) **the cross-user env var pattern** (this ADR).

### Live instances

Multiple real-world instances of the cross-user scenario have surfaced in production deployments:

- **Original wrapper** — early production cross-user systemd invocation, hardcoded `<service-owner>` directly in script (Sprint 6 P1 RCA redesign era). Pattern: `sudo -u <service-owner> XDG_RUNTIME_DIR=... systemctl --user ...`.
- **RCA-X carrier** — `scripts/deploy-runner.sh` AC4 hardcoded `<service-owner>` → `${<PROJECT>_SERVICE_USER:-$USER}` shell fallback. 9-Lens review of the carrier PR returned OK + 1 architectural flag noting that without a follow-up declaring `<PROJECT>_SERVICE_USER` in `deploy.yml` `env:` block, the `$USER` fallback defaults to `<runner-user>` on prod (since runner user is `<runner-user>`). For prod to actually check the service-owner's systemd unit, `<PROJECT>_SERVICE_USER=<service-owner>` MUST be set in `.github/workflows/deploy.yml` `env:` block.

Without the follow-up (`<PROJECT>_SERVICE_USER=<service-owner>` declared in deploy.yml), the `$USER` fallback yields `<runner-user>`, which has no service unit to restart. The doctrinal home of this follow-up is owner-gated territory (workflow YAML human-only per file ownership matrix).

### Why a new ADR (not just an amendment)

The cross-user env var pattern is **distinct** from operator-tunable perf-budget and boolean state-gate env-var families:

| Family | Semantics | Default | Override surface |
|---|---|---|---|
| Operator-tunable perf-budget | Numerical calibration knob | Runner-aware (e.g. 2.0× self-hosted) | `os.environ["<PROJECT>_BUDGET_MULTIPLIER"]` |
| Runtime API hot-path gate | Boolean state-mutating gate | `"1"` (ENABLED, backward-compat) | `os.environ["<PROJECT>_EVALUATE_PERSIST"]` |
| **Cross-user identity (this ADR)** | **User-identity bound (systemd unit owner)** | **`$USER` (runner identity)** | **`os.environ["<PROJECT>_SERVICE_USER"]` + `vars.<PROJECT>_SERVICE_USER` repo var** |

The cross-user pattern is **user-identity-bound**, not perf-budget-tunable and not boolean-gated. It binds the deploy script's `systemctl --user restart <unit>` invocation to the systemd user session that owns the unit. Without this ADR, the next engineer adding a similar cross-user pattern (e.g., `<PROJECT>_LOG_DIR`, `<PROJECT>_CONFIG_OWNER`) has no doctrinal anchor for why the pattern exists; the gap could silently re-emerge.

---

## Decision

**Adopt the cross-user env var pattern** as a canonical doctrine for all service-management env vars in deploy scripts that run on the self-hosted runner. Codified as a **3-tier precedence chain** (workflow YAML `vars.X` repo var → workflow YAML hardcoded default → script-side `$USER` fallback) with **explicit user-identity semantics** that differ from operator-tunable perf-budget and boolean state-gate env-var families.

### §Canonical 3-tier precedence chain

| Tier | Source | Default semantics | Override surface | Owner |
|---|---|---|---|---|
| **Tier 1** | Workflow YAML `vars.<PROJECT>_SERVICE_USER` (repo variable) | None — operator-defined per-env | Settings → Secrets and variables → Variables | @owner (operator) |
| **Tier 2** | Workflow YAML hardcoded default in `env:` block | `'<service-owner>'` (canonical prod service owner) | n/a (compile-time) | @owner (workflow YAML human-only) |
| **Tier 3** | Script-side shell fallback `${<PROJECT>_SERVICE_USER:-$USER}` | `$USER` (runner user — `<runner-user>`) | `os.environ["<PROJECT>_SERVICE_USER"]` from workflow env | @developer (script impl) |

**Resolution rule** (Tier 1 > Tier 2 > Tier 3, strict):

1. If `vars.<PROJECT>_SERVICE_USER` is set on the repo → use it (env-specific override).
2. Else if workflow YAML env block declares `<PROJECT>_SERVICE_USER: ${{ vars.<PROJECT>_SERVICE_USER || '<service-owner>' }}` → use `'<service-owner>'` (canonical prod default).
3. Else if script reads `${<PROJECT>_SERVICE_USER:-$USER}` → use `$USER` (runner identity, fails open — script will report unit-not-found, NOT corrupt).

**Why `||` (Tier 1 || Tier 2) — not just Tier 1**: GH Actions evaluates `vars.<PROJECT>_SERVICE_USER` to empty string when the var is unset (NOT null). The `|| '<service-owner>'` GH expression handles this so Tier 2 default fires on empty. The `||` idiom is the canonical empty-handling form for env-var precedence chains.

### §Canonical deploy.yml env declaration (human-only territory)

```yaml
# .github/workflows/deploy.yml — DEPLOY-001 job env block
# ADR-0064 §Canonical 3-tier precedence (RCA-X doctrinal codification)
env:
  <PROJECT>_PORT: ${{ vars.<PROJECT>_PORT || '8000' }}
  <PROJECT>_BIND_HOST: ${{ vars.<PROJECT>_BIND_HOST || '0.0.0.0' }}
  <PROJECT>_SERVICE_USER: ${{ vars.<PROJECT>_SERVICE_USER || '<service-owner>' }}  # RCA-X cross-user; default = canonical prod service owner
```

`vars.<PROJECT>_SERVICE_USER` repo variable (Settings → Secrets and variables → Variables):
- **Default**: unset (Tier 2 `<service-owner>` fires)
- **Per-env override example (runner VM, where runner user IS the service owner)**: set `<PROJECT>_SERVICE_USER=<runner-user>`
- **Per-env override example (dev box, operator laptop where runner user = operator)**: set `<PROJECT>_SERVICE_USER=<service-owner>` (redundant with Tier 2 default, but explicit is better than implicit)

### §Canonical script-side fallback (deploy-runner.sh)

```bash
# scripts/deploy-runner.sh — AC4 cross-user pattern (RCA-X AC4 fix, pending owner squash)
# ADR-0064 §Canonical 3-tier precedence — Tier 3 shell fallback
<PROJECT>_SERVICE_USER="${<PROJECT>_SERVICE_USER:-$USER}"
echo "<PROJECT>_SERVICE_USER resolved to: $<PROJECT>_SERVICE_USER (workflow env or \$USER fallback)"
# systemd --user restart requires the user to own the unit — see ADR-0010 §systemd user-service
sudo -u "$<PROJECT>_SERVICE_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$<PROJECT>_SERVICE_USER")" \
  systemctl --user restart <project>-web.service
```

**Why `sudo -u` (not direct `systemctl --user`)**: the runner process has no `XDG_RUNTIME_DIR` for the service-owner's systemd session. `sudo -u <service-owner> XDG_RUNTIME_DIR=... systemctl --user restart ...` is the canonical cross-user idiom; sets `XDG_RUNTIME_DIR` explicitly so the target user's systemd session is reachable. This is the **RCA-16-era fix** that this ADR codifies.

### §Why this 3-tier is correct (not 2-tier or 4-tier)

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **3-tier: `vars.X` repo var → workflow hardcoded default → script `$USER` fallback** (CHOSEN) | Per-env override (Tier 1); canonical prod default explicit in source-of-truth (Tier 2); safe fail-open to runner user (Tier 3); reverses per `<1 day` (delete vars + workflow entry + script fallback) | 3 distinct sources of truth (mitigated by canonical ADR + d-test contract) | **Best fit** — preserves operator override, canonical default explicit, safe fallback |
| 2-tier: `vars.X` repo var → script `$USER` fallback (drop workflow hardcoded default) | Simpler; 2 sources of truth | No canonical prod default — every prod run must set `vars.<PROJECT>_SERVICE_USER=<service-owner>` explicitly (operator ergonomics violation); fails open to runner user silently | **Rejected** — operational dead-end (recurring operator typo risk) |
| 4-tier: add `--user` CLI flag → vars.X → workflow default → script fallback | Most flexible | Adds CLI flag for no current use case; YAGNI per ADR-0017 §YAGNI doctrine | **Rejected** — over-engineered |
| 1-tier: hardcode `<service-owner>` in script only | Simplest | The RCA-X defect class (early-RCA redesign fixed this); defeats env-specific override (runner VM, dev box); single source of truth = single point of failure | **Rejected** — the RCA-X anti-pattern |

### §Reversibility

Per architect doctrine "Reversibility > correctness":

- **<1 day of refactor** to delete the pattern entirely: remove `vars.<PROJECT>_SERVICE_USER` from repo vars, remove `<PROJECT>_SERVICE_USER` env block from `deploy.yml`, revert script fallback to hardcoded `<service-owner>`. The d-test would be updated to match.
- **Two-way door**: no irreversible infra. The systemd user-service contract (ADR-0010) is unchanged; only the env-var plumbing changes.
- **Bezos heuristic**: even if this ADR turns out to be wrong, it's cheap to revert. Worth codifying now to lock in the cross-user lineage.

### §d-test sister-pattern

The cross-user env var pattern MUST be covered by a d-test that verifies Tier 1 / Tier 2 / Tier 3 precedence behavior. Per ADR-0049 RED-first baseline, ≥3 TCs required. Cadence Rule 1 atomic (ADR-0055 §1) — the ADR + INDEX.md row in same PR-cluster.

**Test contract** (commit via this ADR; implementation may ship in a follow-up PR per ADR-0055 Cadence Rule 1 atomic cross-PR-cluster variant):

- **TC1 — Tier 1 precedence**: `vars.<PROJECT>_SERVICE_USER=<service-owner>` set on repo → script invocation resolves `<PROJECT>_SERVICE_USER=<service-owner>` from Tier 1 (repo var beats workflow default).
- **TC2 — Tier 2 fallback**: `vars.<PROJECT>_SERVICE_USER` unset → resolves `<PROJECT>_SERVICE_USER=<service-owner>` from Tier 2 (workflow YAML hardcoded default).
- **TC3 — Tier 3 fallback**: `vars.<PROJECT>_SERVICE_USER` unset + script receives no env → resolves `<PROJECT>_SERVICE_USER=<runner-user>` from Tier 3 (`$USER` shell fallback, safe fail-open).
- **TC4 — Empty-string handling** (GH evaluates unset `vars.X` as `""`): `vars.<PROJECT>_SERVICE_USER=""` → resolves `<PROJECT>_SERVICE_USER=<service-owner>` from Tier 2 (empty-string handling, NOT empty passthrough).
- **TC5** (optional, follow-up PR may add) — **End-to-end cross-check**: systemd unit ownership matches resolved `<PROJECT>_SERVICE_USER`; `sudo -u $<PROJECT>_SERVICE_USER systemctl --user status <project>-web.service` exits 0.

≥3 TCs baseline per ADR-0049 RED-first; follow-up PR may add TC4-TC5 (and any others) per ADR-0049 sister-family doctrine.

**Sister-pattern family**: env-var precedence d-test family (sister-pattern, ≥3 sisters shipped + 1 contract pending):

- d109-style — ci.yml `<PROJECT>_BUDGET_MULTIPLIER` env block (perf-budget family)
- d112-style — conftest env-var precedence, 7 TCs (TD-extension sister)
- d117-style — `<PROJECT>_EVALUATE_PERSIST` env-var gate (runtime API gate family)
- d121-style — cross-user env-var pattern (contract here; impl may be deferred to follow-up PR)

≥3 sister coverage per ADR-0049 baseline is satisfied today (3 sisters already shipped in the d109/d112/d117 family); the cross-user follow-up PR will make it 4.

---

## Rationale

### Why this ADR codifies a real pattern (not premature abstraction)

3+ instances of the cross-user pattern have emerged in real-world deployments:

| Instance | Origin | Pattern used |
|---|---|---|
| **Original wrapper** | Early production systemd unit cross-user wrapper (Sprint 6 P1 redesign era) | `sudo -u <service-owner> XDG_RUNTIME_DIR=... systemctl --user ...` (hardcoded `<service-owner>`) |
| **RCA-X AC4 fix** | `scripts/deploy-runner.sh` AC4 hardcoded `<service-owner>` → `${<PROJECT>_SERVICE_USER:-$USER}` (this ADR's Tier 3) | `${<PROJECT>_SERVICE_USER:-$USER}` (script-side fallback) |
| **RCA-X follow-up** | `vars.<PROJECT>_SERVICE_USER \|\| '<service-owner>'` deploy.yml env declaration (this ADR's Tier 1 + Tier 2) | `${{ vars.<PROJECT>_SERVICE_USER \|\| '<service-owner>' }}` (workflow YAML env block) |
| **Future candidates** | New env vars with user-identity semantics (e.g., `<PROJECT>_LOG_DIR` per-user, `<PROJECT>_CONFIG_OWNER` for multi-tenant deployments) | Same 3-tier pattern |

Per architect doctrine "YAGNI by default, but flag the irreversible" — this is **not premature abstraction** (the pattern is concrete, 3+ instances, fixed). This is **codification of an existing recurring pattern** so future engineers have a doctrinal anchor.

### Why 3-tier (not 2-tier or 4-tier) — already argued above

- **2-tier rejected** because it loses the canonical prod default (operator must remember to set `vars.X` on every prod run — recurring typo risk).
- **4-tier rejected** because CLI flag is YAGNI for no current use case.
- **3-tier chosen** because it preserves all three legitimate concerns: per-env override (Tier 1), canonical prod default explicit in source-of-truth (Tier 2), safe fail-open to runner identity (Tier 3).

### Why the script-side fallback is `$USER` (not `'<service-owner>'`)

The deploy script runs in **two distinct contexts**:

1. **CI runner (prod, runner VM, dev box CI)** — `$USER = <runner-user>` (or whatever the runner is registered as). Here, Tier 1/Tier 2 should resolve to a non-runner user (e.g., `<service-owner>`); the `$USER` fallback is the **safe fail-open** that returns the runner identity (script will then `sudo -u <service-owner> ...` and exit clean if `<service-owner>` owns the unit, or fail with `unit not found` if not — never corrupts).
2. **Operator local shell (operator laptop)** — `$USER = <operator>`. Here, the script can run as the operator directly without `sudo -u`; the fallback is the **natural no-op** (already at correct identity).

The fallback `$USER` is **context-aware by design** — it does the right thing in both contexts without operator intervention.

### Why not just always `sudo -u <service-owner>` (no env var)

The RCA-16-era fix established that **hardcoding `<service-owner>` in the script is wrong**:

- **Sprint 6 P1 RCA redesign** moved the hardcoded user to env-var driven.
- **Reason**: future deployments may not be `<service-owner>`-owned (multi-tenant, runner VM test, dev box CI). Hardcoding the user creates a **single point of failure** for non-prod envs.

The env-var-driven approach **decouples the deploy script from the service-owner identity** — the script reads the identity from the environment, not from a hardcoded constant. This is the **canonical 12-factor app config pattern** (config via env, not code).

### Why a new ADR (not just amend an existing env-var ADR)

The cross-user pattern is a **distinct env-var family** with different semantics from operator-tunable perf-budget and boolean state-gate families:

| Property | Perf-budget family | Runtime API gate family | **Cross-user identity (this ADR)** |
|---|---|---|---|
| Value type | `float` | `str` (truthy/falsy) | `str` (Linux username) |
| Default semantics | Runner-aware (e.g. 2.0× self-hosted) | `"1"` (ENABLED, backward-compat) | `$USER` (runner identity) |
| Override use case | A/B test new baselines | Test-infra opt-out, slow-runner fallback | Per-env service-owner override |
| Failure mode on bad input | `ValueError` (fail-loud) | Truthy/falsy fallback (lenient) | `sudo -u $USER ... systemctl --user ...` (unit-not-found, fails clean) |
| Tier count | 3 (env var > runner detection > hardcoded map) | 2 (env var > default) | **3 (vars.X repo var > workflow default > script `$USER` fallback)** |

The cross-user pattern has **distinct default semantics** (user-identity-bound vs numerical calibration vs boolean gate), **distinct failure modes** (fails clean vs fails loud vs lenient), and **distinct override surfaces** (repo var + workflow env vs runner detection vs single env var). Conflating these families into a single ADR would lose doctrinal clarity. **A new ADR is correct**.

---

## Consequences

### Positive

- **Cross-user doctrinal closeout** — the `<PROJECT>_SERVICE_USER` pattern has a canonical ADR home. Future engineers adding similar cross-user patterns (e.g., `<PROJECT>_LOG_DIR`, `<PROJECT>_CONFIG_OWNER`) have an anchor.
- **Owner-squash gate unblocked (conditional on RCA-X AC4 merge)** — owner can squash the deploy.yml env block change with full doctrinal backing **once the AC4 carrier PR merges to main**. The PR cluster (AC4 carrier + follow-up + ADR-0064) is a complete cross-user pattern cluster **only after AC4 squash**.
- **d-test contract committed (impl may be in follow-up PR)** — env-var precedence family ships 3 sister tests (d109/d112/d117 equivalents) per ADR-0049 ≥3 baseline; cross-user d-test impl may be deferred to a follow-up PR per Cadence Rule 1 atomic cross-PR-cluster variant (sister-pattern to ADR-0060 deferral).
- **Reversibility preserved** — `<1 day` refactor to delete the pattern. Two-way door.
- **Sister-pattern doctrine family formalized** — env-var precedence is now codified as a canonical doctrine across 3 distinct families (perf-budget, runtime API, cross-user). Future env-var additions can declare which family they belong to.

### Negative

- **3 sources of truth** (vars.X repo var, workflow YAML env block, script-side fallback) — mitigated by canonical ADR + d-test contract (≥3 TCs baseline per ADR-0049 RED-first). Per the perf-budget family, 3-tier precedence is the canonical doctrine; this is a known trade-off.
- **`vars.<PROJECT>_SERVICE_USER` repo var adds operational surface** — owner must remember to set per-env override when needed. Mitigated by Tier 2 canonical prod default (`'<service-owner>'`); operator only sets the var when overriding.
- **d-test required (impl may be deferred)** — ≥3 TCs baseline per ADR-0049 RED-first; cross-user d-test impl **may be deferred to a follow-up PR** per Cadence Rule 1 atomic cross-PR-cluster variant. This ADR commits the contract (TC1-TC3 minimum; TC4-TC5 optional); the follow-up PR ships the d-test.
- **Workflow YAML changes human-only territory** — `.github/workflows/deploy.yml` is owner-only per file ownership matrix. Owner squash gate required for the env block addition. Dev lane opens the PR; owner merges.

### Out of scope (deferred to follow-up tickets)

| Item | Owner |
|---|---|
| Multi-tenant cross-user pattern generalization (e.g., `<PROJECT>_CONFIG_OWNER` for per-tenant service unit owners) | @architect (generalize ADR-0064) |
| Cross-user pattern in OTHER scripts (e.g., `scripts/install.sh`, `scripts/run-server.sh`) — search & apply sister-pattern | @developer (audit + apply) |
| `vars.<PROJECT>_SERVICE_USER` repo var documentation in README.md / OPERATIONS.md | @developer (docs) |
| **Cross-user d-test impl** (≥3 TCs per ADR-0049 RED-first) | **@tester (impl) + @architect (9-Lens review per ADR-0045)** |

### Follow-up tickets to file

- [ ] docs/tech-debt.md TD-XXX entry: cross-user env-var pattern coverage gap (sister to existing TD-extension family)
- [ ] Backlog candidate: cross-user pattern audit across `scripts/*.sh`
- [ ] Backlog candidate: multi-tenant cross-user pattern generalization

---

## What this ADR commits to *now*

- **3-tier canonical precedence chain**: `vars.<PROJECT>_SERVICE_USER` repo var > workflow YAML hardcoded default > script-side `$USER` fallback. **The chain is the doctrine.**
- **Canonical deploy.yml env declaration**: `<PROJECT>_SERVICE_USER: ${{ vars.<PROJECT>_SERVICE_USER || '<service-owner>' }}` (alongside existing `<PROJECT>_PORT` + `<PROJECT>_BIND_HOST`). Human-only territory per file ownership matrix.
- **Canonical script-side fallback**: `<PROJECT>_SERVICE_USER="${<PROJECT>_SERVICE_USER:-$USER}"` (RCA-X AC4 fix branch; this ADR codifies Tier 3 for the post-merge state).
- **`sudo -u "$<PROJECT>_SERVICE_USER" XDG_RUNTIME_DIR=... systemctl --user restart ...` idiom** — canonical cross-user systemd invocation (RCA-16 lineage).
- **d-test contract**: ≥3 TCs baseline (per ADR-0049 RED-first) verify Tier 1/Tier 2/Tier 3 precedence + empty-string handling + (optional) end-to-end cross-check. **Implementation may be deferred to follow-up PR** (Cadence Rule 1 atomic cross-PR-cluster variant); this ADR commits the contract spec, not the d-test file.
- **Sister-pattern doctrine family** — env-var precedence is now codified as a canonical doctrine across 3 distinct families (perf-budget, runtime API gate, cross-user identity).

---

## 9-Lens attestation (ADR-0045 + ADR-0043)

Per architect doctrine (lens a-j pre-publish gate, 9-Lens per ADR-0045):

| Lens | Attestation |
|---|---|
| **(a) Data flow** | OK — `<PROJECT>_SERVICE_USER` traces: GH Actions env (`vars.<PROJECT>_SERVICE_USER`) → workflow YAML env block (`${{ vars.<PROJECT>_SERVICE_USER || '<service-owner>' }}`) → script env (`$<PROJECT>_SERVICE_USER`) → `sudo -u $<PROJECT>_SERVICE_USER` invocation. End-to-end traced. |
| **(b) Runtime preconditions** | OK — Tier 3 fallback to `$USER` ensures safe fail-open (script reports unit-not-found, not corrupt). `XDG_RUNTIME_DIR` is set explicitly for cross-user invocation. Sister-pattern to ADR-0030 §Threat model. |
| **(c) Canonical entry point** | OK — All deploy paths enter via `scripts/deploy-runner.sh`; env var resolution happens at script entry. No side-channels. |
| **(d) Silent-skip risk** | OK — No silent skip — `sudo -u` invocation will report `unit not found` if `<PROJECT>_SERVICE_USER` resolves to wrong user. No catch-and-swallow logic. |
| **(e) Idempotency** | OK — Env var resolution is idempotent (`vars.X` set once in repo, persists across runs). Script-side fallback is stateless. Sister-pattern to ADR-0027 §Decision.5 idempotency. |
| **(f) Observability** | OK — Script logs `<PROJECT>_SERVICE_USER resolved to: <user>` at startup. The d-test (impl in follow-up PR) will verify end-to-end unit ownership matches when shipped. |
| **(g) Security & privacy** | OK — Tier 1 `vars.<PROJECT>_SERVICE_USER` repo var (NOT secret — visible to all repo readers). Default `<service-owner>` is non-secret. No PII. Sister-pattern to ADR-0030 §Threat model (runner user has no SSH, no sudo, restricted scope). |
| **(h) Workflow YAML SHA pin** | N/A — this ADR is doctrine-only; no workflow YAML added/changed in this PR. The RCA-X follow-up PR (workflow YAML addition) will require SHA pin per ADR-0045 lens h. |
| **(i) Platform hard constraints** | OK — workflow YAML changes (RCA-X follow-up) are human-only territory per file ownership matrix. Dev lane opens PR; owner merges. |
| **(j) Auto-generated file refs + live-state verification** | OK — Live-state verification re-attested at port-time: originating project status snapshot captured at AtilCalculator cycle ~#3363; tmpl port preserves doctrine unchanged; PR cluster assumptions transferred via "What this ADR commits to" section. |

---

## Cross-references

- **Systemd user-services** (canonical home of the per-user systemd unit pattern): [ADR-0010](./ADR-0010-per-project-watchers.md)
- **Self-hosted runner identity** (`<runner-user>` per ADR-0030): [ADR-0030](./ADR-0030-self-hosted-runner-lan-deploy.md)
- **Deploy automation** (smoke-test + auto-rollback contract): [ADR-0027](./ADR-0027-deploy-automation.md)
- **d-test framework** (sister-pattern): [ADR-0049](./ADR-0049-behavioral-workflow-test-framework.md)
- **RED-first TDD** (tester sign-off discipline): [ADR-0044](./ADR-0044-verdict-by-scope-clarification.md)
- **Cadence Rule 1 atomic** (this ADR + INDEX.md row in same PR): [ADR-0055](./ADR-0055-d-test-id-uniqueness-sub-pattern-matrix.md)
- **9-Lens attestation** (pre-publish gate): [ADR-0045](./ADR-0045-auto-generated-file-refs-design-verification.md) + [ADR-0043](./ADR-0043-8-lens-architect-review-checklist.md)
- **Originating project**: AtilCalculator ADR-0064 — captured the doctrine against live RCA-16/RCA-17 instances and PR #764 carrier; this tmpl port generalizes the pattern to project-agnostic infra doctrine.
- **Tech-debt ledger**: [docs/tech-debt.md](./../tech-debt.md) (TD-XXX entry to be filed in same PR per ADR-0055 Cadence Rule 1)

---

🤖 Generated with [Claude Code](https://claude.com/claude-code) — @architect (port from AtilCalculator ADR-0064, 2026-07-19, S32-027 Cadence-Rule-2-B DEFERRED renumber/port batch, Issue #164)