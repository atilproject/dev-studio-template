# ADR-0017 — Tech stack for AtilCalculator

**Status:** Accepted (original via PR #5 at 30c93f4 on 2026-06-17T15:16:07Z) + **Amended 2026-06-24** (this PR) — §CLI scaffolding stdlib-argparse fallback clause added per Sprint 7 empirical evidence (PR #314, #318).
**Date:** 2026-06-17 (original), 2026-06-24 (amendment)
**Deciders:** @architect (drafting), @atilcan65 (final approval), @product-manager (CONDITIONAL APPROVE on engine layer + engine↔UI separation, see PR #5 thread) + @developer (no-objection-from-record on Typer + mypy-strict scope) + @tester (consulted via PR review)
**Accepted:** 2026-06-17 via PR #5 (commit 30c93f4). Housekeeping flip from Proposed → Accepted performed 2026-06-17 alongside ADR-0018 (same PR).
**Supersedes:** —
**Related:** ADR-0010 (per-project watchers, Bash+systemd), ADR-0012 (label invariant), ADR-0014 (PROJECT_TOKEN canary), ADR-0016 (public-by-default). Vision intake Issue #4 — `[Vision] AtilCalculator` (web-first browser calculator on LAN VM).

---

## Context

`.claude/CLAUDE.md` §Tech stack carried the placeholder
`<FILL IN: languages, frameworks, infra. Architect maintains this.>` since
template render. Sprint 0 cannot start any feature story until that
placeholder is resolved.

The product vision (Issue #4 by @product-manager) confirms:

- **Web-first delivery**: always-open browser tab on the LAN, served
  from a Linux VM (Ubuntu 24.04 at 192.168.1.199).
- **Keyboard-first UX** (Enter=equals, Esc=clear, digit/op keys map
  directly; mouse not required).
- **Decimal-precision arithmetic** (0 IEEE-754 errors — `0.1 + 0.2 == 0.3`
  must hold per vision M1).
- **Persistent history** server-side (not browser localStorage), shared
  across LAN devices.
- **Skin system**, 3+ themes, persisted server-side.
- **Out of scope (MVP)**: auth, mobile-first, plotting, unit conversion,
  programmer mode, offline/PWA, cloud sync.

Owner tech hints (non-binding, from vision §Tech Stack Preferences):
- Minimum dependency, AMD/Linux ecosystem, memory-friendly
- Backend open (Go/Node/Python OK)
- Frontend open (vanilla JS to Svelte/React)
- DB hint: small-footprint preferred (SQLite likely sufficient)
- Math engine: external lib vs custom parser — architect to ADR
- Deployment: Docker compose OR systemd unit + nginx — architect to decide

### Hard constraints inherited from the template (ADR-0010 ff.)

| Constraint | Source | Implication |
|---|---|---|
| GitHub-native workflow (Issues, PRs, Projects v2, Actions) | ADR-0012, ADR-0013, ADR-0014 | CI runs on GitHub Actions; toolchain must install in <90s on `ubuntu-latest` |
| Bash + Python in `scripts/` (every agent tool, watcher, notify) | ADR-0010, ADR-0011 | Python already required at runtime → adding Python to product stack is **zero marginal toolchain cost** |
| systemd user-services on Linux for watcher cadence | ADR-0010 | Backend HTTP service runs as a long-lived process under systemd, aligned with deploy host (Ubuntu 24.04 VM) |
| Telegram notifications via shell pipe (`scripts/notify.sh`) | (template) | No coupling to product stack |
| Public repository default | ADR-0016 | No closed-source artefacts; license-compatible dependencies only |
| Pre-existing CI scaffold (`.github/workflows/ci.yml`) skips when `package.json` absent and runs Node 20 when present | template render | **Soft hint** the template expected Node; not binding (updated for Python in story R-3) |
| 4-cat label invariant + atomic hand-off | ADR-0012, ADR-0015 | No effect on product code |

### Architecture invariant (vision-confirmed)

The product is a **web-first browser calculator** with engine code that
must also be reachable from a CLI thin wrapper for power users (later).
This makes the **engine ↔ UI separation** the load-bearing architectural
decision — and it is a **two-way door** (Bezos): the engine can be
wrapped by HTTP (today), CLI (later), or compiled to WASM (much later
if vision ever pivots to offline) without rewriting the arithmetic.

**The CLI surface is *not* the v1 delivery target. The browser tab is.**

---

## Decision

**Adopt Python 3.11+ as the primary language for AtilCalculator. The expression engine is a pure-Python module with no I/O dependencies. The v1 delivery surface is web-first: a FastAPI backend serves the engine over HTTP to a browser front-end on the LAN VM (Ubuntu 24.04, 192.168.1.199). The CLI is a thin Typer wrapper around the same engine, deferred to a post-MVP-1 sprint for power users.**

### Reframing note (post-PM CONDITIONAL APPROVE 2026-06-17 13:29Z)

The first draft of this §Decision was framed "CLI now, HTTP/WASM later"
because it preceded PM's vision-intake on Issue #4. PM's CONDITIONAL
APPROVE flipped that ordering: web-first delivery, CLI as a later thin
wrapper. The engine layer and toolchain are unchanged; only the
**delivery sequencing** changes. The engine ↔ UI separation — the
load-bearing decision — was already correct and is unaffected.

### Concrete stack — engine + web delivery

| Layer | Tooling | Why |
|---|---|---|
| Language | **Python 3.11+** | Bootstrap scripts already require Python; zero new CI install step. `decimal.Decimal` solves float-precision arithmetic out of the box (vision M1). |
| Package manager | **`pip` + `pyproject.toml` (PEP 621)** | Stdlib-friendly, no `poetry`/`pdm` lock-in. Editable installs (`pip install -e .`) make dev → test loop tight. |
| Test framework | **`pytest`** | Industry default, parametrisation native, fixture model maps cleanly onto tester's TDD-red-first workflow. |
| Lint / format | **`ruff`** (lint+format) | One binary, replaces flake8 + black + isort. Runs in ms. |
| Type check | **`mypy --strict`** on the engine module only | Pure-function engine = high-leverage typing target. **`cli/` and `api/` stay un-strict-typed** (`--check-untyped-defs=false` or per-module overrides) — per developer's note, Typer's decorator magic doesn't survive strict mode, and FastAPI's pydantic models give us runtime validation rather than static. The mypy boundary is documented in `pyproject.toml` `[tool.mypy]` overrides so future PRs don't drift. |
| HTTP backend | **FastAPI** | Wraps the engine module; serves `POST /eval`, `GET /history`, `GET/PUT /skin` to the browser. Runs as systemd user-service on the VM behind nginx. PM Sprint 1 commitment. |
| ASGI server | **uvicorn** | FastAPI's default; one process under systemd. No multiprocess complexity for single-user LAN (~10 req/min). |
| CLI wrapper (deferred → Sprint 7 shipped) | **`typer` canonical, stdlib `argparse` permitted fallback** | Declarative, type-hint driven, `--help` autogen. Pulls Click as transitive (small footprint per developer's note); we do **not** opt into Typer's optional `rich` dep so the tree stays click-only. **Stdlib `argparse` is permitted for thin CLI surfaces** — see §Amendment 2026-06-24 for criteria. Sprint 7 P0 chain (PR #314 basic+multi-op, PR #318 REPL) shipped on stdlib argparse. |
| Numeric precision | **`decimal.Decimal`** (stdlib) | Avoids IEEE-754 surprises. Direct mapping to vision M1 acceptance gate. |
| Build / packaging | **`python -m build`** (sdist + wheel) | Stdlib path, no `setuptools`-vs-`hatch` debate. |
| Front-end framework | **DEFERRED to a separate ADR (Sprint 1)** — see §What this ADR does *not* decide → R-2 |
| Persistence (history, skin) | **DEFERRED to a separate ADR (Sprint 2 latest per PM)** → R-5 |
| Runtime infra | **systemd user-service + nginx reverse-proxy** on Ubuntu 24.04 VM | Aligned with ADR-0010 watcher pattern + owner's deployment hint. No Docker required for v1 (one process, no orchestration need). |

### Reframing note — runtime vs dev dependency classification (post-VM-apply 2026-06-18)

**Issue**: [#65](https://github.com/atilproject/AtilCalculator/issues/65) (P3 chore, filed during VM apply of STORY-001 on 2026-06-18). Owner ran `uv sync` (no extras) on 192.168.1.199 — venv was missing `uvicorn[standard]` because both `fastapi` and `uvicorn[standard]` were under `[project.optional-dependencies].dev`. ModuleNotFoundError at startup. Fixed on the day with `uv sync --extra dev`, but the footgun persists: every new operator will hit the same error.

**Decision**: Move `fastapi==0.115.6` and `uvicorn[standard]==0.32.1` from `[project.optional-dependencies].dev` to `[project] dependencies`. Leave `httpx==0.27.2` (TestClient backend), `pytest`, `ruff`, `mypy`, `playwright`, `pytest-playwright` in `dev`. Rationale (matches Issue #65 option (a) recommendation):

- **HTTP surface is core, not optional.** ADR-0017 §Decision line 68 declares "v1 delivery surface is web-first"; ADR-0019 makes the HTTP contract canonical. Classifying the framework that delivers that surface as a `dev` extra inverts the architecture — it tells operators the production path is somehow less standard than the test path.
- **Smallest mental model.** `pip install -e .` (or `uv sync`) = "make it run". `uv sync --extra dev` = "make me able to develop on it". One command per audience; no third "deploy" extra to remember.
- **Engine ↔ UI separation invariant is preserved.** The invariant is about which *module* may import what, not which *pyproject section* holds a dep. `src/atilcalc/engine/` continues to be stdlib-only (zero non-stdlib imports); the runtime deps are the HTTP surface in `src/atilcalc/api/`, which is the opposite side of the boundary.
- **Doctrine: deps classify by consumer.** Runtime deps are what the deployed process needs to start. Test-only deps (`httpx`, `pytest`, `playwright`) stay in `dev` because they are never loaded by the deployed process. This is the standard Python packaging convention; the previous classification was the exception, and it cost an operator error on day one of VM apply.

**Alternatives considered** (full table in Issue #65):

| Option | Effect | Verdict |
|---|---|---|
| (a) Move `fastapi` + `uvicorn[standard]` to `dependencies`; leave `httpx` in `dev` | **CHOSEN** — `uv sync` = deploy; `uv sync --extra dev` = development | Smallest mental model; engine invariant preserved; matches Issue #65 recommendation |
| (b) Add `api` extra alongside `dev`; `uv sync --extra api` for deploy | Three sync variants to remember (`api` / `dev` / `--all-extras`) | Rejected: cognitive load; no benefit over (a) given the HTTP surface is the v1 surface |
| (c) Leave as-is; document `--extra dev` requirement in README | Doc-only fix | Rejected: footgun persists; every new operator hits it; README-rot risk |

**Pyproject impact** (follow-up chore filed for developer):

- Update the leading comment block (lines 28-30) from "Runtime dependencies: stdlib-only by design" to "Runtime dependencies = HTTP surface (FastAPI + uvicorn). Engine module invariant is preserved at the *module* boundary, not the *pyproject section* boundary."
- Move `fastapi==0.115.6` and `uvicorn[standard]==0.32.1` from `dev` to `dependencies`. Leave `httpx==0.27.2` in `dev` (test-only).
- Verify `scripts/run-server.sh` works on a fresh `uv sync` (no extras) — owner will smoke-test on VM.
- CI workflow `.github/workflows/` continues to pass: engine module is still stdlib-only so mypy/ruff strict on engine is unaffected; `pip install -e .[dev]` still installs everything CI needs.
- **Dev-extra backcompat (explicit duplication of `fastapi` + `uvicorn[standard]` in `[dev]`)** — After moving these two pins to `[project] dependencies`, **continue to list them explicitly in `[project.optional-dependencies].dev`** alongside the test-only deps (`httpx`, `pytest`, `ruff`, `mypy`, `playwright`, `pytest-playwright`). Reason: CI installs via `pip install -e .[dev]` for determinism — duplicating the runtime pins in `dev` makes the dev install command resilient to future transitive-resolution changes and prevents version drift between the two extras. The duplication is **deliberate**, not a leftover; reviewers should not "tidy" the `dev` extra by removing the runtime pins.
- **Mypy --strict invariant on engine (explicit load-bearing boundary)** — `src/atilcalc/engine/` continues to have **zero non-stdlib imports**, by design and by CI gate. The `[tool.mypy]` override in `pyproject.toml` (per §Concrete stack line 87) applies `--strict` to the engine module only; `cli/` and `api/` are permissive. **Future contributors must not add non-stdlib imports to `src/atilcalc/engine/`** — doing so will break `mypy --strict` on the engine and require either a CI override or an ADR amendment. The dependency classification in this amendment does **not** relax this invariant; it re-states it at the *module* boundary where it has always lived.
- **CI smoke gate for the deployment path (regression guard, developer-owned follow-up)** — Add a CI workflow step in `.github/workflows/ci.yml` that runs **independently of `[dev]`**: `pip install .` (no extras) → `python -c 'import fastapi, uvicorn; from atilcalc.api.main import app'`. This catches a future regression where someone re-classifies `fastapi` / `uvicorn` back to `dev` (or accidentally drops them) — the exact operator footgun that triggered Issue #65. The step is a **guard, not a verification of the architectural decision** (the ADR is the verification; the gate is the enforcement). Owner applies per `.github/workflows/` human-only territory; developer drafts the PR. Filed below in §Follow-up tickets to file as a separate chore so the architectural PR stays doc-only.

**Out of scope** (recorded for completeness, will be addressed in a follow-up ADR if they materialise):

- Re-pinning versions (current pins are correct per doctrine)
- Web shell static assets (separate from API runtime)
- WSGI server alternative (uWSGI/gunicorn) — separate story if needed for production scale

**Status**: Accepted — supersedes the dependency-classification implicit in §Decision line 68 ("no I/O dependencies" was always about the engine module, not the project as a whole). The engine ↔ UI separation invariant is restated in §Repository layout as the load-bearing architectural rule and is unchanged.

### Reframing note — CLI scaffolding stdlib-argparse fallback (amended 2026-06-24, Issue #315)

**Issue**: [#315](https://github.com/atilproject/AtilCalculator/issues/315) (P1 — Sprint 7 user-facing chain #299/#300/#301 shipped on stdlib `argparse`, not `typer`; tech-stack decision needed). PM's final verdict (Issue #315 cmt 4783590934, 2026-06-24): **Option B** (ADR amendment, not full typer migration), empirically refuting Option C (hybrid) because PR #318 (REPL impl) shipped on argparse + custom `sys.stdin.readline()`, not typer.

**Decision**: Add stdlib `argparse` as a permitted fallback for thin CLI surfaces. The original §Decision line ("a thin Typer wrapper around the same engine") is preserved as canonical for surfaces requiring subcommands/shell-completion/rich help, but is no longer the sole canonical choice.

**§Tech stack — CLI scaffolding (amended 2026-06-24)**

**Canonical**: `typer` for CLI surfaces requiring subcommands, shell-completion, or rich help.

**Permitted fallback**: stdlib `argparse` for thin CLI surfaces that are:
- Single-command (no subcommands)
- No shell-completion requirements
- No rich interactive help (e.g., --help generated from function signatures)
- Stdlib-bias justified (e.g., REPL state machines with custom I/O, scripts in CI)

**Rationale (empirical, Sprint 7)**: PR #314 (#299+#300 cherry-pick, merged 2026-06-23T20:20:11Z) and PR #318 (#301 REPL, merged 2026-06-23T21:15:25Z) shipped on argparse with stdlib-bias. Sprint 7 P0 chain complete on this path. No typer dep added, no migration needed, all 232 tests pass.

**Future trigger for typer migration**: if/when AtilCalculator CLI grows to ≥3 subcommands (e.g., `atilcalc repl`, `atilcalc lint`, `atilcalc repl-server`), reassess typer adoption. Until then, stdlib `argparse` is the recommended default for thin surfaces.

**Supersedes**: prior ADR-0017 §Tech stack "CLI scaffolding: typer" line as the sole canonical choice.

**Why this is a surgical amendment, not a wholesale rewrite**:

- Engine ↔ UI separation invariant is unchanged (engine stays stdlib-only, CLI wrappers import engine — never reverse).
- The mypy --strict engine module boundary is unaffected.
- Test framework (`pytest`), lint (`ruff`), numeric precision (`decimal.Decimal`), HTTP backend (`FastAPI`), runtime infra (systemd + nginx) are all unchanged.
- The only change is **CLI scaffolding canonical**: `typer` becomes "canonical for surfaces requiring subcommands/help/completion", stdlib `argparse` becomes "permitted fallback for thin surfaces".

**Out of scope** (recorded for completeness, will be addressed in follow-up if they materialise):

- Story CLI-003 (REPL) typer dep addition — already shipped on argparse per PR #318; if/when typer is added, it is an additive dep, not a rework.
- Pyproject.toml impact — no runtime dep changes; this amendment is doc-only.
- `cli/__init__.py` "Architecture note" comment (per PR #311 review) — docstring already reflects the stdlib-argparse rationale; no source change needed beyond this ADR.

**Status**: Accepted (architect + PM verdict per Issue #315 cmt 4783590934, owner merge pending this PR). Sister issue: #315 (close after merge). Sprint 7 P1 follow-up ticket #316 (installable binary) unblocked by this amendment.

### Repository layout

```
src/
  atilcalc/
    __init__.py
    engine/         # Pure-function expression engine (no I/O)
      __init__.py
      parser.py
      evaluator.py
    api/            # FastAPI app — depends on engine, not vice versa
      __init__.py
      main.py       # uvicorn entrypoint
      routes.py     # POST /eval, GET /history, GET/PUT /skin
    cli/            # CLI surface — stdlib argparse (Sprint 7 thin surfaces) or typer (≥3 subcommands); same engine import
      __init__.py
      __main__.py
  web/              # Front-end source (framework TBD by R-2)
tests/
  engine/           # pytest, parametrised; mirrors src/atilcalc/engine
  api/              # FastAPI TestClient-based, mirrors src/atilcalc/api
  cli/              # CliRunner-based (added when CLI ships)
pyproject.toml      # PEP 621 metadata, [project] + [tool.ruff] + [tool.pytest.ini_options] + [tool.mypy] with engine-strict / api-cli-permissive overrides
```

The **engine ↔ UI separation** is the load-bearing decision; everything
else is a swappable detail. Both the FastAPI `api/` module and the
deferred `cli/` module import from `engine/` — never the reverse.

### CI implications

`.github/workflows/ci.yml` currently scaffolds for Node (`package.json`
gate). The first developer story under this ADR must:
- add a `pyproject.toml` so `pip install -e .[dev]` works
- update `ci.yml` to detect `pyproject.toml` and run `ruff check`, `mypy src/atilcalc/engine`, `pytest -q`

The CI edit is a `.github/workflows/` change → human-only per
`CLAUDE.md` §Things agents must NEVER do. Architect/developer **propose**
the diff via PR; human merges. This ADR documents the *intent*; the
actual workflow PR is a separate change tracked by story R-3.

### What this ADR does *not* decide

Each of these is **deferred to a separate ADR**, not deferred indefinitely.
Sprint 1 will need ADRs for items marked **\[Sprint 1\]**. PM's vision
PR will reference each by its R-number so the backlog is self-consistent.

- **Front-end framework** (vanilla JS vs Svelte vs React vs htmx vs Solid)
  — **\[Sprint 1, FIRST after this ADR lands\]**. PM's vision is
  web-first; the front-end choice is itself a sizeable architectural
  decision deserving its own ADR. Owner hint: vanilla JS to Svelte
  acceptable, prefers minimum-deps. Architect leans toward
  **vanilla JS + Web Components** or **Svelte 5** as the two finalists,
  but commits nothing here. Tracked as **R-2**.
- **Persistence layer** (SQLite vs flat file vs Postgres) — **\[Sprint 2
  at the latest\]** per PM scoping. Vision M5 (history 1000+ records
  <100 ms) sets the perf bar. Owner hint: small-footprint preferred →
  SQLite is the likely winner but not chosen here. Tracked as **R-5**.
- **HTTP API contract** (request/response schemas, error codes) —
  **\[Sprint 1\]**. Lives in a `docs/designs/STORY-NNN-api.md` doc, not
  a fresh ADR, unless we pick something non-obvious. Tracked as the API
  surface story.
- **Math-engine implementation choice** — pure-Python recursive-descent
  parser vs external lib (e.g. `sympy`, `mpmath`) — **\[Sprint 1\]**.
  Owner explicitly asked for an ADR here. `decimal.Decimal` covers the
  precision class; the question is whether the parser is hand-written
  (control + tiny dep tree) or imported (less code, but adds heavy deps
  if `sympy`). Architect leans **hand-written recursive-descent** for
  + − × ÷ % ^ √ ! parens, with `math` stdlib for sin/cos/tan/log; the
  only sub-question is the `decimal` ↔ `float` boundary for
  transcendentals. Tracked as **R-6**.
- **Deployment topology** (systemd-only vs Docker Compose vs Podman) —
  **\[Sprint 1\]**. Owner hint is open. Architect leans **systemd
  user-service + nginx** (aligns with ADR-0010 watcher pattern; no
  orchestration needed for one process; minimal RAM); Docker Compose
  if developer wants a portable local-dev story. Tracked as **R-4**.
- **VM hardening** (SSH key auth, ufw, fail2ban, password disable) —
  **\[Sprint 1\]** per vision §Operasyonel kısıtlar. Not pure
  architecture; coordinate with PM scoping. Tracked as **R-7**.
- **AuthN/AuthZ**. Out of scope for MVP per vision non-goals
  (no multi-user, no auth). Re-open only if a future story changes that.
- **Telemetry / observability**. Deferred until traffic patterns warrant.
  Backend emits structured logs (stdout → journald) from day one;
  metrics later.
- **WASM / Pyodide front-end engine** — explicitly OUT (vision non-goals:
  no offline/PWA). Off the table unless vision changes.

### What this ADR commits to *now*

- Engine language: Python 3.11+
- Engine test framework: pytest
- Engine type checker: mypy --strict (engine module only; `cli/` and
  `api/` are not strict-typed for the reasons above; the boundary is
  pinned in `pyproject.toml` `[tool.mypy]` overrides)
- Engine lint: ruff (lint + format)
- Engine precision class: `decimal.Decimal` stdlib
- Backend HTTP framework: FastAPI + uvicorn
- Backend runtime: systemd user-service on Ubuntu 24.04 VM
- CLI wrapper (deferred post-MVP-1): Typer (click-only transitive, no
  `rich` opt-in)
- Architectural invariant: engine ↔ UI separation; engine has no I/O

---

## Alternatives considered

### A. Python 3.11 + pytest + Typer (engine + thin wrappers, web-first delivery via FastAPI) (chosen)

- **Pros**: zero new CI install cost; matches existing bootstrap toolchain
  (scripts are Python); `decimal.Decimal` solves precision; tightest
  TDD loop on `ubuntu-latest`; pure-function engine is naturally
  type-checkable; FastAPI is mature for the web-first delivery vision
  PM committed to; CLI thin-wrapper later costs ~50 lines.
- **Cons**: weak in-browser story for engine reuse (would need WASM via
  Pyodide — vision non-goals rule out offline, so this is moot);
  CPython startup ~50 ms feels slow for a one-shot CLI (irrelevant for
  HTTP service which warms once); packaging culture contested
  (we default to stdlib `build`).
- **Verdict**: **Chosen.** Aligned with concrete current constraints and
  PM-confirmed web-first vision; the cons are deferred problems
  (browser engine reuse) that vision non-goals rule out, or operational
  concerns (CLI startup) that don't bind on the MVP delivery surface.

### B. TypeScript / Node.js 20 + Vitest + Commander + Express/Fastify

- **Pros**: CI already scaffolded for Node 20 (template hint); huge
  package ecosystem; same language across frontend + backend if vision
  picks a JS framework; `decimal.js` widely used.
- **Cons**: introduces a second toolchain (Python for scripts/, Node for
  product) → CI must install both for any combined workflow; floating-
  point arithmetic requires `decimal.js` (not stdlib, extra dep);
  Node ecosystem is heavier on lockfile churn and supply-chain risk
  than `pyproject.toml`; owner's "minimum dependency, memory-friendly"
  hint cuts against npm's typical posture.
- **Verdict**: Rejected. Owner's deployment context (small LAN VM)
  and the bootstrap toolchain alignment both favour staying on Python.
  Even if Sprint 1 picks a JS front-end framework, the backend stays
  Python; we pay for one language family + one front-end build, not two.

### C. Go 1.22 + standard testing + Cobra + math/big + chi/echo

- **Pros**: single static binary (trivial distribution); `math/big`
  for precision; fast startup; very low memory footprint; strong fit
  for owner's "minimum dependency, memory-friendly" hint.
- **Cons**: new toolchain in CI (`actions/setup-go`); Python script
  tooling stays so we still pay 2-language cost; calculator has no
  concurrency need (single-user LAN, ~10 req/min); ergonomics of
  generics-light arithmetic code is bumpy compared to Python;
  `math/big` precision handling is more verbose than `decimal.Decimal`.
- **Verdict**: Rejected. Go's strengths (concurrency, single binary)
  are wasted on a single-user LAN HTTP service; its costs (toolchain,
  added language) are paid for nothing. The "memory-friendly" hint is
  satisfied by Python + uvicorn (one process, ~50 MB resident).

### D. Rust + cargo + clap + axum + rust-decimal

- **Pros**: maximum runtime performance; memory-safe; very low
  memory footprint; WASM target is first-class for a future web
  engine reuse; `rust-decimal` for precision.
- **Cons**: cold-compile time on `ubuntu-latest` is ~3–5 min for a
  trivial project; ramp-up cost is real (lifetime, ownership);
  premature optimisation per ADR heuristic — a calculator does not
  need Rust's perf budget; tooling cost dwarfs problem complexity.
- **Verdict**: Rejected. Violates "boring tech wins" and "design for
  the next order of magnitude, not the next ten." Reconsider only if a
  future story actually demands sub-millisecond eval (vision M5 sets
  100 ms for history queries, which Python easily clears).

### E. Bash-only with bats-core for tests + nginx static serve

- **Pros**: zero new toolchain (the entire dev-studio is Bash anyway).
- **Cons**: Bash arithmetic is integer-only (`$(( ))`); `bc`/`awk`
  for decimals is awkward; no realistic HTTP backend; vision demands
  decimal precision + persistent history + REST API which Bash can't
  carry sanely.
- **Verdict**: Rejected. Vision demands ruled out by language ceiling.

### F. Python engine + Pyodide WASM front-end (one engine, two surfaces)

- **Pros**: one engine codebase covers HTTP backend (CPython) + browser
  engine (Pyodide WASM); future-proofs against an offline mode.
- **Cons**: Pyodide bundle is ~6 MB cold; not all stdlib works; toolchain
  is two-headed (Pyodide + a bundler); **vision non-goals explicitly
  rule out offline/PWA**, so Pyodide brings no MVP value.
- **Verdict**: Rejected for v1. Reconsider only if a future vision
  pivot adds offline.

### G. Defer the choice until PM vision lands

- **Pros**: avoids guessing about non-CLI surfaces; lowest commitment.
- **Cons**: blocks Sprint 1 indefinitely; the whole point of running #3
  in parallel with vision-intake was to **not** block.
- **Verdict**: Rejected (and overtaken by events — PM CONDITIONAL APPROVE
  landed during PR #5 review, vision is now known web-first via Issue #4).

---

## Consequences

### Positive

1. **CI install cost is zero**: Python is already on every dev-studio
   workstation and on `ubuntu-latest` by default. No new `setup-*`
   action required for the engine; only `pip install -e .[dev]`.
2. **Engine portability is preserved**: the pure-function engine is
   wrapped by FastAPI (v1) and Typer (post-MVP-1) without rewriting
   arithmetic.
3. **Test loop is tight**: `pytest -q` on the engine completes in
   <1 s for typical specs; tester's TDD-red phase costs nothing in CI
   minutes.
4. **`decimal.Decimal` directly satisfies vision M1**: tester can write
   "0.1 + 0.2 == 0.3" assertions without inventing a float-tolerance
   fixture.
5. **Deployment aligns with VM**: Ubuntu 24.04 + systemd user-service +
   nginx is the lowest-surface deploy story; no Docker daemon needed,
   no orchestrator overhead, fits owner's "memory-friendly" hint.
6. **Stack matches author skill**: the dev-studio agents are Python-
   fluent (scripts/ track record). No ramp.

### Negative / risks

1. **Front-end pivot risk**. The web surface needs a separate ADR
   (R-2). If Sprint 1 picks Svelte or React, the engine layer is
   unaffected; if Sprint 1 picks vanilla JS, no build pipeline is
   needed. The risk is the ADR slips and front-end stories block.
   Mitigation: open R-2 as the first Sprint 1 ADR.
2. **Native-binary distribution path is non-trivial**. PyInstaller
   works for the deferred CLI but is slow and produces large bundles.
   If owner ships a single-binary CLI for power users, that's a
   follow-up ADR (R-1).
3. **CPython startup latency** (~50 ms) is visible on one-shot CLI
   invocations. Irrelevant for the HTTP service (warms once); only
   matters for the deferred Typer CLI. Mitigation: a future
   `atilcalcd` daemon mode if shell-heavy users emerge (no current
   user persona requires it).
4. **Lock-in to Python's packaging history**. PyPI publish flow is
   well-trodden but has its own toolchain choices (twine vs hatch vs
   build). We default to stdlib `build` to minimise surface.
5. **`mypy --strict` boundary needs `pyproject.toml` enforcement**.
   The decision to type-strict only `engine/` (not `api/` or `cli/`)
   is per developer's note that Typer's decorator magic fights strict
   mode and FastAPI's pydantic models give us runtime validation rather
   than static. The `[tool.mypy]` config must pin this boundary
   explicitly (engine: strict; api/cli: permissive) so future PRs don't
   drift. R-3 includes this `pyproject.toml` config.

### Follow-up tickets to file (after this ADR is accepted)

- **R-1**: Distribution-mode ADR — when owner requests single-binary
  CLI, decide PyInstaller vs Nuitka vs PyPI-only. (Post-MVP-1.)
- **R-2**: Front-end framework ADR — **Sprint 1, first**. Decide
  vanilla JS vs Svelte 5 vs htmx vs React. Owner prefers minimum-deps.
- **R-3**: Update `.github/workflows/ci.yml` to detect `pyproject.toml`
  and run `ruff`/`mypy`/`pytest`; also write the initial `pyproject.toml`
  with `[tool.mypy]` strict-engine / permissive-api-cli overrides.
  This is a `.github/workflows/` change → **human-merged PR**, not
  architect-or-developer-merged. Tracked as a developer story dependent
  on this ADR.
- **R-3.1 (added by ADR-0017 amendment, 2026-06-18)**: CI smoke gate for the
  deployment path — add a CI step in `.github/workflows/ci.yml` that runs
  `pip install .` (no extras) → `python -c 'import fastapi, uvicorn;
  from atilcalc.api.main import app'` as a regression guard for the
  Issue #65 operator footgun. Closes the gap raised by `@tester` in PR
  #66 review (2026-06-18). Developer drafts the PR; `@atilcan65` merges.
  Filed as a chore ticket dependent on this amendment; sprint TBD at
  Sprint 2 mid-sprint planning.
- **R-4**: Deployment topology ADR — systemd + nginx vs Docker
  Compose. Sprint 1.
- **R-5**: Persistence ADR — SQLite vs flat file vs Postgres. Sprint 2.
- **R-6**: Math-engine implementation ADR — hand-written recursive-
  descent parser vs sympy/mpmath. Sprint 1.
- **R-7**: VM hardening checklist (SSH keys, ufw, fail2ban, password
  disable) — coordinate with PM scoping. Sprint 1.

### Tech-debt entries opened

None at acceptance. The deferred decisions above are not debt — they are
explicit follow-up ADRs with named owners and sprint targets.

---

## Open questions (resolved + remaining)

- [x] **@product-manager**: does the calculator vision rule out a CLI-first
  shape? — **RESOLVED 2026-06-17 13:29Z**: YES, vision rules it out.
  Reframed §Decision from "CLI now, HTTP/WASM later" to "engine first,
  web-first delivery in Sprint 1, CLI as a thin Typer wrapper post-MVP-1."
- [x] **@developer**: any objection to Typer? It pulls Click + optional
  `rich`. — **RESOLVED 2026-06-17 13:29Z**: no objection; agreed to
  scaffold without `rich` opt-in so dep tree stays click-only.
- [x] **@developer**: scope of `mypy --strict`? — **RESOLVED 2026-06-17 13:29Z**:
  engine module only. `cli/` and `api/` stay un-strict; developer's
  reasoning (Typer decorators + FastAPI runtime validation) accepted.
  Boundary pinned in `pyproject.toml` `[tool.mypy]` (R-3).
- [ ] **@tester**: pytest + parametrisation matches your TDD workflow?
  Or would you prefer hypothesis property-based tests as the default?
  (Hypothesis can be added later as an optional dev-dep.)
- [ ] **@atilcan65**: approval gate per Issue #3 AC — please comment
  "approved" on Issue #3 once this ADR is sound (and vision PR is open).

---

## References

- Bootstrap ADRs that constrain this choice:
  - [ADR-0010 — Per-project systemd watchers](./ADR-0010-per-project-watchers.md)
  - [ADR-0012 — Required label set](./ADR-0012-required-label-set.md)
  - [ADR-0014 — PROJECT_TOKEN canary](./ADR-0014-project-token-secret.md)
  - [ADR-0016 — Public-by-default](./ADR-0016-public-by-default.md)
- Vision intake: Issue #4 — `[Vision] AtilCalculator`
- PM CONDITIONAL APPROVE comment: PR #5 (2026-06-17T13:29:50Z)
- Developer non-objection comment: PR #5 (2026-06-17T13:29:42Z)
- PEP 621 (`pyproject.toml` [project] metadata):
  https://peps.python.org/pep-0621/
- `decimal` stdlib (precision arithmetic):
  https://docs.python.org/3/library/decimal.html
- FastAPI: https://fastapi.tiangolo.com/
- uvicorn: https://www.uvicorn.org/
- Typer (deferred CLI scaffolding): https://typer.tiangolo.com/
- ruff (lint+format): https://docs.astral.sh/ruff/
- Bezos one-way-door heuristic (cited in soul):
  internal — see `.claude/agents/architect.md` §Decision-making heuristics.

---

## Acceptance gate

This ADR moves from **Proposed → Accepted** when:
1. @tester confirms pytest+parametrisation vs hypothesis preference.
2. @atilcan65 comments "approved" on Issue #3.
3. PR (this doc) is merged to `main` with developer + tester + PM sign-off
   recorded as PR reviews. PM CONDITIONAL APPROVE on the reframed
   §Decision becomes full APPROVE.
4. Vision PR for Issue #4 (`docs/product/vision.md`) is also merged so
   the two documents are self-consistent.
5. `.claude/CLAUDE.md` §Tech stack section is updated via the routed
   upstream template update (or accepted as a local-only render — open
   question on Issue #3).
6. `docs/decisions/INDEX.md` lists ADR-0017.
