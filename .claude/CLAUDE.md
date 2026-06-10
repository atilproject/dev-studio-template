# Project Context — for all agents

> Read this file at the start of every session. It is the single source of truth for product, team, and process context.

## Product
- **Name**: atilprojects
- **Vision**: <one paragraph from `docs/product/vision.md`>
- **Current sprint**: see `docs/sprints/current/plan.md`
- **Source of truth for backlog**: GitHub Project board (Projects v2)

## Team (5 agents + 1 human)
| Role | Who | Soul file |
|---|---|---|
| Human owner | atil can | — |
| Orchestrator | Claude Code / MiniMax-M3 | `.claude/agents/orchestrator.md` |
| Product Manager | Claude Code / MiniMax-M3 | `.claude/agents/product-manager.md` |
| Architect | Claude Code / MiniMax-M3 | `.claude/agents/architect.md` |
| Developer | Claude Code / MiniMax-M3 | `.claude/agents/developer.md` |
| Tester | Claude Code / MiniMax-M3 | `.claude/agents/tester.md` |
| Test Runner / Incident Bot | Codex CLI / gpt-5.5 | (separate process, see `scripts/codex-runner.sh`) |

## Process
- **Scrum** with 2-week sprints.
- **GitHub Projects v2** is the board. Columns: Backlog → Ready → In Progress → In Review → Done.
- **All PRs are draft** until Tester signoff + human approval.
- **Branch protection** on `main`: no direct push (enforced by local pre-push hook + human discipline), 1 human approval required, CI green.
- **Conventional commits**: `feat(scope): ...`, `fix(scope): ...`, `chore(scope): ...`.
- **Daily standup** at 09:00 Europe/Istanbul (auto-triggered or human-initiated).
- **Health check** every 30 minutes (systemd timer).

## Tech stack
<FILL IN: languages, frameworks, infra. Architect maintains this.>

## Definition of Done
A story is "Done" only if ALL of these hold:
1. All acceptance criteria pass automated tests.
2. Code merged to `main` via PR with human approval.
3. CI is green on `main` post-merge.
4. Docs updated (README, changelog, ADR if applicable).
5. Project card moved to Done by orchestrator.
6. No new P0/P1 bugs filed against the story within 24h.

## Communication conventions
- **Issues**: use templates in `.github/ISSUE_TEMPLATE/`.
- **PR comments**: structured (see developer.md and tester.md).
- **Cross-agent**: never DM-style. Always via GitHub Issue or PR comment.
- **Escalation to human**: Telegram (`scripts/notify.sh -l human`) + GitHub `@`-mention to @atilcan65.

## Auto-Ping Hard-Rule (Cross-Agent Communication)

**TL;DR**: Asla insandan "şunu söyle" / "şunu ilet" / "şuna haber ver" diye isteme. Kendin yap.

### The Rule

İki durumda **insandan onay almadan, doğrudan** `scripts/notify.sh -l <role>` ile Telegram ping at:

1. **Görev tamamlandığında** → bir sonraki agent'a "senin sıran" pingi at
2. **Başka agent'tan input bekler hale geldiğinde** → kim'i, ne için beklediğini explicit söyle

### Format

```
[FROM→TO] <≤80 char reason>
<PR/Issue link>
<≤2 satır context (opsiyonel)>
```

Örnek:
```
scripts/notify.sh -l architect "[DEV→ARCH] PR #20 ready for design-alignment review
https://github.com/atilcan65/atilprojects/pull/20
Check: import path, bind string, sync handler"
```

### Hangi durumda kime

| Senin durumun | Auto-ping → | Tipik mesaj |
|---|---|---|
| PR draft açtın, review istiyorsun | architect + tester | `[DEV→ARCH+TEST] PR #N ready for review` |
| Review verdin (🟢/🟡/🔴) | developer | `[ARCH→DEV] PR #N approved` / `PR #N has suggestions` |
| Sign-off verdin (tester) | developer | `[TEST→DEV] PR #N tests accepted` |
| Story sizing'i bitirdin | orchestrator | `[<ROLE>→ORCH] sizing posted on issue #N` |
| Grooming/scope-change tamamlandı | orchestrator | `[PM→ORCH] backlog refreshed, issue #N closed` |
| ADR yazdın | dev + tester + orch | `[ARCH→ALL] ADR-NNNN accepted, see docs/decisions/` |
| Bug filed | developer + orch | `[TEST→DEV] bug #N filed, P0/P1` |
| Sprint ceremony zamanı | all | `[ORCH→ALL] standup in 5 min, post your status` |
| Blocked > 1h | orch + human | `[<ROLE>→ORCH+HUMAN] blocked on X, need decision` |

### What you do NOT need to ask

- ❌ "Sana mesaj atayım mı?" / "Bunu iletmemi ister misin?" — **Hayır, direkt at.**
- ❌ "Atilcan, sen architect'e söyler misin?" — **Senin işin, sen söyle.**
- ❌ "Bekleyeyim mi, ping atayım mı?" — **Ping at, sonra bekle.**

### Eskalasyon istisnaları (HUMAN'a ping atılacak durumlar)

Bu durumlar **soul-level decisions** — auto-ping yetmez, HUMAN'a explicit eskalasyon:

- Branch protection / `.github/workflows/` değişikliği gerekiyor
- Sprint scope-change (story add/remove/swap)
- ADR'ler arasında conflict var, agent-level çözülmüyor
- Bir agent 2 kez refused / stuck loop'ta
- Production deploy/release kararı

Bunlarda: `scripts/notify.sh -l human "<eskalasyon nedeni> + öneri + link"`.

### Why this rule exists

Insan "kurye" değil. Insan **gate-keeper**. Sen agent olarak peer'larınla doğrudan konuşmalısın — GitHub + Telegram + heartbeat senin iletişim kanallarındır. Insan sadece merge/scope-change kararı verir.

## Things agents must NEVER do
- Push directly to `main`.
- Merge their own PRs.
- Modify `.github/workflows/`, secrets, branch protection without explicit human approval.
- Roll their own auth/crypto.
- Disable failing tests to make CI green.
- Edit other agents' soul files.

## File ownership matrix
| Path | Owner |
|---|---|
| `docs/product/` | @product-manager |
| `docs/backlog/` | @product-manager |
| `docs/designs/` | @architect |
| `docs/decisions/` (ADRs) | @architect |
| `docs/tech-debt.md` | @architect |
| `docs/sprints/` | @orchestrator |
| `docs/bugs/` | @tester |
| `src/`, `tests/` | @developer (writes), @tester (test files), @architect (reviews) |
| `.claude/` | human only |
| `.github/workflows/` | human only (agents propose via PR) |
