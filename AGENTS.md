# Repository Guidelines

## Project Structure & Module Organization
This repository is organized into four MoonBit sub-packages under `dowdiness/incr`:

- **`types/`** — pure value types (`Revision`, `Durability`, `CellId`); zero dependencies
- **`cells/`** — all engine implementation + unit tests (`signal.mbt`, `memo.mbt`, `runtime.mbt`, `verify.mbt`, `tracked_cell.mbt`, `memo_map.mbt`, etc.)
- **`pipeline/`** — experimental pipeline traits (`Sourceable`, `Parseable`, etc.)
- **`tests/`** — integration tests exercising the full `@incr` public API
- **Root** (`moon.pkg`, `incr.mbt`, `traits.mbt`) — re-exports all public types via `pub type` transparent aliases; downstream users see a unified `@incr` API

Tests in `cells/` live beside source files:
- Black-box tests: `*_test.mbt`
- White-box/internal tests: `*_wbtest.mbt`

Documentation is under `docs/`. Generated public API summaries are tracked in `pkg.generated.mbti` (refresh when APIs change). Build artifacts are in `_build/` (`target` links there).

## Build, Test, and Development Commands
- `moon check` — fast type-check; run before committing.
- `moon build` — compile the package.
- `moon test` — run the full test suite.
- `moon test -p dowdiness/incr/cells -f memo_test.mbt` — run one test file.
- `moon test -p dowdiness/incr/cells -f memo_test.mbt -i 0` — run one test by index.
- `moon info` — regenerate `pkg.generated.mbti` and confirm public API deltas.
- `moon fmt` — apply standard formatting.

## Coding Style & Naming Conventions
Use 2-space indentation and keep files cohesive by responsibility. In MoonBit, file names are organizational only, so group related declarations logically. Follow existing naming:

- Types/traits: `PascalCase`
- Methods: `Type::method`
- Variables/fields/tests: `snake_case`

Use `///|` doc comments for public APIs and keep examples minimal and executable when possible.

## Testing Guidelines
Use MoonBit `test "..." { ... }` blocks with descriptive names like `"memo: cache hit on second read"`. Prefer snapshot-style assertions with `inspect(value, content="...")`. Add regression tests for every behavior change in the nearest matching `*_test.mbt`; use `*_wbtest.mbt` only when internal/private behavior must be exercised. No strict coverage gate is configured, but changes should preserve or improve coverage in touched areas.

## Commit & Pull Request Guidelines
Recent history follows Conventional Commit-style prefixes (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, `test:`). Keep commits focused and atomic. For PRs, include:

- A short problem/solution summary
- Linked issue(s), if applicable
- Commands run (`moon check`, `moon test`)
- Updated docs and `pkg.generated.mbti` when public API changes
