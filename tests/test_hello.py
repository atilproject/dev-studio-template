"""Contract tests for GET /hello/{name} - STORY-004.

Pins AC1-AC4 of docs/backlog/sprint-1/STORY-004-hello-name-greeting-endpoint.md.
AC5 (>= 2 new tests in the suite) is satisfied by the AC1 + AC2 pair below,
with AC3 and AC4 added as bonus regression coverage.
"""

from fastapi.testclient import TestClient


def _client() -> TestClient:
    # Importing inside the helper (not at module top) so a missing
    # app/main.py surfaces as a clean ModuleNotFoundError, matching
    # the convention in test_healthz.py.
    from app.main import app

    return TestClient(app)


def test_hello_world_returns_greeting() -> None:
    """AC1: GET /hello/world → 200, body {"message": "hello, world"}."""
    response = _client().get("/hello/world")

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/json"
    assert response.json() == {"message": "hello, world"}


def test_hello_preserves_case() -> None:
    """AC2: GET /hello/Atil → 200, body {"message": "hello, Atil"} (case preserved)."""
    response = _client().get("/hello/Atil")

    assert response.status_code == 200
    assert response.json() == {"message": "hello, Atil"}


def test_hello_missing_name_returns_404() -> None:
    """AC3: GET /hello/ (missing name segment) → 404, not 500."""
    response = _client().get("/hello/")

    assert response.status_code == 404


def test_hello_url_encoded_space_returns_200() -> None:
    """AC4: GET /hello/%20 → 200, body has the URL-decoded value, no 5xx."""
    response = _client().get("/hello/%20")

    assert response.status_code == 200
    assert response.json() == {"message": "hello,  "}
