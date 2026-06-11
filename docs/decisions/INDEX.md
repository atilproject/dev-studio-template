# Architecture Decision Records — Index

This index lists every ADR the team has produced. ADRs are immutable once
`Accepted`; superseding decisions live in a new ADR that references the old
one in its `Supersedes` field.

| ID | Title | Status | Date | Deciders | Related |
|----|-------|--------|------|----------|---------|
| [ADR-0001](ADR-0001-fastapi-skeleton.md) | FastAPI service skeleton — Python pin, package manager, run command, layout | Accepted | 2026-06-10 | @architect, @atilcan65 | STORY-001, STORY-002, STORY-003, STORY-004 |
| [ADR-0002](ADR-0002-github-native-autonomy.md) | GitHub-native autonomy (auto-kickoff) | Accepted | 2026-06-10 | @architect, @orchestrator | — |
| [ADR-0003](ADR-0003-event-model-v2.md) | Event Model v2 — template-grade silent-failure prevention | Accepted | 2026-06-10 | @architect | — |
| [ADR-0004](ADR-0004-bootstrap-kickoff.md) | Bootstrap kickoff | Accepted | 2026-06-10 | @architect | — |
| [ADR-0005](ADR-0005-pr-merged-events.md) | `pr_merged` events (unconditional 5-role wake) | Accepted (fanout policy superseded by ADR-0008) | 2026-06-11 | @architect | ADR-0008 |
| [ADR-0006](ADR-0006-watcher-resilience.md) | Watcher resilience (systemd --user + auto-reload) | Accepted | 2026-06-11 | @orchestrator, @atilcan65 | ADR-0002, ADR-0005 |
| [ADR-0007](ADR-0007-label-cleanup.md) | Auto label cleanup via GitHub Action | Accepted | 2026-06-11 | @architect, @atilcan65 | ADR-0002, ADR-0005, ADR-0008, ADR-0009 |
| [ADR-0008](ADR-0008-label-conditional-fanout.md) | Label-conditional `pr_merged` fanout (Event Model v3.1) | Accepted | 2026-06-11 | @architect | ADR-0003, ADR-0005, ADR-0006, ADR-0007 |
| [ADR-0009](ADR-0009-pr-labeled-fanout.md) | PR-open `pr_labeled` fanout (closes ADR-0008 § 8.2 loop) | Accepted | 2026-06-11 | @architect | ADR-0007, ADR-0008, issue #47 (D2.2) |

## Conventions

- **Path**: `docs/decisions/ADR-NNNN-<slug>.md`
- **ID**: monotonically increasing, zero-padded to 4 digits
- **Slug**: kebab-case, short, filename-safe
- **Status lifecycle**: Proposed → Accepted → (optionally) Superseded by ADR-MMMM
- **Header**: every ADR starts with `# ADR-NNNN: <title>` followed by a YAML-style frontmatter block (Status, Date, Deciders, Supersedes, Related)

## Pending proposals

_(none — backlog of future-work items lives in each ADR's "Future work" / "Out of scope" section, e.g. ADR-0008 § 9, ADR-0009 § 8.)_
