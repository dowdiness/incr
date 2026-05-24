# Repository Guidelines

This file is the canonical entry point for human contributors and coding agents working in `dowdiness/incr`. Read this before making changes.

## Project Overview

`incr` is a Salsa-inspired incremental recomputation library in MoonBit. The codebase has roughly five public packages and five `internal/` engine sub-packages under `cells/`. See [`docs/architecture.md`](docs/architecture.md) for the package map and [`docs/design/internals.md`](docs/design/internals.md) for the verification algorithm.

Users care about: `Signal`, `Memo`, `MemoMap`, `HybridMemo`, `TrackedCell`, `Reactive`, `Effect`, `Relation`, `Accumulator`, `Scope`, plus the `Database` / `Readable` / `Trackable` traits. Anything under `cells/internal/` is implementation detail and the compiler enforces that visibility.

## Project Structure & Module Organization

```
incr.mbt, traits.mbt        ← Root facade (re-exports + `create_*` helpers)
types/                      ← Pure value types
cells/                      ← Engine: handles, lifecycles, the Runtime coordinator
cells/internal/             ← shared, pull, push, datalog, kernel (compiler-enforced)
pipeline/                   ← Experimental, single 52-LOC file
tests/                      ← Integration tests against the public API
docs/                       ← Index in docs/README.md
scripts/                    ← check-engine-isolation.sh enforces internal-package invariants
```

Tests inside `cells/` live beside source:
- Black-box: `*_test.mbt` (cannot construct private fields)
- White-box: `*_wbtest.mbt` (same package — can reach `priv` state)

Generated `pkg.generated.mbti` files are **not edited by hand** — `moon info` regenerates them.

## Build, Test, and Development Commands

```bash
moon check          # Type-check; fast; run after every edit
moon build          # Compile
moon test           # Full test suite (~650 test blocks)
moon bench --release  # Microbenchmarks — only meaningful with --release
moon fmt            # Apply standard formatting
moon info           # Regenerate all pkg.generated.mbti files
```

Targeted runs:
```bash
moon test cells/derived_test.mbt                            # one file
moon test cells/derived_test.mbt -i 0                       # one test by index
moon test tests                                             # integration tests only
```

There is no CI in this submodule directory. CI runs from the parent `canopy` repo.

## Coding Style & Naming

- 2-space indentation; `moon fmt` enforces the rest.
- Types and traits: `PascalCase`. Methods: `Type::method`. Variables/fields/tests: `snake_case`. Top-level constants: `SCREAMING_SNAKE_CASE`.
- MoonBit doc comments use `///` prefix on each line. Use them on every `pub` item in non-test files.
- Group declarations logically inside a file. File names are organizational; the package boundary is what matters.

For idiomatic MoonBit patterns (constructors, guard, list comprehensions, deprecated-syntax table) see `~/.claude/moonbit-base.md` in the global guidance.

## Documentation Rules

Where things go:

| Content | Location |
|---|---|
| Quick pitch, install, minimal example, dev commands | `README.md` |
| Tutorial / first computation | `docs/getting-started.md` |
| Conceptual model (signals, durability, backdating, …) | `docs/concepts.md` |
| Patterns and anti-patterns | `docs/cookbook.md` |
| Public-API listing | `docs/api-reference.md` |
| Architecture map, data flow, invariants | `docs/architecture.md` |
| Verification algorithm, SoA layout, type erasure | `docs/design/internals.md` |
| Significant decisions | `docs/decisions/` (ADRs) |
| Implementation specs | `docs/design/specs/` |
| Plans for upcoming work | `docs/plans/` (archived to `docs/archive/` on completion) |
| Dated performance snapshots | `docs/performance/` |
| Exploratory ideas not implemented | `docs/research/` |

Three operating rules:

1. **Code is the source of truth.** When a doc and the code disagree, the doc is wrong. Fix the doc or delete it.
2. **Don't restate code in prose.** If the `.mbti` already documents a signature, don't paraphrase it in the same words in the API reference. Document *behavior*, *invariants*, *failure modes*, and *examples* — not types.
3. **Mark uncertainty.** If a claim cannot be verified from the repo, prefer deleting it or marking it "unverified" over guessing.

When you add or move a doc file under `docs/`, update `docs/README.md` in the same commit. The index is the entry point.

## Comment Rules

