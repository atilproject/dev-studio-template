"""FastAPI application — STORY-001 skeleton + STORY-004 greeting.

Implements the contract from docs/designs/STORY-001-design.md and ADR-0001.
Two routes in v1:
- GET /healthz — synchronous liveness probe, 200 with {"status": "ok"}.
- GET /hello/{name} — demo greeting, 200 with {"message": "hello, {name}"}.

Contract pin (do NOT change without a design pass — see ADR-0001):
- Sync handlers (no I/O → no need for `async def`).
- No DB / Redis / HTTP calls in these handlers. A future deep-check liveness
  probe (DB ping, downstream HTTP) is a separate story, not an in-place edit.
"""

from fastapi import FastAPI, Path

from app import __version__

app = FastAPI(
    title="atilprojects",
    version=__version__,
    description="Sprint 1 hello-world FastAPI service (STORY-001 + STORY-004).",
)


@app.get("/healthz")
def healthz() -> dict[str, str]:
    """Liveness probe.

    Contract: synchronous, no I/O, returns 200 with {"status": "ok"}.
    Do not add DB/Redis/HTTP calls here without a separate design pass.
    """
    return {"status": "ok"}


@app.get("/hello/{name}")
def hello(
    name: str = Path(..., min_length=1, max_length=64),
) -> dict[str, str]:
    """Demo greeting endpoint (STORY-004).

    Contract: returns 200 with {"message": "hello, {name}"}.
    - Case is preserved verbatim (no lowercasing).
    - URL-decoded values pass through; `/hello/%20` → `"hello,  "`.
    - Path segment is required; missing name → 404 (FastAPI default).
    - Name is capped at 64 chars to bound log-spam risk.
    """
    return {"message": f"hello, {name}"}
