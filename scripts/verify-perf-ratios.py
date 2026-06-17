#!/usr/bin/env python3
"""Verify and optionally regenerate the shared-vs-independent ratio table.

This script is intentionally narrow: it checks the 16-root comparison table in
``docs/performance/2026-06-16-incr-tea-shared-vs-independent-inactive-root-cohorts.md``
against the two source snapshots it cites. It is not a general Markdown table
library.
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

DEFAULT_SHARED = Path("docs/performance/2026-06-15-incr-tea-inactive-root-cohorts.md")
DEFAULT_INDEPENDENT = Path(
    "docs/performance/2026-06-16-incr-tea-independent-inactive-root-cohorts.md"
)
DEFAULT_SYNTHESIS = Path(
    "docs/performance/2026-06-16-incr-tea-shared-vs-independent-inactive-root-cohorts.md"
)

MEASUREMENT_TABLE_KEYWORDS = ("burst", "activation", "timing", "roots", "incr_tea")
SYNTHESIS_TABLE_KEYWORDS = ("timing", "activation", "updates", "independent / shared")
SYNTHESIS_ROOTS = "16"

NUMBER_RE = re.compile(r"[-+]?\d+(?:\.\d+)?")
RATIO_RE = re.compile(r"([-+]?\d+(?:\.\d+)?)\s*×")
PERCENT_RE = re.compile(r"^\s*([-+]?\d+(?:\.\d+)?)\s*%\s*$")
SEPARATOR_CELL_RE = re.compile(r"^:?-{3,}:?$")

UNIT_FACTORS_NS = {
    "ns": 1.0,
    "µs": 1_000.0,
    "us": 1_000.0,
    "μs": 1_000.0,
    "ms": 1_000_000.0,
    "s": 1_000_000_000.0,
}

RatioKey = tuple[str, str, str, str]


@dataclass(frozen=True)
class Table:
    headers: list[str]
    rows: list[list[str]]
    start_line: int
    end_line: int


@dataclass(frozen=True)
class MeasurementRow:
    value: float
    raw_value: str


@dataclass(frozen=True)
class MeasurementColumns:
    burst: int
    activation: int
    timing: int
    roots: int
    value: int


@dataclass(frozen=True)
class SynthesisColumns:
    timing: int
    activation: int
    updates: int
    shared_value: int
    independent_value: int
    ratio: int


@dataclass(frozen=True)
class SourceRows:
    shared: MeasurementRow
    independent: MeasurementRow


def split_pipe_row(line: str) -> list[str]:
    stripped = line.strip()
    if stripped.startswith("|"):
        stripped = stripped[1:]
    if stripped.endswith("|"):
        stripped = stripped[:-1]
    return [cell.strip() for cell in stripped.split("|")]


def is_pipe_row(line: str) -> bool:
    stripped = line.strip()
    return stripped.startswith("|") and stripped.endswith("|")


def is_separator_row(cells: Iterable[str]) -> bool:
    normalized = [cell.replace(" ", "") for cell in cells]
    return bool(normalized) and all(SEPARATOR_CELL_RE.match(cell) for cell in normalized)


def parse_table_block(lines: list[str], start_line: int, end_line: int) -> Table | None:
    parsed_rows = [split_pipe_row(line) for line in lines]
    content_rows = [row for row in parsed_rows if not is_separator_row(row)]
    if not content_rows:
        return None
    return Table(headers=content_rows[0], rows=content_rows[1:], start_line=start_line, end_line=end_line)


def parse_markdown_tables(text: str) -> list[Table]:
    tables: list[Table] = []
    block: list[str] = []
    block_start = 0
    lines = text.splitlines()

    for index, line in enumerate(lines, start=1):
        if is_pipe_row(line):
            if not block:
                block_start = index
            block.append(line)
            continue
        if block:
            append_table(tables, block, block_start, index - 1)
            block = []

    if block:
        append_table(tables, block, block_start, len(lines))
    return tables


def append_table(tables: list[Table], block: list[str], start_line: int, end_line: int) -> None:
    table = parse_table_block(block, start_line, end_line)
    if table is not None:
        tables.append(table)


def clean_numeric_text(cell: str) -> str:
    text = cell.strip().replace("−", "-")
    while len(text) >= 2 and text[0] in "*_`" and text[-1] == text[0]:
        text = text[1:-1].strip()
    return text


def extract_numeric(cell: str) -> float | None:
    text = clean_numeric_text(cell)
    if not text:
        return None

    ratio_match = RATIO_RE.search(text)
    if ratio_match:
        return float(ratio_match.group(1))

    percent_match = PERCENT_RE.match(text)
    if percent_match:
        return float(percent_match.group(1))

    match = NUMBER_RE.search(text)
    if not match:
        return None

    value = float(match.group(0))
    suffix = text[match.end() :]
    unit_match = re.search(r"\b(ns|us|µs|μs|ms|s)\b", suffix)
    unit = unit_match.group(1) if unit_match else "µs"
    return value * UNIT_FACTORS_NS[unit]


def normalized_headers(table: Table) -> list[str]:
    return [header.strip().lower() for header in table.headers]


def find_table_by_headers(tables: list[Table], keywords: Iterable[str]) -> Table | None:
    lowered = [keyword.lower() for keyword in keywords]
    for table in tables:
        haystack = "\n".join(normalized_headers(table))
        if all(keyword in haystack for keyword in lowered):
            return table
    return None


def require_table(tables: list[Table], keywords: Iterable[str], path: Path, label: str) -> Table:
    table = find_table_by_headers(tables, keywords)
    if table is None:
        raise ValueError(f"could not find {label} table in {path}")
    return table


def column_index(table: Table, name: str) -> int:
    wanted = name.strip().lower()
    for index, header in enumerate(table.headers):
        if header.strip().lower() == wanted:
            return index
    raise ValueError(f"missing column {name!r} in table headers {table.headers!r}")


def require_cell(row: list[str], index: int, header: str) -> str:
    if index >= len(row):
        raise ValueError(f"row {row!r} is missing column {header!r}")
    return row[index]


def measurement_columns(table: Table) -> MeasurementColumns:
    return MeasurementColumns(
        burst=column_index(table, "burst"),
        activation=column_index(table, "activation"),
        timing=column_index(table, "timing"),
        roots=column_index(table, "roots"),
        value=column_index(table, "`incr_tea`"),
    )


def synthesis_columns(table: Table) -> SynthesisColumns:
    return SynthesisColumns(
        timing=column_index(table, "timing"),
        activation=column_index(table, "activation"),
        updates=column_index(table, "updates"),
        shared_value=column_index(table, "shared (#277)"),
        independent_value=column_index(table, "independent (#278)"),
        ratio=column_index(table, "independent / shared"),
    )


def parse_measurements(table: Table, label: str) -> dict[RatioKey, MeasurementRow]:
    columns = measurement_columns(table)
    measurements: dict[RatioKey, MeasurementRow] = {}

    for row in table.rows:
        burst = require_cell(row, columns.burst, "burst")
        activation = require_cell(row, columns.activation, "activation")
        timing = require_cell(row, columns.timing, "timing")
        roots = require_cell(row, columns.roots, "roots")
        raw_value = require_cell(row, columns.value, "`incr_tea`")
        value = extract_numeric(raw_value)
        if value is None:
            raise ValueError(f"{label}: could not parse measurement value {raw_value!r}")
        measurements[(timing, activation, update_count_from_burst(burst), roots)] = MeasurementRow(
            value=value,
            raw_value=raw_value,
        )
    return measurements


def update_count_from_burst(burst: str) -> str:
    match = NUMBER_RE.search(burst)
    if not match:
        raise ValueError(f"could not parse update count from burst cell {burst!r}")
    return match.group(0)


def synthesis_key(row: list[str], columns: SynthesisColumns) -> RatioKey:
    return (
        require_cell(row, columns.timing, "timing"),
        require_cell(row, columns.activation, "activation"),
        require_cell(row, columns.updates, "updates"),
        SYNTHESIS_ROOTS,
    )


def compute_ratio(shared_ns: float, independent_ns: float) -> float:
    if shared_ns == 0:
        raise ValueError("cannot compute ratio with zero shared measurement")
    return independent_ns / shared_ns


def round_ratio(value: float, mode: str) -> float:
    scaled = value * 100.0
    if mode == "up":
        return math.ceil(scaled) / 100.0
    if mode == "down":
        return math.floor(scaled) / 100.0
    return round(value, 2)


def ratio_text(value: float, original: str, mode: str) -> str:
    formatted = f"{round_ratio(value, mode):.2f}×"
    lowered = original.lower()
    if "faster" in lowered:
        return f"{formatted} faster"
    if "slower" in lowered:
        return f"{formatted} slower"
    return formatted


def table_row_line(row: list[str]) -> str:
    return "| " + " | ".join(row) + " |"


def load_tables(args: argparse.Namespace) -> tuple[str, Table, Table, Table]:
    shared_text = args.shared.read_text()
    independent_text = args.independent.read_text()
    synthesis_text = args.synthesis.read_text()

    shared_table = require_table(
        parse_markdown_tables(shared_text), MEASUREMENT_TABLE_KEYWORDS, args.shared, "measurement"
    )
    independent_table = require_table(
        parse_markdown_tables(independent_text),
        MEASUREMENT_TABLE_KEYWORDS,
        args.independent,
        "measurement",
    )
    synthesis_table = require_table(
        parse_markdown_tables(synthesis_text),
        SYNTHESIS_TABLE_KEYWORDS,
        args.synthesis,
        "synthesis ratio",
    )
    return synthesis_text, shared_table, independent_table, synthesis_table


def require_sources(
    key: RatioKey,
    shared: dict[RatioKey, MeasurementRow],
    independent: dict[RatioKey, MeasurementRow],
    failures: list[str],
) -> SourceRows | None:
    shared_row = shared.get(key)
    independent_row = independent.get(key)
    if shared_row is None:
        failures.append(f"missing shared source row for {key}")
    if independent_row is None:
        failures.append(f"missing independent source row for {key}")
    if shared_row is None or independent_row is None:
        return None
    return SourceRows(shared=shared_row, independent=independent_row)


def append_value_drift(
    failures: list[str],
    label: str,
    key: RatioKey,
    displayed_cell: str,
    source: MeasurementRow,
) -> None:
    if displayed_cell == source.raw_value:
        return
    failures.append(
        f"{label} value drift for {key}: synthesis {displayed_cell!r}, "
        f"source {source.raw_value!r}"
    )


def verify_row(
    row: list[str],
    key: RatioKey,
    sources: SourceRows,
    columns: SynthesisColumns,
    tolerance: float,
    failures: list[str],
) -> None:
    ratio_cell = require_cell(row, columns.ratio, "independent / shared")
    actual = extract_numeric(ratio_cell)
    if actual is None:
        failures.append(f"could not parse ratio cell {ratio_cell!r} for {key}")
        return

    append_value_drift(
        failures,
        "shared",
        key,
        require_cell(row, columns.shared_value, "shared (#277)"),
        sources.shared,
    )
    append_value_drift(
        failures,
        "independent",
        key,
        require_cell(row, columns.independent_value, "independent (#278)"),
        sources.independent,
    )

    expected = compute_ratio(sources.shared.value, sources.independent.value)
    if abs(expected - actual) > tolerance:
        failures.append(
            f"ratio mismatch for {key}: expected {expected:.4f}× "
            f"({sources.independent.raw_value} / {sources.shared.raw_value}), found {ratio_cell!r}"
        )


def apply_row(
    row: list[str],
    sources: SourceRows,
    columns: SynthesisColumns,
    round_mode: str,
    tolerance: float,
) -> tuple[list[str], bool]:
    new_row = list(row)
    ratio_cell = require_cell(row, columns.ratio, "independent / shared")
    ratio = compute_ratio(sources.shared.value, sources.independent.value)
    actual = extract_numeric(ratio_cell)
    replacements = {
        columns.shared_value: sources.shared.raw_value,
        columns.independent_value: sources.independent.raw_value,
    }
    if actual is None or abs(ratio - actual) > tolerance:
        replacements[columns.ratio] = ratio_text(ratio, ratio_cell, round_mode)

    changed = False
    for index, value in replacements.items():
        if new_row[index] != value:
            new_row[index] = value
            changed = True
    return new_row, changed


def replacement_table_lines(table: Table, rows: list[list[str]]) -> list[str]:
    separator = ["---"] * len(table.headers)
    return [table_row_line(table.headers), table_row_line(separator)] + [table_row_line(row) for row in rows]


def replace_table(text: str, table: Table, rows: list[list[str]]) -> str:
    lines = text.splitlines()
    new_text = "\n".join(
        lines[: table.start_line - 1] + replacement_table_lines(table, rows) + lines[table.end_line :]
    )
    if text.endswith("\n"):
        new_text += "\n"
    return new_text


def verify_or_apply(args: argparse.Namespace) -> int:
    synthesis_text, shared_table, independent_table, synthesis_table = load_tables(args)
    shared = parse_measurements(shared_table, "shared")
    independent = parse_measurements(independent_table, "independent")
    columns = synthesis_columns(synthesis_table)

    failures: list[str] = []
    changed = False
    new_rows: list[list[str]] = []

    for row in synthesis_table.rows:
        key = synthesis_key(row, columns)
        sources = require_sources(key, shared, independent, failures)
        if sources is None:
            new_rows.append(list(row))
            continue

        if args.apply:
            new_row, row_changed = apply_row(row, sources, columns, args.round_mode, args.tolerance)
            new_rows.append(new_row)
            changed = changed or row_changed
        else:
            verify_row(row, key, sources, columns, args.tolerance, failures)
            new_rows.append(list(row))

    if args.apply:
        if changed:
            args.synthesis.write_text(replace_table(synthesis_text, synthesis_table, new_rows))
            print(f"updated {args.synthesis}")
        else:
            print(f"{args.synthesis}: ratio table already up to date")

    if failures:
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        return 1

    print(f"verified {len(synthesis_table.rows)} ratio rows in {args.synthesis}")
    return 0


def dump_tables(paths: Iterable[Path]) -> int:
    for path in paths:
        print(f"== {path} ==")
        for table_index, table in enumerate(parse_markdown_tables(path.read_text()), start=1):
            print(f"table {table_index} (lines {table.start_line}-{table.end_line})")
            print(f"  headers: {table.headers!r}")
            for row in table.rows:
                print(f"  row: {row!r}")
                for cell in row:
                    print(f"    {cell!r} -> {extract_numeric(cell)!r}")
        print()
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shared", type=Path, default=DEFAULT_SHARED)
    parser.add_argument("--independent", type=Path, default=DEFAULT_INDEPENDENT)
    parser.add_argument("--synthesis", type=Path, default=DEFAULT_SYNTHESIS)
    parser.add_argument("--tolerance", type=float, default=0.01)
    parser.add_argument("--verify", action="store_true", help="verify ratios (default)")
    parser.add_argument("--apply", action="store_true", help="rewrite stale ratio cells in the synthesis doc")
    parser.add_argument("--dump-tables", action="store_true", help="print parsed tables and numeric values")
    parser.add_argument(
        "--round",
        dest="round_mode",
        choices=("nearest", "up", "down"),
        default="nearest",
        help="rounding mode for regenerated ratio cells",
    )
    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.dump_tables:
            return dump_tables([args.shared, args.independent, args.synthesis])
        return verify_or_apply(args)
    except OSError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
