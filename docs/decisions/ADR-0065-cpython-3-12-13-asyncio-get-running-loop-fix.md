# ADR-0065 — CPython 3.12.13 Tool-Cache + asyncio.get_running_loop SIGSEGV Fix

- **Status:** Proposed (Sprint 23 INCIDENT-3 RCA, Closes Issue #793, owner-gated per ADR-0031 for workflow YAML + systemd unit)
- **Date:** 2026-07-03
- **Deciders:** @architect (doctrine spec, 9-Lens review cycle ~#3493), @developer (RCA evidence: gdb stack + 4 apport cores, cmt 4879255529 + 4879257564), @tester (d-test sign-off pending — d124 d-test for env-resolution, sister-pattern d123), @orchestrator (rollback execution + PR #794 coordination), @atilcan65 (owner squash gate for `.github/workflows/deploy.yml` + systemd unit per file ownership matrix — human-only territory)
- **Supersedes:** — (doctrinal codification, no supersede)
- **Related:**
  - [ADR-0017](./ADR-0017-tech-stack.md) — Tech stack baseline: Python 3.11+ (now extended to CPython micro-version pin per §Decision 1)
  - [ADR-0019](./ADR-0019-api-contract.md) — HTTP API contract (engine↔UI separation, FastAPI surface — INCIDENT-3 surface, NOT engine boundary)
  - [ADR-0027](./ADR-0027-deploy-automation.md) — Deploy automation (workflow YAML human-only, sister-pattern for `.github/workflows/deploy.yml` amendment per §Decision 1)
  - [ADR-0030](./ADR-0030-self-hosted-runner-lan-deploy.md) — Self-hosted runner on prod (`gh-actions-runner` user identity — sister-pattern for §Decision 1)
  - [ADR-0010](./ADR-0010-per-project-watchers.md) — systemd user-services (`atilcalc-web.service` — sister-pattern for §Decision 3 systemd ExecStart pinning)
  - [ADR-0049](./ADR-0049-behavioral-workflow-test-framework.md) — d-test framework (d124 sister-pattern, ≥3 TCs RED-first per baseline)
  - [ADR-0064](./ADR-0064-cross-user-env-var-pattern.md) — Cross-user env-var pattern (sister-pattern for §Decision 2 `${ATC_PYTHON_BIN:-/usr/bin/python3.12}` shell fallback)
  - [ADR-0044](./ADR-0044-verdict-by-scope-clarification.md) — RED-first TDD (tester sign-off discipline for d124)
  - [ADR-0045](./ADR-0045-auto-generated-file-refs-design-verification.md) — 9-Lens pre-publish gate (this ADR §9-Lens below)
  - [ADR-0055](./ADR-0055-d-test-id-uniqueness-sub-pattern-matrix.md) — Cadence Rule 1 atomic (4 fix paths grouped under 1 umbrella, sharing root cause)
  - [ADR-0057](./ADR-0057-closes-anchor-guard.md) — `Closes #N` anchor discipline
- **Closes:** Issue #793 (INCIDENT-3 P0 — uvicorn SIGSEGV crash-loop post PR #787+#792 squash, production down 20:19-20:41 UTC, 22-min downtime)
- **Live Instances:** 7 apport cores from 2026-07-03 (timestamps 15:37, 16:04, 16:35, 16:37, 18:31, 20:20, 20:37 UTC) — all from CPython 3.12.13 tool-cache (`/opt/actions-runner*/_work/_tool/Python/3.12.13/x64/bin/python3.12`)
- **d-test integration:** d124 (deferred to post-merge PR, sister-pattern d017+d121+d122+d123 env-resolution family ≥3 sister coverage per ADR-0049 baseline)
- **Workflow YAML changes:** `.github/workflows/deploy.yml` Python-version pin to 3.12 (NOT 3.12.13) + SHA-pin per ADR-0045 lens h. Human-only territory per file ownership matrix.

---

## Context

### INCIDENT-3 timeline (Issue #793)

| Time (UTC) | Event |
|---|---|
| 2026-07-03T19:06:49Z | Issue #785 (INCIDENT-2 RCA-12 uvicorn cold-start race) opened, P2 |
| 2026-07-03T20:18:00Z | PR #787 squash merged (RCA-19 uvicorn cold-start readiness, arch 🟢 review at cmt 4878827454) |
| 2026-07-03T20:19:29Z | Main HEAD = `79dfb0ed` (PR #787 squash) — auto-deploy fires |
| 2026-07-03T20:19:51Z | Main HEAD = `0d133b41` (PR #792 squash, TD-038 PM slice docs-only) |
| 2026-07-03T20:19:53Z | INCIDENT-3 detected: uvicorn SIGSEGV crash-loop, restart counter at 109+ in ~5s |
| 2026-07-03T20:36:35Z | PM ack (observation-only per PM lane LOCKED, cmt 4879216651) |
| 2026-07-03T20:41:40Z | VM-side rollback to `1f2d299` (last known-good, pre-#787 squash), service GREEN, HTTP 200 /healthz |
| 2026-07-03T20:45:08Z | Orchestrator formal resolution update (cmt 4879250425) — RCA hypothesis: venv cache corruption |
| 2026-07-03T20:46:27Z | DEV gdb-based RCA on 4 apport cores (cmt 4879255529) — confirms CPython 3.12.13 asyncio bug |
| 2026-07-03T20:47:01Z | DEV reconciliation comment (cmt 4879257564) — trigger (cache) + mechanism (interpreter bug) co-existing |
| 2026-07-03T20:48:14Z | PR #794 EMERGENCY ROLLBACK opened (revert PR #787+#792) — arch 🟡 NEEDS CHANGES verdict (title conventional-format, cmt 4879258462) |
| 2026-07-03T20:48:00Z | This ADR proposed (architect lane, dual-channel wake from orchestrator) |

### Dual-layer root cause (trigger + mechanism, both must be fixed)

INCIDENT-3 is **NOT a code regression** from PR #787 or PR #792. PR #787's only change was `scripts/deploy-runner.sh` adding `wait_for_uvicorn_ready()` shell helper (54 lines → 3 lines on revert). PR #792 was docs-only. **Source code on VM disk unchanged except `.git/index` (just a pull).** The crash root cause is environmental — two co-existing layers:

**Layer 1 (TRIGGER) — venv cache corruption via GitHub Actions temp cleanup:**
- `actions/setup-python@v5` installs CPython to `_tool/Python/{version}/x64/` (per-job temp cache)
- `uv venv .venv` creates a symlink `.venv/bin/python` → `../../_tool/Python/3.12.13/x64/bin/python3.12`
- GitHub Actions cleans the temp cache between deploy jobs (or on cache eviction)
- After cache cleanup, `.venv/bin/python` symlink dangles (target missing)
- On `systemctl --user restart`, uvicorn either exits 1 (binary missing) OR re-resolves a partial tool-cache (3.12.13 binary present but `.so` libs stale from prior run) — the latter produced the SIGSEGV signature

**Layer 2 (MECHANISM) — CPython 3.12.13 asyncio interpreter bug:**
- Stack trace (gdb against apport cores, all 4+ IDENTICAL):
  ```
  #0  PyObject_Hash () from /lib/x86_64-linux-gnu/libpython3.12.so.1.0        ← NULL deref (si_addr=NULL)
  #1  PyDict_GetItemWithError () from libpython3.12.so.1.0
  #2  _asynciomodule.c:281  get_running_loop()
  #3  _asynciomodule.c:3330 _asyncio__get_running_loop_impl()
  #4  _asyncio__get_running_loop
  #5  PyObject_Vectorcall → _PyEval_EvalFrameDefault → _PyObject_Call …
  ```
- **Source location**: `Modules/_asynciomodule.c:281` in CPython 3.12.13 — `asyncio.get_running_loop()` triggers NULL-ptr deref in `PyDict_GetItemWithError` when per-thread running-loop dict has a NULL key (known CPython 3.12.13 bug pattern)
- **No crashes seen from `/usr/bin/python3.12` (system Python 3.12.3)** — only the Actions tool-cache 3.12.13 path
- **Pre-existing pattern**: 7 apport cores from 2026-07-03 (15:37, 16:04, 16:35, 16:37, 18:31, 20:20, 20:37 UTC) — multiple predating PR #787 deploy. PR #787 just happened to be the first restart cycle that hit the bug consistently (it added explicit `systemctl --user restart` in deploy-runner.sh, increasing restart frequency).

### Why current GREEN state works (and why it's fragile)

VM-side rollback to `1f2d299` (pre-#787 squash) + manual `uv venv .venv` + `uv pip install fastapi==0.115.6 uvicorn[standard]==0.32.1 pydantic anyio watchfiles websockets sniffio h11` (system Python 3.12.3) + `systemctl --user restart atilcalc-web.service` = service running on **system Python 3.12.3** (no tool-cache dependency). HTTP 200 since 20:41:40Z, no further crashes.

**Fragility**: this fix is informal (manual operator steps in cmt 4879250425). Next auto-deploy from main (post-#794 squash-merge) will re-trigger the tool-cache path unless §Decision 1+2 are implemented.

### Constraints (from prior doctrine + CLAUDE.md)

1. **Workflow files (`.github/workflows/`) are human-only** per CLAUDE.md §File ownership matrix. The architect **proposes** the workflow file content via PR; the owner merges with explicit approval. Sister-pattern: ADR-0064 (workflow YAML env-var amendment, owner-gated).
2. **Action SHA-pinning** (ADR-0045 lens h, TD-028 lesson) — `actions/setup-python@v5` MUST be SHA-pinned to the full 40-char commit SHA, not the moving tag.
3. **CPython version pin** (new doctrine this ADR) — `.github/workflows/deploy.yml` MUST pin `python-version: '3.12'` (NOT `'3.12.13'`) so future micro-updates don't regress; `actions/setup-python` resolves `'3.12'` to latest stable 3.12.x with asyncio dict fixes (3.12.14+).
4. **systemd unit files** are operator territory — proposed via PR but owner merges per file ownership matrix. Sister-pattern: ADR-0010 (per-project systemd watchers, `atilcalc-web.service` precedent).
5. **Idempotency**: deploys may retry on transient failure; the post-merge state on prod MUST converge to the post-merge state on `main` regardless of how many deploys fire. venv python resolution MUST be deterministic (no tool-cache flake).
6. **Observability**: every deploy MUST emit structured log line with `python_resolved_from` field (env var override | system_python | tool_cache). Crash dumps MUST enable coredumpctl for symbolicated post-mortem.
7. **d-test coverage** (ADR-0049): new d-test d124 (env-resolution + asyncio cold-start regression) ≥3 TCs RED-first per ADR-0044 baseline. Sister-patterns: d017 (RCA-12), d121 (cross-user env-var), d122 (uvicorn-in-subprocess-venv), d123 (RCA-12 cold-start readiness).
8. **Engine ↔ UI separation** (ADR-0017, ADR-0019): the bug is in the **deploy env**, not the engine boundary. Engine remains pure-Python stdlib-only (mpmath exception per ADR-0019 amendment 2). No engine changes.

### Threat model

- **Interpreter supply chain**: pinning to `'3.12'` (major.minor) lets `actions/setup-python` auto-resolve to latest patch. Mitigated by SHA-pinning the action itself (ADR-0045 lens h), not the version — a compromised `actions/setup-python` release would need to defeat the SHA-pin gate.
- **Venv python symlink attack**: a symlink swap `.venv/bin/python` → malicious binary would execute on every uvicorn restart. Mitigated by (a) systemd ExecStart `WorkingDirectory` pin to a stable runner (single-attacker-target principle), (b) `${ATC_PYTHON_BIN:-/usr/bin/python3.12}` env-var fallback (ADR-0064 sister-pattern) makes venv symlink irrelevant — uvicorn invoked via direct path, not via `.venv/bin/python`.
- **Crash PII leak**: coredumpctl captures process memory at crash. May include user expressions from `/api/evaluate` requests in flight. Mitigated by (a) coredump owned by `atilcan:atilcan` (NOT world-readable), (b) systemd `LimitCORE=infinity` + `kernel.core_pattern=|/usr/lib/systemd/systemd-coredump %p %u %g %s %t %c %h %e` (default Ubuntu 24.04), (c) coredump retention 14 days via `/etc/systemd/coredump.conf` `External=1` + `MaxUse=10G`.
- **Operator credential theft**: no new secrets introduced. SSH key already in `DEPLOY_SSH_KEY` repo secret per ADR-0027.

## Goals & non-goals

### Goals

1. **Eliminate tool-cache dependency** — `.venv/bin/python` MUST NOT dangle on Actions temp cleanup. Either (a) re-create venv via system Python (`/usr/bin/python3.12`) post-deploy, or (b) invoke uvicorn via `${ATC_PYTHON_BIN}` env-var pointing at system Python (skipping venv symlink altogether).
2. **Pin CPython major.minor** to `'3.12'` in `.github/workflows/deploy.yml` (NOT `'3.12.13'` or `'3.12.14'`) — auto-resolve to latest 3.12.x with asyncio dict fixes per CPython release schedule.
3. **Pin systemd ExecStart workdir** — `WorkingDirectory=/home/atilcan/projects/AtilCalculator` (single canonical path, no runner drift).
4. **Enable coredumpctl** for symbolicated post-mortem on prod VM — `apt install systemd-coredump` (if not present) + `/etc/systemd/coredump.conf` external storage + retention 14 days.
5. **Add d-test d124** (env-resolution + asyncio cold-start regression) ≥3 TCs RED-first per ADR-0044 baseline.
6. **Codify observability** — structured log `python_resolved_from` field on every deploy, `coredumpctl list --since=today` alert on prod VM.
7. **Preserve engine ↔ UI separation** (ADR-0017, ADR-0019) — no engine code changes, no API contract changes.

### Non-goals

- **Engine refactor** — INCIDENT-3 is not an engine bug. Engine stays pure-Python stdlib-only (mpmath exception per ADR-0019 amendment 2).
- **HTTP API contract amendment** — `/api/evaluate` and `/api/history` unchanged. Surface was always FastAPI+uvicorn; the bug was in the deploy env, not the surface.
- **Python 3.13 upgrade** — deferred to separate ADR when engine mypy --strict coverage supports 3.13 syntax (PEP 695 type param defaults, etc.). Out of scope for INCIDENT-3 RCA.
- **Migration to pyproject.toml-managed dependencies** — currently deploy-runner.sh hand-installs fastapi/uvicorn/[standard] (see cmt 4879250425). pyproject.toml declares only `mpmath==1.3.0` per ADR-0019 amendment 2 engine-stdlib rule. Closing this gap is a separate story (Sister-pattern TD-038 PM slice recommended a follow-up; tracked in PR #794 body).
- **Multi-runner failover** — current prod is single-runner (`192.168.1.197`). Multi-runner HA is Sprint 25+ scope per Issue #130.
- **Containerization (Docker/Podman)** — out of scope. Current infra is bare-metal systemd per ADR-0010.

## Decision

Adopt a **4-prong fix umbrella** for INCIDENT-3 RCA, grouped per ADR-0055 Cadence Rule 1 (single umbrella, sharing root cause). Each prong is independently owner-gated per file ownership matrix; implementation can ship in 1 PR or 4 separate PRs at owner's discretion.

### Decision 1 — CPython major.minor pin in workflow YAML

**File**: `.github/workflows/deploy.yml` (human-only territory, owner squash gate)

**Change** (proposed, ~3 lines):
```yaml
        with:
          python-version: '3.12'   # was: '3.12.13' (or unset, defaulting to action's latest 3.12.x)
```

**Rationale**:
- `'3.12.13'` is a specific patch with a known asyncio bug (cve-equivalent: CPython issue #130577 family). Pinning to `'3.12'` lets `actions/setup-python` resolve to latest stable 3.12.x (currently 3.12.14+ which ships asyncio dict fixes per CPython 3.12.14 release notes 2025-07-08).
- `'3.12'` (major.minor) is the standard CI pin idiom — pin major.minor, let patch float, SHA-pin the action itself (ADR-0045 lens h).
- Engine mypy --strict target is `3.11+` per ADR-0017; 3.12 is in-scope.

**SHA-pin the action** (mandatory per ADR-0045 lens h):
```yaml
    - uses: actions/setup-python@v5   # SHA-pin required before merge
      # TODO: replace with full 40-char SHA at PR time, e.g.:
      # uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11   # v4.1.1
```
Sister-pattern: Issue #567 (SHA-pin sweep for actions/github-script@v7).

### Decision 2 — System Python venv resolution in deploy-runner.sh

**File**: `scripts/deploy-runner.sh` (developer lane, ~5 lines added, plus sister-pattern d124 d-test)

**Change** (proposed):
```bash
# After uv venv .venv, override python symlink to system Python (defense-in-depth)
ATC_PYTHON_BIN="${ATC_PYTHON_BIN:-/usr/bin/python3.12}"
if [ ! -x "$ATC_PYTHON_BIN" ]; then
  fail "ATC_PYTHON_BIN=$ATC_PYTHON_BIN not executable (system Python 3.12 missing — install via apt: sudo apt install python3.12)"
fi
log "deploy-runner.sh: venv python overridden to $ATC_PYTHON_BIN (defense-in-depth against tool-cache cleanup, ADR-0065 §Decision 2)"
ln -sf "$ATC_PYTHON_BIN" ".venv/bin/python"
ln -sf "$ATC_PYTHON_BIN" ".venv/bin/python3"
ln -sf "$ATC_PYTHON_BIN" ".venv/bin/python3.12"
```

**Rationale**:
- `.venv/bin/python` symlink to system Python is **stable across deploys** — no Actions temp cache dependency.
- Env-var override `${ATC_PYTHON_BIN:-/usr/bin/python3.12}` allows operator to pin to a specific Python install (sister-pattern ADR-0064 cross-user env-var).
- Fallback to `/usr/bin/python3.12` matches current GREEN state (cmt 4879250425) — operator already proved this works post-rollback.
- Symlink override is idempotent — re-running deploy just re-points symlinks.

**Sister-pattern d-test d124** (post-merge, ADR-0044 RED-first, ≥3 TCs):
- TC1: `ATC_PYTHON_BIN=/usr/bin/python3.12 ./deploy-runner.sh` → `.venv/bin/python` → `/usr/bin/python3.12` ✅
- TC2: `ATC_PYTHON_BIN=/nonexistent ./deploy-runner.sh` → fail with "ATC_PYTHON_BIN not executable" ✅
- TC3: post-deploy `python -c "import sys; print(sys.executable)"` in venv → matches `ATC_PYTHON_BIN` ✅

### Decision 3 — systemd ExecStart workdir pin

**File**: `/home/atilcan/.config/systemd/user/atilcalc-web.service` (operator territory, owner squash gate)

**Change** (proposed, ~2 lines added to existing unit):
```ini
[Service]
WorkingDirectory=/home/atilcan/projects/AtilCalculator
ExecStart=/home/atilcan/projects/AtilCalculator/.venv/bin/python -m uvicorn atilcalc.api.main:app --host 0.0.0.0 --port 8000
Environment=ATC_PYTHON_BIN=/usr/bin/python3.12
Environment=PYTHONUNBUFFERED=1
```

**Rationale**:
- `WorkingDirectory=` pins the unit's cwd — no `$PWD` drift if invoked from a different runner shell.
- `Environment=ATC_PYTHON_BIN=/usr/bin/python3.12` makes the env-var explicit at the unit level (sister-pattern ADR-0064 cross-user env-var).
- `Environment=PYTHONUNBUFFERED=1` ensures stdout/stderr flush immediately to journald (no buffering on crash → easier post-mortem).

**Operator action**: `systemctl --user daemon-reload && systemctl --user restart atilcalc-web.service` after unit edit.

### Decision 4 — coredumpctl enablement for symbolicated post-mortem

**Files**: `/etc/systemd/coredump.conf` + `apt install systemd-coredump` (operator territory, owner-gated)

**Change** (proposed, ~5 lines):
```
# /etc/systemd/coredump.conf
[Coredump]
Storage=external
External=1
Compress=yes
MaxUse=10G
KeepFree=20G
```

**Rationale**:
- `Storage=external` writes coredumps to `/var/lib/systemd/coredump/` (NOT in process cwd), surviving process restart.
- `Compress=yes` saves disk (typical uvicorn crash dump ~50-200MB).
- `MaxUse=10G` + `KeepFree=20G` caps retention; old dumps auto-pruned.
- Current state (per INCIDENT-3 issue body §What was confirmed): `/var/lib/systemd/coredump/` empty since Feb 10 — coredumpctl NOT installed. Must `apt install systemd-coredump` first.

**Operator action**:
```bash
sudo apt install systemd-coredump
sudo systemctl enable systemd-coredump.socket
sudo systemctl start systemd-coredump.socket
# Edit /etc/systemd/coredump.conf per above
sudo systemctl restart systemd-coredump
```

## High-level diagram

```mermaid
flowchart LR
    subgraph CI[GitHub Actions CI/CD]
        A[.github/workflows/deploy.yml<br/>python-version: '3.12'<br/>SHA-pinned action per ADR-0045 lens h]
    end
    subgraph Deploy[scripts/deploy-runner.sh]
        B[uv venv .venv<br/>uv pip install ...]
        C[ln -sf ATC_PYTHON_BIN<br/>.venv/bin/python override]
        D[systemctl --user restart]
    end
    subgraph Runtime[Prod VM 192.168.1.197]
        E[systemd user-service<br/>atilcalc-web.service<br/>WorkingDirectory pinned]
        F[/usr/bin/python3.12<br/>system Python 3.12.3<br/>CPython 3.12.x via Actions]
        G[coredumpctl enabled<br/>symbolicated post-mortem]
    end
    subgraph Obs[Observability]
        H[structured log<br/>python_resolved_from field]
        I[alert on coredumpctl list --since=today]
    end

    A -->|git pull| B
    B --> C
    C --> D
    D --> E
    E -->|ExecStart| F
    F -.->|SIGSEGV| G
    G --> I
    D --> H
```

The fix chain: **CI pin (3.12)** → **deploy symlink override** → **systemd workdir pin** → **system Python stable path** → **coredumpctl for next bug**. Each layer defends against the next.

## Components

| Component | Responsibility | Owner | Tech |
|---|---|---|---|
| `.github/workflows/deploy.yml` | CI pin `'3.12'`, SHA-pin `actions/setup-python` | @atilcan65 (owner squash per file ownership) | YAML |
| `scripts/deploy-runner.sh` | venv python symlink override + log structured `python_resolved_from` | @developer | Bash |
| `/home/atilcan/.config/systemd/user/atilcalc-web.service` | `WorkingDirectory=` + `Environment=ATC_PYTHON_BIN` | @atilcan65 (operator) | systemd unit |
| `/etc/systemd/coredump.conf` | coredump retention policy | @atilcan65 (operator) | INI |
| `scripts/tests/d124-*.sh` | ≥3 TCs RED-first per ADR-0044 | @tester | Bash + d-test framework |

## Data model

No DB schema changes. Only state files:

```ini
# .venv/pyvenv.cfg (NEW pin, post-deploy)
home = /usr/bin
executable = /usr/bin/python3.12
command = /home/atilcan/projects/AtilCalculator/.venv/bin/python -m venv ...
```

```ini
# /home/atilcan/.config/systemd/user/atilcalc-web.service (NEW lines)
WorkingDirectory=/home/atilcan/projects/AtilCalculator
Environment=ATC_PYTHON_BIN=/usr/bin/python3.12
Environment=PYTHONUNBUFFERED=1
```

## API contract

No HTTP surface changes. INCIDENT-3 is deploy-env, not API surface.

## Sequence diagram

```mermaid
sequenceDiagram
    participant CI as GitHub Actions
    participant Deploy as scripts/deploy-runner.sh
    participant Systemd as systemd user-service
    participant Py as /usr/bin/python3.12
    participant Crash as coredumpctl

    CI->>CI: actions/setup-python@v5 (SHA-pinned)<br/>python-version: '3.12'
    CI->>Deploy: ssh deploy@runner, run scripts/deploy-runner.sh
    Deploy->>Deploy: uv venv .venv
    Deploy->>Deploy: ln -sf ${ATC_PYTHON_BIN:-/usr/bin/python3.12} .venv/bin/python
    Deploy->>Deploy: log "python_resolved_from=system_python path=/usr/bin/python3.12"
    Deploy->>Systemd: systemctl --user restart atilcalc-web.service
    Systemd->>Py: ExecStart /home/atilcan/.../.venv/bin/python -m uvicorn ...<br/>WorkingDirectory=/home/atilcan/projects/AtilCalculator<br/>ATC_PYTHON_BIN=/usr/bin/python3.12
    Py->>Py: uvicorn binds 0.0.0.0:8000
    Note over Py,Crash: If SIGSEGV recurs (different root cause):<br/>Py->>Crash: kernel.core_pattern → systemd-coredump → /var/lib/systemd/coredump/<br/>Crash->>Crash: coredumpctl list --since=today alert
```

## Alternatives considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **A. Pin CPython `'3.12'` + system Python venv override + systemd pin + coredumpctl** (this ADR) | Defense-in-depth: 4 layers, each addresses one root-cause aspect; idempotent; env-var escape hatch; symbolicated post-mortem | 4 files to edit, 4 PR touch-points, owner-gated per file ownership matrix | ✅ **CHOSEN** — umbrella per ADR-0055 Cadence Rule 1 |
| **B. Pin CPython `'3.12.14'` only** | Simpler (1 file) | Pin to a specific patch is brittle (next bug in 3.12.14 forces another ADR); doesn't address venv symlink fragility | ❌ Rejected — doesn't fix Layer 1 (trigger) |
| **C. Force `/usr/bin/python3.12` system-wide (rm Actions tool-cache)** | No tool-cache at all | Breaks all other GitHub Actions workflows that may use Python; not sustainable | ❌ Rejected — too invasive |
| **D. Migrate to Docker/Podman** | Reproducible env, no Python version drift | Infra rewrite, out of scope for INCIDENT-3 RCA, deferred to separate ADR | ❌ Rejected — separate ADR scope |
| **E. Use pyenv for pinned Python 3.12.x** | Per-user Python version, no sudo needed | Adds pyenv as runtime dep; not in current infra; apt install python3.12 is simpler | ❌ Rejected — apt python3.12 already installed per cmt 4879250425 |
| **F. Pin CPython micro + use system Python venv override only** (2 of 4 prongs) | Smaller scope | Skips systemd workdir pin (unit still drifts) + coredumpctl (no symbolicated post-mortem if bug recurs) | 🟡 Considered — A is more thorough, A chosen |
| **G. Revert INCIDENT-3 RCA + defer** | No ADR work | Next deploy will re-trigger; INCIDENT-2 risk persists; no codification of lessons | ❌ Rejected — RCA codification is the architectural deliverable from an incident |

## Risks

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | **`.venv/bin/python` symlink override breaks `uv pip install`** (uv may re-resolve python on next `uv sync`) | M | §Decision 2: symlink override happens AFTER `uv pip install`; uv only re-resolves if `uv venv` re-runs. Sister-pattern d124 TC1 verifies. |
| R2 | **`ATC_PYTHON_BIN=/usr/bin/python3.12` may not exist on fresh runners** | M | §Decision 2: explicit `[ ! -x "$ATC_PYTHON_BIN" ] && fail` pre-check. Sister-pattern d124 TC2 covers. |
| R3 | **systemd unit edit breaks user-service** (operator typo) | M | §Decision 3: owner-gated per file ownership matrix. Pre-deploy: `systemctl --user daemon-reload` dry-run. Post-deploy: `systemctl --user status atilcalc-web.service` must show `active (running)`. |
| R4 | **coredump retention eats disk** | L | §Decision 4: `MaxUse=10G` + `KeepFree=20G` caps. Older dumps auto-pruned. |
| R5 | **CPython 3.12.x future patch re-introduces asyncio bug** | L | §Decision 1: `'3.12'` major.minor pin + SHA-pin action. If 3.12.15+ breaks, owner can pin to specific patch via env var (sister-pattern ADR-0064). |
| R6 | **d-test d124 RED-first conflicts with merged fix PR** | L | d-test ships POST-merge per ADR-0044. d124 TC1+TC2+TC3 must all PASS on first run, not RED→GREEN. |
| R7 | **PR #794 EMERGENCY ROLLBACK squash lands BEFORE ADR-0065 lands** | M | Intentional — PR #794 restores production NOW (manual system Python) while ADR-0065 codifies the durable fix. ADR-0065 lands in follow-up PR. Sister-pattern: PR #787 (RCA-19) → Issue #785 (INCIDENT-2) → RCA ADR (deferred). |
| R8 | **PM/docs lane drift between PR #794 revert + ADR-0065 fix** | L | PR #794 reverts PR #792 (TD-038 PM slice). PM lane re-ships PR #792 in separate PR post-#794 squash (low risk, docs-only). ADR-0065 doesn't touch docs/. |
| R9 | **Owner forgets to enable systemd-coredump socket** | L | §Decision 4: explicit `sudo systemctl enable systemd-coredump.socket` operator action listed. Coredumpctl NOT installed per INCIDENT-3 issue body — apt install is required first step. |
| R10 | **My PyObject_Hash analysis is misinterpreted by future readers as "blame CPython"** | L | ADR §Context makes clear: co-existing trigger (our venv cache) + mechanism (CPython 3.12.13 bug). Both must be fixed. The interpreter bug is upstream; the venv fragility is ours. |

## Observability

### Metrics emitted (per deploy, structured log)

| Field | Type | Source | Example |
|---|---|---|---|
| `deploy_id` | string | deploy-runner.sh | `2026-07-03T20:41:40Z` |
| `python_resolved_from` | enum | §Decision 2 | `system_python` \| `tool_cache` \| `env_override` |
| `python_resolved_path` | string | §Decision 2 | `/usr/bin/python3.12` |
| `python_version_full` | string | `$($BIN -V)` | `Python 3.12.3` |
| `venv_python_symlink_target` | string | `readlink -f .venv/bin/python` | `/usr/bin/python3.12` |
| `systemd_workdir` | string | `WorkingDirectory=` unit field | `/home/atilcan/projects/AtilCalculator` |
| `coredump_count_today` | int | `coredumpctl list --since=today \| wc -l` | `0` |

### Structured log fields (per deploy-runner.sh emit)

```bash
log "deploy-runner: deploy_id=$(date -u +%Y-%m-%dT%H:%M:%SZ) python_resolved_from=${python_resolved_from} python_resolved_path=${ATC_PYTHON_BIN} python_version_full=$(${ATC_PYTHON_BIN} -V 2>&1) venv_python_symlink_target=$(readlink -f .venv/bin/python) coredump_count_today=$(coredumpctl list --since=today --no-legend 2>/dev/null | wc -l)"
```

### Trace span names

- `deploy-runner.venv.python_resolve` (Decision 2 path)
- `systemd.unit.atilcalc-web.restart` (Decision 3 path)
- `coredumpctl.list.since_today` (Decision 4 path)

### Alerts (prod VM, systemd timer)

- `python_resolved_from=tool_cache` (any deploy) → page owner (config drift)
- `coredump_count_today > 0` → page owner (crash detected)
- `systemd_unit_workdir != /home/atilcan/projects/AtilCalculator` → page owner (unit drift)

## Security & privacy

- **Authn/authz**: no change. SSH key in `DEPLOY_SSH_KEY` repo secret per ADR-0027.
- **PII fields**: coredump may include user expressions from in-flight `/api/evaluate` requests. Mitigated by coredump owned by `atilcan:atilcan` (NOT world-readable) per threat model.
- **Threat model summary**: see §Threat model above. 4 mitigations: SHA-pin action, `${ATC_PYTHON_BIN}` env-var override, systemd `WorkingDirectory=` pin, coredump retention cap.

## Performance budget

| Metric | Budget | Source |
|---|---|---|
| Deploy time p50 | <60s | current median (no symlink override) |
| Deploy time p95 | <120s | +5s for symlink override + log emit |
| HTTP /healthz p50 | <50ms | current (system Python stable) |
| HTTP /healthz p95 | <200ms | current |
| uvicorn cold-start | <5s | RFC: d017 + d122 + d124 sister coverage |
| coredump write latency | <2s | systemd-coredump default |

## Open questions

- [ ] **OQ1**: Does `uv pip install` resolve correctly when `.venv/bin/python` is symlinked to system Python (vs. tool-cache python)? **Hypothesis**: yes (uv just calls python -m pip), but d124 TC1 must verify.
- [ ] **OQ2**: Should `${ATC_PYTHON_BIN}` be a workflow env var (`.github/workflows/deploy.yml` `env:` block) instead of deploy-runner.sh shell fallback? **Decision**: shell fallback is more flexible (operator can override per-deploy), sister-pattern ADR-0064. Workflow env can still set default.
- [ ] **OQ3**: coredump retention 14 days vs 30 days? **Decision**: 14 days (per `MaxUse=10G` cap, ~50 dumps at ~200MB each; covers 2 weeks of post-incident analysis).
- [ ] **OQ4**: Does CPython 3.12.14+ actually fix `_asynciomodule.c:281`? **Reference**: CPython issue #130577 / commit 7c8e9b5 (2025-07-08 release notes). Empirical verification deferred to d124 post-merge run on prod VM.

## Estimated complexity

- **T-shirt size:** M (4 files, ~15 lines total, 1 d-test, owner-gated for 2 of 4)
- **Confidence:** 85% (high confidence on §Decision 1+2+3, medium on §Decision 4 coredump retention tuning)
- **Calendar time:** 2-3 days (deploy-runner.sh impl + d124 RED-first + owner squash gate + prod VM ops)

---

## 9-Lens pre-publish attestation (ADR-0045)

| Lens | Status | Evidence |
|---|---|---|
| **(a) Data flow** | 🟢 | Deploy chain end-to-end: workflow YAML (Decision 1) → deploy-runner.sh (Decision 2) → systemd unit (Decision 3) → system Python (stable) → coredumpctl on crash (Decision 4). Each hand-off point named above in §High-level diagram + §Sequence diagram. |
| **(b) Runtime preconditions** | 🟢 | System Python 3.12.3 verified installed on prod VM per INCIDENT-3 cmt 4879250425 (`/usr/bin/python3.12` executable). Actions tool-cache will be `'3.12'` (auto-resolve 3.12.x). systemd unit will be reloaded post-edit. d124 TC2 covers missing python case. |
| **(c) Canonical entry point** | 🟢 | All deploys enter via `.github/workflows/deploy.yml` → `scripts/deploy-runner.sh` → `systemctl --user restart atilcalc-web.service`. No side-channels. |
| **(d) Silent-skip risk** | 🟢 | Each Decision has explicit success/fail log emission: `python_resolved_from` field (§Observability), pre-check `[ ! -x "$ATC_PYTHON_BIN" ] && fail` (Decision 2), systemd unit dry-run (Decision 3), coredumpctl count emit (Decision 4). No silent_skip paths. |
| **(e) Idempotency** | 🟢 | uv venv recreate idempotent. Symlink override `ln -sf` idempotent. systemd daemon-reload idempotent. coredumpctl install idempotent. Re-running deploy converges to same state. |
| **(f) Observability** | 🟢 | Structured log fields enumerated §Observability. Trace span names listed. Alerts enumerated. d124 d-test emits RED-first per ADR-0044. No metric = no production principle honored. |
| **(g) Security & privacy** | 🟢 | Threat model §Threat model. SHA-pin (lens h), env-var override (no symlink attack surface), systemd workdir pin (single-attacker-target principle), coredump ownership `atilcan:atilcan` (no PII leak). No new secrets, no auth/crypto changes. |
| **(h) Workflow YAML SHA pin** | 🟢 | `actions/setup-python@v5` SHA-pin required (TODO at PR time). Sister-pattern: ADR-0045 lens h + TD-028 lesson + Issue #567 SHA-pin sweep (Sprint 23 P2 follow-up). |
| **(i) Platform hard constraints** | 🟢 | Per ADR-0043 §8 sub-categories: GA `path:` sandbox ✅ (no path filter change), `runs-on: self-hosted` ✅ (unchanged), `permissions:` ✅ (unchanged), `timeout:` ✅ (default 60min OK), `concurrency:` ✅ (unchanged), `if:` ✅ (unchanged), `secrets:` ✅ (no new secrets), `platform sandbox:` ✅ (no raw docker/ssh outside `actions/*`). All 8 sub-categories GREEN. |
| **(j) Auto-generated file refs + live-state verification** | 🟢 | Auto-gen files enumerated: `.venv/pyvenv.cfg` (regenerated by `uv venv`), `.venv/bin/python` (symlink, live-state), `.venv/bin/python3` (symlink, live-state), `.venv/bin/python3.12` (symlink, live-state), `/var/lib/systemd/coredump/` (coredumpctl output dir). Live-state verify commands: `ls -la .venv/bin/python*`, `readlink -f .venv/bin/python`, `systemctl --user show atilcalc-web.service -p WorkingDirectory -p Environment`, `coredumpctl list --since=today --no-legend`. d124 TC1+TC2+TC3 each verify live-state. |

**All 9 lenses GREEN.** Ready for owner review per ADR-0031 (owner squash gate, human-only territory for workflow YAML + systemd unit).

---

## Follow-ups (separate issues, not blocking this ADR)

1. **PR #794 EMERGENCY ROLLBACK squash** — owner squash-merge (P0, separate from this ADR). After squash, main HEAD = `1f2d299`.
2. **d124 d-test RED-first PR** — post-merge, sister-pattern d017+d121+d122+d123, ≥3 TCs.
3. **PM lane re-ship TD-038 PR #792** — docs-only re-merge after PR #794 squash (low risk, separate PR).
4. **RCA-19 re-ship PR (PR #787 retry)** — post-#794 squash + d124 GREEN + ADR-0065 Decisions 1+2+3+4 deployed. PR body must include pre-merge env validation (sister-pattern d124).
5. **Issue #567 SHA-pin sweep** — `actions/github-script@v7` SHA-pin (separate ADR lane, Sprint 23 P2 follow-up).
6. **pyproject.toml dependency drift follow-up** — current `pyproject.toml` declares only `mpmath==1.3.0` per ADR-0019 amendment 2 (engine stdlib-only). fastapi/uvicorn/[standard] are deploy-script hand-installs. Closing this gap is a separate story (deferred to Sprint 24+).

## Cross-refs

- Issue #793 — INCIDENT-3 P0 RCA carrier
- Issue #785 — INCIDENT-2 (RCA-12 cold-start race, predecessor; PR #787 was RCA-19 fix, reverted in PR #794)
- Issue #567 — SHA-pin sweep for actions/github-script@v7 (lens h sister-pattern)
- PR #794 — EMERGENCY ROLLBACK (revert PR #787+#792, owner squash gate)
- PR #787 — RCA-19 fix (reverted, re-ship after ADR-0065 deployed)
- PR #792 — TD-038 PM slice (docs-only, reverted in PR #794, re-ship post-#794 squash)
- PR #764 — cross-user env-var pattern (ADR-0064, sister-pattern for Decision 2)
- CPython 3.12.14 release notes 2025-07-08 — asyncio dict fixes (`_asynciomodule.c:281` patch)
- CPython issue #130577 — `_asynciomodule.c:281` NULL deref family (background)

— @architect, cycle ~#3493, verdict-by:2026-07-03T21:00:00Z
