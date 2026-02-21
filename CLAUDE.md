# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Salsa-inspired incremental recomputation library written in MoonBit. Provides automatic dependency tracking, memoization with backdating, and durability-based verification skipping.

## Commands

```bash
moon check          # Type-check without building
moon build          # Build the library
moon test           # Run all 128 tests
moon test -p dowdiness/incr -f memo_test.mbt           # Run tests in a specific file
moon test -p dowdiness/incr -f memo_test.mbt -i 0      # Run a single test by index
```

## Architecture

This is a single-package MoonBit library (`dowdiness/incr`). All source files are in the root directory.

### Core Computation Model

The library implements Salsa's incremental computation pattern with three key types:

- **Signal[T]** (`signal.mbt`) — Input cells with externally-set values. Support same-value optimization (skip revision bump if value unchanged) and durability levels (Low/Medium/High).
- **Memo[T]** (`memo.mbt`) — Derived computations that lazily evaluate and cache results. Automatically track dependencies via the runtime's tracking stack. Implement **backdating**: when a recomputed value equals the previous value, `changed_at` is preserved, preventing unnecessary downstream recomputation.
- **Runtime** (`runtime.mbt`) — Central state: global revision counter, cell metadata array (indexed by CellId), dependency tracking stack, per-durability revision tracking, and batch state.

### Dependency Graph Internals

- **CellMeta** (`cell.mbt`) — Type-erased metadata for each cell. Stores `changed_at`/`verified_at` revisions, dependency list, durability, `recompute_and_check` closure (derived cells), and `commit_pending` closure (input cells during batch). The `in_progress` flag provides cycle detection.
- **ActiveQuery** (`tracking.mbt`) — Frame pushed onto `Runtime.tracking_stack` during memo computation. Collects dependencies (with HashSet-based O(1) deduplication) read via `Signal::get` or `Memo::get`.
- **Revision** / **Durability** (`revision.mbt`) — Monotonic revision counter bumped on input changes. Durability classifies input change frequency; derived cells inherit the minimum durability of their dependencies.
- **Verification** (`verify.mbt`) — `maybe_changed_after()` is the core algorithm. For derived cells: checks the durability shortcut first, then walks dependencies iteratively using an explicit stack of `VerifyFrame`s. If any dependency changed, recomputes the cell (enabling backdating). Green path (no change) marks `verified_at` without recomputation.

### Data Flow

1. `Signal::set()` bumps the global revision and records `changed_at` on the signal's CellMeta (or defers to batch if inside `Runtime::batch()`)
2. `Memo::get()` checks `verified_at` against current revision; if stale, calls `maybe_changed_after()`
3. `maybe_changed_after()` iteratively verifies dependencies using an explicit stack, recomputing only cells whose inputs actually changed
4. Backdating: if a Memo recomputes to the same value, `changed_at` stays old, so downstream cells skip recomputation
5. Durability shortcut: if no input of a cell's durability level changed, verification is skipped entirely
6. Batch mode: `Runtime::batch(fn)` groups multiple signal updates into a single revision with two-phase commit and revert detection

### MoonBit Conventions

- Tests use `///|` doc-comment prefix followed by `test "name" { ... }` blocks
- Assertions use `inspect(expr, content="expected")` pattern
- The library imports `moonbitlang/core/hashset` as its only external dependency

## Documentation Hierarchy

### For Users
- **README.md** — Entry point: features, quick start, documentation index
- **docs/getting-started.md** — Step-by-step tutorial for new users (shows both Runtime and IncrDb patterns)
- **docs/concepts.md** — Core concepts explained simply (Signals, Memos, Revisions, Durability)
- **docs/api-reference.md** — Complete reference for all public types and methods
- **docs/cookbook.md** — Common patterns and recipes
- **docs/api-design-guidelines.md** — Design philosophy, best practices, planned improvements

### For Contributors
- **docs/design.md** — Deep technical internals: verification algorithm, backdating, durability, type erasure
- **CLAUDE.md** (this file) — Contributor and AI guidance: commands, architecture map, conventions
- **docs/roadmap.md** — Phased future direction with detailed Phase 2 API improvements (introspection, callbacks, builders)
- **docs/todo.md** — Concrete actionable tasks with checkboxes organized by priority
- **docs/comparison-with-alien-signals.md** — Analysis of alien-signals vs Salsa-style computation
- **docs/api-design-guidelines.md** — API design principles, patterns, and anti-patterns
- **docs/api-updates.md** — Summary of recent API documentation changes

When contributing, read [docs/design.md](docs/design.md) to understand the conceptual model (pull-based verification, backdating, durability shortcuts) before modifying core algorithm files like `verify.mbt` or `memo.mbt`.
