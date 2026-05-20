"""Quick Onshape API auth check used by install.ps1."""
from __future__ import annotations

import json
import sys
from pathlib import Path

import httpx


def main() -> int:
    cfg_path = Path(__file__).resolve().parent.parent / "config.json"
    if not cfg_path.exists():
        print(f"FAIL: missing {cfg_path}")
        return 1
    cfg = json.loads(cfg_path.read_text(encoding="utf-8-sig"))
    r = httpx.get(
        cfg["onshape_base_url"] + "/api/users/sessioninfo",
        auth=(cfg["onshape_access_key"], cfg["onshape_secret_key"]),
        headers={"Accept": "application/json"},
        timeout=15,
    )
    if r.status_code != 200:
        print(f"FAIL: HTTP {r.status_code} - {r.text[:200]}")
        return 1
    j = r.json()
    print(f"OK: {j.get('name')} <{j.get('email') or ''}>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
