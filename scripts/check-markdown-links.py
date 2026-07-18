#!/usr/bin/env python3
"""Fail when a repository Markdown file points to a missing local path."""

from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote

ROOT = Path(
    subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
)
LINK_START = re.compile(r"!?\[[^]\n]*\]\(\s*")
REFERENCES = re.compile(
    r"^\s*\[[^]\n]+\]:\s*(?:<(?P<angle>[^>\n]+)>|(?P<plain>[^\s>\n]+))",
    re.MULTILINE,
)
INLINE_CODE = re.compile(r"(`+)([^`\n]*?)\1")
FENCE_OPEN = re.compile(r"^ {0,3}(`{3,}|~{3,})")
SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


def tracked_markdown(root: Path = ROOT) -> list[Path]:
    output = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "*.md"],
        cwd=root,
    )
    return [
        path
        for name in output.split(b"\0")
        if name and (path := root / Path(name.decode())).exists()
    ]


def _blank(text: str) -> str:
    return "".join("\n" if char == "\n" else " " for char in text)


def mask_code(text: str) -> str:
    """Mask fenced and inline code without changing offsets or line numbers."""
    masked: list[str] = []
    fence_char = ""
    fence_length = 0
    for line in text.splitlines(keepends=True):
        marker = FENCE_OPEN.match(line)
        if fence_char:
            masked.append(_blank(line))
            closing = re.match(
                rf"^ {{0,3}}{re.escape(fence_char)}{{{fence_length},}}[ \t]*(?:\r?\n)?$",
                line,
            )
            if closing:
                fence_char = ""
            continue
        if marker:
            fence_char = marker.group(1)[0]
            fence_length = len(marker.group(1))
            masked.append(_blank(line))
            continue
        masked.append(INLINE_CODE.sub(lambda match: _blank(match.group(0)), line))
    return "".join(masked)


def inline_links(text: str):
    """Yield (offset, destination), balancing parentheses in destinations."""
    for match in LINK_START.finditer(text):
        start = match.end()
        if start < len(text) and text[start] == "<":
            end = text.find(">", start + 1)
            if end != -1:
                yield match.start(), text[start + 1 : end]
            continue

        depth = 0
        end = start
        while end < len(text):
            char = text[end]
            if char == "(":
                depth += 1
            elif char == ")":
                if depth == 0:
                    break
                depth -= 1
            elif char.isspace() and depth == 0:
                break
            end += 1
        if end > start:
            yield match.start(), text[start:end]


def local_target(source: Path, raw: str) -> Path | None:
    target = unquote(raw).split("#", 1)[0]
    if not target or target.startswith(("#", "/")) or SCHEME.match(target):
        return None
    if any(marker in target for marker in ("${", "{{", "<", ">")):
        return None
    return (source.parent / target).resolve()


def find_missing(files: list[Path], root: Path) -> list[str]:
    missing: list[str] = []
    for source in files:
        searchable = mask_code(source.read_text(encoding="utf-8"))
        destinations = list(inline_links(searchable))
        destinations.extend(
            (match.start(), match.group("angle") or match.group("plain"))
            for match in REFERENCES.finditer(searchable)
        )
        for offset, raw in destinations:
            target = local_target(source, raw)
            if target is not None and not target.exists():
                line = searchable.count("\n", 0, offset) + 1
                missing.append(f"{source.relative_to(root)}:{line}: {raw}")
    return sorted(set(missing))


def main() -> int:
    files = tracked_markdown()
    missing = find_missing(files, ROOT)
    if missing:
        print("Missing local Markdown links:", file=sys.stderr)
        print("\n".join(f"  {item}" for item in missing), file=sys.stderr)
        return 1

    print(f"OK: checked local links in {len(files)} Markdown files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
