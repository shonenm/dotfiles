#!/usr/bin/env python3
"""Require provenance labels on repository documentation."""

from pathlib import Path
import re
import subprocess

ROOT = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
LABEL = re.compile(r"\A# .+\n\n> \*\*由来:\*\*")
EXCLUDED = {ROOT / "docs/INDEX.md"}

files = [ROOT / "README.md", *sorted((ROOT / "docs").rglob("*.md"))]
missing = [path.relative_to(ROOT) for path in files if path not in EXCLUDED and not LABEL.match(path.read_text())]

if missing:
    print("Missing provenance label:")
    print("\n".join(f"  {path}" for path in missing))
    raise SystemExit(1)

print(f"OK: checked provenance labels in {len(files) - len(EXCLUDED)} Markdown files.")
