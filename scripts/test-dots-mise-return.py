#!/usr/bin/env python3
"""apply/update must return so the zsh dots wrapper can refresh mise PATH."""

import re
from pathlib import Path

text = Path(__file__).with_name("dots").read_text(encoding="utf-8")
for name in ("apply", "update"):
    match = re.search(rf"\n  {name}\)\n(.*?)\n    ;;", text, re.S)
    assert match, f"missing {name} branch"
    body = match.group(1)
    assert "exec " not in body, f"{name} must not exec (zsh mise wrapper needs return):\n{body}"

print("dots mise return: OK")
