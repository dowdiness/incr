# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Salsa-inspired incremental recomputation library written in MoonBit. Provides automatic dependency tracking, memoization with backdating, and durability-based verification skipping.

## Commands

```bash
moon check          # Type-check without building
moon build          # Build the library
moon test           # Run all 34 tests
moon test -p dowdiness/incr -f memo_test.mbt           # Run tests in a specific file
moon test -p dowdiness/incr -f memo_test.mbt -i 0      # Run a single test by index
```

## Architecture

This is a single-package MoonBit library (`dowdiness/incr`). All source files are in the root directory.

### Core Computation Model

The library implements Salsa's incremental computation pattern with three key types:

- **Signal[T]** (`signal.mbt`) — Input cells with externally-set values. Support same-value optimization (skip revision bump if value unchanged) and durability levels (Low/Medium/High).
- **Memo[T]** (`memo.mbt`) — Derived computations that lazily evaluate and cache results. Automatically track dependencies via the runtime's tracking stack. Implement **backdating**: when a recomputed value equals the previous value, `changed_at` is preserved, preventing unnecessary downstream recomputation.
- **Runtime** (`runtime.mbt`) — Central state: global revision counter, cell metadata HashMap, dependency tracking stack, and per-durability revision tracking.

### Dependency Graph Internals

- **CellMeta** (`cell.mbt`) — Type-erased metadata for each cell. Stores `changed_at`/`verified_at` revisions, dependency list, durability, and a type-erased `recompute_and_check` closure for derived cells. The `in_progress` flag provides cycle detection.
- **ActiveQuery** (`tracking.mbt`) — Frame pushed onto `Runtime.tracking_stack` during memo computation. Collects dependencies (with deduplication) read via `Signal::get` or `Memo::get`.
- **Revision** / **Durability** (`revision.mbt`) — Monotonic revision counter bumped on input changes. Durability classifies input change frequency; derived cells inherit the minimum durability of their dependencies.
- **Verification** (`verify.mbt`) — `maybe_changed_after()` is the core algorithm. For derived cells: checks the durability shortcut first, then walks dependencies recursively. If any dependency changed, recomputes the cell (enabling backdating). Green path (no change) marks `verified_at` without recomputation.

### Data Flow

1. `Signal::set()` bumps the global revision and records `changed_at` on the signal's CellMeta
2. `Memo::get()` checks `verified_at` against current revision; if stale, calls `maybe_changed_after()`
3. `maybe_changed_after()` recursively verifies dependencies, recomputing only cells whose inputs actually changed
4. Backdating: if a Memo recomputes to the same value, `changed_at` stays old, so downstream cells skip recomputation
5. Durability shortcut: if no input of a cell's durability level changed, verification is skipped entirely

### MoonBit Conventions

- Tests use `///|` doc-comment prefix followed by `test "name" { ... }` blocks
- Assertions use `inspect(expr, content="expected")` pattern
- The library imports `moonbitlang/core/hashmap` as its only external dependency

## Planning Documents

- **ROADMAP.md** — Phased future direction (error handling, performance, advanced features, ecosystem)
- **TODO.md** — Concrete actionable tasks with checkboxes
