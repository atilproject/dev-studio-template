# ADR-0054: §9-Lens Enforcement Application (d-test family 9th sister)

- **Status**: Proposed (Sprint 14 P1 #4)
- **Date**: 2026-06-27
- **Deciders**: @architect (drafter) + @developer (d055 impl) + @tester (d-test sign-off) + @human (CI integration)
- **Closes**: Issue #495

## Context

ADR-0049 §Code review codification (PR #478, MERGED @ bf8b2be) established the **9-Lens Review Checklist** in `.claude/agents/architect.md` §9-Lens (pre-publish gate). Each lens (a–k) is a distinct verification mechanism backed by a known blind-spot TD:

| Lens | TD | Domain |
|---|---|---|
| (a) Data flow | TD-016 | request/response path end-to-end |
| (b) Runtime preconditions | TD-018 | service up, deps installed, secrets |
| (c) Canonical entry point | TD-019 | no side-channels |
| (d) Silent-skip risk | TD-020 | feature-flags/conditionals log `silent_skip` |
| (e) Idempotency | — | network/retries/mutations re-entrant |
| (f) Observability | — | structured logs + trace + counters |
| (g) Security & privacy | — | authn/authz, PII, threat model |
| (h) Workflow YAML SHA pin | TD-028 | all `uses: actions/*@<full-40-char-sha>` |
| (i) Platform hard constraints | TD-029 | GA sandbox, permissions, timeout, concurrency |
| (j) Auto-gen file refs + live-state | TD-030 | grep .gitignore + Makefile + ls -la |
| (k) JS syntactic correctness | TD-031 | `node --check` on `actions/github-script` |

### Gap (Sprint 13–14 live evidence)

The 9-Lens checklist lives in `.claude/agents/architect.md` §9-Lens Review Checklist, but **enforcement is manual**:

- §Code review (architect.md line 80): "Check the design doc's §Risks for 9-lens attestation coverage …"
- Sprint 14 P1 #4 trigger (Issue #495): no automated verification that all 9 lenses fire on PR review.
- Sister-pattern gap closed for: 4-cat labels (d053, ADR-0050), Closes-anchor strict format (d054), workflow SHA pins (d046/d043), Layer 5 reviewer chain (d048), 5-soul dispatch discipline (d051), agent-watch hardening (d052), CI re-run race (d056, ADR-0052), perf flake vs regression (d057, ADR-0051), Layer 5 race pattern (ADR-0053, deferred to Sprint 14+ P2).

**No programmatic guard for 9-Lens coverage.** This is the gap.

### Live evidence (Sprint 13–14)

| Incident | Lens gap | Impact |
|---|---|---|
| **PR #441** (Issue #441 L337 regression) | (k) JS syntactic — missing backticks | P0 hotfix PR #438 |
| **PR #450** (squash-time catch) | (g) Security — type:bug + missing needs-tester-signoff | squash-time catch, late |
| **RETRO-008 §3** wip_overflow false positive | (d) Silent-skip — manual claim missed work-stream | Issue #497 follow-up |
| **PR #500** (ADR-0051 birth) | (j) Auto-gen — main HEAD canonical check doctrine | codified but no test |
| **PR #501** (ADR-0052 birth) | (b) Runtime — workflow re-run race | codified but no test |
| **PR #502** (ADR-0053 birth, 4 bugs) | (c) Canonical — link integrity + mermaid syntax | self-validation caught |

## Decision

**d055 d-test** programmatically verifies that every PR with `needs-architect-review` label carries 9-Lens attestation in the architect's review comment **OR** design doc §Risks. Sister-pattern to d046 + d048 + d053 + d054 + d056 + d057 (8-sister d-test family extended to 9).

### Decision rules

1. **d055 contract** (RED-first per ADR-0044):
   - Read PR labels (`gh pr view <N> --json labels`)
   - If `needs-architect-review` is present, find the arch verdict comment
   - Verify **9-lens table or 9-lens bullet list** present in verdict (regex `\(a\)` … `\(k\)`)
   - 9/9 lens markers required; missing lens = CHANGES_REQUESTED
   - Output PASS/FAIL within 5 seconds (static check, no API wait)

2. **9-Lens application flow on arch review** (operational discipline):
   - Step 1: Read PR diff + design doc §Risks
   - Step 2: For each lens (a–k), run the verification mechanism (or note N/A with reason)
   - Step 3: Cite TD reference for relevant lenses (`TD-016/018/019/020/028/029/030/031`)
   - Step 4: Post verdict with 9-Lens attestation table (or pointer to design doc §Risks if already attested)
   - Step 5: If lens (h)/(i)/(j)/(k) applies to a workflow PR, run the corresponding d-test as evidence

3. **No `.claude/agents/architect.md` amendment in this ADR** (out of scope per Issue #495):
   - 9-Lens doctrine is already at architect.md line 87 (k lens amendment is separate, per ADR-0049 amendment-subcheck-k.md)
   - This ADR codifies **enforcement** (d-test), not **checklist content**
   - Future lens additions (lens l, m, …) follow same pattern: ADR proposal → architect.md amendment (owner squash) → d055 extension (dev lane)

### §9-Lens attestation format (architect verdict)

```markdown
## 9-Lens Attestation

| Lens | Status | Note |
|---|---|---|
| (a) Data flow | ✅ | … (cite TD-016 if gap) |
| (b) Runtime preconditions | N/A | doctrine-only PR |
| (c) Canonical entry point | ✅ | … |
| (d) Silent-skip risk | NONE | no skip paths |
| (e) Idempotency | ✅ | … |
| (f) Observability | ✅ | … |
| (g) Security & privacy | N/A | no auth/PII changes |
| (h) Workflow YAML SHA pin | N/A | no workflow changes |
| (i) Platform hard constraints | N/A | no platform changes |
| (j) Auto-gen file refs + live-state | N/A | doctrine-only |
| (k) JS syntactic correctness | N/A | no `actions/github-script` |
```

**Required on every PR with `needs-architect-review` label.** N/A lenses must include a 1-line reason.

### Sister-pattern symmetry

| d-test | Scope | Sister-pattern |
|---|---|---|
| d046 | jq-filter, JS syntactic | static lint |
| d048 | Layer 5 reviewer chain | workflow contract |
| d050b | behavioral workflow test | runtime gate |
| d053 | 4-cat verification | pre-merge invariant |
| d054 | Closes-anchor strict format | text invariant |
| d055 (THIS) | **9-Lens coverage** | **review invariant** |
| d056 | CI re-run race | timing invariant |
| d057 | perf flake vs regression | signal invariant |

All d-tests share: **read-only static check**, **5-second budget**, **PASS/FAIL binary**, **CI integration on `.claude/**` + `.github/**` + `docs/decisions/**` + `scripts/**` paths**.

## Why now

- **Sprint 14 P1 #4 home** (Issue #495, owner-ratified 2026-06-27T07:25Z)
- **RETRO-008 §3 wip_overflow** + **§4 Layer 5 race** + **§6 LIVE INSTANCE** (3 consecutive ADR with link/syntax bug) — d055 catches (c) canonical + (j) live-state + (k) JS syntactic gaps at review time
- **Architect.md §9-Lens** has 11 lenses (a–k) now codified, no programmatic guard for any — first enforcement of the checklist itself

## Sprint 14 P1 #4 critical path

| Step | Owner | SP | Status |
|---|---|---|---|
| 1. ADR-0054 (this PR) | @architect | 0.5 | DONE |
| 2. d055 impl (9-lens coverage verifier) | @developer | 1.0 | TODO |
| 3. d055 tester sign-off (9/9 cases) | @tester | 0.25-0.5 | TODO |
| 4. CI integration (`lint-and-test.yml` paths trigger) | @human | 0.5 | TODO (owner merge) |
| **Total** | | **2.25-2.5 SP** | |

## Alternatives considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **Skip d-test, rely on arch manual attestation** | Lower dev lane cost | No programmatic guard, drift inevitable | ❌ Reject (RETRO-008 §3/§4/§6) |
| **Add 9-Lens to label-check.yml** | Single workflow | Label-check is presence-only, not doctrinal | ❌ Reject (ADR-0050 §Gap) |
| **d055 d-test (THIS)** | Sister-pattern symmetry, 8 established family | New d-test overhead | ✅ Chosen |
| **Defer to Sprint 15+** | Lower sprint risk | Sprint 14 P1 #4 commitment + RETRO-008 carrier | ❌ Reject |
| **Single mega-d-test (combine d053 + d054 + d055)** | One file | Defeats sister-pattern granularity | ❌ Reject (anti-pattern) |

## Consequences

### Positive

- **Programmatic 9-Lens enforcement** on every `needs-architect-review` PR
- **Sister-pattern symmetry** with 8 existing d-tests (d046/d048/d050b/d051/d052/d053/d054/d056/d057 → 9-sister family)
- **Catch lens gaps at review time**, not post-merge (architect verdict → CHANGES_REQUESTED → fix loop)
- **RETRO-008 §6 LIVE INSTANCE prevention** — link/syntax/citation bugs caught by lens (c)/(j)/(k) attestation table
- **Future lens additions** (l, m, …) follow established d-test extension pattern

### Negative

- New d-test adds dev lane 1.0 SP (mitigation: 9-sister d-test family has established pattern, copy-paste-modify from d053/d054)
- Architect verdict length grows (9-Lens table is ~12 lines, mitigation: N/A lenses collapse to single line)
- Possible **verdict-template rigidity** — architects must follow format (mitigation: §Risks in design doc carries same table, only pointer needed)

### Follow-up tickets

- **d055 impl** — `scripts/tests/d055-9lens-enforcement.sh` (dev lane, Sprint 14 P1 #4 step 2)
- **d055 sign-off** — tester lane, 9/9 cases per ADR-0044 RED-first
- **CI integration** — `lint-and-test.yml` paths trigger = human-only territory per file ownership matrix
- **Verdict template** — consider adding `## 9-Lens Attestation` boilerplate to arch verdict template (Sprint 14+ candidate)
- **Future lens additions** — l, m, … follow same d-test extension pattern (Sprint 15+ candidate)

## Cross-refs

- [ADR-0049 §Code review codification](./ADR-0049-amendment-subcheck-k.md) (9-Lens source)
- [ADR-0049 3-layer d-test defense](./ADR-0049-behavioral-workflow-test-framework.md) (d-test framework)
- [ADR-0050 pre-merge 4-cat verification](./ADR-0050-pre-merge-4-cat-verification.md) (d053 sister-pattern)
- [ADR-0051 engine perf flake vs regression](./ADR-0051-engine-perf-flake-vs-regression.md) (d057 sister-pattern)
- [ADR-0052 CI re-run race codification](https://github.com/atilproject/AtilCalculator/pull/501) (d056 sister-pattern, MERGED @ 13477d2)
- [ADR-0053 Layer 5 race pattern](https://github.com/atilproject/AtilCalculator/pull/502) (sister-pattern, this PR's birth family, squash queue)
- [RETRO-008 §3 wip_overflow](../sprints/sprint-14/plan.md) (RETRO-008 carrier)
- [RETRO-008 §4 Layer 5 race](../sprints/sprint-14/plan.md) (RETRO-008 carrier)
- [RETRO-008 §6 LIVE INSTANCE](../sprints/sprint-14/plan.md) (RETRO-008 carrier)
- [Issue #444](https://github.com/atilproject/AtilCalculator/issues/444) (TD-031 lens k carrier)
- [Issue #469](https://github.com/atilproject/AtilCalculator/issues/469) (ADR-0049 k lens text apply)
- [Issue #495](https://github.com/atilproject/AtilCalculator/issues/495) (Sprint 14 P1 #4 home)
- [PR #438](https://github.com/atilproject/AtilCalculator/pull/438) (Issue #441 hotfix, k lens trigger)
- [PR #441](https://github.com/atilproject/AtilCalculator/pull/441) (L337 backtick regression, k lens trigger)
- [PR #478](https://github.com/atilproject/AtilCalculator/pull/478) (§9-Lens Review Checklist, MERGED @ bf8b2be)
- [PR #502](https://github.com/atilproject/AtilCalculator/pull/502) (3-of-3 verdicts, 4 bugs fixed, RETRO-008 §6 LIVE INSTANCE)

## 9-Lens attestation (per architect.md)

| Lens | Status | Note |
|---|---|---|
| (a) Data flow | ✅ | d055 → arch verdict → design doc §Risks (read-only static check path) |
| (b) Runtime preconditions | ✅ | d055 runs in CI, 5s budget, no API wait |
| (c) Canonical entry point | ✅ | every PR review enters via `needs-architect-review` label → d055 hook |
| (d) Silent-skip risk | NONE | d055 PASS/FAIL binary, no silent path |
| (e) Idempotency | ✅ | re-running d055 on same PR = same output (read-only) |
| (f) Observability | ✅ | d055 emits metric `arch_9lens_coverage_pass/fail` per PR |
| (g) Security & privacy | N/A | no auth/authz/PII changes |
| (h) Workflow YAML SHA pin | N/A | no workflow changes in this ADR |
| (i) Platform hard constraints | N/A | no platform changes |
| (j) Auto-gen file refs + live-state | ✅ | ADR-0054 references live PR #438/#441/#478/#502 + ADR-0049 amend file on main |
| (k) JS syntactic correctness | N/A | no `actions/github-script` snippets in this ADR |

— @architect, prepared 2026-06-27 for Issue #495 AC1 (Sprint 14 P1 #4)