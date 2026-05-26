#!/usr/bin/env python3
"""Conservative compatibility-handle to target-facade migration helper.

Dry-run is the default. Use --apply to perform only the rewrites this script can
make without choosing between strict tracked reads and permissive outside reads.
Context-sensitive read sites are always reported for manual migration.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

IDENT = r"[A-Za-z_][A-Za-z0-9_]*"
EXCLUDED_DIRS = {
    ".git",
    ".mooncakes",
    ".worktrees",
    "_build",
    "docs/archive",
    "node_modules",
}

QUALIFIED_REWRITES = [
    ("@incr.HybridMemo::new(", "@incr.ReachableDerived("),
    ("@incr.MemoMap::new(", "@incr.DerivedMap("),
    ("@incr.Memo::new(", "@incr.Derived("),
    ("@incr.HybridMemo(", "@incr.ReachableDerived("),
    ("@incr.MemoMap(", "@incr.DerivedMap("),
    ("@incr.Memo(", "@incr.Derived("),
    ("@incr.HybridMemo[", "@incr.ReachableDerived["),
    ("@incr.MemoMap[", "@incr.DerivedMap["),
    ("@incr.Memo[", "@incr.Derived["),
]

UNQUALIFIED_REWRITES = [
    (r"(?<![A-Za-z0-9_.])HybridMemo::new\(", "ReachableDerived("),
    (r"(?<![A-Za-z0-9_.])MemoMap::new\(", "DerivedMap("),
    (r"(?<![A-Za-z0-9_.])Memo::new\(", "Derived("),
    (r"(?<![A-Za-z0-9_.])HybridMemo\(", "ReachableDerived("),
    (r"(?<![A-Za-z0-9_.])MemoMap\(", "DerivedMap("),
    (r"(?<![A-Za-z0-9_.])Memo\(", "Derived("),
    (r"(?<![A-Za-z0-9_.])HybridMemo\[", "ReachableDerived["),
    (r"(?<![A-Za-z0-9_.])MemoMap\[", "DerivedMap["),
    (r"(?<![A-Za-z0-9_.])Memo\[", "Derived["),
]

MAP_METHOD_REWRITES = [
    ("get_tracked", "get_or_abort"),
    ("get_or_else", "read_or_else"),
    ("get_or", "read_or"),
    ("contains", "has_cached"),
    ("length", "cache_len"),
    ("sweep", "sweep_cache"),
    ("clear", "clear_cache"),
]

MEMO_MANUAL_METHODS = {
    "get_or": "legacy Memo::get_or: migrate manually with match Derived::read() fallback",
    "get_or_else": "legacy Memo::get_or_else: migrate manually with match Derived::read() fallback",
    "is_up_to_date": "legacy Memo::is_up_to_date: use Derived::is_fresh after migrating the handle",
    "dependencies": "compatibility-only Memo diagnostics: keep Memo or design a separate introspection path",
    "verified_at": "compatibility-only Memo diagnostics: keep Memo or design a separate introspection path",
    "on_change": "compatibility-only Memo callback: keep Memo or design a target callback path",
    "clear_on_change": "compatibility-only Memo callback: keep Memo or design a target callback path",
    "dispose": "compatibility-only Memo disposal call: keep Memo or redesign ownership around Scope/Watch",
    "accumulated_result": "compatibility-only Memo accumulator Result read: keep Memo or migrate manually",
}

HYBRID_MANUAL_METHODS = {
    "is_up_to_date": "legacy HybridMemo::is_up_to_date: use ReachableDerived::is_fresh after migrating the handle",
    "observe": "legacy HybridMemo::observe: use ReachableDerived::watch after migrating the handle",
    "id": "compatibility-only HybridMemo::id: keep HybridMemo or design a separate introspection path",
    "dispose": "compatibility-only HybridMemo::dispose: keep HybridMemo or redesign ownership around Scope/Watch",
    "is_disposed": "compatibility-only HybridMemo::is_disposed: keep HybridMemo or design a separate lifecycle path",
}


@dataclass
class Finding:
    path: Path
    line_no: int
    message: str
    line: str


@dataclass
class FileResult:
    path: Path
    safe_rewrites: int
    findings: list[Finding]
    new_text: str
    old_text: str


def is_excluded(path: Path) -> bool:
    parts = path.parts
    for excluded in EXCLUDED_DIRS:
        excluded_parts = tuple(excluded.split("/"))
        if any(parts[i : i + len(excluded_parts)] == excluded_parts for i in range(len(parts))):
            return True
    return False


def is_candidate(path: Path, include_md: bool) -> bool:
    name = path.name
    if name.endswith(".mbti"):
        return False
    return name.endswith(".mbt") or name.endswith(".mbt.md") or (include_md and name.endswith(".md"))


def iter_files(paths: list[Path], include_md: bool) -> Iterable[Path]:
    for root in paths:
        if root.is_file():
            if is_candidate(root, include_md) and not is_excluded(root):
                yield root
            continue
        for path in root.rglob("*"):
            if path.is_file() and is_candidate(path, include_md) and not is_excluded(path):
                yield path


def collect_vars(text: str, type_names: tuple[str, ...], qualified_only: bool = False) -> set[str]:
    names = "|".join(type_names)
    prefix = r"@incr\." if qualified_only else r"(?:@incr\.)?"
    vars_: set[str] = set()
    patterns = [
        rf"\b(?:let|var)\s+({IDENT})\s*:\s*{prefix}(?:{names})\b",
        rf"(?<!::)\b({IDENT})\s*:\s*{prefix}(?:{names})\b",
        rf"\b(?:let|var)\s+({IDENT})\s*=\s*{prefix}(?:{names})(?:::new)?\s*\(",
    ]
    for pattern in patterns:
        for match in re.finditer(pattern, text):
            name = match.group(1)
            if name != "self":
                vars_.add(name)
    return vars_


def apply_literal_rewrites(text: str, rewrites: list[tuple[str, str]]) -> tuple[str, int]:
    count = 0
    for old, new in rewrites:
        hits = text.count(old)
        if hits:
            text = text.replace(old, new)
            count += hits
    return text, count


def apply_regex_rewrites(text: str, rewrites: list[tuple[str, str]]) -> tuple[str, int]:
    count = 0
    for pattern, replacement in rewrites:
        text, hits = re.subn(pattern, replacement, text)
        count += hits
    return text, count


def apply_map_method_rewrites(text: str, map_vars: set[str]) -> tuple[str, int]:
    total = 0
    for var in sorted(map_vars, key=len, reverse=True):
        escaped = re.escape(var)
        for old, new in MAP_METHOD_REWRITES:
            if old in {"length", "sweep", "clear"}:
                pattern = rf"(?<![A-Za-z0-9_])({escaped})\.{old}\s*\(\s*\)"
                repl = rf"\1.{new}()"
            else:
                pattern = rf"(?<![A-Za-z0-9_])({escaped})\.{old}\s*\("
                repl = rf"\1.{new}("
            text, hits = re.subn(pattern, repl, text)
            total += hits
    return text, total


def add_finding(findings: list[Finding], path: Path, line_no: int, message: str, line: str) -> None:
    findings.append(Finding(path=path, line_no=line_no, message=message, line=line.rstrip()))


def add_method_findings(
    findings: list[Finding],
    path: Path,
    line_no: int,
    line: str,
    var: str,
    methods: dict[str, str],
) -> None:
    escaped = re.escape(var)
    for method, message in methods.items():
        if re.search(rf"(?<![A-Za-z0-9_]){escaped}\.{method}\s*\(", line):
            add_finding(findings, path, line_no, message, line)


def collect_findings(path: Path, text: str, memo_vars: set[str], hybrid_vars: set[str], map_vars: set[str]) -> list[Finding]:
    findings: list[Finding] = []
    memo_like = memo_vars | hybrid_vars
    old_handle_vars = memo_vars | hybrid_vars | map_vars
    for line_no, line in enumerate(text.splitlines(), start=1):
        for var in sorted(memo_like | map_vars):
            escaped = re.escape(var)
            if re.search(rf"(?<![A-Za-z0-9_]){escaped}\.get_result\s*\(", line):
                if var in map_vars:
                    msg = "context-sensitive MemoMap::get_result: use DerivedMap::get inside tracked computes, DerivedMap::read outside"
                else:
                    msg = "context-sensitive Memo::get_result: use Derived::get inside tracked computes, Derived::read outside"
                add_finding(findings, path, line_no, msg, line)
            if re.search(rf"(?<![A-Za-z0-9_]){escaped}\.get\s*\(", line):
                if var in hybrid_vars:
                    msg = "legacy HybridMemo::get: migrate the handle to ReachableDerived and choose get_or_abort/read_or_abort by context"
                elif var in memo_vars:
                    msg = "legacy Memo::get: migrate the handle to Derived and use get_or_abort inside tracked computes"
                elif var in map_vars:
                    msg = "legacy MemoMap::get: migrate the handle to DerivedMap and use read_or_abort for current permissive aborting semantics"
                else:
                    msg = "legacy get on compatibility handle"
                add_finding(findings, path, line_no, msg, line)
        for var in sorted(memo_vars):
            add_method_findings(findings, path, line_no, line, var, MEMO_MANUAL_METHODS)
        for var in sorted(hybrid_vars):
            add_method_findings(findings, path, line_no, line, var, HYBRID_MANUAL_METHODS)
        if re.search(r"\bread_hybrid\s*\(", line):
            add_finding(findings, path, line_no, "legacy Runtime::read_hybrid: migrate argument to ReachableDerived::read/read_or_abort", line)
        if re.search(r"\bread_reactive\s*\(", line):
            add_finding(findings, path, line_no, "legacy Runtime::read_reactive: migrate argument to EagerDerived::read", line)
        for var in sorted(old_handle_vars):
            escaped = re.escape(var)
            if re.search(rf"\.read\s*\(\s*{escaped}\b", line):
                add_finding(findings, path, line_no, "possible Runtime::read compatibility call: migrate argument handle to target facade read/watch", line)
            if re.search(rf"(?<![A-Za-z0-9_]){escaped}\.(?:accumulated|dependencies|changed_at|verified_at)\s*\(", line):
                add_finding(findings, path, line_no, "compatibility-only API: keep Memo or design a separate introspection/diagnostic path", line)
    return findings


def process_file(path: Path, include_unqualified: bool) -> FileResult:
    old_text = path.read_text()
    memo_vars = collect_vars(old_text, ("Memo",))
    hybrid_vars = collect_vars(old_text, ("HybridMemo",))
    map_vars = collect_vars(old_text, ("MemoMap",))
    rewritable_map_vars = collect_vars(
        old_text,
        ("MemoMap",),
        qualified_only=not include_unqualified,
    )

    new_text, safe_rewrites = apply_literal_rewrites(old_text, QUALIFIED_REWRITES)
    if include_unqualified:
        new_text, hits = apply_regex_rewrites(new_text, UNQUALIFIED_REWRITES)
        safe_rewrites += hits
    new_text, hits = apply_map_method_rewrites(new_text, rewritable_map_vars)
    safe_rewrites += hits

    findings = collect_findings(path, old_text, memo_vars, hybrid_vars, map_vars)
    return FileResult(path=path, safe_rewrites=safe_rewrites, findings=findings, new_text=new_text, old_text=old_text)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Migrate incr compatibility handles to target facades conservatively.",
    )
    parser.add_argument("paths", nargs="*", default=["."], help="files or directories to scan")
    parser.add_argument("--apply", action="store_true", help="write safe rewrites; report-only findings remain manual")
    parser.add_argument(
        "--unqualified",
        action="store_true",
        help="also rewrite unqualified Memo/HybridMemo/MemoMap constructors and type names",
    )
    parser.add_argument("--include-md", action="store_true", help="also scan prose Markdown files; default is MoonBit sources and .mbt.md examples")
    parser.add_argument("--max-reports", type=int, default=200, help="maximum report-only findings to print")
    args = parser.parse_args(argv)

    roots = [Path(p) for p in args.paths]
    results = [process_file(path, args.unqualified) for path in iter_files(roots, args.include_md)]
    changed = [r for r in results if r.new_text != r.old_text]
    findings = [finding for result in results for finding in result.findings]

    updated_count = 0
    skipped_count = 0
    if args.apply:
        for result in changed:
            if result.findings:
                skipped_count += 1
                print(
                    f"skipped {result.path} ({result.safe_rewrites} safe rewrites; "
                    f"{len(result.findings)} manual sites)"
                )
            else:
                result.path.write_text(result.new_text)
                updated_count += 1
                print(f"updated {result.path} ({result.safe_rewrites} safe rewrites)")
    else:
        for result in changed:
            print(f"would update {result.path} ({result.safe_rewrites} safe rewrites)")

    if findings:
        print("\nmanual review required:")
        for finding in findings[: args.max_reports]:
            print(f"{finding.path}:{finding.line_no}: {finding.message}")
            print(f"  {finding.line}")
        if len(findings) > args.max_reports:
            print(f"... truncated {len(findings) - args.max_reports} additional findings")

    print(
        f"\nscanned {len(results)} files; "
        f"{'updated ' + str(updated_count) + ' files; skipped ' + str(skipped_count) if args.apply else 'would update ' + str(len(changed)) + ' files'}; "
        f"reported {len(findings)} manual sites"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
