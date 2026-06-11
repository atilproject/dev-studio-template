# Tech-debt log

> Maintained by @architect. Each row is debt the team knowingly accepted with
> a payoff trigger (a concrete measurable condition that says "we should fix
> this when X"). Until the trigger fires, the debt is **load-bearing** — by
> design, not by neglect.

| ID    | Description                                                                                | Introduced in        | Severity | Payoff trigger                                          | Owner       |
|-------|--------------------------------------------------------------------------------------------|----------------------|----------|---------------------------------------------------------|-------------|
| TD-001 | `agent-watch.sh` only watches itself for reload (ADR-0006 § 4) — `agent-state.sh`/`notify.sh` edits need manual `systemctl --user restart` | ADR-0006 (D4)        | L        | next time a non-`agent-watch.sh` script change requires hot-reload | @architect  |
| TD-002 | `query_pr_labeled` (ADR-0009) uses PR's `updatedAt` as proxy for label-event timestamp     | ADR-0009 (D2.2)      | L        | dedup-ring churn > 5% of polled PRs (currently 0%)      | @architect  |

## Conventions

- **ID**: monotonically increasing, zero-padded to 3 digits (`TD-NNN`)
- **Severity**: H (blocks next milestone), M (will bite within 2 sprints), L (acceptable for >1 quarter)
- **Payoff trigger**: a concrete observable metric, not a vague intention. If the trigger fires, the debt is due.
- **Owner**: the agent responsible for the resolution PR, not the agent who introduced the debt (though they may coincide)
- **Log discipline**: every time an ADR is Accepted with a "we'll use X for now, switch to Y when Z" section, the architect appends a row here in the same PR.

## How to retire a row

1. Fix the underlying issue in a PR that explicitly references `Closes TD-NNN`.
2. Update this table: change `Introduced in` to `Retired in PR #N`, severity to ~~struck through~~, leave the rest as a historical note.
3. Mention the retirement in the next sprint retro.

## Review cadence

- **Per-ADR acceptance**: architect checks the ADR for "we'll use X for now" sections and adds a row if any.
- **Per-sprint retro**: PM and architect jointly review the table. Triggered rows are scheduled for the next sprint's backlog. Non-triggered rows are kept (debt is load-bearing until proven otherwise).
