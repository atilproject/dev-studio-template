## Soul file clause template — bounded standby semantics

**Location**: Each of `.claude/agents/{orchestrator,product-manager,architect,developer,tester}.md` (5 files). Insert under the role's "Operating Principles" or "Hard Rules" section as a new bullet.

### Template (variable substitution: `<role>` → role name)

> **Bounded standby (per CLAUDE.md §Things agents must NEVER do + retro A14).** When you receive a chat-level standby instruction (e.g., "pickup et, sonra standby"), treat it as bounded to the **current task turn** — the immediate work item the human mentioned. When that work item completes (review posted, label flipped, peer notified), return to normal `<role>` queue processing. Do NOT self-extend the standby into the next queue turn without an explicit re-confirmation. If the queue has open P0/P1 work and you've been idle for >3 polls, treat the silence as a wake-up trigger (technical complement: `agent-watch.sh` `query_queue_empty_with_priority` fires `queue_empty_but_priority_pending` synthetic events).

### Per-role instantiation examples

#### `.claude/agents/developer.md` (you are here)

Insert after the "Things agents must NEVER do" section (or before "Hard Rules"):

> **Bounded standby (per CLAUDE.md §Things agents must NEVER do + retro A14).** When you receive a chat-level standby instruction (e.g., "pickup et, sonra standby"), treat it as bounded to the **current task turn** — the immediate work item the human mentioned. When that work item completes (review posted, label flipped, peer notified), return to normal `developer` queue processing. Do NOT self-extend the standby into the next queue turn without an explicit re-confirmation. If the queue has open P0/P1 work and you've been idle for >3 polls, treat the silence as a wake-up trigger (technical complement: `agent-watch.sh` `query_queue_empty_with_priority` fires `queue_empty_but_priority_pending` synthetic events).

#### `.claude/agents/orchestrator.md`

Same template, substitute `<role>` → `orchestrator`. The orchestrator's normal queue processing = board hygiene + sprint ceremonies + escalation. Bounded standby here is especially important because the orchestrator is the one who WAKES other agents — if the orchestrator is in indefinite standby, the whole team stalls.

#### `.claude/agents/architect.md`

Same template, substitute `<role>` → `architect`. The architect's queue = ADRs + design reviews + TD filings. Note: the architect soul file has the heaviest "standby while peer implements" pattern (rare for architects to do active coding). The bounded rule says "if the architect is the active reviewer on an open PR with `needs-architect-review`, that's the active task; bounded standby ends when the review is posted".

#### `.claude/agents/tester.md`

Same template, substitute `<role>` → `tester`. Tester's queue = TDD red contracts + signoffs + bug filings. Bounded standby is most relevant here when the tester is waiting for impl to unskip their contracts.

#### `.claude/agents/product-manager.md`

Same template, substitute `<role>` → `product-manager`. PM's queue = backlog grooming + sizing + sprint planning. Standby is rare here but the bounded rule still applies for consistency.

### Mechanical application

```bash
# Per agent role:
ROLE="developer"  # or architect, tester, orchestrator, product-manager
SOUL_FILE=".claude/agents/${ROLE}.md"
CLAUSE=$(cat <<'EOF'

**Bounded standby (per CLAUDE.md §Things agents must NEVER do + retro A14).** When you receive a chat-level standby instruction (e.g., "pickup et, sonra standby"), treat it as bounded to the **current task turn** — the immediate work item the human mentioned. When that work item completes (review posted, label flipped, peer notified), return to normal `<role>` queue processing. Do NOT self-extend the standby into the next queue turn without an explicit re-confirmation. If the queue has open P0/P1 work and you've been idle for >3 polls, treat the silence as a wake-up trigger (technical complement: `agent-watch.sh` `query_queue_empty_with_priority` fires `queue_empty_but_priority_pending` synthetic events).
EOF
)
# Substitute <role> for the actual role name
CLAUSE="${CLAUSE//<role>/$ROLE}"
# Insert at the marker line (or append)
# (human will apply this — agents do not edit .claude/ per file ownership matrix)
```

### Why a per-soul-file clause, not just CLAUDE.md

CLAUDE.md sets the doctrine. Each soul file references it. But soul files also contain role-specific behavior — and the bounded standby rule has slightly different operational implications per role:
- **Orchestrator**: bounded to "current sprint ceremony / current escalation ping"
- **Developer**: bounded to "current PR review / current issue ownership ack"
- **Architect**: bounded to "current ADR review / current design feedback"
- **Tester**: bounded to "current TDD contract write / current PR signoff"
- **PM**: bounded to "current story sizing / current backlog grooming"

The CLAUDE.md rule says "bounded to current task turn". The soul file clause specifies what "current task turn" means in role context. Both are needed.
