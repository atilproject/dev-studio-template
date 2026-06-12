#!/usr/bin/env python3
"""
apply-reprime-protocol.py — Insert REPRIME Protocol section into role docs.

Idempotent: re-running is safe (skips files that already have the section).

Inserts the REPRIME Protocol block BEFORE the final `---` separator that
precedes the closing `**Remember: ...**` motto, so the motto stays last.

Run from repo root:
    python3 scripts/apply-reprime-protocol.py [--dry-run]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROLES = ["orchestrator", "product-manager", "architect", "developer", "tester"]
ROLE_DOC_DIR = Path(".claude/agents")

REPRIME_BLOCK = """## REPRIME Protocol

If you receive a chat message starting with `[REPRIME]`:

1. Finish your current work unit (in-flight tool call, PR draft,
   acknowledgment). Do not abandon partial work.
2. Re-read `.claude/CLAUDE.md` (project root) and this role doc.
3. Re-query GitHub for any state you were holding in chat memory
   (PR labels, issue status, board state). Do not trust chat history.
4. Reply with exactly one line:
   `[REPRIME ACK] <role>: <one-line summary of any doctrine change
   noticed, or "no change">`.
5. Resume normal duties under the refreshed doctrine.

See `docs/CONTEXT-HYGIENE.md` for the full doctrine.

"""

SENTINEL = "## REPRIME Protocol"


def patch_one(path: Path, dry_run: bool) -> tuple[str, int]:
    """
    Returns (status, lines_added).
    status ∈ {"skipped:already", "skipped:no-motto", "patched"}
    """
    text = path.read_text(encoding="utf-8")

    if SENTINEL in text:
        return ("skipped:already", 0)

    # Find the LAST '---' line. The closing motto sits after it.
    lines = text.splitlines(keepends=True)
    sep_idx = None
    for i in range(len(lines) - 1, -1, -1):
        # Match a horizontal-rule line (just '---' possibly with trailing space).
        if lines[i].strip() == "---":
            sep_idx = i
            break

    if sep_idx is None:
        return ("skipped:no-motto", 0)

    # Insert REPRIME_BLOCK BEFORE the final '---'. Ensure exactly one blank
    # line between the inserted block and the surrounding content.
    block_lines = [ln + "\n" if not ln.endswith("\n") else ln
                   for ln in REPRIME_BLOCK.splitlines(keepends=False)]
    # Make the block end with a blank line so the '---' that follows is well-spaced.
    if not block_lines[-1].endswith("\n"):
        block_lines[-1] += "\n"
    block_lines.append("\n")

    # Also make sure there's a blank line BEFORE the inserted block.
    # If the line right before sep_idx is not blank, add one.
    if sep_idx > 0 and lines[sep_idx - 1].strip() != "":
        block_lines.insert(0, "\n")

    new_lines = lines[:sep_idx] + block_lines + lines[sep_idx:]
    new_text = "".join(new_lines)

    if not dry_run:
        path.write_text(new_text, encoding="utf-8")

    added = len(new_lines) - len(lines)
    return ("patched", added)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true",
                    help="Show what would change without writing files.")
    args = ap.parse_args()

    if not ROLE_DOC_DIR.is_dir():
        print(f"ERROR: {ROLE_DOC_DIR} not found. Run from repo root.",
              file=sys.stderr)
        return 1

    failures = 0
    print(f"Mode: {'DRY-RUN' if args.dry_run else 'WRITE'}")
    print(f"Target dir: {ROLE_DOC_DIR}")
    print()

    for role in ROLES:
        path = ROLE_DOC_DIR / f"{role}.md"
        if not path.exists():
            print(f"  MISS:    {path} (file not found)")
            failures += 1
            continue
        status, added = patch_one(path, args.dry_run)
        if status == "patched":
            print(f"  PATCH:   {path} (+{added} lines)")
        elif status == "skipped:already":
            print(f"  SKIP:    {path} (already has REPRIME Protocol)")
        elif status == "skipped:no-motto":
            print(f"  WARN:    {path} (no final '---' found — manual patch needed)")
            failures += 1

    print()
    if failures:
        print(f"DONE with {failures} issue(s).")
        return 1
    print("DONE cleanly.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
