#!/usr/bin/env python3
"""Enforce documentation retention, workspace README, and link boundaries."""

from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit


def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)


def markdown_files(root):
    result = subprocess.run(
        ["git", "ls-files", "*.md", "*.mbt.md"],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )
    return [root / line for line in result.stdout.splitlines() if line]


def without_fenced_code(text):
    lines = []
    fence = None
    for line in text.splitlines(keepends=True):
        match = re.match(r"^\s*(`{3,}|~{3,})", line)
        if match:
            marker = match.group(1)[0]
            if fence is None:
                fence = marker
            elif marker == fence:
                fence = None
            continue
        if fence is None:
            lines.append(line)
    return "".join(lines)


def link_targets(text):
    # Avoid treating API signatures such as `Input[T](self, value: T)` as
    # Markdown links. Fenced blocks are removed first because they can contain
    # arbitrary text that resembles Markdown.
    text = re.sub(r"(`+)(?:(?!\1).)*?\1", "", without_fenced_code(text), flags=re.DOTALL)
    pattern = re.compile(r"(?<!\!)\[[^\]]*\]\(([^)]*)\)")
    for match in pattern.finditer(text):
        value = match.group(1).strip()
        if value.startswith("<"):
            end = value.find(">")
            target = value[1:end] if end >= 0 else value[1:]
        else:
            target = value.split(None, 1)[0] if value else ""
        yield target


def is_external(target):
    parsed = urlsplit(target)
    return (
        not target
        or target.startswith("#")
        or target.startswith("//")
        or parsed.scheme in {"mailto"}
        or bool(parsed.scheme)
    )


def workspace_members(root):
    text = (root / "moon.work").read_text(encoding="utf-8")
    match = re.search(r"\bmembers\s*=\s*\[(.*?)\]", text, re.DOTALL)
    if not match:
        return []
    return [Path(value) for value in re.findall(r"[\"']([^\"']+)[\"']", match.group(1))]


def main():
    root = Path.cwd()
    violations = []
    if (root / "docs" / "archive").exists():
        violations.append("docs/archive/ must not exist")

    for name in ("README.md", "README.mbt.md"):
        if (root / name).exists():
            break
    else:
        violations.append("repository root lacks README.md or README.mbt.md")

    members = workspace_members(root)
    for member in members:
        directory = root / member
        if not any((directory / name).exists() for name in ("README.md", "README.mbt.md")):
            violations.append(f"{member}: lacks README.md or README.mbt.md")

    files = markdown_files(root)
    missing = []
    for source in files:
        text = source.read_text(encoding="utf-8")
        for target in link_targets(text):
            if is_external(target):
                continue
            parsed = urlsplit(target)
            path = unquote(parsed.path)
            # Markdown source-location links commonly use `file.md:line`.
            # Validate the file target while leaving the line fragment unchecked.
            location = re.fullmatch(r"(.+\.(?:mbt\.)?md):\d+", path)
            if location:
                path = location.group(1)
            resolved = (root / path.lstrip("/")) if path.startswith("/") else source.parent / path
            if not resolved.exists():
                missing.append(f"{source.relative_to(root)}:{target}")
    violations.extend(missing)

    if violations:
        for violation in violations:
            fail(violation)
        return 1

    print(f"Documentation boundaries OK: {len(files)} Markdown files, {len(members)} workspace members checked.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.CalledProcessError) as error:
        fail(str(error))
        raise SystemExit(1)