Default: write no comment. Only add one when the *why* would not be obvious to a reader of the code alone — a hidden invariant, a workaround for a bug, an interaction effect, a performance constraint. Comments that restate the code are a maintenance burden; delete them on sight.

Never:
- Re-narrate the diff in a comment ("added X for the Y flow", "TODO: remove later"). Use the PR description.
- Describe a function in a comment when a doc comment would do.
- Leave hedge words: "for now", "temporarily", "provisional". Decide or don't write it.

For public APIs, prefer `///` doc comments with a short behavior summary, optional `# Example` block (mark `nocheck` if it cannot stand alone), and a note about errors/aborts when relevant.

## How to verify documentation examples

`moon check` only verifies blocks tagged ` ```mbt check`. Untagged ` ```moonbit` blocks (which is most of the docs) are not checked by the toolchain — they can drift silently and have.

When adding a new example you want the toolchain to catch:
- Put it in a `.mbt.md` file (literate test), or
- Use a ` ```mbt check` block inside a doc comment.

Integration tests in `tests/*_test.mbt` are the strongest correctness signal; prefer adding a test there for any non-trivial behavior you describe in prose.

## Files and outputs not to edit manually

- `pkg.generated.mbti` (all of them) — regenerated by `moon info`.
- `_build/` — build artifacts; in `.gitignore`.
- `docs/archive/**` — historical record. Edit only to fix broken links or archive new entries.

## Testing Guidelines

- Use `test "name" { ... }` blocks with descriptive names. Prefer snapshot-style assertions via `inspect(value, content="...")`.
- Add regression tests for every behavior change in the nearest matching `*_test.mbt`. Use `*_wbtest.mbt` only when private state must be reached.
- Panic-style tests: prefix the test name with `"panic "`; the runner expects `abort()`.
- No strict coverage gate; preserve or improve coverage in touched areas.

## Commit & PR Guidelines

History follows Conventional Commit prefixes (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, `test:`). Keep commits atomic. Each PR should include:

- Short problem/solution summary
- Commands run (at minimum: `moon check`, `moon test`)
- Updated docs and regenerated `pkg.generated.mbti` when public API changes
- ADR or spec link if the PR makes a non-obvious design decision

## Pre-PR Checklist

Run in this order; do not push until each passes:

1. `moon fmt` — formatting applied
2. `moon info` — `pkg.generated.mbti` regenerated; inspect the diff
3. `moon check` — zero errors; do not introduce *new categories* of deprecation warnings beyond those documented below
4. `moon test` — all tests pass
5. Update `docs/` and `docs/README.md` if the API or behavior changed; update `CHANGELOG.md` for user-visible changes
6. Verify no `pkg.generated.mbti` was edited by hand (file should match `moon info` output)
7. If you added a new doc file, ensure it appears in `docs/README.md`

### Known deprecation warnings (status)

The MoonBit v0.9.2 (2026-05-13) release introduced several deprecations. Status of the migration in this repository:

- **`@hashmap.new()` / `@hashset.new()` / `@priority_queue.new()` / `Ref::new(x)`.** Migrated to `HashMap([])` / `HashSet([])` / `PriorityQueue([])` / `Ref(x)`.
- **`Show`-on-container snapshots.** Migrated: test sites that pass `Option`, `Array`, `Map`, or other container values to `inspect` were switched to `debug_inspect` (which uses `Debug`, not the deprecated `Show` impl). Snapshots regenerated via `moon test --update`.
- **`gc_tracked(rt, t)`.** Marked `#deprecated` in `traits.mbt`; the function is a no-op. New code should call `add_tracked(scope, t)` instead.
- **`fn new(..)` inside `struct`.** MoonBit v0.9.2 deprecated declaring constructors inside the struct body in favour of a separated `fn Type::Type(...)` toplevel. Migrated everywhere — 10 library types (`Runtime`, `Signal`, `Memo`, `HybridMemo`, `MemoMap`, `TrackedCell`, `Relation`, `FunctionalRelation`, `ActiveQuery`, `BatchFrame`) keep both `Type::Type` and `Type::new` for source compatibility; 4 test-only types (`Point`, `Versioned`, `TestDb`, `CalcPipeline`) collapsed to a single `fn Type::Type(..)` with the body inline.

When you add a new test or example, **use the modern constructor form** (`Signal(rt, v)`, `HashMap([])`, `debug_inspect(...)` for container snapshots) so you don't add to the warning count.
